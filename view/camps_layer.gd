class_name CampsLayer
extends Node2D
## Draws barbarian camps the viewer has discovered, on explored tiles (they
## stay drawn under the fog once seen). View only.

const SPRITE_OFFSET := Vector2(0, -6)
const TENT_SIZE := Vector2(30, 22)

var _texture: Texture2D
## World positions of camps to draw.
var _camps: PackedVector2Array = PackedVector2Array()
var _time := 0.0


func sync(state: GameState, map_view: MapView, viewer: int) -> void:
	_texture = SpriteLibrary.get_texture(Barbarians.camp_sprite())
	_camps.clear()
	for camp in state.camps:
		if camp.discovered_by.has(viewer) and state.is_explored(viewer, camp.position):
			_camps.append(map_view.grid_to_world(camp.position))
	queue_redraw()


func clear() -> void:
	_camps.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if not _camps.is_empty():
		_time += delta
		queue_redraw()


func _draw() -> void:
	for pos in _camps:
		var center := pos + SPRITE_OFFSET
		if _texture != null:
			draw_texture(_texture, center - _texture.get_size() / 2.0)
		else:
			PlaceholderArt.draw_tent(self, center, TENT_SIZE, _time)
