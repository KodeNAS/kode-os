#!/bin/bash -e
# pi-gen stage prerun hook. Copies the previous stage's rootfs into
# this stage's ROOTFS_DIR so we can layer on top. Boilerplate from
# pi-gen's own stage scripts.
if [ ! -d "${ROOTFS_DIR}" ]; then
  copy_previous
fi
