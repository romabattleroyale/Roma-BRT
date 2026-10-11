#!/usr/bin/env bash
# Install MapGen into the EXISTING Roma-BRT checkout; does not create a separate project.
# Run from the repository root in Termux/Linux: bash tools/install_mapgen.sh
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"
DEST="addons/mapgen"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ -e "$DEST/plugin.cfg" ]; then
  echo "MapGen already exists at $DEST; leaving it untouched."
  exit 0
fi
mkdir -p addons
 git clone --depth 1 https://github.com/MarcelloMorettoni/mapgen.git "$TMP/mapgen"
if [ ! -f "$TMP/mapgen/addons/mapgen/plugin.cfg" ]; then
  echo "ERROR: upstream MapGen addon/plugin.cfg not found; no files copied." >&2
  exit 1
fi
cp -a "$TMP/mapgen/addons/mapgen" "$DEST"
# Copy the upstream texture-fetch helper when present; texture assets are not guessed or fabricated.
if [ -f "$TMP/mapgen/tools/fetch_textures.py" ]; then
  mkdir -p tools/mapgen
  cp "$TMP/mapgen/tools/fetch_textures.py" tools/mapgen/fetch_textures.py
fi
printf '\nMapGen source installed to %s.\n' "$DEST"
printf 'Open the existing Roma-BRT project in Godot and enable the MapGen plugin from Project > Project Settings > Plugins.\n'
printf 'This installer intentionally does not add a second terrain generator to main.tscn: integrate MapGen output only after choosing the terrain workflow.\n'