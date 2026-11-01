class_name UnitView
extends Node2D
## Draws one unit: its sprite (or placeholder shield), a selection ring, and
## a stack marker. Animates moves step by step.

const SHIELD_SIZE := Vector2(22, 26)
## The sprite stands slightly above the tile center.
const SPRITE_OFFSET := Vector2(0, -10)
const STEP_TIME := 0.14
const RING_COLOR := Color(1.0, 0.93, 0.55)
const RING_RADIUS := 24.0

var unit_id := -1
var selected := false:
	set(value):
		selected = value
		_time = 0.0
		queue_redraw()
var stack_count := 1:
	set(value):
		if value != stack_count:
			stack_count = value
			queue_redraw()

var _letter := ""
var _color := Color.WHITE
var _texture: Texture2D
var _time := 0.0
var _waypoints: Array[Vector2] = []
var _walking := false


func setup(id: int, def: Dictionary, owner_color: Color) -> void:
	unit_id = id
	_letter = String(def.get("name", "?")).left(1).to_upper()
	_color = owner_color
	_texture = SpriteLibrary.get_texture(String(def.get("sprite", "")))


func is_walking() -> bool:
	return _walking


## Queues a one-tile step; steps play back to back.
func walk_to(world_pos: Vector2) -> void:
	_waypoints.append(world_pos)
	if not _walking:
		_next_step()


func _next_step() -> void:
	if _waypoints.is_empty():
		_walking = false
		return
	_walking = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", _waypoints.pop_front(), STEP_TIME)
	tween.finished.connect(_next_step)


func _process(delta: float) -> void:
	if selected:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if selected:
		var alpha := 0.55 + 0.45 * sin(_time * 6.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 40, Color(RING_COLOR, alpha), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# The selected unit hops gently so it's easy to spot.
	var hop := -2.5 * absf(sin(_time * 4.0)) if selected else 0.0
	var center := SPRITE_OFFSET + Vector2(0, hop)
	if stack_count > 1:
		_draw_body(center + Vector2(4, -3), _color.darkened(0.35))
	_draw_body(center, _color)


func _draw_body(center: Vector2, color: Color) -> void:
	if _texture != null:
		draw_texture(_texture, center - _texture.get_size() / 2.0, Color.WHITE if color == _color else Color(0.6, 0.6, 0.6))
	else:
		PlaceholderArt.draw_shield(self, center, SHIELD_SIZE, color, _letter)
