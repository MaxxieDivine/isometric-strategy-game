class_name Research
extends RefCounted
## Research rules. Each city's science (trade, boosted by a Library) is banked
## in the player's `science` store; the store pays for the current research.
## Science banked before anything is chosen counts toward the first tech, and
## leftover science after a discovery carries over.
##
## Player fields used (see GameState.add_player):
##   science: int        stored science
##   known_techs: Array  ids of discovered techs, in discovery order
##   research: String    id of the tech being researched, "" for none


static func known(state: GameState, player_id: int) -> Array:
	return state.players[player_id]["known_techs"]


static func knows(state: GameState, player_id: int, tech_id: String) -> bool:
	return known(state, player_id).has(tech_id)


static func current(state: GameState, player_id: int) -> String:
	return String(state.players[player_id]["research"])


static func stored(state: GameState, player_id: int) -> int:
	return int(state.players[player_id]["science"])


## True if `item_id` needs no tech, or the player knows the tech it needs.
static func has_unlocked(state: GameState, player_id: int, item_id: String) -> bool:
	var tech := TechDefs.required_for(item_id)
	return tech == "" or knows(state, player_id, tech)


## Not yet known, with every prerequisite known.
static func is_available(state: GameState, player_id: int, tech_id: String) -> bool:
	if not TechDefs.has(tech_id) or knows(state, player_id, tech_id):
		return false
	for prereq in TechDefs.prerequisites(tech_id):
		if not knows(state, player_id, prereq):
			return false
	return true


## Techs the player can research now, in data order.
static func available(state: GameState, player_id: int) -> Array[String]:
	var result: Array[String] = []
	for def in TechDefs.all():
		var id := String(def["id"])
		if is_available(state, player_id, id):
			result.append(id)
	return result


static func cost(state: GameState, player_id: int, tech_id: String) -> int:
	return TechDefs.cost(tech_id, known(state, player_id).size())


## The player's total science per turn over all their cities.
static func science_per_turn(state: GameState, player_id: int) -> int:
	var total := 0
	for city in state.cities_of(player_id):
		total += CityRules.science(state, city)
	return total


## Turns until `tech_id` would be discovered if researched from now on, or
## -1 if the player makes no science.
static func turns_to(state: GameState, player_id: int, tech_id: String) -> int:
	var needed := cost(state, player_id, tech_id) - stored(state, player_id)
	if needed <= 0:
		return 1
	var per_turn := science_per_turn(state, player_id)
	if per_turn <= 0:
		return -1
	return ceili(float(needed) / per_turn)


## The tech an undecided player gets: cheapest, then lowest tier, then data order.
static func cheapest_available(state: GameState, player_id: int) -> String:
	var best := ""
	for id in available(state, player_id):
		if best == "":
			best = id
			continue
		var c := cost(state, player_id, id)
		var best_cost := cost(state, player_id, best)
		if c < best_cost or (c == best_cost and TechDefs.tier(id) < TechDefs.tier(best)):
			best = id
	return best


## Empty string if the player may research `tech_id`, else the reason not.
## Switching keeps the stored science.
static func can_research(state: GameState, player_id: int, tech_id: String) -> String:
	if not TechDefs.has(tech_id):
		return "Unknown tech"
	if knows(state, player_id, tech_id):
		return "%s is already known" % TechDefs.display_name(tech_id)
	if not is_available(state, player_id, tech_id):
		return "%s needs %s first" % [TechDefs.display_name(tech_id), _missing_names(state, player_id, tech_id)]
	return ""


static func set_research(state: GameState, player_id: int, tech_id: String) -> void:
	state.players[player_id]["research"] = tech_id


## Called once per player at the end of turn processing, after cities banked
## their science. Discovers the current tech if the store covers it.
static func process(state: GameState, player_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var tech := current(state, player_id)
	if tech == "":
		return events
	var price := cost(state, player_id, tech)
	if stored(state, player_id) < price:
		return events
	state.players[player_id]["science"] = stored(state, player_id) - price
	known(state, player_id).append(tech)
	state.players[player_id]["research"] = ""
	events.append({ "type": "tech_discovered", "player": player_id, "tech": tech })
	return events


static func _missing_names(state: GameState, player_id: int, tech_id: String) -> String:
	var missing := PackedStringArray()
	for prereq in TechDefs.prerequisites(tech_id):
		if not knows(state, player_id, prereq):
			missing.append(TechDefs.display_name(prereq))
	return " and ".join(missing)
