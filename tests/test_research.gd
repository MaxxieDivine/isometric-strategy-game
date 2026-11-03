extends SceneTree
## Headless tests for research: science accumulation and the Library bonus,
## the cost formula, prerequisites, unlock gating in the build list,
## carry-over, auto-pick, and saving research.
## Run: godot --headless --path . --script res://tests/test_research.gd

var _failures := 0


func _initialize() -> void:
	_test_tech_data()
	_test_cost_formula()
	_test_science_accumulates()
	_test_library_boosts_research()
	_test_prerequisites()
	_test_unlock_gating()
	_test_discovery_and_carry_over()
	_test_banked_science_counts_for_first_tech()
	_test_one_discovery_per_turn()
	_test_switching_keeps_science()
	_test_auto_pick()
	_test_turn_estimates()
	_test_everything_known()
	_test_round_trip()
	_test_loads_version_3_save()
	if _failures == 0:
		print("All research tests passed.")
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


func _learn(state: GameState, techs: Array) -> void:
	for tech: String in techs:
		Research.known(state, 0).append(tech)


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			result.append(event)
	return result


# --- Data -------------------------------------------------------------------

func _test_tech_data() -> void:
	_check(TechDefs.all().size() == 10, "10 techs (got %d)" % TechDefs.all().size())
	_check(Array(TechDefs.prerequisites("mathematics")) == ["alphabet", "masonry"], "mathematics needs alphabet + masonry")
	_check(Array(TechDefs.prerequisites("writing")) == ["alphabet"], "writing needs alphabet")
	_check(Array(TechDefs.prerequisites("warrior_code")) == ["bronze_working"], "warrior code needs bronze working")
	_check(TechDefs.prerequisites("pottery").is_empty(), "pottery needs nothing")
	_check(TechDefs.required_for("granary") == "pottery", "granary needs pottery")
	_check(TechDefs.required_for("library") == "writing", "library needs writing")
	_check(TechDefs.required_for("city_walls") == "masonry", "walls need masonry")
	_check(TechDefs.required_for("horseman") == "horseback_riding", "horseman needs horseback riding")
	_check(TechDefs.required_for("archer") == "warrior_code", "archer needs warrior code")
	_check(TechDefs.required_for("warrior") == "", "warriors need no tech")
	_check(TechDefs.required_for("settler") == "", "settlers need no tech")
	_check(Array(TechDefs.leads_to("alphabet")) == ["writing", "mathematics"], "alphabet leads to writing and mathematics")
	for def in TechDefs.all():
		for prereq in TechDefs.prerequisites(String(def["id"])):
			_check(TechDefs.has(prereq), "%s's prerequisite %s exists" % [def["id"], prereq])
		for item in TechDefs.unlocks(String(def["id"])):
			_check(Production.kind(item) != "", "%s unlocks a real item (%s)" % [def["id"], item])
	var horseman := UnitDefs.get_def("horseman")
	_check(int(horseman["cost"]) == 20 and int(horseman["moves"]) == 2
		and int(horseman["attack"]) == 2 and int(horseman["defense"]) == 1, "horseman stats")
	var archer := UnitDefs.get_def("archer")
	_check(int(archer["cost"]) == 30 and int(archer["moves"]) == 1
		and int(archer["attack"]) == 3 and int(archer["defense"]) == 2, "archer stats")


func _test_cost_formula() -> void:
	_check(TechDefs.cost("pottery", 0) == 10, "first tech costs 10")
	_check(TechDefs.cost("writing", 1) == 18, "second tech costs 18")
	_check(TechDefs.cost("mathematics", 5) == 50, "10 + 8 x 5 = 50")
	var state := _make_state()
	_check(Research.cost(state, 0, "alphabet") == 10, "a new player pays 10")
	_learn(state, ["pottery", "alphabet"])
	_check(Research.cost(state, 0, "writing") == 26, "after two techs: 10 + 16 = 26")


# --- Science ------------------------------------------------------------------

func _test_science_accumulates() -> void:
	var state := _make_state()
	var a := _found_at(state, CENTER)
	var b := _found_at(state, CENTER + Vector2i(6, 0))
	# Each grassland city: 1 trade from the center bonus.
	_check(CityRules.science(state, a) == 1 and CityRules.science(state, b) == 1, "setup: 1 science per city")
	_check(Research.science_per_turn(state, 0) == 2, "player science is the sum over cities")
	GameActions.set_research(state, 0, "pottery")
	for turn in 3:
		GameActions.end_turn(state)
	_check(Research.stored(state, 0) == 6, "2/turn for 3 turns banks 6 (got %d)" % Research.stored(state, 0))


func _test_library_boosts_research() -> void:
	var state := _make_state("ocean")
	state.map.set_terrain(CENTER, "grassland")
	var city := _found_at(state, CENTER)
	city.size = 3
	city.food_box = 10
	CityRules.auto_assign(state, city)
	_check(Research.science_per_turn(state, 0) == 7, "setup: 7 trade -> 7 science")
	city.buildings.append("library")
	_check(Research.science_per_turn(state, 0) == 10, "library: 7 + 50% = 10")
	GameActions.set_research(state, 0, "pottery")
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "tech_discovered").size() == 1, "10 science buys the 10-cost first tech in one turn")


# --- Prerequisites --------------------------------------------------------------

func _test_prerequisites() -> void:
	var state := _make_state()
	var start := Research.available(state, 0)
	_check(Array(start) == ["pottery", "alphabet", "bronze_working", "horseback_riding", "masonry", "ceremonial_burial"],
		"only no-prerequisite techs are available at first (got %s)" % [start])
	var failed := GameActions.set_research(state, 0, "writing")
	_check(failed[0]["type"] == "research_failed", "can't research writing without alphabet")
	_check(String(failed[0]["reason"]) == "Writing needs Alphabet first", "reason names the missing tech (%s)" % failed[0]["reason"])
	_check(Research.current(state, 0) == "", "research stays unset after a refusal")
	_learn(state, ["alphabet"])
	_check(Research.is_available(state, 0, "writing"), "alphabet opens writing")
	_check(not Research.is_available(state, 0, "mathematics"), "mathematics also needs masonry")
	_check(String(GameActions.set_research(state, 0, "mathematics")[0]["reason"]) == "Mathematics needs Masonry first",
		"only the missing prerequisite is named")
	_learn(state, ["masonry"])
	_check(Research.is_available(state, 0, "mathematics"), "alphabet + masonry open mathematics")
	_check(not Research.is_available(state, 0, "alphabet"), "known techs aren't available again")
	_check(GameActions.set_research(state, 0, "alphabet")[0]["type"] == "research_failed", "can't research a known tech")
	_check(GameActions.set_research(state, 0, "nonsense")[0]["type"] == "research_failed", "unknown techs rejected")


# --- Unlocks ------------------------------------------------------------------

func _test_unlock_gating() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	var items := Production.available_items(state, city)
	_check(Array(items) == ["settler", "warrior", "scout"],
		"a new civ can only build settlers, warriors and scouts (got %s)" % [items])
	var refused := GameActions.enqueue_build(state, city.id, "library")
	_check(refused[0]["type"] == "build_failed" and String(refused[0]["reason"]) == "Library needs Writing",
		"queueing a locked building is refused with a reason")
	_check(city.queue.is_empty(), "nothing was queued")
	_learn(state, ["pottery", "horseback_riding"])
	items = Production.available_items(state, city)
	_check(items.has("granary") and items.has("horseman"), "pottery and horseback riding unlock granary and horseman")
	_check(not items.has("library") and not items.has("city_walls") and not items.has("archer"), "the rest stay locked")
	_learn(state, ["alphabet", "writing", "masonry", "bronze_working", "warrior_code"])
	items = Production.available_items(state, city)
	for id in ["library", "city_walls", "archer"]:
		_check(items.has(id), "%s unlocked by its tech" % id)
	_check(GameActions.enqueue_build(state, city.id, "library")[0]["type"] == "city_queue_changed", "library queues once unlocked")


# --- Discovery ------------------------------------------------------------------

func _test_discovery_and_carry_over() -> void:
	var state := _make_state()
	_found_at(state, CENTER)  # 1 science/turn.
	GameActions.set_research(state, 0, "alphabet")
	state.players[0]["science"] = 14
	var events := GameActions.end_turn(state)
	var found := _events_of(events, "tech_discovered")
	_check(found.size() == 1 and found[0]["tech"] == "alphabet", "15 stored >= 10 discovers alphabet")
	_check(Research.knows(state, 0, "alphabet"), "alphabet is known")
	_check(Research.stored(state, 0) == 5, "15 - 10 leaves 5 carried over (got %d)" % Research.stored(state, 0))
	_check(Research.current(state, 0) == "", "research is cleared for the next choice")
	_check(Research.cost(state, 0, "writing") == 18, "the next tech costs 18")
	GameActions.set_research(state, 0, "writing")
	_check(Research.turns_to(state, 0, "writing") == 13, "13 more at 1/turn (got %d)" % Research.turns_to(state, 0, "writing"))


func _test_banked_science_counts_for_first_tech() -> void:
	var state := _make_state()
	_found_at(state, CENTER)
	# Science banked before any research existed (e.g. an older save).
	state.players[0]["science"] = 9
	_check(Research.turns_to(state, 0, "pottery") == 1, "9 banked + 1 this turn finishes the first tech")
	GameActions.set_research(state, 0, "pottery")
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "tech_discovered").size() == 1, "banked science pays for the first tech")
	_check(Research.stored(state, 0) == 0, "nothing left over")


func _test_one_discovery_per_turn() -> void:
	var state := _make_state()
	_found_at(state, CENTER)
	GameActions.set_research(state, 0, "pottery")
	state.players[0]["science"] = 100
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "tech_discovered").size() == 1, "only one discovery per turn")
	_check(Research.stored(state, 0) == 91, "the rest stays banked (got %d)" % Research.stored(state, 0))
	# Not choosing: the next turn auto-picks and the bank pays at once.
	events = GameActions.end_turn(state)
	_check(_events_of(events, "research_set").size() == 1 and _events_of(events, "tech_discovered").size() == 1,
		"next turn auto-picks and discovers from the bank")
	_check(Research.known(state, 0).size() == 2, "two techs after two turns")


func _test_switching_keeps_science() -> void:
	var state := _make_state()
	GameActions.set_research(state, 0, "pottery")
	state.players[0]["science"] = 7
	var events := GameActions.set_research(state, 0, "masonry")
	_check(events[0]["type"] == "research_set" and not bool(events[0]["auto"]), "a chosen tech is not auto")
	_check(Research.current(state, 0) == "masonry" and Research.stored(state, 0) == 7, "switching keeps stored science")


func _test_auto_pick() -> void:
	var state := _make_state()
	_found_at(state, CENTER)
	var events := GameActions.end_turn(state)
	var picked := _events_of(events, "research_set")
	_check(picked.size() == 1 and bool(picked[0]["auto"]), "an undecided player gets research auto-picked")
	_check(Research.current(state, 0) == "pottery", "equal costs: the first tier-1 tech in data order (got %s)" % Research.current(state, 0))
	_check(Research.stored(state, 0) == 1, "the turn's science goes into the picked tech")
	_check(GameActions.auto_pick_research(state, 0).is_empty(), "auto-pick leaves a chosen tech alone")
	_check(_events_of(GameActions.end_turn(state), "research_set").is_empty(), "no auto-pick while researching")

	var later := _make_state()
	_learn(later, ["pottery", "alphabet", "bronze_working", "horseback_riding", "masonry", "ceremonial_burial"])
	_check(GameActions.auto_pick_research(later, 0)[0]["tech"] == "writing", "after tier 1, the first tier-2 tech")

	# With equal costs, a lower tier wins.
	var cheap := _make_state()
	_learn(cheap, ["alphabet"])
	_check(Research.cheapest_available(cheap, 0) == "pottery", "tier 1 beats tier 2 on a tie")


func _test_turn_estimates() -> void:
	var state := _make_state()
	_check(Research.turns_to(state, 0, "pottery") == -1, "no cities, no science: no estimate")
	_found_at(state, CENTER)
	_check(Research.turns_to(state, 0, "pottery") == 10, "10 at 1/turn = 10 turns")
	state.players[0]["science"] = 4
	_check(Research.turns_to(state, 0, "pottery") == 6, "stored science shortens the wait")


func _test_everything_known() -> void:
	var state := _make_state()
	_found_at(state, CENTER)
	for def in TechDefs.all():
		Research.known(state, 0).append(String(def["id"]))
	_check(Research.available(state, 0).is_empty(), "nothing left to research")
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "research_set").is_empty(), "no auto-pick with nothing left")
	_check(Research.stored(state, 0) == 1, "science still banks")


# --- Saving -------------------------------------------------------------------

func _test_round_trip() -> void:
	var state := GameSetup.new_game(11, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	if state.cities.is_empty():
		_check(false, "setup: city founded at start")
		return
	_learn(state, ["alphabet"])
	GameActions.set_research(state, 0, "writing")
	for turn in 4:
		GameActions.end_turn(state)
	var data := state.to_dict()
	_check(int(data["version"]) == GameState.VERSION, "save has the current version")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(Research.known(loaded, 0) == Research.known(state, 0), "known techs survive save")
	_check(Research.current(loaded, 0) == "writing", "current research survives save")
	_check(Research.stored(loaded, 0) == Research.stored(state, 0), "stored science survives save")
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(data), "full state round-trips identically")
	for turn in 30:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(Research.known(state, 0).size() > 1, "setup: discoveries happen during play")
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(state.to_dict()), "loaded game researches identically")


func _test_loads_version_3_save() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	city.queue.append("warrior")
	state.players[0]["science"] = 12
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	data["version"] = 3
	for player: Dictionary in data["players"]:
		player.erase("known_techs")
		player.erase("research")
	var loaded := GameState.from_dict(data)
	_check(Research.known(loaded, 0).is_empty(), "a version 3 save loads with no techs")
	_check(Research.current(loaded, 0) == "", "and no research chosen")
	_check(Research.stored(loaded, 0) == 12, "its banked science is kept")
	var events := GameActions.end_turn(loaded)
	_check(_events_of(events, "tech_discovered").size() == 1, "the old bank pays for the first tech")
	_check(int(loaded.to_dict()["version"]) == GameState.VERSION, "it saves back as the current version")
