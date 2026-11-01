class_name DataLoader
extends RefCounted
## Reads definition files from data/.


## Returns the array of objects stored under `key` in the JSON file at `path`.
static func load_list(path: String, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data := load_dict(path)
	if not data.has(key):
		push_error("Missing '%s' in %s" % [key, path])
		return result
	for entry: Variant in data[key]:
		result.append(entry as Dictionary)
	return result


## Returns the top-level JSON object in the file at `path`.
static func load_dict(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Failed to parse %s" % path)
		return {}
	return parsed
