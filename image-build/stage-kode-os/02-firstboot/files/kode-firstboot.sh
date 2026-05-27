#!/usr/bin/env bash
#
# kode-firstboot.sh — runs once on first power-on of a freshly
# flashed KODE OS image. Picks up where the chroot bake left off:
#
#   1. Expands the root filesystem to fill the SD card.
#   2. Bootstraps CasaOS (upstream installer needs a live Docker
#      daemon, which can't run in chroot — so it's deferred to here).
#   3. Mints a random wizard token; writes it to
#      /opt/kode-os/.wizard-token (mode 0600, root-owned).
#   4. Tells the user where to point their browser via:
#         - /etc/motd (visible on console + SSH after wizard)
#         - the OLED daemon (signal via /tmp/kode-oled-firstboot)
#         - /opt/kode-os/.wizard-url (consumed by kode-os-ui)
#   5. Starts the OLED daemon (kode-nas-display.service).
#   6. Removes /opt/kode-os/.firstboot-pending so the systemd unit
#      doesn't fire again on subsequent boots.
#
# Idempotency: if any step fails, .firstboot-pending stays in place
# and systemd re-runs us on the next boot. The token is generated
# fresh each run, so a failed run doesn't leak a half-set-up token.
#
# Installed to /opt/kode-os/scripts/kode-firstboot.sh by 02-run.sh.

set -euo pipefail

LOG=/var/log/kode-firstboot.log
exec >>"$LOG" 2>&1

KODE_ROOT="/opt/kode-os"
TOKEN_FILE="${KODE_ROOT}/.wizard-token"
URL_FILE="${KODE_ROOT}/.wizard-url"
# Web-accessible copy of the token. The kode-os-ui router's
# wizard-token guard fetches /.wizard-token to validate the URL.
# Mode 0644 because casaos-gateway serves it as a regular static
# file. (See router/index.js wizardTokenMatches() for the threat
# model + why fileToken being LAN-fetchable is acceptable here.)
WEB_TOKEN_FILE="/var/lib/casaos/www/.wizard-token"
PENDING_MARKER="${KODE_ROOT}/.firstboot-pending"
OLED_SIGNAL="/tmp/kode-oled-firstboot"

ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] kode-firstboot: $*"; }

# oled() — surface a step on the OLED status card. Three positional
# args (title, subtitle, footer); all optional. Errors are swallowed
# because the OLED is hardware-dependent and a missing display
# should never block first-boot.
oled() {
  "${KODE_ROOT}/scripts/oled-status" "$@" 2>/dev/null || true
}

# wait_for_network — block until we have actual internet, not just
# what systemd's network-online.target thinks. NetworkManager
# "completes" network-online after a 90s timeout even with no link
# at all, so depending only on After=network-online.target gives us
# zero protection against "ethernet not plugged in yet." We poll a
# real DNS+TCP path (github.com — install.sh needs it next anyway)
# and surface the wait state on the OLED so the buyer knows to
# plug in the cable. Returns 0 once network is up, non-zero after
# the wait budget elapses.
wait_for_network() {
  local max_wait=300         # 5 min total before we give up
  local interval=10          # poll every 10s
  local elapsed=0
  # Quick first check — if internet is already up (the common case
  # with ethernet plugged in at power-on) skip the OLED message
  # entirely so it doesn't flicker.
  if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
    log "Network already up"
    return 0
  fi
  log "No network yet — waiting up to ${max_wait}s"
  while (( elapsed < max_wait )); do
    local remaining=$((max_wait - elapsed))
    oled "WAITING FOR NETWORK" "Plug in Ethernet" "retrying in ${interval}s (${remaining}s left)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
    if ping -c 1 -W 2 github.com >/dev/null 2>&1; then
      log "Network is up after ${elapsed}s"
      return 0
    fi
  done
  log "No network after ${max_wait}s — bailing"
  return 1
}

log "Starting first-boot setup"
oled "SETTING UP" "Just a moment" "first power-on"

# ----- 1. Filesystem expansion ----------------------------------
# raspi-config nonint do_expand_rootfs schedules the resize on next
# boot. It typically requires a reboot to take effect — we DON'T
# reboot here because that'd interrupt the rest of the firstboot
# sequence. Pi OS handles the actual resize during the next boot.
log "Expanding root filesystem"
oled "SETTING UP" "Expanding storage" "step 1 of 3"
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_expand_rootfs || log "expand_rootfs returned non-zero (continuing)"
else
  log "raspi-config not present — skipping fs expansion (manual resize may be needed)"
fi

# ----- 2. CasaOS bootstrap --------------------------------------
# Defer to install.sh — it already knows the whole CasaOS upstream
# install dance + idempotent re-runs of the rest. install.sh detects
# "already installed" bits and skips them; the only real work here
# should be the upstream CasaOS install.
log "Checking for internet before CasaOS install"
if ! wait_for_network; then
  log "No network — leaving .firstboot-pending so we retry on next boot"
  oled "NO NETWORK" "Plug in Ethernet" "then reboot"
  exit 1
fi

log "Running install.sh to bootstrap CasaOS"
oled "SETTING UP" "Installing CasaOS" "step 2 of 3 (~2 min)"
if ! "${KODE_ROOT}/scripts/install.sh"; then
  log "install.sh failed — leaving .firstboot-pending so we retry on next boot"
  oled "SETUP FAILED" "Install error — check logs" "ssh + journalctl -u kode-firstboot"
  exit 1
fi

# ----- 3. Wizard token ------------------------------------------
TOKEN=$(openssl rand -hex 16)
umask 077
printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
chown root:root "$TOKEN_FILE"
# Web-accessible copy for the UI router to fetch + compare.
umask 022
mkdir -p "$(dirname "$WEB_TOKEN_FILE")"
printf '%s\n' "$TOKEN" > "$WEB_TOKEN_FILE"
chmod 644 "$WEB_TOKEN_FILE"
log "Wizard token generated (32 hex chars; 0600 at $TOKEN_FILE, 0644 at $WEB_TOKEN_FILE)"

# ----- 4. Wizard URL display -----------------------------------
# Compose the URL the user should visit. Prefer hostname.local for
# friendliness but always also show the IP since mDNS is unreliable
# on some networks.
HOSTNAME=$(hostname)
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
WIZARD_PATH="/#/wizard/${TOKEN}"

# Persist the URL so kode-os-ui (and anything else) can read it
# without parsing the token directly.
printf 'http://%s%s\n' "${IP:-pebble.local}" "${WIZARD_PATH}" > "$URL_FILE"
chmod 644 "$URL_FILE"

# MOTD — what SSH/console users see.
cat > /etc/motd <<EOM

  ╔══════════════════════════════════════════════════════════╗
  ║              KODE OS — first-boot setup                  ║
  ╠══════════════════════════════════════════════════════════╣
  ║                                                          ║
  ║   Finish setup in your browser at:                       ║
  ║                                                          ║
  ║     http://${HOSTNAME}.local${WIZARD_PATH}
  ║     http://${IP}${WIZARD_PATH}
  ║                                                          ║
  ║   (Use the IP if .local doesn't resolve on your network.)║
  ║                                                          ║
  ║   SSH stays disabled until the wizard finishes — there   ║
  ║   is no usable password on this account yet.             ║
  ║                                                          ║
  ╚══════════════════════════════════════════════════════════╝

EOM

# OLED — write a small signal file the running daemon picks up
# and renders. The daemon's normal hostname/IP/storage rotation
# pauses while the firstboot signal is present.
mkdir -p "$(dirname "$OLED_SIGNAL")"
cat > "$OLED_SIGNAL" <<EOM
hostname=${HOSTNAME}
ip=${IP:-?.?.?.?}
url=${WIZARD_PATH}
EOM
chmod 644 "$OLED_SIGNAL"

# ----- 5. Start OLED daemon ------------------------------------
log "Starting OLED display daemon"
oled "SETTING UP" "Almost done" "step 3 of 3"
systemctl start kode-nas-display.service || log "OLED daemon start failed (no SH1122 wired up?)"

# Switch OLED to the wizard-URL card. Stays on until the next reboot
# OR until something clears /run/kode-os/oled-status. For v0.2.0-alpha
# the user clears it manually once the wizard is done; v0.3.0 will
# auto-clear when CasaOS reports initialized.
oled "OPEN IN BROWSER" "${HOSTNAME}.local" "${WIZARD_PATH}"

# ----- 6. Clear firstboot marker --------------------------------
rm -f "$PENDING_MARKER"
log "First-boot setup complete — wizard awaiting at http://${IP}${WIZARD_PATH}"
