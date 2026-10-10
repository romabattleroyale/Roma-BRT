#!/data/data/com.termux/files/usr/bin/bash
# Guarded GitHub -> Godot project sync for Termux.
# Initial pass backs up differing tracked files before aligning them to GitHub.
# Later passes update only files that still match their previous Git version.
set -u

REPO="$HOME/Roma-BRT-git"
PROJECT="$HOME/storage/shared/Documents/roma-brt-main"
LOG="$HOME/roma-brt-auto-sync.log"
BACKUP="$HOME/roma-brt-sync-backups"
BASELINE="$HOME/.roma-brt-auto-sync-baseline"
INTERVAL=60

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }
skip_path() {
  case "$1" in .git/*|.godot/*|*.import|tools/android_auto_sync.sh) return 0 ;; esac
  return 1
}
backup_file() {
  local src="$1" rel="$2" stamp safe
  stamp="$(date '+%Y%m%d-%H%M%S')"
  safe="$BACKUP/$stamp/$rel"
  mkdir -p "$(dirname "$safe")"
  if cp -p "$src" "$safe"; then
    log "BACKUP: $rel -> $safe"
  else
    log "ERROR backing up $rel; refusing to overwrite"
    return 1
  fi
}

if [ ! -d "$REPO/.git" ] || [ ! -d "$PROJECT" ]; then
  log "ERROR: repo or Godot project folder not found; stopping."
  exit 1
fi

# One-time alignment: backup every differing existing tracked file, then copy GitHub version.
if [ ! -f "$BASELINE" ]; then
  log "Initial sync: aligning tracked files with GitHub; local differences are backed up."
  while IFS= read -r REL; do
    [ -n "$REL" ] || continue
    skip_path "$REL" && continue
    SRC="$REPO/$REL"
    DST="$PROJECT/$REL"
    [ -f "$SRC" ] || continue
    mkdir -p "$(dirname "$DST")"
    if [ -f "$DST" ] && ! cmp -s "$SRC" "$DST"; then
      backup_file "$DST" "$REL" || continue
    fi
    if [ ! -f "$DST" ] || ! cmp -s "$SRC" "$DST"; then
      TMP="$DST.roma-sync-tmp"
      if cp "$SRC" "$TMP" && mv "$TMP" "$DST"; then
        log "INITIAL SYNC: $REL"
      else
        rm -f "$TMP"
        log "ERROR copying $REL"
      fi
    fi
  done < <(git -C "$REPO" ls-files)
  git -C "$REPO" rev-parse HEAD > "$BASELINE"
  log "Initial baseline saved."
fi

while true; do
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
    skip_path "$REL" && continue
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
        backup_file "$DST" "$REL" || continue
        log "CONFLICT: local version backed up; replacing with GitHub version: $REL"
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
