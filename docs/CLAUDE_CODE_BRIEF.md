# KODE OS — Project Brief for Claude Code

**Version 1.0** · Handoff document for Claude Code · Read this entire file at the start of every session.

---

## 1. What this project is

KODE OS is a **fork of CasaOS** customized for the **pebble v1** — a small, beginner-friendly home NAS appliance sold by KODE NAS. The product is a Raspberry Pi 5 in a custom case running KODE OS, marketed at non-technical home users as "your own private cloud."

**Why we're forking instead of using CasaOS directly:** CasaOS is great software but feels like a developer dashboard. Our target buyer (parents tired of paying for iCloud, photographers with full cloud quotas, anyone who heard "NAS" and got scared by Synology) needs an experience that's closer to Apple than to Linux. We're building a curated, simpler shell on top of CasaOS's solid technical foundation.

**Why we're not building from scratch:** CasaOS already does the hard parts well — Docker container management, Samba shares, file browser, app store API, system monitoring. Rebuilding those would be 6-12 months of work with no user-visible benefit. The fork lets us spend our time on the parts that actually differentiate the product.

---

## 2. Product context

| Attribute | Value |
|---|---|
| Company name | KODE NAS |
| Product name | pebble v1 |
| Operating system name | KODE OS |
| Target retail price | $280-300 CAD |
| Hardware | Raspberry Pi 5 (4 GB) in a custom case |
| Target storage | M.2 NVMe (eventually; SD card for prototype) |
| Target buyer | Non-technical home user — "Apple buyer, not Linux buyer" |
| Brand color | `#2D5F4E` (deep forest teal) |
| Brand typography | IBM Plex Sans (Google Fonts) |
| Tagline | "Your own private cloud, in a box the size of a paperback." |

**Critical positioning principle:** The product competes with Synology and iCloud, not with DIY Pi builds. Buyers should feel like they bought a finished appliance, not a kit. Anything that requires Linux knowledge to use is a bug.

---

## 3. Decision locked in: FORK CasaOS

Upstream repo: **https://github.com/IceWhaleTech/CasaOS**

CasaOS architecture (read this — it determines what we change vs keep):

```
CasaOS
├── Backend: Go (multiple microservices)
│   ├── casaos-gateway       — Reverse proxy / routing
│   ├── casaos-main          — Main API
│   ├── casaos-app-management — App install/start/stop
│   ├── casaos-user-service  — Auth
│   ├── casaos-message-bus   — Inter-service events
│   ├── casaos-local-storage — Disks / Samba
│   └── casaos-file          — File browser API
│
└── Frontend: Vue 2 + Bulma CSS
    └── github.com/IceWhaleTech/CasaOS-UI
        └── This is the repo we modify most
```

**Strategy:**
- **Keep the backend as-is for now** (it works, it's not user-visible).
- **Fork CasaOS-UI** as our primary work target. Rebrand, restructure, simplify.
- **Bundle our fork** with the upstream backend services into a single installable script that replaces the default CasaOS install on a fresh Pi.

The fork lives at: **`github.com/<your-username>/kode-os-ui`** (private repo to start)

---

## 4. License compliance — NON-NEGOTIABLE

CasaOS is licensed under **Apache License 2.0**. We are allowed to fork, modify, rebrand, and commercially distribute. **In exchange, we MUST:**

### 4.1 Required actions in every fork

1. **Keep the `LICENSE` file from CasaOS in the repo root, unchanged.** Renaming it to `LICENSE-CASAOS` and adding our own `LICENSE-KODE-OS` is fine if we choose a different license for our changes, but the upstream license file stays.

2. **Add a `NOTICE.md` file in the repo root** with this content:

   ```markdown
   # NOTICE

   KODE OS is a derivative work of CasaOS by IceWhale Technology Co., Ltd.

   Copyright © IceWhale Technology Co., Ltd.
   Licensed under the Apache License, Version 2.0.

   Original project: https://github.com/IceWhaleTech/CasaOS
   Original license: https://www.apache.org/licenses/LICENSE-2.0

   Modifications and additions are © KODE NAS and licensed separately.
   ```

3. **Add a credit line in the product's About / Settings page** that says something like:

   > KODE OS is based on CasaOS — Apache 2.0. Source: github.com/IceWhaleTech/CasaOS

4. **Add a `CHANGES.md` file** documenting major divergences from upstream. This isn't strictly required by Apache 2.0 but is a best practice and protects us legally if there's ever a dispute.

5. **Do not remove or obscure copyright headers in source files** we don't modify. If we substantially rewrite a file, we add our own copyright alongside the original (do not replace it).

### 4.2 What we are allowed to do

- ✅ Rebrand the product entirely as KODE OS
- ✅ Sell hardware running KODE OS commercially
- ✅ Charge subscription fees for additional services
- ✅ Keep our additions/modifications under a different (or proprietary) license
- ✅ Use our own logo, fonts, colors throughout the UI
- ✅ Remove CasaOS branding from the user-visible UI (we just keep attribution in About/source)

### 4.3 What we are NOT allowed to do

- ❌ Claim we wrote CasaOS ourselves
- ❌ Delete the original copyright notices from upstream code
- ❌ Sue CasaOS contributors for patent infringement (Apache 2.0 patent grant)
- ❌ Distribute the binary without the LICENSE file

**Claude Code: enforce these rules. If you're about to delete a copyright header, stop and ask.**

---

## 5. Phased roadmap

The full scope (everything from the user's wishlist) is 300-500 hours of work. We ship in phases so each milestone produces something demoable and shippable.

### Phase 1 — Source-level rebrand (40-60 hours)

Goal: Replace what we did with CSS overrides with proper changes in the Vue source code. KODE OS is recognizably its own product, but the layout still matches CasaOS.

Deliverables:
- Repo forked, build environment working
- All "CasaOS" strings replaced with "KODE OS" / "KODE NAS" / "pebble" appropriately
- Logo assets replaced throughout
- IBM Plex Sans loaded properly in the build
- Brand color (`#2D5F4E`) applied at the source level, not via overrides
- About page with proper Apache 2.0 attribution
- Custom wallpaper as default
- Production build deployed to Pi 5

**This is what you build first. Ship this before starting Phase 2.**

### Phase 2 — Beginner mode + simplified dashboard (60-100 hours)

Goal: Restructure the dashboard so a first-time user sees only essentials. An "Advanced" toggle in settings reveals power-user features.

Deliverables:
- New Vue component: `BeginnerDashboard.vue`
- Settings preference: `interfaceMode: 'beginner' | 'advanced'`, persists per user
- Beginner mode hides: App Store browsing, system stats widget, advanced settings, terminal access
- Beginner mode shows: Photo backup status, recent files, "Add device" wizard, basic family member list
- Warning modal component that fires when entering advanced features (replaces our DOM-overlay hack)
- Default mode on first install: beginner

### Phase 3 — Custom Files UI (80-150 hours)

Goal: Replace CasaOS's file manager with a simpler, more visual one for beginners.

Deliverables:
- New Vue component: `KodeFiles.vue`
- Grid view default (thumbnails), list view as toggle
- Predefined "home" folders (Photos, Videos, Documents) as top-level cards
- Drag-drop upload from desktop, multi-file
- One-tap share link generation
- Mobile-responsive — works in a phone browser

### Phase 4 — First-boot wizard (40-80 hours)

Goal: The "out of the box" experience. User plugs in pebble, opens browser, walks through a 5-step setup in <5 minutes.

Deliverables:
- New Vue route: `/welcome` (bypasses login on first run, locked after setup completes)
- Step 1: Welcome screen with KODE branding, system check (network, storage detected)
- Step 2: Create admin account (no need to fight CasaOS's existing onboarding)
- Step 3: Name your pebble (sets hostname, displayed name)
- Step 4: Pick which default apps to enable (Immich, Jellyfin, etc.)
- Step 5: Phone photo backup setup — QR code linking to Immich mobile app
- Backend hook: sets `kode_first_boot_complete=true` to prevent re-running

### Phase 5 — Onboarding tour + help system (40-60 hours)

Goal: Contextual help for new users.

Deliverables:
- Spotlight tour on first dashboard view (uses Shepherd.js or similar)
- Help button (?) in top bar that opens contextual help
- Help content stored in markdown files, rendered into a side drawer
- "Show this tour again" option in settings

### Phase 6 — Smartphone companion app (150-300 hours, separate project)

Goal: Native iOS + Android app for photo backup, file access, device status.

Approach: React Native, separate repo. Not part of this brief.
**Do not start until Phases 1-5 are complete and validated with real users.**

### Phase 7 — Custom KODE apps in app store (ongoing)

Goal: Apps designed by KODE NAS that ship as defaults — branded experiences that wrap Immich, Jellyfin, etc. in simpler UI.

This is a future concern. Skip for now.

---

## 6. Phase 1 detailed work order

This is what you start with. Do these tasks in order. Each ends with a working build deployable to the Pi 5.

### Task 1.1: Fork and clone

```bash
# On the user's laptop:
# 1. Go to github.com/IceWhaleTech/CasaOS-UI, click Fork
# 2. Set the new repo name to "kode-os-ui", make it PRIVATE
# 3. Then locally:
cd ~/projects   # or wherever you keep code
git clone git@github.com:<user>/kode-os-ui.git
cd kode-os-ui
git remote add upstream https://github.com/IceWhaleTech/CasaOS-UI
git fetch upstream
```

### Task 1.2: Add KODE OS license + notice files

Create these three files in the repo root:

- `LICENSE-CASAOS` — copy the original `LICENSE` here
- `NOTICE.md` — as written in section 4.1 above
- `CHANGES.md` — start empty, add to as we go

Update the main `README.md` to reflect KODE OS branding, but keep an "Original project" link to CasaOS.

### Task 1.3: Set up build environment

CasaOS-UI is a Vue 2 project using pnpm. Verify these versions:

```bash
node --version       # Need v18+
pnpm --version       # Need 8+
```

Install dependencies:

```bash
pnpm install
```

First build sanity check (should produce unchanged CasaOS):

```bash
pnpm build
# Output goes to /dist
```

If build fails, fix it before any rebranding work. Common issues:
- Node version mismatch — use `nvm install 18 && nvm use 18`
- pnpm missing — `npm install -g pnpm`

### Task 1.4: Branding inventory

Find every place "CasaOS" appears in the source. Run:

```bash
grep -ri "casaos" src/ --include="*.vue" --include="*.js" --include="*.ts" --include="*.json" --include="*.html" | wc -l
```

Expect 100-300 hits. Categorize them into:

1. **User-visible strings** — translation files (probably under `src/lang/` or `src/i18n/`)
2. **Component names** — Vue components, JS classes (e.g., `CasaOSDashboard.vue`)
3. **API endpoints** — URLs referencing `/v1/casaos/...` (DO NOT change these — they map to the backend)
4. **Asset paths** — image/logo file paths
5. **Comments/docs** — code comments mentioning CasaOS (leave alone for now)

For each category:
1. ✅ Replace with KODE OS / pebble (user-visible strings, component names, asset paths)
2. ❌ Do NOT touch API endpoints, code comments

### Task 1.5: Translation string replacements

Most CasaOS UI text comes from i18n JSON files. Find them:

```bash
find src/ -name "*.json" | xargs grep -l "CasaOS"
```

Replace strings according to this mapping:

| Original | Replace with |
|---|---|
| "CasaOS" | "KODE OS" |
| "Welcome to CasaOS" | "Welcome to your pebble" |
| "CasaOS Dashboard" | "Dashboard" |
| "CasaOS App Store" | "App Store" |
| "CasaOS Files" | "Files" |
| "About CasaOS" | "About KODE OS" |
| "CasaOS Community" | "KODE NAS Community" |

**Do not blindly find-and-replace.** Some strings inside `<code>` blocks or technical docs should stay as "CasaOS." Use your judgment.

### Task 1.6: Logo + favicon replacement

Existing files (the user will give you these):
- `logo.svg` — full horizontal logo (K mark + "KODE NAS" wordmark)
- `logo-mark.svg` — just the K symbol
- `logo-light.png` / `logo-dark.png` — pre-rendered raster versions
- `favicon.svg` — K on teal square (for browser tabs)
- `favicon.ico` / `favicon-16.png` / `favicon-32.png` / `apple-touch-icon.png`
- `wallpaper.jpg` — misty forest scene

CasaOS source has logo references in:
- `src/assets/img/logo/` (or similar — find with `find src -name "logo*"`)
- `public/favicon.ico`
- `public/site.webmanifest`
- `public/index.html`

Replace each one. Maintain aspect ratios; export at 2× resolution for retina displays.

### Task 1.7: Color palette swap

CasaOS uses Bulma + custom SCSS variables. Find the variables file:

```bash
find src/ -name "*variables*.scss" -o -name "*colors*.scss"
```

Update primary color from CasaOS blue to `#2D5F4E` and update all derived shades. Don't forget:

- Hover color: `#3F7A66`
- Active/pressed: `#1F4438`
- Light tint background: `rgba(45, 95, 78, 0.12)`

After this change, every button/link/badge that uses `is-primary` automatically becomes KODE teal. No CSS overrides needed.

### Task 1.8: Typography — IBM Plex Sans at the source level

Add to `public/index.html` `<head>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet">
```

Update the SCSS font stack (find `$family-primary` or similar):

```scss
$family-primary: 'IBM Plex Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
```

Rebuild. Verify text actually renders in IBM Plex.

### Task 1.9: About page with attribution

Find the About/Settings page (probably `src/views/Settings.vue` or `src/views/About.vue`). Add a section:

```html
<section class="about-section">
  <h3>About KODE OS</h3>
  <p>Version {{ version }}</p>
  <p>
    KODE OS is based on
    <a href="https://github.com/IceWhaleTech/CasaOS" target="_blank">
      CasaOS by IceWhale Technology
    </a>, licensed under
    <a href="https://www.apache.org/licenses/LICENSE-2.0" target="_blank">
      Apache 2.0
    </a>.
  </p>
  <p class="text-secondary">
    Made by KODE NAS · pebble v1
  </p>
</section>
```

### Task 1.10: Wallpaper as default

Place `wallpaper.jpg` in `src/assets/wallpapers/forest.jpg`. Find the default wallpaper selection in CasaOS (probably `src/store/` or a settings file) and set the new file as default. Existing CasaOS wallpapers can stay as additional options for now.

### Task 1.11: Production build + deploy script

Write a `scripts/deploy-to-pi.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Build production
pnpm build

# Sync to Pi via rsync (faster than scp for many small files)
PI_HOST="${PI_HOST:-kode@pebble.local}"
echo "Deploying to ${PI_HOST}..."

rsync -avz --delete dist/ "${PI_HOST}:/tmp/kode-os-ui/"
ssh "${PI_HOST}" "sudo rsync -a /tmp/kode-os-ui/ /var/lib/casaos/www/ && sudo systemctl restart casaos-gateway && sudo systemctl restart casaos"

echo "Deployed. Hard-refresh browser to see changes."
```

Make executable: `chmod +x scripts/deploy-to-pi.sh`

### Task 1.12: First end-to-end test

1. Run `./scripts/deploy-to-pi.sh`
2. Open `http://pebble.local` on a clean browser (Incognito)
3. Verify:
   - Title bar shows "KODE OS"
   - Logo is the K mark
   - Buttons are teal
   - Font is IBM Plex Sans
   - About page shows Apache 2.0 attribution
   - Wallpaper is the forest
4. Walk through every page in the UI looking for missed "CasaOS" strings

Phase 1 is complete when an outside observer can use the system without realizing it's based on CasaOS (except where credited).

---

## 7. Branding kit reference

| Item | Value |
|---|---|
| Brand name | KODE NAS (company), pebble v1 (product), KODE OS (operating system) |
| Primary color | `#2D5F4E` |
| Primary hover | `#3F7A66` |
| Primary active | `#1F4438` |
| Primary light tint | `rgba(45, 95, 78, 0.12)` |
| Background overlay | `linear-gradient(180deg, rgba(15,25,30,0.30), rgba(15,25,30,0.55))` |
| Font family | `'IBM Plex Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif` |
| Base font size | 16px |
| Body line-height | 1.6 |
| Heading weight | 500 |
| Body weight | 400 |
| Letter-spacing on headings | -0.01em |
| Border radius (small) | 8px |
| Border radius (cards) | 12-16px |
| Card backdrop blur | `blur(14px)` |
| Card background | `rgba(255, 255, 255, 0.92)` with backdrop blur |
| Text on dark | `rgba(255, 255, 255, 0.96)` |
| Text shadow on dark | `0 1px 4px rgba(0, 0, 0, 0.55)` |

### Voice & tone

- Direct, friendly, unintimidating
- Avoid jargon — no "NAS", "Docker", "SMB", "TCP", "container" in user-visible UI
- Replace with: "your pebble", "apps", "file sharing", "network", "service"
- Use second person ("your photos") not third person ("the user's photos")
- Sentences short. Periods strong. Active voice.

### Copy snippets to use directly

- Welcome screen heading: "Welcome to your pebble"
- Welcome screen subhead: "Your own private cloud, ready in 5 minutes."
- Setup complete: "You're all set. Your pebble is ready."
- Empty state, dashboard: "Apps you install will appear here."
- Empty state, photos: "Photos backed up from your phone will appear here."
- About page tagline: "pebble v1 — made by KODE NAS"
- Error state, network: "Can't reach the network. Check the cable to your router."
- Error state, generic: "Something went wrong. Try again in a moment."

---

## 8. Existing assets — what the user already has

The user has been working on this product for weeks. These pieces already exist and need to be preserved/integrated:

### 8.1 Hardware

- Raspberry Pi 5 (4 GB)
- Official Pi 5 USB-C PSU
- 64 GB microSD running Raspberry Pi OS Lite (64-bit)
- CasaOS already installed at `/var/lib/casaos/`
- Apps already installed: Immich, Jellyfin, File Browser, Pi-hole, Home Assistant
- Pi configured with hostname `pebble`, user `kode`

### 8.2 OLED screen + Arduino bridge

- 256×64 SH1122 OLED via SPI, connected to an Arduino Nano
- Arduino Nano connected to the Pi 5 via USB serial (`/dev/ttyUSB0`)
- Python daemon (`nas_screen.py`) runs as systemd service `pebble-screen.service`
- Sends pipe-delimited data every 2 seconds: `hostname|ip|disk_free|cpu_temp|cpu_pct|uptime|app_count`
- Arduino displays: KODE logo splash → KODE NAS / pebble v1 brand splash → 3 rotating screens (Address, Storage, Status)
- Button on pin D7: short-press cycles screens, long-press toggles screen lock

**These files already exist and shouldn't be re-written by Claude Code in Phase 1:**

- `~/nas_screen.py` (Python daemon on Pi)
- `~/kode-pebble/setup-pebble.sh` (provisioning script on Pi)
- Arduino sketch saved on the user's laptop (KODE NAS pebble v1.ino)

Claude Code should reference these but not modify them in Phase 1. They become integration points in Phase 4 (first-boot wizard surfacing the OLED status).

### 8.3 What's already configured

- `/DATA` folder structure: `Photos, Videos, Documents, Music, Backups, Downloads`
- Samba (SMB) file sharing for all 6 folders
- 5 default apps installed and configured to use `/DATA` subfolders
- Timezone: `America/Toronto`

### 8.4 Branding files the user will provide

When you start work, ask the user for these files:

- `logo.svg` (horizontal logo)
- `logo-mark.svg` (K symbol only)
- `favicon.svg`, `favicon.ico`, `favicon-16.png`, `favicon-32.png`, `favicon-64.png`, `apple-touch-icon.png`
- `wallpaper.jpg` (misty forest, 1920×1080 or larger)
- `logo-light.png` / `logo-dark.png`

They should be in a folder the user can share with you.

---

## 9. Development environment setup

The user's laptop runs **Endeavour OS** (Arch-based). They have shell/CLI comfort. Hours per week available is uncertain — work as efficiently as possible.

### 9.1 Prerequisites to install

```bash
# Node.js 18 LTS via nvm (preferred over system package)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 18
nvm use 18

# pnpm
npm install -g pnpm

# Git (probably already installed)
sudo pacman -S --needed git

# Optional: code editor
sudo pacman -S code   # VS Code
```

### 9.2 SSH key setup for GitHub

```bash
ssh-keygen -t ed25519 -C "user@example.com"
cat ~/.ssh/id_ed25519.pub   # Copy this to github.com/settings/keys
```

### 9.3 SSH access to the Pi

The user has SSH access to the Pi as `kode@pebble.local`. Verify:

```bash
ssh kode@pebble.local "uname -a"
```

For password-less deploys, copy the SSH key:

```bash
ssh-copy-id kode@pebble.local
```

---

## 10. Repository structure recommendation

Once forked, structure should look like:

```
kode-os-ui/
├── LICENSE              (original Apache 2.0 from CasaOS — unchanged)
├── LICENSE-KODE-OS      (optional, for KODE additions)
├── NOTICE.md            (attribution as per section 4)
├── CHANGES.md           (changelog of divergences from upstream)
├── README.md            (KODE OS branding, links back to CasaOS)
├── package.json         (renamed to "kode-os-ui")
├── public/              (mostly unchanged — favicons swapped)
├── src/                 (heavy modification here)
├── scripts/
│   ├── deploy-to-pi.sh  (new — built in Task 1.11)
│   ├── sync-upstream.sh (new — pull updates from CasaOS-UI master)
│   └── ...
├── docs/
│   ├── brand.md         (the branding kit above)
│   ├── phases.md        (roadmap)
│   └── ...
└── tests/               (existing CasaOS tests — keep)
```

---

## 11. Workflow guidance for Claude Code

### 11.1 Always-do rules

- **Commit early, commit often.** Every meaningful change gets a commit. Use conventional commit messages: `feat:`, `fix:`, `chore:`, `docs:`, `style:`.
- **Branch per task.** `feat/rebrand-strings`, `feat/logo-swap`, `chore/setup-build`. PRs are optional for solo work but branches keep history clean.
- **Build before committing.** Don't push broken code. `pnpm build` should always succeed.
- **Deploy to Pi after each meaningful change.** Verify it looks right in a real browser, not just `pnpm dev`.
- **Take screenshots of progress.** The user wants to see things working.

### 11.2 Never-do rules

- ❌ Never delete the upstream `LICENSE` file
- ❌ Never change API endpoint URLs (these talk to CasaOS backend)
- ❌ Never modify files in `casaos-*` Go backend services (out of scope for Phase 1)
- ❌ Never push secrets/passwords to the repo — use `.env` files (gitignored)
- ❌ Never run destructive shell commands on the Pi without showing the user first
- ❌ Never claim something is done without testing it on the actual Pi 5

### 11.3 When stuck or unsure

If a task is ambiguous or you hit something not covered in this brief, **stop and ask the user**. Don't make load-bearing decisions on your own. Examples:

- "Should the Beginner mode default to ON or OFF for new installs?" → ask
- "The CasaOS source uses Vuex 3 for state. Should I migrate to Pinia?" → ask
- "I see a CasaOS Pro feature. Are we including it?" → ask

---

## 12. Testing checklist (per Phase 1 milestone)

After each task, verify on the Pi 5:

- [ ] `pnpm build` completes without errors
- [ ] Deploy script runs without errors
- [ ] CasaOS web UI loads at `http://pebble.local`
- [ ] Browser tab title shows "KODE OS"
- [ ] Favicon shows the K logo
- [ ] Logo on dashboard is KODE
- [ ] Primary buttons are teal (`#2D5F4E`)
- [ ] Font is IBM Plex Sans (verify via DevTools)
- [ ] About page shows Apache 2.0 attribution
- [ ] Wallpaper is the misty forest
- [ ] App tiles show installed apps (Immich, Jellyfin, etc.)
- [ ] Installed apps still launch when clicked
- [ ] Samba shares still work from a phone or laptop
- [ ] OLED screen continues to display correctly (should be unaffected, but verify)
- [ ] No JavaScript errors in browser console
- [ ] No 404s in Network tab

Don't move to the next task until all checks pass.

---

## 13. Out of scope for now

Things the user might mention but we explicitly defer:

- ❌ Smartphone companion app (Phase 6, separate project)
- ❌ Custom KODE-branded apps (Phase 7, future)
- ❌ Multi-bay support (pebble v1 is single-bay only)
- ❌ Backend microservice modifications (we use upstream as-is)
- ❌ Custom Linux distribution / OS image (we use Raspberry Pi OS)
- ❌ Case design / 3D printing (separate hardware track)
- ❌ Trademark legal work (the user handles this independently)
- ❌ Local LLM / AI assistant (deferred until 8 GB Pi 5 hardware is locked in)
- ❌ Cloud sync / off-device backup features (Phase 5+)

If the user asks you to start any of these, point them back to this section and the roadmap. Suggest writing it down in a "future ideas" file rather than blocking Phase 1.

---

## 14. Critical reminder: validation before deep code

This brief enables roughly 6-12 months of work. **Before you start coding, the user should validate the concept with real potential buyers.** Suggested validation moves:

1. Film a 60-90 second demo video showing the prototype (CasaOS as currently branded is fine)
2. Post to `r/selfhosted` with the product description
3. Show 10-20 people in person ("what does this look like it costs?", "what's missing?", "would you buy this?")
4. Set up a simple landing page with email signup

If validation reveals the product idea is wrong, we don't want to have spent 6 months on KODE OS code. **Strongly encourage the user to validate before Phase 1 work starts in earnest.**

Claude Code should remind the user about validation in the first session.

---

## 15. Open questions for the user (ask in first session)

1. Have you forked CasaOS-UI yet? If yes, what's the URL?
2. Where are your branding asset files? Share the folder/links so we can reference them.
3. Do you have a GitHub account set up with SSH keys?
4. How many hours per week realistically can you commit to this?
5. Have you done any validation with real potential buyers? (If no, strongly suggest doing this before Phase 1.)
6. Beginner mode default — ON or OFF for new installs?
7. What does "advanced mode" allow that beginner mode hides? Be specific.
8. Should installed apps appear identically in both modes, or differently?
9. Is the existing Arduino + OLED hardware staying for v1, or is it being redesigned?
10. What's your timeline / launch target?

---

## 16. Quick reference card

```
Brand name:        KODE NAS
Product:           pebble v1
OS name:           KODE OS
Color:             #2D5F4E
Font:              IBM Plex Sans
Repo:              github.com/<user>/kode-os-ui (private)
Upstream:          github.com/IceWhaleTech/CasaOS-UI
License:           Apache 2.0 (kept), modifications optional
Target hardware:   Raspberry Pi 5 (4 GB)
Target price:      $280-300 CAD
Pi hostname:       pebble (kode@pebble.local)
Web UI path:       /var/lib/casaos/www/ on Pi
Deploy command:    ./scripts/deploy-to-pi.sh
```

---

## End of brief

This document is the contract between the user, Claude Code, and the long-term shape of KODE OS. Update it as the project evolves. When you start a new Claude Code session, paste this brief into the first message so the assistant has full context.

**Read this entire file before writing code. Reference it whenever a question comes up.**

Good luck. Ship something real.
