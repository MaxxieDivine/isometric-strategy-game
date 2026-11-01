class_name TerrainDefs
extends RefCounted
## Read-only terrain definitions loaded from data/terrain.json.
## Pure data: no Nodes, safe to use headless.

const PATH := "res://data/terrain.json"

static var _defs: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		_load()
	return _defs


static func get_def(id: String) -> Dictionary:
	for def in all():
		if def["id"] == id:
			return def
	push_error("Unknown terrain id: %s" % id)
	return {}


static func id_for_symbol(symbol: String) -> String:
	for def in all():
		if def["symbol"] == symbol:
			return def["id"]
	push_error("Unknown terrain symbol: %s" % symbol)
	return ""


static func _load() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("terrain"):
		push_error("Failed to parse %s" % PATH)
		return
	for entry: Variant in parsed["terrain"]:
		_defs.append(entry as Dictionary)
