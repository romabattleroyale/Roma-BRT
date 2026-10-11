#!/usr/bin/env python3
"""Download real geographic source data for the Roma-BRT playable terrain.

Default bounds cover a 2 km x 2 km square centered on the Colosseum.
Outputs:
  res://data/rome_geodata/roads.geojson  (OSM road centerlines, coordinates in game metres)
  res://data/rome_geodata/elevation.json (real DEM samples in game metres)
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
# Elevation sampling at 100 m intervals, then interpolate in Godot/import pipeline.
DEM_STEP_M = 100.0
OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
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

def fetch_osm():
    south, west, north, east = bounds()
    query = f"""[out:json][timeout:60];
    way[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|pedestrian|footway|path|cycleway|steps)$"]({south},{west},{north},{east});
    out geom;"""
    last_error = None
    for endpoint in OVERPASS:
        try:
            raw = request(endpoint, urllib.parse.urlencode({"data": query}).encode())
            data = json.loads(raw)
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
                    },
                    "geometry": {"type": "LineString", "coordinates": coords},
                })
            return {"type":"FeatureCollection","source":"OpenStreetMap contributors","features":features}
        except Exception as exc:
            last_error = exc
            time.sleep(2)
    raise RuntimeError(f"Could not download OSM roads from any Overpass endpoint: {last_error}")

def fetch_elevation():
    # Open-Meteo's elevation API serves a real global DEM. Sample a 21x21 grid
    # (100 m spacing) to avoid a huge number of requests and preserve terrain relief.
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
    print("Source: © OpenStreetMap contributors; elevation: Open-Meteo global DEM.")
    print("NOTE: these are source datasets; Godot terrain/road mesh baking is a separate integration step.")

if __name__ == "__main__":
    main()
