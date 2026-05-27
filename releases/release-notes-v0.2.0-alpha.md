# KODE OS v0.2.0-alpha — first bootable image

The big one for v0.2: **no more CLI.** Download an image, flash it with Raspberry Pi Imager, boot the Pi, finish setup in the browser.

> ⚠️ **Still alpha.** APIs, defaults, and the install path will change before v1. Run this on hardware you can re-flash, not on anything you care about.

## What's in the box

A flashable `.img.xz` of KODE OS for the **Raspberry Pi 5**. Boots Pi OS Lite Bookworm 64-bit underneath, runs the KODE OS first-boot service automatically, lands the buyer in a browser-based wizard. ~475 MB compressed, ~2.8 GB on the card.

- **`kode-os-v0.2.0-alpha-pi5-lite.img.xz`** — the default. Pulls Immich/Jellyfin/Pi-hole/File Browser/Home Assistant on demand at first-boot. Needs internet during setup.
- **`.sha256`** sidecars to verify your download.

(A "with-apps" variant that pre-pulls all the Docker images for offline setup is planned for v0.2.1.)

## How to install

### From the image (recommended)

1. Download `kode-os-v0.2.0-alpha-pi5-lite.img.xz` below.
2. Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/), choose **"Use custom"**, point it at the `.img.xz`.
3. **Skip the customization screen** (gear icon) — the image already has hostname `pebble`, no usable login (the wizard creates the admin), SSH off by default. The only thing worth setting via Imager is **Wi-Fi credentials** if you don't have Ethernet handy.
4. Flash, plug into the Pi 5, **plug in Ethernet**, power on.
5. Wait ~3-5 minutes. The OLED (if you have one wired) will show "WAITING FOR NETWORK" → "SETTING UP / Installing CasaOS" → "OPEN IN BROWSER".
6. Open `http://pebble.local/` in any browser on the same network. You'll land directly in the wizard.
7. Set up admin account, pick apps, follow the walkthroughs.

### From the install script (still works)

If you already have Raspberry Pi OS Lite on a Pi and want to layer KODE OS on top:

```bash
git clone https://github.com/KodeNAS/kode-os.git
cd kode-os
sudo ./scripts/install.sh
```

## Verifying the image

Every release ships a `.sha256` sidecar next to the `.img.xz`. After downloading both into the same folder:

```bash
sha256sum -c kode-os-v0.2.0-alpha-pi5-lite.img.xz.sha256
```

Expected output: `kode-os-v0.2.0-alpha-pi5-lite.img.xz: OK`. If you see `FAILED` or `WARNING`, your download is incomplete or tampered — re-download from the release page.

## Upgrading from v0.1.0-alpha

There is no in-place upgrade path. v0.1.0-alpha is a script-installed layer on Pi OS Lite; v0.2.0-alpha is a flashed image with its own first-boot service. To move over:

1. Back up anything under `/DATA` you want to keep (file share, USB drive, another machine).
2. Flash the v0.2 image to a fresh SD card (or wipe your existing one). The image's filesystem layout differs from the script-installed one, so re-flashing is the supported path.
3. Boot, run the new wizard, restore your `/DATA` files.

The `kode-os` device CLI (`sudo kode-os update`) only updates within the same major install path. v0.1 → v0.2 is a re-flash, not an update.

## What's new since v0.1.0-alpha

### The big stuff
- **Bootable image** with everything baked in — built by the new `image-build/` pipeline + GitHub Actions
- **First-boot service** that waits for internet (with a clear OLED message if Ethernet's unplugged), bootstraps CasaOS, mints a random wizard token, and tells the user where to go
- **OLED setup-progress display** — three-line status cards walk the buyer through the install in real time
- **Token-gated wizard URL** so a random LAN visitor can't race the buyer to admin creation
- **`kode-os` device CLI** for updates + uninstall (`sudo kode-os update`, `sudo kode-os uninstall --purge`)
- **Tiered uninstall** (bare / `--purge` / `--wipe-data`)

### Polish
- Brand banner on the README
- Domain references corrected to `kodenas.dev`
- Installer is quieter (KODE banner, not CasaOS noise)
- Node 20 LTS (Node 18 is EOL)

### Fixed (highlights)
- OLED auto-install on a fresh Pi 5 (five cascading bugs around SPI enablement, lgpio, GPIO permissions, systemd device policy, and CWD-dependent FIFO creation)
- `--uninstall` no longer hangs on CasaOS's interactive prompt
- Family-member data survives switching URLs (e.g. `pebble.local` → LAN IP)
- Dashboard layout stops snapping to equal-thirds columns on every refresh
- Wizard URL works when pasted into a browser address bar (it includes `#` now)

Full technical changelog: [CHANGELOG.md](https://github.com/KodeNAS/kode-os/blob/main/CHANGELOG.md).

## Known limitations

- **Pi 5 only — and only the 4 GB model is actively tested.** 8 GB is expected to work but is unverified this release. Pi 4 needs different GPIO handling and lands in v0.3.0.
- **SSH is disabled by default.** Production builds ship with no usable login (the wizard creates the admin account, but SSH itself stays off). Logs and a built-in terminal will surface in the dashboard's Settings panel; until then, debugging on the device means flashing the `--debug-ssh` build, which bakes in your `~/.ssh/id_ed25519.pub` and enables sshd.
- **Ethernet recommended for first boot.** Wi-Fi works if you set the credentials in Raspberry Pi Imager's customization screen before flashing. An in-wizard Wi-Fi step is on the roadmap.
- **No bundled-apps variant yet.** First-boot pulls apps when the buyer selects them, so internet is needed during setup.
- **Wizard token is URL obfuscation, not authentication.** The token file is readable from the LAN, so a determined attacker on the same network could race the buyer to admin creation during the ~5-minute setup window. The real defense is CasaOS's `initialized` flag (also checked). Server-validated tokens are a v0.3.0 item.
- Inherited from v0.1.0-alpha: UI-only family members, default HTTP, no 2FA, upstream CasaOS app catalogue.

## Troubleshooting

**OLED stays dark / shows wrong info during setup**: make sure SPI is enabled (the installer writes `dtparam=spi=on` to `/boot/firmware/config.txt`, but if you've customized the boot partition the change may not stick — verify post-flash).

**"SETUP FAILED" on the OLED**: install.sh hit an actual error (vs network being unplugged, which shows "NO NETWORK"). Flash the `--debug-ssh` build, SSH in, `sudo journalctl -u kode-firstboot -n 100 --no-pager`. Email the log to bugs@kodenas.dev or open a GitHub issue.

**Browser shows `{"message":"Not Found"}` at the wizard URL**: you typed the URL without the `#`. Visit `http://pebble.local/` (no path) — the router auto-redirects you. Or use the full hashed URL: `http://pebble.local/#/wizard/<token>`.

**"This account doesn't exist" on login**: the wizard hasn't completed. Visit `http://pebble.local/` — should redirect to the wizard.

**Lost admin password**: easiest fix is reflash. If you want to keep `/DATA`, SSH in (debug build only), `sudo systemctl stop casaos-user-service casaos-gateway casaos`, `sudo rm /var/lib/casaos/db/user.db`, restart the services — the wizard runs fresh.

## Feedback

- **Bugs:** [GitHub Issues](https://github.com/KodeNAS/kode-os/issues)
- **Security issues:** see [SECURITY.md](https://github.com/KodeNAS/kode-os/blob/main/SECURITY.md)
- **General questions:** open a GitHub Discussion

Thanks for trying it. Real users with real opinions are what makes the path from alpha → v1 actually go somewhere.
