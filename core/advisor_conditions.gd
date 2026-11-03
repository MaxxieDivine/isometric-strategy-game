class_name AdvisorConditions
extends RefCounted
## Trigger conditions: [{ "fact": name, "op": "==", "value": ... }], all of
## which must hold. Facts read game state, the triggering event, and the
## advisor's own memory ("memory.<key>"). Read only.
##
## Facts: turn, city_count, unit_count, idle_city_count, research_chosen,
## known_tech_count, event_unit_can_found, memory.<key> (null if unset).
## Ops: ==, !=, <, <=, >, >=.


static func all_hold(conditions: Array, state: GameState, player_id: int, event: Dictionary,
		memory: Dictionary) -> bool:
	for condition: Variant in conditions:
		if not holds(condition, state, player_id, event, memory):
			return false
	return true


static func holds(condition: Dictionary, state: GameState, player_id: int, event: Dictionary,
		memory: Dictionary) -> bool:
	var actual: Variant = fact(String(condition.get("fact", "")), state, player_id, event, memory)
	return compare(actual, String(condition.get("op", "==")), condition.get("value"))


static func fact(name: String, state: GameState, player_id: int, event: Dictionary, memory: Dictionary) -> Variant:
	if name.begins_with("memory."):
		return memory.get(name.trim_prefix("memory."))
	match name:
		"turn":
			return state.turn
		"city_count":
			return state.cities_of(player_id).size()
		"unit_count":
			return state.units_of(player_id).size()
		"idle_city_count":
			return state.idle_cities(player_id).size()
		"research_chosen":
			return Research.current(state, player_id) != ""
		"known_tech_count":
			return Research.known(state, player_id).size()
		"event_unit_can_found":
			var unit := state.get_unit(int(event.get("unit_id", -1)))
			return unit != null and UnitDefs.can_found_city(unit.type)
	push_warning("Unknown advisor fact '%s'" % name)
	return null


## JSON numbers arrive as floats, so numbers compare by value.
static func compare(actual: Variant, op: String, expected: Variant) -> bool:
	var numeric := _is_number(actual) and _is_number(expected)
	var same: bool = typeof(actual) == typeof(expected) and actual == expected
	match op:
		"==":
			return float(actual) == float(expected) if numeric else same
		"!=":
			return float(actual) != float(expected) if numeric else not same
	if not numeric:
		return false
	var a := float(actual)
	var b := float(expected)
	match op:
		"<":
			return a < b
		"<=":
			return a <= b
		">":
			return a > b
		">=":
			return a >= b
	push_warning("Unknown advisor condition op '%s'" % op)
	return false


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
