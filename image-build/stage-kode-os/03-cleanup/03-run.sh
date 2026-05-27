#!/bin/bash -e
#
# 03-cleanup — last-mile shrink + housekeeping before image export.
#
# Runs after every previous stage has finished, before pi-gen
# packages the rootfs into the final .img.xz. Anything we delete
# here doesn't ship to the buyer; anything we leave does.
#
# Heuristic: keep what the running OS needs at boot, remove
# everything that's just build-time residue (apt caches, .git
# trees, log files, history). Don't touch /var/log structure —
# truncate files instead so log rotation + journald can write into
# the existing dirs at first boot.

on_chroot << 'EOF'
set -e

# apt: ~150 MB of downloaded .deb files we no longer need.
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*

# Truncate every existing log file to 0 bytes (keeps the file so
# the rsyslog / journald / casaos-gateway file handles stay valid)
# instead of deleting them. Skips dirs + symlinks.
find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true

# Journald journal files — these accumulate boot history from
# pi-gen's own stages. Wipe so the buyer's first-boot logs start
# clean.
rm -rf /var/log/journal/*
rm -rf /run/log/journal/* 2>/dev/null || true

# /tmp + /var/tmp from build-time noise (qemu, apt scratch, etc).
rm -rf /tmp/*           /tmp/.[!.]*           2>/dev/null || true
rm -rf /var/tmp/*       /var/tmp/.[!.]*       2>/dev/null || true

# Bash history — root and any user accounts pi-gen may have
# touched. Buyer should see an empty history on first ssh.
: > /root/.bash_history 2>/dev/null || true
rm -f /root/.viminfo /root/.lesshst /root/.wget-hsts 2>/dev/null || true
if id kode >/dev/null 2>&1; then
  : > /home/kode/.bash_history 2>/dev/null || true
  rm -f /home/kode/.viminfo /home/kode/.lesshst /home/kode/.wget-hsts 2>/dev/null || true
fi
EOF

# Run on the host side (no chroot needed) — strip .git from the
# kode-os source we copied into /opt/kode-os. That's ~5-15 MB
# saved and avoids shipping per-commit history with the image.
# `|| true` because the dir might not exist if 01-install-kode-os
# didn't run for some reason.
find "${ROOTFS_DIR}/opt/kode-os" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true

# Belt + braces: drop any node_modules that might have slipped in
# (build.sh rsync excludes it, but a future-me edit could break
# that and this catches it).
find "${ROOTFS_DIR}/opt/kode-os" -name node_modules -type d -prune -exec rm -rf {} + 2>/dev/null || true
