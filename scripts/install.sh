#!/usr/bin/env bash
#
# KODE OS installer
# https://github.com/KodeNAS/kode-os
#
# Usage (on a fresh Raspberry Pi OS Lite install, as root):
#
#   curl -fsSL https://kodenas.dev/install.sh | sudo bash
#
# Or, after cloning this repo:
#
#   sudo ./scripts/install.sh
#
# Flags:
#   --uninstall    Remove KODE OS UI overlay + OLED daemon + CasaOS
#                  runtime. Keeps Docker, /DATA, and system packages
#                  CasaOS pulled in (samba, smartmontools, etc).
#   --uninstall --purge
#                  Above + remove all KODE-installed Docker containers
#                  + images + volumes + the Docker API override + the
#                  kode user (if we created one). Keeps Docker itself
#                  + /DATA.
#   --uninstall --wipe-data
#                  Adds /DATA wipe to whatever uninstall mode you're
#                  in. Requires typing WIPE to confirm. Combine with
#                  --purge for the full nuke.
#   --uninstall --yes
#                  Skip the type-WIPE confirmation. For automation.
#                  Use with care.
#   --skip-casaos  Skip the upstream CasaOS install (advanced)
#   --no-oled      Don't install the SH1122 OLED daemon
#   --version VER  Pin to a specific KODE OS UI release (default: latest)
#
# This is an alpha installer. Expect rough edges. Don't run it on hardware
# you can't reflash.

set -euo pipefail

# ---- config ----
KODE_UI_REPO="https://github.com/KodeNAS/kode-os-ui.git"
KODE_UI_REF="${KODE_UI_REF:-main}"
CASAOS_INSTALL_URL="https://get.casaos.io/install"
# Node 20 LTS — Node 18 is end-of-life as of Apr 2025 and the NodeSource
# installer prints a 10-second deprecation warning every time it runs.
NODE_MAJOR=20
# The wrapped CasaOS upstream installer is loud (banner, download
# progress, migration script noise, its own final "running at" block).
# We redirect its stdout to this file so the screen stays clean but
# the full log is preserved for debugging.
CASAOS_LOG="/tmp/kode-os-casaos-install.log"

UNINSTALL=0
PURGE=0
WIPE_DATA=0
ASSUME_YES=0
SKIP_CASAOS=0
INSTALL_OLED=auto      # auto = install only if /dev/spidev0.0 exists

KODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=1; shift ;;
    --purge) PURGE=1; shift ;;
    --wipe-data) WIPE_DATA=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --skip-casaos) SKIP_CASAOS=1; shift ;;
    --no-oled) INSTALL_OLED=0; shift ;;
    --version) KODE_UI_REF="$2"; shift 2 ;;
    -h|--help)
      # Print the file-header comment block (stops at the first
      # blank line so later inline comments don't leak into --help).
      sed -n '1,/^$/p' "$0" | sed 's/^#\!.*//;s/^# \{0,1\}//' | head -40
      exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ---- helpers ----
log()  { echo -e "\033[1;36m[kode-os]\033[0m $*"; }
warn() { echo -e "\033[1;33m[kode-os] WARN:\033[0m $*" >&2; }
fail() { echo -e "\033[1;31m[kode-os] ERROR:\033[0m $*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    fail "This script needs root. Re-run with sudo."
  fi
}

detect_pi() {
  if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null \
     && ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    warn "This doesn't look like a Raspberry Pi. KODE OS is tested on Pi 5 only."
    warn "Continuing anyway — bail out (Ctrl+C) if you want."
    sleep 3
  fi
}

detect_oled() {
  [[ -e /dev/spidev0.0 ]]
}

# ---- uninstall path ----
# Tiered: --uninstall is the safe default (KODE + CasaOS gone, data
# kept). --purge adds Docker app teardown + system cleanup. --wipe-data
# nukes /DATA. All destructive tiers require a typed WIPE confirmation
# unless --yes is also passed.
if [[ $UNINSTALL -eq 1 ]]; then
  require_root

  echo
  echo "Uninstall plan:"
  echo "  ✓ Stop + disable KODE OS daemons (OLED display, etc.)"
  echo "  ✓ Remove KODE UI overlay from /var/lib/casaos/www"
  echo "  ✓ Run the upstream casaos-uninstall (removes casaos-* services + binaries)"
  if (( PURGE )); then
    echo "  ✓ [--purge] Stop + remove ALL Docker containers KODE installed"
    echo "  ✓ [--purge] Remove the Docker API compatibility override"
    echo "  ✓ [--purge] Remove the kode user (if no other home dir uses it)"
  fi
  if (( WIPE_DATA )); then
    echo "  ⚠ [--wipe-data] Recursively delete /DATA (photos, files, app data)"
  fi
  echo
  echo "What this WILL keep regardless:"
  echo "  • Docker itself (use 'apt purge docker-ce' separately if you want it gone)"
  echo "  • System packages CasaOS pulled in (smartmontools, samba, mergerfs, rclone…)"
  if ! (( WIPE_DATA )); then
    echo "  • Everything under /DATA"
  fi
  echo

  # Type-WIPE confirmation for any tier that touches user data or
  # tears down Docker apps. Bypassed with --yes for automation.
  if (( WIPE_DATA || PURGE )) && ! (( ASSUME_YES )); then
    read -r -p "Type WIPE to confirm: " confirm
    if [[ "$confirm" != "WIPE" ]]; then
      fail "Confirmation didn't match. Aborted, nothing removed."
    fi
  fi

  # --- KODE OS bits ---
  log "Stopping KODE OS daemons…"
  systemctl disable --now kode-nas-display.service 2>/dev/null || true
  rm -f /etc/systemd/system/kode-nas-display.service
  rm -f /home/kode/kode_nas_display.py /home/kode/restart-display.sh /tmp/oled.log

  log "Removing kode-os CLI symlink…"
  rm -f /usr/local/bin/kode-os

  log "Removing KODE UI overlay from /var/lib/casaos/www…"
  rm -rf /var/lib/casaos/www

  # --- CasaOS upstream runtime ---
  # The upstream installer provides a `casaos-uninstall` helper that
  # stops every casaos-* service, removes binaries from /usr/bin, and
  # cleans /etc/casaos + /var/lib/casaos (except apps + their data,
  # which only `--purge` should touch).
  if command -v casaos-uninstall >/dev/null 2>&1; then
    log "Running casaos-uninstall (this stops + removes all casaos-* services)…"
    # casaos-uninstall is interactive — it `read -p`s for a y/N
    # confirmation and hangs forever on EOF. Force-feed a stream of
    # `y` so it always answers yes, and cap the call with a 90s
    # timeout so a deeper-stuck call still surrenders. Output goes
    # to a log file we tail if the call exits non-zero.
    if ! timeout 90 bash -c 'yes y | casaos-uninstall' >/tmp/kode-os-casaos-uninstall.log 2>&1; then
      warn "casaos-uninstall hung or exited non-zero. Falling back to manual teardown."
      warn "Full log: /tmp/kode-os-casaos-uninstall.log"
      for svc in casaos casaos-gateway casaos-message-bus casaos-user-service \
                 casaos-local-storage casaos-app-management rclone; do
        systemctl disable --now "${svc}.service" 2>/dev/null || true
      done
      rm -f /usr/bin/casaos /usr/bin/casaos-* /usr/bin/casaos-cli
      rm -f /etc/systemd/system/casaos*.service \
            /etc/systemd/system/multi-user.target.wants/casaos*.service
      rm -rf /etc/casaos /var/lib/casaos /usr/share/casaos
    fi
  else
    # Fallback: stop services we know about manually.
    log "casaos-uninstall not found — stopping known casaos-* services manually."
    for svc in casaos casaos-gateway casaos-message-bus casaos-user-service \
               casaos-local-storage casaos-app-management rclone; do
      systemctl disable --now "${svc}.service" 2>/dev/null || true
    done
    rm -f /usr/bin/casaos /usr/bin/casaos-* /usr/bin/casaos-cli
    rm -rf /etc/casaos /var/lib/casaos /usr/share/casaos
  fi
  systemctl daemon-reload

  # --- --purge — Docker teardown + Docker override + kode user ---
  if (( PURGE )); then
    if command -v docker >/dev/null 2>&1; then
      log "Stopping + removing KODE-installed Docker containers…"
      # Compose apps live under /var/lib/casaos/apps/ — but with
      # casaos-uninstall already run, that path may be gone. Fall
      # back to listing every container + image and removing those
      # whose label/name matches our app set.
      KODE_APPS="immich jellyfin filebrowser pihole homeassistant big-bear-home-assistant"
      for app in $KODE_APPS; do
        # Stop + remove containers matching the app name or label.
        for cid in $(docker ps -aq --filter "name=^/${app}" 2>/dev/null); do
          docker rm -f "$cid" >/dev/null 2>&1 || true
        done
        for cid in $(docker ps -aq --filter "label=com.docker.compose.project=${app}" 2>/dev/null); do
          docker rm -f "$cid" >/dev/null 2>&1 || true
        done
      done

      # Best-effort image cleanup for the canonical KODE app images.
      log "Removing KODE app Docker images (best-effort)…"
      for img in $(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -iE 'immich|jellyfin|filebrowser|pihole|home-assistant|hass' || true); do
        docker rmi -f "$img" >/dev/null 2>&1 || true
      done

      # Volumes + networks
      log "Pruning leftover KODE app Docker volumes + networks…"
      docker volume prune -f >/dev/null 2>&1 || true
      docker network prune -f >/dev/null 2>&1 || true
    fi

    # CasaOS dropped a Docker API compatibility override on first
    # install — yank it so Docker comes back to a stock config.
    if [[ -f /etc/systemd/system/docker.service.d/override.conf ]]; then
      log "Removing Docker API compatibility override…"
      rm -f /etc/systemd/system/docker.service.d/override.conf
      rmdir /etc/systemd/system/docker.service.d 2>/dev/null || true
      systemctl daemon-reload
      systemctl restart docker 2>/dev/null || true
    fi

    # Remove the kode user — but only if their home is empty (avoid
    # nuking SSH keys + dotfiles the buyer might want to keep). The
    # user may also have non-KODE work on the system.
    if id kode >/dev/null 2>&1; then
      if [[ -z "$(ls -A /home/kode 2>/dev/null | grep -v -E '^\.bash_history$|^\.bash_logout$|^\.bashrc$|^\.profile$|^\.ssh$')" ]]; then
        log "Removing kode user (home dir is otherwise empty)…"
        userdel -r kode 2>/dev/null || true
      else
        warn "Keeping kode user — /home/kode has non-default files."
      fi
    fi
  fi

  # --- --wipe-data — /DATA nuke ---
  if (( WIPE_DATA )); then
    log "Wiping /DATA (this can take a minute on full drives)…"
    if [[ -d /DATA ]]; then
      # Recurse but skip hidden dotdirs at the top level (mount points,
      # system markers). Same heuristic the Factory Reset modal uses.
      find /DATA -mindepth 1 -maxdepth 1 ! -name '.*' -exec rm -rf {} +
    fi
  fi

  log ""
  log "✓ KODE OS uninstalled."
  if (( PURGE )); then log "✓ Docker apps + override + (maybe) kode user removed."; fi
  if (( WIPE_DATA )); then log "✓ /DATA wiped."; fi
  if ! (( PURGE )); then
    log ""
    log "To also remove Docker containers + the API override, re-run with:"
    log "    sudo ./scripts/install.sh --uninstall --purge"
  fi
  if ! (( WIPE_DATA )); then
    log "To also wipe /DATA, add --wipe-data."
  fi
  log "To remove Docker itself:  sudo apt purge -y docker-ce docker-ce-cli containerd.io"
  exit 0
fi

# ---- install path ----
require_root
detect_pi

# KODE OS banner — printed before any of the wrapped installer output
# so the user sees our branding first, even if CasaOS's own banner
# shows up later in the log file.
cat <<'BANNER'

 _  _____  ___  ____    ___  ___
| |/ / _ \|   \| ___|  / _ \/ __|
| ' < (_) | |) | _|   | (_) \__ \
|_|\_\___/|___/|___|   \___/|___/

  KODE OS installer · alpha · KODE NAS
  https://github.com/KodeNAS/kode-os

BANNER

# 1. Prereqs
log "Installing prerequisites…"
apt-get update -qq
apt-get install -y -qq git curl ca-certificates rsync

# 2. Docker (if missing)
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker (via official convenience script)…"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
else
  log "Docker already installed: $(docker --version | head -1)"
fi

# 3. CasaOS upstream runtime (the OS engine KODE OS runs on top of).
# The upstream installer is verbose and prints its own banner + final
# "running at" message — both branded as CasaOS. We redirect all of
# its output to $CASAOS_LOG so the screen stays clean. The KODE OS
# success banner at the end is what the user sees instead.
if [[ $SKIP_CASAOS -eq 0 ]]; then
  # Probe by binary, not by `systemctl list-unit-files | grep -q`. The
  # grep version is a real foot-gun under `set -o pipefail`: `grep -q`
  # exits at the first match, SIGPIPEs systemctl mid-write, the pipeline
  # exit status becomes systemctl's death code, `!` flips that to truthy,
  # and the "install CasaOS" branch runs against an already-installed
  # CasaOS — which then re-downloads the upstream tarballs (and fails on
  # any flaky network blip). Binary existence is the reliable signal.
  if ! command -v casaos-gateway >/dev/null 2>&1; then
    log "Installing OS runtime (this is the upstream CasaOS layer KODE OS rides on — takes ~2 min)…"
    log "  Full log: $CASAOS_LOG"
    if curl -fsSL "$CASAOS_INSTALL_URL" | bash >"$CASAOS_LOG" 2>&1; then
      log "OS runtime installed."
    else
      fail "Upstream CasaOS install failed. Tail of the log: $(tail -20 "$CASAOS_LOG" | sed 's/^/    /')"
    fi
  else
    log "OS runtime already installed."
  fi
fi

# 4. Node 18 + pnpm (needed to build the UI)
if ! command -v node >/dev/null 2>&1 \
   || [[ "$(node -v | sed 's/v//;s/\..*//')" -lt $NODE_MAJOR ]]; then
  log "Installing Node $NODE_MAJOR…"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y -qq nodejs
fi
if ! command -v pnpm >/dev/null 2>&1; then
  log "Installing pnpm…"
  npm install -g pnpm
fi

# 5. KODE OS UI — clone, build, overlay
log "Cloning KODE OS UI ($KODE_UI_REPO @ $KODE_UI_REF)…"
WORK_DIR=$(mktemp -d -t kode-os-ui-XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT
git clone --depth 1 --branch "$KODE_UI_REF" "$KODE_UI_REPO" "$WORK_DIR/kode-os-ui"
cd "$WORK_DIR/kode-os-ui"

log "Installing UI dependencies (this takes ~2 min)…"
pnpm install --frozen-lockfile

log "Building production assets…"
pnpm build

log "Overlaying UI onto /var/lib/casaos/www…"
mkdir -p /var/lib/casaos/www
rsync -a --delete build/sysroot/var/lib/casaos/www/ /var/lib/casaos/www/

# Restart the gateway so it picks up the new index.html
systemctl restart casaos-gateway || true
systemctl restart casaos || true

cd /
rm -rf "$WORK_DIR"
trap - EXIT

# 6. OLED display daemon (optional, hardware-gated)
# Pi OS Lite ships with SPI on the GPIO header disabled, so a fresh install
# has no /dev/spidev0.0 even when an SH1122 OLED is wired up. Auto-enable
# dtparam=spi=on in config.txt so the next boot exposes it — we can't load
# the overlay mid-install, so defer the daemon install until reboot.
SPI_JUST_ENABLED=0
if [[ $INSTALL_OLED == "auto" ]]; then
  if detect_oled; then
    INSTALL_OLED=1
    log "SH1122 OLED detected on /dev/spidev0.0 — installing daemon."
  else
    # Find the right config.txt — Bookworm+ moved it under /boot/firmware/.
    CONFIG_TXT=""
    for candidate in /boot/firmware/config.txt /boot/config.txt; do
      [[ -f "$candidate" ]] && { CONFIG_TXT="$candidate"; break; }
    done
    if [[ -n "$CONFIG_TXT" ]] && ! grep -qE '^[[:space:]]*dtparam=spi=on' "$CONFIG_TXT"; then
      log "Enabling SPI on the GPIO header (dtparam=spi=on → $CONFIG_TXT)…"
      # Uncomment an existing commented line if Pi OS pre-included one;
      # otherwise append our own. Either way the next boot exposes
      # /dev/spidev0.0 and the OLED daemon can attach.
      if grep -qE '^[[:space:]]*#[[:space:]]*dtparam=spi=on' "$CONFIG_TXT"; then
        sed -i -E 's/^[[:space:]]*#[[:space:]]*(dtparam=spi=on)/\1/' "$CONFIG_TXT"
      else
        printf '\n# Enabled by KODE OS installer for the SH1122 OLED.\ndtparam=spi=on\n' >> "$CONFIG_TXT"
      fi
      SPI_JUST_ENABLED=1
      INSTALL_OLED=0
      log "SPI enabled — reboot, then re-run 'sudo kode-os update' to install the OLED daemon."
    else
      INSTALL_OLED=0
      log "No /dev/spidev0.0 — skipping OLED daemon."
    fi
  fi
fi

if [[ $INSTALL_OLED -eq 1 ]]; then
  # Ensure the kode user exists (CasaOS install creates it; defensive check).
  if ! id kode >/dev/null 2>&1; then
    warn "User 'kode' not found — creating one for the OLED daemon."
    useradd -m -s /bin/bash kode
  fi
  # Python deps for the daemon. python3-rpi-lgpio is critical on Pi 5 —
  # it's a chardev-only RPi.GPIO shim that talks directly to /dev/gpiochip0
  # without needing an lgd daemon (which isn't packaged on Pi OS Bookworm).
  # The plain python3-lgpio package would seem like the obvious pick, but
  # its 0.2.2 Python bindings unconditionally try to open a notification
  # FIFO created by the lgd daemon at import time and die with
  # FileNotFoundError before gpiozero ever sees the factory.
  apt-get install -y -qq python3-pip python3-pil python3-psutil python3-spidev python3-gpiozero python3-rpi-lgpio
  # Grant the daemon user access to the SPI bus + GPIO chip. Pi OS Lite
  # ships these as 'spi' / 'gpio' group-owned 660 devices, so without
  # group membership opening them fails with EACCES.
  usermod -aG spi,gpio kode 2>/dev/null || true
  install -m 0755 -o kode -g kode "$KODE_ROOT/pebble/kode_nas_display.py" /home/kode/kode_nas_display.py
  install -m 0755 -o kode -g kode "$KODE_ROOT/pebble/restart-display.sh"  /home/kode/restart-display.sh
  install -m 0644 "$KODE_ROOT/pebble/kode-nas-display.service" /etc/systemd/system/kode-nas-display.service
  systemctl daemon-reload
  systemctl enable kode-nas-display.service
  # restart instead of just --now so a re-run picks up service-file changes
  # without us having to track whether the unit was already running.
  systemctl restart kode-nas-display.service
fi

# 7. kode-os CLI — symlink the dispatcher into /usr/local/bin so users
# get `kode-os update`, `kode-os uninstall`, `kode-os version` from
# anywhere. The dispatcher follows the symlink with readlink -f to
# find the repo it was installed from, so we don't have to bake the
# path in.
if [[ -x "$KODE_ROOT/scripts/kode-os" ]]; then
  ln -sf "$KODE_ROOT/scripts/kode-os" /usr/local/bin/kode-os
  log "kode-os CLI installed → /usr/local/bin/kode-os (try: kode-os update)"
fi

# 8. Done — print access info. KODE OS banner (NOT CasaOS's) is the
# last thing on screen so the buyer's first impression is ours.
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

────────────────────────────────────────────────────────────
  ✓ KODE OS installed.

  Open your dashboard at:
      http://${HOST_IP}/
      http://$(hostname).local/

  The first-boot wizard runs on first visit.
  About five minutes from box-open to working.
────────────────────────────────────────────────────────────

  Update:            sudo kode-os update
  HTTPS (optional):  sudo ${KODE_ROOT}/scripts/setup-pebble-https.sh
  Uninstall:         sudo kode-os uninstall      (--purge / --wipe-data for deeper)
  Upstream log:      ${CASAOS_LOG}

  Made by KODE NAS · pebble v1
  Based on CasaOS (Apache 2.0) — github.com/IceWhaleTech/CasaOS
EOF

if (( SPI_JUST_ENABLED )); then
  cat <<EOF

  ⚠ SPI was just enabled in ${CONFIG_TXT} for the SH1122 OLED.
      Reboot now, then run:  sudo kode-os update
      to install the OLED daemon.

      sudo reboot
EOF
fi
