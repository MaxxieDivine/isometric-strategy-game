class_name TileInfoPanel
extends PanelContainer
## Small panel describing the selected unit or tile. A tile's yields show as
## food, production and trade icons with numbers. In the compact layout only
## the title and first line show; tap the panel for the rest.

const MUTED := Color(0.75, 0.78, 0.85)

var _swatch: ColorRect
var _title_label: Label
var _details_label: Label
var _yields_row: HBoxContainer
var _yield_chips: Array[StatChip] = []
var _more: Label
var _details := ""
var _compact := false
var _expanded := false


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(24, 24)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_swatch)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title_row)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	title_row.add_child(_title_label)
	_more = Label.new()
	_more.text = "  ▾"
	_more.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	_more.add_theme_color_override("font_color", UiStyle.GOLD)
	title_row.add_child(_more)

	_yields_row = HBoxContainer.new()
	_yields_row.add_theme_constant_override("separation", 12)
	text.add_child(_yields_row)
	for stat: String in ["food", "production", "trade"]:
		var chip := StatChip.make(stat)
		_yields_row.add_child(chip)
		_yield_chips.append(chip)

	_details_label = Label.new()
	_details_label.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	_details_label.add_theme_color_override("font_color", MUTED)
	_details_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_details_label)

	hide()


func set_compact(compact: bool) -> void:
	_compact = compact
	_expanded = false
	if visible:
		_refresh()


## `yields`: the tile's food, production, trade, or (-1, -1, -1) for none.
func show_info(title: String, details: String, swatch_color: Color, yields := Vector3i(-1, -1, -1)) -> void:
	if title != _title_label.text:
		_expanded = false
	_title_label.text = title
	_details = details
	_swatch.color = swatch_color
	_yields_row.visible = yields.x >= 0
	if yields.x >= 0:
		var names: Array[String] = ["Food", "Production", "Trade"]
		for i in 3:
			_yield_chips[i].set_value(str(yields[i]), "%s %d per turn when worked" % [names[i], yields[i]], names[i])
	_refresh()
	show()


func _refresh() -> void:
	var lines := _details.split("\n")
	var collapsed := _compact and not _expanded and lines.size() > 1
	_details_label.text = lines[0] if collapsed else _details
	_details_label.visible = _details != ""
	_more.visible = collapsed
	# Shrink back to fit when the text gets shorter.
	reset_size()


func _on_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _compact:
		accept_event()
		_expanded = not _expanded
		_refresh()
