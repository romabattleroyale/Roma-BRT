#!/usr/bin/env python3
"""Download five Poly Haven CC0 terrain texture sets and pack them for Terrain3D.

The API is queried for each asset's actual file URLs; no CDN URLs are guessed.
The source JPG maps are retained, and Terrain3D-ready RGBA PNGs are generated.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures" / "terrain"
RESOURCE = ROOT / "terrain_materials" / "terrain_assets_polyhaven_zones.tres"
API = "https://api.polyhaven.com"
USER_AGENT = "RomaBattleRoyaleTerrainImporter/1.0 (Poly Haven public API)"

ASSETS = [
    ("asphalt_02", "asphalt", "Asphalt Worn", 0, 0.055, 0.72),
    ("cobblestone_04", "cobblestone", "Roman Cobblestone", 1, 0.075, 0.82),
    ("aerial_grass_rock", "grass", "Aerial Grass and Rock", 2, 0.050, 0.88),
    ("brown_mud_leaves_01", "mud", "Brown Mud and Leaves", 3, 0.060, 0.90),
    ("concrete_floor_worn_001", "concrete", "Worn Concrete", 4, 0.055, 0.78),
]

def get_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=45) as response:
        return json.loads(response.read().decode("utf-8"))

def download(url: str, path: Path):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=90) as response:
        path.write_bytes(response.read())

def select_file(tree, map_key: str):
    node = tree.get(map_key, {})
    node = node.get("2k", {}) if isinstance(node, dict) else {}
    # Prefer JPG as requested; use PNG only when the asset does not expose JPG.
    for fmt in ("jpg", "png"):
        entry = node.get(fmt, {}) if isinstance(node, dict) else {}
        if isinstance(entry, dict) and entry.get("url"):
            return entry["url"], fmt
    raise RuntimeError(f"No 2k JPG/PNG file for map {map_key}")

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    RESOURCE.parent.mkdir(parents=True, exist_ok=True)
    generated = []
    for asset_id, short, display, texture_id, uv_scale, roughness in ASSETS:
        print(f"[Poly Haven] API files: {asset_id}", flush=True)
        tree = get_json(f"{API}/files/{asset_id}")
        source_paths = {}
        for map_name, api_key, target_suffix in (
            ("diffuse", "diffuse", "diffuse"),
            ("normal", "nor_gl", "normal"),
            ("rough", "rough", "rough"),
        ):
            url, fmt = select_file(tree, api_key)
            target = OUT / f"{short}_{target_suffix}.{fmt}"
            if not target.exists() or target.stat().st_size < 1024:
                print(f"  download {map_name} ({fmt})", flush=True)
                download(url, target)
            source_paths[map_name] = target

        diffuse = Image.open(source_paths["diffuse"]).convert("RGB")
        normal = Image.open(source_paths["normal"]).convert("RGB")
        rough = Image.open(source_paths["rough"]).convert("L")
        size = (2048, 2048)
        if diffuse.size != size:
            diffuse = diffuse.resize(size, Image.Resampling.LANCZOS)
        if normal.size != size:
            normal = normal.resize(size, Image.Resampling.LANCZOS)
        if rough.size != size:
            rough = rough.resize(size, Image.Resampling.LANCZOS)

        # No displacement map was requested, so use neutral midpoint height.
        albedo_rgba = diffuse.convert("RGBA")
        albedo_rgba.putalpha(Image.new("L", size, 128))
        normal_rgba = normal.convert("RGBA")
        normal_rgba.putalpha(rough)
        albedo_path = OUT / f"{short}_albedo_height.png"
        normal_path = OUT / f"{short}_normal_roughness.png"
        albedo_rgba.save(albedo_path, optimize=True)
        normal_rgba.save(normal_path, optimize=True)
        generated.append({
            "id": texture_id, "name": display, "short": short,
            "uv_scale": uv_scale, "roughness": roughness,
            "albedo": f"res://assets/textures/terrain/{albedo_path.name}",
            "normal": f"res://assets/textures/terrain/{normal_path.name}",
        })
        print(f"  packed: {albedo_path.name}, {normal_path.name}", flush=True)

    lines = [
        f'[gd_resource type="Terrain3DAssets" load_steps={1 + len(generated) * 3} format=3]',
        "",
    ]
    for item in generated:
        lines.append(f'[ext_resource type="Texture2D" path="{item["albedo"]}" id="{item["id"]}a"]')
        lines.append(f'[ext_resource type="Texture2D" path="{item["normal"]}" id="{item["id"]}n"]')
    lines.append("")
    sub_ids = ["Asphalt", "Cobblestone", "GrassRock", "MudLeaves", "Concrete"]
    for item, sub_id in zip(generated, sub_ids):
        lines += [
            f'[sub_resource type="Terrain3DTextureAsset" id="{sub_id}"]',
            f'name = "{item["name"]}"',
            f'id = {item["id"]}',
            f'albedo_texture = ExtResource("{item["id"]}a")',
            f'normal_texture = ExtResource("{item["id"]}n")',
            'normal_depth = 0.55',
            f'roughness = {item["roughness"]}',
            f'uv_scale = {item["uv_scale"]}',
            '',
        ]
    lines += [
        '[resource]',
        'texture_list = Array[Terrain3DTextureAsset]([' + ', '.join(f'SubResource("{sid}")' for sid in sub_ids) + '])',
        '',
    ]
    RESOURCE.write_text("\n".join(lines), encoding="utf-8")
    print(f"[Poly Haven] wrote {RESOURCE.relative_to(ROOT)}", flush=True)
    print("[Poly Haven] CC0 assets; sources retained in assets/textures/terrain/.", flush=True)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: Poly Haven terrain import failed: {exc}", file=sys.stderr)
        raise
