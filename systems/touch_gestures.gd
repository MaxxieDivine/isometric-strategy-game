class_name TouchGestures
extends Node
## Turns raw touches on the map into gestures: tap, long press, one-finger
## drag (pan) and two-finger pinch (zoom). Touches that land on UI controls
## never get here: the GUI consumes them first.
##
## Positions are viewport coordinates (the same space as mouse positions).

signal tapped(screen_pos: Vector2)
signal long_pressed(screen_pos: Vector2)
## The view should move by `delta` screen pixels (content follows the finger).
signal dragged(delta: Vector2)
## Zoom by `factor` (> 1 zooms in) around `center`.
signal pinched(factor: float, center: Vector2)
## Any touch at all: the player is on a touch screen.
signal touch_seen

## A finger that moves less than this is still a tap.
const TAP_SLOP := 14.0
const LONG_PRESS_TIME := 0.45

## Active touches: finger index -> current position.
var _touches := {}
var _start_pos := Vector2.ZERO
var _press_time := 0.0
## The current one-finger touch may still become a tap or long press.
var _tap_possible := false
var _long_press_fired := false
var _dragging := false
var _pinch_distance := 0.0


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		touch_seen.emit()
		if touch.pressed:
			_on_press(touch)
		else:
			_on_release(touch)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_on_drag(drag)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _tap_possible or _long_press_fired:
		return
	_press_time += delta
	if _press_time >= LONG_PRESS_TIME:
		_long_press_fired = true
		_tap_possible = false
		long_pressed.emit(_start_pos)


func _on_press(touch: InputEventScreenTouch) -> void:
	_touches[touch.index] = touch.position
	if _touches.size() == 1:
		_start_pos = touch.position
		_press_time = 0.0
		_tap_possible = true
		_long_press_fired = false
		_dragging = false
	else:
		# A second finger turns this into a pinch: no tap, no long press.
		_tap_possible = false
		_dragging = false
		_pinch_distance = _finger_distance()


func _on_release(touch: InputEventScreenTouch) -> void:
	_touches.erase(touch.index)
	if _touches.is_empty():
		if _tap_possible and not _long_press_fired:
			tapped.emit(touch.position)
		_tap_possible = false
		_dragging = false
	elif _touches.size() == 1:
		# Back to one finger after a pinch: let it pan from here, never tap.
		_dragging = true
	_pinch_distance = _finger_distance()


func _on_drag(drag: InputEventScreenDrag) -> void:
	if not _touches.has(drag.index):
		return
	_touches[drag.index] = drag.position
	if _touches.size() >= 2:
		var distance := _finger_distance()
		if _pinch_distance > 0.0 and distance > 0.0:
			pinched.emit(distance / _pinch_distance, _finger_center())
		_pinch_distance = distance
		return
	if not _dragging:
		if drag.position.distance_to(_start_pos) < TAP_SLOP:
			return
		_dragging = true
		_tap_possible = false
		# Catch up on the slop so the map stays under the finger.
		dragged.emit(drag.position - _start_pos)
		return
	dragged.emit(drag.relative)


func _finger_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _finger_center() -> Vector2:
	var points: Array = _touches.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) / 2.0
