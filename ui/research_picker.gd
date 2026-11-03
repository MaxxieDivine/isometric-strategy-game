class_name ResearchPicker
extends PanelContainer
## Small, non-blocking card listing the techs the player can research, each
## with a turn estimate (science icon + turns) and what it unlocks. The map
## stays usable while open.
##
## Full layout: a card at the bottom left. Compact layout: a bottom sheet
## with two columns; drag its grip down to close it.

signal tech_chosen(tech_id: String)
## The player closed the card (✕, Esc or a drag down) without picking.
signal dismissed
signal tech_tree_requested

const OPTION_BG := Color(0.12, 0.14, 0.2, 0.95)
const CURRENT_BG := Color(0.42, 0.3, 0.1, 0.98)
const MUTED := Color(0.62, 0.65, 0.72)
## Room left below the card for the key-hint line.
const BOTTOM_CLEARANCE := 40
const CARD_WIDTH := 300.0
## A compact sheet never covers more of the screen than this.
const SHEET_MAX := 0.8

var _compact := false
var _handle: SheetHandle
var _title: Label
var _subtitle: Label
var _tree_button: Button
var _close: Button
var _scroll: ScrollContainer
var _options: GridContainer
var _drag := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_handle = SheetHandle.new()
	_handle.dragged.connect(func(delta_y: float) -> void:
		_drag = maxf(0.0, _drag + delta_y)
		position.y = get_viewport_rect().size.y - size.y + _drag)
	_handle.released.connect(func() -> void:
		if _drag > size.y * 0.3:
			dismissed.emit()
		_drag = 0.0
		if visible:
			_place())
	box.add_child(_handle)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_tree_button = Button.new()
	_tree_button.text = "Tech tree"
	_tree_button.focus_mode = Control.FOCUS_NONE
	_tree_button.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	_tree_button.add_theme_stylebox_override("normal", UiStyle.button(OPTION_BG))
	_tree_button.add_theme_stylebox_override("hover", UiStyle.button(OPTION_BG.lightened(0.15)))
	_tree_button.add_theme_stylebox_override("pressed", UiStyle.button(OPTION_BG))
	_tree_button.pressed.connect(func() -> void: tech_tree_requested.emit())
	header.add_child(_tree_button)
	_close = Button.new()
	_close.text = "✕"
	_close.flat = true
	_close.focus_mode = Control.FOCUS_NONE
	_close.tooltip_text = "Close (the cheapest tech is picked if you haven't chosen)"
	_close.pressed.connect(func() -> void: dismissed.emit())
	header.add_child(_close)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", UiLayout.SMALL_FONT)
	_subtitle.add_theme_color_override("font_color", MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_subtitle)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_options = GridContainer.new()
	_options.columns = 1
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.add_theme_constant_override("h_separation", 4)
	_options.add_theme_constant_override("v_separation", 4)
	_scroll.add_child(_options)
	set_compact(false)
	hide()


func set_compact(compact: bool) -> void:
	_compact = compact
	_handle.visible = compact
	_tree_button.visible = compact
	_options.columns = 2 if compact else 1
	add_theme_stylebox_override("panel", UiStyle.sheet() if compact else UiStyle.panel())
	_close.custom_minimum_size = Vector2.ONE * UiLayout.touch_target()
	_tree_button.custom_minimum_size = Vector2(0, UiLayout.touch_target())
	if visible:
		_place()


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
		_options.add_child(_option(option, String(option["id"]) == info["current"]))
	var was_visible := visible
	show()
	_place()
	if not was_visible:
		# Slide in; quick so it never holds up the turn.
		var axis := "position:y" if _compact else "position:x"
		var rest: float = position.y if _compact else position.x
		if _compact:
			position.y = rest + 40
		else:
			position.x = rest - 40
		modulate.a = 0.0
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, axis, rest, 0.18)
		tween.tween_property(self, "modulate:a", 1.0, 0.12)


## A tech: its name with a science icon and turns, then what it unlocks.
func _option(option: Dictionary, current: bool) -> CardButton:
	var id: String = option["id"]
	var turns: int = option["turns"]
	var button := CardButton.make(CURRENT_BG if current else OPTION_BG, UiLayout.button_height(0.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s: %s" % [option["name"], "%d turns" % turns if turns > 0 else "no science yet"]
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	button.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	box.add_child(row)
	var name_label := _label(row, UiLayout.BODY_FONT + 1, Color.WHITE)
	name_label.text = option["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(StatIcon.make("science", UiLayout.BODY_FONT + 2))
	_label(row, UiLayout.BODY_FONT, Color.WHITE).text = "%dt" % turns if turns > 0 else "–"
	var unlocks := _label(box, UiLayout.BODY_FONT if _compact else UiLayout.SMALL_FONT + 1, MUTED)
	unlocks.text = option["unlocks"]
	unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Wrap at the width the option will really have, so its height is right.
	var width := (get_viewport_rect().size.x - 40.0) / 2.0 - 20.0 if _compact else CARD_WIDTH - 44.0
	unlocks.custom_minimum_size = Vector2(width, 0)
	button.pressed.connect(func() -> void: tech_chosen.emit(id))
	return button


## Full: bottom-left, above the key hints and clear of the unit panel at the
## top. Compact: a bottom sheet, as tall as its list needs.
func _place() -> void:
	var view := get_viewport_rect().size
	_drag = 0.0
	if _compact:
		custom_minimum_size = Vector2.ZERO
		var list := _options.get_combined_minimum_size().y
		var chrome := get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
		_scroll.custom_minimum_size = Vector2(0, minf(list, view.y * SHEET_MAX - chrome))
		SheetHandle.place(self, minf(chrome + list, view.y * SHEET_MAX))
		return
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var list_height := _options.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, minf(list_height, view.y - 220.0))
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top -= BOTTOM_CLEARANCE
	offset_bottom -= BOTTOM_CLEARANCE


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
