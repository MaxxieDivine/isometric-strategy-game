extends SceneTree
## Headless tests for pathfinding, movement costs, multi-turn moves, fog,
## game setup, the calendar, and GameState saving.
## Run: godot --headless --path . --script res://tests/test_units.gd

var _failures := 0


func _initialize() -> void:
	_test_step_distance()
	_test_path_on_open_ground()
	_test_path_avoids_ocean()
	_test_no_path_when_walled_off()
	_test_path_is_optimal()
	_test_terrain_move_costs()
	_test_full_moves_rule()
	_test_entering_costly_tile_with_full_moves()
	_test_multi_turn_move()
	_test_path_turns()
	_test_fog_reveal_radius()
	_test_fog_visibility_after_move()
	_test_game_setup()
	_test_calendar()
	_test_game_state_round_trip()
	if _failures == 0:
		print("All unit tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

func _make_state(width: int = 12, height: int = 24, fill: String = "grassland") -> GameState:
	var state := GameState.new()
	state.map = MapState.new(width, height, fill)
	state.add_player("Test", "#ffffff")
	return state


func _all_known(map: MapState) -> PackedByteArray:
	var known := PackedByteArray()
	known.resize(map.width * map.height)
	known.fill(1)
	return known


func _is_connected_path(start: Vector2i, path: Array[Vector2i], map: MapState) -> bool:
	var prev := start
	for cell in path:
		if not IsoGrid.neighbors(prev, map.width, map.height).has(cell):
			return false
		prev = cell
	return true


## Reference Dijkstra (O(n²), fine for tiny maps). Returns -1 if unreachable.
func _dijkstra_cost(map: MapState, known: PackedByteArray, start: Vector2i, goal: Vector2i) -> int:
	var n := map.width * map.height
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[IsoGrid.index_of(start, map.width)] = 0
	while true:
		var best := -1
		for i in n:
			if done[i] == 0 and dist[i] >= 0 and (best == -1 or dist[i] < dist[best]):
				best = i
		if best == -1:
			return -1
		if best == IsoGrid.index_of(goal, map.width):
			return dist[best]
		done[best] = 1
		for nb in IsoGrid.neighbors(IsoGrid.cell_of(best, map.width), map.width, map.height):
			var cost := Movement.enter_cost(map, known, nb, "land")
			if cost == Movement.IMPASSABLE:
				continue
			var j := IsoGrid.index_of(nb, map.width)
			if dist[j] == -1 or dist[best] + cost < dist[j]:
				dist[j] = dist[best] + cost
	return -1


# --- Pathfinding --------------------------------------------------------------

func _test_step_distance() -> void:
	var center := Vector2i(5, 10)
	for n in IsoGrid.neighbors(center, 20, 40):
		_check(IsoGrid.step_distance(center, n) == 1, "neighbor %s should be 1 step away" % n)
	_check(IsoGrid.step_distance(center, Vector2i(7, 10)) == 2, "two tiles right should be 2 steps")
	_check(IsoGrid.step_distance(center, Vector2i(5, 14)) == 2, "two tiles down should be 2 steps")
	_check(IsoGrid.cells_within(center, 1, 20, 40).size() == 9, "radius 1 should cover 9 tiles")
	_check(IsoGrid.cells_within(center, 2, 20, 40).size() == 25, "radius 2 should cover 25 tiles")


func _test_path_on_open_ground() -> void:
	var map := MapState.new(12, 24, "grassland")
	var start := Vector2i(3, 6)
	var goal := Vector2i(6, 6)
	var path := Pathfinder.find_path(map, _all_known(map), start, goal)
	_check(path.size() == IsoGrid.step_distance(start, goal), "open-ground path should be as short as possible")
	_check(not path.is_empty() and path.back() == goal, "path should end at the goal")
	_check(_is_connected_path(start, path, map), "path steps should be adjacent")


## Rows 10–11 are ocean except a gap at x = 8 (any crossing must touch them).
func _walled_map(with_gap: bool) -> MapState:
	var map := MapState.new(12, 24, "grassland")
	for y in [10, 11]:
		for x in map.width:
			if not (with_gap and x == 8):
				map.set_terrain(Vector2i(x, y), "ocean")
	return map


func _test_path_avoids_ocean() -> void:
	var map := _walled_map(true)
	var start := Vector2i(2, 4)
	var path := Pathfinder.find_path(map, _all_known(map), start, Vector2i(2, 18))
	_check(not path.is_empty(), "should find a path through the gap")
	_check(_is_connected_path(start, path, map), "gap path steps should be adjacent")
	var uses_gap := false
	for cell in path:
		_check(map.get_terrain(cell) != "ocean", "land path should never enter ocean (%s)" % cell)
		if cell.x == 8 and (cell.y == 10 or cell.y == 11):
			uses_gap = true
	_check(uses_gap, "path should cross through the gap")


func _test_no_path_when_walled_off() -> void:
	var map := _walled_map(false)
	var path := Pathfinder.find_path(map, _all_known(map), Vector2i(2, 4), Vector2i(2, 18))
	_check(path.is_empty(), "no path should exist across a solid ocean wall")
	var to_ocean := Pathfinder.find_path(map, _all_known(map), Vector2i(2, 4), Vector2i(2, 10))
	_check(to_ocean.is_empty(), "land units can't path into ocean")


func _test_path_is_optimal() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var terrains := ["grassland", "plains", "hills", "forest", "ocean"]
	var weights := PackedFloat32Array([3, 3, 2, 2, 1])
	for trial in 30:
		var map := MapState.new(10, 20)
		for i in map.terrain.size():
			map.terrain[i] = terrains[rng.rand_weighted(weights)]
		var known := _all_known(map)
		var start := Vector2i(rng.randi_range(0, 9), rng.randi_range(0, 19))
		var goal := Vector2i(rng.randi_range(0, 9), rng.randi_range(0, 19))
		map.set_terrain(start, "grassland")
		map.set_terrain(goal, "grassland")
		if start == goal:
			continue
		var path := Pathfinder.find_path(map, known, start, goal)
		var expected := _dijkstra_cost(map, known, start, goal)
		if expected == -1:
			_check(path.is_empty(), "trial %d: unreachable goal should give empty path" % trial)
		else:
			_check(_is_connected_path(start, path, map), "trial %d: path should be connected" % trial)
			var cost := Movement.path_cost(map, known, path, "land")
			_check(cost == expected, "trial %d: A* cost %d != optimal %d" % [trial, cost, expected])


# --- Movement -----------------------------------------------------------------

func _test_terrain_move_costs() -> void:
	_check(TerrainDefs.move_cost("grassland") == 1, "grassland costs 1")
	_check(TerrainDefs.move_cost("plains") == 1, "plains cost 1")
	_check(TerrainDefs.move_cost("hills") == 2, "hills cost 2")
	_check(TerrainDefs.move_cost("forest") == 2, "forest costs 2")
	var map := MapState.new(4, 8, "ocean")
	var known := _all_known(map)
	_check(Movement.enter_cost(map, known, Vector2i(1, 1), "land") == Movement.IMPASSABLE,
		"ocean is impassable for land units")
	var unknown := PackedByteArray()
	unknown.resize(known.size())
	_check(Movement.enter_cost(map, unknown, Vector2i(1, 1), "land") == 1,
		"unexplored tiles are assumed to cost 1")


func _test_full_moves_rule() -> void:
	_check(Movement.can_enter(1, 1, 2), "full moves can always enter a costly tile")
	_check(not Movement.can_enter(1, 2, 2), "partial moves can't enter a tile costing more")
	_check(Movement.can_enter(2, 2, 2), "enough moves can enter")
	_check(not Movement.can_enter(0, 1, 1), "no moves left means no entry")
	_check(not Movement.can_enter(1, 1, Movement.IMPASSABLE), "impassable is never enterable")


func _test_entering_costly_tile_with_full_moves() -> void:
	var state := _make_state()
	state.map.set_terrain(Vector2i(6, 10), "forest")
	var warrior := state.add_unit("warrior", 0, Vector2i(5, 10))
	Fog.reveal_for_units(state, 0)
	var events := GameActions.move_unit(state, warrior.id, Vector2i(6, 10))
	_check(warrior.position == Vector2i(6, 10), "1-move warrior should enter forest with full moves")
	_check(warrior.moves_left == 0, "entering forest should use all moves")
	_check(events.size() == 1 and events[0]["type"] == "unit_moved", "should emit one unit_moved event")


func _test_multi_turn_move() -> void:
	var state := _make_state()
	var warrior := state.add_unit("warrior", 0, Vector2i(5, 10))
	Fog.reveal_for_units(state, 0)
	var goal := Vector2i(5, 16)  # 3 steps away
	GameActions.move_unit(state, warrior.id, goal)
	_check(IsoGrid.step_distance(warrior.position, goal) == 2, "turn 1: should advance one step")
	_check(warrior.has_goal() and warrior.path.size() == 2, "turn 1: should keep 2 planned steps")
	_check(not warrior.needs_orders(), "a unit with orders doesn't need new ones")
	GameActions.end_turn(state)
	_check(IsoGrid.step_distance(warrior.position, goal) == 1, "turn 2: should continue automatically")
	GameActions.end_turn(state)
	_check(warrior.position == goal, "turn 3: should arrive")
	_check(not warrior.has_goal(), "orders should clear on arrival")
	GameActions.end_turn(state)
	_check(warrior.needs_orders(), "after arriving, the unit waits for orders next turn")
	_check(state.turn == 4, "turn counter should advance")


func _test_path_turns() -> void:
	var state := _make_state()
	state.map.set_terrain(Vector2i(6, 10), "forest")
	var warrior := state.add_unit("warrior", 0, Vector2i(5, 10))
	var known := _all_known(state.map)
	warrior.path = [Vector2i(6, 10), Vector2i(7, 10), Vector2i(8, 10)]
	var one_per_turn: Array[int] = [0, 1, 2]
	_check(Movement.path_turns(warrior, state.map, known) == one_per_turn,
		"1-move unit: one step per turn")
	warrior.moves_left = 0
	var starting_next_turn: Array[int] = [1, 2, 3]
	_check(Movement.path_turns(warrior, state.map, known) == starting_next_turn,
		"a unit with no moves left starts next turn")


# --- Fog ----------------------------------------------------------------------

func _count(tiles: PackedByteArray) -> int:
	return tiles.count(1)


func _test_fog_reveal_radius() -> void:
	var state := _make_state(20, 40)
	_check(_count(state.explored[0]) == 0, "everything starts unexplored")
	var revealed := Fog.reveal_around(state, 0, Vector2i(5, 10))
	_check(revealed == 9, "a unit on grassland reveals radius 1 (9 tiles), got %d" % revealed)
	_check(_count(state.explored[0]) == 9, "explored tiles should be stored in state")
	state.map.set_terrain(Vector2i(14, 30), "hills")
	revealed = Fog.reveal_around(state, 0, Vector2i(14, 30))
	_check(revealed == 25, "a unit on hills reveals radius 2 (25 tiles), got %d" % revealed)
	_check(Fog.reveal_around(state, 0, Vector2i(5, 10)) == 0, "re-revealing finds nothing new")


func _test_fog_visibility_after_move() -> void:
	var state := _make_state(20, 40)
	var start := Vector2i(5, 10)
	var warrior := state.add_unit("warrior", 0, start)
	Fog.reveal_for_units(state, 0)
	var goal := Vector2i(5, 18)  # 4 steps away
	GameActions.move_unit(state, warrior.id, goal)
	for i in 4:
		GameActions.end_turn(state)
	_check(warrior.position == goal, "warrior should reach the goal")
	var visible := Fog.compute_visible(state, 0)
	var start_i := IsoGrid.index_of(start, state.map.width)
	_check(state.explored[0][start_i] == 1, "the start tile stays explored")
	_check(visible[start_i] == 0, "the start tile is no longer visible")
	_check(visible[IsoGrid.index_of(goal, state.map.width)] == 1, "the unit's tile is visible")
	_check(_count(state.explored[0]) > _count(visible), "explored area should exceed visible area")


# --- Setup, calendar, saving --------------------------------------------------

func _test_game_setup() -> void:
	for s in 15:
		var state := GameSetup.new_game(s, 40, 80)
		var units := state.units_of(0)
		_check(units.size() == 2, "seed %d: should start with 2 units" % s)
		if units.size() != 2:
			continue
		var types := [units[0].type, units[1].type]
		_check(types.has("settler") and types.has("warrior"), "seed %d: settler + warrior" % s)
		var start := units[0].position
		_check(units[1].position == start, "seed %d: units share the start tile" % s)
		_check(GameSetup.is_valid_start(state.map, start), "seed %d: start %s should be valid" % [s, start])
		_check(state.is_explored(0, start), "seed %d: start tile should be explored" % s)
	var a := GameSetup.new_game(5, 40, 80)
	var b := GameSetup.new_game(5, 40, 80)
	_check(a.units[0].position == b.units[0].position, "same seed gives same start")


func _test_calendar() -> void:
	_check(Calendar.format_year(Calendar.year_for_turn(1)) == "4000 BC", "turn 1 is 4000 BC")
	_check(Calendar.format_year(Calendar.year_for_turn(2)) == "3950 BC", "turn 2 is 3950 BC")
	_check(Calendar.format_year(Calendar.year_for_turn(81)) == "AD 1", "year 0 shows as AD 1")


func _test_game_state_round_trip() -> void:
	var state := GameSetup.new_game(42, 40, 80)
	var warrior := state.units[1]
	var target := warrior.position + Vector2i(0, 6)
	GameActions.move_unit(state, warrior.id, target)
	var json := JSON.stringify(state.to_dict())
	var loaded := GameState.from_dict(JSON.parse_string(json))
	_check(loaded.turn == state.turn, "turn survives save")
	_check(loaded.map.terrain == state.map.terrain, "map survives save")
	_check(loaded.units.size() == state.units.size(), "units survive save")
	for i in state.units.size():
		var a := state.units[i]
		var b := loaded.units[i]
		_check(a.id == b.id and a.type == b.type and a.position == b.position
			and a.moves_left == b.moves_left and a.goal == b.goal and a.path == b.path,
			"unit %d survives save" % a.id)
	_check(loaded.explored[0] == state.explored[0], "fog survives save")
	_check(loaded.rng.randi() == state.rng.randi(), "rng state survives save")
