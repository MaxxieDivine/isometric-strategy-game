class_name CityPanel
extends PanelContainer
## City details: size, food box and growth, production and the build queue,
## unit upkeep, trade, citizens, and buildings.

signal close_requested
signal enqueue_requested(item_id: String)
signal remove_requested(index: int)

const FOOD_COLOR := Color("#7bd04f")
const STARVING_COLOR := Color("#e0584a")
const MUTED := Color(0.75, 0.78, 0.85)
const PRODUCTION_COLOR := Color("#d9813a")
const WARNING_COLOR := Color("#f2b84e")
const SECTION_COLOR := Color(0.6, 0.62, 0.68)
const QUEUE_BG := Color(0.2, 0.17, 0.12, 0.95)
const ITEM_BG := Color(0.12, 0.14, 0.2, 0.95)
const WONDER_BG := Color(0.42, 0.3, 0.08, 0.98)
const WONDER_MARK := "★ "

var _name_label: Label
var _size_label: Label
var _food_bar: ProgressBar
var _food_label: Label
var _production_label: Label
var _build_bar: ProgressBar
var _build_label: Label
var _queue_box: VBoxContainer
var _build_grid: GridContainer
var _buildings_label: Label
var _wonders_label: Label
var _trade_label: Label
var _citizens_label: Label
var _units_label: Label


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

	_food_bar = _add_bar(box, FOOD_COLOR)
	_food_label = _add_label(box, 14, MUTED)

	_production_label = _add_label(box, 15, Color.WHITE)
	_build_bar = _add_bar(box, PRODUCTION_COLOR)
	_build_label = _add_label(box, 14, MUTED)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 2)
	box.add_child(_queue_box)
	_add_label(box, 12, SECTION_COLOR).text = "Add to queue"
	_build_grid = GridContainer.new()
	_build_grid.columns = 2
	_build_grid.add_theme_constant_override("h_separation", 4)
	_build_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_build_grid)

	_units_label = _add_label(box, 15, Color.WHITE)
	_trade_label = _add_label(box, 15, Color.WHITE)
	_citizens_label = _add_label(box, 15, Color.WHITE)
	_buildings_label = _add_label(box, 14, MUTED)
	_buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wonders_label = _add_label(box, 13, MUTED)
	_wonders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var hint := _add_label(box, 12, Color(0.6, 0.62, 0.68))
	hint.text = "Click a tile in the city radius to move a citizen there. Click a worked tile to free it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	hide()


func _add_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.04, 0.06)
	bar_bg.border_color = Color(0.3, 0.3, 0.3)
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = fill_color
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	parent.add_child(bar)
	return bar


func _small_button(text: String, bg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	var normal := UiStyle.button(bg)
	normal.set_content_margin_all(4)
	var hover := UiStyle.button(bg.lightened(0.15))
	hover.set_content_margin_all(4)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	return button


func _add_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


## `info` keys: name, size, food_box, food_box_size, food_surplus, turns_to_grow,
## production (after upkeep), production_box, upkeep, supported, free_units,
## trade, science, science_per_turn, working, idle,
## queue (Array of names), current_cost (0 if nothing queued),
## turns_to_complete, blocked (reason or ""), available (Array of
## { id, name, cost, turns, wonder, tooltip }), buildings (Array of names),
## queue_wonders (Array of bool, parallel to queue), wonders (one-line status
## of every wonder, "" to hide).
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

	var upkeep: int = info["upkeep"]
	_production_label.text = "Production   %s/turn   (%d stored)" % [_signed(info["production"]), info["production_box"]]
	if upkeep > 0:
		_production_label.text = "Production   %s/turn after %d upkeep   (%d stored)" % [
			_signed(info["production"]), upkeep, info["production_box"]]
	var supported: int = info["supported"]
	_units_label.text = "Units   %d supported   ·   %d free" % [supported, info["free_units"]]
	if upkeep > 0:
		_units_label.text += "   ·   upkeep -%d production" % upkeep
	_units_label.add_theme_color_override("font_color", WARNING_COLOR if upkeep > 0 else Color.WHITE)
	_show_queue(info)
	_trade_label.text = "Trade   %s/turn   ·   science %s/turn   (total %d)" % [
		_signed(info["trade"]), _signed(info["science_per_turn"]), info["science"]]
	var buildings: Array = info["buildings"]
	_buildings_label.text = "Buildings   " + (", ".join(PackedStringArray(buildings)) if not buildings.is_empty() else "none yet")
	var wonders := String(info.get("wonders", ""))
	_wonders_label.text = wonders
	_wonders_label.visible = wonders != ""
	var citizens := "Citizens   %d working" % info["working"]
	if int(info["idle"]) > 0:
		citizens += ", %d idle" % info["idle"]
	_citizens_label.text = citizens
	show()


func _show_queue(info: Dictionary) -> void:
	var queue: Array = info["queue"]
	var queue_wonders: Array = info.get("queue_wonders", [])
	var cost: int = info["current_cost"]
	_build_bar.max_value = maxi(1, cost)
	_build_bar.value = mini(int(info["production_box"]), cost) if cost > 0 else 0
	if queue.is_empty():
		_build_label.text = "Nothing queued: pick something to build"
		_build_label.add_theme_color_override("font_color", WARNING_COLOR)
	elif String(info["blocked"]) != "":
		_build_label.text = info["blocked"]
		_build_label.add_theme_color_override("font_color", WARNING_COLOR)
	else:
		var turns: int = info["turns_to_complete"]
		if turns < 0:
			_build_label.text = "%s: no production" % queue[0]
			_build_label.add_theme_color_override("font_color", WARNING_COLOR)
		else:
			_build_label.text = "%s in %d turn%s" % [queue[0], turns, "" if turns == 1 else "s"]
			_build_label.add_theme_color_override("font_color", MUTED)

	for child in _queue_box.get_children():
		child.queue_free()
	for i in queue.size():
		var is_wonder: bool = i < queue_wonders.size() and bool(queue_wonders[i])
		var entry := _small_button("%d. %s%s   ✕" % [i + 1, WONDER_MARK if is_wonder else "", queue[i]],
			WONDER_BG if is_wonder else QUEUE_BG)
		if is_wonder:
			entry.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.tooltip_text = "Remove from queue"
		var index := i
		entry.pressed.connect(func() -> void: remove_requested.emit(index))
		_queue_box.add_child(entry)

	for child in _build_grid.get_children():
		child.queue_free()
	for item: Dictionary in info["available"]:
		var turns: int = item["turns"]
		var eta := "%dt" % turns if turns > 0 else "–"
		var is_wonder := bool(item.get("wonder", false))
		var button := _small_button("%s%s  %d · %s" % [WONDER_MARK if is_wonder else "", item["name"], item["cost"], eta],
			WONDER_BG if is_wonder else ITEM_BG)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Cost %d, %s at the current rate" % [item["cost"], eta]
		if is_wonder:
			button.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
			button.tooltip_text = "Wonder of the World: %s\nOnly one can exist. %s" % [item.get("tooltip", ""), button.tooltip_text]
		var id: String = item["id"]
		button.pressed.connect(func() -> void: enqueue_requested.emit(id))
		_build_grid.add_child(button)


func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
