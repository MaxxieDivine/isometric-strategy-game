extends SceneTree
## Headless tests for build queues: accumulation and overflow, unit and
## building completion, settler population cost, granary, library, duplicate
## prevention, idle cities, and saving queues and buildings.
## Run: godot --headless --path . --script res://tests/test_production.gd

var _failures := 0


func _initialize() -> void:
	_test_item_data()
	_test_accumulation_and_overflow()
	_test_one_item_per_turn()
	_test_unit_appears_on_city_tile()
	_test_turns_to_complete()
	_test_settler_waits_for_size_two()
	_test_settler_costs_population()
	_test_granary_keeps_half()
	_test_library_science_bonus()
	_test_no_duplicate_buildings()
	_test_idle_cities()
	_test_queue_actions()
	_test_round_trip_with_queues()
	_test_loads_save_without_queues()
	if _failures == 0:
		print("All production tests passed.")
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


func _find_event(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


# --- Data -------------------------------------------------------------------

func _test_item_data() -> void:
	_check(Production.cost("warrior") == 10, "warrior costs 10")
	_check(Production.cost("settler") == 30, "settler costs 30")
	_check(Production.cost("granary") == 40, "granary costs 40")
	_check(Production.cost("library") == 60, "library costs 60")
	_check(Production.cost("city_walls") == 60, "city walls cost 60")
	_check(Production.kind("warrior") == Production.UNIT, "warrior is a unit")
	_check(Production.kind("granary") == Production.BUILDING, "granary is a building")
	_check(Production.kind("nonsense") == "", "unknown ids have no kind")
	_check(Production.news_name("granary") == "a Granary", "news name with article")
	_check(Production.news_name("city_walls") == "City Walls", "city walls take no article")
	var city := CityState.new()
	city.buildings.append("city_walls")
	_check(BuildingDefs.effect(city, "defense_percent") == 100, "walls store a defense modifier")


# --- Accumulation -------------------------------------------------------------

func _test_accumulation_and_overflow() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	city.queue.append("warrior")
	city.production_box = 8
	var events := Production.process(state, city, 4)
	_check(not _find_event(events, "city_built").is_empty(), "8 + 4 >= 10 completes the warrior")
	_check(city.production_box == 2, "2 production carries over (got %d)" % city.production_box)
	_check(city.queue.is_empty(), "completed item leaves the queue")

	city.queue.append("warrior")
	city.production_box = 0
	Production.process(state, city, 4)
	Production.process(state, city, 4)
	_check(city.production_box == 8 and city.queue.size() == 1, "production accumulates until the cost is met")

	var empty := _found_at(state, CENTER + Vector2i(5, 0))
	Production.process(state, empty, 3)
	_check(empty.production_box == 3, "an empty queue still banks production")


func _test_one_item_per_turn() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	city.queue.assign(["warrior", "warrior"])
	city.production_box = 25
	var units_before := state.units.size()
	Production.process(state, city, 0)
	_check(state.units.size() == units_before + 1, "only one item completes per turn")
	_check(city.production_box == 15 and city.queue.size() == 1, "the rest carries to the next item")
	Production.process(state, city, 0)
	_check(state.units.size() == units_before + 2, "the next item completes on the following turn")


func _test_unit_appears_on_city_tile() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	city.queue.append("warrior")
	city.production_box = 10
	var events := GameActions.end_turn(state)
	var built := _find_event(events, "city_built")
	_check(not built.is_empty() and built["item"] == "warrior", "end_turn completes the warrior")
	if built.is_empty():
		return
	var unit := state.get_unit(built["unit_id"])
	_check(unit != null and unit.type == "warrior", "a warrior unit is created")
	_check(unit != null and unit.position == CENTER, "the new unit stands on the city tile")
	_check(unit != null and unit.owner == city.owner, "the new unit belongs to the city's owner")


func _test_turns_to_complete() -> void:
	var city := CityState.new()
	_check(Production.turns_to_complete(city, 3) == -1, "nothing queued: no estimate")
	city.queue.append("warrior")
	city.production_box = 4
	_check(Production.turns_to_complete(city, 3) == 2, "6 more at 3/turn = 2 turns")
	_check(Production.turns_to_complete(city, 0) == -1, "no production: no estimate")
	city.production_box = 12
	_check(Production.turns_to_complete(city, 0) == 1, "already paid for: next turn")


# --- Settlers -----------------------------------------------------------------

func _test_settler_waits_for_size_two() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	_check(Production.can_enqueue(city, "settler") == "", "a settler can be queued at size 1")
	city.queue.append("settler")
	city.production_box = 40
	var events := Production.process(state, city, 0)
	_check(_find_event(events, "city_built").is_empty(), "a size-1 city can't finish a settler")
	_check(city.size == 1 and city.production_box == 40, "it waits with production intact")
	_check(Production.blocked_reason(city, "settler") == "Settler waits for size 2", "the reason is shown")


func _test_settler_costs_population() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	city.size = 2
	CityRules.auto_assign(state, city)
	city.food_box = 28  # Fits the size-2 box (30) but not the size-1 box (20).
	city.queue.append("settler")
	city.production_box = 30
	var units_before := state.units.size()
	var events := Production.process(state, city, 0)
	_check(not _find_event(events, "city_built").is_empty(), "size 2 finishes the settler")
	_check(state.units.size() == units_before + 1, "a settler unit appears")
	_check(city.size == 1, "building a settler costs one population (size %d)" % city.size)
	_check(city.food_box == 20, "food box is clamped to the smaller box (got %d)" % city.food_box)
	_check(city.worked.size() == 1, "citizens are re-assigned after the size drop")


# --- Buildings ----------------------------------------------------------------

func _test_granary_keeps_half() -> void:
	var state := _make_state()
	var plain := _found_at(state, CENTER)
	plain.food_box = 19
	CityRules.process_turn(state, plain)
	_check(plain.size == 2 and plain.food_box == 0, "without a granary the box empties")

	var stocked := _found_at(state, CENTER + Vector2i(5, 0))
	stocked.buildings.append("granary")
	stocked.food_box = 19
	CityRules.process_turn(state, stocked)
	_check(stocked.size == 2, "test setup: city grows")
	_check(stocked.food_box == 10, "granary keeps 50%% of the 20 box (got %d)" % stocked.food_box)


func _test_library_science_bonus() -> void:
	var state := _make_state("ocean")
	state.map.set_terrain(CENTER, "grassland")
	var city := _found_at(state, CENTER)
	city.size = 3
	city.food_box = 10  # Ocean leaves a -1 food deficit; keep the city from shrinking.
	CityRules.auto_assign(state, city)
	# Center 1 trade + 3 ocean tiles x 2 = 7 trade.
	var trade := Yields.city_total(state, city)[Yields.TRADE]
	_check(trade == 7, "test setup: 7 trade (got %d)" % trade)
	_check(CityRules.science(state, city) == 7, "no library: science = trade")
	city.buildings.append("library")
	_check(CityRules.science(state, city) == 10, "library: 7 + 50%% = 10 (rounded down)")
	var before := int(state.players[0]["science"])
	CityRules.process_turn(state, city)
	_check(int(state.players[0]["science"]) - before == 10, "turn processing banks boosted science")


func _test_no_duplicate_buildings() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	_check(GameActions.enqueue_build(state, city.id, "granary")[0]["type"] == "city_queue_changed", "queue a granary")
	var again := GameActions.enqueue_build(state, city.id, "granary")
	_check(again[0]["type"] == "build_failed", "can't queue the same building twice")
	_check(city.queue.size() == 1, "queue still holds one granary")
	_check(not Production.available_items(city).has("granary"), "queued building not offered again")
	city.production_box = 40
	Production.process(state, city, 0)
	_check(Array(city.buildings) == ["granary"], "granary is built")
	_check(Production.can_enqueue(city, "granary") != "", "a built building can't be queued")
	_check(not Production.available_items(city).has("granary"), "built building not offered")
	_check(Production.available_items(city).has("warrior"), "units can always be queued again")
	GameActions.enqueue_build(state, city.id, "warrior")
	GameActions.enqueue_build(state, city.id, "warrior")
	_check(city.queue.size() == 2, "units may repeat in the queue")
	_check(GameActions.enqueue_build(state, city.id, "nonsense")[0]["type"] == "build_failed", "unknown ids rejected")


# --- Idle -----------------------------------------------------------------------

func _test_idle_cities() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	_check(city.is_idle(), "a new city starts with an empty queue")
	_check(state.idle_cities(0).size() == 1, "and is listed as idle")
	city.queue.append("warrior")
	_check(state.idle_cities(0).is_empty(), "a queued item clears the idle flag")
	city.production_box = 10
	var events := Production.process(state, city, 0)
	_check(not _find_event(events, "city_idle").is_empty(), "finishing the last item emits city_idle")
	_check(state.idle_cities(0).size() == 1, "the city is idle again")


func _test_queue_actions() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	GameActions.enqueue_build(state, city.id, "warrior")
	GameActions.enqueue_build(state, city.id, "library")
	GameActions.enqueue_build(state, city.id, "settler")
	_check(Array(city.queue) == ["warrior", "library", "settler"], "items queue in order")
	city.production_box = 5
	GameActions.remove_from_queue(state, city.id, 0)
	_check(Array(city.queue) == ["library", "settler"], "removing the head")
	_check(city.production_box == 5, "stored production stays when the head changes")
	_check(GameActions.remove_from_queue(state, city.id, 9).is_empty(), "bad index does nothing")


# --- Saving -------------------------------------------------------------------

func _test_round_trip_with_queues() -> void:
	var state := GameSetup.new_game(7, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	if state.cities.is_empty():
		_check(false, "setup: city founded at start")
		return
	var city := state.cities[0]
	city.buildings.append("granary")
	GameActions.enqueue_build(state, city.id, "warrior")
	GameActions.enqueue_build(state, city.id, "library")
	for turn in 3:
		GameActions.end_turn(state)
	var data := state.to_dict()
	_check(int(data["version"]) == 3, "save version is 3")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	var b := loaded.cities[0]
	_check(b.queue == city.queue, "queue survives save (%s vs %s)" % [b.queue, city.queue])
	_check(b.buildings == city.buildings, "buildings survive save")
	_check(b.production_box == city.production_box, "production box survives save")
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(data), "full state round-trips identically")
	# Both copies keep playing the same way.
	for turn in 5:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(state.to_dict()), "loaded game plays on identically")


func _test_loads_save_without_queues() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	var data := city.to_dict()
	data.erase("queue")
	data.erase("buildings")
	var loaded := CityState.from_dict(data)
	_check(loaded.queue.is_empty() and loaded.buildings.is_empty(), "older saves load with empty queues")
