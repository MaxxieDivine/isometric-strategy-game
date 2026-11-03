class_name UnitDefs
extends RefCounted
## Read-only unit type definitions loaded from data/units.json.

const PATH := "res://data/units.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "units")
		for def in _defs:
			_by_id[def["id"]] = def
	return _defs


static func has(id: String) -> bool:
	all()
	return _by_id.has(id)


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown unit type: %s" % id)
		return {}
	return _by_id[id]


static func max_moves(id: String) -> int:
	return int(get_def(id).get("moves", 1))


static func can_found_city(id: String) -> bool:
	return bool(get_def(id).get("can_found_city", false))


static func domain(id: String) -> String:
	return String(get_def(id).get("domain", "land"))


## How far the unit sees on flat ground (default 1; terrain may add to it).
static func sight(id: String) -> int:
	return int(get_def(id).get("sight", 1))


## Every passable land tile costs this unit 1 move (scouts ignore hills and forest).
static func ignores_terrain(id: String) -> bool:
	return bool(get_def(id).get("ignores_terrain", false))
