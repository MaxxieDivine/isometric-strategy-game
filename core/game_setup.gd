class_name GameSetup
extends RefCounted
## Builds a new game: world, player, and starting units.

const START_TERRAIN: Array[String] = ["grassland", "plains"]
## Minimum steps between the start tile and the map edge.
const EDGE_CLEARANCE := 3
## Start candidates scoring within this much of the best are equally likely.
const START_SCORE_SLACK := 2
## Civ (data/civs.json) the human player plays.
const PLAYER_CIV := "player"
const STARTING_UNITS: Array[String] = ["settler", "warrior"]


static func new_game(map_seed: int, width: int, height: int) -> GameState:
	var state := GameState.new()
	state.rng.seed = map_seed
	state.map = MapGenerator.generate(width, height, map_seed)
	var civ := CivDefs.get_def(PLAYER_CIV)
	var player := state.add_player(String(civ["name"]), String(civ["color"]), PLAYER_CIV)
	var start := find_start(state.map, state.rng)
	for type in STARTING_UNITS:
		state.add_unit(type, player, start)
	Fog.reveal_for_units(state, player)
	state.ensure_barbarian_player()
	return state


## Picks a grassland/plains tile away from the edge with lots of usable land nearby.
static func find_start(map: MapState, rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var scores: Array[int] = []
	var best := -1
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			if not is_valid_start(map, cell):
				continue
			var score := _start_score(map, cell)
			candidates.append(cell)
			scores.append(score)
			best = maxi(best, score)
	var shortlist: Array[Vector2i] = []
	for i in candidates.size():
		if scores[i] >= best - START_SCORE_SLACK:
			shortlist.append(candidates[i])
	if shortlist.is_empty():
		push_warning("No valid start tile; using map center")
		return Vector2i(map.width >> 1, map.height >> 1)
	return shortlist[rng.randi_range(0, shortlist.size() - 1)]


static func is_valid_start(map: MapState, cell: Vector2i) -> bool:
	if not START_TERRAIN.has(map.get_terrain(cell)):
		return false
	return (cell.x >= EDGE_CLEARANCE and cell.x < map.width - EDGE_CLEARANCE
		and cell.y >= 2 * EDGE_CLEARANCE and cell.y < map.height - 2 * EDGE_CLEARANCE)


static func _start_score(map: MapState, cell: Vector2i) -> int:
	var score := 0
	for c in IsoGrid.cells_within(cell, 2, map.width, map.height):
		var terrain := map.get_terrain(c)
		if terrain != "ocean":
			score += 1
		if START_TERRAIN.has(terrain):
			score += 1
	return score
