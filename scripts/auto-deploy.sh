#!/usr/bin/env bash
# Auto-deploy hook invoked from .claude/settings.json Stop event.
#
# When Claude finishes a turn, this script inspects what changed in
# either repo (parent + kode-os-ui) and routes the right deploy:
#
#   kode-os-ui/{src,public,scripts,pi}/**, package.json, vue.config.js
#       → cd kode-os-ui && pnpm build && ./scripts/deploy-to-pi.sh
#   pi/nas_screen.py (inside kode-os-ui)
#       → ./scripts/deploy-screen-to-pi.sh
#   kode_nas_display.py (parent)
#       → scp + restart detached python daemon on the pebble
#
# After deploys complete, untracked-or-modified files in the kode-os-ui
# repo are auto-committed with a generic conventional-commit message
# (user explicitly asked for auto-commits in this project).
#
# Failures are non-fatal: each phase logs and continues so a single
# broken deploy can't lock the Stop hook in a failing state.
set -uo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-/home/olicz/Documents/KODE OS}"
PI_HOST="${PI_HOST:-kode@pebble.local}"

cd "$PROJECT_ROOT" || exit 0

# Idempotent deploy gating via mtime stamps. `git status` doesn't work
# for files that have never been tracked (kode_nas_display.py shows up
# as "??" forever in this repo), and re-deploying on every Stop event
# would needlessly rebuild the UI + bounce the OLED daemon when Claude
# was just answering a question. The stamp file records the mtime of
# each file we deployed; we only deploy when the current mtime is
# strictly newer.
STAMP_FILE="$PROJECT_ROOT/.claude/.auto-deploy.stamps"
mkdir -p "$(dirname "$STAMP_FILE")"
touch "$STAMP_FILE"

# Stamps are TAB-separated (`<path>\t<mtime>`) because the project
# root has spaces in it and awk's default whitespace splitting would
# otherwise chop the path into pieces.
TAB=$'\t'

# Return 0 if $file is newer than the stamp recorded for it. On first
# run (no stamp present) we treat the file as new and deploy.
file_changed() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local mtime
  mtime=$(stat -c '%Y' "$file" 2>/dev/null) || return 1
  local stamp
  stamp=$(awk -F"$TAB" -v f="$file" '$1 == f { print $2; exit }' "$STAMP_FILE" 2>/dev/null)
  if [[ -z "$stamp" ]] || (( mtime > stamp )); then
    return 0
  fi
  return 1
}

# Record file's current mtime in the stamp file (replace prior entry).
mark_deployed() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local mtime
  mtime=$(stat -c '%Y' "$file" 2>/dev/null) || return 0
  local tmp
  tmp=$(mktemp)
  awk -F"$TAB" -v f="$file" '$1 != f' "$STAMP_FILE" > "$tmp" 2>/dev/null || true
  printf '%s\t%s\n' "$file" "$mtime" >> "$tmp"
  mv "$tmp" "$STAMP_FILE"
}

# Identify which deploys we need this turn. The UI build is triggered
# by ANY file under kode-os-ui/{src,public,scripts,pi} having a newer
# mtime than its stamp — we check directory-aggregate via find.
ui_dir="$PROJECT_ROOT/kode-os-ui"
daemon_file="$PROJECT_ROOT/pebble/kode_nas_display.py"

ui_needs_build=0
ui_needs_screen=0
daemon_changed=0

# UI sources: anything newer than the stamp inside the build inputs.
if [[ -d "$ui_dir/src" ]]; then
  ui_stamp=$(awk -F"$TAB" '$1 == "__ui_build__" { print $2; exit }' "$STAMP_FILE" 2>/dev/null)
  ui_stamp=${ui_stamp:-0}
  newer=$(find "$ui_dir/src" "$ui_dir/public" "$ui_dir/package.json" "$ui_dir/vue.config.js" \
                "$ui_dir/babel.config.js" 2>/dev/null \
            -newermt "@$ui_stamp" -type f -print -quit 2>/dev/null || true)
  if [[ -n "$newer" ]]; then ui_needs_build=1; fi
fi

if file_changed "$ui_dir/pi/nas_screen.py"; then ui_needs_screen=1; fi
if file_changed "$daemon_file"; then daemon_changed=1; fi

# Exit fast if nothing to do.
if (( ui_needs_build == 0 && ui_needs_screen == 0 && daemon_changed == 0 )); then
  exit 0
fi

log() { echo "[auto-deploy] $*" >&2; }

# --- 1. UI build + rsync to pebble ---
if (( ui_needs_build )); then
  log "UI changes — pnpm build + deploy-to-pi.sh"
  if ( cd "$ui_dir" && pnpm build >/dev/null && ./scripts/deploy-to-pi.sh >/dev/null ); then
    # Stamp the build with the current time so the next run only
    # rebuilds if a source file is touched after this point.
    tmp=$(mktemp)
    awk -F"$TAB" '$1 != "__ui_build__"' "$STAMP_FILE" > "$tmp" 2>/dev/null || true
    printf '%s\t%s\n' "__ui_build__" "$(date +%s)" >> "$tmp"
    mv "$tmp" "$STAMP_FILE"
  else
    log "UI deploy FAILED (build or rsync exit non-zero)"
  fi
fi

# --- 2. Old serial OLED daemon (Arduino path) ---
if (( ui_needs_screen )); then
  log "pi/nas_screen.py changed — deploy-screen-to-pi.sh"
  if ( cd "$ui_dir" && ./scripts/deploy-screen-to-pi.sh >/dev/null ); then
    mark_deployed "$ui_dir/pi/nas_screen.py"
  else
    log "screen daemon deploy FAILED"
  fi
fi

# --- 3. SH1122-direct OLED daemon ---
# Deploy the daemon + invoke the pebble-side restart helper. The
# helper exists so pkill -f doesn't accidentally match (and kill) our
# SSH bash subshell — see pebble/restart-display.sh for the
# explanation. We re-scp the helper every run so a stale copy on the
# pebble auto-heals.
if (( daemon_changed )); then
  log "kode_nas_display.py changed — scp + restart on $PI_HOST"
  if scp -q "$daemon_file" "$PI_HOST:/home/kode/kode_nas_display.py" \
       && scp -q "$PROJECT_ROOT/pebble/restart-display.sh" "$PI_HOST:/home/kode/restart-display.sh"; then
    if ssh "$PI_HOST" "chmod +x /home/kode/restart-display.sh && /home/kode/restart-display.sh"; then
      mark_deployed "$daemon_file"
    else
      log "remote restart FAILED"
    fi
  else
    log "scp FAILED"
  fi
fi

# --- 4. Auto-commit in kode-os-ui (user opt-in) ---
# Parent dir has no tracked files yet, so commits there would just
# stage everything once and then nothing forever. Skip until the user
# initializes that repo properly. The kode-os-ui sub-repo has real
# history and is the one we want versioned.
if [[ -d "$ui_dir/.git" ]]; then
  ( cd "$ui_dir" \
      && git add -A \
      && if ! git diff --cached --quiet; then
           files=$(git diff --cached --name-only)
           git commit -m "chore: auto-commit from claude session

$(echo "$files" | sed 's/^/  - /')" >/dev/null
         fi \
  ) || log "auto-commit FAILED (pre-commit hook? merge conflict?)"
fi

exit 0
