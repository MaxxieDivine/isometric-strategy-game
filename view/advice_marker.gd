class_name AdviceMarker
extends Node2D
## A gently bobbing pennant over a tile an advisor pointed at (e.g. a
## suggested city site), with a soft ring on the ground. View only.

const COLOR := Color(0.55, 0.85, 1.0)
const BOB_SPEED := 2.6

var _time := 0.0


func _ready() -> void:
	z_index = 9
	hide()


func show_at(world_pos: Vector2) -> void:
	position = world_pos
	_time = 0.0
	show()
	scale = Vector2.ONE * 0.4
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(self, "scale", Vector2.ONE, 0.3)


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var pulse := 0.5 + 0.5 * sin(_time * BOB_SPEED)
	var s := half * (0.72 + 0.08 * pulse)
	var ring := PackedVector2Array([Vector2(0, -s.y), Vector2(s.x, 0), Vector2(0, s.y), Vector2(-s.x, 0)])
	draw_colored_polygon(ring, Color(COLOR, 0.12 + 0.1 * pulse))
	ring.append(ring[0])
	draw_polyline(ring, Color(COLOR, 0.7), 1.5, true)
	# Pole and pennant, bobbing a little.
	var lift := -4.0 * pulse
	var foot := Vector2(0, -2)
	var top := Vector2(0, -half.y * 1.6 + lift)
	draw_line(foot, top, Color(0.2, 0.16, 0.1), 2.0)
	var wave := 2.0 * sin(_time * 4.0)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(14, 4 + wave), top + Vector2(0, 9)]), COLOR)
	draw_polyline(PackedVector2Array([top, top + Vector2(14, 4 + wave), top + Vector2(0, 9)]),
		Color(0.1, 0.2, 0.3), 1.0)
