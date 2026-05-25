#!/bin/bash -e
#
# 02-firstboot — bake the first-boot service + script into the image.
#
# This stage just installs files + enables a systemd service:
#   - /opt/kode-os/scripts/kode-firstboot.sh   (the script)
#   - /etc/systemd/system/kode-firstboot.service  (the unit)
#
# The actual first-boot logic runs after the user flashes the image
# and powers on — see files/kode-firstboot.sh for what it does.

# Install the firstboot script under /opt/kode-os/scripts/ so the
# systemd unit's ExecStart path is stable. install -D creates the
# parent dir if missing.
install -D -m 0755 -o root -g root \
  files/kode-firstboot.sh \
  "${ROOTFS_DIR}/opt/kode-os/scripts/kode-firstboot.sh"

install -D -m 0644 -o root -g root \
  files/kode-firstboot.service \
  "${ROOTFS_DIR}/etc/systemd/system/kode-firstboot.service"

# Enable the service so it fires on the buyer's first boot. The
# unit's ConditionPathExists=/opt/kode-os/.firstboot-pending makes
# it self-disabling after a successful run (the script removes the
# marker file as its last step) — re-enabling is harmless because
# the condition gates execution.
on_chroot << 'EOF'
systemctl enable kode-firstboot.service
EOF
