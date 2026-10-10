#!/data/data/com.termux/files/usr/bin/bash
# Guarded GitHub -> Godot project sync for Termux.
# First run copies only missing files. Later runs copy changed remote files if the destination
# still matches the previous Git version; local edits are backed up and skipped.
set -u

REPO="$HOME/Roma-BRT-git"
PROJECT="$HOME/storage/shared/Documents/roma-brt-main"
LOG="$HOME/roma-brt-auto-sync.log"
BACKUP="$HOME/roma-brt-sync-backups"
BASELINE="$HOME/.roma-brt-auto-sync-baseline"
INTERVAL=60

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

if [ ! -d "$REPO/.git" ] || [ ! -d "$PROJECT" ]; then
  log "ERROR: repo or Godot project folder not found; stopping."
  exit 1
fi

# Seed the Godot folder conservatively: only add missing tracked files; never replace existing files.
if [ ! -f "$BASELINE" ]; then
  log "Initial sync: copying missing files only."
  while IFS= read -r REL; do
    [ -n "$REL" ] || continue
    case "$REL" in .git/*|.godot/*|*.import|tools/android_auto_sync.sh) continue ;; esac
    SRC="$REPO/$REL"
    DST="$PROJECT/$REL"
    [ -f "$SRC" ] || continue
    if [ ! -e "$DST" ]; then
      mkdir -p "$(dirname "$DST")"
      if cp "$SRC" "$DST"; then log "ADDED: $REL"; else log "ERROR adding $REL"; fi
    else
      log "INITIAL SKIP existing file: $REL"
    fi
  done < <(git -C "$REPO" ls-files)
  git -C "$REPO" rev-parse HEAD > "$BASELINE"
  log "Initial baseline saved."
fi

while true; do
  # Keep routine successful fetch output out of the log; record only failures.
  if ! git -C "$REPO" fetch -q origin main 2>> "$LOG"; then
    log "Fetch failed; retrying in ${INTERVAL}s."
    sleep "$INTERVAL"
    continue
  fi

  OLD="$(cat "$BASELINE" 2>/dev/null || true)"
  NEW="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"
  if [ -z "$OLD" ] || [ -z "$NEW" ] || [ "$OLD" = "$NEW" ]; then
    sleep "$INTERVAL"
    continue
  fi

  if ! git -C "$REPO" merge-base --is-ancestor "$OLD" "$NEW"; then
    log "STOP: baseline diverged from origin/main; no files copied."
    exit 2
  fi

  CHANGED="$(git -C "$REPO" diff --name-only "$OLD" "$NEW")"
  if ! git -C "$REPO" merge --ff-only origin/main >> "$LOG" 2>&1; then
    log "STOP: local Git changes prevented fast-forward; no files copied."
    exit 3
  fi

  while IFS= read -r REL; do
    [ -n "$REL" ] || continue
    case "$REL" in .git/*|.godot/*|*.import|tools/android_auto_sync.sh) continue ;; esac
    SRC="$REPO/$REL"
    DST="$PROJECT/$REL"
    OLD_FILE_EXISTS=0
    git -C "$REPO" cat-file -e "$OLD:$REL" 2>/dev/null && OLD_FILE_EXISTS=1

    if [ ! -f "$SRC" ]; then
      log "SKIP deletion (manual review required): $REL"
      continue
    fi

    mkdir -p "$(dirname "$DST")"
    if [ -e "$DST" ]; then
      MATCHES_OLD=0
      if [ "$OLD_FILE_EXISTS" -eq 1 ] && git -C "$REPO" show "$OLD:$REL" > "$HOME/.roma-brt-old-check" 2>/dev/null; then
        cmp -s "$DST" "$HOME/.roma-brt-old-check" && MATCHES_OLD=1
      fi
      if [ "$MATCHES_OLD" -eq 0 ]; then
        STAMP="$(date '+%Y%m%d-%H%M%S')"
        SAFE="$BACKUP/$STAMP/$REL"
        mkdir -p "$(dirname "$SAFE")"
        cp -p "$DST" "$SAFE" 2>/dev/null || true
        log "CONFLICT: preserved local file; backup=$SAFE; skipped=$REL"
        continue
      fi
    fi

    TMP="$DST.roma-sync-tmp"
    if cp "$SRC" "$TMP" && mv "$TMP" "$DST"; then
      log "UPDATED: $REL"
    else
      rm -f "$TMP"
      log "ERROR copying $REL"
    fi
  done <<EOF
$CHANGED
EOF
  printf '%s\n' "$NEW" > "$BASELINE"
  log "Sync pass complete: $OLD -> $NEW"
  sleep "$INTERVAL"
done
