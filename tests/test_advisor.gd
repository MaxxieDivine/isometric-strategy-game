extends SceneTree
## Headless tests for the advisor: trigger matching and conditions, priority
## and the per-turn limit, cooldowns and once-only triggers, carry-over,
## placeholder filling, the city site scorer and selection policy, save/load,
## the advice log, the real advisor data, and determinism (a seeded game plays
## out identically with the advisor on and off).
## Run: godot --headless --path . --script res://tests/test_advisor.gd

const SEED := 4242
const CENTER := Vector2i(8, 16)

var _failures := 0


func _initialize() -> void:
	_test_text_placeholders()
	_test_conditions()
	_test_trigger_matching()
	_test_event_owner_filter()
	_test_priority_and_turn_limit()
	_test_cooldown_and_once()
	_test_carry_over()
	_test_unfillable_lines_skipped()
	_test_line_variety_uses_own_rng()
	_test_disabled_says_nothing()
	_test_scorer_ranking()
	_test_scorer_coast_overlap_edge()
	_test_scorer_respects_fog_and_rules()
	_test_selection_policy()
	_test_save_round_trip()
	_test_old_save_loads()
	AdvisorDefs.reset()
	_test_real_advisor_data()
	_test_advice_followed_log()
	_test_first_scout_line()
	_test_determinism_on_off()
	AdvisorDefs.reset()
	if _failures == 0:
		print("All advisor tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

func _make_state(fill: String = "grassland") -> GameState:
	var state := GameState.new()
	state.map = MapState.new(20, 40, fill)
	state.add_player("Tester", "#ffffff")
	state.explored[0].fill(1)
	return state


func _trigger(id: String, event: String, priority: int = 0, extra: Dictionary = {}) -> Dictionary:
	var trigger := { "id": id, "event": event, "conditions": [], "once": false, "cooldown": 0,
		"priority": priority, "lines": [{ "tone": "warm", "text": "%s speaks" % id }] }
	trigger.merge(extra, true)
	return trigger


## Uses a made-up advisor "test" with these triggers.
func _use(triggers: Array, max_per_turn: int = 1) -> void:
	AdvisorDefs.use_defs({ "advisors": ["test"], "max_messages_per_turn": max_per_turn, "log_limit": 50 }, {
		"test": { "id": "test", "name": "Tess", "title": "Tester", "portrait": "advisor_test",
			"placeholder_color": "#888888", "initial_state": {}, "policies": { "city_site": "best" },
			"phrases": { "site_here": "here", "site_away": "{site_distance} to the {site_direction}" },
			"triggers": triggers },
	})


func _say(state: GameState, events: Array[Dictionary]) -> String:
	var message := AdvisorDirector.observe(state, 0, events)
	return String(message.get("trigger", ""))


func _event(type: String, fields: Dictionary = {}) -> Dictionary:
	var event := { "type": type }
	event.merge(fields)
	return event


func _json(data: Dictionary) -> String:
	return JSON.stringify(data)


# --- Text and conditions -----------------------------------------------------

func _test_text_placeholders() -> void:
	var values := { "city_name": "Rome", "item": "a Granary" }
	_check(AdvisorText.fill("{city_name} has finished {item}.", values) == "Rome has finished a Granary.",
		"placeholders are filled")
	_check(AdvisorText.fill("{city_name} and {city_name}", values) == "Rome and Rome", "repeats are filled")
	_check(AdvisorText.fill("Hello {nobody}", values) == "Hello {nobody}", "unknown placeholders stay")
	_check(AdvisorText.can_fill("{city_name}", values) and not AdvisorText.can_fill("{tech}", values),
		"can_fill tells whether every placeholder has a value")
	_check(Array(AdvisorText.placeholders("{a_b} x {c}")) == ["a_b", "c"], "placeholders are listed")


func _test_conditions() -> void:
	var state := _make_state()
	var memory := { "mood": "calm", "count": 2 }
	var event := {}
	_check(AdvisorConditions.holds({ "fact": "city_count", "op": "==", "value": 0.0 }, state, 0, event, memory),
		"float values from JSON compare with int facts")
	_check(AdvisorConditions.holds({ "fact": "turn", "op": ">=", "value": 1 }, state, 0, event, memory), "turn >= 1")
	_check(not AdvisorConditions.holds({ "fact": "turn", "op": ">", "value": 1 }, state, 0, event, memory), "not turn > 1")
	_check(AdvisorConditions.holds({ "fact": "memory.mood", "op": "==", "value": "calm" }, state, 0, event, memory),
		"conditions read the advisor's memory")
	_check(AdvisorConditions.holds({ "fact": "memory.count", "op": "<", "value": 3 }, state, 0, event, memory),
		"memory numbers compare")
	_check(not AdvisorConditions.holds({ "fact": "memory.missing", "op": "==", "value": true }, state, 0, event, memory),
		"unset memory doesn't match")
	_check(AdvisorConditions.holds({ "fact": "research_chosen", "op": "==", "value": false }, state, 0, event, memory),
		"no research chosen yet")
	var settler := state.add_unit("settler", 0, CENTER)
	var warrior := state.add_unit("warrior", 0, CENTER)
	var can_found := { "fact": "event_unit_can_found", "op": "==", "value": true }
	_check(AdvisorConditions.holds(can_found, state, 0, { "unit_id": settler.id }, memory), "a settler can found")
	_check(not AdvisorConditions.holds(can_found, state, 0, { "unit_id": warrior.id }, memory), "a warrior can't")
	_check(AdvisorConditions.compare("a", "==", "a") and not AdvisorConditions.compare("1", "==", 1),
		"different types never compare equal")


# --- Matching, priority, limits ------------------------------------------------

func _test_trigger_matching() -> void:
	_use([
		_trigger("first_city", "city_founded", 0, { "conditions": [{ "fact": "city_count", "op": "==", "value": 1 }] }),
		_trigger("on_select", "unit_selected"),
	])
	var state := _make_state()
	_check(_say(state, [_event("turn_started", { "turn": 1 })]) == "", "no trigger listens for turn_started")
	var settler := state.add_unit("settler", 0, CENTER)
	var events := GameActions.found_city(state, settler.id)
	_check(_say(state, events) == "first_city", "city_founded with one city matches")
	state.turn += 1
	var second := state.add_unit("settler", 0, CENTER + Vector2i(6, 0))
	_check(_say(state, GameActions.found_city(state, second.id)) == "", "the city_count condition fails for a second city")
	var warrior := state.add_unit("warrior", 0, CENTER)
	_check(_say(state, [_event("unit_selected", { "unit_id": warrior.id })]) == "on_select",
		"session events (unit_selected) match too")


func _test_event_owner_filter() -> void:
	_use([_trigger("built", "city_built")])
	var state := _make_state()
	state.add_player("Rival", "#000000")
	var mine := state.add_city(0, CENTER)
	var theirs := state.add_city(1, CENTER + Vector2i(6, 0))
	_check(_say(state, [_event("city_built", { "city_id": theirs.id, "item": "warrior" })]) == "",
		"another player's city doesn't trigger the advisor")
	_check(_say(state, [_event("city_built", { "city_id": mine.id, "item": "warrior" })]) == "built",
		"the player's own city does")


func _test_priority_and_turn_limit() -> void:
	_use([_trigger("low", "city_built", 10), _trigger("high", "city_idle", 50), _trigger("mid", "city_grew", 30)])
	var state := _make_state()
	var city := state.add_city(0, CENTER)
	var events: Array[Dictionary] = [
		_event("city_built", { "city_id": city.id, "item": "warrior" }),
		_event("city_grew", { "city_id": city.id, "size": 2 }),
		_event("city_idle", { "city_id": city.id }),
	]
	_check(_say(state, events) == "high", "the highest priority match speaks")
	_check(_say(state, events) == "", "only one message per turn")
	state.turn += 1
	_check(_say(state, events) == "high", "cooldown 0: the top trigger may speak again next turn")
	_use([_trigger("low", "city_built", 10), _trigger("high", "city_idle", 50)], 2)
	var two := _make_state()
	var two_city := two.add_city(0, CENTER)
	var batch: Array[Dictionary] = [_event("city_built", { "city_id": two_city.id, "item": "warrior" }),
		_event("city_idle", { "city_id": two_city.id })]
	_check(_say(two, batch) == "high" and _say(two, batch) == "low" and _say(two, batch) == "",
		"max_messages_per_turn comes from data")


func _test_cooldown_and_once() -> void:
	_use([_trigger("cool", "city_built", 0, { "cooldown": 3 }), _trigger("once", "city_idle", 0, { "once": true })], 5)
	var state := _make_state()
	var city := state.add_city(0, CENTER)
	var built: Array[Dictionary] = [_event("city_built", { "city_id": city.id, "item": "warrior" })]
	var idle: Array[Dictionary] = [_event("city_idle", { "city_id": city.id })]
	_check(_say(state, built) == "cool", "cooldown trigger speaks on turn 1")
	state.turn = 2
	_check(_say(state, built) == "", "still cooling down on turn 2")
	state.turn = 3
	_check(_say(state, built) == "", "still cooling down on turn 3")
	state.turn = 4
	_check(_say(state, built) == "cool", "speaks again after 3 turns")
	_check(_say(state, idle) == "once", "once-only trigger speaks the first time")
	for turn in range(5, 30):
		state.turn = turn
		_check(_say(state, idle) == "", "once-only trigger never repeats (turn %d)" % turn)


func _test_carry_over() -> void:
	_use([_trigger("big", "game_started", 100), _trigger("first_city", "city_founded", 50, { "carry_over": 2 })])
	var state := _make_state()
	var settler := state.add_unit("settler", 0, CENTER)
	_check(_say(state, [_event("game_started", { "player": 0 })]) == "big", "setup: turn 1's message is spent")
	_check(_say(state, GameActions.found_city(state, settler.id)) == "", "over the limit: nothing more on turn 1")
	_check(state.advisor.pending.size() == 1, "the blocked trigger waits")
	state.turn = 2
	_check(_say(state, [_event("turn_started", { "turn": 2 })]) == "first_city", "and speaks on the next turn")
	_check(state.advisor.pending.is_empty(), "then stops waiting")
	# A carried match that waits too long expires.
	var late := _make_state()
	var late_settler := late.add_unit("settler", 0, CENTER)
	_say(late, [_event("game_started", { "player": 0 })])
	_say(late, GameActions.found_city(late, late_settler.id))
	late.turn = 4
	_check(_say(late, [_event("turn_started", { "turn": 4 })]) == "", "carry-over expires after its turns")


func _test_unfillable_lines_skipped() -> void:
	_use([_trigger("spotted", "barbarians_spotted", 0, { "lines": [
		{ "tone": "warm", "text": "Raiders near {city_name}!" },
		{ "tone": "warm", "text": "Raiders in the wilds." }] }),
		_trigger("empty", "city_idle", 0, { "lines": [{ "tone": "warm", "text": "{nothing}" }] })], 5)
	var state := _make_state()
	var message := AdvisorDirector.observe(state, 0, [_event("barbarians_spotted", { "player": 0, "city_id": 0 })])
	_check(String(message.get("text", "")) == "Raiders in the wilds.", "lines whose placeholders can't be filled are skipped")
	var city := state.add_city(0, CENTER)
	_check(String(AdvisorDirector.observe(state, 0, [_event("city_idle", { "city_id": city.id })]).get("trigger", "")) == "",
		"a trigger with no fillable line says nothing")
	state.turn = 2
	message = AdvisorDirector.observe(state, 0, [_event("barbarians_spotted", { "player": 0, "city_id": city.id })])
	_check(String(message.get("text", "")) == "Raiders near %s!" % city.name, "the city name is filled in")


func _test_line_variety_uses_own_rng() -> void:
	var lines: Array = []
	for i in 4:
		lines.append({ "tone": "warm", "text": "line %d" % i })
	_use([_trigger("chatty", "city_built", 0, { "lines": lines })])
	var state := _make_state()
	var city := state.add_city(0, CENTER)
	state.rng.seed = 99
	var gameplay_state := state.rng.state
	var advisor_state := state.advisor.rng.state
	var last := ""
	var repeats := 0
	for turn in range(1, 30):
		state.turn = turn
		var text := String(AdvisorDirector.observe(state, 0,
			[_event("city_built", { "city_id": city.id, "item": "warrior" })]).get("text", ""))
		if text == last:
			repeats += 1
		last = text
	_check(state.rng.state == gameplay_state, "picking lines never touches the gameplay RNG")
	_check(state.advisor.rng.state != advisor_state, "it draws from the advisor's own RNG")
	_check(repeats == 0, "the same line is never used twice in a row")


func _test_disabled_says_nothing() -> void:
	_use([_trigger("built", "city_built")])
	var state := _make_state()
	var city := state.add_city(0, CENTER)
	AdvisorDirector.set_enabled(state, false)
	_check(_say(state, [_event("city_built", { "city_id": city.id, "item": "warrior" })]) == "", "off: nothing is said")
	_check(state.advisor.last_fired("test", "built") == -1, "off: no trigger is spent")
	AdvisorDirector.set_enabled(state, true)
	_check(_say(state, [_event("city_built", { "city_id": city.id, "item": "warrior" })]) == "built", "on again: it speaks")


# --- City site scorer ------------------------------------------------------------

func _test_scorer_ranking() -> void:
	var state := _make_state("plains")
	var ranked := CitySiteScorer.rank(state, 0, CENTER)
	_check(not ranked.is_empty(), "sites are found on open land")
	if ranked.is_empty():
		return
	_check(ranked[0]["cell"] == CENTER, "on uniform land the settler's own tile is best (no walk)")
	var sorted := true
	for i in range(1, ranked.size()):
		if int(ranked[i - 1]["score"]) < int(ranked[i]["score"]):
			sorted = false
	_check(sorted, "the ranking is best first")
	_check(_json({ "r": ranked }) == _json({ "r": CitySiteScorer.rank(state, 0, CENTER) }), "the ranking is deterministic")
	_check(CitySiteScorer.rank(state, 0, CENTER, -1, 3).size() == 3, "limit keeps the top few")
	# Richer land a few steps away beats the settler's own tile.
	var rich := CENTER + Vector2i(0, 6)
	for cell in IsoGrid.cells_within(rich, 2, state.map.width, state.map.height):
		state.map.set_terrain(cell, "grassland")
	for cell in IsoGrid.cells_within(rich, 1, state.map.width, state.map.height):
		state.map.set_terrain(cell, "forest")
	state.map.set_terrain(rich, "grassland")
	var best: Vector2i = CitySiteScorer.rank(state, 0, CENTER)[0]["cell"]
	_check(IsoGrid.step_distance(best, rich) <= 1, "food and production pull the best site toward rich land (got %s)" % best)


func _test_scorer_coast_overlap_edge() -> void:
	var state := _make_state("plains")
	var ocean := CENTER + Vector2i(3, 0)
	state.map.set_terrain(ocean, "ocean")
	var coastal := CitySiteScorer.score_site(state, 0, CENTER + Vector2i(2, 0), 2)
	var inland := CitySiteScorer.score_site(state, 0, CENTER + Vector2i(-2, 0), 2)
	_check(bool(coastal["coast"]) and not bool(inland["coast"]), "coastal tiles are recognised")
	_check(int(coastal["score"]) > int(inland["score"]), "the coast adds to a site's score")
	var spaced := _make_state("plains")
	spaced.add_city(0, CENTER)
	var near := CitySiteScorer.score_site(spaced, 0, CENTER + Vector2i(4, 0))
	var far := CitySiteScorer.score_site(spaced, 0, CENTER + Vector2i(0, 16))
	_check(int(near["overlap"]) > 0 and int(far["overlap"]) == 0, "overlap with a city's work area is counted")
	_check(int(near["score"]) < int(far["score"]), "overlapping another city scores lower")
	var edge := CitySiteScorer.score_site(spaced, 0, Vector2i(0, 30))
	var middle := CitySiteScorer.score_site(spaced, 0, Vector2i(10, 30))
	_check(int(edge["score"]) < int(middle["score"]), "the map edge scores lower")
	var close := CitySiteScorer.score_site(state, 0, CENTER, 1)
	var walk := CitySiteScorer.score_site(state, 0, CENTER, 4)
	_check(int(walk["score"]) < int(close["score"]), "a longer walk scores lower")


func _test_scorer_respects_fog_and_rules() -> void:
	var state := _make_state("plains")
	state.explored[0].fill(0)
	Fog.reveal_radius(state, 0, CENTER, 2)
	for entry in CitySiteScorer.rank(state, 0, CENTER):
		_check(state.is_explored(0, entry["cell"]), "only explored tiles are suggested")
	state.explored[0].fill(1)
	state.add_city(0, CENTER + Vector2i(0, 8))
	for entry in CitySiteScorer.rank(state, 0, CENTER):
		_check(IsoGrid.step_distance(entry["cell"], CENTER + Vector2i(0, 8)) > CityRules.no_city_within(),
			"no site breaks the city spacing rule")
	# Land across water isn't reachable on foot.
	var island := _make_state("ocean")
	for cell in IsoGrid.cells_within(CENTER, 1, 20, 40):
		island.map.set_terrain(cell, "grassland")
	var far_land := CENTER + Vector2i(5, 0)
	island.map.set_terrain(far_land, "grassland")
	var cells: Array = []
	for entry in CitySiteScorer.rank(island, 0, CENTER):
		cells.append(entry["cell"])
		_check(TerrainDefs.passable_by_land(island.map.get_terrain(entry["cell"])), "sites are on land")
	_check(not cells.has(far_land), "land across the water isn't offered")


func _test_selection_policy() -> void:
	var rng := RandomNumberGenerator.new()
	var options: Array[Dictionary] = [{ "cell": Vector2i(1, 1), "score": 9 }, { "cell": Vector2i(2, 2), "score": 5 }]
	_check(AdvisorPolicy.select("best", options, rng)["cell"] == Vector2i(1, 1), "'best' takes the top option")
	_check(AdvisorPolicy.select("best", [] as Array[Dictionary], rng).is_empty(), "no options, no choice")
	_check(AdvisorPolicy.select("mystery", options, rng)["cell"] == Vector2i(1, 1), "unknown policies fall back to best")
	_use([_trigger("site", "unit_selected", 0, { "action": { "type": "suggest_city_site", "policy": "city_site" },
		"lines": [{ "tone": "warm", "text": "Settle {site_where}." }] })])
	var state := _make_state("plains")
	var settler := state.add_unit("settler", 0, CENTER)
	var message := AdvisorDirector.observe(state, 0, [_event("unit_selected", { "unit_id": settler.id })])
	var ranked := CitySiteScorer.rank(state, 0, CENTER)
	_check(message.get("highlight") == ranked[0]["cell"], "the advisor suggests the policy's pick and highlights it")
	_check(String(message.get("text", "")) == "Settle here.", "site placeholders are filled (got '%s')" % message.get("text"))


# --- Saving ----------------------------------------------------------------------

func _test_save_round_trip() -> void:
	_use([_trigger("built", "city_built", 0, { "cooldown": 4, "carry_over": 3 }), _trigger("site", "unit_selected", 10, {
		"action": { "type": "suggest_city_site", "policy": "city_site" },
		"lines": [{ "tone": "warm", "text": "Go {site_where}" }, { "tone": "warm", "text": "Try {site_where}" }] })])
	var state := _make_state("plains")
	var city := state.add_city(0, CENTER + Vector2i(0, 20))
	var settler := state.add_unit("settler", 0, CENTER)
	state.advisor.memory("test")["mood"] = "calm"
	AdvisorDirector.observe(state, 0, [_event("city_built", { "city_id": city.id, "item": "warrior" }),
		_event("unit_selected", { "unit_id": settler.id })])
	var data := state.to_dict()
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(_json(loaded.to_dict()) == _json(data), "advisor state survives a save exactly")
	_check(loaded.advisor.last_fired("test", "site") == 1, "spoken triggers survive")
	_check(loaded.advisor.pending.size() == 1, "waiting triggers survive")
	_check(loaded.advisor.advice_log.size() == 1 and loaded.advisor.advice_log[0].has("suggested"), "the advice log survives")
	_check(String(loaded.advisor.memory("test").get("mood", "")) == "calm", "advisor memory survives")
	_check(loaded.advisor.rng.state == state.advisor.rng.state, "the advisor's RNG survives")
	state.advisor.enabled = false
	_check(not GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict()))).advisor.enabled,
		"turning the advisor off is saved")


func _test_old_save_loads() -> void:
	var state := GameSetup.new_game(SEED, 40, 80)
	var data := state.to_dict()
	data.erase("advisor")
	data["version"] = 6
	_check(SaveSystem.check(data) == "", "a version 6 save passes the checks")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(loaded != null and loaded.advisor.enabled and loaded.advisor.advice_log.is_empty(),
		"a version 6 save loads with a fresh advisor")
	_check(loaded.advisor.rng.seed == GameState.advisor_seed(state.map.generation_seed), "its advisor gets a seeded RNG")
	_check(int(state.to_dict()["version"]) >= 7, "saves are version 7 or later")


# --- The real advisor ----------------------------------------------------------

func _test_real_advisor_data() -> void:
	var ids := AdvisorDefs.ids()
	_check(ids.size() == 1, "exactly one advisor is active")
	if ids.is_empty():
		return
	var def := AdvisorDefs.get_def(ids[0])
	for key in ["id", "name", "title", "portrait", "personality", "triggers"]:
		_check(def.has(key), "the advisor defines %s" % key)
	var wanted := { "game_started": false, "unit_selected": false, "city_founded": false, "city_built": false,
		"city_idle": false, "tech_discovered": false, "barbarians_spotted": false }
	for trigger: Dictionary in def.get("triggers", []):
		wanted[String(trigger["event"])] = true
		for key in ["id", "event", "once", "cooldown", "priority", "lines"]:
			_check(trigger.has(key), "trigger %s defines %s" % [trigger.get("id"), key])
		for line: Dictionary in trigger["lines"]:
			_check(String(line.get("tone", "")) == "warm", "every line is warm for now (%s)" % trigger["id"])
	for event: String in wanted:
		_check(wanted[event], "some trigger listens for %s" % event)
	var state := GameSetup.new_game(SEED, 40, 80)
	var settler: UnitState = null
	for unit in state.units_of(0):
		if UnitDefs.can_found_city(unit.type):
			settler = unit
	var message := AdvisorDirector.observe(state, 0, [_event("game_started", { "player": 0 }),
		_event("unit_selected", { "unit_id": settler.id })])
	_check(String(message.get("trigger", "")) == "welcome", "a new game opens with the welcome")
	var cell: Vector2i = message.get("highlight", Vector2i(-1, -1))
	_check(CitySiteScorer.can_settle(state, 0, cell), "the welcome marks a site a city can be founded on")
	_check(not String(message.get("text", "")).contains("{"), "every placeholder is filled: %s" % message.get("text"))
	_check(not String(message.get("text", "")).to_lower().contains("tip"), "no 'Tip' wording")
	var site := AdvisorDirector.suggest_city_site(state, 0, "steward", { "unit_id": settler.id }, "city_site")
	var steps := int(site["values"]["site_distance"])
	_check(String(site["values"]["site_steps"]) == ("1 step" if steps == 1 else "%d steps" % steps),
		"site_steps agrees with the distance, singular for one")
	_check(AdvisorText.fill(AdvisorDefs.phrase("steward", "site_away"), { "site_steps": "1 step",
		"site_direction": "north" }) == "1 step to the north", "one step away reads '1 step to the north'")


func _test_advice_followed_log() -> void:
	var state := GameSetup.new_game(SEED, 40, 80)
	var settler: UnitState = state.units_of(0)[0]
	for unit in state.units_of(0):
		if UnitDefs.can_found_city(unit.type):
			settler = unit
	var message := AdvisorDirector.observe(state, 0, [_event("game_started", { "player": 0 })])
	var suggested: Vector2i = message["highlight"]
	var log := AdvisorDirector.advice_log(state)
	_check(log.size() == 1 and String(log[0]["outcome"]) == "pending", "the suggestion is logged as pending")
	var start := settler.position
	AdvisorDirector.observe(state, 0, GameActions.found_city(state, settler.id))
	var entry: Dictionary = log[0]
	var expected := "followed" if start == suggested else "elsewhere"
	_check(String(entry["outcome"]) == expected, "founding resolves the advice as %s (got %s)" % [expected, entry["outcome"]])
	_check(int(entry["distance"]) == IsoGrid.step_distance(start, suggested), "the log notes how far off the city was")
	_check(entry["actual"] == [start.x, start.y], "the log notes where the city was founded")


func _test_first_scout_line() -> void:
	var state := GameSetup.new_game(SEED, 40, 80)
	var city := state.add_city(0, state.units[0].position)
	var built: Array[Dictionary] = [_event("city_built", { "city_id": city.id, "item": "warrior" })]
	_check(String(AdvisorDirector.observe(state, 0, built).get("trigger", "")) != "first_scout",
		"a warrior doesn't bring up exploring")
	state.turn = 5
	var scout: Array[Dictionary] = [_event("city_built", { "city_id": city.id, "item": "scout" })]
	var message := AdvisorDirector.observe(state, 0, scout)
	_check(String(message.get("trigger", "")) == "first_scout", "the first scout brings up Explore")
	_check(String(message.get("text", "")).contains("Explore"), "and names the command")
	state.turn = 20
	_check(String(AdvisorDirector.observe(state, 0, scout).get("trigger", "")) != "first_scout", "only the first time")


# --- Determinism -------------------------------------------------------------------

## The same seeded game, played with the same orders, with the advisor
## watching every step or switched off, ends in exactly the same state.
func _test_determinism_on_off() -> void:
	var with_advisor := _scripted_game(true)
	var without := _scripted_game(false)
	var a: Dictionary = with_advisor.to_dict()
	var b: Dictionary = without.to_dict()
	_check(not (a["advisor"]["log"] as Array).is_empty(), "the advisor spoke during the game")
	_check((b["advisor"]["log"] as Array).is_empty(), "the advisor said nothing while off")
	a.erase("advisor")
	b.erase("advisor")
	_check(_json(a) == _json(b), "the game plays out identically with the advisor on and off")


func _scripted_game(advisor_on: bool) -> GameState:
	var state := GameSetup.new_game(SEED, 40, 80)
	AdvisorDirector.set_enabled(state, advisor_on)
	_watch(state, [_event("game_started", { "player": 0 })])
	for turn in 60:
		for unit in state.units_of(0):
			_watch(state, [_event("unit_selected", { "unit_id": unit.id })])
			if state.get_unit(unit.id) == null:
				continue
			if UnitDefs.can_found_city(unit.type) and CityRules.can_found(state, unit) == "":
				_watch(state, GameActions.found_city(state, unit.id))
			elif not unit.has_goal():
				var goal := unit.position + Vector2i(1 if turn % 2 == 0 else -1, 2)
				if state.map.in_bounds(goal):
					_watch(state, GameActions.move_unit(state, unit.id, goal))
		for city in state.cities_of(0):
			if city.queue.is_empty():
				_watch(state, GameActions.enqueue_build(state, city.id, "warrior" if turn % 3 else "settler"))
		_watch(state, GameActions.end_turn(state))
	return state


func _watch(state: GameState, events: Array[Dictionary]) -> void:
	AdvisorDirector.observe(state, 0, events)
