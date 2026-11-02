class_name TerrainDefs
extends RefCounted
## Read-only terrain definitions loaded from data/terrain.json.
## Pure data: no Nodes, safe to use headless.

const PATH := "res://data/terrain.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "terrain")
		for def in _defs:
			_by_id[def["id"]] = def
	return _defs


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown terrain id: %s" % id)
		return {}
	return _by_id[id]


static func move_cost(id: String) -> int:
	return int(get_def(id).get("move_cost", 1))


static func passable_by_land(id: String) -> bool:
	return bool(get_def(id).get("passable_by_land", true))


static func sight_bonus(id: String) -> int:
	return int(get_def(id).get("sight_bonus", 0))


## Defense bonus for units standing here, in percent (hills +50, forest +25).
static func defense_percent(id: String) -> int:
	return int(get_def(id).get("defense_percent", 0))
