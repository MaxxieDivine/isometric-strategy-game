extends SceneTree
## Headless tests for barbarians: the turn-15 grace period, camp site rules
## (land, distance, visibility), unit types by era and the unit cap, AI
## targeting and wandering, city sacking, camp rewards, sightings, and
## saving camps and barbarian units.
## Run: godot --headless --path . --script res://tests/test_barbarians.gd

var _failures := 0


func _initialize() -> void:
	_test_data()
	_test_grace_period()
	_test_camp_site_rules()
	_test_camps_spawn_legally()
	_test_camps_prefer_nearby_sites()
	_test_unit_types_and_cap()
	_test_targeting()
	_test_wandering()
	_test_attack_when_adjacent()
	_test_sack_empty_city()
	_test_sack_after_last_defender()
	_test_camp_destroyed_for_reward()
	_test_sightings()
	_test_barbarians_dont_research()
	_test_round_trip()
	_test_loads_version_4_save()
	if _failures == 0:
		print("All barbarian tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

const CITY := Vector2i(5, 30)


func _make_state(rng_seed: int = 99) -> GameState:
	var state := GameState.new()
	state.map = MapState.new(30, 60, "grassland")
	state.add_player("Test", "#ffffff")
	state.ensure_barbarian_player()
	state.rng.seed = rng_seed
	return state


func _barb() -> int:
	return 1


func _found_at(state: GameState, cell: Vector2i) -> CityState:
	var settler := state.add_unit("settler", 0, cell)
	GameActions.found_city(state, settler.id)
	return state.city_at(cell)


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event["type"] == type:
			result.append(event)
	return result


# --- Data -------------------------------------------------------------------

func _test_data() -> void:
	var state := _make_state()
	_check(state.barbarian_id() == 1 and state.is_barbarian(1) and not state.is_barbarian(0), "barbarians are player 1")
	_check(Array(state.civ_player_ids()) == [0], "only player 0 is a civ")
	_check(state.ensure_barbarian_player() == 1 and state.players.size() == 2, "ensure doesn't add a second barbarian player")
	_check(Barbarians.start_turn() == 15, "no barbarians before turn 15")
	_check(Barbarians.camp_min_city_distance() == 8, "camps keep 8 tiles from cities")
	_check(Barbarians.aggro_range() == 6, "barbarians react within 6 tiles")
	_check(Barbarians.max_units(80) > Barbarians.max_units(20), "the unit cap grows over time")
	_check(Barbarians.max_camps(80) > Barbarians.max_camps(20), "the camp cap grows over time")


# --- Spawning -------------------------------------------------------------------

func _test_grace_period() -> void:
	var state := GameSetup.new_game(3, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	var events: Array[Dictionary] = []
	while state.turn < Barbarians.start_turn() - 1:
		events.append_array(GameActions.end_turn(state))
	_check(state.camps.is_empty() and Barbarians.barbarian_units(state).is_empty(),
		"nothing barbarian exists through turn %d" % state.turn)
	_check(_events_of(events, "camp_spawned").is_empty(), "no camp events before turn 15")
	var later: Array[Dictionary] = []
	for i in 20:
		later.append_array(GameActions.end_turn(state))
	_check(not _events_of(later, "camp_spawned").is_empty(), "a camp appears once the grace period is over")


func _test_camp_site_rules() -> void:
	var state := _make_state()
	_found_at(state, CITY)
	state.map.set_terrain(Vector2i(25, 30), "ocean")
	var seen := Barbarians.seen_by_civs(state)
	_check(Barbarians.camp_site_problem(state, Vector2i(25, 30), seen) == "water", "never on water")
	_check(Barbarians.camp_site_problem(state, CITY + Vector2i(7, 0), seen) == "near a city", "7 tiles from a city is too close")
	_check(Barbarians.camp_site_problem(state, CITY + Vector2i(8, 0), seen) == "", "8 tiles from a city is allowed")
	var scout := state.add_unit("warrior", 0, Vector2i(20, 30))
	seen = Barbarians.seen_by_civs(state)
	_check(Barbarians.camp_site_problem(state, scout.position + Vector2i(1, 0), seen) == "visible", "never where the player can see")
	scout.position = Vector2i(20, 50)
	seen = Barbarians.seen_by_civs(state)
	_check(Barbarians.camp_site_problem(state, Vector2i(21, 30), seen) == "", "fine once the scout has left")
	state.add_camp(Vector2i(22, 10))
	_check(Barbarians.camp_site_problem(state, Vector2i(24, 10), seen) == "near a camp", "camps keep apart")


func _test_camps_spawn_legally() -> void:
	for s in 12:
		var state := GameSetup.new_game(100 + s, 40, 80)
		GameActions.found_city(state, state.units[0].id)
		for i in 60:
			var before := state.camps.size()
			GameActions.end_turn(state)
			# No unit has orders here, so what's visible after the turn is what
			# was visible when the camp spawned.
			if state.camps.size() > before:
				var camp := state.camps.back() as CampState
				_check(TerrainDefs.passable_by_land(state.map.get_terrain(camp.position)), "seed %d: camp on land" % s)
				for city in state.cities:
					_check(IsoGrid.step_distance(city.position, camp.position) >= 8, "seed %d: camp 8+ tiles from cities" % s)
				_check(state.turn >= Barbarians.start_turn(), "seed %d: camp after the grace period" % s)
				_check(not _visible_after(state, camp), "seed %d: camp not on a visible tile" % s)


func _test_camps_prefer_nearby_sites() -> void:
	var state := _make_state()
	_found_at(state, CITY)
	state.turn = Barbarians.start_turn()
	Barbarians.spawn(state)
	_check(state.camps.size() == 1, "setup: a camp appears at turn 15")
	if state.camps.is_empty():
		return
	var distance := IsoGrid.step_distance(CITY, state.camps[0].position)
	_check(distance >= 8 and distance <= Barbarians.camp_preferred_max_city_distance(),
		"the camp is a real threat: 8-%d tiles from the city (got %d)" % [Barbarians.camp_preferred_max_city_distance(), distance])


## True if the camp's tile is visible to the player right now.
func _visible_after(state: GameState, camp: CampState) -> bool:
	return Fog.compute_visible(state, 0)[IsoGrid.index_of(camp.position, state.map.width)] == 1


func _test_unit_types_and_cap() -> void:
	_check(Array(Barbarians.unit_types(30)) == ["warrior"], "early camps spawn warriors")
	_check(Barbarians.unit_types(60).size() == 1 and Barbarians.unit_types(61).has("archer"), "archers after turn 60")
	_check(not Barbarians.unit_types(90).has("horseman") and Barbarians.unit_types(91).has("horseman"), "horsemen after turn 90")

	var state := _make_state()
	state.turn = 20
	for i in 3:
		state.add_camp(Vector2i(5 + i * 8, 5))
	var events := Barbarians.spawn(state)
	var spawned := _events_of(events, "barbarian_spawned")
	_check(spawned.size() == Barbarians.max_units(20), "spawns stop at the cap (%d)" % spawned.size())
	for event in spawned:
		_check(state.get_unit(event["unit_id"]).type == "warrior", "turn 20 spawns are warriors")
		_check(state.get_unit(event["unit_id"]).camp_id == int(event["camp_id"]), "units remember their camp")


# --- AI -------------------------------------------------------------------------

func _test_targeting() -> void:
	var state := _make_state()
	var target := state.add_unit("warrior", 0, Vector2i(5, 30))
	var raider := state.add_unit("warrior", _barb(), Vector2i(10, 30))
	_check(Barbarians.find_target(state, raider) == target.position, "a unit 5 tiles away is a target")
	var before := IsoGrid.step_distance(raider.position, target.position)
	Barbarians.act(state)
	_check(IsoGrid.step_distance(raider.position, target.position) == before - 1, "the raider closes in")
	var city := _found_at(state, Vector2i(11, 30))  # 2 tiles from the raider, the unit is 4.
	_check(Barbarians.find_target(state, raider) == city.position, "the nearest target wins (now the city)")
	var far := _make_state()
	far.add_unit("warrior", 0, Vector2i(5, 30))
	var idle := far.add_unit("warrior", _barb(), Vector2i(12, 30))
	_check(Barbarians.find_target(far, idle) == Vector2i(-1, -1), "7 tiles away is out of range")


func _test_wandering() -> void:
	var state := _make_state()
	var camp := state.add_camp(Vector2i(20, 20))
	var raider := state.add_unit("warrior", _barb(), camp.position)
	raider.camp_id = camp.id
	var moved := false
	for i in 30:
		var start := raider.position
		Barbarians.act(state)
		raider.moves_left = raider.max_moves()
		moved = moved or raider.position != start
		_check(IsoGrid.step_distance(raider.position, camp.position) <= Barbarians.wander_radius(), "wanders within range of its camp")
	_check(moved, "an idle raider moves about")


func _test_attack_when_adjacent() -> void:
	var state := _make_state()
	var guard := state.add_unit("warrior", 0, Vector2i(5, 30))
	var raider := state.add_unit("warrior", _barb(), Vector2i(6, 30))
	var events := Barbarians.act(state)
	var fights := _events_of(events, "combat")
	_check(fights.size() == 1 and fights[0]["attacker_id"] == raider.id and fights[0]["defender_id"] == guard.id,
		"an adjacent raider attacks")


func _test_sack_empty_city() -> void:
	var state := _make_state()
	var city := _found_at(state, CITY)
	city.size = 3
	city.production_box = 17
	CityRules.auto_assign(state, city)
	var raider := state.add_unit("warrior", _barb(), CITY + Vector2i(1, 0))
	var events := Barbarians.act(state)
	var sacked := _events_of(events, "city_sacked")
	_check(sacked.size() == 1 and sacked[0]["city_id"] == city.id, "walking into an empty city sacks it")
	_check(city.size == 2 and city.production_box == 0, "the city loses a citizen and its production")
	_check(int(sacked[0]["production_lost"]) == 17, "the event reports the lost production")
	_check(state.get_unit(raider.id) == null, "the raider leaves (is removed)")
	_check(state.city_at(CITY) == city and city.owner == 0, "sacked, not captured")
	_check(city.worked.size() == 2, "citizens are re-assigned")

	city.size = 1
	city.production_box = 5
	state.add_unit("warrior", _barb(), CITY + Vector2i(1, 0))
	Barbarians.act(state)
	_check(city.size == 1 and city.production_box == 0, "a size-1 city stays size 1")


func _test_sack_after_last_defender() -> void:
	var state := _make_state(5)
	var city := _found_at(state, CITY)
	city.size = 2
	var guard := state.add_unit("warrior", 0, CITY)
	guard.hp = 1
	var raider := state.add_unit("archer", _barb(), CITY + Vector2i(1, 0))
	var events := Barbarians.act(state)
	var fight := _events_of(events, "combat")
	_check(fight.size() == 1 and fight[0]["winner"] == "attacker", "setup: the raider beats the 1-HP guard")
	_check(_events_of(events, "city_sacked").is_empty() and city.size == 2, "winning the fight doesn't also sack this turn")
	raider.moves_left = raider.max_moves()
	events = Barbarians.act(state)
	_check(_events_of(events, "city_sacked").size() == 1 and city.size == 1, "next turn it walks in and sacks")


func _test_camp_destroyed_for_reward() -> void:
	var rewards := {}
	for s in 12:
		var state := _make_state(s)
		var city := _found_at(state, CITY)
		var camp := state.add_camp(CITY + Vector2i(3, 0))
		var hero := state.add_unit("warrior", 0, CITY + Vector2i(2, 0))
		var events := GameActions.move_unit(state, hero.id, camp.position)
		var destroyed := _events_of(events, "camp_destroyed")
		_check(destroyed.size() == 1 and state.camps.is_empty(), "walking onto an empty camp destroys it")
		if destroyed.is_empty():
			continue
		var reward: String = destroyed[0]["reward"]
		rewards[reward] = true
		if reward == "production":
			_check(city.production_box == 25 and destroyed[0]["city_id"] == city.id, "+25 production to the nearest city")
		else:
			_check(Research.stored(state, 0) == 25, "+25 science")
	_check(rewards.size() == 2, "both rewards come up over 12 seeds (%s)" % [rewards.keys()])

	var guarded := _make_state()
	var camp := guarded.add_camp(Vector2i(10, 30))
	guarded.add_unit("warrior", _barb(), camp.position)
	var hero := guarded.add_unit("warrior", 0, Vector2i(9, 30))
	var events := GameActions.move_unit(guarded, hero.id, camp.position)
	_check(_events_of(events, "combat").size() == 1 and guarded.camps.size() == 1, "a guarded camp must be fought for first")


func _test_sightings() -> void:
	var state := _make_state()
	var city := _found_at(state, CITY)
	var raider := state.add_unit("warrior", _barb(), CITY + Vector2i(6, 0))
	_check(Barbarians.update_sightings(state, 0).is_empty(), "out of sight: no warning")
	raider.position = CITY + Vector2i(2, 0)
	var events := Barbarians.update_sightings(state, 0)
	_check(events.size() == 1 and events[0]["type"] == "barbarians_spotted" and events[0]["city_id"] == city.id,
		"entering the city's sight radius warns, naming the city")
	_check(Barbarians.update_sightings(state, 0).is_empty(), "it warns once, not every check")
	raider.position = CITY + Vector2i(6, 0)
	Barbarians.update_sightings(state, 0)
	raider.position = CITY + Vector2i(2, 0)
	_check(Barbarians.update_sightings(state, 0).size() == 1, "leaving and coming back warns again")

	var scout := state.add_unit("warrior", 0, Vector2i(20, 10))
	var other := state.add_unit("warrior", _barb(), Vector2i(21, 10))
	events = Barbarians.update_sightings(state, 0)
	_check(_events_of(events, "barbarians_spotted").size() == 1 and int(events[0]["unit_id"]) == other.id,
		"a player unit spots barbarians next to it")

	var camp := state.add_camp(Vector2i(20, 50))
	scout.position = Vector2i(19, 50)
	_check(_events_of(Barbarians.update_sightings(state, 0), "camp_discovered").size() == 1, "seeing a camp discovers it")
	scout.position = Vector2i(5, 10)
	Barbarians.update_sightings(state, 0)
	_check(camp.discovered_by.has(0), "a discovered camp stays discovered out of sight")


func _test_barbarians_dont_research() -> void:
	var state := _make_state()
	_found_at(state, CITY)
	GameActions.end_turn(state)
	_check(Research.current(state, 1) == "" and Research.known(state, 1).is_empty(), "barbarians get no research")


# --- Saving -------------------------------------------------------------------

func _test_round_trip() -> void:
	var state := GameSetup.new_game(21, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	GameActions.fortify_unit(state, state.units[0].id)
	for i in 40:
		GameActions.end_turn(state)
	_check(not state.camps.is_empty(), "setup: camps exist by turn 41")
	var data := state.to_dict()
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(data), "camps, barbarians, HP and fortify round-trip identically")
	_check(loaded.camps.size() == state.camps.size() and loaded.next_camp_turn == state.next_camp_turn, "camp timers survive")
	for i in state.units.size():
		var a := state.units[i]
		var b := loaded.units[i]
		_check(a.hp == b.hp and a.fortified == b.fortified and a.home_city == b.home_city and a.camp_id == b.camp_id,
			"unit %d combat fields survive" % a.id)
	for i in 50:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(state.to_dict()), "loaded game plays on identically for 50 turns")


func _test_loads_version_4_save() -> void:
	var state := GameSetup.new_game(8, 40, 80)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	data["version"] = 4
	data["players"] = [data["players"][0]]
	data["explored"] = [data["explored"][0]]
	(data["players"][0] as Dictionary).erase("barbarian")
	for key in ["camps", "next_camp_id", "next_camp_turn"]:
		data.erase(key)
	for unit: Dictionary in data["units"]:
		for key in ["hp", "fortified", "moved", "home_city", "camp_id", "spotted"]:
			unit.erase(key)
	var loaded := GameState.from_dict(data)
	_check(loaded.barbarian_id() == 1, "an old save gains a barbarian player")
	_check(loaded.explored.size() == 2, "with its own fog array")
	_check(loaded.units[0].hp == 10 and not loaded.units[0].fortified and loaded.units[0].home_city == UnitState.NONE,
		"old units load at full HP, unfortified, homeless")
	for i in 30:
		GameActions.end_turn(loaded)
	_check(loaded.turn == 31, "the migrated game plays on")
