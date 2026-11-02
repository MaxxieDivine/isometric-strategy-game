class_name Chronicle
extends RefCounted
## Key moments for the end screen, kept as plain entries in
## GameState.chronicle: { turn, player, type, name, city } with names captured
## when it happens. Types: city_founded (name = city), tech_discovered (tech),
## camp_destroyed (city = nearest own city), wonder_built (wonder, city),
## game_over (name = reason).


static func record(state: GameState, events: Array[Dictionary]) -> void:
	for event in events:
		match event["type"]:
			"city_founded":
				var city := state.get_city(int(event["city_id"]))
				if city != null:
					_add(state, city.owner, "city_founded", city.name, city.name)
			"tech_discovered":
				_add(state, int(event["player"]), "tech_discovered", TechDefs.display_name(event["tech"]), "")
			"camp_destroyed":
				var player := int(event["player"])
				_add(state, player, "camp_destroyed", "Barbarian camp", _nearest_city_name(state, player, event["cell"]))
			"wonder_built":
				var city := state.get_city(int(event["city_id"]))
				_add(state, int(event["player"]), "wonder_built", WonderDefs.display_name(event["wonder"]),
					city.name if city != null else "")
			"game_over":
				_add(state, int(event["winner"]), "game_over", String(event["reason"]), "")


## Entries of one player (or everyone with player < 0), oldest first.
static func entries(state: GameState, player_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in state.chronicle:
		if player_id < 0 or int(entry["player"]) == player_id:
			result.append(entry)
	return result


static func _add(state: GameState, player_id: int, type: String, entry_name: String, city_name: String) -> void:
	state.chronicle.append({ "turn": state.turn, "player": player_id, "type": type, "name": entry_name, "city": city_name })


static func _nearest_city_name(state: GameState, player_id: int, cell: Vector2i) -> String:
	var best: CityState = null
	for city in state.cities_of(player_id):
		if best == null or IsoGrid.step_distance(city.position, cell) < IsoGrid.step_distance(best.position, cell):
			best = city
	return best.name if best != null else ""
