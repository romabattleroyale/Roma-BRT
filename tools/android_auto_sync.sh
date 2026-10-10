#!/data/data/com.termux/files/usr/bin/bash
# Guarded GitHub -> Godot project sync for Termux.
# Copies only files changed by new remote commits. Local divergences are backed up and skipped.
set -u

REPO="$HOME/Roma-BRT-git"
PROJECT="$HOME/storage/shared/Documents/roma-brt-main"
LOG="$HOME/roma-brt-auto-sync.log"
BACKUP="$HOME/roma-brt-sync-backups"
INTERVAL=60

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

if [ ! -d "$REPO/.git" ] || [ ! -d "$PROJECT" ]; then
  log "ERROR: repo or Godot project folder not found; stopping."
  exit 1
fi

while true; do
  if ! git -C "$REPO" fetch origin main >> "$LOG" 2>&1; then
    log "Fetch failed; retrying in ${INTERVAL}s."
    sleep "$INTERVAL"
    continue
  fi

  OLD="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)"
  NEW="$(git -C "$REPO" rev-parse origin/main 2>/dev/null || true)"

  if [ -z "$OLD" ] || [ -z "$NEW" ] || [ "$OLD" = "$NEW" ]; then
    sleep "$INTERVAL"
    continue
  fi

  # Never reset or force the local repository. Stop if it cannot fast-forward.
  if ! git -C "$REPO" merge-base --is-ancestor "$OLD" "$NEW"; then
    log "STOP: local branch diverged from origin/main; no files copied."
    exit 2
  fi

  CHANGED="$(git -C "$REPO" diff --name-only "$OLD" "$NEW")"
  if ! git -C "$REPO" merge --ff-only origin/main >> "$LOG" 2>&1; then
    log "STOP: local Git changes prevented fast-forward; no files copied."
    exit 3
  fi

  while IFS= read -r REL; do
    [ -n "$REL" ] || continue
    case "$REL" in
      .git/*|.godot/*|*.import|tools/android_auto_sync.sh) continue ;;
    esac
    SRC="$REPO/$REL"
    DST="$PROJECT/$REL"
    OLD_FILE_EXISTS=0
    git -C "$REPO" cat-file -e "$OLD:$REL" 2>/dev/null && OLD_FILE_EXISTS=1

    if [ ! -f "$SRC" ]; then
      # Deletions are intentionally not propagated automatically.
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
  log "Sync pass complete: $OLD -> $NEW"
  sleep "$INTERVAL"
done
