class_name Hud
extends Control
## Turn/year display, End Turn button, key hints, and short toast messages.

signal end_turn_requested

const BUTTON_BG := Color(0.16, 0.14, 0.1, 0.95)
const BUTTON_READY_BG := Color(0.55, 0.38, 0.1, 0.98)

var _turn_label: Label
var _end_turn_button: Button
var _hint_label: Label
var _toast_label: Label
var _toast_tween: Tween
var _pulse_tween: Tween
var _turn_done := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var turn_panel := PanelContainer.new()
	turn_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(turn_panel)
	turn_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	turn_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	turn_panel.add_child(_turn_label)

	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn"
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.custom_minimum_size = Vector2(160, 46)
	_end_turn_button.add_theme_font_size_override("font_size", 18)
	_set_button_bg(BUTTON_BG)
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	add_child(_end_turn_button)
	_end_turn_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_end_turn_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_end_turn_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_end_turn_button.pivot_offset = _end_turn_button.custom_minimum_size / 2.0

	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 4)
	add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 20)
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)
	_toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_WIDTH, 16)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH


func set_turn(turn: int, year_text: String) -> void:
	_turn_label.text = "Turn %d   ·   %s" % [turn, year_text]


func set_hint(text: String) -> void:
	_hint_label.text = text


## Highlights the End Turn button when every unit has finished.
func set_turn_done(done: bool) -> void:
	if done == _turn_done:
		return
	_turn_done = done
	if _pulse_tween != null:
		_pulse_tween.kill()
	_end_turn_button.scale = Vector2.ONE
	_end_turn_button.modulate = Color.WHITE
	if done:
		_end_turn_button.text = "End Turn  ⏎"
		_set_button_bg(BUTTON_READY_BG)
		_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color(1.35, 1.25, 1.0), 0.6)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color.WHITE, 0.6)
	else:
		_end_turn_button.text = "End Turn"
		_set_button_bg(BUTTON_BG)


func toast(text: String) -> void:
	_toast_label.text = text
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.4)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.4)


func _set_button_bg(bg: Color) -> void:
	var normal := UiStyle.button(bg)
	var hover := UiStyle.button(bg.lightened(0.15))
	var pressed := UiStyle.button(bg.darkened(0.2))
	_end_turn_button.add_theme_stylebox_override("normal", normal)
	_end_turn_button.add_theme_stylebox_override("hover", hover)
	_end_turn_button.add_theme_stylebox_override("pressed", pressed)
