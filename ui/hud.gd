class_name Hud
extends Control
## Turn/year display, End Turn and Found City buttons, key hints, and a
## notification card for batched turn news.

signal end_turn_requested
signal found_city_requested

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


func set_turn(turn: int, year_text: String) -> void:
	_turn_label.text = "Turn %d   ·   %s" % [turn, year_text]


func set_hint(text: String) -> void:
	_hint_label.text = text


func set_found_city_visible(shown: bool) -> void:
	_found_city_button.visible = shown


## Highlights the End Turn button when every unit has finished.
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
