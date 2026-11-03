class_name StatChip
extends PanelContainer
## Icon + number: e.g. a food icon with "2/20 (+2) 9t". The full sentence is
## the tooltip on desktop and appears on long-press (or tap, unless the chip
## does something else on tap: then it emits `tapped`).

signal tapped

const LONG_PRESS_TIME := 0.45

var full_title := ""
var full_text := ""
## True: a tap emits `tapped` (e.g. opens a panel) instead of showing the text.
var tap_action := false

var _icon: StatIcon
var _label: Label
var _press_id := 0
var _long_pressed := false


## A chip for `stat` with `font_size` text. `framed` gives it a panel look
## (top-bar chips); unframed chips sit inline in other panels.
static func make(stat: String, font_size: int = UiLayout.BODY_FONT, framed: bool = false) -> StatChip:
	var chip := StatChip.new()
	chip._build(stat, font_size, framed)
	return chip


func _build(stat: String, font_size: int, framed: bool) -> void:
	if framed:
		add_theme_stylebox_override("panel", UiStyle.panel())
	else:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(2)
		add_theme_stylebox_override("panel", empty)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = StatIcon.make(stat, font_size + 3)
	row.add_child(_icon)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", font_size)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	gui_input.connect(_on_input)


## `text`: the short form; `full`: the sentence behind it (with `title`).
func set_value(text: String, full: String, title: String = "") -> void:
	_label.text = text
	full_text = full
	full_title = title
	tooltip_text = full if not UiLayout.touch else ""


func set_color(color: Color) -> void:
	_label.add_theme_color_override("font_color", color)


func set_stat(stat: String) -> void:
	_icon.set_stat(stat)


func show_full() -> void:
	InfoPopover.show_text(full_title, full_text, get_global_rect())


func _on_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if click.pressed:
		_press_id += 1
		_long_pressed = false
		var id := _press_id
		get_tree().create_timer(LONG_PRESS_TIME).timeout.connect(func() -> void:
			if id == _press_id and not _long_pressed:
				_long_pressed = true
				show_full())
	else:
		_press_id += 1
		if _long_pressed:
			return
		if tap_action:
			InfoPopover.hide_any()
			tapped.emit()
		else:
			show_full()
