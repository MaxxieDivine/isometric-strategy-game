class_name DataLoader
extends RefCounted
## Reads definition lists from JSON files in data/.


## Returns the array stored under `key` in the JSON file at `path`.
static func load_list(path: String, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has(key):
		push_error("Failed to read '%s' from %s" % [key, path])
		return result
	for entry: Variant in parsed[key]:
		result.append(entry as Dictionary)
	return result
