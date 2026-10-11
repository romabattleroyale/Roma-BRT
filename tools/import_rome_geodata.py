#!/usr/bin/env python3
"""Download real geographic source data for the Roma-BRT playable terrain.

Default bounds cover a 2 km x 2 km square centered on the Colosseum.
Outputs:
  res://data/rome_geodata/roads.geojson  (OSM road centerlines, coordinates in game metres)
  res://data/rome_geodata/elevation.json (real DEM samples in game metres)
  res://terrain_materials/river_path.json (real OSM Tevere centerline, heightmap pixel coordinates)
This is an import step, not a runtime network dependency. Run from the repo root.
"""
from __future__ import annotations
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "rome_geodata"
# Colosseum-centered bounds; game world maps west/east to x=0..2000,
# north/south to z=0..2000. This replaces invented rectangular city layouts.
CENTER_LAT, CENTER_LON = 41.8902, 12.4922
HALF_SIZE_M = 1000.0
# Elevation sampling at 50 m intervals, then interpolate in Godot/import pipeline.
DEM_STEP_M = 50.0
OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.nchc.org.tw/api/interpreter",
]
WORLD_SIZE_M = 2000.0
HEIGHTMAP_SAMPLES = 1081
RIVER_HALF_WIDTH_M = 45.0  # 90 m total width, within the 70–120 m urban Tiber range

USER_AGENT = "RomaBRT-GeodataImporter/1.0 (terrain import; OSM contributors credited)"

def bounds():
    lat_delta = HALF_SIZE_M / 111_320.0
    lon_delta = HALF_SIZE_M / (111_320.0 * math.cos(math.radians(CENTER_LAT)))
    return (CENTER_LAT-lat_delta, CENTER_LON-lon_delta,
            CENTER_LAT+lat_delta, CENTER_LON+lon_delta)

def request(url: str, data: bytes | None = None, timeout: int = 90):
    req = urllib.request.Request(url, data=data, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded" if data else "application/json",
    })
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def _overpass_json(query: str, label: str):
    """Try independent Overpass instances with bounded retries and useful diagnostics."""
    errors = []
    for endpoint in OVERPASS:
        for attempt in range(2):
            try:
                raw = request(endpoint, urllib.parse.urlencode({"data": query}).encode(), timeout=75)
                payload = json.loads(raw)
                if not isinstance(payload, dict) or "elements" not in payload:
                    raise RuntimeError("Overpass response has no elements array")
                print(f"{label}: OK from {endpoint} (attempt {attempt + 1})")
                return payload
            except Exception as exc:
                errors.append(f"{endpoint} attempt {attempt + 1}: {type(exc).__name__}: {exc}")
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"{label}: all Overpass instances failed; " + " | ".join(errors))

def fetch_osm():
    south, west, north, east = bounds()
    query = f"""[out:json][timeout:60];
    way[highway~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|road|track|pedestrian|footway|path|cycleway|steps)$"]({south},{west},{north},{east});
    out geom;"""
    data = _overpass_json(query, "OSM roads")
    features = []
    for way in data.get("elements", []):
        tags = way.get("tags", {})
        points = way.get("geometry", [])
        if len(points) < 2:
            continue
        coords = []
        for p in points:
            x = (p["lon"] - CENTER_LON) * 111_320.0 * math.cos(math.radians(CENTER_LAT)) + 1000.0
            z = 1000.0 - (p["lat"] - CENTER_LAT) * 111_320.0
            coords.append([round(x, 2), round(z, 2)])
        features.append({
            "type": "Feature",
            "properties": {
                "osm_id": way.get("id"),
                "highway": tags.get("highway", "residential"),
                "name": tags.get("name", ""),
                "surface": tags.get("surface", ""),
                "lanes": tags.get("lanes", ""),
                "width": tags.get("width", ""),
                "lit": tags.get("lit", ""),
                "oneway": tags.get("oneway", ""),
                "bridge": tags.get("bridge", ""),
                "tunnel": tags.get("tunnel", ""),
                "junction": tags.get("junction", ""),
                "sidewalk": tags.get("sidewalk", ""),
                "maxspeed": tags.get("maxspeed", ""),
            },
            "geometry": {"type": "LineString", "coordinates": coords},
        })
    return {"type": "FeatureCollection", "source": "OpenStreetMap contributors", "features": features}


def fetch_river_path():
    """Build the runtime river ribbon from real OpenStreetMap waterway geometry."""
    south, west, north, east = bounds()
    query = f"""[out:json][timeout:60];
    way["waterway"="river"]({south},{west},{north},{east});
    out geom;"""
    data = _overpass_json(query, "OSM Tevere")

    segments = []
    for way in data.get("elements", []):
        geometry = way.get("geometry", [])
        if len(geometry) < 2:
            continue
        coords = []
        for p in geometry:
            x_m = (p["lon"] - CENTER_LON) * 111_320.0 * math.cos(math.radians(CENTER_LAT)) + 1000.0
            z_m = 1000.0 - (p["lat"] - CENTER_LAT) * 111_320.0
            if 0.0 <= x_m <= WORLD_SIZE_M and 0.0 <= z_m <= WORLD_SIZE_M:
                coords.append((x_m, z_m))
        if len(coords) >= 2:
            segments.append(coords)

    if not segments:
        raise RuntimeError("OSM returned no waterway=river geometry inside the Rome map bounds")

    route = segments.pop(0)
    while segments:
        end = route[-1]
        best = None
        best_dist = float("inf")
        reverse = False
        for idx, seg in enumerate(segments):
            for rev, candidate in ((False, seg[0]), (True, seg[-1])):
                dist = math.hypot(candidate[0] - end[0], candidate[1] - end[1])
                if dist < best_dist:
                    best, best_dist, reverse = idx, dist, rev
        if best is None or best_dist > 120.0:
            break
        segment = segments.pop(best)
        if reverse:
            segment.reverse()
        if math.hypot(segment[0][0] - route[-1][0], segment[0][1] - route[-1][1]) < 3.0:
            route.extend(segment[1:])
        else:
            route.extend(segment)

    spacing = WORLD_SIZE_M / (HEIGHTMAP_SAMPLES - 1)
    points = []
    last = None
    for x_m, z_m in route:
        px = x_m / spacing
        pz = z_m / spacing
        if last is None or math.hypot(px - last[0], pz - last[1]) >= 1.0:
            points.append({"x": round(px, 3), "z": round(pz, 3), "half_width": RIVER_HALF_WIDTH_M})
            last = (px, pz)

    if len(points) < 20:
        raise RuntimeError(f"OSM Tevere path too short after clipping/deduplication: {len(points)} points")
    return {
        "source": "OpenStreetMap contributors; waterway=river; map bounds centered on Colosseum",
        "world_size_m": WORLD_SIZE_M,
        "heightmap_samples": HEIGHTMAP_SAMPLES,
        "half_width_m": RIVER_HALF_WIDTH_M,
        "points": points,
    }

def fetch_elevation():
    # Open-Meteo's elevation API serves a real global DEM. Sample a 41x41 grid
    # (50 m spacing) to avoid a huge number of requests and preserve terrain relief.
    south, west, north, east = bounds()
    rows = []
    count = int((2 * HALF_SIZE_M) / DEM_STEP_M) + 1
    for iz in range(count):
        lat = north - (iz * DEM_STEP_M / 111_320.0)
        row = []
        for ix in range(count):
            lon = west + (ix * DEM_STEP_M / (111_320.0 * math.cos(math.radians(CENTER_LAT))))
            row.append((lat, lon))
        rows.append(row)
    points = [p for row in rows for p in row]
    values = []
    # API accepts coordinate lists. Chunk conservatively and preserve order.
    for start in range(0, len(points), 80):
        chunk = points[start:start+80]
        params = urllib.parse.urlencode({
            "latitude": ",".join(f"{p[0]:.6f}" for p in chunk),
            "longitude": ",".join(f"{p[1]:.6f}" for p in chunk),
        })
        data = json.loads(request("https://api.open-meteo.com/v1/elevation?" + params).decode())
        elevations = data.get("elevation", [])
        if len(elevations) != len(chunk):
            raise RuntimeError(f"DEM returned {len(elevations)} elevations for {len(chunk)} samples")
        values.extend(float(v) for v in elevations)
        time.sleep(0.15)
    return {
        "source": "Open-Meteo elevation API (global DEM; see Open-Meteo terms)",
        "center": {"lat": CENTER_LAT, "lon": CENTER_LON},
        "bounds_game_metres": [0, 0, 2000, 2000],
        "step_metres": DEM_STEP_M,
        "width": count, "height": count,
        "elevation_metres_north_to_south": [values[i*count:(i+1)*count] for i in range(count)],
    }

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print("Downloading actual OpenStreetMap road centerlines around the Colosseum...")
    roads = fetch_osm()
    if len(roads["features"]) < 20:
        raise RuntimeError(f"Unexpectedly few roads returned: {len(roads['features'])}")
    (OUT / "roads.geojson").write_text(json.dumps(roads, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Saved {len(roads['features'])} real road/path centerlines.")
    print("Sampling real DEM elevations...")
    dem = fetch_elevation()
    (OUT / "elevation.json").write_text(json.dumps(dem, separators=(",", ":")), encoding="utf-8")
    print(f"Saved {dem['width']}x{dem['height']} elevation samples.")
    print("Downloading actual OSM Tevere centerline...")
    river = fetch_river_path()
    river_out = ROOT / "terrain_materials" / "river_path.json"
    river_out.parent.mkdir(parents=True, exist_ok=True)
    river_out.write_text(json.dumps(river, separators=(",", ":")), encoding="utf-8")
    print(f"Saved real Tevere path: {len(river['points'])} points, half-width={RIVER_HALF_WIDTH_M:.0f} m.")
    print("Source: © OpenStreetMap contributors; elevation: Open-Meteo global DEM.")
    print("NOTE: these are source datasets; Godot terrain/road mesh baking is a separate integration step.")

if __name__ == "__main__":
    main()
