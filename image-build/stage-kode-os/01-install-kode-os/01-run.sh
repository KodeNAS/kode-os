#!/bin/bash -e
#
# 01-install-kode-os — copies the kode-os source into the rootfs
# at /opt/kode-os and runs install-in-chroot.sh to bake KODE OS into
# the image (UI overlay, OLED daemon, kode-os CLI symlink, SPI in
# config.txt). CasaOS upstream binaries get installed on first boot
# (Phase 3) — they need a running Docker daemon to set up the API
# override, which we can't do in chroot.
#
# Variables provided by pi-gen at runtime:
#   ROOTFS_DIR — the staging rootfs we're baking
#   STAGE_DIR  — the parent stage dir (.../stage-kode-os)
#   PWD        — pi-gen pushd's into the sub-stage dir before
#                running this script, so plain `files/...` paths
#                resolve correctly (BASE_DIR is /pi-gen, NOT what
#                you'd expect — burned us once).
#
# Variables provided by build.sh (exported in config):
#   KODE_BUNDLE_APPS — 1 if we should pre-pull Docker images,
#                      0 (default) for the slim variant.

# Source — staged by build.sh under
# files/kode-os-source/ before pi-gen runs.
KODE_SRC="files/kode-os-source"
KODE_DST="/opt/kode-os"

if [[ ! -d "${KODE_SRC}" ]]; then
  echo "01-install-kode-os: kode-os source missing at ${KODE_SRC}" >&2
  echo "  This is staged by build.sh — did you run pi-gen manually?" >&2
  exit 1
fi

echo "Copying kode-os source → ${ROOTFS_DIR}${KODE_DST}"
install -d -m 755 "${ROOTFS_DIR}${KODE_DST}"
rsync -a --delete \
  --exclude=".git" \
  --exclude="image-build/pi-gen-work" \
  --exclude="node_modules" \
  "${KODE_SRC}/" "${ROOTFS_DIR}${KODE_DST}/"

# Stage the pre-built UI artifact (build.sh built this natively on the
# host to avoid the ~30 min qemu-user emulation cost). If it's missing,
# bail loudly — running the chroot pnpm build as a fallback would
# silently 10× the build time.
UI_PREBUILT="files/ui-prebuilt"
if [[ ! -d "${UI_PREBUILT}/var/lib/casaos/www" ]]; then
  echo "01-install-kode-os: pre-built UI missing at ${UI_PREBUILT}" >&2
  echo "  build.sh should have built kode-os-ui natively + staged it here." >&2
  exit 1
fi

echo "Overlaying UI → ${ROOTFS_DIR}/var/lib/casaos/www"
install -d -m 755 "${ROOTFS_DIR}/var/lib/casaos/www"
rsync -a "${UI_PREBUILT}/var/lib/casaos/www/" "${ROOTFS_DIR}/var/lib/casaos/www/"

# Stage the chroot install script and run it inside the chroot.
install -m 755 "files/install-in-chroot.sh" \
  "${ROOTFS_DIR}/tmp/install-in-chroot.sh"

on_chroot << 'EOF'
/tmp/install-in-chroot.sh
rm /tmp/install-in-chroot.sh
EOF
