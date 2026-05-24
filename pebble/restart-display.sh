#!/usr/bin/env bash
# Pebble-side restart helper for the SH1122 OLED daemon. Deployed via
# scp by auto-deploy.sh; lives at /home/kode/restart-display.sh.
#
# Why a separate script: `pkill -f kode_nas_display.py` invoked
# directly over SSH matches the bash subshell hosting the pkill
# command (its argv contains the search string) and kills the SSH
# session itself. Wrapping the kill+restart in a script run by name
# means the bash argv is just "bash restart-display.sh" — the search
# pattern is only present in the actual python daemon, so pkill only
# hits the right process.
set -uo pipefail

# Kill any running daemon. pkill returns 1 when no match — that's
# fine on the cold-start case.
pkill -f /home/kode/kode_nas_display.py || true
sleep 1

# Detach a fresh daemon. setsid + double-fork + redirect-everything so
# the SSH parent can close cleanly and the daemon stays alive across
# session disconnects + reboots-of-the-bash-shell.
( setsid /usr/bin/python3 /home/kode/kode_nas_display.py \
    </dev/null >/tmp/oled.log 2>&1 & ) &

exit 0
