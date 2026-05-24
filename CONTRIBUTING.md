# Contributing to KODE OS

Thanks for considering a contribution. KODE OS is built for non-technical home users, which makes design and UX feedback as valuable as code.

## Before you start

- KODE OS is in alpha. Big architectural changes during this phase will get pushed back unless they unblock the v1 release.
- The project competes with Synology and iCloud, **not** with DIY Pi builds. Anything that requires Linux knowledge to use is a bug. If your contribution adds a setting nobody outside this repo will understand, expect a "is this really for the buyer?" comment.
- Read [CLAUDE_CODE_BRIEF.md](docs/CLAUDE_CODE_BRIEF.md) for the full product context.

## Where the code lives

- **`kode-os` (this repo)** — installer, OLED daemon, branding, legal, docs.
- **`kode-os-ui`** — the Vue 2 dashboard. Lives in a separate repo so the dashboard can release on its own cadence.

## Setting up a dev environment

You need:
- A Raspberry Pi 5 with Raspberry Pi OS Lite 64-bit + Docker + a fresh CasaOS install (the installer in `scripts/install.sh` covers this end-to-end).
- A laptop with Node 18+, pnpm 8+, and SSH access to the pebble.

```bash
# Clone both repos side by side
git clone https://github.com/KodeNAS/kode-os.git
git clone https://github.com/KodeNAS/kode-os-ui.git

cd kode-os-ui
pnpm install
pnpm dev            # local dev server, proxies API to the pebble
```

For deployment to a real pebble:

```bash
PI_HOST=kode@pebble.local ./scripts/deploy-to-pi.sh
```

## How to propose a change

1. **Open an issue first** for anything bigger than a typo or a small bug fix. It saves you from doing the work the wrong way around.
2. **Fork the repo** you're changing.
3. **Branch per change.** `feat/foo`, `fix/bar`, `docs/baz`.
4. **Conventional commits** for the title: `feat(dashboard): add weather forecast cards`. Body explains the why.
5. **Open a PR** with:
   - The user-facing change in plain English.
   - Screenshots or a screen recording if it touches the UI.
   - Test notes — how you verified it on a real pebble.

## Code style

- The Vue UI follows the existing project's eslint + prettier setup. Run `pnpm lint --fix` before pushing.
- The Python daemon (`pebble/kode_nas_display.py`) follows PEP 8 and uses standard-library-only imports where possible.
- Bash scripts target Bash 5 and use `set -euo pipefail`.
- Comments explain *why*, not *what*. The code already says what.

## Things we'll push back on

- Adding telemetry, analytics, or remote update checks. See [PRIVACY.md](PRIVACY.md) — keeping data on the pebble is core to the product.
- Removing the CasaOS attribution. Required by Apache 2.0 and by basic honesty.
- Hidden / "advanced" settings buried in submenus that change the dashboard's default behavior. Either it's a first-class UI choice or it doesn't ship.

## Security

Don't open public issues for vulnerabilities. See [SECURITY.md](SECURITY.md) for the private reporting channel.

## License + DCO

By submitting a contribution you agree it can be released under the [Apache License 2.0](LICENSE). KODE OS uses an implicit Developer Certificate of Origin — you're affirming you have the right to submit the code you're sending.

## Questions

GitHub Discussions: https://github.com/KodeNAS/kode-os/discussions  
Email (general): hello@kode-nas.com *(live with the first public alpha)*

Thanks for helping make a NAS that grandparents can actually use.
