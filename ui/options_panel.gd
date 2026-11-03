class_name OptionsPanel
extends PanelContainer
## Player options: UI size, Layout (Auto / Compact / Full), the advisor, and
## the controls. A centered card; the map stays visible behind it.

signal ui_scale_changed(value: float)
signal layout_changed(layout: String)
signal advisor_toggled
signal close_requested

const MUTED := Color(0.62, 0.65, 0.72)
const OFF_BG := Color(0.12, 0.14, 0.2, 0.95)
const ON_BG := Color(0.42, 0.3, 0.1, 0.98)
const LAYOUTS := [["auto", "Auto"], ["compact", "Compact"], ["full", "Full"]]

var _slider: HSlider
var _scale_label: Label
var _auto_scale: Button
var _layout_buttons := {}
var _advisor: Button
var _controls: Label
var _layout_hint: Label
var _close: Button
var _scroll: ScrollContainer
var _content: VBoxContainer
var _dragging := false
var _setting := false


func _ready() -> void:
	var style := UiStyle.panel()
	style.bg_color = Color(UiStyle.PANEL_BG, 1.0)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(360, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := _label(header, 20, UiStyle.GOLD)
	title.text = "Options"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_close = Button.new()
	_close.text = "✕"
	_close.flat = true
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)
	# The rest scrolls when the screen is too short for it.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	box = _content

	_label(box, UiLayout.SMALL_FONT, MUTED).text = "UI size"
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	box.add_child(size_row)
	_slider = HSlider.new()
	_slider.min_value = UiLayout.MIN_SCALE
	_slider.max_value = UiLayout.MAX_SCALE
	_slider.step = 0.05
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	# Apply when the drag ends, so the panel doesn't resize under the finger.
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		ui_scale_changed.emit(_slider.value))
	_slider.value_changed.connect(func(value: float) -> void:
		_scale_label.text = "%d%%" % roundi(value * 100.0)
		if not _dragging and not _setting:
			ui_scale_changed.emit(value))
	size_row.add_child(_slider)
	_scale_label = _label(size_row, UiLayout.BODY_FONT, Color.WHITE)
	_scale_label.custom_minimum_size = Vector2(52, 0)
	_auto_scale = _button("Auto")
	_auto_scale.pressed.connect(func() -> void: ui_scale_changed.emit(0.0))
	size_row.add_child(_auto_scale)

	_label(box, UiLayout.SMALL_FONT, MUTED).text = "Layout"
	var layout_row := HBoxContainer.new()
	layout_row.add_theme_constant_override("separation", 6)
	box.add_child(layout_row)
	for entry: Array in LAYOUTS:
		var button := _button(entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var layout: String = entry[0]
		button.pressed.connect(func() -> void: layout_changed.emit(layout))
		layout_row.add_child(button)
		_layout_buttons[layout] = button
	_layout_hint = _label(box, UiLayout.SMALL_FONT, MUTED)
	_layout_hint.text = "Auto uses the compact layout when the screen is small."
	_layout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_label(box, UiLayout.SMALL_FONT, MUTED).text = "Advisor"
	_advisor = _button("")
	_advisor.pressed.connect(func() -> void: advisor_toggled.emit())
	box.add_child(_advisor)

	_label(box, UiLayout.SMALL_FONT, MUTED).text = "Controls"
	_controls = _label(box, UiLayout.BODY_FONT, Color.WHITE)
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hide()


## `info` keys: ui_scale (setting, 0 = auto), scale (in effect), layout,
## advisor_on, advisor_name, controls (one line per control).
func open(info: Dictionary) -> void:
	_setting = true
	_slider.value = float(info["scale"])
	_setting = false
	_scale_label.text = "%d%%" % roundi(float(info["scale"]) * 100.0)
	var auto := float(info["ui_scale"]) <= 0.0
	_style(_auto_scale, auto)
	_auto_scale.tooltip_text = "Pick a size for this screen" if not auto else "The size is picked for this screen"
	for layout: String in _layout_buttons:
		_style(_layout_buttons[layout], layout == String(info["layout"]))
	var advisor_name := String(info.get("advisor_name", "The advisor"))
	_advisor.text = ("%s speaks up now and then: on" if bool(info["advisor_on"]) else "%s keeps quiet: off") % advisor_name
	_style(_advisor, bool(info["advisor_on"]))
	_controls.text = String(info["controls"])
	var target := UiLayout.button_height(34.0)
	for button: Button in [_auto_scale, _advisor] + _layout_buttons.values():
		button.custom_minimum_size.y = target
	_close.custom_minimum_size = Vector2.ONE * UiLayout.touch_target()
	_slider.custom_minimum_size = Vector2(0, UiLayout.touch_target())
	var view := get_viewport_rect().size
	custom_minimum_size = Vector2(minf(420.0, view.x - 24.0), 0)
	# Wrapped labels measure their height at their current width: set it first.
	for label: Label in [_controls, _layout_hint]:
		label.custom_minimum_size = Vector2(custom_minimum_size.x - 40.0, 0)
		label.size = Vector2(custom_minimum_size.x - 40.0, 0)
	show()
	var chrome := get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, minf(_content.get_combined_minimum_size().y, view.y - 16.0 - chrome))
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func _style(button: Button, on: bool) -> void:
	var bg := ON_BG if on else OFF_BG
	button.add_theme_stylebox_override("normal", UiStyle.button(bg))
	button.add_theme_stylebox_override("hover", UiStyle.button(bg.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", UiStyle.button(bg))
	button.add_theme_color_override("font_color", UiStyle.GOLD if on else Color.WHITE)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	_style(button, false)
	return button


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
