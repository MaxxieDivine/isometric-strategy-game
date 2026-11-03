extends SceneTree
## Headless tests for the scout and auto-explore: scout movement and sight,
## scouts can't attack, frontier targets and their tie-breaks, avoiding
## barbarians, waking up (finished, barbarians, wounded, new order),
## explorers skipped by auto-select, saving, and RNG-free determinism.
## Run: godot --headless --path . --script res://tests/test_exploration.gd

const CENTER := Vector2i(8, 20)
const SEED := 2024

var _failures := 0


func _initialize() -> void:
	_test_scout_definition()
	_test_scout_terrain_costs()
	_test_scout_sight()
	_test_scout_cannot_attack()
	_test_frontier()
	_test_target_tie_breaks()
	_test_target_prefers_cheaper_route()
	_test_avoids_camps()
	_test_avoids_ending_next_to_barbarians()
	_test_wakes_when_finished()
	_test_wakes_on_barbarians()
	_test_known_threats_dont_wake()
	_test_wakes_when_hurt()
	_test_new_order_stops_exploring()
	_test_explorers_skipped_by_auto_select()
	_test_explores_at_turn_start()
	_test_military_explorers_never_attack()
	_test_save_round_trip()
	_test_old_save_loads()
	_test_no_gameplay_rng()
	_test_seeded_game_deterministic()
	if _failures == 0:
		print("All exploration tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

## A 20 × 40 map of `fill`; the player knows only what `known_radius` around
## CENTER reveals (-1: everything).
func _make_state(fill: String = "grassland", known_radius: int = -1) -> GameState:
	var state := GameState.new()
	state.map = MapState.new(20, 40, fill)
	state.add_player("Tester", "#ffffff")
	state.ensure_barbarian_player()
	if known_radius < 0:
		state.explored[0].fill(1)
	else:
		Fog.reveal_radius(state, 0, CENTER, known_radius)
	return state


func _has_event(events: Array[Dictionary], type: String) -> bool:
	for event in events:
		if event["type"] == type:
			return true
	return false


func _stop_reason(events: Array[Dictionary]) -> String:
	for event in events:
		if event["type"] == "explore_stopped":
			return String(event["reason"])
	return ""


## An island of grassland (radius `radius` around CENTER) in ocean.
func _island(radius: int) -> GameState:
	var state := _make_state("ocean", 1)
	for cell in IsoGrid.cells_within(CENTER, radius, 20, 40):
		state.map.set_terrain(cell, "grassland")
	return state


func _json(state: GameState) -> String:
	return JSON.stringify(state.to_dict())


# --- Scout --------------------------------------------------------------------

func _test_scout_definition() -> void:
	var def := UnitDefs.get_def("scout")
	_check(int(def.get("cost", 0)) == 15 and UnitDefs.max_moves("scout") == 3, "scout: cost 15, 3 moves")
	_check(int(def.get("attack", -1)) == 0 and int(def.get("defense", 0)) == 1, "scout: attack 0, defense 1")
	_check(UnitDefs.sight("scout") == 2 and UnitDefs.sight("warrior") == 1, "scouts see 2, others 1")
	_check(TechDefs.required_for("scout") == "", "scouts need no tech")
	var state := _make_state()
	var city := state.add_city(0, CENTER)
	_check(Production.available_items(state, city).has("scout"), "a new city can build scouts")
	_check(String(def.get("sprite", "")) == "unit_scout" and String(def.get("letter", "")) == "Sc",
		"scout art: sprite key with an 'Sc' placeholder")


func _test_scout_terrain_costs() -> void:
	var map := MapState.new(20, 40, "hills")
	map.set_terrain(CENTER, "forest")
	map.set_terrain(CENTER + Vector2i(1, 0), "ocean")
	var known := PackedByteArray()
	_check(Movement.unit_enter_cost(map, known, CENTER, "scout") == 1, "forest costs a scout 1")
	_check(Movement.unit_enter_cost(map, known, CENTER + Vector2i(0, 2), "scout") == 1, "hills cost a scout 1")
	_check(Movement.unit_enter_cost(map, known, CENTER, "warrior") == 2, "forest still costs a warrior 2")
	_check(Movement.unit_enter_cost(map, known, CENTER + Vector2i(1, 0), "scout") == Movement.IMPASSABLE,
		"scouts can't walk on water")
	var state := _make_state("hills")
	var scout := state.add_unit("scout", 0, CENTER)
	GameActions.move_unit(state, scout.id, CENTER + Vector2i(0, 6))
	_check(scout.position == CENTER + Vector2i(0, 6), "a scout crosses 3 hills in one turn (at %s)" % scout.position)
	var warrior := state.add_unit("warrior", 0, CENTER)
	GameActions.move_unit(state, warrior.id, CENTER + Vector2i(0, 6))
	_check(IsoGrid.step_distance(CENTER, warrior.position) == 1, "a warrior manages 1 hill")


func _test_scout_sight() -> void:
	var state := _make_state("plains", 0)
	state.explored[0].fill(0)
	var scout := state.add_unit("scout", 0, CENTER)
	Fog.reveal_for_units(state, 0)
	_check(state.is_explored(0, CENTER + Vector2i(0, 4)), "a scout sees 2 tiles away")
	_check(not state.is_explored(0, CENTER + Vector2i(0, 6)), "but not 3")
	var visible := Fog.compute_visible(state, 0)
	_check(visible.count(1) == IsoGrid.cells_within(scout.position, 2, 20, 40).size(), "it sees the whole radius-2 area")


func _test_scout_cannot_attack() -> void:
	var state := _make_state()
	var scout := state.add_unit("scout", 0, CENTER)
	_check(not Combat.can_attack(scout), "scouts can't attack")
	var target := CENTER + Vector2i(0, 2)
	var raider := state.add_unit("warrior", state.barbarian_id(), target)
	var events := GameActions.move_unit(state, scout.id, target)
	_check(not _has_event(events, "combat"), "moving a scout into an enemy starts no fight")
	_check(state.get_unit(raider.id) != null and scout.position != target, "the enemy stays and the scout stops")


# --- Targets ----------------------------------------------------------------

func _test_frontier() -> void:
	var state := _make_state("grassland", 2)
	_check(Exploration.is_frontier(state, 0, CENTER + Vector2i(0, 4)), "known land at the edge of the known is frontier")
	_check(not Exploration.is_frontier(state, 0, CENTER), "known land surrounded by known isn't")
	_check(not Exploration.is_frontier(state, 0, CENTER + Vector2i(0, 8)), "unknown tiles aren't frontier")
	state.map.set_terrain(CENTER + Vector2i(0, 4), "ocean")
	_check(not Exploration.is_frontier(state, 0, CENTER + Vector2i(0, 4)), "water isn't frontier for land units")


func _test_target_tie_breaks() -> void:
	var state := _make_state("grassland", 3)
	var scout := state.add_unit("scout", 0, CENTER)
	var costs := Pathfinder.cost_map(state.map, state.explored[0], CENTER, "land", true)
	var expected := Vector2i(-1, -1)
	var best := Pathfinder.UNREACHED
	for y in 40:
		for x in 20:
			var cell := Vector2i(x, y)
			var cost := costs[IsoGrid.index_of(cell, 20)]
			if cell != CENTER and Exploration.is_frontier(state, 0, cell) and cost < best:
				best = cost
				expected = cell
	var target := Exploration.next_target(state, scout)
	_check(target == expected, "the nearest frontier tile wins, lowest row then column on ties (%s vs %s)" % [target, expected])
	_check(Exploration.next_target(state, scout) == target, "the choice is the same every time")
	var ties := 0
	for i in costs.size():
		var cell := IsoGrid.cell_of(i, 20)
		if cell != CENTER and costs[i] == best and Exploration.is_frontier(state, 0, cell):
			ties += 1
	_check(ties > 1, "setup: several frontier tiles tie on distance (%d)" % ties)


func _test_target_prefers_cheaper_route() -> void:
	var state := _make_state("grassland", 3)
	# Everything north of the scout is known: only southern frontier is left.
	for y in range(0, CENTER.y):
		for x in 20:
			Fog.reveal_radius(state, 0, Vector2i(x, y), 0)
	var warrior := state.add_unit("warrior", 0, CENTER)
	var target := Exploration.next_target(state, warrior)
	_check(target.y >= CENTER.y, "the target is where the unknown is (got %s)" % target)
	# Hills make the west side dearer for a warrior; it picks the cheap side.
	var west := _make_state("grassland", 3)
	for cell in IsoGrid.cells_within(CENTER + Vector2i(-2, 0), 2, 20, 40):
		if cell.x < CENTER.x:
			west.map.set_terrain(cell, "hills")
	var walker := west.add_unit("warrior", 0, CENTER)
	var pick := Exploration.next_target(west, walker)
	_check(pick.x >= CENTER.x, "with hills to the west, a warrior explores east first (got %s)" % pick)


func _test_avoids_camps() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	var camp := state.add_camp(CENTER + Vector2i(0, 4))
	camp.discovered_by.append(0)
	scout.exploring = true
	var visited: Array[Vector2i] = []
	for turn in 30:
		scout.moves_left = scout.max_moves()
		for event in Exploration.explore(state, scout, false):
			if event["type"] == "unit_moved":
				visited.append(event["to"])
		_check(Exploration.next_target(state, scout) != camp.position, "a camp is never the target")
		if not scout.exploring:
			break
	_check(not visited.has(camp.position), "the scout never steps onto a known camp")
	_check(state.get_camp(camp.id) != null, "and never clears it by accident")
	var danger := Exploration.danger_costs(state, 0)
	_check(danger[IsoGrid.index_of(camp.position, 20)] == Pathfinder.BLOCKED, "known camps are blocked for explorers")


func _test_avoids_ending_next_to_barbarians() -> void:
	# A barbarian sits just past where the scout would end its move.
	var state := _make_state("grassland", 3)
	var scout := state.add_unit("scout", 0, CENTER)
	scout.exploring = true
	var target := Exploration.next_target(state, scout)
	var raider := state.add_unit("warrior", state.barbarian_id(), target + Vector2i(0, 2))
	scout.explore_ignored = Exploration.threats_in_sight(state, scout)
	Exploration.explore(state, scout, false)
	var adjacent := IsoGrid.step_distance(scout.position, raider.position) <= 1
	_check(not adjacent, "the scout doesn't end its move next to a visible barbarian (at %s, raider %s)" % [
		scout.position, raider.position])
	var danger := Exploration.danger_costs(state, 0)
	_check(danger[IsoGrid.index_of(raider.position, 20)] == Pathfinder.BLOCKED, "the barbarian's tile is blocked")
	_check(danger[IsoGrid.index_of(raider.position + Vector2i(0, 2), 20)] == Exploration.danger_step_cost(),
		"tiles next to it cost extra")


# --- Waking up ----------------------------------------------------------------

func _test_wakes_when_finished() -> void:
	var state := _island(3)
	var scout := state.add_unit("scout", 0, CENTER)
	var reason := _stop_reason(GameActions.explore_unit(state, scout.id))
	var turns := 0
	while scout.exploring and turns < 40:
		reason = _stop_reason(GameActions.end_turn(state))
		turns += 1
	_check(reason == Exploration.FINISHED, "it stops with 'finished' (got '%s')" % reason)
	_check(not scout.exploring, "and is no longer exploring")
	for cell in IsoGrid.cells_within(CENTER, 3, 20, 40):
		_check(state.is_explored(0, cell), "the whole island is explored (%s)" % cell)
	GameActions.end_turn(state)
	_check(state.units_needing_orders(0).has(scout), "a finished explorer asks for orders again")
	var news := TurnNews.describe(state, [{ "type": "explore_stopped", "unit_id": scout.id, "unit_type": "scout",
		"reason": Exploration.FINISHED, "cell": scout.position }], 0)
	_check((news["lines"] as PackedStringArray).has("Scout finished exploring"), "the turn card says so")
	_check(news["jump"] == scout.position, "and clicking it jumps to the scout")


func _test_wakes_on_barbarians() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	GameActions.explore_unit(state, scout.id)
	_check(scout.exploring, "setup: exploring")
	# A raider appears within sight before the next turn.
	state.add_unit("warrior", state.barbarian_id(), scout.position + Vector2i(1, 2))
	scout.moves_left = scout.max_moves()
	var events := Exploration.explore(state, scout)
	_check(_stop_reason(events) == Exploration.BARBARIANS, "a barbarian coming into sight wakes it")
	_check(not scout.exploring and scout.moves_left == scout.max_moves(), "it stops before moving on")
	# A camp seen mid-move wakes it too: a strip of land leads south to one.
	var walk := _make_state("ocean", 1)
	for y in range(CENTER.y, CENTER.y + 16):
		walk.map.set_terrain(Vector2i(CENTER.x, y), "grassland")
	var runner := walk.add_unit("scout", 0, CENTER)
	walk.add_camp(Vector2i(CENTER.x, CENTER.y + 12))
	var reason := ""
	runner.exploring = true
	for turn in 10:
		runner.moves_left = runner.max_moves()
		reason = _stop_reason(Exploration.explore(walk, runner))
		if reason != "":
			break
	_check(reason == Exploration.BARBARIANS, "a camp coming into sight wakes it (got '%s')" % reason)
	var news := TurnNews.describe(walk, [{ "type": "explore_stopped", "unit_id": runner.id, "unit_type": "scout",
		"reason": Exploration.BARBARIANS, "cell": runner.position }], 0)
	_check(String((news["lines"] as PackedStringArray)[0]).begins_with("Scout spotted barbarians"), "the card says so")


func _test_known_threats_dont_wake() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	var camp := state.add_camp(CENTER + Vector2i(-2, 0))
	camp.discovered_by.append(0)
	var events := GameActions.explore_unit(state, scout.id)
	_check(_stop_reason(events) != Exploration.BARBARIANS, "barbarians already in sight when ordered don't wake it")


func _test_wakes_when_hurt() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	GameActions.explore_unit(state, scout.id)
	scout.hp = Combat.max_hp() / 2
	_check(not Exploration.is_hurt(scout), "exactly half HP is still fine")
	scout.hp -= 1
	scout.moves_left = scout.max_moves()
	_check(_stop_reason(Exploration.explore(state, scout)) == Exploration.HURT, "below half HP it stops")
	_check(not scout.exploring, "and waits for orders")


func _test_new_order_stops_exploring() -> void:
	var orders := {
		"move": func(state: GameState, unit: UnitState) -> void: GameActions.move_unit(state, unit.id, unit.position + Vector2i(0, 2)),
		"fortify": func(state: GameState, unit: UnitState) -> void: GameActions.fortify_unit(state, unit.id),
		"skip": func(state: GameState, unit: UnitState) -> void: GameActions.skip_unit(state, unit.id),
	}
	for name: String in orders:
		var state := _make_state("grassland", 2)
		var unit := state.add_unit("warrior", 0, CENTER)
		unit.exploring = true
		(orders[name] as Callable).call(state, unit)
		_check(not unit.exploring, "a %s order stops exploring" % name)
	var settle := _make_state("grassland", 2)
	var settler := settle.add_unit("settler", 0, CENTER)
	settler.exploring = true
	GameActions.found_city(settle, settler.id)
	_check(settle.city_at(CENTER) != null, "an exploring settler can still found a city")


func _test_explorers_skipped_by_auto_select() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	var warrior := state.add_unit("warrior", 0, CENTER)
	scout.exploring = true
	scout.moves_left = scout.max_moves()
	_check(not scout.needs_orders(), "an exploring unit needs no orders, even with moves left")
	var waiting := state.units_needing_orders(0)
	_check(not waiting.has(scout) and waiting.has(warrior), "auto-select skips explorers")


func _test_explores_at_turn_start() -> void:
	var state := _make_state("grassland", 2)
	var scout := state.add_unit("scout", 0, CENTER)
	GameActions.explore_unit(state, scout.id)
	var after_order := scout.position
	var events := GameActions.end_turn(state)
	_check(scout.position != after_order and _has_event(events, "unit_moved"), "explorers move on their own each turn")
	_check(scout.exploring, "and keep exploring")


func _test_military_explorers_never_attack() -> void:
	var state := _make_state("grassland", 2)
	var archer := state.add_unit("archer", 0, CENTER)
	GameActions.explore_unit(state, archer.id)
	# Surround the way forward with raiders and let it explore for a while.
	for offset: Vector2i in [Vector2i(0, 4), Vector2i(1, 4), Vector2i(0, -4)]:
		state.add_unit("warrior", state.barbarian_id(), CENTER + offset)
	archer.explore_ignored = Exploration.threats_in_sight(state, archer)
	for turn in 6:
		archer.moves_left = archer.max_moves()
		archer.exploring = true
		_check(not _has_event(Exploration.explore(state, archer, false), "combat"), "an exploring archer never attacks")


# --- Saving and determinism ------------------------------------------------------

func _test_save_round_trip() -> void:
	var state := GameSetup.new_game(SEED, 40, 80)
	var scout := state.add_unit("scout", 0, state.units[0].position)
	GameActions.explore_unit(state, scout.id)
	scout.explore_ignored.append("camp:9")
	var data := state.to_dict()
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	_check(JSON.stringify(loaded.to_dict()) == JSON.stringify(data), "a save with an explorer reloads identically")
	var copy := loaded.get_unit(scout.id)
	_check(copy.exploring and copy.explore_ignored.has("camp:9"), "exploring state survives the save")
	for turn in 8:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(_json(state) == _json(loaded), "a reloaded game explores exactly like the original")


func _test_old_save_loads() -> void:
	var data := GameSetup.new_game(SEED, 40, 80).to_dict()
	data["version"] = 7
	for unit: Dictionary in data["units"]:
		unit.erase("exploring")
		unit.erase("explore_ignored")
	_check(SaveSystem.check(data) == "", "a version 7 save passes the checks")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(data)))
	for unit in loaded.units:
		_check(not unit.exploring and unit.explore_ignored.is_empty(), "units from a version 7 save aren't exploring")
	_check(GameState.VERSION == 8, "saves are version 8")


func _test_no_gameplay_rng() -> void:
	var state := _make_state("grassland", 2)
	state.rng.seed = 77
	var before := state.rng.state
	var scout := state.add_unit("scout", 0, CENTER)
	GameActions.explore_unit(state, scout.id)
	for turn in 20:
		scout.moves_left = scout.max_moves()
		Exploration.explore(state, scout)
	_check(state.rng.state == before, "exploring never draws from the gameplay RNG")


## A seeded game with an explorer replays identically, and exploring draws
## nothing from the gameplay RNG.
func _test_seeded_game_deterministic() -> void:
	var a := _explore_game()
	var b := _explore_game()
	_check(_json(a) == _json(b), "a seeded game with an explorer plays out identically every time")
	# Barbarians react to where units are, so compare the RNG before they
	# arrive: an exploring scout and an idle one leave it in the same place.
	var scout_start := GameSetup.new_game(SEED, 40, 80).units[0].position
	var early_a := GameSetup.new_game(SEED, 40, 80)
	var early_b := GameSetup.new_game(SEED, 40, 80)
	var scout := early_a.add_unit("scout", 0, scout_start)
	early_b.add_unit("scout", 0, scout_start)
	GameActions.explore_unit(early_a, scout.id)
	for turn in Barbarians.start_turn() - 2:
		GameActions.end_turn(early_a)
		GameActions.end_turn(early_b)
	_check(early_a.rng.state == early_b.rng.state, "exploring leaves the gameplay RNG exactly where it would be")


func _explore_game() -> GameState:
	var state := GameSetup.new_game(SEED, 40, 80)
	var scout := state.add_unit("scout", 0, state.units[0].position)
	GameActions.explore_unit(state, scout.id)
	for turn in 40:
		if not scout.exploring and state.get_unit(scout.id) != null:
			GameActions.explore_unit(state, scout.id)
		GameActions.end_turn(state)
	return state
