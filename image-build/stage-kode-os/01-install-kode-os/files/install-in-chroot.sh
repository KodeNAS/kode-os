#!/usr/bin/env bash
#
# install-in-chroot.sh — bakes the chroot-safe subset of KODE OS into
# the pi-gen rootfs. Runs INSIDE the chroot via on_chroot.
#
# What this does (chroot-safe operations only):
#   1. Enables SPI in /boot/firmware/config.txt for the OLED.
#   2. Installs the OLED daemon + its systemd unit.
#   3. Adds the kode-os CLI symlink under /usr/local/bin.
#   4. Adds the `kode` user to gpio/spi groups for OLED device access.
#   5. Marks /opt/kode-os/.firstboot-pending so the first-boot service
#      (installed by stage 02-firstboot) knows to run.
#
# What this does NOT do (deferred to first-boot — Phase 3):
#   - CasaOS upstream install (needs a running Docker daemon)
#   - UI build (pre-built natively by build.sh and rsync'd in by
#     01-run.sh — much faster than qemu-user emulation)
#   - systemctl start of anything (no live systemd in chroot)
#
# This script assumes /opt/kode-os/ already has the kode-os repo
# contents (rsync'd by 01-run.sh) and /var/lib/casaos/www/ has the
# pre-built UI overlay.

set -euo pipefail

KODE_ROOT="/opt/kode-os"
log() { echo "[install-in-chroot] $*"; }

# 1. Enable SPI on the GPIO header so the OLED's /dev/spidev0.0
# appears at first boot. Same logic as the runtime install.sh path,
# but writing to the IMAGE's config.txt (mounted at /boot/firmware/
# in the chroot).
CONFIG_TXT=""
for candidate in /boot/firmware/config.txt /boot/config.txt; do
  [[ -f "$candidate" ]] && { CONFIG_TXT="$candidate"; break; }
done
if [[ -n "$CONFIG_TXT" ]] && ! grep -qE '^[[:space:]]*dtparam=spi=on' "$CONFIG_TXT"; then
  log "Enabling SPI in $CONFIG_TXT for the SH1122 OLED"
  if grep -qE '^[[:space:]]*#[[:space:]]*dtparam=spi=on' "$CONFIG_TXT"; then
    sed -i -E 's/^[[:space:]]*#[[:space:]]*(dtparam=spi=on)/\1/' "$CONFIG_TXT"
  else
    printf '\n# Enabled by KODE OS image build for the SH1122 OLED.\ndtparam=spi=on\n' >> "$CONFIG_TXT"
  fi
fi

# 2. OLED daemon. The user account `kode` already exists from
# pi-gen's FIRST_USER_NAME; we just need to add it to the spi/gpio
# groups so the daemon can open /dev/spidev0.0 + /dev/gpiochip0.
# We ALSO lock the account immediately — pi-gen needed a non-empty
# FIRST_USER_PASS to pass its safety check, but we don't want any
# usable login until the wizard creates the real admin. SSH is also
# disabled (ENABLE_SSH=0 in pi-gen-config) so this is belt + braces.
if id kode >/dev/null 2>&1; then
  log "Locking kode account (no login until wizard creates the real admin)"
  passwd -l kode >/dev/null
  log "Adding kode user to gpio + spi groups"
  usermod -aG spi,gpio kode 2>/dev/null || true
fi

log "Installing OLED daemon + systemd unit"
install -m 0755 -o kode -g kode \
  "${KODE_ROOT}/pebble/kode_nas_display.py" /home/kode/kode_nas_display.py
install -m 0755 -o kode -g kode \
  "${KODE_ROOT}/pebble/restart-display.sh"  /home/kode/restart-display.sh
install -m 0644 \
  "${KODE_ROOT}/pebble/kode-nas-display.service" \
  /etc/systemd/system/kode-nas-display.service
systemctl enable kode-nas-display.service

# 3. kode-os CLI dispatcher. Same symlink the runtime installer
# would have made — exposes `sudo kode-os update` / `kode-os version`
# from anywhere on PATH.
log "Installing kode-os CLI symlink"
ln -sf "${KODE_ROOT}/scripts/kode-os" /usr/local/bin/kode-os

# 4. Pre-create the /DATA directory tree CasaOS would normally
# scaffold on first run. Done now so the first-boot CasaOS install
# can fill them with sample content immediately.
log "Creating /DATA folder tree"
install -d -m 0755 -o root -g root /DATA
for dir in Photos Movies Shows Videos Documents Music Downloads Backups; do
  install -d -m 0775 -o root -g users "/DATA/${dir}"
done

# 5. Mark firstboot pending so the kode-firstboot.service (installed
# by 02-firstboot/02-run.sh) knows to run on next power-on. The
# service removes this file when it finishes, so a reboot mid-setup
# resumes correctly.
touch /opt/kode-os/.firstboot-pending

log "Done. CasaOS install + service start happen at first boot."
