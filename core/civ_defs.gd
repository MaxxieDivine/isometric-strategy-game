class_name CivDefs
extends RefCounted
## Read-only civilization definitions loaded from data/civs.json:
## unit color and border color per civ.

const PATH := "res://data/civs.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "civs")
		for def in _defs:
			_by_id[def["id"]] = def
	return _defs


static func has(id: String) -> bool:
	all()
	return _by_id.has(id)


static func get_def(id: String) -> Dictionary:
	all()
	if not _by_id.has(id):
		push_error("Unknown civ: %s" % id)
		return {}
	return _by_id[id]
