extends SceneTree
## Headless tests for founding, yields, citizen auto-assignment, growth,
## starvation, manual tile placement, and saving with cities.
## Run: godot --headless --path . --script res://tests/test_cities.gd

var _failures := 0


func _initialize() -> void:
	_test_found_city()
	_test_only_settlers_found()
	_test_cannot_found_on_ocean()
	_test_city_spacing()
	_test_city_reveals_radius()
	_test_city_names()
	_test_terrain_yields()
	_test_center_bonus()
	_test_city_total()
	_test_auto_assign_food_first()
	_test_pick_tiles_balances_after_food_target()
	_test_tiles_are_exclusive()
	_test_growth()
	_test_starvation()
	_test_production_and_science()
	_test_toggle_worked_tile()
	_test_locked_tiles_survive_growth()
	_test_round_trip_with_cities()
	if _failures == 0:
		print("All city tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

const CENTER := Vector2i(8, 16)


func _make_state(fill: String = "grassland") -> GameState:
	var state := GameState.new()
	state.map = MapState.new(20, 40, fill)
	state.add_player("Test", "#ffffff")
	return state


func _found_at(state: GameState, cell: Vector2i) -> CityState:
	var settler := state.add_unit("settler", 0, cell)
	GameActions.found_city(state, settler.id)
	return state.city_at(cell)


func _has_event(events: Array[Dictionary], type: String) -> bool:
	for event in events:
		if event["type"] == type:
			return true
	return false


# --- Founding -----------------------------------------------------------------

func _test_found_city() -> void:
	var state := _make_state()
	var settler := state.add_unit("settler", 0, CENTER)
	var events := GameActions.found_city(state, settler.id)
	var city := state.city_at(CENTER)
	_check(city != null, "settler should found a city")
	_check(_has_event(events, "city_founded"), "founding should emit city_founded")
	_check(state.get_unit(settler.id) == null, "settler should be consumed")
	if city == null:
		return
	_check(city.size == 1, "new city has size 1")
	_check(city.worked.size() == 1, "its one citizen should work a tile")


func _test_only_settlers_found() -> void:
	var state := _make_state()
	var warrior := state.add_unit("warrior", 0, CENTER)
	var events := GameActions.found_city(state, warrior.id)
	_check(state.cities.is_empty(), "warriors can't found cities")
	_check(_has_event(events, "found_failed"), "should emit found_failed")
	_check(state.get_unit(warrior.id) != null, "warrior should not be consumed")


func _test_cannot_found_on_ocean() -> void:
	var state := _make_state()
	state.map.set_terrain(CENTER, "ocean")
	var settler := state.add_unit("settler", 0, CENTER)
	GameActions.found_city(state, settler.id)
	_check(state.cities.is_empty(), "can't found a city on ocean")


func _test_city_spacing() -> void:
	var state := _make_state()
	_found_at(state, CENTER)
	var three_away := CENTER + Vector2i(3, 0)
	var four_away := CENTER + Vector2i(4, 0)
	_check(IsoGrid.step_distance(CENTER, three_away) == 3, "test setup: 3 steps")
	_check(IsoGrid.step_distance(CENTER, four_away) == 4, "test setup: 4 steps")
	var too_close := state.add_unit("settler", 0, three_away)
	var reason := CityRules.can_found(state, too_close)
	_check(reason.begins_with("Too close"), "3 tiles from a city is too close (got '%s')" % reason)
	var far_enough := state.add_unit("settler", 0, four_away)
	_check(CityRules.can_found(state, far_enough) == "", "4 tiles away is allowed")


func _test_city_reveals_radius() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	for cell in IsoGrid.cells_within(city.position, 2, state.map.width, state.map.height):
		_check(state.is_explored(0, cell), "city should reveal %s (within 2)" % cell)
	var visible := Fog.compute_visible(state, 0)
	_check(visible.count(1) == 25, "city alone should see 25 tiles, saw %d" % visible.count(1))


func _test_city_names() -> void:
	var state := _make_state()
	var first := _found_at(state, CENTER)
	var second := _found_at(state, CENTER + Vector2i(5, 0))
	_check(first.name == "Rome", "first city takes the first name (got %s)" % first.name)
	_check(second.name == "Athens", "second city takes the second name (got %s)" % second.name)


# --- Yields -------------------------------------------------------------------

func _test_terrain_yields() -> void:
	var map := MapState.new(4, 8)
	var expected := {
		"grassland": Vector3i(2, 0, 0), "plains": Vector3i(1, 1, 0), "forest": Vector3i(1, 2, 0),
		"hills": Vector3i(1, 0, 0), "ocean": Vector3i(1, 0, 2),
	}
	for id: String in expected:
		map.set_terrain(Vector2i(1, 1), id)
		_check(Yields.tile(map, Vector2i(1, 1)) == expected[id], "%s yield should be %s" % [id, expected[id]])


func _test_center_bonus() -> void:
	var map := MapState.new(4, 8, "grassland")
	_check(Yields.city_center(map, Vector2i(1, 1)) == Vector3i(2, 1, 1), "grassland center = 2/1/1")
	map.set_terrain(Vector2i(1, 1), "hills")
	_check(Yields.city_center(map, Vector2i(1, 1)) == Vector3i(1, 1, 1), "hills center = 1/1/1")


func _test_city_total() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	_check(Yields.city_total(state, city) == Vector3i(4, 1, 1), "size-1 grassland city = 4/1/1")
	_check(CityRules.food_surplus(state, city) == 2, "size-1 grassland city has +2 food")


# --- Citizens -----------------------------------------------------------------

func _test_auto_assign_food_first() -> void:
	var state := _make_state("hills")
	state.map.set_terrain(CENTER, "grassland")
	var grass_a := CENTER + Vector2i(1, 0)
	var grass_b := CENTER + Vector2i(0, 2)
	var forest := CENTER + Vector2i(-1, 0)
	state.map.set_terrain(grass_a, "grassland")
	state.map.set_terrain(grass_b, "grassland")
	state.map.set_terrain(forest, "forest")
	var city := _found_at(state, CENTER)
	city.size = 2
	CityRules.auto_assign(state, city)
	_check(city.worked.has(grass_a) and city.worked.has(grass_b),
		"below +2 surplus, citizens should take the grassland (worked %s)" % [city.worked])


func _test_pick_tiles_balances_after_food_target() -> void:
	var grass := Vector3i(2, 0, 0)
	var forest := Vector3i(1, 2, 0)
	var plains := Vector3i(1, 1, 0)
	var candidates: Array[Vector3i] = [grass, forest, plains]
	# Surplus already +2: balance food and production -> forest (1+2) beats grassland (2).
	var balanced := CityRules.pick_tiles(6, 4, candidates, 1)
	_check(balanced.size() == 1 and balanced[0] == 1, "with surplus met, forest should be picked")
	# Surplus 0: food first -> grassland.
	var hungry := CityRules.pick_tiles(4, 4, candidates, 1)
	_check(hungry[0] == 0, "below the food target, grassland should be picked")
	# Asking for more tiles than exist returns them all.
	_check(CityRules.pick_tiles(0, 0, candidates, 10).size() == 3, "can't pick more tiles than exist")


func _test_tiles_are_exclusive() -> void:
	var state := _make_state()
	var a := _found_at(state, CENTER)
	var b := _found_at(state, CENTER + Vector2i(4, 0))
	a.size = 8
	b.size = 8
	CityRules.auto_assign(state, a)
	CityRules.auto_assign(state, b)
	for cell in a.worked:
		_check(not b.worked.has(cell), "tile %s worked by both cities" % cell)
		_check(cell != b.position, "city A works city B's center")
	for cell in b.worked:
		_check(cell != a.position, "city B works city A's center")


# --- Growth -------------------------------------------------------------------

func _test_growth() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	_check(CityRules.food_box_size(1) == 20, "size-1 food box holds 20")
	_check(CityRules.turns_to_grow(state, city) == 10, "+2 food into a 20 box takes 10 turns")
	var grew_on := -1
	for turn in 10:
		var events := GameActions.end_turn(state)
		if _has_event(events, "city_grew") and grew_on == -1:
			grew_on = turn + 1
	_check(grew_on == 10, "city should grow on the 10th turn (grew on %d)" % grew_on)
	_check(city.size == 2, "city should be size 2")
	_check(city.food_box == 0, "food box empties on growth")
	_check(city.worked.size() == 2, "the new citizen should get a tile")
	_check(CityRules.food_box_size(2) == 30, "size-2 food box holds 30")


func _test_starvation() -> void:
	var state := _make_state("hills")
	var city := _found_at(state, CENTER)
	city.size = 3
	city.food_box = 3
	CityRules.auto_assign(state, city)
	# Hills: center 1 food + 3 tiles × 1 = 4, citizens eat 6 → -2 per turn.
	_check(CityRules.food_surplus(state, city) == -2, "test setup: -2 food")
	CityRules.process_turn(state, city)
	_check(city.size == 3 and city.food_box == 1, "box drains first (size %d, box %d)" % [city.size, city.food_box])
	var events := CityRules.process_turn(state, city)
	_check(city.size == 2 and city.food_box == 0, "empty box + deficit shrinks the city")
	_check(_has_event(events, "city_shrank"), "should emit city_shrank")
	_check(city.worked.size() == 2, "citizens should be re-assigned after shrinking")
	CityRules.process_turn(state, city)
	_check(city.size == 1, "keeps shrinking while starving (size %d)" % city.size)
	CityRules.process_turn(state, city)
	_check(city.size == 1, "size 1 on hills breaks even")
	# Force a deficit at size 1: the citizen has no tile.
	city.worked.clear()
	events = CityRules.process_turn(state, city)
	_check(city.size == 1, "a city never shrinks below size 1")
	_check(_has_event(events, "city_starving"), "should warn that the city is starving")


func _test_production_and_science() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	for turn in 3:
		GameActions.end_turn(state)
	_check(city.production_box == 3, "1 production/turn for 3 turns (got %d)" % city.production_box)
	_check(int(state.players[0]["science"]) == 3, "1 trade/turn adds to science (got %d)" % state.players[0]["science"])


# --- Manual placement -----------------------------------------------------------

func _test_toggle_worked_tile() -> void:
	var state := _make_state()
	var forest := CENTER + Vector2i(-1, 0)
	state.map.set_terrain(forest, "forest")
	var city := _found_at(state, CENTER)
	_check(not city.worked.has(forest), "test setup: auto picks grassland, not forest")
	GameActions.toggle_worked_tile(state, city.id, forest)
	_check(city.worked.size() == 1 and city.worked[0] == forest,
		"clicking a tile should move the citizen there")
	_check(city.locked.has(forest), "a hand-placed tile is locked")
	GameActions.toggle_worked_tile(state, city.id, forest)
	_check(not city.worked.has(forest) and city.worked.size() == 1, "clicking a worked tile frees it to auto")
	_check(city.locked.is_empty(), "freed tile is no longer locked")
	var events := GameActions.toggle_worked_tile(state, city.id, CENTER)
	_check(events.is_empty(), "the center can't be toggled")
	events = GameActions.toggle_worked_tile(state, city.id, CENTER + Vector2i(5, 0))
	_check(events.is_empty(), "tiles outside the radius can't be worked")


func _test_locked_tiles_survive_growth() -> void:
	var state := _make_state()
	var hills := CENTER + Vector2i(1, 0)
	state.map.set_terrain(hills, "hills")
	var city := _found_at(state, CENTER)
	GameActions.toggle_worked_tile(state, city.id, hills)
	city.size = 2
	CityRules.auto_assign(state, city)
	_check(city.worked.has(hills), "auto-assignment keeps hand-placed tiles")
	_check(city.worked.size() == 2, "the new citizen is placed automatically")


# --- Saving -------------------------------------------------------------------

func _test_round_trip_with_cities() -> void:
	var state := GameSetup.new_game(7, 40, 80)
	var settler := state.units[0]
	GameActions.found_city(state, settler.id)
	_check(state.cities.size() == 1, "setup: city founded at start")
	if state.cities.is_empty():
		return
	var city := state.cities[0]
	var area := CityRules.work_area(state, city)
	GameActions.toggle_worked_tile(state, city.id, area[0])
	for turn in 4:
		GameActions.end_turn(state)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	_check(loaded.cities.size() == 1 and loaded.next_city_id == state.next_city_id, "cities survive save")
	var a := city
	var b := loaded.cities[0]
	_check(a.id == b.id and a.name == b.name and a.owner == b.owner and a.position == b.position,
		"city identity survives save")
	_check(a.size == b.size and a.food_box == b.food_box and a.production_box == b.production_box,
		"city stores survive save")
	_check(a.worked == b.worked and a.locked == b.locked, "worked and locked tiles survive save")
	_check(int(loaded.players[0]["science"]) == int(state.players[0]["science"]), "science survives save")
	_check(Yields.city_total(loaded, b) == Yields.city_total(state, a), "yields match after load")
