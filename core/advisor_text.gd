class_name AdvisorText
extends RefCounted
## Fills {placeholders} in advisor lines, e.g. "{city_name} has finished {item}".

static var _pattern: RegEx


## `template` with every {key} found in `values` replaced. Unknown keys stay.
static func fill(template: String, values: Dictionary) -> String:
	var result := template
	for key in placeholders(template):
		if values.has(key):
			result = result.replace("{%s}" % key, str(values[key]))
	return result


## True if every placeholder in `template` has a value.
static func can_fill(template: String, values: Dictionary) -> bool:
	for key in placeholders(template):
		if not values.has(key):
			return false
	return true


## The placeholder names in `template`, in order (repeats included).
static func placeholders(template: String) -> Array[String]:
	if _pattern == null:
		_pattern = RegEx.create_from_string("\\{([a-z_]+)\\}")
	var result: Array[String] = []
	for found in _pattern.search_all(template):
		result.append(found.get_string(1))
	return result
