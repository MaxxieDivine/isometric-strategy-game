class_name CitySiteScorer
extends RefCounted
## Ranks tiles as places to found a city. Shared logic: the advisor uses it to
## pick a suggestion, and rival AI can reuse it. It only produces options;
## whoever calls it decides which one to act on or recommend.
##
## Only what `player_id` has explored counts (unexplored tiles in a work area
## score a small flat amount), so a suggestion never leaks hidden terrain.
## Weights live in data/city_sites.json. Reads state only; changes nothing.

const PATH := "res://data/city_sites.json"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


static func search_radius() -> int:
	return int(rules().get("search_radius", 6))


static func _weight(key: String) -> int:
	var weights: Dictionary = rules().get("weights", {})
	return int(weights.get(key, 0))


## Candidate sites reachable over explored land from `origin` within
## `max_steps` (-1: search_radius), best first. Each entry:
## { cell, score, food, production, trade, coast: bool, distance, overlap }.
## `limit` > 0 keeps only that many. Ties go to the nearer tile, then the
## lower row and column, so the ranking is fully deterministic.
static func rank(state: GameState, player_id: int, origin: Vector2i, max_steps: int = -1,
		limit: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not state.map.in_bounds(origin):
		return result
	var steps := reachable_land(state, player_id, origin, search_radius() if max_steps < 0 else max_steps)
	for cell: Vector2i in steps:
		if can_settle(state, player_id, cell):
			result.append(score_site(state, player_id, cell, int(steps[cell])))
	result.sort_custom(_better)
	if limit > 0 and result.size() > limit:
		result.resize(limit)
	return result


## Scores one tile as a city site, `distance` steps from where the settler is.
static func score_site(state: GameState, player_id: int, cell: Vector2i, distance: int = 0) -> Dictionary:
	var map := state.map
	var explored := state.explored[player_id]
	var total := Yields.city_center(map, cell)
	var unexplored := 0
	var overlap := 0
	for other in IsoGrid.cells_within(cell, CityRules.work_radius(), map.width, map.height):
		if other == cell:
			continue
		if explored[IsoGrid.index_of(other, map.width)] == 0:
			unexplored += 1
			continue
		total += Yields.tile(map, other)
		if _in_any_city_area(state, other):
			overlap += 1
	var coast := is_coastal(state, player_id, cell)
	var score := total[Yields.FOOD] * _weight("food") + total[Yields.PRODUCTION] * _weight("production") \
		+ total[Yields.TRADE] * _weight("trade") + unexplored * _weight("unexplored_tile") \
		+ (_weight("coast") if coast else 0) - distance * _weight("per_step_away") \
		- overlap * _weight("overlap_tile") - _edge_shortfall(map, cell) * _weight("edge_step_short")
	return { "cell": cell, "score": score, "food": total[Yields.FOOD], "production": total[Yields.PRODUCTION],
		"trade": total[Yields.TRADE], "coast": coast, "distance": distance, "overlap": overlap }


## Land the player has explored, with no other city too close, and no camp or
## foreign unit on it.
static func can_settle(state: GameState, player_id: int, cell: Vector2i) -> bool:
	if not state.is_explored(player_id, cell) or not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
		return false
	for city in state.cities:
		if IsoGrid.step_distance(city.position, cell) <= CityRules.no_city_within():
			return false
	return state.camp_at(cell) == null and state.enemy_units_at(cell, player_id).is_empty()


## Next to known ocean.
static func is_coastal(state: GameState, player_id: int, cell: Vector2i) -> bool:
	for other in IsoGrid.neighbors(cell, state.map.width, state.map.height):
		if state.is_explored(player_id, other) and not TerrainDefs.passable_by_land(state.map.get_terrain(other)):
			return true
	return false


## Explored land cells connected to `origin` over land, with their step count
## (cell -> steps), breadth first up to `max_steps`.
static func reachable_land(state: GameState, player_id: int, origin: Vector2i, max_steps: int) -> Dictionary:
	var steps := { origin: 0 }
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		var next: Array[Vector2i] = []
		for cell in frontier:
			var here := int(steps[cell])
			if here >= max_steps:
				continue
			for other in IsoGrid.neighbors(cell, state.map.width, state.map.height):
				if steps.has(other) or not state.is_explored(player_id, other) \
						or not TerrainDefs.passable_by_land(state.map.get_terrain(other)):
					continue
				steps[other] = here + 1
				next.append(other)
		frontier = next
	return steps


static func _in_any_city_area(state: GameState, cell: Vector2i) -> bool:
	for city in state.cities:
		if IsoGrid.step_distance(city.position, cell) <= CityRules.work_radius():
			return true
	return false


## How many steps short of the edge clearance the tile is (0 when clear).
static func _edge_shortfall(map: MapState, cell: Vector2i) -> int:
	var clearance := int(rules().get("edge_clearance", 3))
	# Rows are half a step apart in the stacked layout.
	var to_edge := mini(mini(cell.x, map.width - 1 - cell.x), mini(cell.y, map.height - 1 - cell.y) >> 1)
	return maxi(0, clearance - to_edge)


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	if int(a["distance"]) != int(b["distance"]):
		return int(a["distance"]) < int(b["distance"])
	var ca: Vector2i = a["cell"]
	var cb: Vector2i = b["cell"]
	return ca.y < cb.y if ca.y != cb.y else ca.x < cb.x
