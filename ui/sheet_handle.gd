class_name SheetHandle
extends Control
## The grip at the top of a bottom sheet (compact layout). Dragging it emits
## `dragged` with the vertical movement; letting go emits `released`.
## Also places a panel as a bottom sheet (see place).

signal dragged(delta_y: float)
signal released

const GRIP := Vector2(44, 5)

var _dragging := false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_VSIZE


## Anchors `panel` across the bottom of the screen, `height` UI units tall.
static func place(panel: Control, height: float) -> void:
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.offset_top = -height
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		if not button.pressed:
			released.emit()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		dragged.emit(motion.relative.y)
		accept_event()


func _draw() -> void:
	var center := Vector2(size.x / 2.0, size.y / 2.0)
	draw_rect(Rect2(center - GRIP / 2.0, GRIP), Color(UiStyle.GOLD, 0.7))
