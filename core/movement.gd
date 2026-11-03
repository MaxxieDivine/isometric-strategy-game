class_name Movement
extends RefCounted
## Movement rules: what a step costs and whether a unit may take it.

const IMPASSABLE := -1


## Move points needed to enter `cell`, or IMPASSABLE.
## Unexplored tiles are assumed to cost 1 (optimistic), so players can send
## units into the unknown; routes are re-planned as terrain is revealed.
## `flat`: the unit ignores terrain (UnitDefs.ignores_terrain), so every
## passable tile costs 1.
static func enter_cost(map: MapState, explored: PackedByteArray, cell: Vector2i, domain: String,
		flat: bool = false) -> int:
	if not explored.is_empty() and explored[IsoGrid.index_of(cell, map.width)] == 0:
		return 1
	var terrain := map.get_terrain(cell)
	if domain == "land" and not TerrainDefs.passable_by_land(terrain):
		return IMPASSABLE
	return 1 if flat else TerrainDefs.move_cost(terrain)


## enter_cost for a unit of `unit_type` (its domain and terrain rule).
static func unit_enter_cost(map: MapState, explored: PackedByteArray, cell: Vector2i, unit_type: String) -> int:
	return enter_cost(map, explored, cell, UnitDefs.domain(unit_type), UnitDefs.ignores_terrain(unit_type))


## Civ II rule: a unit with full moves may always enter a tile, even one that
## costs more than it has. Otherwise it needs enough moves left.
static func can_enter(moves_left: int, max_moves: int, cost: int) -> bool:
	if cost == IMPASSABLE or moves_left <= 0:
		return false
	return moves_left >= cost or moves_left == max_moves


## Total move cost of a path (excluding the starting tile).
static func path_cost(map: MapState, explored: PackedByteArray, path: Array[Vector2i], domain: String,
		flat: bool = false) -> int:
	var total := 0
	for cell in path:
		total += enter_cost(map, explored, cell, domain, flat)
	return total


## For each step of the unit's planned path, the turn it arrives there
## (0 = this turn, 1 = next turn, ...).
static func path_turns(unit: UnitState, map: MapState, explored: PackedByteArray) -> Array[int]:
	return turns_along(unit, unit.path, map, explored)


## Like path_turns, for a route the unit hasn't been given yet (a preview).
static func turns_along(unit: UnitState, path: Array[Vector2i], map: MapState,
		explored: PackedByteArray) -> Array[int]:
	var turns: Array[int] = []
	var max_moves := unit.max_moves()
	var moves_left := unit.moves_left
	var turn := 0
	for cell in path:
		var cost := unit_enter_cost(map, explored, cell, unit.type)
		if not can_enter(moves_left, max_moves, cost):
			turn += 1
			moves_left = max_moves
		moves_left = maxi(0, moves_left - cost)
		turns.append(turn)
	return turns
