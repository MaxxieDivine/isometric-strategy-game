class_name Wonders
extends RefCounted
## Who holds which wonder. GameState.wonders maps a wonder id to
## { "city_id": int, "builder": int, "turn": int }. The owner is whoever holds
## the city now (the builder if the city is gone).


static func is_built(state: GameState, id: String) -> bool:
	return state.wonders.has(id)


static func record(state: GameState, id: String) -> Dictionary:
	return state.wonders.get(id, {})


static func city_of(state: GameState, id: String) -> CityState:
	if not is_built(state, id):
		return null
	return state.get_city(int(record(state, id)["city_id"]))


## Player holding the wonder, or -1 if it isn't built.
static func owner_of(state: GameState, id: String) -> int:
	if not is_built(state, id):
		return -1
	var city := city_of(state, id)
	return city.owner if city != null else int(record(state, id)["builder"])


## Wonder ids the player holds, in data order.
static func wonders_of(state: GameState, player_id: int) -> Array[String]:
	var result: Array[String] = []
	for id in WonderDefs.ids():
		if owner_of(state, id) == player_id:
			result.append(id)
	return result


## Wonder ids in `city`, in data order.
static func in_city(state: GameState, city: CityState) -> Array[String]:
	var result: Array[String] = []
	for id in WonderDefs.ids():
		if is_built(state, id) and int(record(state, id)["city_id"]) == city.id:
			result.append(id)
	return result


## The city of `player_id` that has `id` queued (other than `except`), or null.
static func queued_by(state: GameState, player_id: int, id: String, except: CityState = null) -> CityState:
	for city in state.cities_of(player_id):
		if city != except and city.queue.has(id):
			return city
	return null


## Marks the wonder as built in `city` this turn.
static func complete(state: GameState, city: CityState, id: String) -> void:
	state.wonders[id] = { "city_id": city.id, "builder": city.owner, "turn": state.turn }


## Takes a built wonder out of every queue. Stored production stays in each
## city's box for its next build. Returns wonder_lost (and city_idle) events.
static func drop_taken(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for city in state.cities:
		var lost := false
		for id in city.queue.duplicate():
			if not WonderDefs.has(id) or not is_built(state, id):
				continue
			city.queue.erase(id)
			lost = true
			var winner := city_of(state, id)
			events.append({
				"type": "wonder_lost", "city_id": city.id, "wonder": id,
				"by_player": owner_of(state, id), "by_city_id": winner.id if winner != null else 0,
				"kept": city.production_box,
			})
		if lost and city.queue.is_empty():
			events.append({ "type": "city_idle", "city_id": city.id })
	return events
