#!/usr/bin/env bash
# Set up HTTPS on the pebble using Caddy with its `tls internal` mode.
#
# Caddy auto-generates a local Certificate Authority on first run,
# stores it under /var/lib/caddy/.local/share/caddy/pki/authorities/local/,
# and issues a cert for pebble.local signed by that CA. Customers
# install the CA on their devices once → browsers stop showing the
# "Not Secure" warning for https://pebble.local.
#
# Architecture:
#   :80  → casaos-gateway (existing, unchanged — plain HTTP still works)
#   :443 → caddy → reverse_proxy 127.0.0.1:80 (HTTPS to the same gateway)
#
# Run with sudo on the pebble:
#   ssh kode@pebble.local 'bash -s' < scripts/setup-pebble-https.sh
#
# Or interactively:
#   ssh kode@pebble.local
#   sudo bash setup-pebble-https.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script needs root. Re-run with sudo." >&2
  exit 1
fi

echo "[1/5] Installing Caddy..."
# Caddy's official Debian repo — pre-built binaries for arm64 (Pi 5).
# Idempotent: re-running just refreshes.
if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update
  apt-get install -y caddy
else
  echo "  Caddy already installed: $(caddy version | head -1)"
fi

echo "[2/5] Writing Caddyfile..."
# Plain text + comments so the buyer (or future-you) can audit it.
# `tls internal` = use Caddy's local CA. No public DNS required.
cat > /etc/caddy/Caddyfile <<'EOF'
# KODE OS — HTTPS termination for the pebble.
#
# Caddy uses its local CA (tls internal) to issue a cert for
# pebble.local + the pebble's IP. The cert is signed by a per-pebble
# root CA stored at /var/lib/caddy/.local/share/caddy/pki/authorities/local/.
#
# Install that root CA on each device once → no browser warnings.
# The Settings page in KODE OS surfaces a download link for it.

(common) {
	encode gzip
	reverse_proxy 127.0.0.1:80 {
		header_up Host {host}
		header_up X-Forwarded-Proto https
		header_up X-Forwarded-Host {host}
	}
}

# Match by hostname OR by raw IP — Caddy's tls internal handles both.
# 0.0.0.0 catches anything else that hits :443 (e.g. local IP).
pebble.local, pebble {
	tls internal
	import common
}

# Catch-all for IP-based access (192.168.x.x). Caddy issues a cert
# for whatever Host header the request carries; modern browsers will
# still complain about IP-in-SAN if you reach by IP, but most home
# devices use mDNS (pebble.local) so this is a fallback.
:443 {
	tls internal
	import common
}
EOF

echo "[3/5] Validating Caddyfile..."
caddy fmt --overwrite /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile

echo "[4/5] Enabling + starting caddy..."
systemctl enable --now caddy
systemctl restart caddy
sleep 2
systemctl is-active caddy

echo "[5/5] Caddy's root CA (install this on each device):"
ROOT_CA=$(find /var/lib/caddy -type f -name 'root.crt' 2>/dev/null | head -1 || true)
if [[ -n "$ROOT_CA" ]]; then
  echo "  Path on pebble: $ROOT_CA"
  echo "  Copy locally with:"
  echo "    scp kode@pebble.local:$ROOT_CA pebble-ca.crt"
  echo "    sudo cp pebble-ca.crt /etc/ssl/certs/  # Linux"
  echo "    # macOS: open Keychain Access → System → drag pebble-ca.crt in → trust."
  echo "    # Windows: certmgr.msc → Trusted Root → Import."
  echo "    # iOS/Android: serve the cert via /pebble-ca.crt from KODE OS."
else
  echo "  Root CA not generated yet — Caddy will mint it on first HTTPS request."
  echo "  Visit https://pebble.local in a browser once, then re-run this script's [5/5] step."
fi

cat <<EOF

Done. Try:
  https://pebble.local
  https://$(hostname -I | awk '{print $1}')

First visit will show a "Not Secure" warning until you trust the local
CA above. After trust, browsers go quiet — same UX as Plex / Synology.
EOF
