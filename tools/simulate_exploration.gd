extends SceneTree
## How long one scout on auto-explore from turn 1 takes to explore its
## continent. For each seed: a new game, a scout added on the start tile and
## ordered to explore, and the settler founds the capital. When barbarians
## wake the scout it is sent exploring again at once (an impatient player).
## Runs twice: with barbarians, and with them held off as a baseline.
## Columns: the turn every land tile of the continent had been seen, the turn
## explore reported "finished" (its coast fully mapped too), wake-ups, and
## the turn the scout was killed, if it was.
## Run: godot --headless --path . --script res://tools/simulate_exploration.gd

const SEEDS := 20
const FIRST_SEED := 1000
const MAX_TURNS := 150


func _initialize() -> void:
	_run("With barbarians")
	Barbarians.rules()["start_turn"] = 100000
	_run("Barbarians held off")
	quit()


func _run(title: String) -> void:
	print("\n%s" % title)
	print("seed   land  land seen  finished  wakes  killed")
	var land_turns: Array[int] = []
	var finish_turns: Array[int] = []
	var killed := 0
	for i in SEEDS:
		var result := _play(FIRST_SEED + i)
		print("%-6d %-5d %-10s %-9s %-6d %s" % [FIRST_SEED + i, result["land"], _turn(result["land_seen"]),
			_turn(result["finished"]), result["wakes"], _turn(result["killed"])])
		if result["land_seen"] > 0:
			land_turns.append(result["land_seen"])
		if result["finished"] > 0:
			finish_turns.append(result["finished"])
		if result["killed"] > 0:
			killed += 1
	print("Continent's land fully seen: %s" % _summary(land_turns))
	print("Explore finished:            %s" % _summary(finish_turns))
	print("Scouts killed: %d/%d" % [killed, SEEDS])


func _play(map_seed: int) -> Dictionary:
	var state := GameSetup.new_game(map_seed, 40, 80)
	var start := state.units[0].position
	var continent := _continent(state.map, start)
	var scout := state.add_unit("scout", 0, start)
	for unit in state.units_of(0):
		if UnitDefs.can_found_city(unit.type):
			GameActions.found_city(state, unit.id)
	GameActions.explore_unit(state, scout.id)
	var result := { "land": continent.size(), "land_seen": -1, "finished": -1, "wakes": 0, "killed": -1 }
	while state.turn < MAX_TURNS and int(result["finished"]) < 0:
		for event in GameActions.end_turn(state):
			if event["type"] == "explore_stopped" and int(event["unit_id"]) == scout.id:
				if event["reason"] == Exploration.FINISHED:
					result["finished"] = state.turn
				else:
					result["wakes"] = int(result["wakes"]) + 1
		if int(result["land_seen"]) < 0 and _all_seen(state, continent):
			result["land_seen"] = state.turn
		if state.get_unit(scout.id) == null:
			result["killed"] = state.turn
			break
		if int(result["finished"]) < 0 and not scout.exploring:
			GameActions.explore_unit(state, scout.id)
	return result


func _all_seen(state: GameState, cells: Array[Vector2i]) -> bool:
	for cell in cells:
		if not state.is_explored(0, cell):
			return false
	return true


## Land tiles connected to `start` over land (the whole map, ignoring fog).
func _continent(map: MapState, start: Vector2i) -> Array[Vector2i]:
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for other in IsoGrid.neighbors(cell, map.width, map.height):
			if not seen.has(other) and TerrainDefs.passable_by_land(map.get_terrain(other)):
				seen[other] = true
				queue.append(other)
	return queue


func _turn(value: int) -> String:
	return str(value) if value > 0 else "-"


func _summary(turns: Array[int]) -> String:
	if turns.is_empty():
		return "never"
	turns.sort()
	var total := 0
	for t in turns:
		total += t
	return "%d/%d games, median turn %d, mean %.1f, range %d-%d" % [turns.size(), SEEDS, turns[turns.size() / 2],
		float(total) / turns.size(), turns[0], turns.back()]
