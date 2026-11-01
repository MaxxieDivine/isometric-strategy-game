class_name PathOverlay
extends Node2D
## Draws planned unit routes. Steps reached this turn are white; later turns
## are amber, with a number marking where each turn's movement ends.

const THIS_TURN := Color(1.0, 1.0, 1.0)
const LATER_TURNS := Color(1.0, 0.72, 0.3)
## Routes of units other than the selected one are drawn faintly.
const INACTIVE_ALPHA := 0.35
const FONT_SIZE := 13

## Each entry: { start: Vector2, points: PackedVector2Array, turns: Array[int], active: bool }
var _paths: Array[Dictionary] = []


func show_paths(paths: Array[Dictionary]) -> void:
	_paths = paths
	queue_redraw()


func _draw() -> void:
	for path in _paths:
		_draw_path(path)


func _draw_path(path: Dictionary) -> void:
	var points: PackedVector2Array = path["points"]
	var turns: Array[int] = path["turns"]
	var alpha := 1.0 if path["active"] else INACTIVE_ALPHA
	var prev: Vector2 = path["start"]
	for i in points.size():
		var color := _turn_color(turns[i], alpha)
		draw_dashed_line(prev, points[i], Color(color, 0.7 * alpha), 2.0, 5.0)
		prev = points[i]
	for i in points.size():
		var color := _turn_color(turns[i], alpha)
		var is_last := i == points.size() - 1
		draw_circle(points[i], 5.0 if is_last else 3.0, color)
		draw_circle(points[i], 5.0 if is_last else 3.0, Color(0, 0, 0, 0.6 * alpha), false, 1.0)
		var turn_ends_here := is_last or turns[i + 1] != turns[i]
		if path["active"] and turn_ends_here:
			_draw_turn_label(points[i], turns[i] + 1, color)


func _draw_turn_label(at: Vector2, turn_number: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var text := str(turn_number)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var pos := at + Vector2(-width / 2.0, -8)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _turn_color(turn: int, alpha: float) -> Color:
	return Color(THIS_TURN if turn == 0 else LATER_TURNS, alpha)
