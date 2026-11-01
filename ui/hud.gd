class_name Hud
extends Control
## Turn/year display, End Turn and Found City buttons, key hints, a
## notification card for batched turn news, and the idle-city prompt.

signal end_turn_requested
signal found_city_requested
signal end_turn_confirmed
signal idle_city_jump_requested(city_id: int)

const BUTTON_BG := Color(0.16, 0.14, 0.1, 0.95)
const BUTTON_READY_BG := Color(0.55, 0.38, 0.1, 0.98)
const NOTICE_BASE_TIME := 1.6
const NOTICE_TIME_PER_LINE := 0.8

var _turn_label: Label
var _end_turn_button: Button
var _found_city_button: Button
var _hint_label: Label
var _notice: PanelContainer
var _notice_title: Label
var _notice_lines: Label
var _notice_tween: Tween
var _pulse_tween: Tween
var _turn_done := false
var _idle_prompt: PanelContainer
var _idle_label: Label
var _idle_jump_button: Button
var _idle_city_id := -1


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

	_end_turn_button = _make_button("End Turn", 0)
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	_found_city_button = _make_button("Found City  (B)", 1)
	_found_city_button.pressed.connect(func() -> void: found_city_requested.emit())
	_found_city_button.hide()

	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 4)
	add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_build_notice()
	_build_idle_prompt()


## A bottom-right button; `slot` 0 is the bottom one, higher slots stack upward.
func _make_button(text: String, slot: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(170, 46)
	button.add_theme_font_size_override("font_size", 18)
	_set_button_bg(button, BUTTON_BG)
	add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_top -= slot * 56
	button.offset_bottom -= slot * 56
	button.pivot_offset = button.custom_minimum_size / 2.0
	return button


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", UiStyle.panel())
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.modulate.a = 0.0
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_notice.add_child(box)
	_notice_title = Label.new()
	_notice_title.add_theme_font_size_override("font_size", 18)
	_notice_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_notice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_title)
	_notice_lines = Label.new()
	_notice_lines.add_theme_font_size_override("font_size", 15)
	_notice_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_lines)


## A small card above the buttons: "Rome has nothing to build" with
## [Go to Rome] and [End Turn anyway]. Not modal; the map stays usable.
func _build_idle_prompt() -> void:
	_idle_prompt = PanelContainer.new()
	_idle_prompt.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(_idle_prompt)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_idle_prompt.add_child(box)
	_idle_label = Label.new()
	_idle_label.add_theme_font_size_override("font_size", 16)
	_idle_label.add_theme_color_override("font_color", UiStyle.GOLD)
	box.add_child(_idle_label)
	var hint := Label.new()
	hint.text = "End Turn again to skip"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_idle_jump_button = Button.new()
	_idle_jump_button.focus_mode = Control.FOCUS_NONE
	_idle_jump_button.pressed.connect(func() -> void: idle_city_jump_requested.emit(_idle_city_id))
	row.add_child(_idle_jump_button)
	var anyway := Button.new()
	anyway.text = "End Turn anyway"
	anyway.focus_mode = Control.FOCUS_NONE
	anyway.pressed.connect(func() -> void: end_turn_confirmed.emit())
	row.add_child(anyway)
	for button: Button in [_idle_jump_button, anyway]:
		_set_button_bg(button, BUTTON_BG)
	_idle_prompt.hide()


func show_idle_prompt(city_id: int, city_name: String, other_idle: int) -> void:
	_idle_city_id = city_id
	_idle_label.text = "%s has nothing to build" % city_name
	if other_idle > 0:
		_idle_label.text += "  (+%d more)" % other_idle
	_idle_jump_button.text = "Go to %s" % city_name
	_idle_prompt.show()
	_idle_prompt.reset_size()
	_idle_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_idle_prompt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_idle_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Sit above the two button slots.
	_idle_prompt.offset_top -= 2 * 56
	_idle_prompt.offset_bottom -= 2 * 56
	_idle_prompt.pivot_offset = _idle_prompt.size / 2.0
	_idle_prompt.scale = Vector2.ONE * 0.85
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) 		.tween_property(_idle_prompt, "scale", Vector2.ONE, 0.15)


func hide_idle_prompt() -> void:
	_idle_prompt.hide()
	_idle_city_id = -1


func is_idle_prompt_visible() -> bool:
	return _idle_prompt.visible


func set_turn(turn: int, year_text: String) -> void:
	_turn_label.text = "Turn %d   ·   %s" % [turn, year_text]


func set_hint(text: String) -> void:
	_hint_label.text = text


func set_found_city_visible(shown: bool) -> void:
	_found_city_button.visible = shown


## Highlights the End Turn button when every unit and city has orders.
func set_turn_done(done: bool) -> void:
	if done == _turn_done:
		return
	_turn_done = done
	if _pulse_tween != null:
		_pulse_tween.kill()
	_end_turn_button.modulate = Color.WHITE
	if done:
		_end_turn_button.text = "End Turn  ⏎"
		_set_button_bg(_end_turn_button, BUTTON_READY_BG)
		_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color(1.35, 1.25, 1.0), 0.6)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color.WHITE, 0.6)
	else:
		_end_turn_button.text = "End Turn"
		_set_button_bg(_end_turn_button, BUTTON_BG)


## Shows one notification card (replacing any current one): a title plus
## optional lines of news. Stays up a little longer the more it says.
func notify(title: String, lines: PackedStringArray = PackedStringArray()) -> void:
	_notice_title.text = title
	_notice_lines.text = "\n".join(lines)
	_notice_lines.visible = not lines.is_empty()
	_notice.reset_size()
	# Re-center after resizing.
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	if _notice_tween != null:
		_notice_tween.kill()
	_notice.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(NOTICE_BASE_TIME + NOTICE_TIME_PER_LINE * lines.size())
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.4)


func _set_button_bg(button: Button, bg: Color) -> void:
	button.add_theme_stylebox_override("normal", UiStyle.button(bg))
	button.add_theme_stylebox_override("hover", UiStyle.button(bg.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", UiStyle.button(bg.darkened(0.2)))
