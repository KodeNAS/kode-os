# CLAUDE.md

Documentation for Claude Code (and any other coding assistant) working in this repo. Updated 2026-05-24.

## What this project is

**KODE OS** is a fork of [CasaOS](https://github.com/IceWhaleTech/CasaOS) for the **KODE NAS pebble v1** — a Raspberry Pi 5 home NAS appliance aimed at non-technical buyers. The product competes with Synology and iCloud, NOT with DIY Pi builds. Anything that requires Linux knowledge to use is a bug.

Current state: **v0.2.0-alpha** (first bootable image release), both repos published at https://github.com/KodeNAS.

For full product context, branding kit, and roadmap → [docs/CLAUDE_CODE_BRIEF.md](docs/CLAUDE_CODE_BRIEF.md). Read it before making product decisions.

## Two repos

| Path | Repo | Role |
|---|---|---|
| `/home/olicz/Documents/KODE OS/` | `KodeNAS/kode-os` | installer, OLED daemon, branding, legal, docs (THIS file lives here) |
| `/home/olicz/Documents/KODE OS/kode-os-ui/` | `KodeNAS/kode-os-ui` | Vue 2 dashboard UI (separate git tree, gitignored from the parent) |

The kode-os-ui repo's UI gets cloned + built + overlaid onto `/var/lib/casaos/www/` on the pebble by `scripts/install.sh`. Day-to-day during development, `scripts/auto-deploy.sh` (a Stop-hook) does the same thing on every turn.

## Hardware target

- **Pi 5 (4 GB)** running Raspberry Pi OS Lite 64-bit + Docker + CasaOS upstream
- Hostname `pebble`, primary user `kode`
- Dev pebble lives at `kode@192.168.0.220` (not `pebble.local` — mDNS isn't reliable on the dev network)
- Optional Waveshare 2.08" SH1122 OLED on SPI0 (`/dev/spidev0.0`)
- SSH key + NOPASSWD sudoers for the deploy + the `pebble-screen.service` line. Other sudo commands (e.g. `kode-nas-display.service`) currently DO need a password.

## Project layout (root)

```
KODE OS/
├── README.md, LICENSE, NOTICE, PRIVACY.md, SECURITY.md,
│   CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG.md
├── assets/        branding (logos, favicons, wallpapers — keep these)
├── docs/          dev brief + future design docs
├── pebble/        OLED daemon + restart helper + systemd unit
├── scripts/       install.sh, setup-pebble-https.sh, auto-deploy.sh
├── kode-os-ui/    separate git repo, gitignored here
├── .claude/       hook + settings (gitignored, machine-local)
└── .gitignore
```

## Auto-deploy hook (important)

There's a **Stop hook** in `.claude/settings.json` that runs `scripts/auto-deploy.sh` at the end of every Claude turn. It:

1. Detects what changed (mtime-stamped in `.claude/.auto-deploy.stamps`).
2. If anything under `kode-os-ui/src|public|scripts|pi/`, `package.json`, `vue.config.js`, `babel.config.js` → `pnpm build && deploy-to-pi.sh`.
3. If `kode_nas_display.py` → scp + restart the OLED daemon via `pebble/restart-display.sh`.
4. If `pi/nas_screen.py` → run `kode-os-ui/scripts/deploy-screen-to-pi.sh`.
5. Auto-commits any dirty files in `kode-os-ui` with `chore: auto-commit from claude session`.

**Don't run `pnpm build` or `deploy-to-pi.sh` manually** — the hook handles it. If a change didn't reach the pebble, check that the hook ran first (look for `[auto-deploy]` lines in the Stop hook output) before suspecting a deploy bug. Stale stamps can also cause skips — `rm .claude/.auto-deploy.stamps` forces full re-deploy.

The parent repo (this one) has nothing to auto-commit (only the kode-os-ui sub-repo). Parent commits are manual.

## Common commands

```bash
# Manual UI build (rarely needed — hook does this)
cd kode-os-ui && pnpm build

# Manual deploy (rarely needed — hook does this)
cd kode-os-ui && ./scripts/deploy-to-pi.sh

# OLED daemon restart on the pebble
ssh kode@pebble.local "/home/kode/restart-display.sh"

# Live container check
ssh kode@pebble.local "docker ps --format '{{.Names}}\t{{.Status}}'"

# Production install end-to-end (on a fresh Pi)
git clone https://github.com/KodeNAS/kode-os.git
cd kode-os && sudo ./scripts/install.sh
```

## Architecture quick-reference

### UI (`kode-os-ui/`)

- **Vue 2 + Bulma + Buefy**, build via vue-cli (`vue.config.js`)
- **Custom dashboard** = `src/views/BeginnerDashboard.vue`. Drag-and-drop grid; six pre-made layouts in `src/service/dashboardTemplates.js`. Per-profile layout buckets keyed by `kode_p_<slug>_*` in localStorage.
- **First-boot wizard** = `src/views/Welcome.vue` → step components in `src/components/firstboot/steps/`. App walkthroughs in `src/components/firstboot/walkthroughs/`.
- **Family profiles** = `src/components/beginner/FamilyTile.vue` + `AddUserModal.vue` + `SignupModal.vue`. SHA-256 hashed passwords in custom storage + localStorage mirror.
- **Login** = `src/views/Login.vue` (unified admin + family-member auth).
- **Tour** = `src/components/KodeTour.vue` + `src/service/tour.js`. Custom (replaced driver.js) — spotlight via 4-panel dim overlay; falls back to first sized descendant when matched element has `display: contents`.
- **API plumbing** = `src/service/*.js` (one file per CasaOS endpoint group). `service.js` configures axios with auth interceptor.

### Pebble (`pebble/`)

- `kode_nas_display.py` — OLED daemon. Drives the SH1122 over SPI0. 3-second rotation between hostname/IP, storage, system status, app data. Configurable in-place (no rebuild needed) — restart via `restart-display.sh`.
- `kode-nas-display.service` — systemd unit. Drops privileges to user `kode`, restricted device access (`/dev/spidev0.0` only).
- `restart-display.sh` — wrapper that pkills the daemon then double-forks a fresh one. Lives on the pebble at `/home/kode/restart-display.sh`. Lives here in the repo so `install.sh` can deploy it, and `auto-deploy.sh` re-scp's it on every daemon change.

### Install path (`scripts/install.sh`)

7 phases: prereqs → Docker → CasaOS upstream → Node 18 + pnpm → clone-build-overlay kode-os-ui → OLED daemon (hardware-gated) → print access info. `--uninstall`, `--skip-casaos`, `--no-oled`, `--version REF` flags.

## Hard rules

These come from Apache 2.0 compliance, the brand brief, and accumulated user feedback. Don't violate without explicit consent:

- **Never delete the upstream `LICENSE` or `NOTICE` files.** Apache 2.0 requires them for derivative works.
- **Never remove the CasaOS attribution** from the dashboard About page or `BrandBar.vue`. Legally required + honest.
- **Never change `/v1/...` or `/v2/...` API endpoint paths in `kode-os-ui`.** They map to CasaOS upstream services.
- **Never add telemetry, analytics, or remote update checks beyond what CasaOS upstream already does.** See [PRIVACY.md](PRIVACY.md). The "no telemetry" commitment is a product positioning pillar.
- **Never use icons that don't exist in the casa pack.** Verify against `find build/sysroot/var/lib/casaos/www -name '*.js' -exec grep -hoE 'casa-[a-z][a-z0-9\-]+' {} \; | sort -u`. Wrong icon names render as blank circles silently — this has caused multiple "X feature doesn't work" reports.
- **Never push to GitHub without the user asking.** Commits happen freely via the auto-deploy hook; pushes are manual.

## Soft conventions

- **Beginner mode hides aggressively** — when in doubt, hide anything counter-intuitive from KODE OS Beginner mode. Surface borderline cases as user decisions instead of guessing.
- **Comments explain WHY, not WHAT.** Code already says what. Especially needed when the why isn't obvious — past incident, hidden constraint, workaround for a third-party quirk.
- **Brand colour** `#2D5F4E` (deep forest teal). Apply at the source level, not via overrides.
- **Typography** IBM Plex Sans (Google Fonts). Loaded in `public/index.html`.
- **Use Pi 5 IP for SSH** in scripts/examples — `kode@192.168.0.220` is reliable, `pebble.local` sometimes isn't.
- **Conventional commits** for kode-os-ui (`feat:`, `fix:`, `chore:`, `docs:`). Auto-deploy hook prefixes its own with `chore: auto-commit from claude session`.

## Known limitations (alpha)

- Family members are UI-only. CasaOS backend is single-user; the family system rides on the admin's CasaOS session token. Real Linux-user-per-member is v1 roadmap.
- Default HTTP. `scripts/setup-pebble-https.sh` installs Caddy with `tls internal` for per-pebble local CA HTTPS.
- No 2FA. v1 roadmap.
- App store is upstream CasaOS catalogue. KODE-branded store is v1 roadmap.
- The `casaos-gateway` Go server doesn't honour `Accept-Encoding: gzip` on static assets, so pre-compressed `.gz` files in the build aren't served. Skip the compression-webpack-plugin until the gateway gains support.

## Where to look first when X breaks

- **Spotlight on tour doesn't appear** → `KodeTour.vue` reposition; check if matched element has `display: contents` (then it returns 0×0 rect and falls back to first sized descendant).
- **"This account doesn't exist" on family-member login** → `kode_remembered_admin` missing from localStorage; admin needs to sign in once on this browser first.
- **UI changes not reaching the pebble** → check the Stop hook ran. `[auto-deploy]` lines should appear. If not, `rm .claude/.auto-deploy.stamps` forces re-deploy.
- **OLED daemon stuck / not updating** → `ssh kode@pebble.local "ps aux | grep kode_nas_display"`. If multiple, kill them all + run `/home/kode/restart-display.sh`.
- **App icon missing in walkthrough/guides** → wrong casa icon name. Grep the built bundle for valid names.
- **Casaos returning 401 to UI** → admin token expired. Login flow re-mints via `kode_remembered_admin`. If THAT fails, full re-login required.

## When stuck or unsure

- **Read [docs/CLAUDE_CODE_BRIEF.md](docs/CLAUDE_CODE_BRIEF.md)** for product context and roadmap.
- **Read [CHANGELOG.md](CHANGELOG.md)** for what shipped + known limits.
- **Ask the user** before making load-bearing decisions. They prefer being asked over having a guess work out.
