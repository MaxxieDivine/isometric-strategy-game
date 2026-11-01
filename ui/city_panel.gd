class_name CityPanel
extends PanelContainer
## City details: size, food box and growth, production, trade, citizens.

signal close_requested

const FOOD_COLOR := Color("#7bd04f")
const STARVING_COLOR := Color("#e0584a")
const MUTED := Color(0.75, 0.78, 0.85)

var _name_label: Label
var _size_label: Label
var _food_bar: ProgressBar
var _food_label: Label
var _production_label: Label
var _trade_label: Label
var _citizens_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	custom_minimum_size = Vector2(310, 0)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", UiStyle.GOLD)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_name_label)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	_size_label = _add_label(box, 16, Color.WHITE)

	_food_bar = ProgressBar.new()
	_food_bar.show_percentage = false
	_food_bar.custom_minimum_size = Vector2(0, 12)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.04, 0.06)
	bar_bg.border_color = Color(0.3, 0.3, 0.3)
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = FOOD_COLOR
	_food_bar.add_theme_stylebox_override("background", bar_bg)
	_food_bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(_food_bar)
	_food_label = _add_label(box, 14, MUTED)

	_production_label = _add_label(box, 15, Color.WHITE)
	_trade_label = _add_label(box, 15, Color.WHITE)
	_citizens_label = _add_label(box, 15, Color.WHITE)

	var hint := _add_label(box, 12, Color(0.6, 0.62, 0.68))
	hint.text = "Click a tile in the city radius to move a citizen there. Click a worked tile to free it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	hide()


func _add_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


## `info` keys: name, size, food_box, food_box_size, food_surplus, turns_to_grow,
## production, production_box, trade, science, working, idle.
func show_city(info: Dictionary) -> void:
	_name_label.text = info["name"]
	_size_label.text = "Size %d" % info["size"]

	var surplus: int = info["food_surplus"]
	_food_bar.max_value = info["food_box_size"]
	_food_bar.value = info["food_box"]
	var food := "Food %d/%d   %s/turn" % [info["food_box"], info["food_box_size"], _signed(surplus)]
	if surplus > 0:
		var turns: int = info["turns_to_grow"]
		food += "   ·   grows in %d turn%s" % [turns, "" if turns == 1 else "s"]
		_food_label.add_theme_color_override("font_color", MUTED)
	elif surplus == 0:
		food += "   ·   not growing"
		_food_label.add_theme_color_override("font_color", MUTED)
	else:
		food += "   ·   starving!"
		_food_label.add_theme_color_override("font_color", STARVING_COLOR)
	_food_label.text = food

	_production_label.text = "Production   %s/turn   (%d stored)" % [_signed(info["production"]), info["production_box"]]
	_trade_label.text = "Trade   %s/turn   (science %d)" % [_signed(info["trade"]), info["science"]]
	var citizens := "Citizens   %d working" % info["working"]
	if int(info["idle"]) > 0:
		citizens += ", %d idle" % info["idle"]
	_citizens_label.text = citizens
	show()


func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
