class_name BuildingDefs
extends RefCounted
## Read-only building definitions loaded from data/buildings.json.
## Each building carries `effects`: { effect_key: int } permanent modifiers.

const PATH := "res://data/buildings.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "buildings")
		for def in _defs:
			_by_id[def["id"]] = def
	return _defs


static func has(id: String) -> bool:
	all()
	return _by_id.has(id)


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown building: %s" % id)
		return {}
	return _by_id[id]


## Sum of one effect over every building in the city (0 if none provide it).
static func effect(city: CityState, key: String) -> int:
	var total := 0
	for id in city.buildings:
		if has(id):
			total += int((get_def(id).get("effects", {}) as Dictionary).get(key, 0))
	return total
