@tool
class_name MapWater
extends RefCounted
## A single subdivided plane at the water level. One plane covers lakes, rivers
## in the canyon floor and the coastline at once, because the water level came
## out of the height distribution rather than being placed by hand.


static func build(hf: MapHeightfield, s: MapGenSettings, material: Material) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	# Slight overhang so the water reaches past the terrain edge and you never
	# see a hairline gap at the map border.
	plane.size = Vector2(hf.size_m * 1.02, hf.size_m * 1.02)
	# Enough subdivision for the vertex wave displacement to actually show.
	var sub: int = clampi(int(hf.size_m / 8.0), 16, 200)
	plane.subdivide_width = sub
	plane.subdivide_depth = sub

	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = material
	mi.position = Vector3(0.0, hf.water_level, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
