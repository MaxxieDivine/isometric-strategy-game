extends SceneTree
## Headless tests for wonders: world uniqueness, tech gating, the three
## effects (Hanging Gardens, Colossus, Great Wall), and kept production when
## a wonder is completed elsewhere.
## Run: godot --headless --path . --script res://tests/test_wonders.gd

var _failures := 0

const CENTER := Vector2i(8, 16)
const FAR := Vector2i(8, 32)


func _initialize() -> void:
	_test_wonder_data()
	_test_tech_gating()
	_test_completion_is_recorded()
	_test_uniqueness()
	_test_one_city_per_civ()
	_test_race_same_turn()
	_test_kept_production_when_taken()
	_test_taken_from_later_queue_slot()
	_test_hanging_gardens()
	_test_colossus()
	_test_great_wall()
	if _failures == 0:
		print("All wonder tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

## Two civ players (0 and 1) on grassland, both knowing every tech.
func _make_state(fill: String = "grassland") -> GameState:
	var state := GameState.new()
	state.map = MapState.new(20, 48, fill)
	state.add_player("One", "#ff0000")
	state.add_player("Two", "#0000ff")
	for player in 2:
		for def in TechDefs.all():
			Research.known(state, player).append(String(def["id"]))
	return state


func _found_at(state: GameState, owner: int, cell: Vector2i) -> CityState:
	var settler := state.add_unit("settler", owner, cell)
	GameActions.found_city(state, settler.id)
	return state.city_at(cell)


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			result.append(event)
	return result


## Fills the box so the head of the queue completes on the next end_turn.
func _ready_to_finish(city: CityState) -> void:
	city.production_box = Production.cost(city.queue[0])


# --- Data and gating ----------------------------------------------------------

func _test_wonder_data() -> void:
	_check(Array(WonderDefs.ids()) == ["hanging_gardens", "colossus", "great_wall"], "three wonders in data order")
	_check(Production.cost("hanging_gardens") == 150 and Production.cost("colossus") == 150
		and Production.cost("great_wall") == 180, "wonder costs come from data")
	_check(Production.is_wonder("colossus") and not Production.is_wonder("library"), "wonders are their own kind")
	_check(TechDefs.required_for("hanging_gardens") == "pottery", "Hanging Gardens needs Pottery")
	_check(TechDefs.required_for("colossus") == "bronze_working", "Colossus needs Bronze Working")
	_check(TechDefs.required_for("great_wall") == "masonry", "Great Wall needs Masonry")
	_check(Production.news_name("colossus") == "the Colossus", "news name uses 'the'")


func _test_tech_gating() -> void:
	var state := GameState.new()
	state.map = MapState.new(20, 40, "grassland")
	state.add_player("Test", "#ffffff")
	var city := _found_at(state, 0, CENTER)
	_check(Production.can_enqueue(state, city, "colossus").contains("Bronze Working"), "Colossus locked without Bronze Working")
	_check(not Production.available_items(state, city).has("colossus"), "locked wonders aren't offered")
	Research.known(state, 0).append("bronze_working")
	_check(Production.can_enqueue(state, city, "colossus") == "", "Colossus unlocked by Bronze Working")
	_check(Production.available_items(state, city).has("colossus"), "and offered")
	_check(Production.can_enqueue(state, city, "great_wall") != "", "Great Wall still locked")


# --- Uniqueness ---------------------------------------------------------------

func _test_completion_is_recorded() -> void:
	var state := _make_state()
	var city := _found_at(state, 0, CENTER)
	GameActions.enqueue_build(state, city.id, "colossus")
	_ready_to_finish(city)
	var events := GameActions.end_turn(state)
	var built := _events_of(events, "wonder_built")
	_check(built.size() == 1 and built[0]["wonder"] == "colossus" and int(built[0]["player"]) == 0, "wonder_built event")
	_check(Wonders.is_built(state, "colossus"), "the wonder is recorded")
	var record := Wonders.record(state, "colossus")
	_check(int(record["city_id"]) == city.id and int(record["builder"]) == 0 and int(record["turn"]) == state.turn,
		"who built it, where, and on which turn")
	_check(Wonders.owner_of(state, "colossus") == 0 and Array(Wonders.in_city(state, city)) == ["colossus"],
		"owner and city lookups")
	_check(not city.buildings.has("colossus"), "wonders don't go in the building list")
	_check(_events_of(events, "city_built").is_empty(), "no plain city_built for a wonder")


func _test_uniqueness() -> void:
	var state := _make_state()
	var city := _found_at(state, 0, CENTER)
	var rival := _found_at(state, 1, FAR)
	GameActions.enqueue_build(state, city.id, "colossus")
	_ready_to_finish(city)
	GameActions.end_turn(state)
	_check(Production.can_enqueue(state, city, "colossus").contains("completed"), "the builder can't queue it again")
	_check(Production.can_enqueue(state, rival, "colossus").contains("completed in %s" % city.name), "nor can another civ")
	var events := GameActions.enqueue_build(state, rival.id, "colossus")
	_check(_events_of(events, "build_failed").size() == 1 and rival.queue.is_empty(), "the enqueue action refuses")
	_check(not Production.available_items(state, rival).has("colossus"), "built wonders aren't offered")


func _test_one_city_per_civ() -> void:
	var state := _make_state()
	var first := _found_at(state, 0, CENTER)
	var second := _found_at(state, 0, FAR)
	var rival := _found_at(state, 1, Vector2i(8, 4))
	GameActions.enqueue_build(state, first.id, "great_wall")
	_check(Production.can_enqueue(state, second, "great_wall").contains("being built in %s" % first.name),
		"a civ builds a wonder in one city at a time")
	_check(Production.can_enqueue(state, rival, "great_wall") == "", "a rival civ may race for it")
	_check(Production.can_enqueue(state, first, "great_wall").contains("already queued"), "no double queueing")


func _test_race_same_turn() -> void:
	var state := _make_state()
	var first := _found_at(state, 0, CENTER)
	var second := _found_at(state, 1, FAR)
	GameActions.enqueue_build(state, first.id, "hanging_gardens")
	GameActions.enqueue_build(state, second.id, "hanging_gardens")
	_ready_to_finish(first)
	_ready_to_finish(second)
	var stored := second.production_box
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "wonder_built").size() == 1, "only one civ completes a wonder raced on the same turn")
	_check(Wonders.owner_of(state, "hanging_gardens") == 0, "the first city processed wins")
	var lost := _events_of(events, "wonder_lost")
	_check(lost.size() == 1 and int(lost[0]["city_id"]) == second.id and int(lost[0]["by_player"]) == 0, "the loser hears it")
	_check(second.production_box >= stored, "the loser keeps its stored production (plus this turn's)")


# --- Kept production ----------------------------------------------------------

func _test_kept_production_when_taken() -> void:
	var state := _make_state()
	var winner := _found_at(state, 0, CENTER)
	var loser := _found_at(state, 1, FAR)
	GameActions.enqueue_build(state, winner.id, "colossus")
	GameActions.enqueue_build(state, loser.id, "colossus")
	_ready_to_finish(winner)
	loser.production_box = 90
	var production := CityRules.net_production(state, loser)
	var events := GameActions.end_turn(state)
	var lost := _events_of(events, "wonder_lost")
	_check(lost.size() == 1, "wonder_lost event for the city that was building it")
	_check(not loser.queue.has("colossus"), "the wonder leaves the loser's queue")
	_check(loser.production_box == 90 + production, "stored production is kept (90 + this turn's)")
	_check(int(lost[0]["kept"]) == 90, "the event says how much stored production was kept")
	_check(int(lost[0]["by_city_id"]) == winner.id, "and where it was completed")
	_check(_events_of(events, "city_idle").any(func(e: Dictionary) -> bool: return int(e["city_id"]) == loser.id),
		"a queue left empty reports the city idle")
	# The kept production pays for the next build.
	GameActions.enqueue_build(state, loser.id, "warrior")
	var built := _events_of(GameActions.end_turn(state), "city_built")
	_check(built.size() >= 1 and built.back()["item"] == "warrior", "kept production finishes the next item")


func _test_taken_from_later_queue_slot() -> void:
	var state := _make_state()
	var winner := _found_at(state, 0, CENTER)
	var loser := _found_at(state, 1, FAR)
	GameActions.enqueue_build(state, winner.id, "great_wall")
	GameActions.enqueue_build(state, loser.id, "library")
	GameActions.enqueue_build(state, loser.id, "great_wall")
	GameActions.enqueue_build(state, loser.id, "warrior")
	_ready_to_finish(winner)
	loser.production_box = 5
	GameActions.end_turn(state)
	_check(Array(loser.queue) == ["library", "warrior"], "a wonder further back in the queue is removed too")
	# A save that still queues a taken wonder: it's dropped when the city works its queue.
	loser.queue.insert(0, "great_wall")
	var events := GameActions.end_turn(state)
	_check(not loser.queue.has("great_wall") and _events_of(events, "wonder_lost").size() == 1,
		"a stale queued wonder is dropped at turn processing")


# --- Effects ------------------------------------------------------------------

func _test_hanging_gardens() -> void:
	var state := _make_state()
	var a := _found_at(state, 0, CENTER)
	var b := _found_at(state, 0, FAR)
	var rival := _found_at(state, 1, Vector2i(8, 4))
	var food_a := Yields.city_total(state, a)[Yields.FOOD]
	var food_b := Yields.city_total(state, b)[Yields.FOOD]
	var food_rival := Yields.city_total(state, rival)[Yields.FOOD]
	Wonders.complete(state, a, "hanging_gardens")
	_check(Yields.city_total(state, a)[Yields.FOOD] == food_a + 1, "+1 food in the wonder city")
	_check(Yields.city_total(state, b)[Yields.FOOD] == food_b + 1, "+1 food in every other city of the owner")
	_check(Yields.city_total(state, rival)[Yields.FOOD] == food_rival, "nothing for another civ")
	_check(CityRules.food_surplus(state, b) == food_b + 1 - CityRules.food_per_citizen() * b.size, "it feeds growth")
	var later := _found_at(state, 0, Vector2i(16, 24))
	_check(Yields.city_total(state, later)[Yields.FOOD]
		== Yields.city_center(state.map, later.position)[Yields.FOOD] + Yields.worked_tile(state, later, later.worked[0])[Yields.FOOD] + 1,
		"cities founded later get it too")


func _test_colossus() -> void:
	var state := _make_state()
	# Ocean all around the west side of the city, grassland elsewhere.
	for cell in IsoGrid.cells_within(CENTER, 2, state.map.width, state.map.height):
		if cell.x < CENTER.x:
			state.map.set_terrain(cell, "ocean")
	var city := _found_at(state, 0, CENTER)
	var other := _found_at(state, 0, FAR)
	var ocean := CENTER + Vector2i(-1, 0)
	var land := CENTER + Vector2i(1, 0)
	var ocean_trade := Yields.worked_tile(state, city, ocean)[Yields.TRADE]
	_check(Yields.worked_tile(state, city, land)[Yields.TRADE] == 0, "setup: grassland has no trade")
	Wonders.complete(state, city, "colossus")
	_check(Yields.worked_tile(state, city, ocean)[Yields.TRADE] == ocean_trade + 1, "+1 trade on an ocean tile")
	_check(Yields.worked_tile(state, city, land)[Yields.TRADE] == 0, "land tiles are unchanged")
	_check(Yields.tile(state.map, ocean)[Yields.TRADE] == ocean_trade, "the bare tile is unchanged")
	state.map.set_terrain(FAR + Vector2i(-1, 0), "ocean")
	_check(Yields.worked_tile(state, other, FAR + Vector2i(-1, 0))[Yields.TRADE] == ocean_trade,
		"another city of the same civ gets nothing")
	# City total counts only worked ocean tiles.
	city.size = 3
	city.locked.clear()
	city.worked = [ocean, land] as Array[Vector2i]
	var center := Yields.city_center(state.map, city.position)
	_check(Yields.city_total(state, city)[Yields.TRADE] == center[Yields.TRADE] + ocean_trade + 1, "city trade counts the bonus")
	# Auto-assign scores tiles by their worked yield: with only ocean and
	# hills (1/0/0) to choose from, the boosted ocean wins.
	for cell in CityRules.work_area(state, city):
		if cell.x >= CENTER.x:
			state.map.set_terrain(cell, "hills")
	city.size = 1
	CityRules.auto_assign(state, city)
	_check(state.map.get_terrain(city.worked[0]) == "ocean", "auto-assign picks the boosted ocean")
	_check(Yields.worked_tile(state, city, city.worked[0]) == Vector3i(1, 0, ocean_trade + 1), "worth 1/0/%d" % (ocean_trade + 1))


func _test_great_wall() -> void:
	var state := _make_state()
	var barbarian := state.ensure_barbarian_player()
	var city := _found_at(state, 0, CENTER)
	var guard := state.add_unit("warrior", 0, city.position)
	var raider := state.add_unit("warrior", barbarian, city.position + Vector2i(1, 0))
	var rival := state.add_unit("warrior", 1, city.position + Vector2i(-1, 0))
	_check(is_equal_approx(Combat.defense_strength(state, guard, "warrior", barbarian), 1.0), "setup: no walls, no bonus")
	Wonders.complete(state, city, "great_wall")
	var other := _found_at(state, 0, FAR)
	var far_guard := state.add_unit("warrior", 0, other.position)
	var walls := float(BuildingDefs.get_def("city_walls")["effects"]["defense_percent"]) / 100.0
	_check(is_equal_approx(Combat.defense_strength(state, guard, "warrior", barbarian), 1.0 + walls),
		"the Great Wall counts as City Walls against barbarians")
	_check(is_equal_approx(Combat.defense_strength(state, far_guard, "warrior", barbarian), 1.0 + walls),
		"in every city of the owner")
	_check(is_equal_approx(Combat.win_odds(state, raider, guard), Combat.odds(1, 1.0 + walls, 10, 10)),
		"barbarian attack odds use it")
	_check(is_equal_approx(Combat.defense_strength(state, guard, "warrior", 1), 1.0), "no effect against another civ")
	_check(is_equal_approx(Combat.win_odds(state, rival, guard), Combat.odds(1, 1.0, 10, 10)), "rival odds unchanged")
	city.buildings.append("city_walls")
	_check(is_equal_approx(Combat.defense_strength(state, guard, "warrior", barbarian), 1.0 + walls),
		"real walls and the Great Wall don't stack")
	_check(is_equal_approx(Combat.defense_strength(state, guard, "warrior", 1), 1.0 + walls), "real walls still work vs civs")
