class_name Effects
extends RefCounted
## The modifier pipeline: buildings in a city plus the wonders that reach it.
## Effect keys (ints):
##   city_food / city_production / city_trade   flat bonus to the city total
##   tile_<yield>:<terrain>                     bonus per worked tile of that terrain
##   science_percent, food_kept_on_growth_percent, defense_percent
## A wonder reaches every city of its owner (scope "civ") or only its own
## city (scope "city").


## Wonder ids whose effects apply to `city`.
static func wonders_affecting(state: GameState, city: CityState) -> Array[String]:
	var result: Array[String] = []
	for id in WonderDefs.ids():
		if not Wonders.is_built(state, id):
			continue
		if WonderDefs.scope(id) == WonderDefs.SCOPE_CIV:
			if Wonders.owner_of(state, id) == city.owner:
				result.append(id)
		elif int(Wonders.record(state, id)["city_id"]) == city.id:
			result.append(id)
	return result


## Sum of one effect over the city's buildings and the wonders reaching it.
static func city_effect(state: GameState, city: CityState, key: String) -> int:
	var total := BuildingDefs.effect(city, key)
	for id in wonders_affecting(state, city):
		total += int(WonderDefs.effects(id).get(key, 0))
	return total


## Buildings the city has or counts as having against `attacker_owner`
## (e.g. City Walls from the Great Wall against barbarians). No duplicates.
static func effective_buildings(state: GameState, city: CityState, attacker_owner: int) -> Array[String]:
	var result: Array[String] = city.buildings.duplicate()
	for id in wonders_affecting(state, city):
		var grant := WonderDefs.counts_as(id)
		if grant.is_empty() or not _applies_against(state, String(grant.get("against", "")), attacker_owner):
			continue
		var building := String(grant.get("building", ""))
		if building != "" and not result.has(building):
			result.append(building)
	return result


## Defense bonus (percent) of `city` against a land attack by `attacker_owner`.
static func defense_percent(state: GameState, city: CityState, attacker_owner: int) -> int:
	var total := 0
	for id in effective_buildings(state, city, attacker_owner):
		if BuildingDefs.has(id):
			total += int((BuildingDefs.get_def(id).get("effects", {}) as Dictionary).get("defense_percent", 0))
	for id in wonders_affecting(state, city):
		total += int(WonderDefs.effects(id).get("defense_percent", 0))
	return total


static func _applies_against(state: GameState, against: String, attacker_owner: int) -> bool:
	match against:
		"", "all":
			return true
		"barbarians":
			return state.is_barbarian(attacker_owner)
	return false
