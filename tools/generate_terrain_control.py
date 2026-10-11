from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import maximum_filter, convolve

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "assets" / "heightmap.raw"
BANK = ROOT / "terrain_materials" / "river_mask.png"
OUT = ROOT / "build" / "terrain_control.bin"

MAP_SIZE_M = 2000.0
HEIGHT_SCALE_M = 48.0
RADIUS = 12
SLOPE_START = 12.0
SLOPE_FULL = 24.0

raw = np.fromfile(RAW, dtype=">u2")
side = int(np.sqrt(raw.size))
if side * side != raw.size:
    raise SystemExit(f"RAW non quadrato: {raw.size} campioni")
values = raw.reshape((side, side)).astype(np.float32)
min_u = int(values.min())
max_u = int(values.max())
source_range = max(1.0, float(max_u - min_u))
values = np.clip((values - min_u) / source_range, 0.0, 1.0)

# Match the runtime RAW importer: lightly smooth isolated sample spikes without
# flattening broad hills. This pass is intentionally identical to the Godot 3x3 kernel.
kernel = np.array([[1, 2, 1], [2, 4, 2], [1, 2, 1]], dtype=np.float32) / 16.0
smoothed = convolve(values, kernel, mode="nearest")
values = values * 0.55 + smoothed * 0.45

bank = np.asarray(Image.open(BANK).convert("L"), dtype=np.uint8) > 127
if bank.shape != values.shape:
    raise SystemExit(f"river_mask dimensione {bank.shape} != heightmap {(side, side)}")

# Equivalent to the original 5x5 bank dilation, but vectorized.
bank_dilated = maximum_filter(bank, size=5, mode="constant", cval=False)

spacing = MAP_SIZE_M / float(side - 1)
idx = np.arange(side)
x0 = np.maximum(0, idx - RADIUS)
x1 = np.minimum(side - 1, idx + RADIUS)
z0 = x0
z1 = x1

dx_dist = (x1 - x0).astype(np.float32) * spacing
dz_dist = (z1 - z0).astype(np.float32) * spacing

# Central differences over the same 24-pixel radius used by the Godot code.
dx = (values[:, x1] - values[:, x0]) * HEIGHT_SCALE_M / np.where(dx_dist > 0, dx_dist, 1.0)[None, :]
dz = (values[z1, :] - values[z0, :]) * HEIGHT_SCALE_M / np.where(dz_dist > 0, dz_dist, 1.0)[:, None]
slope_deg = np.degrees(np.arctan(np.sqrt(dx * dx + dz * dz)))
t = np.clip((slope_deg - SLOPE_START) / (SLOPE_FULL - SLOPE_START), 0.0, 1.0)
rock_weight = t * t * (3.0 - 2.0 * t)
# Rock on sustained slopes; soil only along the authored Tiber bank mask.
overlay_id = np.where(rock_weight > 0.01, 2, 1).astype(np.uint32)
overlay_weight = rock_weight.copy()
overlay_id = np.where(bank_dilated, 1, overlay_id)
overlay_weight = np.where(bank_dilated, np.maximum(overlay_weight, 0.28), overlay_weight)
blend = np.clip(np.rint(overlay_weight * 255.0), 0, 255).astype(np.uint32)
packed = (overlay_id << np.uint32(22)) | (blend << np.uint32(14))

OUT.parent.mkdir(parents=True, exist_ok=True)
packed.astype("<u4").tofile(OUT)
print(f"TERRAIN CONTROL OK: {side}x{side}, raw min/max={min_u}/{max_u}, bytes={OUT.stat().st_size}")
