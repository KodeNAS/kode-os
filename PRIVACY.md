# Privacy policy

> Last updated: 2026-05-27 · Applies to: KODE OS v0.2.0-alpha

KODE OS is built to keep your data on your own pebble. This document describes exactly what the OS collects, where it sends information, and what you can turn off.

## TL;DR

- The pebble is yours. Your photos, files, account names, and app data live on its disk and never leave unless you explicitly send them somewhere (a share link, a phone-app sync, a cloud-backup app you install).
- **No analytics.** KODE OS does not include any third-party analytics, advertising, or behavioral tracking.
- **No remote telemetry from KODE NAS.** We do not collect crash reports, usage stats, or fingerprints from your pebble.
- A small number of features make outbound network calls — listed below. All are opt-in or replaceable.

---

## What stays on the pebble

The following all live on the pebble's disk and are never transmitted off it by KODE OS:

- Your KODE OS admin account name, hash, and avatar
- Family-member names, role assignments, and locally-hashed passwords (SHA-256, stored in your CasaOS custom storage and mirrored to the browser's `localStorage` for sign-in pre-population)
- The pebble's hostname, dashboard layout, widget settings, wallpaper choice, language
- Files under `/DATA` and its subfolders
- App-specific data for Immich, Jellyfin, Pi-hole, Home Assistant, and any other apps you install — under `/DATA/AppData/<app>/`
- Logs in `journalctl` and Docker container logs

## What goes off the pebble (and why)

| Outbound | Purpose | Opt out |
|---|---|---|
| `weatherapi-free.open-meteo.com` | Weather widget — current conditions + forecast for the city you set | Remove the Weather widget from your dashboard |
| `*.docker.io` and the image registries each app pulls from | Downloading container images when you install an app | Don't install apps |
| App-specific traffic (Immich-mobile → your pebble, Jellyfin client → your pebble, etc.) | These run on YOUR network and go to your pebble, not to KODE NAS | Don't install/connect the apps |
| `casaos.io` (upstream update check) | Inherited from CasaOS upstream — checks for new CasaOS releases | Disable in Settings → System Updates (CasaOS panel) |
| `github.com` + `get.docker.com` (first boot only) | First-boot bootstraps CasaOS (downloads upstream binaries) and Docker (downloads convenience installer). Doesn't run again — the `.firstboot-pending` marker is removed on success. | Use the future "with-apps" bundled image variant when it ships in v0.2.1 — that one ships the dependencies pre-pulled. |

That's it. There is no other outbound traffic introduced by KODE OS.

## Cookies + local storage

The dashboard sets the following in your browser's `localStorage`:

- `access_token`, `refresh_token` — your CasaOS auth session
- `kode_active_member` — which family-member profile is active
- `kode_family_members`, `kode_user_roles` — local mirror of the family-member list + role assignments (the source of truth is server-side CasaOS custom storage; the local mirror lets the dashboard render without a round-trip every load and survives the browser working offline against the pebble)
- `kode_columns_layout_v2`, `kode_columns_weights_v1`, `kode_column_count_v1`, widget settings — your dashboard layout
- `kode_chosen_template_v1` — which pre-made layout you picked
- `kode_tour_seen`, `kode_hint_mode` — onboarding state
- `wallpaper`, `lang`, `version`, `expires_at`, `user` — display preferences + session metadata

None of this is transmitted to KODE NAS or any third party. To clear it, sign out and clear the browser's local storage for `http://pebble.local`. The Factory Reset flow in Settings clears it too.

## Wizard token

On first boot, KODE OS generates a 32-hex-char random token and writes it to two places:

- `/opt/kode-os/.wizard-token` — mode 0600, root-only, the canonical copy
- `/var/lib/casaos/www/.wizard-token` — mode 0644, web-accessible, read by the UI router to validate the wizard URL

The web-accessible copy means anyone who can reach the dashboard on your LAN can read the token. This is **URL obfuscation, not authentication** — the real protection against unauthorized admin creation is CasaOS's `initialized` flag (the wizard refuses to render once an admin exists). The threat model assumes a trusted home LAN; if you're worried about a hostile network during the ~5 minute setup window, set up the pebble offline first.

Server-validated tokens (so the token is never readable from outside root) are a v0.3.0 item.

## Children's privacy

KODE OS is intended for adult buyers. The OS does not knowingly collect data from anyone, including children. The family-member feature is a profile system for shared home use; it does not collect or transmit minors' data anywhere.

## Apps you install

Apps installed via the KODE OS app store run as standard Docker containers on your pebble. Their privacy practices are their own — read each one's documentation before deciding to install them. KODE OS does not modify what they do.

## Changes to this policy

When this policy changes materially, the new version will land in this file (`PRIVACY.md`) in the kode-os repository and the dashboard will surface a one-line notice on next login.

## Contact

For privacy questions or to report a concern: open an issue at https://github.com/KodeNAS/kode-os/issues or email privacy@kodenas.dev.
