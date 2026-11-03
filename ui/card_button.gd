class_name CardButton
extends PanelContainer
## A button that sizes itself to whatever is inside it (icons, several
## lines), unlike Button. Emits `pressed` on a click or tap; lightens on hover.

signal pressed

var _bg := Color.BLACK
var _hover := false
var _down := false


static func make(bg: Color, min_height: float = 0.0) -> CardButton:
	var card := CardButton.new()
	card._bg = bg
	card.custom_minimum_size = Vector2(0, min_height)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card._restyle()
	return card


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_down = false
		_restyle())


func set_bg(bg: Color) -> void:
	_bg = bg
	_restyle()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if click.pressed:
		_down = true
	elif _down:
		_down = false
		if get_global_rect().has_point(get_global_mouse_position()):
			pressed.emit()


func _restyle() -> void:
	var style := UiStyle.button(_bg.lightened(0.15) if _hover and not UiLayout.touch else _bg)
	style.set_content_margin_all(6)
	style.border_color = UiStyle.GOLD.darkened(0.4)
	add_theme_stylebox_override("panel", style)
