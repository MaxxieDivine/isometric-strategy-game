class_name MapGenerator
extends RefCounted
## Seeded procedural world generator. A pure function of (width, height, seed):
## the same inputs always produce the same map. No Nodes, runs headless.
##
## Steps: place 2–4 continent blobs, distort their coastlines with noise,
## clean up specks, then paint terrain by distance from the coast.

const MIN_CONTINENTS := 2
const MAX_CONTINENTS := 4
## A landmass needs at least this many tiles to count as a continent.
const MIN_CONTINENT_TILES := 40
## Islands smaller than this are sunk; enclosed lakes smaller than this are filled.
const MIN_FEATURE_TILES := 4
## Retries if blobs merge or split into the wrong number of continents.
const MAX_ATTEMPTS := 25

## Rough share of the ground area that becomes land.
const LAND_FRACTION := 0.36
## How strongly noise bends coastlines (relative to blob falloff 0..1).
const COAST_NOISE := 0.55
const COAST_NOISE_FREQUENCY := 0.11
## Distance from the map edge (ground units) over which land fades into ocean.
const EDGE_FALLOFF := 3.0

const TERRAIN_NOISE_FREQUENCY := 0.16
const HILL_THRESHOLD := 0.84
const FOREST_THRESHOLD := 0.74
const GRASSLAND_THRESHOLD := 0.46

const LAND := 1
const WATER := 0


static func generate(width: int, height: int, map_seed: int) -> MapState:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed

	var land := PackedByteArray()
	for attempt in MAX_ATTEMPTS:
		land = _build_land(width, height, rng)
		_clean_up_small_features(land, width, height)
		var continents := _count_large_components(land, width, height)
		if continents >= MIN_CONTINENTS and continents <= MAX_CONTINENTS:
			break

	var map := MapState.new(width, height)
	map.generation_seed = map_seed
	_assign_terrain(map, land, rng)
	return map


## Number of landmasses big enough to count as continents.
static func count_continents(map: MapState) -> int:
	var land := PackedByteArray()
	land.resize(map.terrain.size())
	for i in map.terrain.size():
		land[i] = WATER if map.terrain[i] == "ocean" else LAND
	return _count_large_components(land, map.width, map.height)


# --- Land shape -------------------------------------------------------------

static func _build_land(width: int, height: int, rng: RandomNumberGenerator) -> PackedByteArray:
	var ground_size := IsoGrid.ground_size(width, height)
	var count := rng.randi_range(MIN_CONTINENTS, MAX_CONTINENTS)
	var base_radius := sqrt(ground_size.x * ground_size.y * LAND_FRACTION / count / PI)

	var continents: Array[Dictionary] = []
	for i in count:
		var stretch := rng.randf_range(0.6, 1.0)
		# Keep area roughly constant when squashing the blob into an ellipse.
		var radius := base_radius * rng.randf_range(0.8, 1.2) / sqrt(stretch)
		continents.append({
			"center": _place_center(ground_size, radius, continents, rng),
			"radius": radius,
			"stretch": stretch,
			"angle": rng.randf() * TAU,
		})

	var noise := _make_noise(rng.randi(), COAST_NOISE_FREQUENCY)
	var land := PackedByteArray()
	land.resize(width * height)
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var g := IsoGrid.ground_position(cell)
			var elevation := -1.0
			for c in continents:
				var local: Vector2 = (g - c["center"]).rotated(-c["angle"])
				local.y /= c["stretch"]
				elevation = maxf(elevation, 1.0 - local.length() / c["radius"])
			elevation += noise.get_noise_2dv(g) * COAST_NOISE
			var edge_dist := minf(minf(g.x, ground_size.x - g.x), minf(g.y, ground_size.y - g.y))
			if edge_dist < EDGE_FALLOFF:
				elevation -= (EDGE_FALLOFF - edge_dist) / EDGE_FALLOFF
			var on_border := x == 0 or x == width - 1 or y < 2 or y >= height - 2
			land[IsoGrid.index_of(cell, width)] = LAND if elevation > 0.0 and not on_border else WATER
	return land


## Picks the candidate center that keeps this continent farthest from the others.
static func _place_center(ground_size: Vector2, radius: float, placed: Array[Dictionary], rng: RandomNumberGenerator) -> Vector2:
	var margin := Vector2.ONE * minf(EDGE_FALLOFF + radius * 0.6, ground_size.x * 0.3)
	var best := ground_size / 2.0
	var best_score := -INF
	for i in 40:
		var candidate := Vector2(
			rng.randf_range(margin.x, ground_size.x - margin.x),
			rng.randf_range(margin.y, ground_size.y - margin.y))
		var score := INF
		for other in placed:
			score = minf(score, candidate.distance_to(other["center"]) - radius - float(other["radius"]))
		if score > best_score:
			best_score = score
			best = candidate
		if placed.is_empty():
			break
	return best


static func _clean_up_small_features(land: PackedByteArray, width: int, height: int) -> void:
	for component in _components(land, width, height, LAND):
		if component.size() < MIN_FEATURE_TILES:
			for i in component:
				land[i] = WATER
	# The border is always water, so the world ocean contains index 0;
	# any other water body is an enclosed lake.
	for component in _components(land, width, height, WATER):
		if component.size() < MIN_FEATURE_TILES and not component.has(0):
			for i in component:
				land[i] = LAND


static func _count_large_components(land: PackedByteArray, width: int, height: int) -> int:
	var count := 0
	for component in _components(land, width, height, LAND):
		if component.size() >= MIN_CONTINENT_TILES:
			count += 1
	return count


## Connected regions (8-neighbor) of cells equal to `value`, as lists of indices.
static func _components(land: PackedByteArray, width: int, height: int, value: int) -> Array[PackedInt32Array]:
	var seen := PackedByteArray()
	seen.resize(land.size())
	var result: Array[PackedInt32Array] = []
	for start in land.size():
		if land[start] != value or seen[start] == 1:
			continue
		var component := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			component.append(i)
			for n in IsoGrid.neighbors(IsoGrid.cell_of(i, width), width, height):
				var j := IsoGrid.index_of(n, width)
				if land[j] == value and seen[j] == 0:
					seen[j] = 1
					stack.append(j)
		result.append(component)
	return result


# --- Terrain ----------------------------------------------------------------

static func _assign_terrain(map: MapState, land: PackedByteArray, rng: RandomNumberGenerator) -> void:
	var coast_distance := _distance_from_water(land, map.width, map.height)
	var hill_noise := _make_noise(rng.randi(), TERRAIN_NOISE_FREQUENCY)
	var moisture_noise := _make_noise(rng.randi(), TERRAIN_NOISE_FREQUENCY)

	for i in land.size():
		var cell := IsoGrid.cell_of(i, map.width)
		if land[i] == WATER:
			map.set_terrain(cell, "ocean")
			continue
		var d := coast_distance[i]
		var g := IsoGrid.ground_position(cell)
		# 0 on the coast, 1 three or more tiles inland.
		var inland := clampf((d - 1) / 3.0, 0.0, 1.0)
		var hilliness := _noise01(hill_noise, g) + 0.3 * inland
		var moisture := _noise01(moisture_noise, g)
		var id := "plains"
		if d >= 3 and hilliness > HILL_THRESHOLD:
			id = "hills"
		elif d >= 2 and moisture + 0.25 * inland > FOREST_THRESHOLD:
			id = "forest"
		elif moisture > GRASSLAND_THRESHOLD:
			id = "grassland"
		map.set_terrain(cell, id)


## Steps from each cell to the nearest water cell (0 for water itself).
static func _distance_from_water(land: PackedByteArray, width: int, height: int) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(land.size())
	distance.fill(-1)
	var frontier: Array[int] = []
	for i in land.size():
		if land[i] == WATER:
			distance[i] = 0
			frontier.append(i)
	var head := 0
	while head < frontier.size():
		var i := frontier[head]
		head += 1
		for n in IsoGrid.neighbors(IsoGrid.cell_of(i, width), width, height):
			var j := IsoGrid.index_of(n, width)
			if distance[j] == -1:
				distance[j] = distance[i] + 1
				frontier.append(j)
	return distance


static func _make_noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	return noise


static func _noise01(noise: FastNoiseLite, at: Vector2) -> float:
	return noise.get_noise_2dv(at) * 0.5 + 0.5
