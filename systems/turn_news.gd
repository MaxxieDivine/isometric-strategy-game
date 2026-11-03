class_name TurnNews
extends RefCounted
## Turns game events into the words on the batched turn card, from one
## player's point of view. Reads state for names only; changes nothing.

## Fights farther than this from every city are reported without a place name.
const NEAR_CITY := 4


## Returns { lines, highlights, warnings: PackedStringArray, jump: Vector2i
## (a place worth looking at, or (-1, -1)), discovered: bool, wonders: Array
## (the viewer's wonder_built events, for the celebration card), game_over: bool }.
static func describe(state: GameState, events: Array[Dictionary], viewer: int) -> Dictionary:
	var lines := PackedStringArray()
	var highlights := PackedStringArray()
	var warnings := PackedStringArray()
	var jump := Vector2i(-1, -1)
	var discovered := false
	var wonders: Array = []
	var game_over := false
	var spotted_places := {}
	for event in events:
		match event["type"]:
			"city_grew":
				lines.append("%s grew to size %d" % [_city_name(state, event["city_id"]), event["size"]])
			"city_shrank":
				lines.append("%s starved down to size %d" % [_city_name(state, event["city_id"]), event["size"]])
			"city_starving":
				lines.append("%s is starving" % _city_name(state, event["city_id"]))
			"city_built":
				lines.append("%s built %s" % [_city_name(state, event["city_id"]), Production.news_name(event["item"])])
			"wonder_built":
				var city_name := _city_name(state, event["city_id"])
				var wonder_name := WonderDefs.display_name(event["wonder"])
				if int(event["player"]) == viewer:
					highlights.append("%s completed the %s!" % [city_name, wonder_name])
					wonders.append(event)
				else:
					lines.append("The %s completed the %s in %s" % [
						_owner_adjective(state, event["player"]), wonder_name, city_name])
			"wonder_lost":
				var city := state.get_city(event["city_id"])
				if city != null and city.owner == viewer:
					var by := "by the %s" % _owner_adjective(state, event["by_player"])
					if int(event["by_player"]) == viewer:
						by = "in %s" % _city_name(state, event["by_city_id"])
					warnings.append("The %s was completed %s: %s keeps its %d stored production" % [
						WonderDefs.display_name(event["wonder"]), by, city.name, event["kept"]])
					if jump == Vector2i(-1, -1):
						jump = city.position
			"turns_remaining":
				var left := int(event["turns"])
				if left == 1:
					warnings.append("Final turn of the age: the game ends when you end this turn")
				else:
					lines.append("%d turns remain in this age" % left)
			"game_over":
				game_over = true
			"city_idle":
				lines.append("%s has nothing to build" % _city_name(state, event["city_id"]))
			"research_set":
				if bool(event["auto"]) and int(event["player"]) == viewer:
					lines.append("Researching %s (auto-picked: cheapest)" % TechDefs.display_name(event["tech"]))
			"tech_discovered":
				if int(event["player"]) == viewer:
					var tech: String = event["tech"]
					highlights.append("Discovered %s!  %s" % [TechDefs.display_name(tech), tech_detail(tech)])
					discovered = true
			"unit_disbanded":
				var city_name := _city_name(state, event["city_id"])
				warnings.append("%s can't pay upkeep: its %s disbanded" % [city_name, _type_name(event["unit_type"])])
			"combat":
				var text := _combat_text(state, event, viewer)
				if text != "":
					if int(event["defender_owner"]) == viewer and event["winner"] == "attacker":
						warnings.append(text)
					else:
						lines.append(text)
			"barbarians_spotted":
				if int(event["player"]) == viewer:
					var place := _place(state, event["cell"], viewer)
					if not spotted_places.has(place):
						spotted_places[place] = true
						warnings.append("Barbarians spotted%s!" % place)
					if jump == Vector2i(-1, -1):
						jump = event["cell"]
			"explore_stopped":
				var explorer := state.get_unit(int(event["unit_id"]))
				if explorer != null and explorer.owner == viewer:
					var who := _type_name(event["unit_type"])
					match String(event["reason"]):
						Exploration.FINISHED:
							lines.append("%s finished exploring" % who)
						Exploration.BARBARIANS:
							lines.append("%s spotted barbarians and is waiting for orders" % who)
						Exploration.HURT:
							lines.append("%s is wounded and stopped exploring" % who)
					if jump == Vector2i(-1, -1):
						jump = event["cell"]
			"camp_discovered":
				if int(event["player"]) == viewer:
					lines.append("Barbarian camp found%s. Clear it out for a reward" % _place(state, event["cell"], viewer))
			"camp_destroyed":
				if int(event["player"]) == viewer:
					var reward := "+%d science" % event["amount"]
					if event["reward"] == "production":
						reward = "+%d production for %s" % [event["amount"], _city_name(state, event["city_id"])]
					highlights.append("Barbarian camp destroyed!  %s" % reward)
			"city_sacked":
				var city := state.get_city(event["city_id"])
				if city != null and city.owner == viewer:
					var loss := "loses its stored production"
					if int(event["production_lost"]) > 0:
						loss = "loses %d stored production" % event["production_lost"]
					warnings.append("Barbarians sacked %s! It is size %d and %s" % [city.name, event["size"], loss])
					jump = city.position
	return { "lines": lines, "highlights": highlights, "warnings": warnings, "jump": jump, "discovered": discovered,
		"wonders": wonders, "game_over": game_over }


static func _combat_text(state: GameState, event: Dictionary, viewer: int) -> String:
	var attacker := _type_name(event["attacker_type"])
	var defender := _type_name(event["defender_type"])
	var odds := "%d%%" % roundi(float(event["odds"]) * 100.0)
	var won: bool = event["winner"] == "attacker"
	if int(event["attacker_owner"]) == viewer:
		var foe := "%s %s" % [_owner_adjective(state, event["defender_owner"]), defender]
		if won:
			return "Your %s defeated the %s (%s odds)" % [attacker, foe, odds]
		return "Your %s fell attacking the %s (%s odds)" % [attacker, foe, odds]
	if int(event["defender_owner"]) == viewer:
		var foe := "%s %s" % [_owner_adjective(state, event["attacker_owner"]), attacker]
		var place := _place(state, event["to"], viewer)
		if won:
			return "Your %s%s was destroyed by a %s" % [defender, place, foe]
		return "Your %s%s held off a %s" % [defender, place, foe]
	return ""


## "Unlocks: Granary", else "Leads to: Writing, Mathematics", to tease what's next.
static func tech_detail(tech_id: String) -> String:
	if not TechDefs.unlocks(tech_id).is_empty():
		return "Unlocks: " + unlock_names(tech_id)
	var next := PackedStringArray()
	for id in TechDefs.leads_to(tech_id):
		next.append(TechDefs.display_name(id))
	if next.is_empty():
		return "No unlocks yet"
	return "Leads to: " + ", ".join(next)


static func unlock_names(tech_id: String) -> String:
	var names := PackedStringArray()
	for id in TechDefs.unlocks(tech_id):
		names.append(Production.display_name(id))
	return ", ".join(names)


## " in Rome", " near Rome", or "" when no city of the viewer is close.
static func _place(state: GameState, cell: Vector2i, viewer: int) -> String:
	var best: CityState = null
	for city in state.cities_of(viewer):
		if best == null or IsoGrid.step_distance(city.position, cell) < IsoGrid.step_distance(best.position, cell):
			best = city
	if best == null:
		return ""
	var distance := IsoGrid.step_distance(best.position, cell)
	if distance == 0:
		return " in %s" % best.name
	if distance <= NEAR_CITY:
		return " near %s" % best.name
	return ""


static func _owner_adjective(state: GameState, owner: int) -> String:
	return "barbarian" if state.is_barbarian(owner) else String(state.players[owner]["name"])


static func _type_name(type: String) -> String:
	return String(UnitDefs.get_def(type).get("name", type))


static func _city_name(state: GameState, city_id: int) -> String:
	var city := state.get_city(city_id)
	return city.name if city != null else "A city"
