#!/usr/bin/env bash
#
# KODE OS installer
# https://github.com/KodeNAS/kode-os
#
# Usage (on a fresh Raspberry Pi OS Lite install, as root):
#
#   curl -fsSL https://kode-nas.com/install.sh | sudo bash
#
# Or, after cloning this repo:
#
#   sudo ./scripts/install.sh
#
# Flags:
#   --uninstall   remove KODE OS + the OLED daemon. Leaves /DATA alone.
#   --skip-casaos skip the upstream CasaOS install (advanced)
#   --no-oled     don't install the SH1122 OLED daemon
#   --version VER pin to a specific KODE OS UI release (default: latest)
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
SKIP_CASAOS=0
INSTALL_OLED=auto      # auto = install only if /dev/spidev0.0 exists

KODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=1; shift ;;
    --skip-casaos) SKIP_CASAOS=1; shift ;;
    --no-oled) INSTALL_OLED=0; shift ;;
    --version) KODE_UI_REF="$2"; shift 2 ;;
    -h|--help)
      grep -E '^#' "$0" | sed 's/^# \{0,1\}//' | head -25
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
if [[ $UNINSTALL -eq 1 ]]; then
  require_root
  log "Uninstalling KODE OS…"
  systemctl disable --now kode-nas-display.service 2>/dev/null || true
  rm -f /etc/systemd/system/kode-nas-display.service
  rm -f /home/kode/kode_nas_display.py /home/kode/restart-display.sh /tmp/oled.log
  systemctl daemon-reload
  log "Removing KODE UI overlay from /var/lib/casaos/www…"
  rm -rf /var/lib/casaos/www
  log "KODE OS removed. /DATA is untouched."
  log "To also remove CasaOS upstream:  curl -fsSL https://get.casaos.io/uninstall | sudo bash"
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
  if ! systemctl list-unit-files | grep -q casaos-gateway; then
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
if [[ $INSTALL_OLED == "auto" ]]; then
  if detect_oled; then
    INSTALL_OLED=1
    log "SH1122 OLED detected on /dev/spidev0.0 — installing daemon."
  else
    INSTALL_OLED=0
    log "No /dev/spidev0.0 — skipping OLED daemon. (Enable SPI in raspi-config and re-run to install.)"
  fi
fi

if [[ $INSTALL_OLED -eq 1 ]]; then
  # Ensure the kode user exists (CasaOS install creates it; defensive check).
  if ! id kode >/dev/null 2>&1; then
    warn "User 'kode' not found — creating one for the OLED daemon."
    useradd -m -s /bin/bash kode
  fi
  # Python deps for the daemon.
  apt-get install -y -qq python3-pip python3-pil python3-psutil python3-spidev python3-gpiozero
  install -m 0755 -o kode -g kode "$KODE_ROOT/pebble/kode_nas_display.py" /home/kode/kode_nas_display.py
  install -m 0755 -o kode -g kode "$KODE_ROOT/pebble/restart-display.sh"  /home/kode/restart-display.sh
  install -m 0644 "$KODE_ROOT/pebble/kode-nas-display.service" /etc/systemd/system/kode-nas-display.service
  systemctl daemon-reload
  systemctl enable --now kode-nas-display.service
fi

# 7. Done — print access info. KODE OS banner (NOT CasaOS's) is the
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

  HTTPS (optional):  sudo ${KODE_ROOT}/scripts/setup-pebble-https.sh
  Uninstall:         sudo ${KODE_ROOT}/scripts/install.sh --uninstall
  Upstream log:      ${CASAOS_LOG}

  Made by KODE NAS · pebble v1
  Based on CasaOS (Apache 2.0) — github.com/IceWhaleTech/CasaOS
EOF
