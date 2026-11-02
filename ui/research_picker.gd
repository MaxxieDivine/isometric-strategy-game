class_name ResearchPicker
extends PanelContainer
## Small, non-blocking card listing the techs the player can research, each
## with a turn estimate and what it unlocks. The map stays usable while open.

signal tech_chosen(tech_id: String)
## The player closed the card (✕ or Esc) without picking.
signal dismissed

const OPTION_BG := Color(0.12, 0.14, 0.2, 0.95)
const CURRENT_BG := Color(0.42, 0.3, 0.1, 0.98)
const MUTED := Color(0.6, 0.62, 0.68)
## Room left below the card for the key-hint line.
const BOTTOM_CLEARANCE := 40

var _title: Label
var _subtitle: Label
var _options: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	custom_minimum_size = Vector2(290, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (the cheapest tech is picked if you haven't chosen)"
	close.pressed.connect(func() -> void: dismissed.emit())
	header.add_child(close)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", MUTED)
	box.add_child(_subtitle)

	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	box.add_child(_options)
	hide()


## `info` keys: title, subtitle, current (tech id or ""), options (Array of
## { id, name, turns, unlocks }) where `turns` is -1 when there's no science.
func open(info: Dictionary) -> void:
	_title.text = info["title"]
	_subtitle.text = info["subtitle"]
	for child in _options.get_children():
		# Detach now so the card can shrink to the new list this frame.
		_options.remove_child(child)
		child.queue_free()
	for option: Dictionary in info["options"]:
		var id: String = option["id"]
		var turns: int = option["turns"]
		var eta := "%d turn%s" % [turns, "" if turns == 1 else "s"] if turns > 0 else "no science yet"
		var button := Button.new()
		button.text = "%s   ·   %s\n%s" % [option["name"], eta, option["unlocks"]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 14)
		var bg := CURRENT_BG if id == info["current"] else OPTION_BG
		for state_name: String in ["normal", "pressed"]:
			button.add_theme_stylebox_override(state_name, _option_style(bg))
		button.add_theme_stylebox_override("hover", _option_style(bg.lightened(0.15)))
		button.pressed.connect(func() -> void: tech_chosen.emit(id))
		_options.add_child(button)
	var was_visible := visible
	show()
	_place()
	if not was_visible:
		# Slide in from the left; quick so it never holds up the turn.
		var rest := position.x
		position.x = rest - 40
		modulate.a = 0.0
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position:x", rest, 0.18)
		tween.tween_property(self, "modulate:a", 1.0, 0.12)


## Bottom-left, above the key hints and clear of the unit/tile panel at the top.
func _place() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top -= BOTTOM_CLEARANCE
	offset_bottom -= BOTTOM_CLEARANCE


func _option_style(bg: Color) -> StyleBoxFlat:
	var style := UiStyle.button(bg)
	style.set_content_margin_all(6)
	style.border_color = UiStyle.GOLD.darkened(0.4)
	return style
