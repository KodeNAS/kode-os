#!/bin/bash -e
#
# 00-install-deps — system packages + service enables.
#
# Packages listed in 00-packages get apt-installed automatically by
# pi-gen before this script runs. This script just enables the
# services that need to be on by default.
#
# Important: NO `systemctl start` in a chroot — there's no live
# systemd to start anything. `systemctl enable` works because it
# only writes the wants/required symlinks under /etc/systemd/system.

on_chroot << EOF
# Docker (we use docker.io from Debian rather than the curl|sh
# convenience installer because the latter starts the daemon, which
# can't work in chroot).
systemctl enable docker.service

# mDNS so http://pebble.local/ works on the user's LAN.
systemctl enable avahi-daemon.service

# SMB for the /DATA shares CasaOS exposes.
systemctl enable smbd.service
systemctl enable nmbd.service

# Pre-configure samba to use a per-machine workgroup. Default
# Debian config is fine; nothing to change here.

# Clear any apt caches the package install left behind. Saves
# ~150 MB on the final image.
apt-get clean
EOF
