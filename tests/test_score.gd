extends SceneTree
## Headless tests for score and game end: the score formula, score history,
## camps counter, the turn limit, Wonder Victory, Keep Playing, the chronicle,
## and saving it all.
## Run: godot --headless --path . --script res://tests/test_score.gd

var _failures := 0

const CENTER := Vector2i(8, 16)
const FAR := Vector2i(8, 32)


func _initialize() -> void:
	_test_score_formula()
	_test_camps_counter()
	_test_score_history()
	_test_history_for_several_civs()
	_test_turn_limit()
	_test_countdown()
	_test_wonder_victory()
	_test_no_victory_when_split()
	_test_wonder_victory_by_building()
	_test_keep_playing()
	_test_chronicle()
	_test_round_trip()
	_test_round_trip_after_game_over()
	_test_loads_version_5_save()
	if _failures == 0:
		print("All score tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

func _make_state(players: int = 1) -> GameState:
	var state := GameState.new()
	state.map = MapState.new(20, 48, "grassland")
	for i in players:
		state.add_player("P%d" % i, "#ffffff")
	state.ensure_barbarian_player()
	state.turn_limit = 150
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


func _same(a: GameState, b: GameState) -> bool:
	return JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict())


func _reload(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))


# --- Score ------------------------------------------------------------------

func _test_score_formula() -> void:
	_check(Score.weight("citizens") == 1 and Score.weight("techs") == 2 and Score.weight("wonders") == 10
		and Score.weight("camps_destroyed") == 3, "weights come from data/score.json")
	var state := _make_state()
	_check(Score.score(state, 0) == 0, "an empty civ scores 0")
	var a := _found_at(state, 0, CENTER)
	var b := _found_at(state, 0, FAR)
	a.size = 5
	b.size = 3
	Research.known(state, 0).append_array(["pottery", "alphabet", "masonry"])
	Wonders.complete(state, a, "colossus")
	state.players[0]["camps_destroyed"] = 2
	var parts := Score.breakdown(state, 0)
	_check(parts["citizens"]["count"] == 8 and parts["citizens"]["points"] == 8, "citizens x1")
	_check(parts["techs"]["count"] == 3 and parts["techs"]["points"] == 6, "techs x2")
	_check(parts["wonders"]["count"] == 1 and parts["wonders"]["points"] == 10, "wonders x10")
	_check(parts["camps_destroyed"]["count"] == 2 and parts["camps_destroyed"]["points"] == 6, "camps x3")
	_check(Score.score(state, 0) == 8 + 6 + 10 + 6, "total is the sum")
	_check(String(Score.title_for(0)["name"]) != "" and Score.title_for(9999)["name"] != Score.title_for(0)["name"],
		"titles rise with score")


func _test_camps_counter() -> void:
	var state := GameSetup.new_game(3, 40, 80)
	var warrior: UnitState = null
	for unit in state.units:
		if unit.type == "warrior":
			warrior = unit
	var camp := state.add_camp(warrior.position + Vector2i(0, 2))
	Barbarians.destroy_camp(state, warrior, camp)
	_check(int(state.players[0]["camps_destroyed"]) == 1, "destroying a camp counts for the player")
	_check(Score.breakdown(state, 0)["camps_destroyed"]["points"] == 3, "and scores 3")


func _test_score_history() -> void:
	var state := GameSetup.new_game(5, 40, 80)
	_check(state.score_history.size() == 1 and int(state.score_history[0]["turn"]) == 1, "turn 1 is recorded at setup")
	GameActions.found_city(state, state.units[0].id)
	for i in 10:
		GameActions.end_turn(state)
	_check(state.score_history.size() == 11, "one entry per turn")
	var history := Score.history_of(state, 0)
	_check(history.size() == 11 and int(history.back()[0]) == state.turn, "history entries carry their turn")
	_check(int(history.back()[1]) == Score.score(state, 0), "the latest entry is the current score")
	_check(not state.score_history.back()["scores"].has(str(state.barbarian_id())), "barbarians have no score")


func _test_history_for_several_civs() -> void:
	var state := _make_state(3)
	_found_at(state, 0, CENTER)
	_found_at(state, 2, FAR)
	Research.known(state, 2).append("pottery")
	for i in 3:
		GameActions.end_turn(state)
	var scores: Dictionary = state.score_history.back()["scores"]
	_check(scores.size() == 3 and scores.has("0") and scores.has("1") and scores.has("2"), "every civ is recorded")
	_check(int(scores["2"]) == Score.score(state, 2) and int(scores["1"]) == 0, "each with its own score")


# --- Game end ---------------------------------------------------------------

func _test_turn_limit() -> void:
	var state := GameSetup.new_game(7, 40, 80, 10)
	_check(state.turn_limit == 10, "the turn limit is configurable")
	_check(GameSetup.new_game(7, 40, 80).turn_limit == 150, "default limit is 150")
	GameActions.found_city(state, state.units[0].id)
	var game_over: Array[Dictionary] = []
	while state.turn <= 10:
		_check(not Victory.is_over(state), "still playing on turn %d" % state.turn)
		game_over = _events_of(GameActions.end_turn(state), "game_over")
	_check(game_over.size() == 1 and game_over[0]["reason"] == Victory.TURN_LIMIT, "ending turn 10 ends the game")
	_check(Victory.is_over(state) and int(state.game_over["turn"]) == 10, "game over records the last turn played")
	_check(int(state.game_over["winner"]) == 0, "the top scorer wins")
	_check(int(state.game_over["final"]["0"]["total"]) == Score.score(state, 0), "the final score is stored")


func _test_countdown() -> void:
	var state := GameSetup.new_game(7, 40, 80, 30)
	_check(not Victory.show_countdown(state), "no countdown early on")
	var news := {}
	while state.turn < 30:
		for event in _events_of(GameActions.end_turn(state), "turns_remaining"):
			news[int(event["turns"])] = state.turn
	_check(Victory.show_countdown(state) and Victory.turns_remaining(state) == 1, "the final turn shows 1 remaining")
	_check(news.keys() == [20, 10, 5, 1], "countdown news at 20, 10, 5 and 1 turns")
	_check(int(news[20]) == 11, "20 turns remain on turn 11 of 30")


func _test_wonder_victory() -> void:
	var state := _make_state()
	var city := _found_at(state, 0, CENTER)
	Wonders.complete(state, city, "hanging_gardens")
	Wonders.complete(state, city, "colossus")
	_check(Victory.wonder_victor(state) == -1, "two of three is not enough")
	Wonders.complete(state, city, "great_wall")
	_check(Victory.wonder_victor(state) == 0, "all three wonders: a victor")
	var events := GameActions.end_turn(state)
	var over := _events_of(events, "game_over")
	_check(over.size() == 1 and over[0]["reason"] == Victory.WONDER_VICTORY and int(over[0]["winner"]) == 0, "Wonder Victory ends the game")
	_check(state.turn < state.turn_limit, "early")


func _test_no_victory_when_split() -> void:
	var state := _make_state(2)
	var a := _found_at(state, 0, CENTER)
	var b := _found_at(state, 1, FAR)
	Wonders.complete(state, a, "hanging_gardens")
	Wonders.complete(state, a, "colossus")
	Wonders.complete(state, b, "great_wall")
	_check(Victory.wonder_victor(state) == -1, "wonders split between civs: no victor")
	_check(_events_of(GameActions.end_turn(state), "game_over").is_empty(), "the game goes on")


func _test_wonder_victory_by_building() -> void:
	var state := _make_state()
	for def in TechDefs.all():
		Research.known(state, 0).append(String(def["id"]))
	var a := _found_at(state, 0, CENTER)
	var b := _found_at(state, 0, FAR)
	Wonders.complete(state, a, "hanging_gardens")
	Wonders.complete(state, a, "colossus")
	GameActions.enqueue_build(state, b.id, "great_wall")
	b.production_box = 180
	var events := GameActions.end_turn(state)
	_check(_events_of(events, "wonder_built").size() == 1, "the third wonder completes")
	var over := _events_of(events, "game_over")
	_check(over.size() == 1 and over[0]["reason"] == Victory.WONDER_VICTORY, "and wins in the same turn")
	_check(int(state.game_over["turn"]) == int(Wonders.record(state, "great_wall")["turn"]), "on the turn it was completed")
	_check(int(state.game_over["final"]["0"]["wonders"]["count"]) == 3, "the final score counts all three")


func _test_keep_playing() -> void:
	var state := GameSetup.new_game(9, 40, 80, 5)
	GameActions.found_city(state, state.units[0].id)
	while not Victory.is_over(state):
		GameActions.end_turn(state)
	var final := Score.score(state, 0)
	var history_size := state.score_history.size()
	var events := GameActions.keep_playing(state)
	_check(_events_of(events, "game_continued").size() == 1 and Victory.is_continued(state), "Keep Playing continues")
	_check(GameActions.keep_playing(state).is_empty(), "only once")
	var turn := state.turn
	var game_overs := 0
	for i in 20:
		game_overs += _events_of(GameActions.end_turn(state), "game_over").size()
	_check(state.turn == turn + 20, "turns go on")
	_check(game_overs == 0, "no second game over")
	_check(Victory.is_over(state), "the game stays over")
	_check(Score.score(state, 0) == final, "the score is frozen")
	_check(Score.live_breakdown(state, 0)["total"] >= final, "even though the civ kept growing")
	_check(state.score_history.size() == history_size, "no history after the end")


func _test_chronicle() -> void:
	var state := _make_state()
	for def in TechDefs.all():
		Research.known(state, 0).append(String(def["id"]))
	var city := _found_at(state, 0, CENTER)
	var warrior := state.add_unit("warrior", 0, CENTER + Vector2i(0, 2))
	state.add_camp(CENTER + Vector2i(0, 4))
	GameActions.move_unit(state, warrior.id, CENTER + Vector2i(0, 4))
	GameActions.enqueue_build(state, city.id, "colossus")
	city.production_box = 150
	Research.known(state, 0).erase("pottery")
	Research.set_research(state, 0, "pottery")
	state.players[0]["science"] = 9999
	GameActions.end_turn(state)
	var types := {}
	for entry: Dictionary in Chronicle.entries(state, 0):
		types[entry["type"]] = entry
	_check(types.has("city_founded") and types["city_founded"]["name"] == city.name, "city founded is recorded")
	_check(types.has("camp_destroyed") and types["camp_destroyed"]["city"] == city.name, "camp destroyed, near the city")
	_check(types.has("wonder_built") and types["wonder_built"]["name"] == "Colossus" and types["wonder_built"]["city"] == city.name,
		"wonder built, with its city")
	_check(types.has("tech_discovered") and types["tech_discovered"]["name"] == "Pottery", "tech discovered")
	_check(int(types["wonder_built"]["turn"]) == state.turn, "entries carry the turn")


# --- Saving -----------------------------------------------------------------

func _test_round_trip() -> void:
	var state := GameSetup.new_game(11, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	for i in 30:
		GameActions.end_turn(state)
	var city := state.cities[0]
	Wonders.complete(state, city, "colossus")
	state.players[0]["camps_destroyed"] = 2
	var loaded := _reload(state)
	_check(_same(loaded, state), "wonders, history, chronicle and counters round-trip identically")
	_check(Wonders.owner_of(loaded, "colossus") == 0 and loaded.score_history.size() == state.score_history.size(),
		"loaded wonders and history")
	_check(Score.score(loaded, 0) == Score.score(state, 0), "same score after loading")
	for i in 30:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(_same(loaded, state), "the loaded game plays on identically")


func _test_round_trip_after_game_over() -> void:
	var state := GameSetup.new_game(13, 40, 80, 8)
	GameActions.found_city(state, state.units[0].id)
	while not Victory.is_over(state):
		GameActions.end_turn(state)
	var loaded := _reload(state)
	_check(_same(loaded, state), "game over round-trips identically")
	_check(Victory.is_over(loaded) and not Victory.is_continued(loaded) and loaded.turn_limit == 8, "still over, same limit")
	GameActions.keep_playing(state)
	GameActions.keep_playing(loaded)
	for i in 5:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(_same(loaded, state), "and keeps playing identically")
	_check(Victory.is_continued(_reload(state)), "Keep Playing survives a save")


func _test_loads_version_5_save() -> void:
	var state := GameSetup.new_game(15, 40, 80)
	GameActions.found_city(state, state.units[0].id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	data["version"] = 5
	for key in ["wonders", "score_history", "chronicle", "game_over", "turn_limit"]:
		data.erase(key)
	for player: Dictionary in data["players"]:
		player.erase("camps_destroyed")
	var loaded := GameState.from_dict(data)
	_check(loaded.wonders.is_empty() and loaded.score_history.is_empty() and loaded.chronicle.is_empty(), "old saves start empty")
	_check(loaded.game_over.is_empty() and loaded.turn_limit == Victory.default_turn_limit(), "still playing, default limit")
	_check(int(loaded.players[0]["camps_destroyed"]) == 0, "no camps destroyed yet")
	for i in 5:
		GameActions.end_turn(loaded)
	_check(loaded.score_history.size() == 5 and loaded.to_dict()["version"] == GameState.VERSION, "the migrated game plays on and saves as v6")
