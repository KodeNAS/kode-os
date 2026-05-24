# Security policy

## Supported versions

KODE OS is currently in **alpha**. Only the `main` branch receives security fixes during the alpha. Once we tag a stable release line, this section will track which versions are still in the patch window.

| Version | Supported |
|---|---|
| alpha (`main`) | ✅ |
| anything else | ❌ |

## Reporting a vulnerability

**Please don't open public GitHub issues for security vulnerabilities.** Public disclosure before a patch puts every running pebble at risk.

Instead:

1. Email `security@kode-nas.com` *(goes live with the first public alpha — until then, use the private form at https://kode-nas.com/security)*.
2. Include:
   - A description of the issue + the impact you've assessed.
   - Steps to reproduce on a stock KODE OS install.
   - The KODE OS version, CasaOS upstream version, and Raspberry Pi OS version.
   - A proof of concept if you have one.
3. We will acknowledge receipt within **72 hours**.
4. We'll work with you on a fix, then coordinate a public disclosure window (typically **90 days** from the initial report, sooner if the issue is being actively exploited).
5. With your permission, we'll credit you in the release notes for the fix.

## Scope

In scope:
- The KODE OS dashboard UI (`kode-os-ui` repo)
- The OLED display daemon (`pebble/kode_nas_display.py`)
- The install script (`scripts/install.sh`)
- The HTTPS setup script (`scripts/setup-pebble-https.sh`)
- Custom storage formats, default permissions, family-member profile system

Out of scope (please report upstream):
- [CasaOS](https://github.com/IceWhaleTech/CasaOS) backend services — report to IceWhale Technology
- App container images (Immich, Jellyfin, Pi-hole, Home Assistant, etc.) — report to each project
- Docker, the kernel, Raspberry Pi OS — report to the respective upstreams

## What we ask of you

- **Don't run automated scanners against pebbles you don't own.** A pebble is a home appliance on someone's network — DoS or unauthorized access attempts against third parties' devices are not authorized.
- **Don't exploit a vulnerability beyond the minimum needed to confirm it.** Stop and report.
- **Don't publicly disclose before the coordinated window expires.** We will share the timeline up front; we will not stall.

## What you can expect from us

- A response within 72 hours.
- An honest assessment of impact (we won't downplay it to avoid embarrassment).
- A fix on a reasonable timeline, with you in the loop.
- Public credit unless you'd rather stay anonymous.

## Known limitations of the current alpha

The following are documented architectural limitations, not vulnerabilities. They will be addressed before the stable release; please don't report them as new findings:

- **Single-user CasaOS backend.** Family-member accounts are a UI-layer profile system on top of one shared CasaOS admin session. They're labels + per-profile preferences, not real auth boundaries. Anyone with access to the admin session has admin power.
- **`kode_remembered_admin` localStorage.** The admin's password is stored in `localStorage` after first sign-in (see [PRIVACY.md](PRIVACY.md)) so family members can sign in on the same browser later. Trade-off documented in [PRIVACY.md](PRIVACY.md#security-trade-off).
- **Default HTTP.** The default web UI is plain HTTP. Run `scripts/setup-pebble-https.sh` to enable HTTPS via a local Caddy CA. Auto-enabling HTTPS by default is on the roadmap.
- **No 2FA on the admin account.** Planned for the v1 release.

Thanks for keeping KODE OS — and the homes it runs in — safe.
