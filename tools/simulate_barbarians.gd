extends SceneTree
## Barbarian pressure check: a simple scripted player plays N turns and we
## report barbarian spawns, attacks on cities, defender win rate, and sacks.
##
## The scripted player: founds 3 cities (capital builds settlers), keeps one
## fortified defender in every city, queues a second defender at the front
## of a city's queue when barbarians are spotted near it, otherwise builds
## Granary/Library/City Walls as they unlock, then warriors. It never attacks.
## Research is auto-picked.
##
## Run: godot --headless --path . --script res://tools/simulate_barbarians.gd

const TURNS := 120
const SEEDS: Array[int] = [11, 12, 13, 14, 15, 16, 17, 18]
const MAP_SIZE := Vector2i(40, 80)
const PLAYER := 0
const TARGET_CITIES := 3
## A spotting keeps a city on alert (wanting 2 defenders) for this many turns.
const ALERT_TURNS := 8
const BUILDINGS: Array[String] = ["granary", "library", "city_walls"]


## Pass seeds after `--` to look at specific games: ... --script res://tools/simulate_barbarians.gd -- 12
func _initialize() -> void:
	var seeds := SEEDS.duplicate()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		seeds.clear()
		for arg in args:
			seeds.append(arg.to_int())
	var runs: Array[Dictionary] = []
	for map_seed in seeds:
		runs.append(_simulate(map_seed))
	_print_detail(runs[0])
	print("")
	_print_summary(runs)
	quit()


# --- The scripted player ----------------------------------------------------------

func _simulate(map_seed: int) -> Dictionary:
	var state := GameSetup.new_game(map_seed, MAP_SIZE.x, MAP_SIZE.y)
	var stats := {
		"seed": map_seed, "camps": [], "spawned": [], "spawned_types": {},
		"city_attacks": [], "field_attacks": [], "sacks": [], "disbanded": [],
		"spotted_turns": [], "city_founded": [], "settlers_lost": 0,
	}
	var alert := {}  # city id -> last turn barbarians were spotted near it
	var settler_targets := {}  # unit id -> site
	_record(state, GameActions.found_city(state, state.units_of(PLAYER)[0].id), stats, alert)
	for i in TURNS:
		_play_turn(state, alert, settler_targets, stats)
		_record(state, GameActions.end_turn(state), stats, alert)
	stats["final_cities"] = state.cities_of(PLAYER).size()
	stats["final_sizes"] = state.cities_of(PLAYER).map(func(c: CityState) -> int: return c.size)
	stats["barbarians_alive"] = Barbarians.barbarian_units(state).size()
	stats["camps_alive"] = state.camps.size()
	return stats


func _play_turn(state: GameState, alert: Dictionary, settler_targets: Dictionary, stats: Dictionary) -> void:
	# Settlers: walk to a site and found there.
	for unit in state.units_of(PLAYER):
		if not UnitDefs.can_found_city(unit.type) or unit.has_goal():
			continue
		var site: Vector2i = settler_targets.get(unit.id, Vector2i(-1, -1))
		if site == unit.position and CityRules.can_found(state, unit) == "":
			_record(state, GameActions.found_city(state, unit.id), stats, alert)
			continue
		site = _pick_site(state, unit)
		settler_targets[unit.id] = site
		if site != Vector2i(-1, -1):
			GameActions.move_unit(state, unit.id, site)
	# Cities: defenders first, then settlers (capital), then buildings, then warriors.
	var cities := state.cities_of(PLAYER)
	var settlers_alive := 0
	for unit in state.units_of(PLAYER):
		if UnitDefs.can_found_city(unit.type):
			settlers_alive += 1
	for city in cities:
		var defenders := _defenders(state, city).size()
		var queued := 0
		var settlers_queued := 0
		for id in city.queue:
			if _is_defender_type(id):
				queued += 1
			elif id == "settler":
				settlers_queued += 1
		var wanted := 2 if state.turn - int(alert.get(city.id, -100)) <= ALERT_TURNS else 1
		if defenders + queued < wanted:
			_queue_front(state, city, _best_defender_type(state, city))
		elif city.queue.is_empty():
			var planned := cities.size() + settlers_alive + settlers_queued
			if city == cities[0] and planned < TARGET_CITIES:
				GameActions.enqueue_build(state, city.id, "settler")
			else:
				var next := _best_defender_type(state, city)
				for building in BUILDINGS:
					if Production.can_enqueue(state, city, building) == "":
						next = building
						break
				GameActions.enqueue_build(state, city.id, next)
	# Every military unit sitting in a city fortifies there.
	for unit in state.units_of(PLAYER):
		if _is_defender_type(unit.type) and not unit.fortified and state.city_at(unit.position) != null:
			GameActions.fortify_unit(state, unit.id)


func _defenders(state: GameState, city: CityState) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in state.units_at(city.position, PLAYER):
		if _is_defender_type(unit.type):
			result.append(unit)
	return result


func _is_defender_type(id: String) -> bool:
	return UnitDefs.has(id) and not UnitDefs.can_found_city(id)


func _best_defender_type(state: GameState, city: CityState) -> String:
	return "archer" if Production.can_enqueue(state, city, "archer") == "" else "warrior"


## Puts `id` at the head of the queue using only player commands.
func _queue_front(state: GameState, city: CityState, id: String) -> void:
	var rest := city.queue.duplicate()
	while not city.queue.is_empty():
		GameActions.remove_from_queue(state, city.id, 0)
	GameActions.enqueue_build(state, city.id, id)
	for item in rest:
		GameActions.enqueue_build(state, city.id, item)


## A legal city site 4–7 tiles from the nearest own city with lots of land.
func _pick_site(state: GameState, settler: UnitState) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1
	for cell in IsoGrid.cells_within(settler.position, 8, state.map.width, state.map.height):
		if not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
			continue
		var nearest := 99
		for city in state.cities:
			nearest = mini(nearest, IsoGrid.step_distance(city.position, cell))
		if nearest <= CityRules.no_city_within() or nearest > 7:
			continue
		if state.camp_at(cell) != null or not state.enemy_units_at(cell, PLAYER).is_empty():
			continue
		var score := 0
		for c in IsoGrid.cells_within(cell, 2, state.map.width, state.map.height):
			if state.map.get_terrain(c) != "ocean":
				score += 1
		score = score * 10 - IsoGrid.step_distance(settler.position, cell)
		if score > best_score:
			best = cell
			best_score = score
	return best


# --- Bookkeeping ----------------------------------------------------------------

func _record(state: GameState, events: Array[Dictionary], stats: Dictionary, alert: Dictionary) -> void:
	for event in events:
		match event["type"]:
			"camp_spawned":
				stats["camps"].append(state.turn)
			"barbarian_spawned":
				stats["spawned"].append(state.turn)
				var type := state.get_unit(event["unit_id"]).type
				stats["spawned_types"][type] = int(stats["spawned_types"].get(type, 0)) + 1
			"barbarians_spotted":
				stats["spotted_turns"].append(state.turn)
				if int(event["city_id"]) != 0:
					alert[int(event["city_id"])] = state.turn
			"combat":
				if state.is_barbarian(int(event["attacker_owner"])):
					var city := state.city_at(event["to"])
					var entry := { "turn": state.turn, "defender_won": event["winner"] == "defender",
						"defender": event["defender_type"], "attacker": event["attacker_type"],
						"city": city.name if city != null else "" }
					if city != null:
						stats["city_attacks"].append(entry)
					else:
						stats["field_attacks"].append(entry)
						if event["defender_type"] == "settler" and event["winner"] == "attacker":
							stats["settlers_lost"] += 1
			"city_sacked":
				stats["sacks"].append({ "turn": state.turn, "city": state.get_city(event["city_id"]).name, "size": event["size"] })
			"unit_disbanded":
				stats["disbanded"].append(state.turn)
			"city_founded":
				stats["city_founded"].append(state.turn)


# --- Report ---------------------------------------------------------------------

func _print_detail(run: Dictionary) -> void:
	print("=== Seed %d, %d turns, scripted player ===" % [run["seed"], TURNS])
	print("  cities founded on turns: %s   (final sizes %s)" % [run["city_founded"], run["final_sizes"]])
	print("  camps appeared on turns: %s   (%d still standing)" % [run["camps"], run["camps_alive"]])
	print("  barbarian units spawned: %d %s   (%d alive at the end)" % [
		run["spawned"].size(), run["spawned_types"], run["barbarians_alive"]])
	print("    by 20-turn block: %s" % [_by_block(run["spawned"])])
	print("  first sighting near the player: turn %s" % (str(run["spotted_turns"][0]) if not run["spotted_turns"].is_empty() else "never"))
	var attacks: Array = run["city_attacks"]
	var held := attacks.filter(func(a: Dictionary) -> bool: return a["defender_won"]).size()
	print("  attacks on city defenders: %d, defenders won %d (%s)" % [attacks.size(), held, _pct(held, attacks.size())])
	for a: Dictionary in attacks:
		print("    turn %3d  %-8s vs %-7s in %-8s %s" % [a["turn"], a["attacker"], a["defender"], a["city"],
			"held" if a["defender_won"] else "DEFENDER LOST"])
	var field: Array = run["field_attacks"]
	print("  attacks on units outside cities: %d (settlers lost: %d)" % [field.size(), run["settlers_lost"]])
	var sacks: Array = run["sacks"]
	print("  cities sacked: %d %s" % [sacks.size(), sacks.map(func(s: Dictionary) -> String: return "%s on turn %d (now size %d)" % [s["city"], s["turn"], s["size"]])])
	print("  units disbanded for upkeep: %d %s" % [run["disbanded"].size(), run["disbanded"]])


func _print_summary(runs: Array[Dictionary]) -> void:
	print("=== Summary over %d seeds (%d turns each) ===" % [runs.size(), TURNS])
	print("  seed | cities | camps | spawned | city attacks | defenders won | sacks (turns)       | disbanded")
	var totals := { "attacks": 0, "held": 0, "sacks": 0, "spawned": 0 }
	for run in runs:
		var attacks: Array = run["city_attacks"]
		var held := attacks.filter(func(a: Dictionary) -> bool: return a["defender_won"]).size()
		var sack_turns: Array = run["sacks"].map(func(s: Dictionary) -> int: return s["turn"])
		print("  %4d | %6d | %5d | %7d | %12d | %13s | %-19s | %d" % [run["seed"], run["final_cities"], run["camps"].size(),
			run["spawned"].size(), attacks.size(), _pct(held, attacks.size()), str(sack_turns), run["disbanded"].size()])
		totals["attacks"] += attacks.size()
		totals["held"] += held
		totals["sacks"] += sack_turns.size()
		totals["spawned"] += run["spawned"].size()
	print("  all seeds: %d barbarians spawned, %d attacks on cities, defenders won %s, %d sacks" % [
		totals["spawned"], totals["attacks"], _pct(totals["held"], totals["attacks"]), totals["sacks"]])


func _by_block(turns: Array) -> Array:
	var blocks := []
	for start in range(1, TURNS + 1, 20):
		blocks.append(turns.filter(func(t: int) -> bool: return t >= start and t < start + 20).size())
	return blocks


func _pct(part: int, whole: int) -> String:
	return "-" if whole == 0 else "%d%%" % roundi(100.0 * part / whole)
