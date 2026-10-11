@tool
class_name MapFlow
extends RefCounted
## D8 drainage over a finished heightfield: which way the water on each cell
## leaves, and how much has gathered by the time it gets there.
##
## This exists for the waterfalls, and it is the whole reason they read as part
## of the landscape. Water does not fall off a random cliff, it falls off the
## cliff a stream happens to run over, so the falls are placed on the drainage
## network rather than on "steep spot, nice view" -- which is the version that
## looks like someone stuck a waterfall decal on a mountain.
##
## One steepest-descent pass plus one height-ordered sweep. No iteration to
## convergence, so a 384^2 field routes in well under a second; the sort is the
## engine's, not GDScript's.

var dim := 0
var cell := 1.0
var size_m := 0.0

## Index of the steepest downhill neighbour, or -1 where the water stops: pits
## left behind by erosion, and every cell on the map border (water leaves).
var down := PackedInt32Array()
## Cells draining through here, this one included. 1.0 on a ridge top, and
## roughly dim^2 at the mouth of the map's main valley.
var accum := PackedFloat32Array()
## Cell indices, highest first. The order the accumulation sweep runs in, and
## a useful "walk the map from the top down" for anything else.
var order := PackedInt32Array()


static func build(hf: MapHeightfield) -> MapFlow:
	var f := MapFlow.new()
	f.dim = hf.dim
	f.cell = hf.cell
	f.size_m = hf.size_m
	f._route(hf)
	f._accumulate(hf)
	return f


# ---------------------------------------------------------------------------
# passes
# ---------------------------------------------------------------------------

func _route(hf: MapHeightfield) -> void:
	var n := dim * dim
	down.resize(n)
	# Border cells drain off the map. Marking them as pits up front also keeps
	# the inner loop free of bounds checks.
	down.fill(-1)

	var offs := PackedInt32Array([-1, 1, -dim, dim, -dim - 1, -dim + 1, dim - 1, dim + 1])
	# Compare drop per metre travelled, not raw drop. A diagonal step covers
	# 1.41 cells, so scoring on raw drop sends every stream in the map off
	# diagonally and the network comes out visibly herringboned.
	var inv_s := 1.0 / cell
	var inv_d := 1.0 / (cell * sqrt(2.0))
	var invd := PackedFloat32Array([inv_s, inv_s, inv_s, inv_s, inv_d, inv_d, inv_d, inv_d])

	var h := hf.height
	for zi in range(1, dim - 1):
		var row := zi * dim
		for xi in range(1, dim - 1):
			var i := row + xi
			var hi := h[i]
			var best := -1
			var best_grad := 0.0
			for k in 8:
				var j := i + offs[k]
				var g := (hi - h[j]) * invd[k]
				if g > best_grad:
					best_grad = g
					best = j
			down[i] = best


func _accumulate(hf: MapHeightfield) -> void:
	var n := dim * dim
	accum.resize(n)
	accum.fill(1.0)

	# Cells have to be processed strictly highest-first, and sort_custom() over
	# 150k entries in GDScript costs more than the rest of the generator put
	# together. So pack the quantised height into the high bits of a 64-bit key
	# and let the engine's native integer sort do the work: height gets 32 bits,
	# which is sub-millimetre on any relief this thing produces, and the low 21
	# bits carry the cell index (enough for the 1024 resolution cap).
	var lo := hf.min_h
	var inv := 4294967295.0 / maxf(hf.max_h - hf.min_h, 0.0001)
	var keys := PackedInt64Array()
	keys.resize(n)
	for i in n:
		keys[i] = (int((hf.height[i] - lo) * inv) << 21) | i
	keys.sort()

	order.resize(n)
	for k in n:
		order[k] = keys[n - 1 - k] & 0x1FFFFF

	for i in order:
		var d := down[i]
		if d >= 0:
			accum[d] += accum[i]


# ---------------------------------------------------------------------------
# queries
# ---------------------------------------------------------------------------

func cell_x(i: int) -> float:
	return -size_m * 0.5 + float(i % dim) * cell


func cell_z(i: int) -> float:
	return -size_m * 0.5 + float(i / dim) * cell


## Metres between two adjacent cells: diagonal neighbours are further apart,
## and everything that measures a gradient has to know it.
func step_length(a: int, b: int) -> float:
	return cell if (absi(a - b) == 1 or absi(a - b) == dim) else cell * sqrt(2.0)


## Fall per metre travelled from `a` to its neighbour `b`, as a tangent.
func gradient(hf: MapHeightfield, a: int, b: int) -> float:
	return (hf.height[a] - hf.height[b]) / step_length(a, b)


## The neighbour that feeds this cell with the most water, or -1 if nothing
## does. Walking back up this is how a fall gets a stream above its lip
## instead of water appearing out of the rock face.
func upstream_of(i: int) -> int:
	var xi := i % dim
	var zi := i / dim
	if xi <= 0 or zi <= 0 or xi >= dim - 1 or zi >= dim - 1:
		return -1
	var best := -1
	var best_accum := 0.0
	for off in [-1, 1, -dim, dim, -dim - 1, -dim + 1, dim - 1, dim + 1]:
		var j: int = i + off
		if down[j] == i and accum[j] > best_accum:
			best_accum = accum[j]
			best = j
	return best


## Channel cells from `i` down, `i` included. Stops at a pit or at `max_steps`.
func trace_downstream(i: int, max_steps: int) -> PackedInt32Array:
	var out := PackedInt32Array([i])
	var cur := i
	for _k in max_steps:
		var nxt := down[cur]
		if nxt < 0:
			break
		out.append(nxt)
		cur = nxt
	return out


## Channel cells above `i`, ordered downhill so the result ends at `i`.
func trace_upstream(i: int, max_steps: int) -> PackedInt32Array:
	var rev := PackedInt32Array()
	var cur := i
	for _k in max_steps:
		var up := upstream_of(cur)
		if up < 0:
			break
		rev.append(up)
		cur = up
	var out := PackedInt32Array()
	for k in range(rev.size() - 1, -1, -1):
		out.append(rev[k])
	out.append(i)
	return out
