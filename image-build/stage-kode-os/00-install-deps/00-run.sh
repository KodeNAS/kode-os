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
# mDNS so http://pebble.local/ works on the user's LAN.
systemctl enable avahi-daemon.service

# SMB for the /DATA shares CasaOS exposes.
systemctl enable smbd.service
systemctl enable nmbd.service

# Note: Docker is NOT installed at image-build time. The Debian
# Bookworm repos only ship the older docker.io (~v24), and
# docker-compose-plugin lives behind download.docker.com which
# we'd have to set up + key inside the chroot. Easier + more
# consistent with our v0.1.0-alpha install path: let the
# first-boot service run install.sh, which uses the upstream
# convenience installer (get.docker.com) and lands the same
# Docker version (29.x) we've been testing on the pebble.

# Clear any apt caches the package install left behind. Saves
# ~150 MB on the final image.
apt-get clean
EOF
