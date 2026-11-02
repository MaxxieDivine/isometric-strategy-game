extends SceneTree
## Headless tests for combat: round math and exact odds, determinism with a
## fixed seed, every defense modifier, odds vs simulated win rate, attacking
## through move orders, fortify, healing, and unit upkeep with disbanding.
## Run: godot --headless --path . --script res://tests/test_combat.gd

var _failures := 0


func _initialize() -> void:
	_test_round_math()
	_test_determinism()
	_test_defense_modifiers()
	_test_best_defender()
	_test_odds_match_simulation()
	_test_resolve_outcome()
	_test_attack_by_move_order()
	_test_fortify()
	_test_healing()
	_test_home_city_and_upkeep()
	_test_disband_when_upkeep_exceeds_production()
	if _failures == 0:
		print("All combat tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

const CENTER := Vector2i(10, 20)


func _make_state(fill: String = "grassland", rng_seed: int = 1234) -> GameState:
	var state := GameState.new()
	state.map = MapState.new(30, 60, fill)
	state.add_player("Test", "#ffffff")
	state.ensure_barbarian_player()
	state.rng.seed = rng_seed
	return state


func _found_at(state: GameState, cell: Vector2i) -> CityState:
	var settler := state.add_unit("settler", 0, cell)
	GameActions.found_city(state, settler.id)
	return state.city_at(cell)


func _find(events: Array[Dictionary], type: String) -> Dictionary:
	for event in events:
		if event["type"] == type:
			return event
	return {}


func _near(a: float, b: float, tolerance: float = 0.0001) -> bool:
	return absf(a - b) <= tolerance


# --- Math ---------------------------------------------------------------------

func _test_round_math() -> void:
	_check(_near(Combat.round_odds(1, 1), 0.5), "equal strength: 50% per round")
	_check(_near(Combat.round_odds(3, 1), 0.75), "3 vs 1: 75% per round")
	_check(Combat.round_odds(0, 1) == 0.0, "no attack, no chance")
	_check(_near(Combat.odds(1, 1, 10, 10), 0.5), "even fight is 50%")
	_check(_near(Combat.odds(2, 1, 10, 10) + Combat.odds(1, 2, 10, 10), 1.0), "odds are complementary")
	_check(Combat.odds(1, 1, 10, 0) == 1.0 and Combat.odds(1, 1, 0, 10) == 0.0, "0 HP edge cases")
	_check(Combat.odds(3, 1, 10, 10) > 0.99, "3 vs 1 at full HP is near certain")
	_check(Combat.odds(1, 1, 10, 3) > Combat.odds(1, 1, 10, 10), "a wounded defender is easier")
	_check(Combat.max_hp() == 10, "units have 10 HP")


func _test_determinism() -> void:
	var results: Array = []
	for run in 2:
		var state := _make_state("grassland", 777)
		var outcome: Array = []
		for fight in 20:
			var attacker := state.add_unit("warrior", 0, CENTER)
			var defender := state.add_unit("warrior", 1, CENTER + Vector2i(1, 0))
			var event := Combat.resolve(state, attacker, defender)
			outcome.append([event["winner"], event["attacker_hp"], event["defender_hp"]])
			for unit in state.units.duplicate():
				state.remove_unit(unit.id)
		results.append(outcome)
	_check(results[0] == results[1], "the same seed gives the same 20 fights")
	var winners := {}
	for entry: Array in results[0]:
		winners[entry[0]] = true
	_check(winners.size() == 2, "even fights go both ways over 20 tries")


# --- Modifiers ------------------------------------------------------------------

func _test_defense_modifiers() -> void:
	var state := _make_state()
	var hills := CENTER + Vector2i(3, 0)
	var forest := CENTER + Vector2i(6, 0)
	state.map.set_terrain(hills, "hills")
	state.map.set_terrain(forest, "forest")
	var grass_unit := state.add_unit("warrior", 0, CENTER)
	var hill_unit := state.add_unit("warrior", 0, hills)
	var forest_unit := state.add_unit("warrior", 0, forest)
	_check(_near(Combat.defense_strength(state, grass_unit, "warrior"), 1.0), "grassland: no bonus")
	_check(_near(Combat.defense_strength(state, hill_unit, "warrior"), 1.5), "hills +50%")
	_check(_near(Combat.defense_strength(state, forest_unit, "warrior"), 1.25), "forest +25%")
	grass_unit.fortified = true
	_check(_near(Combat.defense_strength(state, grass_unit, "warrior"), 1.5), "fortified +50%")
	hill_unit.fortified = true
	_check(_near(Combat.defense_strength(state, hill_unit, "warrior"), 2.25), "hills and fortified multiply")

	var city := _found_at(state, CENTER + Vector2i(0, 12))
	var guard := state.add_unit("warrior", 0, city.position)
	_check(_near(Combat.defense_strength(state, guard, "warrior"), 1.0), "a city alone gives no bonus")
	city.buildings.append("city_walls")
	_check(_near(Combat.defense_strength(state, guard, "warrior"), 2.0), "City Walls +100% vs land")
	guard.fortified = true
	_check(_near(Combat.defense_strength(state, guard, "warrior"), 3.0), "walls and fortified multiply")
	var raider := state.add_unit("warrior", 1, city.position + Vector2i(1, 0))
	_check(_near(Combat.win_odds(state, raider, guard), Combat.odds(1, 3, 10, 10)), "win odds use the modified defense")


func _test_best_defender() -> void:
	var state := _make_state()
	var settler := state.add_unit("settler", 0, CENTER)
	var archer := state.add_unit("archer", 0, CENTER)
	var raider := state.add_unit("warrior", 1, CENTER + Vector2i(1, 0))
	_check(Combat.best_defender(state, CENTER, raider) == archer, "the archer (defense 2) defends the stack")
	archer.hp = 2
	_check(Combat.best_defender(state, CENTER, raider) == settler, "a badly hurt archer lets the settler defend")
	_check(Combat.best_defender(state, CENTER + Vector2i(5, 0), raider) == null, "no enemy, no defender")


func _test_odds_match_simulation() -> void:
	var cases := [
		{ "attacker": "warrior", "defender": "warrior", "terrain": "grassland", "fortified": false, "a_hp": 10, "d_hp": 10 },
		{ "attacker": "archer", "defender": "warrior", "terrain": "hills", "fortified": true, "a_hp": 10, "d_hp": 10 },
		{ "attacker": "horseman", "defender": "archer", "terrain": "forest", "fortified": false, "a_hp": 10, "d_hp": 10 },
		{ "attacker": "warrior", "defender": "warrior", "terrain": "grassland", "fortified": true, "a_hp": 10, "d_hp": 6 },
	]
	var fights := 4000
	for c: Dictionary in cases:
		var state := _make_state(c["terrain"], 4242)
		var wins := 0
		var shown := -1.0
		for i in fights:
			var attacker := state.add_unit(c["attacker"], 1, CENTER + Vector2i(1, 0))
			var defender := state.add_unit(c["defender"], 0, CENTER)
			attacker.hp = c["a_hp"]
			defender.hp = c["d_hp"]
			defender.fortified = c["fortified"]
			shown = Combat.win_odds(state, attacker, defender)
			if Combat.resolve(state, attacker, defender)["winner"] == "attacker":
				wins += 1
			for unit in state.units.duplicate():
				state.remove_unit(unit.id)
		var rate := float(wins) / fights
		_check(absf(rate - shown) <= 0.03, "%s vs %s on %s: shown %.1f%%, simulated %.1f%%" % [
			c["attacker"], c["defender"], c["terrain"], shown * 100.0, rate * 100.0])


func _test_resolve_outcome() -> void:
	var state := _make_state()
	var attacker := state.add_unit("archer", 1, CENTER + Vector2i(1, 0))
	var defender := state.add_unit("warrior", 0, CENTER)
	attacker.fortified = true
	var event := Combat.resolve(state, attacker, defender)
	var winner := attacker if event["winner"] == "attacker" else defender
	var loser := defender if winner == attacker else attacker
	_check(state.get_unit(loser.id) == null, "the loser is destroyed")
	_check(state.get_unit(winner.id) != null and winner.hp > 0, "the winner survives with HP left")
	_check(winner.hp == (event["attacker_hp"] if winner == attacker else event["defender_hp"]), "event reports final HP")
	if winner == attacker:
		_check(attacker.position == CENTER + Vector2i(1, 0), "the attacker stays on its own tile")
		_check(attacker.moves_left == 0 and not attacker.fortified and attacker.moved, "attacking spends moves and unfortifies")


func _test_attack_by_move_order() -> void:
	var state := _make_state()
	var warrior := state.add_unit("warrior", 0, CENTER)
	var enemy := state.add_unit("warrior", 1, CENTER + Vector2i(1, 0))
	var events := GameActions.move_unit(state, warrior.id, enemy.position)
	_check(not _find(events, "combat").is_empty(), "ordering a move onto an adjacent enemy attacks it")
	_check(_find(events, "unit_moved").is_empty(), "the attacker doesn't move into the tile")

	var settler := state.add_unit("settler", 0, CENTER + Vector2i(0, 10))
	var other := state.add_unit("warrior", 1, CENTER + Vector2i(1, 10))
	events = GameActions.move_unit(state, settler.id, other.position)
	_check(_find(events, "combat").is_empty(), "settlers can't attack")
	_check(not _find(events, "orders_cancelled").is_empty(), "the order is dropped instead")
	_check(state.get_unit(other.id) != null, "the enemy is untouched")

	# An enemy in the way (not the goal) stops a move rather than starting a fight.
	var scout := state.add_unit("warrior", 0, CENTER + Vector2i(0, 20))
	state.add_unit("warrior", 1, CENTER + Vector2i(1, 20))
	state.map.set_terrain(CENTER + Vector2i(1, 19), "ocean")
	state.map.set_terrain(CENTER + Vector2i(1, 21), "ocean")
	state.map.set_terrain(CENTER + Vector2i(0, 19), "ocean")
	state.map.set_terrain(CENTER + Vector2i(0, 21), "ocean")
	state.map.set_terrain(CENTER + Vector2i(0, 18), "ocean")
	state.map.set_terrain(CENTER + Vector2i(0, 22), "ocean")
	events = GameActions.move_unit(state, scout.id, CENTER + Vector2i(2, 20))
	_check(_find(events, "combat").is_empty(), "passing through an enemy doesn't attack")
	_check(scout.position == CENTER + Vector2i(0, 20) and not scout.has_goal(), "the unit stops and drops its orders")


# --- Fortify and healing ----------------------------------------------------------

func _test_fortify() -> void:
	var state := _make_state()
	var warrior := state.add_unit("warrior", 0, CENTER)
	_check(warrior.needs_orders(), "setup: a fresh unit needs orders")
	var events := GameActions.fortify_unit(state, warrior.id)
	_check(events[0]["type"] == "unit_fortified" and warrior.fortified, "fortify sets the flag")
	_check(warrior.moves_left == 0 and not warrior.needs_orders(), "a fortified unit is done for the turn")
	GameActions.end_turn(state)
	_check(warrior.fortified and not warrior.needs_orders(), "it stays fortified and asks for nothing next turn")
	GameActions.move_unit(state, warrior.id, CENTER + Vector2i(1, 0))
	_check(not warrior.fortified, "moving ends the fortification")


func _test_healing() -> void:
	var state := _make_state()
	var resting := state.add_unit("warrior", 0, CENTER)
	var walking := state.add_unit("warrior", 0, CENTER + Vector2i(0, 6))
	var city := _found_at(state, CENTER + Vector2i(0, 14))
	var garrison := state.add_unit("warrior", 0, city.position)
	for unit in [resting, walking, garrison]:
		unit.hp = 4
	GameActions.move_unit(state, walking.id, walking.position + Vector2i(1, 0))
	GameActions.end_turn(state)
	_check(resting.hp == 5, "+1 HP in the field when it stayed put (got %d)" % resting.hp)
	_check(walking.hp == 4, "no field healing after moving (got %d)" % walking.hp)
	_check(garrison.hp == 7, "+3 HP inside a city (got %d)" % garrison.hp)
	GameActions.end_turn(state)
	_check(walking.hp == 5, "heals once it rests a turn")
	garrison.hp = 9
	GameActions.end_turn(state)
	_check(garrison.hp == 10, "healing stops at max HP")


# --- Upkeep -------------------------------------------------------------------

func _test_home_city_and_upkeep() -> void:
	var state := _make_state()
	var starter := state.add_unit("warrior", 0, CENTER)
	_check(starter.home_city == UnitState.NONE, "starting units have no home city")
	var city := _found_at(state, CENTER + Vector2i(0, 10))
	city.queue.append("warrior")
	city.production_box = 10
	var built := Production.process(state, city, 0)
	var unit := state.get_unit(int(_find(built, "city_built")["unit_id"]))
	_check(unit.home_city == city.id, "a built unit's home is the city that built it")
	_check(CityRules.upkeep(state, city) == 0, "one supported unit is free")
	state.add_unit("warrior", 0, city.position).home_city = city.id
	_check(CityRules.upkeep(state, city) == 0, "two supported units are free")
	state.add_unit("warrior", 0, city.position).home_city = city.id
	_check(CityRules.upkeep(state, city) == 1, "the third costs 1 production")
	var gross := Yields.city_total(state, city)[Yields.PRODUCTION]
	_check(CityRules.net_production(state, city) == gross - 1, "upkeep comes out of production")
	city.production_box = 0
	CityRules.process_turn(state, city)
	_check(city.production_box == gross - 1, "the build queue gets production after upkeep (got %d)" % city.production_box)


func _test_disband_when_upkeep_exceeds_production() -> void:
	var state := _make_state()
	var city := _found_at(state, CENTER)
	# Grassland city: 1 production from the center bonus.
	_check(Yields.city_total(state, city)[Yields.PRODUCTION] == 1, "setup: 1 production")
	var supported: Array[UnitState] = []
	for i in 5:
		var unit := state.add_unit("warrior", 0, city.position)
		unit.home_city = city.id
		supported.append(unit)
	_check(CityRules.upkeep(state, city) == 3, "setup: 5 units, 3 over the free 2")
	var events := CityRules.process_turn(state, city)
	var disbanded: Array[int] = []
	for event in events:
		if event["type"] == "unit_disbanded":
			disbanded.append(int(event["unit_id"]))
	_check(Array(disbanded) == [supported[4].id, supported[3].id],
		"the two newest units disband (got %s)" % [disbanded])
	_check(CityRules.upkeep(state, city) == 1, "upkeep now fits production")
	_check(state.get_unit(supported[0].id) != null, "older units stay")
