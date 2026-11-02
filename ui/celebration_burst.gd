class_name CelebrationBurst
extends Control
## A quick gold starburst (expanding ring, rays, sparks) that frees itself.
## Purely cosmetic and never blocks input.

const DURATION := 0.7
const RAYS := 12
const COLOR := Color(1.0, 0.86, 0.4)

var radius := 90.0
var _t := 0.0:
	set(value):
		_t = value
		queue_redraw()
## Cosmetic only, so it has its own RNG.
var _rng := RandomNumberGenerator.new()
var _spark_angles: PackedFloat32Array = PackedFloat32Array()


## Plays a burst centered on `center` (in `parent`'s coordinates).
static func play(parent: Control, center: Vector2, burst_radius: float = 90.0) -> void:
	var burst := CelebrationBurst.new()
	burst.radius = burst_radius
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	burst.position = center
	parent.add_child(burst)


func _ready() -> void:
	_rng.randomize()
	for i in 16:
		_spark_angles.append(_rng.randf() * TAU)
	var tween := create_tween()
	tween.tween_property(self, "_t", 1.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(queue_free)


func _draw() -> void:
	var fade := 1.0 - _t
	var color := Color(COLOR, fade)
	draw_arc(Vector2.ZERO, radius * _t, 0.0, TAU, 48, color, 4.0 * fade + 1.0)
	for i in RAYS:
		var dir := Vector2.from_angle(TAU * i / RAYS + 0.2)
		draw_line(dir * radius * (0.25 + 0.6 * _t), dir * radius * (0.45 + 0.75 * _t), color, 3.0)
	for i in _spark_angles.size():
		var dir := Vector2.from_angle(_spark_angles[i])
		var dist := radius * (0.3 + 0.9 * _t) * (0.7 + 0.3 * float(i % 3))
		draw_rect(Rect2(dir * dist - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 0.8, fade))
