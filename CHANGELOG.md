# Changelog

All notable changes to KODE OS are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once the project leaves alpha.

## [unreleased]

### Added
- `kode-os` device CLI: `sudo kode-os update` (git pull + re-run installer), `sudo kode-os uninstall` (forwards to `install.sh --uninstall` with `--purge` / `--wipe-data` flags), `kode-os version`. Symlinked into `/usr/local/bin/kode-os` by the installer; resolves its real location with `readlink -f` so it works through the symlink.
- Tiered uninstall in `scripts/install.sh`: bare `--uninstall` removes the KODE layer + CasaOS runtime, `--purge` additionally removes KODE-installed Docker containers + images + the Docker API override + the kode user, `--wipe-data` additionally deletes `/DATA` (requires typing `WIPE` to confirm; `--yes` skips for automation).
- Brand banner image (`assets/banner.png` + source SVG) at the top of the README. Tagline: "Your own private cloud in 5 minutes."
- 8 GitHub topics + repo homepage on `KodeNAS/kode-os` for discoverability.

### Changed
- README domain references swapped from `kode-nas.com` → `kodenas.dev` (the actual owned domain).
- Installer closing banner now points users at `sudo kode-os update` / `sudo kode-os uninstall` instead of bare script paths.
- Installer bumped from Node 18 → Node 20 LTS (Node 18 reached EOL April 2025; NodeSource was printing a deprecation banner on every install).
- Installer is quieter: upstream CasaOS install output redirected to `/tmp/kode-os-casaos-install.log` so the KODE banner is the first + last thing the buyer sees.

### Fixed
- `--uninstall` no longer hangs on `casaos-uninstall`'s interactive y/N prompt. Now pipes `yes y |` into the helper and caps the call with a 90-second `timeout`; falls back to manual teardown of casaos-* services + binaries + `/etc/casaos` + `/var/lib/casaos` + `/usr/share/casaos` if the helper still misbehaves.
- Family-member data now survives switching URLs. Signing in as admin on a new origin (e.g. switching from `http://pebble.local` to the LAN IP, which the browser treats as a separate origin with empty localStorage) hydrates `kode_family_members` + `kode_user_roles` from server-side custom storage into the new origin's localStorage. Without this fix, family tiles were empty and the signup dupe-check would let someone re-claim an existing name on the new URL.
- OLED auto-install on a fresh Pi 5 — five compounding bugs were keeping the SH1122 dark even when wired correctly:
  1. `dtparam=spi=on` isn't in Pi OS Lite's default `config.txt`, so `/dev/spidev0.0` never appeared. Installer now writes it (uncommenting any pre-included line or appending a tagged one) and prompts for a reboot.
  2. `kode-os update` short-circuited with "Already up to date" when the repo was unchanged, skipping the reconverge that would have picked up new hardware. Now always re-runs the installer after the fetch.
  3. `systemctl list-unit-files | grep -q casaos-gateway` was a `pipefail` foot-gun: `grep -q` SIGPIPE'd systemctl mid-write, flipped the pipeline exit, and re-installed CasaOS every run (failing on transient gateway-tarball download blips). Replaced with `command -v casaos-gateway`.
  4. The OLED daemon needs `python3-rpi-lgpio` (a chardev RPi.GPIO shim that works on the Pi 5 RP1 chip) + the `kode` user in `gpio`/`spi` groups + `SupplementaryGroups=` + `DeviceAllow=/dev/gpiochip0` + `GPIOZERO_PIN_FACTORY=rpigpio` in the systemd unit. Installer + unit now provide all of that.
  5. `lgpio`'s C library `mkfifo`'s its notification FIFO in CWD at import time; systemd default `CWD=/` + `ProtectSystem=strict` made that silently fail. Unit now sets `WorkingDirectory=/tmp` (already in `ReadWritePaths`).

## [0.1.0-alpha] — 2026-05-24

First publishable alpha. Forked from CasaOS 0.4.5.

### Added
- Custom dashboard (Vue 2): six pre-made layouts, drag-and-drop widget canvas, per-profile layout buckets.
- First-boot setup wizard: system check → admin account → pebble name → app picker → layout chooser → install → per-app walkthroughs → done.
- Per-app walkthroughs for Immich, Jellyfin, File Browser, Pi-hole, Home Assistant — each follows a five-step pattern (open app → in-app setup → connect mobile/network → extra settings → done).
- Family-member profile system: name + password (SHA-256 hashed locally), role (viewer/editor/admin), per-profile dashboard layout namespaced by `kode_p_<slug>_*` localStorage keys. UI-only — rides on the underlying CasaOS admin token.
- Profile switching with password verification, role-rank gating (lower-rank can't switch up), three-dots admin menu for role change + remove.
- Single unified Login form: tries admin auth first, falls back to family-member match. Signup creates viewer-role accounts.
- OLED display daemon (`pebble/kode_nas_display.py`) driving a Waveshare 2.08" SH1122 over SPI0 — cycles hostname/IP, storage, system status, app data (Immich, Pi-hole, Jellyfin) every 3 seconds.
- KODE-built guided tour (`KodeTour.vue`) replacing driver.js — spotlight + 4-panel dim overlay, layout-aware per-template intros, scroll-into-view for offscreen widgets, `display: contents` fallback measurement.
- Hint help button + hover-tip mode for first-time users.
- App Guides side panel (replayable walkthroughs from the dashboard).
- Auto-creates `/DATA/{Photos,Movies,Shows,Videos,Documents,Music,Downloads,Backups}` and Samba-shares them.
- `scripts/install.sh` — one-line install onto a fresh Raspberry Pi OS Lite.
- `scripts/setup-pebble-https.sh` — optional HTTPS via Caddy `tls internal`.
- Factory reset modal with type-WIPE confirmation, per-API timeouts, fallback to local-only wipe if backend calls hang.
- "Add a device" wizard (phone / computer / smart TV) with SMB instructions, Immich app QR, Jellyfin app QR.

### Changed
- Replaced upstream CasaOS branding throughout the UI with KODE OS / KODE NAS / pebble.
- Brand color, typography (IBM Plex Sans), wallpaper, console banner, terminal panel title.
- Jellyfin compose injects `/DATA/Movies`, `/DATA/Shows`, `/DATA/Music`, `/DATA/Photos` bind mounts so the buyer can point Jellyfin libraries at the same paths they see in the file browser.
- Pi-hole compose injects the buyer's KODE password as the web admin password — same credentials everywhere.

### Removed
- CasaOS Discord/GitHub/Share/Feedback ContactBar links.
- Upstream Advanced-mode dashboard (the OS reads as a single appliance UI).
- 7 orphan Vue components carried over from CasaOS that nothing imports.
- 8 unused npm dependencies (`driver.js`, `@fontsource/roboto`, `docx-preview`, `ejs`, `tiptap-markdown`, `vue-demi`, `yargs-parser`, plus the obsolete tour library).
- LanguageStep from the wizard (browser locale + post-install user settings cover it).
- Dev wipe button from the wizard shell (Factory reset lives in Settings).

### Fixed
- Tour spotlight no longer renders at top-left on widget tiles (root cause: `display: contents` on widget-slot wrappers — now falls back to measuring the first sized descendant).
- "Settings & shutdown" tour step anchors to the cog button, not the whole topbar.
- Topbar reveals + repositions cleanly during the corresponding tour step.
- Family-member sign-in works after logout via remembered admin creds.
- AccountPanel displays the active family member's name + role, not the underlying admin.
- Network and SystemInfo widgets throttled (2s→5s and 5s→10s) for less Pi 5 idle load.

### Known limitations
- Family members are a UI-only profile system. CasaOS upstream is single-user; a real Linux user-per-family-member system needs a forked user-service and is on the v1 roadmap.
- Default HTTP only. Run `scripts/setup-pebble-https.sh` for HTTPS (Caddy + per-pebble local CA).
- No 2FA on the admin account yet.
- App store still pulls from the CasaOS upstream catalogue. KODE-branded app store is on the v1 roadmap.

---

[unreleased]: https://github.com/KodeNAS/kode-os/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/KodeNAS/kode-os/releases/tag/v0.1.0-alpha
