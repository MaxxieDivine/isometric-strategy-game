class_name WonderDefs
extends RefCounted
## Read-only wonder definitions loaded from data/wonders.json. A wonder is a
## building that can exist only once in the world. Each carries:
##   effects:   { effect_key: int } modifiers (see Effects)
##   scope:     "civ" (every city of the owner) or "city" (its own city only)
##   counts_as: optional { building, against } - cities in scope count as
##              having that building against that kind of attacker.

const PATH := "res://data/wonders.json"
const SCOPE_CIV := "civ"
const SCOPE_CITY := "city"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "wonders")
		for def in _defs:
			_by_id[def["id"]] = def
	return _defs


static func ids() -> Array[String]:
	var result: Array[String] = []
	for def in all():
		result.append(String(def["id"]))
	return result


static func has(id: String) -> bool:
	all()
	return _by_id.has(id)


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown wonder: %s" % id)
		return {}
	return _by_id[id]


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func scope(id: String) -> String:
	return String(get_def(id).get("scope", SCOPE_CITY))


static func effects(id: String) -> Dictionary:
	return get_def(id).get("effects", {})


static func counts_as(id: String) -> Dictionary:
	return get_def(id).get("counts_as", {})


static func effect_text(id: String) -> String:
	return String(get_def(id).get("effect_text", ""))
