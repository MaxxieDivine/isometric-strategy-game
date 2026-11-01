class_name TileInfoPanel
extends PanelContainer
## Small panel describing the selected tile.

var _swatch: ColorRect
var _name_label: Label
var _coords_label: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.92)
	style.border_color = Color(0.85, 0.75, 0.45)
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(28, 28)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_swatch)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	text.add_child(_name_label)

	_coords_label = Label.new()
	_coords_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	text.add_child(_coords_label)

	hide()


func show_tile(cell: Vector2i, terrain_def: Dictionary) -> void:
	_name_label.text = terrain_def.get("name", "Unknown")
	_coords_label.text = "Tile (%d, %d)" % [cell.x, cell.y]
	_swatch.color = Color.html(terrain_def.get("placeholder_color", "#ffffff"))
	show()
