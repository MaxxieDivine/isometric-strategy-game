extends SceneTree
## Headless tests for the layout decision (UiLayout) and settings saving.
## Run: godot --headless --path . --script res://tests/test_ui_layout.gd

const BASE := Vector2(1152, 648)

var _failures := 0


func _initialize() -> void:
	_test_compact_by_space()
	_test_layout_setting_overrides()
	_test_scale_never_below_css_pixel()
	_test_desktop_scale_unchanged()
	_test_settings_round_trip()
	if _failures == 0:
		print("All UI layout tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _test_compact_by_space() -> void:
	_check(UiLayout.is_compact(Vector2(844, 390), "auto"), "a landscape phone (844 × 390) is compact")
	_check(UiLayout.is_compact(Vector2(740, 360), "auto"), "a small landscape phone (740 × 360) is compact")
	_check(UiLayout.is_compact(Vector2(390, 844), "auto"), "a portrait phone is compact")
	_check(not UiLayout.is_compact(Vector2(1280, 720), "auto"), "a laptop window is full")
	_check(not UiLayout.is_compact(Vector2(1024, 500), "auto"), "a shorter side of exactly 500 is full")
	_check(UiLayout.is_compact(Vector2(1024, 499), "auto"), "under 500 is compact, whatever the device")


func _test_layout_setting_overrides() -> void:
	_check(UiLayout.is_compact(Vector2(1920, 1080), "compact"), "Compact forces the compact layout")
	_check(not UiLayout.is_compact(Vector2(740, 360), "full"), "Full forces the full layout")


func _test_scale_never_below_css_pixel() -> void:
	for css: Vector2 in [Vector2(844, 390), Vector2(740, 360), Vector2(390, 844)]:
		var per_unit := UiLayout.units_to_css(css, BASE, 1.1)
		_check(is_equal_approx(per_unit, 1.1), "%s: one UI unit is 1.1 CSS px at 110%% (got %.3f)" % [css, per_unit])
		_check(UiLayout.BODY_FONT * per_unit >= 16.0, "%s: body text is at least 16 CSS px" % css)
		_check(UiLayout.TOUCH_TARGET_CSS / per_unit * per_unit >= 48.0 - 0.001, "touch targets are 48 CSS px")


func _test_desktop_scale_unchanged() -> void:
	var css := Vector2(1280, 720)
	_check(is_equal_approx(UiLayout.scale_factor(css, BASE, 1.0), 1.0), "a desktop window keeps the plain stretch")
	_check(is_equal_approx(UiLayout.units_to_css(css, BASE, 1.0), 1280.0 / 1152.0), "and draws as large as before")


func _test_settings_round_trip() -> void:
	var dir := ProjectSettings.globalize_path("res://saves/_test_settings")
	DirAccess.make_dir_recursive_absolute(dir)
	_check(SaveSystem.load_settings(dir).is_empty(), "no settings file: empty settings")
	_check(SaveSystem.save_settings({ "ui_scale": 1.25, "layout": "compact" }, dir), "settings save")
	var loaded := SaveSystem.load_settings(dir)
	_check(is_equal_approx(float(loaded.get("ui_scale", 0)), 1.25) and loaded.get("layout") == "compact",
		"settings load back")
	var file := FileAccess.open(dir.path_join(SaveSystem.SETTINGS), FileAccess.WRITE)
	file.store_string("not json {")
	file.close()
	_check(SaveSystem.load_settings(dir).is_empty(), "a broken settings file is ignored")
	DirAccess.remove_absolute(dir.path_join(SaveSystem.SETTINGS))
	DirAccess.remove_absolute(dir)
