# Changelog

All notable changes to KODE OS are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once the project leaves alpha.

## [unreleased]

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

[unreleased]: https://github.com/kode-nas/kode-os/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/kode-nas/kode-os/releases/tag/v0.1.0-alpha
