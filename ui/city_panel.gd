class_name CityPanel
extends PanelContainer
## City details in three sections: Production (rate, build queue, what to
## add), Citizens (food and growth, workers, trade and science, units) and
## Buildings (buildings and wonders). Stats are icon + number chips; the full
## sentence is on long-press or hover.
##
## Full layout: a side panel with all sections stacked. Compact layout
## (UiLayout.compact): a bottom sheet, half height by default; drag its grip
## up to expand or down to close; tabs pick the section.

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
const TAB_BG := Color(0.12, 0.14, 0.2, 0.95)
const TAB_ON_BG := Color(0.42, 0.3, 0.1, 0.98)
const WONDER_MARK := "★ "
const SIDE_WIDTH := 320.0
## The side panel stays below the top bar and above the End Turn button.
const SIDE_TOP := 76.0
const SIDE_BOTTOM := 70.0
const TAB_NAMES: Array[String] = ["Production", "Citizens", "Buildings"]
## Bottom sheet heights, as fractions of the screen.
const SHEET_HALF := 0.5
const SHEET_FULL := 0.9

var _compact := false
var _tab := 0
var _sheet_fraction := SHEET_HALF
var _info := {}

var _handle: SheetHandle
var _name_label: Label
var _size_label: Label
var _close: Button
var _tabs: HBoxContainer
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _sections: Array[VBoxContainer] = []

var _production_chip: StatChip
var _build_bar: ProgressBar
var _build_name: Label
var _build_turns: StatChip
var _queue_box: VBoxContainer
var _build_grid: GridContainer
var _units_label: Label

var _food_chip: StatChip
var _food_bar: ProgressBar
var _citizens_label: Label
var _trade_chip: StatChip
var _science_chip: StatChip
var _tile_hint: Label

var _buildings_label: Label
var _wonders_box: VBoxContainer


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_handle = SheetHandle.new()
	_handle.dragged.connect(_on_handle_dragged)
	_handle.released.connect(_on_handle_released)
	root.add_child(_handle)

	# Compact: name, tabs and close share one row; full: tabs are hidden.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	_name_label = _label(header, 22, UiStyle.GOLD)
	_size_label = _label(header, UiLayout.BODY_FONT + 1, Color.WHITE)
	_size_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	header.add_child(_tabs)
	_close = Button.new()
	_close.text = "✕"
	_close.flat = true
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(_close)

	for i in TAB_NAMES.size():
		var tab := Button.new()
		tab.text = TAB_NAMES[i]
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
		var index := i
		tab.pressed.connect(func() -> void: show_tab(index))
		_tabs.add_child(tab)
		_tab_buttons.append(tab)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_scroll.add_child(content)
	for i in TAB_NAMES.size():
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 6)
		content.add_child(section)
		_sections.append(section)
	_build_production(_sections[0])
	_build_citizens(_sections[1])
	_build_buildings(_sections[2])
	hide()


## Rate, current build and its turns share the first row.
func _build_production(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_production_chip = StatChip.make("production")
	row.add_child(_production_chip)
	_build_name = _label(row, UiLayout.BODY_FONT, MUTED)
	_build_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_turns = StatChip.make("turns")
	row.add_child(_build_turns)
	_build_bar = _add_bar(box, PRODUCTION_COLOR)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 3)
	box.add_child(_queue_box)
	_label(box, UiLayout.SMALL_FONT, SECTION_COLOR).text = "Add to queue"
	_build_grid = GridContainer.new()
	_build_grid.columns = 2
	_build_grid.add_theme_constant_override("h_separation", 4)
	_build_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_build_grid)
	_units_label = _label(box, UiLayout.BODY_FONT, Color.WHITE)


## Food, trade and science share the first row.
func _build_citizens(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_food_chip = StatChip.make("food")
	row.add_child(_food_chip)
	_trade_chip = StatChip.make("trade")
	row.add_child(_trade_chip)
	_science_chip = StatChip.make("science")
	row.add_child(_science_chip)
	_food_bar = _add_bar(box, FOOD_COLOR)
	_citizens_label = _label(box, UiLayout.BODY_FONT, Color.WHITE)
	_tile_hint = _label(box, UiLayout.SMALL_FONT + 1, SECTION_COLOR)
	_tile_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_buildings(box: VBoxContainer) -> void:
	_label(box, UiLayout.SMALL_FONT, SECTION_COLOR).text = "Buildings"
	_buildings_label = _label(box, UiLayout.BODY_FONT, Color.WHITE)
	_buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(box, UiLayout.SMALL_FONT, SECTION_COLOR).text = "Wonders"
	_wonders_box = VBoxContainer.new()
	_wonders_box.add_theme_constant_override("separation", 2)
	box.add_child(_wonders_box)


# --- Layout -------------------------------------------------------------------

## Switches between the side panel and the bottom sheet.
func set_compact(compact: bool) -> void:
	_compact = compact
	_sheet_fraction = SHEET_HALF
	_close.custom_minimum_size = Vector2.ONE * UiLayout.touch_target()
	for tab in _tab_buttons:
		tab.custom_minimum_size = Vector2(96.0, UiLayout.button_height(32.0))
	add_theme_stylebox_override("panel", UiStyle.sheet() if compact else UiStyle.panel())
	_build_grid.columns = 3 if compact else 2
	if not _info.is_empty():
		_refresh()
	_place()


## Shows one section (compact layout; the full layout shows all of them).
func show_tab(index: int) -> void:
	_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	_apply_tabs()
	_scroll.scroll_vertical = 0


## How much of the screen's height the panel covers from the bottom (0 for
## the side panel), so the camera can keep the city in view above it.
func covered_fraction() -> float:
	return _sheet_fraction if _compact and visible else 0.0


func _apply_tabs() -> void:
	_tabs.visible = _compact
	_handle.visible = _compact
	for i in _sections.size():
		_sections[i].visible = not _compact or i == _tab
		var on := i == _tab
		var bg := TAB_ON_BG if on else TAB_BG
		_tab_buttons[i].add_theme_stylebox_override("normal", UiStyle.button(bg))
		_tab_buttons[i].add_theme_stylebox_override("hover", UiStyle.button(bg.lightened(0.12)))
		_tab_buttons[i].add_theme_stylebox_override("pressed", UiStyle.button(bg))
		_tab_buttons[i].add_theme_color_override("font_color", UiStyle.GOLD if on else MUTED)


func _place() -> void:
	_apply_tabs()
	var view := get_viewport_rect().size
	if _compact:
		custom_minimum_size = Vector2.ZERO
		_scroll.custom_minimum_size = Vector2.ZERO
		SheetHandle.place(self, view.y * _sheet_fraction)
		return
	custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	# Below the top bar and above End Turn; taller content scrolls.
	var content_height := (_scroll.get_child(0) as Control).get_combined_minimum_size().y
	var chrome := get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size = Vector2(0, minf(content_height, view.y - SIDE_TOP - SIDE_BOTTOM - chrome))
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	offset_top = SIDE_TOP
	offset_bottom = SIDE_TOP + size.y
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END


func _on_handle_dragged(delta_y: float) -> void:
	var view := get_viewport_rect().size.y
	_sheet_fraction = clampf(_sheet_fraction - delta_y / view, 0.15, SHEET_FULL)
	SheetHandle.place(self, view * _sheet_fraction)


## Snap: dragged well down closes it, otherwise half or expanded.
func _on_handle_released() -> void:
	if _sheet_fraction < SHEET_HALF * 0.6:
		_sheet_fraction = SHEET_HALF
		close_requested.emit()
		return
	_sheet_fraction = SHEET_FULL if _sheet_fraction > (SHEET_HALF + SHEET_FULL) / 2.0 else SHEET_HALF
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "offset_top", -get_viewport_rect().size.y * _sheet_fraction, 0.15)


# --- Content ----------------------------------------------------------------------

## `info` keys: name, size, food_box, food_box_size, food_surplus,
## turns_to_grow, production (after upkeep), production_box, upkeep,
## supported, free_units, trade, science, science_per_turn, working, idle,
## queue (Array of names), current_cost (0 if nothing queued),
## turns_to_complete, blocked (reason or ""), available (Array of
## { id, name, cost, turns, wonder, tooltip }), buildings (Array of names),
## queue_wonders (Array of bool, parallel to queue), wonder_lines (Array of
## one-line statuses, one per wonder).
func show_city(info: Dictionary) -> void:
	var was_visible := visible
	_info = info
	_refresh()
	show()
	_place()
	if not was_visible and _compact:
		show_tab(_tab)


func _refresh() -> void:
	var info := _info
	_name_label.text = info["name"]
	_size_label.text = "Size %d" % info["size"]
	_refresh_production(info)
	_refresh_citizens(info)
	_refresh_buildings(info)


func _refresh_production(info: Dictionary) -> void:
	var upkeep: int = info["upkeep"]
	var rate := _signed(info["production"])
	var full := "Production %s per turn, %d stored" % [rate, info["production_box"]]
	if upkeep > 0:
		full = "Production %s per turn after paying %d upkeep, %d stored" % [rate, upkeep, info["production_box"]]
	_production_chip.set_value("%s (%d)" % [rate, info["production_box"]], full, "Production")
	_production_chip.set_color(WARNING_COLOR if upkeep > 0 else Color.WHITE)

	var queue: Array = info["queue"]
	var queue_wonders: Array = info.get("queue_wonders", [])
	var cost: int = info["current_cost"]
	_build_bar.max_value = maxi(1, cost)
	_build_bar.value = mini(int(info["production_box"]), cost) if cost > 0 else 0
	_build_turns.visible = false
	_build_name.add_theme_color_override("font_color", WARNING_COLOR)
	if queue.is_empty():
		_build_name.text = "Nothing queued: pick something below"
	elif String(info["blocked"]) != "":
		_build_name.text = info["blocked"]
	else:
		var turns: int = info["turns_to_complete"]
		_build_name.text = queue[0] if turns >= 0 else "%s: no production" % queue[0]
		if turns >= 0:
			_build_name.add_theme_color_override("font_color", Color.WHITE)
			_build_turns.visible = true
			_build_turns.set_value("%dt" % turns, "%s completes in %d turn%s (%d of %d production)" % [
				queue[0], turns, "" if turns == 1 else "s", mini(int(info["production_box"]), cost), cost], queue[0])

	_clear(_queue_box)
	for i in queue.size():
		var is_wonder: bool = i < queue_wonders.size() and bool(queue_wonders[i])
		var entry := _button("%d. %s%s   ✕" % [i + 1, WONDER_MARK if is_wonder else "", queue[i]],
			WONDER_BG if is_wonder else QUEUE_BG)
		if is_wonder:
			entry.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.tooltip_text = "Remove from queue"
		var index := i
		entry.pressed.connect(func() -> void: remove_requested.emit(index))
		_queue_box.add_child(entry)

	_clear(_build_grid)
	for item: Dictionary in info["available"]:
		_build_grid.add_child(_item_button(item))

	var supported: int = info["supported"]
	_units_label.text = "Units %d   ·   %d free" % [supported, info["free_units"]]
	if upkeep > 0:
		_units_label.text += "   ·   upkeep −%d" % upkeep
	_units_label.add_theme_color_override("font_color", WARNING_COLOR if upkeep > 0 else MUTED)


func _refresh_citizens(info: Dictionary) -> void:
	var surplus: int = info["food_surplus"]
	_food_bar.max_value = info["food_box_size"]
	_food_bar.value = info["food_box"]
	var short := "%d/%d (%s)" % [info["food_box"], info["food_box_size"], _signed(surplus)]
	var full := "Food %d/%d, %s per turn" % [info["food_box"], info["food_box_size"], _signed(surplus)]
	if surplus > 0:
		var turns: int = info["turns_to_grow"]
		short += " %dt" % turns
		full += ", grows in %d turn%s" % [turns, "" if turns == 1 else "s"]
		_food_chip.set_color(Color.WHITE)
	elif surplus == 0:
		full += ", not growing"
		_food_chip.set_color(MUTED)
	else:
		short += " !"
		full += ", starving!"
		_food_chip.set_color(STARVING_COLOR)
	_food_chip.set_value(short, full, "Food")
	var citizens := "Citizens: %d working" % info["working"]
	if int(info["idle"]) > 0:
		citizens += ", %d idle" % info["idle"]
	_citizens_label.text = citizens
	_trade_chip.set_value(_signed(info["trade"]), "Trade %s per turn" % _signed(info["trade"]), "Trade")
	_science_chip.set_value("%s (%d)" % [_signed(info["science_per_turn"]), info["science"]],
		"Science %s per turn from this city, %d stored in all" % [_signed(info["science_per_turn"]), info["science"]],
		"Science")
	_tile_hint.text = "{0} a tile near the city to move a citizen there; {1} a worked tile to free it.".format(
		[UiText.click(), UiText.click().to_lower()])


func _refresh_buildings(info: Dictionary) -> void:
	var buildings: Array = info["buildings"]
	_buildings_label.text = ", ".join(PackedStringArray(buildings)) if not buildings.is_empty() else "None yet"
	_buildings_label.add_theme_color_override("font_color", Color.WHITE if not buildings.is_empty() else MUTED)
	_clear(_wonders_box)
	for line: Variant in info.get("wonder_lines", []):
		var label := _label(_wonders_box, UiLayout.BODY_FONT, MUTED)
		label.text = String(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if String(line).begins_with("★"):
			label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))


## A build option: name on the left, production cost and turns as icons.
func _item_button(item: Dictionary) -> CardButton:
	var is_wonder := bool(item.get("wonder", false))
	var button := CardButton.make(WONDER_BG if is_wonder else ITEM_BG, UiLayout.button_height(0.0))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var turns: int = item["turns"]
	var eta := "%dt" % turns if turns > 0 else "–"
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	button.add_child(row)
	var name_label := _label(row, UiLayout.BODY_FONT, Color(1.0, 0.92, 0.65) if is_wonder else Color.WHITE)
	name_label.text = (WONDER_MARK if is_wonder else "") + String(item["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part: Array in [["production", str(item["cost"])], ["turns", eta]]:
		row.add_child(StatIcon.make(part[0], UiLayout.SMALL_FONT + 2))
		var value := _label(row, UiLayout.SMALL_FONT + 1, MUTED)
		value.text = part[1]
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = "Cost %d, %s at the current rate" % [item["cost"], eta]
	if is_wonder:
		button.tooltip_text = "Wonder of the World: %s\nOnly one can exist. %s" % [item.get("tooltip", ""), button.tooltip_text]
	var id: String = item["id"]
	button.pressed.connect(func() -> void: enqueue_requested.emit(id))
	return button


# --- Helpers --------------------------------------------------------------------

func _add_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
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


func _button(text: String, bg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	button.custom_minimum_size = Vector2(0, UiLayout.button_height(0.0))
	var normal := UiStyle.button(bg)
	normal.set_content_margin_all(5)
	var hover := UiStyle.button(bg.lightened(0.15))
	hover.set_content_margin_all(5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	return button


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


## Removes children now (not at the end of the frame) so sizes update at once.
func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _signed(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
