extends SceneTree
## Headless tests for SaveSystem: saving and loading through real files,
## continuing a loaded game deterministically, and rejecting broken saves
## without errors.
## Run: godot --headless --path . --script res://tests/test_save_system.gd

const SEED := 12345

var _failures := 0
var _dir := ""


func _initialize() -> void:
	_dir = ProjectSettings.globalize_path("res://saves/_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_round_trip()
	_test_continues_identically()
	_test_missing_save()
	_test_rejects_broken_saves()
	_test_rejects_newer_version()
	_test_overwrite_and_delete()
	_cleanup()
	if _failures == 0:
		print("All save system tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


# --- Helpers ----------------------------------------------------------------

## A real game a few turns in: a city founded and some turns ended.
func _played_game() -> GameState:
	var state := GameSetup.new_game(SEED, 40, 80)
	for unit in state.units_of(0):
		if UnitDefs.can_found_city(unit.type):
			GameActions.found_city(state, unit.id)
			break
	for i in 5:
		GameActions.end_turn(state)
	return state


func _json(state: GameState) -> String:
	return JSON.stringify(state.to_dict())


func _write(file_name: String, text: String) -> void:
	var file := FileAccess.open(_dir.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	for file_name in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


# --- Tests ------------------------------------------------------------------

func _test_round_trip() -> void:
	var state := _played_game()
	_check(SaveSystem.save(state, "round_trip.json", _dir), "save succeeds")
	var loaded := SaveSystem.load_game("round_trip.json", _dir)
	_check(loaded != null, "the save loads")
	if loaded != null:
		_check(_json(loaded) == _json(state), "the loaded game is identical to the saved one")
	var text := FileAccess.get_file_as_string(_dir.path_join("round_trip.json"))
	_check(text.contains("\"version\""), "the save is readable JSON with a version field")


## Loading mid-game and playing on gives exactly the same game as never
## having saved (the RNG state comes along).
func _test_continues_identically() -> void:
	var state := _played_game()
	SaveSystem.save(state, "continue.json", _dir)
	var loaded := SaveSystem.load_game("continue.json", _dir)
	if loaded == null:
		_check(false, "the save loads for continuing")
		return
	for i in 10:
		GameActions.end_turn(state)
		GameActions.end_turn(loaded)
	_check(_json(loaded) == _json(state), "10 more turns after loading match 10 turns without saving")


func _test_missing_save() -> void:
	_check(not SaveSystem.has_save("nothing.json", _dir), "no save reported when there is none")
	_check(SaveSystem.load_game("nothing.json", _dir) == null, "loading a missing save gives null")


func _test_rejects_broken_saves() -> void:
	var good := _json(_played_game())
	var cases := {
		"empty": "",
		"garbage": "this is not json {",
		"truncated": good.substr(0, good.length() / 2),
		"array": "[1, 2, 3]",
		"missing key": JSON.stringify(_without(JSON.parse_string(good), "map")),
		"wrong type": JSON.stringify(_with(JSON.parse_string(good), "players", "nobody")),
		"no players": JSON.stringify(_with(JSON.parse_string(good), "players", [])),
		"no rng": JSON.stringify(_with(JSON.parse_string(good), "rng", {})),
	}
	for label: String in cases:
		_write("broken.json", cases[label])
		_check(SaveSystem.load_game("broken.json", _dir) == null, "a broken save (%s) is ignored" % label)


func _test_rejects_newer_version() -> void:
	var data: Dictionary = _played_game().to_dict()
	data["version"] = GameState.VERSION + 1
	_write("future.json", JSON.stringify(data))
	_check(SaveSystem.load_game("future.json", _dir) == null, "a save from a newer version is ignored")
	data["version"] = GameState.VERSION
	_write("current.json", JSON.stringify(data))
	_check(SaveSystem.load_game("current.json", _dir) != null, "the same save at the current version loads")


func _test_overwrite_and_delete() -> void:
	var first := _played_game()
	var second := _played_game()
	GameActions.end_turn(second)
	SaveSystem.save(first, "slot.json", _dir)
	SaveSystem.save(second, "slot.json", _dir)
	var loaded := SaveSystem.load_game("slot.json", _dir)
	_check(loaded != null and loaded.turn == second.turn, "saving again replaces the old save")
	_check(not FileAccess.file_exists(_dir.path_join("slot.json.tmp")), "no temp file is left behind")
	_check(SaveSystem.has_save("slot.json", _dir), "the save is reported")
	SaveSystem.delete_save("slot.json", _dir)
	_check(not SaveSystem.has_save("slot.json", _dir), "deleting removes the save")


func _without(data: Dictionary, key: String) -> Dictionary:
	data.erase(key)
	return data


func _with(data: Dictionary, key: String, value: Variant) -> Dictionary:
	data[key] = value
	return data
