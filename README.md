# KODE OS

> Your own private cloud, in a box the size of a paperback.

**KODE OS** is the operating system that ships on the [KODE NAS pebble](https://kodenas.dev) — a small, beginner-friendly home NAS appliance built around a Raspberry Pi 5. It turns the Pi into a private cloud for your photos, files, and media, without the Synology price tag or the DIY Pi-build complexity.

> ⚠️ **alpha** — this release is for early adopters and developers. APIs, defaults, and the install path will change. Don't run it on hardware you can't reflash.

KODE OS is a fork of [CasaOS](https://github.com/IceWhaleTech/CasaOS) with a customized UI, an OLED display daemon, a first-boot setup wizard, and per-app onboarding walkthroughs designed for non-technical buyers.

---

## What's in the box (the software box)

- **Dashboard** — a tile-based home screen with clock, weather, file shortcuts, family-member profiles, system monitor, network status, photo-of-the-day, and per-app launchers. Six pre-made layouts plus full drag-and-drop customization.
- **First-boot wizard** — language → system check → admin account → pebble name → app picker → layout chooser → install → per-app walkthroughs → done. Designed to take five minutes.
- **App walkthroughs** — guided setup for Immich, Jellyfin, File Browser, Pi-hole, and Home Assistant. Each one opens the app, walks the user through account creation + mobile-app connect + recommended settings + a "you're done" screen.
- **Family-member profiles** — per-profile dashboard layouts, optional per-member passwords, role hierarchy (viewer / editor / admin), all stored locally and synced via the CasaOS user-service custom storage.
- **OLED display daemon** — a Python daemon driving a 2.08" SH1122 OLED over SPI, cycling through hostname/IP, storage, system status, and live app data (Immich photos backed up, Pi-hole ads blocked, Jellyfin now-playing).
- **Auto-deploy + dev tooling** — Stop-hook auto-deploy script for fast iteration (Claude Code integration).

---

## Hardware

| Component | Recommended |
|---|---|
| **Computer** | Raspberry Pi 5 (4 GB) |
| **Storage** | 64 GB+ microSD or M.2 NVMe via Pi 5 HAT |
| **OS** | Raspberry Pi OS Lite (64-bit, Bookworm) |
| **Display** | Waveshare 2.08" SH1122 OLED on SPI0 *(optional)* |
| **Network** | Ethernet preferred (Wi-Fi works too) |

The pebble v1 also ships with a custom case + power button + USB-C PSU — those are hardware-side, not part of this repo.

---

## Install

### One-line install *(coming soon)*

```bash
curl -fsSL https://kodenas.dev/install.sh | sudo bash
```

> The hosted installer URL above will go live with the first public alpha. Until then, use the local installer:

### Local install (from this repo)

On a fresh Raspberry Pi OS Lite install, SSH in and run:

```bash
git clone https://github.com/KodeNAS/kode-os.git
cd kode-os
sudo ./scripts/install.sh
```

The script:
1. Verifies you're on a Raspberry Pi 5 with a supported Raspberry Pi OS release.
2. Installs Docker (if missing) and the upstream CasaOS runtime.
3. Builds the KODE OS UI and overlays it onto the CasaOS web root.
4. Optionally installs the OLED display daemon (auto-detected — requires `dtparam=spi=on` in `/boot/firmware/config.txt`).
5. Prints the dashboard URL.

Open `https://pebble.local` in any browser on the same network and run through the wizard.

### Uninstall

```bash
sudo ./scripts/install.sh --uninstall
```

Removes KODE OS, the OLED daemon, and the CasaOS runtime. Leaves your `/DATA` folder untouched.

---

## Project layout

```
kode-os/
├── README.md          this file
├── LICENSE            Apache 2.0
├── NOTICE             attribution to upstream projects
├── PRIVACY.md         data the OS handles + sends nowhere
├── SECURITY.md        how to report vulnerabilities
├── CONTRIBUTING.md    contribution guide
├── CHANGELOG.md       release notes
├── assets/            branding (logos, favicons, wallpapers)
├── docs/              developer documentation
├── pebble/            OLED daemon + systemd unit + helper scripts
├── scripts/           install, HTTPS setup, deploy helpers
└── kode-os-ui/        (separate repo) the Vue 2 dashboard UI
```

The UI lives in its own repo at [KodeNAS/kode-os-ui](https://github.com/KodeNAS/kode-os-ui) — the installer clones it, builds it, and copies the production assets onto the pebble.

---

## Privacy

KODE OS does not phone home. Read the full [PRIVACY.md](PRIVACY.md). Short version:

- All your data stays on the pebble.
- No analytics. No telemetry. No remote update checks beyond what CasaOS upstream does (and you can opt out).
- The dashboard talks only to the pebble itself + (optionally) the public Open-Meteo weather API for the Weather widget.

---

## Legal

KODE OS is licensed under the [Apache License 2.0](LICENSE).

It is a derivative work of [CasaOS](https://github.com/IceWhaleTech/CasaOS), which is also Apache 2.0 — required attribution lives in [NOTICE](NOTICE) and on the dashboard's About page.

KODE NAS, pebble, and the KODE OS logo + wordmark are trademarks of KODE NAS. The code is freely forkable under Apache 2.0; the branding isn't.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests welcome — please read the bug-report template first.

---

## Status, roadmap, support

- **Status:** alpha, internal testing
- **Issues:** https://github.com/KodeNAS/kode-os/issues
- **Security:** see [SECURITY.md](SECURITY.md)
- **Commercial support / pebble hardware:** https://kodenas.dev
