# KODE OS v0.1.0-alpha

The first public release of **KODE OS** — a friendly Linux distribution for Raspberry Pi 5, built on top of CasaOS.

> ⚠️ **Alpha quality.** APIs, defaults, and the install path will change before v1. Run this on hardware you can re-flash, not on anything you care about.

## What this is

KODE OS turns a Raspberry Pi 5 into a small, beginner-friendly home server. It ships with a custom dashboard, a guided first-boot wizard, family-member profiles, and an OLED display daemon.

Read the full overview at <https://kodenas.dev/os>.

## How to install

This release is install-script based — there's no flashable image yet (coming in v0.2).

On a fresh Raspberry Pi OS Lite install (Bookworm 64-bit):

```bash
git clone https://github.com/KodeNAS/kode-os.git
cd kode-os
sudo ./scripts/install.sh
```

Then open `https://pebble.local` in any browser on the same network.

**Full installation guide:** <https://docs.kodenas.dev/os/installation/>

## What works

- One-line install on a fresh Pi 5
- Dashboard with weather, clock, system stats, and app launchers
- First-boot setup wizard with user-style picker (Beginner / Normal / Developer)
- App walkthroughs for Immich, Jellyfin, File Browser, Pi-hole, Home Assistant
- OLED display daemon (Waveshare SH1122, optional)
- Tiered uninstall (`--uninstall`, `--uninstall --purge`, `--uninstall --wipe-data`)

## What doesn't work yet

- Flashable SD card image (v0.2 target)
- Full family-profile per-user password enforcement
- Multi-language support
- Automatic backups
- Wi-Fi setup from the dashboard (use Pi Imager for now)

## Known issues

- Initial Docker pull can take 5–10 minutes on slower networks. Be patient.
- Hangs during install usually mean you're not on Raspberry Pi OS Lite Bookworm 64-bit.

## Feedback

- **Bugs:** <https://github.com/KodeNAS/kode-os/issues>
- **General questions:** open a Discussion on GitHub
- **Security issues:** see [SECURITY.md](https://github.com/KodeNAS/kode-os/blob/main/SECURITY.md)

Thanks for trying it.
