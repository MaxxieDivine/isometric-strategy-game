extends SceneTree
## Pacing check: plays N turns with one city (no new settlers) and reports the
## turn each tech is discovered. The city builds a Library, then a Granary, as
## soon as they unlock, otherwise warriors. Research is either auto-picked
## (what an idle player gets) or follows a "player-like" order (Writing early).
##
## Run: godot --headless --path . --script res://tools/simulate_research.gd

const TURNS := 60
const SEEDS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
const MAP_SIZE := Vector2i(40, 80)
const PLAYER_ORDER: Array[String] = [
	"alphabet", "writing", "pottery", "bronze_working", "masonry",
	"ceremonial_burial", "horseback_riding", "warrior_code", "currency", "mathematics",
]


func _initialize() -> void:
	print("=== Auto-pick research, seed %d, %d turns, one city ===" % [SEEDS[0], TURNS])
	_print_run(_simulate(SEEDS[0], []), true)
	print("")
	print("=== Writing-first research, seed %d ===" % SEEDS[0])
	_print_run(_simulate(SEEDS[0], PLAYER_ORDER), false)
	print("")
	print("=== Auto-pick over %d seeds: discovery turn of the n-th tech (min / median / max) ===" % SEEDS.size())
	var by_index: Array = []
	for map_seed in SEEDS:
		var run := _simulate(map_seed, [])
		var discoveries: Array = run["discoveries"]
		for i in discoveries.size():
			if by_index.size() <= i:
				by_index.append([])
			by_index[i].append(int(discoveries[i]["turn"]))
	for i in by_index.size():
		var turns: Array = by_index[i]
		turns.sort()
		print("  tech %2d: %3d / %3d / %3d   (reached in %d of %d games)" % [
			i + 1, turns[0], turns[turns.size() / 2], turns[-1], turns.size(), SEEDS.size()])
	quit()


func _simulate(map_seed: int, order: Array[String]) -> Dictionary:
	var state := GameSetup.new_game(map_seed, MAP_SIZE.x, MAP_SIZE.y)
	var settler := state.units[0]
	GameActions.found_city(state, settler.id)
	var city := state.cities[0]
	var discoveries: Array = []
	var samples: Array = []
	for i in TURNS:
		if Research.current(state, 0) == "":
			for tech in order:
				if Research.is_available(state, 0, tech):
					GameActions.set_research(state, 0, tech)
					break
		if city.queue.is_empty():
			GameActions.enqueue_build(state, city.id, _next_build(state, city))
		for event in GameActions.end_turn(state):
			if event["type"] == "tech_discovered":
				discoveries.append({
					"turn": state.turn,
					"tech": event["tech"],
					"size": city.size,
					"science": Research.science_per_turn(state, 0),
				})
		if state.turn % 10 == 1:
			samples.append("turn %d: size %d, %d science/turn, %s" % [
				state.turn, city.size, Research.science_per_turn(state, 0), ", ".join(city.buildings)])
	return { "discoveries": discoveries, "samples": samples, "city": city, "state": state }


func _next_build(state: GameState, city: CityState) -> String:
	for id in ["library", "granary"]:
		if Production.can_enqueue(state, city, id) == "":
			return id
	return "warrior"


func _print_run(run: Dictionary, show_samples: bool) -> void:
	var previous := 1
	for entry: Dictionary in run["discoveries"]:
		print("  turn %3d  (+%2d)  %-18s city size %d, %d science/turn" % [
			entry["turn"], int(entry["turn"]) - previous, TechDefs.display_name(entry["tech"]), entry["size"], entry["science"]])
		previous = entry["turn"]
	var state: GameState = run["state"]
	var known := Research.known(state, 0).size()
	print("  %d of %d techs by turn %d; %d science stored toward %s" % [
		known, TechDefs.all().size(), state.turn, Research.stored(state, 0),
		TechDefs.display_name(Research.current(state, 0)) if Research.current(state, 0) != "" else "nothing"])
	if show_samples:
		for line: String in run["samples"]:
			print("    " + line)
