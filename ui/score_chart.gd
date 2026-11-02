class_name ScoreChart
extends Control
## A line chart of score over time: one line per civ, turns along the bottom,
## score up the side. Optional gold markers (e.g. wonders) sit on the line of
## the civ they belong to. Draws once and animates the lines in.

const AXIS_COLOR := Color(0.55, 0.55, 0.6)
const GRID_COLOR := Color(1, 1, 1, 0.07)
const LABEL_COLOR := Color(0.7, 0.7, 0.75)
const MARKER_COLOR := Color(1.0, 0.86, 0.4)
const FONT_SIZE := 11
const PAD_LEFT := 34.0
const PAD_BOTTOM := 20.0
const PAD_TOP := 8.0
const PAD_RIGHT := 10.0

## [{ name, color: Color, points: [[turn, score], ...] }]
var _series: Array[Dictionary] = []
## [{ turn, series (index), label }]
var _markers: Array[Dictionary] = []
var _max_turn := 1
var _max_score := 10
var _reveal := 1.0:
	set(value):
		_reveal = value
		queue_redraw()


func set_data(series: Array[Dictionary], markers: Array[Dictionary] = []) -> void:
	_series = series
	_markers = markers
	_max_turn = 1
	_max_score = 10
	for entry in _series:
		for point: Array in entry["points"]:
			_max_turn = maxi(_max_turn, int(point[0]))
			_max_score = maxi(_max_score, int(point[1]))
	_max_score = _nice_ceiling(_max_score)
	_reveal = 0.0
	create_tween().tween_property(self, "_reveal", 1.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _plot_rect() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - PAD_RIGHT, size.y - PAD_TOP - PAD_BOTTOM)


func _to_screen(turn: float, score: float) -> Vector2:
	var plot := _plot_rect()
	var x := plot.position.x + plot.size.x * (turn - 1.0) / maxf(1.0, _max_turn - 1.0)
	var y := plot.end.y - plot.size.y * score / float(_max_score)
	return Vector2(x, y)


func _draw() -> void:
	var plot := _plot_rect()
	var font := ThemeDB.fallback_font
	# Horizontal grid with score labels.
	for i in 5:
		var value := _max_score * i / 4.0
		var y := _to_screen(1, value).y
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COLOR, 1.0)
		var text := str(roundi(value))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(plot.position.x - width - 5.0, y + 4.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)
	# Turn labels along the bottom.
	var step := _turn_step()
	var turn := 1
	while turn <= _max_turn:
		var x := _to_screen(turn, 0).x
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 3.0), AXIS_COLOR, 1.0)
		var text := str(turn)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(x - width / 2.0, plot.end.y + 15.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, LABEL_COLOR)
		turn = step if turn == 1 else turn + step
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), AXIS_COLOR, 1.0)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, AXIS_COLOR, 1.0)
	# Lines, revealed left to right.
	var cutoff := 1.0 + (_max_turn - 1.0) * _reveal
	for entry in _series:
		var points := PackedVector2Array()
		for point: Array in entry["points"]:
			if float(point[0]) > cutoff:
				break
			points.append(_to_screen(point[0], point[1]))
		if points.size() >= 2:
			draw_polyline(points, Color(0, 0, 0, 0.5), 4.0, true)
			draw_polyline(points, entry["color"], 2.5, true)
		elif points.size() == 1:
			draw_circle(points[0], 2.5, entry["color"])
	# Markers.
	for marker in _markers:
		if float(marker["turn"]) > cutoff:
			continue
		var at := _score_at(int(marker["series"]), int(marker["turn"]))
		var pos := _to_screen(marker["turn"], at)
		PlaceholderArt.draw_wonder_marker(self, pos, 13.0, Color(0.5, 0.35, 0.1), "", 0.4)


func _score_at(series: int, turn: int) -> int:
	if series < 0 or series >= _series.size():
		return 0
	var best := 0
	for point: Array in _series[series]["points"]:
		if int(point[0]) > turn:
			break
		best = int(point[1])
	return best


func _turn_step() -> int:
	for step: int in [5, 10, 20, 25, 50, 100]:
		if _max_turn / float(step) <= 8.0:
			return step
	return 200


static func _nice_ceiling(value: int) -> int:
	for step: int in [10, 20, 25, 50, 100, 200, 250, 500]:
		if value <= step * 4:
			return ceili(value / float(step)) * step
	return ceili(value / 1000.0) * 1000
