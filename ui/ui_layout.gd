class_name UiLayout
extends Node
## The one place that decides how the UI is laid out and sized. View state
## only; never game state.
##
## Layout follows available space, not device type: the window size in CSS
## pixels (physical pixels / DisplayServer.screen_get_scale()) decides it.
## If the shorter side is under COMPACT_BELOW the compact layout is used
## (bottom sheets, tabs, chips), unless the player picked Compact or Full.
## Touch-sized targets follow DisplayServer.is_touchscreen_available() (or a
## touch having been seen). Re-evaluated on every resize and rotation.
##
## UI scale: the project stretches a 1152 × 648 canvas to the window, which
## on a phone shrank everything to ~60%. Here the stretch is topped up so one
## UI unit is never smaller than one CSS pixel, times the player's UI size
## (auto: larger on small or touch screens). Font sizes in UI units then map
## to at least that many CSS pixels.
##
## Settings (UI size, Layout) persist through SaveSystem.save_settings.

signal changed

const COMPACT_BELOW := 500.0
const LAYOUT_AUTO := "auto"
const LAYOUT_COMPACT := "compact"
const LAYOUT_FULL := "full"
## UI size when left on auto: small or touch screens get bigger UI.
const AUTO_SCALE := 1.0
const AUTO_SCALE_SMALL := 1.1
const MIN_SCALE := 0.8
const MAX_SCALE := 1.6
## Touch targets, in CSS pixels.
const TOUCH_TARGET_CSS := 48.0
## Body text, in UI units (the smallest size used for reading text).
const BODY_FONT := 15
const SMALL_FONT := 13

## The current decision, readable from any UI script.
static var compact := false
static var touch := false
## UI size multiplier in effect (the setting, or the auto choice).
static var scale := 1.0
## CSS pixels per UI unit.
static var css_per_unit := 1.0
## Window size in CSS pixels.
static var css_size := Vector2.ZERO

## Player settings: ui_scale 0 means auto; layout is auto/compact/full.
var ui_scale_setting := 0.0
var layout_setting := LAYOUT_AUTO
var _applied := {}


func _ready() -> void:
	var settings := SaveSystem.load_settings()
	ui_scale_setting = clampf(float(settings.get("ui_scale", 0.0)), 0.0, MAX_SCALE)
	if ui_scale_setting > 0.0:
		ui_scale_setting = maxf(ui_scale_setting, MIN_SCALE)
	var saved_layout := String(settings.get("layout", LAYOUT_AUTO))
	layout_setting = saved_layout if saved_layout in [LAYOUT_AUTO, LAYOUT_COMPACT, LAYOUT_FULL] else LAYOUT_AUTO
	get_tree().root.size_changed.connect(refresh)
	refresh()


## Touch targets in UI units (0 when not on a touch screen).
static func touch_target() -> float:
	return TOUCH_TARGET_CSS / css_per_unit if touch else 0.0


## A button height that is comfortable here: at least `desktop` units, and a
## full touch target on touch screens.
static func button_height(desktop: float) -> float:
	return maxf(desktop, touch_target())


func set_ui_scale(value: float) -> void:
	ui_scale_setting = 0.0 if value <= 0.0 else clampf(value, MIN_SCALE, MAX_SCALE)
	_save()
	refresh()


func set_layout(value: String) -> void:
	layout_setting = value
	_save()
	refresh()


## The UI size auto would pick right now.
func auto_scale() -> float:
	return AUTO_SCALE_SMALL if (touch or _shorter_css_side() < COMPACT_BELOW) else AUTO_SCALE


## Recomputes the layout and scale; emits `changed` if anything differs.
func refresh() -> void:
	var window := get_tree().root
	var dpr := maxf(1.0, DisplayServer.screen_get_scale())
	css_size = Vector2(window.size) / dpr
	touch = DisplayServer.is_touchscreen_available() or UiText.touch
	compact = is_compact(css_size, layout_setting)
	scale = ui_scale_setting if ui_scale_setting > 0.0 else auto_scale()
	var base := Vector2(window.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		base = Vector2(1152, 648)
	if css_size.x <= 0.0 or css_size.y <= 0.0:
		return
	window.content_scale_factor = scale_factor(css_size, base, scale)
	css_per_unit = units_to_css(css_size, base, scale)
	var now := { "compact": compact, "touch": touch, "scale": scale, "size": css_size }
	if now != _applied:
		_applied = now
		changed.emit()


## Compact layout for this window size (CSS pixels) and Layout setting.
static func is_compact(css: Vector2, layout: String) -> bool:
	match layout:
		LAYOUT_COMPACT:
			return true
		LAYOUT_FULL:
			return false
	return minf(css.x, css.y) < COMPACT_BELOW


## The window's content_scale_factor: Godot draws min(window / base)
## physical pixels per UI unit times this, and we want max(stretch, 1) × ui
## scale CSS pixels per unit (never smaller than a CSS pixel).
static func scale_factor(css: Vector2, base: Vector2, ui_scale: float) -> float:
	var stretch := minf(css.x / base.x, css.y / base.y)
	return maxf(1.0, 1.0 / stretch) * ui_scale


## CSS pixels per UI unit with that factor applied.
static func units_to_css(css: Vector2, base: Vector2, ui_scale: float) -> float:
	return minf(css.x / base.x, css.y / base.y) * scale_factor(css, base, ui_scale)


func _shorter_css_side() -> float:
	return minf(css_size.x, css_size.y)


func _save() -> void:
	SaveSystem.save_settings({ "ui_scale": ui_scale_setting, "layout": layout_setting })
