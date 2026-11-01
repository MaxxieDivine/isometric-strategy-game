class_name TileInfoPanel
extends PanelContainer
## Small panel describing the selected unit or tile.

var _swatch: ColorRect
var _title_label: Label
var _details_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())

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

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	text.add_child(_title_label)

	_details_label = Label.new()
	_details_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	text.add_child(_details_label)

	hide()


func show_info(title: String, details: String, swatch_color: Color) -> void:
	_title_label.text = title
	_details_label.text = details
	_swatch.color = swatch_color
	# Shrink back to fit when the text gets shorter.
	reset_size()
	show()
