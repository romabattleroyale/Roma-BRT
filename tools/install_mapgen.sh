#!/usr/bin/env bash
# Install MapGen into this EXISTING Roma-BRT project (Android/Termux or Linux).
# Put mapgen-main.zip in the repository root, then run: bash tools/install_mapgen.sh
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
DEST="addons/mapgen"
if [ -f "$DEST/plugin.cfg" ]; then
  echo "MapGen is already installed at $DEST."
  exit 0
fi
ZIP=""
for candidate in "$ROOT/mapgen-main.zip" "$ROOT/MapGen-main.zip" "$ROOT/mapgen.zip"; do
  if [ -f "$candidate" ]; then ZIP="$candidate"; break; fi
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if [ -n "$ZIP" ]; then
  echo "Installing MapGen from $ZIP"
  unzip -q "$ZIP" -d "$TMP"
else
  echo "No local MapGen ZIP found; downloading the upstream source."
  git clone --depth 1 https://github.com/MarcelloMorettoni/mapgen.git "$TMP/mapgen"
fi
SRC=""
for candidate in "$TMP/mapgen-main/addons/mapgen" "$TMP/mapgen/addons/mapgen"; do
  if [ -f "$candidate/plugin.cfg" ]; then SRC="$candidate"; break; fi
done
if [ -z "$SRC" ]; then
  echo "ERROR: archive does not contain addons/mapgen/plugin.cfg; nothing was installed." >&2
  exit 1
fi
mkdir -p addons
cp -a "$SRC" "$DEST"
# Remove upstream editor cache artifacts if included; Godot regenerates these locally.
find "$DEST" -type d -name .godot -prune -exec rm -rf {} +
echo "MapGen installed into $DEST in the existing Roma-BRT project."
echo "Next: open this project in Godot > Project Settings > Plugins and enable MapGen."
echo "MapGen is installed as a plugin/library; it does not replace the existing Terrain3D in main.tscn."
