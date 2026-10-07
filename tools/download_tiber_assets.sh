#!/usr/bin/env bash
set -euo pipefail

: "${SKETCHFAB_TOKEN:?SKETCHFAB_TOKEN is required}"

ROOT="poi_test_tiber_island/poi_test/assets/models"
rm -rf "$ROOT"
mkdir -p "$ROOT"
echo "Starting verified 9-asset Sketchfab download"

assets=(
  "ponte_fabricio|8511381f0b844306ab53e4fbc5660095"
  "ponte_cestio|58691a67ba774f2bbccff7ce8f85d1d8"
  "basilica_san_bartolomeo|132e19cdff9247f092c8d85f903d67fc"
  "torre_caetani|6c821f2aae3b4e8db5d94c6f48fb568b"
  "casa_01|bb5406594f4d4dd59daf1e19cb08e88c"
  "pavimento|a70ea3530a004baebe6c33c29cebe1de"
  "fontana|8580500134194ba5be3f6df7593049f2"
  "lampione|17e2bc2ec7de42d08d98e3a6c886a8b2"
  "albero|430f1d7b0d2748888a67539c18626eb9"
)

for item in "${assets[@]}"; do
  NAME="${item%%|*}"
  MODEL_UID="${item##*|}"
  META="/tmp/${NAME}.json"
  DL="/tmp/${NAME}-download.json"
  ZIP="/tmp/${NAME}.zip"
  DIR="/tmp/${NAME}"
  OUT="$ROOT/${NAME}.glb"

  echo "Downloading ${NAME} (${MODEL_UID})"
  curl -fsSL "https://api.sketchfab.com/v3/models/${MODEL_UID}" -o "${META}"
  LICENSE=$(jq -r '.license.label // empty' "${META}")
  DOWNLOADABLE=$(jq -r '.isDownloadable // false' "${META}")
  case "${LICENSE}" in
    "CC Attribution"|"CC0") ;;
    *) echo "Rejected ${NAME}: license=${LICENSE}"; exit 1 ;;
  esac
  test "${DOWNLOADABLE}" = "true"

  CODE=$(curl -sS -o "${DL}" -w "%{http_code}" -H "Authorization: Bearer ${SKETCHFAB_TOKEN}" "https://api.sketchfab.com/v3/models/${MODEL_UID}/download")
  if [ "${CODE}" != "200" ]; then
    CODE=$(curl -sS -o "${DL}" -w "%{http_code}" -H "Authorization: Token ${SKETCHFAB_TOKEN}" "https://api.sketchfab.com/v3/models/${MODEL_UID}/download")
  fi
  test "${CODE}" = "200"

  URL=$(jq -r '.gltf.url // empty' "${DL}")
  test -n "${URL}"
  curl -fsSL "${URL}" -o "${ZIP}"

  rm -rf "${DIR}"
  mkdir -p "${DIR}"
  unzip -q "${ZIP}" -d "${DIR}"
  GLTF=$(find "${DIR}" -type f -name '*.gltf' | head -n 1)
  test -n "${GLTF}"

  gltf-transform copy "${GLTF}" "${OUT}"
  rm -rf "${DIR}" "${ZIP}" "${DL}" "${META}"
  test -s "${OUT}"
done

EXPECTED="albero basilica_san_bartolomeo casa_01 fontana lampione pavimento ponte_cestio ponte_fabricio torre_caetani"
ACTUAL=$(find "$ROOT" -maxdepth 1 -type f -name '*.glb' -printf '%f\n' | sed 's/\.glb$//' | sort | tr '\n' ' ')
WANT=$(printf '%s\n' $EXPECTED | sort | tr '\n' ' ')
test "$ACTUAL" = "$WANT"
test "$(find "$ROOT" -type f | wc -l)" -eq 9

python3 - <<'PY'
from pathlib import Path
from pygltflib import GLTF2
root=Path("poi_test_tiber_island/poi_test/assets/models")
total=0
size=sum(p.stat().st_size for p in root.glob("*.glb"))
if size >= 50*1024*1024: raise SystemExit("GLB budget exceeded")
for p in sorted(root.glob("*.glb")):
    g=GLTF2().load_binary(str(p))
    tris=0
    for mesh in g.meshes or []:
        for prim in mesh.primitives:
            if prim.indices is not None:
                n=g.accessors[prim.indices].count
            elif prim.attributes.POSITION is not None:
                n=g.accessors[prim.attributes.POSITION].count
            else:
                n=0
            tris += n//3
    print(p.name, tris, "triangles")
    if tris>15000: raise SystemExit(f"{p.name} exceeds 15000 triangles")
    total += tris
    for image in g.images or []:
        if image.uri: raise SystemExit(f"{p.name} has external texture")
if total>=200000: raise SystemExit("Total triangle budget exceeded")
print("PASS", total, "triangles", size, "bytes")
PY
