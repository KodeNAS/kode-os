# Building the KODE OS image

This builds a flashable SD card image of KODE OS for the Raspberry Pi 5
using [pi-gen](https://github.com/RPi-Distro/pi-gen), the official Pi
Foundation build system. Output is a `.img.xz` file that Raspberry Pi
Imager (or `dd`) can flash directly.

## Requirements

- Linux host — Ubuntu 22.04+ or Debian 12+ recommended
  (macOS users: run inside a Linux VM)
- Docker installed and your user in the `docker` group
- ~20 GB free disk space for a slim build, ~30 GB for `--with-apps`
- 30–60 minutes per build

## Build the slim image (default)

```bash
./build.sh
```

Produces `pi-gen-work/deploy/kode-os-v0.2.0-alpha-pi5.img.xz`
(~1.2 GB compressed). Apps (Immich, Jellyfin, Pi-hole, File Browser,
Home Assistant) are pulled on demand at first-boot — needs internet
during setup.

## Build the bundled image

```bash
./build.sh --with-apps
```

Produces `kode-os-v0.2.0-alpha-pi5-with-apps.img.xz` (~3 GB compressed).
Every supported app's Docker images are pre-pulled into `/var/lib/docker`
inside the image so first-boot can finish without an internet connection.

## Flash to an SD card

Easiest: open Raspberry Pi Imager, choose **"Use custom"**, and point it
at the `.img.xz`. Imager handles the decompression + write.

Or manually:

```bash
xz -dc kode-os-v0.2.0-alpha-pi5.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

(Replace `/dev/sdX` with your card's device. `lsblk` shows the right
one.)

## What the image does on first boot

1. Filesystem expands to fill the SD card.
2. A random wizard token is generated and shown on the MOTD + OLED.
3. The browser-side wizard opens at `http://pebble.local/wizard/<token>`.
4. The user finishes setup (admin account, apps, layout).
5. SSH is enabled (or stays off) per the user's choice in the wizard.

The image ships with **no default password** and SSH disabled. There's
nothing to log into until the wizard creates an account.

## Build internals

`build.sh` clones pi-gen fresh per build (pinned via `PI_GEN_TAG`) into
`./pi-gen-work/` and copies our `stage-kode-os/` into it. Stages 3, 4,
and 5 (desktop / NOOBS) are skipped — we only need Lite + our custom
stage.

Our stage adds:
- 00-install-deps — apt packages KODE OS needs
- 01-install-kode-os — runs a chroot-safe version of `scripts/install.sh`
- 02-firstboot — installs the first-boot systemd service + wizard token
- 03-cleanup — apt cache wipe, `.git` removal, history clear

See [`bootableos.md`](../bootableos.md) for the full design brief.
