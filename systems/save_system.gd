class_name SaveSystem
## Reads and writes saves as JSON (GameState.to_dict / from_dict).
##
## Where saves live (see get_save_dir):
## - Editor and debug runs: the project's saves/ folder.
## - Exported desktop builds: a saves/ folder next to the executable.
## - Web builds: browser storage (user://saves). A web page can't write files
##   anywhere else, so this is the one place user:// is used.
##
## Loading never trusts the file: anything missing, malformed, or from a
## newer version comes back as null, and the game starts fresh instead.

const AUTOSAVE := "autosave.json"
const _TEMP_SUFFIX := ".tmp"
## Keys from_dict reads without a fallback; a save missing any is rejected.
const _REQUIRED := {
	"turn": TYPE_FLOAT,
	"map": TYPE_DICTIONARY,
	"players": TYPE_ARRAY,
	"units": TYPE_ARRAY,
	"next_unit_id": TYPE_FLOAT,
	"explored": TYPE_ARRAY,
	"rng": TYPE_DICTIONARY,
}


static func get_save_dir() -> String:
	var dir: String
	if OS.has_feature("web"):
		dir = "user://saves"
	elif OS.has_feature("template"):
		# Exported build: res:// is read-only, so sit next to the executable.
		dir = OS.get_executable_path().get_base_dir().path_join("saves")
	else:
		dir = ProjectSettings.globalize_path("res://saves")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Writes the game to `file_name`. Writes a temp file first and then swaps it
## in, so a crash mid-write can't leave a half-written save behind.
static func save(state: GameState, file_name: String = AUTOSAVE, dir: String = "") -> bool:
	if dir == "":
		dir = get_save_dir()
	var path := dir.path_join(file_name)
	var temp := path + _TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save %s: %s" % [temp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(temp, path) != OK:
		push_warning("Could not move save into place: %s" % path)
		return false
	return true


## The saved game, or null if there is none or it can't be used.
static func load_game(file_name: String = AUTOSAVE, dir: String = "") -> GameState:
	if dir == "":
		dir = get_save_dir()
	var path := dir.path_join(file_name)
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var problem := check(data)
	if problem != "":
		push_warning("Ignoring save %s: %s" % [path, problem])
		return null
	var state := GameState.from_dict(data)
	if state == null or state.map == null or state.players.is_empty() \
			or state.explored.size() != state.players.size():
		push_warning("Ignoring save %s: it didn't load cleanly" % path)
		return null
	return state


static func has_save(file_name: String = AUTOSAVE, dir: String = "") -> bool:
	if dir == "":
		dir = get_save_dir()
	return FileAccess.file_exists(dir.path_join(file_name))


static func delete_save(file_name: String = AUTOSAVE, dir: String = "") -> void:
	if dir == "":
		dir = get_save_dir()
	var path := dir.path_join(file_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## "" if `data` (parsed JSON) looks like a save this version can load,
## otherwise what's wrong with it.
static func check(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "not a save file"
	var dict: Dictionary = data
	var version: Variant = dict.get("version", 0)
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		return "bad version"
	if int(version) > GameState.VERSION:
		return "made by a newer version (%d > %d)" % [int(version), GameState.VERSION]
	for key: String in _REQUIRED:
		if not dict.has(key):
			return "missing \"%s\"" % key
		var wanted: int = _REQUIRED[key]
		var actual := typeof(dict[key])
		if actual != wanted and not (wanted == TYPE_FLOAT and actual == TYPE_INT):
			return "\"%s\" has the wrong type" % key
	var rng: Dictionary = dict["rng"]
	if not rng.has("seed") or not rng.has("state"):
		return "missing random state"
	if (dict["players"] as Array).is_empty():
		return "no players"
	return ""
