extends SceneTree
## Pacing check for wonders and victory: a simple scripted player plays a full
## game (turn limit 150) and the run reports when each wonder was completed,
## the final score and breakdown, and whether Wonder Victory was reached.
##
## The scripted player:
##   - founds its capital at once and expands to 4 cities (settlers walk to
##     the best open site nearby),
##   - researches Pottery, Bronze Working, Masonry first (the wonder techs),
##   - keeps one fortified defender in every city (Archers once available),
##   - builds wonders in its best production city (picked once expansion is
##     done, or by turn 50) as soon as they unlock,
##   - fills other queues with Granary, Library, City Walls, warriors,
##   - from turn 50 sends one spare unit to explore and clear barbarian camps.
## A second pass ("spread") builds each wonder in a different city, for
## comparison.
##
## Run: godot --headless --path . --script res://tools/simulate_wonders.gd

const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6]
const MAP_SIZE := Vector2i(40, 80)
const TARGET_CITIES := 4
const SITE_SEARCH_RADIUS := 10
const RESEARCH_FIRST: Array[String] = ["pottery", "bronze_working", "masonry", "alphabet", "writing", "warrior_code"]
const PLAYER := 0
## Turn by which the wonder city is picked even if expansion isn't finished.
const WONDER_CITY_BY_TURN := 50

## Settler id -> target cell.
var _settler_targets: Dictionary = {}
## Defender id -> city id it guards.
var _guards: Dictionary = {}
var _hunter_id := -1
var _wonder_city_id := -1
## Comparison mode: every city may build a (different) wonder.
var _spread := false


func _initialize() -> void:
	var runs: Array[Dictionary] = []
	for map_seed in SEEDS:
		runs.append(_simulate(map_seed))
	_spread = true
	var spread_runs: Array[Dictionary] = []
	for map_seed in SEEDS:
		spread_runs.append(_simulate(map_seed))
	_spread = false
	print("=== Seed %d (headline run) ===" % SEEDS[0])
	_print_run(runs[0], true)
	print("")
	for i in range(1, runs.size()):
		print("seed %d best city: %s" % [runs[i]["seed"], ", ".join(runs[i]["production"])])
	print("")
	print("=== All seeds: wonders in the best production city ===")
	_print_table(runs)
	print("")
	print("=== Comparison: each wonder in a different city ===")
	_print_table(spread_runs)
	quit()


func _print_table(runs: Array[Dictionary]) -> void:
	print("  seed | cities | Gardens | Colossus | Wall | victory      | score (cit/tech/won/camp)  | title")
	for run in runs:
		var w: Dictionary = run["wonder_turns"]
		var b: Dictionary = run["breakdown"]
		print("  %4d | %6d | %7s | %8s | %4s | %-12s | %3d (%2d/%2d/%2d/%2d)          | %s" % [
			run["seed"], run["cities"], _turn_text(w, "hanging_gardens"), _turn_text(w, "colossus"),
			_turn_text(w, "great_wall"), run["ending"], b["total"],
			b["citizens"]["points"], b["techs"]["points"], b["wonders"]["points"], b["camps_destroyed"]["points"],
			run["title"]])


func _turn_text(turns: Dictionary, id: String) -> String:
	return "T%d" % turns[id] if turns.has(id) else "-"


func _simulate(map_seed: int) -> Dictionary:
	_settler_targets.clear()
	_guards.clear()
	_hunter_id = -1
	_wonder_city_id = -1
	var state := GameSetup.new_game(map_seed, MAP_SIZE.x, MAP_SIZE.y)
	for unit in state.units_of(PLAYER):
		if UnitDefs.can_found_city(unit.type):
			GameActions.found_city(state, unit.id)
			break
	var wonder_turns := {}
	var lost := 0
	var victory_turn := -1
	var log := PackedStringArray()
	var production_samples := PackedStringArray()
	while not Victory.is_over(state):
		_play_turn(state)
		if state.turn % 25 == 0:
			var best := _best_city(state) if not _spread else _most_productive(state)
			var building := best.queue[0] if not best.queue.is_empty() else "nothing"
			production_samples.append("T%d %s %d/turn (%s, %d/%d)" % [state.turn, best.name,
				CityRules.net_production(state, best), building, best.production_box, Production.cost(building) if building != "nothing" else 0])
		for event in GameActions.end_turn(state):
			match event["type"]:
				"wonder_built":
					wonder_turns[event["wonder"]] = int(event["turn"])
					log.append("T%d  %s completed the %s" % [event["turn"], state.get_city(event["city_id"]).name,
						WonderDefs.display_name(event["wonder"])])
				"combat":
					if int(event["defender_owner"]) == PLAYER and event["winner"] == "attacker" \
							or int(event["attacker_owner"]) == PLAYER and event["winner"] == "defender":
						lost += 1
				"city_sacked":
					log.append("T%d  barbarians sacked %s" % [state.turn, state.get_city(event["city_id"]).name])
				"game_over":
					if event["reason"] == Victory.WONDER_VICTORY:
						victory_turn = int(state.game_over["turn"])
	var breakdown := Score.breakdown(state, PLAYER)
	var chronicle := PackedStringArray()
	for entry in Chronicle.entries(state, PLAYER):
		match String(entry["type"]):
			"city_founded":
				chronicle.append("T%d founded %s" % [entry["turn"], entry["name"]])
			"tech_discovered":
				chronicle.append("T%d %s" % [entry["turn"], entry["name"]])
			"camp_destroyed":
				chronicle.append("T%d camp destroyed" % entry["turn"])
	var sizes := PackedStringArray()
	for city in state.cities_of(PLAYER):
		sizes.append("%s %d" % [city.name, city.size])
	return {
		"seed": map_seed,
		"state": state,
		"wonder_turns": wonder_turns,
		"breakdown": breakdown,
		"title": String(Score.title_for(int(breakdown["total"])).get("name", "")),
		"ending": "wonders T%d" % victory_turn if victory_turn > 0 else "turn limit",
		"victory_turn": victory_turn,
		"cities": state.cities_of(PLAYER).size(),
		"sizes": ", ".join(sizes),
		"units_lost": lost,
		"log": log,
		"chronicle": chronicle,
		"production": production_samples,
	}


func _print_run(run: Dictionary, detailed: bool) -> void:
	var state: GameState = run["state"]
	var w: Dictionary = run["wonder_turns"]
	print("Wonders completed:")
	for id in WonderDefs.ids():
		print("  %-16s %s" % [WonderDefs.display_name(id), "turn %d" % w[id] if w.has(id) else "not built"])
	if int(run["victory_turn"]) > 0:
		print("Wonder Victory: YES, on turn %d" % run["victory_turn"])
	else:
		print("Wonder Victory: no (game ended at the turn limit, %d)" % state.turn_limit)
	var b: Dictionary = run["breakdown"]
	print("Final score: %d   (%s)" % [b["total"], run["title"]])
	for part in Score.PARTS:
		print("  %-16s %3d x %2d = %3d" % [part, b[part]["count"], Score.weight(part), b[part]["points"]])
	print("Cities: %s" % run["sizes"])
	print("Units lost in combat: %d" % run["units_lost"])
	print("Best production city: " + ", ".join(run["production"]))
	if detailed:
		print("Timeline:")
		for line in run["chronicle"]:
			print("  " + line)
		for line in run["log"]:
			print("  " + line)
		var samples := PackedStringArray()
		for entry: Dictionary in state.score_history:
			if int(entry["turn"]) % 25 == 0:
				samples.append("T%d: %d" % [entry["turn"], entry["scores"]["0"]])
		print("Score over time: " + ", ".join(samples))


# --- The scripted player ------------------------------------------------------

func _play_turn(state: GameState) -> void:
	_pick_research(state)
	_assign_guards(state)
	for unit in state.units_of(PLAYER).duplicate():
		if state.get_unit(unit.id) == null:
			continue
		if UnitDefs.can_found_city(unit.type):
			_move_settler(state, unit)
		elif unit.id == _hunter_id:
			_move_hunter(state, unit)
		elif _guards.has(unit.id):
			_move_guard(state, unit)
		elif unit.needs_orders():
			GameActions.fortify_unit(state, unit.id)
	for city in state.cities_of(PLAYER):
		if city.queue.is_empty():
			var item := _next_build(state, city)
			if item != "":
				GameActions.enqueue_build(state, city.id, item)
		elif city.queue[0] == "warrior" or city.queue[0] == "granary":
			# Swap filler for a wonder as soon as one opens up here.
			var wonder := _wonder_for(state, city)
			if wonder != "" and city.queue.size() == 1:
				GameActions.enqueue_build(state, city.id, wonder)


func _pick_research(state: GameState) -> void:
	if Research.current(state, PLAYER) != "":
		return
	for tech in RESEARCH_FIRST:
		if Research.is_available(state, PLAYER, tech):
			GameActions.set_research(state, PLAYER, tech)
			return
	GameActions.auto_pick_research(state, PLAYER)


func _next_build(state: GameState, city: CityState) -> String:
	if _guard_count(city) == 0:
		return _defender_type(state, city)
	# A settler waits for size 2 in the queue, banking production meanwhile.
	var can_grow := city.size >= 2 or CityRules.food_surplus(state, city) > 0
	if _wants_settler(state) and not _is_wonder_city(state, city) and can_grow:
		return "settler"
	var wonder := _wonder_for(state, city)
	if wonder != "":
		return wonder
	if _hunter_id == -1 and not _hunter_queued(state) and state.turn >= WONDER_CITY_BY_TURN \
			and not _is_wonder_city(state, city) and _guard_count(city) > 0:
		return _defender_type(state, city)
	for id in ["granary", "library", "city_walls"]:
		if Production.can_enqueue(state, city, id) == "":
			return id
	# Nothing useful left: a spare unit only while it's free of upkeep;
	# otherwise leave the queue empty (production stays in the box).
	if state.units_supported_by(city.id).size() < CityRules.free_units():
		return _defender_type(state, city)
	return ""


func _defender_type(state: GameState, city: CityState) -> String:
	return "archer" if Production.can_enqueue(state, city, "archer") == "" else "warrior"


## A wonder this city should build now ("" if none): only the best
## production city builds them, once expansion is done (or nearly).
func _wonder_for(state: GameState, city: CityState) -> String:
	if not _is_wonder_city(state, city):
		return ""
	for id in WonderDefs.ids():
		if Production.can_enqueue(state, city, id) == "":
			return id
	return ""


func _is_wonder_city(state: GameState, city: CityState) -> bool:
	var expanded := state.cities_of(PLAYER).size() >= TARGET_CITIES
	if not expanded and state.turn < WONDER_CITY_BY_TURN:
		return false
	if _spread:
		return true
	if _wonder_city_id == -1:
		_wonder_city_id = _most_productive(state).id
	return city.id == _wonder_city_id


func _most_productive(state: GameState) -> CityState:
	var best: CityState = null
	for city in state.cities_of(PLAYER):
		if best == null or CityRules.net_production(state, city) > CityRules.net_production(state, best):
			best = city
	return best


func _hunter_queued(state: GameState) -> bool:
	for city in state.cities_of(PLAYER):
		if city.queue.has("archer") or city.queue.has("warrior"):
			return true
	return false


func _best_city(state: GameState) -> CityState:
	var best: CityState = null
	for city in state.cities_of(PLAYER):
		# A city already building a wonder stays the wonder city.
		for id in city.queue:
			if Production.is_wonder(id):
				return city
		if best == null or CityRules.net_production(state, city) > CityRules.net_production(state, best):
			best = city
	return best


func _wants_settler(state: GameState) -> bool:
	var settlers := 0
	for unit in state.units_of(PLAYER):
		if UnitDefs.can_found_city(unit.type):
			settlers += 1
	for city in state.cities_of(PLAYER):
		settlers += city.queue.count("settler")
	return state.cities_of(PLAYER).size() + settlers < TARGET_CITIES


# --- Defenders ----------------------------------------------------------------

func _guard_count(city: CityState) -> int:
	return _guards.values().count(city.id)


## Every city without a guard claims the nearest unassigned military unit.
func _assign_guards(state: GameState) -> void:
	for id: int in _guards.keys():
		if state.get_unit(id) == null or state.get_city(int(_guards[id])) == null:
			_guards.erase(id)
	if state.get_unit(_hunter_id) == null:
		_hunter_id = -1
	for city in state.cities_of(PLAYER):
		if _guard_count(city) > 0:
			continue
		var best: UnitState = null
		for unit in state.units_of(PLAYER):
			if UnitDefs.can_found_city(unit.type) or _guards.has(unit.id) or unit.id == _hunter_id:
				continue
			if best == null or IsoGrid.step_distance(unit.position, city.position) < IsoGrid.step_distance(best.position, city.position):
				best = unit
		if best != null:
			_guards[best.id] = city.id
	# A spare archer becomes the camp hunter.
	if _hunter_id == -1:
		for unit in state.units_of(PLAYER):
			if not UnitDefs.can_found_city(unit.type) and not _guards.has(unit.id):
				_hunter_id = unit.id
				break


func _move_guard(state: GameState, unit: UnitState) -> void:
	var city := state.get_city(int(_guards[unit.id]))
	if unit.position == city.position:
		if not unit.fortified:
			GameActions.fortify_unit(state, unit.id)
	elif not unit.has_goal():
		GameActions.move_unit(state, unit.id, city.position)


func _known_camp(state: GameState) -> CampState:
	for camp in state.camps:
		if camp.discovered_by.has(PLAYER):
			return camp
	return null


func _move_hunter(state: GameState, unit: UnitState) -> void:
	if unit.moves_left <= 0:
		return
	var home := _nearest_city(state, unit.position)
	if unit.hp < Combat.max_hp() / 2 and home != null:
		if unit.position != home.position:
			GameActions.move_unit(state, unit.id, home.position)
		else:
			GameActions.skip_unit(state, unit.id)
		return
	if unit.hp < Combat.max_hp() and home != null and unit.position == home.position:
		GameActions.skip_unit(state, unit.id)
		return
	var camp := _known_camp(state)
	if camp != null:
		GameActions.move_unit(state, unit.id, camp.position)
		return
	if unit.has_goal():
		return
	var target := _nearest_unexplored(state, unit)
	if target != Vector2i(-1, -1):
		GameActions.move_unit(state, unit.id, target)
	elif unit.needs_orders():
		GameActions.skip_unit(state, unit.id)


## The nearest reachable unexplored land tile within camp range of an own
## city (barbarian camps appear there), or (-1, -1). The script peeks at the
## real terrain so it skips land across water.
func _nearest_unexplored(state: GameState, unit: UnitState) -> Vector2i:
	var from := unit.position
	var tries := 0
	for radius in range(2, 40):
		for cell in IsoGrid.cells_within(from, radius, state.map.width, state.map.height):
			if IsoGrid.step_distance(from, cell) != radius or state.is_explored(PLAYER, cell):
				continue
			if not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
				continue
			var near_home := _nearest_city(state, cell)
			if near_home == null or IsoGrid.step_distance(near_home.position, cell) > Barbarians.camp_preferred_max_city_distance():
				continue
			if not Pathfinder.find_path(state.map, PackedByteArray(), from, cell, "land").is_empty():
				return cell
			tries += 1
			if tries > 60:
				return Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _nearest_city(state: GameState, cell: Vector2i) -> CityState:
	var best: CityState = null
	for city in state.cities_of(PLAYER):
		if best == null or IsoGrid.step_distance(city.position, cell) < IsoGrid.step_distance(best.position, cell):
			best = city
	return best


# --- Settlers -----------------------------------------------------------------

func _move_settler(state: GameState, unit: UnitState) -> void:
	var target: Vector2i = _settler_targets.get(unit.id, Vector2i(-1, -1))
	if target == Vector2i(-1, -1) or not _site_open(state, target, unit.id):
		target = _best_site(state, unit)
		if target == Vector2i(-1, -1):
			return
		_settler_targets[unit.id] = target
	if unit.position == target:
		if CityRules.can_found(state, unit) == "":
			GameActions.found_city(state, unit.id)
			_settler_targets.erase(unit.id)
		else:
			_settler_targets.erase(unit.id)
		return
	if unit.moves_left > 0:
		GameActions.move_unit(state, unit.id, target)
		if state.get_unit(unit.id) != null and not unit.has_goal() and unit.position != target:
			_settler_targets.erase(unit.id)  # No route: pick another site next turn.


func _site_open(state: GameState, cell: Vector2i, settler_id: int) -> bool:
	if not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
		return false
	for city in state.cities:
		if IsoGrid.step_distance(city.position, cell) <= CityRules.no_city_within():
			return false
	for id: int in _settler_targets:
		if id != settler_id and IsoGrid.step_distance(_settler_targets[id], cell) <= CityRules.no_city_within():
			return false
	return state.camp_at(cell) == null


func _best_site(state: GameState, unit: UnitState) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1000.0
	for cell in IsoGrid.cells_within(unit.position, SITE_SEARCH_RADIUS, state.map.width, state.map.height):
		if not _site_open(state, cell, unit.id):
			continue
		var score := _site_score(state.map, cell) - 0.8 * IsoGrid.step_distance(unit.position, cell)
		if score > best_score:
			best = cell
			best_score = score
	return best


func _site_score(map: MapState, cell: Vector2i) -> float:
	var score := 0.0
	for c in IsoGrid.cells_within(cell, CityRules.work_radius(), map.width, map.height):
		match map.get_terrain(c):
			"grassland", "plains":
				score += 2.0
			"forest", "hills":
				score += 1.5
			"ocean":
				score += 0.8
	return score
