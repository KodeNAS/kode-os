# Changelog

All notable changes to KODE OS are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once the project leaves alpha.

## [unreleased]

## [0.2.0-alpha] — 2026-05-27

**The flash-and-boot release.** No more cloning + `sudo ./scripts/install.sh` — download an `.img.xz` from the GitHub release, flash with Raspberry Pi Imager, boot the Pi, finish setup in the browser. The install script still works for anyone who wants to layer KODE OS onto an existing Pi OS install.

Bundles everything between `v0.1.0-alpha` and now, including the v0.1.x bug-fix work (`kode-os` CLI, tiered uninstall, OLED auto-install, README polish) plus the new bootable-image pipeline.

### Added

#### Bootable image
- **Flashable image** built with [pi-gen](https://github.com/RPi-Distro/pi-gen). One `.img.xz` (~475 MB compressed, ~2.8 GB uncompressed) flashable with Raspberry Pi Imager. Boots, runs a first-boot service, completes setup over the LAN with zero CLI interaction. Pi 5 only this release; Pi 4 lands in v0.3.0.
- **`image-build/` pipeline** in the repo: `./build.sh` clones pi-gen, layers our `stage-kode-os/` custom stage on top of Pi OS Lite Bookworm arm64, pre-builds the UI natively (saves ~30 min vs qemu-user emulation), bakes everything into the image. `--debug-ssh` opt-in flag for SSH-enabled debug builds with a baked-in pubkey; default release builds ship SSH off + no usable password.
- **First-boot service** (`kode-firstboot.service`) runs once on first power-on: expands the root filesystem to fill the SD card, waits for real internet (not just systemd's `network-online.target` which lies if the cable is unplugged), runs `install.sh` to bootstrap CasaOS, generates a 32-hex-char random wizard token + writes it to MOTD + OLED + a web-accessible file, starts the OLED daemon. Removes its own `.firstboot-pending` marker on success so subsequent boots skip the work.
- **OLED setup-progress display** during first-boot. New status-card mode in `kode_nas_display.py` reads `/run/kode-os/oled-status` (set by `scripts/oled-status` helper or directly by firstboot.sh) — present → overrides the normal hostname/storage rotation with a three-line title/subtitle/footer card. Buyers see "WAITING FOR NETWORK / Plug in Ethernet / retrying in 10s" instead of a dark display, "SETTING UP / Installing CasaOS / step 2 of 3 (~2 min)" during install, "OPEN IN BROWSER / pebble.local / /#/wizard/<token>" when ready.
- **Token-gated wizard URL** (`/#/wizard/<token>`). New `kode-os-ui` route + router guard: validates the URL token against `/.wizard-token` AND checks that CasaOS reports `initialized: false` before allowing the welcome wizard to render. Bare `http://pebble.local/` auto-redirects to the token URL (fetches the file from the browser side). v0.1.0-alpha script-installs (no token file) fall through to the legacy `/welcome` path for backward compat. Threat-model caveat: the token file is fetchable from the LAN, so this is URL obfuscation rather than authentication — the real gate against unauthorized admin creation is CasaOS's `initialized` state, also checked in the guard.
- **`kode-os` device CLI** symlinked into `/usr/local/bin/kode-os`:
  - `sudo kode-os update` → `git fetch` + ff-merge + re-run `install.sh` (always reruns; doesn't short-circuit on "already up to date" so it picks up environment changes like fresh hardware).
  - `sudo kode-os uninstall [--purge] [--wipe-data]` → forwards to `install.sh --uninstall` with the requested tier.
  - `kode-os version` → `git describe` output.
- **Tiered uninstall** in `scripts/install.sh`: bare `--uninstall` removes the KODE layer + CasaOS runtime; `--purge` additionally removes KODE-installed Docker containers + images + the Docker API override + the kode user; `--wipe-data` additionally deletes `/DATA` (requires typing `WIPE` to confirm; `--yes` skips for automation).
- **GitHub Actions workflow** (`.github/workflows/build-image.yml`) auto-builds the image on tag pushes + uploads `.img.xz` + `.sha256` to the Release as a draft prerelease. `workflow_dispatch` for smoke tests; `--with-apps` input bakes a (deferred) bundled-apps variant in.
- **Brand banner** at the top of the README (`assets/banner.png`). Tagline: "Your own private cloud in 5 minutes."
- **8 GitHub topics + repo homepage** on `KodeNAS/kode-os` for discoverability.

### Changed
- **`scripts/install.sh` is now BOTH** the live-system install path (v0.1.x) AND the first-boot bootstrap script run from the image (v0.2.0). Same script; the chroot-friendly subset runs at image-build time, the rest runs on first power-on.
- README domain references swapped from `kode-nas.com` → `kodenas.dev` (the actual owned domain).
- Installer closing banner now points users at `sudo kode-os update` / `sudo kode-os uninstall` instead of bare script paths.
- Installer bumped from Node 18 → Node 20 LTS (Node 18 reached EOL April 2025).
- Installer is quieter: upstream CasaOS install output redirected to `/tmp/kode-os-casaos-install.log` so the KODE banner is the first + last thing the buyer sees.

### Fixed
- `--uninstall` no longer hangs on `casaos-uninstall`'s interactive y/N prompt. Pipes `yes y |` into the helper, caps with a 90-second `timeout`, manual fallback if it still misbehaves.
- Family-member data survives switching URLs. Admin login on a new origin (e.g. `http://pebble.local` → LAN IP) now hydrates `kode_family_members` + `kode_user_roles` from server-side custom storage into the new origin's localStorage.
- OLED auto-install on a fresh Pi 5 — five cascading bugs were keeping the SH1122 dark even when wired correctly:
  1. `dtparam=spi=on` isn't in Pi OS Lite's default `config.txt`, so `/dev/spidev0.0` never appeared. Installer writes it now (uncommenting any pre-included line or appending a tagged one).
  2. `kode-os update` used to short-circuit with "Already up to date" when the repo was unchanged, skipping the reconverge that would have picked up new hardware. Now always re-runs the installer after the fetch.
  3. `systemctl list-unit-files | grep -q casaos-gateway` was a `pipefail` foot-gun: `grep -q` SIGPIPE'd systemctl mid-write, flipped the pipeline exit, and re-installed CasaOS every run. Replaced with `command -v casaos-gateway`.
  4. The OLED daemon needs `python3-rpi-lgpio` (a chardev RPi.GPIO shim that works on the Pi 5 RP1 chip) + the `kode` user in `gpio`/`spi` groups + `SupplementaryGroups=` + `DeviceAllow=/dev/gpiochip0` + `GPIOZERO_PIN_FACTORY=rpigpio` in the systemd unit. All in place now.
  5. `lgpio`'s C library `mkfifo`'s its notification FIFO in CWD at import time; systemd default `CWD=/` + `ProtectSystem=strict` made that silently fail. Unit now sets `WorkingDirectory=/tmp`.
- Dashboard layout no longer snaps to even-thirds columns on every refresh. `loadWeights()` now falls back to the mode's authored defaults (`[0.75, 1.75, 0.7]` for Beginner) instead of `Array(count).fill(1)` when the weights file is missing, and `resetLayoutToDefault()` persists the new state rather than only updating in-memory.
- Wizard URL printed in MOTD/OLED now includes the `#` for Vue's hash-routed router. Pre-fix, pasting the URL into a browser gave a casaos-gateway 404 because `/wizard/<token>` was treated as a literal static-file path.
- Pi-gen build pipeline: 20 separate fixes across `build.sh` + `pi-gen-config` + the chroot stage to actually produce a flashable image on a clean Ubuntu CI runner. (Each one shipped as its own commit; see git log for the full saga.)

### Known limitations
- **Pi 5 only.** Pi 4 support requires different GPIO + lgpio handling; landing in v0.3.0.
- **Ethernet required for first boot.** Wi-Fi setup via Raspberry Pi Imager's customization screen (Ctrl+Shift+X before flashing) — an in-wizard Wi-Fi step is v0.3.0 work.
- **No bundled-apps variant yet.** The slim image (475 MB) pulls Immich/Jellyfin/Pi-hole/etc. at first-boot. The `--with-apps` flag exists in `build.sh` but the Docker pre-pull logic lands in v0.2.1.
- **Wizard token is URL obfuscation, not auth.** A LAN attacker who reads `/.wizard-token` could race the buyer to admin creation during the few-minute setup window. The CasaOS `initialized` flag is the real gate. Server-validated tokens land in v0.3.0.
- Inherited from v0.1.0-alpha: UI-only family members (single CasaOS admin underneath), default HTTP, no 2FA, upstream CasaOS app catalogue. All on the v1.0 roadmap.

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

[unreleased]: https://github.com/KodeNAS/kode-os/compare/v0.2.0-alpha...HEAD
[0.2.0-alpha]: https://github.com/KodeNAS/kode-os/releases/tag/v0.2.0-alpha
[0.1.0-alpha]: https://github.com/KodeNAS/kode-os/releases/tag/v0.1.0-alpha
