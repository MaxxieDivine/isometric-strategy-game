class_name TileHighlight
extends Node2D
## Pulsing diamond outline over the selected tile.

const COLOR := Color(1.0, 0.93, 0.55)
const PULSE_SPEED := 5.0

var _time := 0.0
var _pop: Tween


func _ready() -> void:
	z_index = 10
	hide()


func show_at(world_pos: Vector2) -> void:
	position = world_pos
	show()
	if _pop != null:
		_pop.kill()
	scale = Vector2.ONE * 1.3
	_pop = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.18)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	modulate.a = 0.7 + 0.3 * sin(_time * PULSE_SPEED)


func _draw() -> void:
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var points := PackedVector2Array([
		Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0),
	])
	draw_colored_polygon(points, Color(COLOR, 0.2))
	points.append(points[0])
	draw_polyline(points, COLOR, 2.0)
