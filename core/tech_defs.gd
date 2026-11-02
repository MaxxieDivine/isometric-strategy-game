class_name TechDefs
extends RefCounted
## Read-only tech tree loaded from data/techs.json: each tech's tier,
## prerequisites, the items (unit/building ids) it unlocks, and the cost formula.

const PATH := "res://data/techs.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}
## Item id -> id of the tech that unlocks it.
static var _unlocked_by: Dictionary = {}
static var _cost_rule: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		var data := DataLoader.load_dict(PATH)
		_cost_rule = data.get("cost", {})
		for entry: Variant in data.get("techs", []):
			var def: Dictionary = entry
			_defs.append(def)
			_by_id[def["id"]] = def
			for item: Variant in def.get("unlocks", []):
				_unlocked_by[String(item)] = String(def["id"])
	return _defs


static func has(id: String) -> bool:
	all()
	return _by_id.has(id)


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown tech: %s" % id)
		return {}
	return _by_id[id]


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func tier(id: String) -> int:
	return int(get_def(id).get("tier", 1))


static func prerequisites(id: String) -> Array[String]:
	var result: Array[String] = []
	for prereq: Variant in get_def(id).get("prerequisites", []):
		result.append(String(prereq))
	return result


## Unit/building ids this tech unlocks.
static func unlocks(id: String) -> Array[String]:
	var result: Array[String] = []
	for item: Variant in get_def(id).get("unlocks", []):
		result.append(String(item))
	return result


## Techs that list `id` as a prerequisite, in data order.
static func leads_to(id: String) -> Array[String]:
	var result: Array[String] = []
	for def in all():
		if (def.get("prerequisites", []) as Array).has(id):
			result.append(String(def["id"]))
	return result


## The tech needed to build `item_id`, or "" if it needs none.
static func required_for(item_id: String) -> String:
	all()
	return String(_unlocked_by.get(item_id, ""))


## Science cost of `id` for a player who already knows `known_count` techs.
static func cost(id: String, known_count: int) -> int:
	all()
	return (int(_cost_rule.get("base", 10))
		+ int(_cost_rule.get("per_known", 8)) * known_count
		+ int(_cost_rule.get("per_tier", 0)) * (tier(id) - 1))
