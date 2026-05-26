#!/usr/bin/env bash
#
# Build a flashable KODE OS image with pi-gen.
#
# Two variants:
#   ./build.sh                  → slim image (~1.2 GB compressed)
#                                  pulls Immich/Jellyfin/Pi-hole/etc.
#                                  at first-boot. Needs internet
#                                  during setup.
#   ./build.sh --with-apps      → bundled image (~3 GB compressed)
#                                  every supported app's Docker images
#                                  are pre-pulled. First-boot works
#                                  fully offline.
#
# Output lands in ./pi-gen-work/deploy/<IMG_NAME>.img.xz.
#
# Requirements:
#   - Linux host (Ubuntu 22.04+ or Debian 12+ ideal)
#   - Docker installed + your user in the docker group
#   - ~20 GB free disk (slim), ~30 GB (with-apps)
#   - 30–60 min runtime
#
# pi-gen is NOT a submodule — we clone it fresh per build at the tag
# pinned via PI_GEN_TAG below. That keeps this repo small and lets us
# bump pi-gen versions independently.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
# Always work out of /tmp regardless of where the repo lives. Pi-gen's
# build-docker.sh and the chroot internals resolve paths to their
# physical form (via pwd -P) at various points, so symlinks don't
# rescue a repo path that contains spaces — only living in a space-
# free dir does. /tmp is universally space-free + tmpfs-fast on most
# systems. We symlink the working dir back into the repo for
# convenience so `ls image-build/pi-gen-work` still works.
WORK_DIR="/tmp/kode-pi-gen-work"

# Pin pi-gen to a known-good Bookworm arm64 tag. Pi-gen tags by
# release date — bump this when you want a newer base Pi OS. Override
# with PI_GEN_TAG=… for ad-hoc tests.
PI_GEN_TAG="${PI_GEN_TAG:-2025-11-24-raspios-bookworm-arm64}"

# Parse flags.
WITH_APPS=0
DEBUG_SSH=0
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519.pub"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-apps) WITH_APPS=1; shift ;;
    --debug-ssh) DEBUG_SSH=1; shift ;;
    --ssh-key)   SSH_KEY_PATH="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^#\!.*//;s/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if (( WITH_APPS )); then
  export KODE_IMG_NAME="kode-os-v0.2.0-alpha-pi5-with-apps"
  export KODE_BUNDLE_APPS=1
else
  export KODE_IMG_NAME="kode-os-v0.2.0-alpha-pi5"
  export KODE_BUNDLE_APPS=0
fi

# Pi-gen demands a non-empty FIRST_USER_PASS unless you also enable
# the first-boot user-rename prompt — both of which we don't want.
# Generate a fresh random pass per build; install-in-chroot.sh then
# `passwd -l kode` to lock the account. The pass never touches disk
# in cleartext and dies with this process.
export KODE_FIRST_USER_PASS="$(openssl rand -hex 32)"

# --debug-ssh: enable sshd + bake the maintainer's pubkey so we can
# `ssh kode@pebble.local` to debug a broken first-boot. Account
# stays passwd -l locked → pubkey auth is the only path in. Default
# (no flag) ships SSH off + no key, matching the release-image
# security model.
if (( DEBUG_SSH )); then
  if [[ ! -f "$SSH_KEY_PATH" ]]; then
    echo "--debug-ssh needs a pubkey at $SSH_KEY_PATH (override with --ssh-key PATH)" >&2
    exit 1
  fi
  export KODE_ENABLE_SSH=1
  export KODE_SSH_PUBKEY="$(cat "$SSH_KEY_PATH")"
  export KODE_IMG_NAME="${KODE_IMG_NAME}-debug"
  echo "==> --debug-ssh: SSH enabled, baking pubkey from $SSH_KEY_PATH"
fi

# Pi-gen's build-docker.sh runs the build inside a docker container.
# Env vars exported here DON'T propagate into the container by default
# — `docker run -e VAR` (without value) is the way to pass through
# host env. PIGEN_DOCKER_OPTS gets injected into the docker run line.
# Without this the config file (sourced inside the container) sees
# every KODE_* variable as empty, so FIRST_USER_PASS silently uses
# its placeholder string and PUBKEY_SSH_FIRST_USER fails the empty
# check, killing the build.
export PIGEN_DOCKER_OPTS="-e KODE_IMG_NAME -e KODE_BUNDLE_APPS -e KODE_FIRST_USER_PASS -e KODE_ENABLE_SSH -e KODE_SSH_PUBKEY"

log() { echo "==> $*"; }

# Refuse to run as root — pi-gen's own build-docker.sh will sudo
# what it needs. Running THIS script as root creates root-owned
# artifacts in the repo, which is annoying to clean up.
if [[ $EUID -eq 0 ]]; then
  echo "Don't run build.sh as root — it'll sudo what it needs." >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || {
  echo "Docker isn't installed. Install it first: https://docs.docker.com/engine/install/" >&2
  exit 1
}

# (We used to guard against $SCRIPT_DIR having spaces, but now the
# whole build runs out of $WORK_DIR=/tmp/kode-pi-gen-work which is
# always space-free — so the repo can live anywhere.)

log "Building $KODE_IMG_NAME (bundle apps: $KODE_BUNDLE_APPS)"

# Clean prior build. pi-gen owns root-owned files inside WORK_DIR
# from a previous run, so sudo is needed even though THIS script
# isn't root.
if [[ -d "$WORK_DIR" ]]; then
  log "Cleaning previous build at $WORK_DIR"
  sudo rm -rf "$WORK_DIR"
fi

# Also nuke any stale pigen_work docker container from a previous
# failed run. Pi-gen refuses to start a new build if its container
# is already around (it doesn't auto-replace), so without this you
# get "Container pigen_work already exists" after every failure.
docker rm -fv pigen_work >/dev/null 2>&1 || true

log "Cloning pi-gen ($PI_GEN_TAG) into $WORK_DIR"
git clone --depth 1 --branch "$PI_GEN_TAG" \
  https://github.com/RPi-Distro/pi-gen.git "$WORK_DIR"

# Symlink the work dir back into the repo so `ls image-build/pi-gen-work`
# keeps working for convenience (deploy/ is the same on both paths).
ln -sfn "$WORK_DIR" "$SCRIPT_DIR/pi-gen-work"

log "Skipping stages 3, 4, 5 (desktop / NOOBS — we only need Lite + our stage)"
for stage in stage3 stage4 stage5; do
  touch "$WORK_DIR/$stage/SKIP" "$WORK_DIR/$stage/SKIP_IMAGES"
done

log "Copying KODE OS stage into pi-gen"
cp -r "$SCRIPT_DIR/stage-kode-os" "$WORK_DIR/"

# rsync the rest of the kode-os repo into the stage so the chroot
# install script (Phase 2) can copy it into /opt/kode-os in the image.
# Excludes:
#   - .git (huge, useless inside the image)
#   - image-build/pi-gen-work (would copy this build's own working dir
#     into the image — infinite recursion of disk usage)
#   - node_modules / kode-os-ui (the UI gets cloned + built fresh inside
#     the chroot to avoid stale builds and ARM/x86 mismatches)
log "Copying kode-os source into stage"
mkdir -p "$WORK_DIR/stage-kode-os/01-install-kode-os/files/kode-os-source"
rsync -a \
  --exclude=".git" \
  --exclude="image-build/pi-gen-work" \
  --exclude="kode-os-ui" \
  --exclude="node_modules" \
  --exclude=".claude" \
  --exclude="_assets-reference" \
  "$REPO_ROOT/" \
  "$WORK_DIR/stage-kode-os/01-install-kode-os/files/kode-os-source/"

log "Cross-compiling OLED splash binary for arm64 (Docker-based, no host toolchain needed)"
# We avoid requiring gcc-aarch64-linux-gnu on the host by running
# the compile inside a Debian container. Net cost: ~30s for the
# first run (apt installs gcc + python3-pil + fonts in the
# container), then Docker layer cache makes subsequent builds
# near-instant. Produces splash.arm64 + splash_bitmap.h in-tree;
# install-in-chroot.sh picks them up from /opt/kode-os.
SPLASH_DIR="$WORK_DIR/stage-kode-os/01-install-kode-os/files/oled-splash"
docker run --rm \
  -v "$SPLASH_DIR":/src \
  -w /src \
  debian:bookworm bash -c '
    set -e
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends \
      gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
      python3-pil fonts-dejavu-core make file >/dev/null
    make clean >/dev/null
    make
    file splash.arm64
  '

log "Pre-building kode-os-ui natively (saves ~30 min vs qemu-user emulation)"
# We build the UI on the build host instead of inside the chroot
# because Vue 2 + Vue CLI under qemu-user takes 30–45 min while a
# native build is ~80s. The chroot stage just rsyncs the resulting
# build/sysroot/var/lib/casaos/www/ into the rootfs.
UI_BUILD_DIR="$(mktemp -d -t kode-os-ui-build-XXXXXX)"
trap 'rm -rf "$UI_BUILD_DIR"' EXIT
git clone --depth 1 https://github.com/KodeNAS/kode-os-ui.git "$UI_BUILD_DIR/kode-os-ui"
(
  cd "$UI_BUILD_DIR/kode-os-ui"
  command -v pnpm >/dev/null 2>&1 || npm install -g pnpm
  pnpm install --frozen-lockfile
  pnpm build
)
UI_STAGE="$WORK_DIR/stage-kode-os/01-install-kode-os/files/ui-prebuilt"
mkdir -p "$UI_STAGE/var/lib/casaos/www"
rsync -a "$UI_BUILD_DIR/kode-os-ui/build/sysroot/var/lib/casaos/www/" \
  "$UI_STAGE/var/lib/casaos/www/"
rm -rf "$UI_BUILD_DIR"
trap - EXIT

log "Copying pi-gen config"
cp "$SCRIPT_DIR/pi-gen-config" "$WORK_DIR/config"

# Export build-time env vars into pi-gen's config sourcing chain.
# pi-gen sources `config` then runs each stage; KODE_BUNDLE_APPS is
# read by stage-kode-os/01-install-kode-os/01-run.sh to decide
# whether to pre-pull Docker images.
{
  echo ""
  echo "# Injected by build.sh"
  echo "export KODE_BUNDLE_APPS=${KODE_BUNDLE_APPS}"
} >> "$WORK_DIR/config"

log "Starting pi-gen build (30–60 min — go get coffee)"
cd "$WORK_DIR"
sudo ./build-docker.sh

log "Build complete. Output:"
ls -lh "$WORK_DIR/deploy/" || true
