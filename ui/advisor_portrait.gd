class_name AdvisorPortrait
extends Control
## An advisor's framed portrait: `assets/sprites/<key>.png` when it exists,
## otherwise a code-drawn silhouette with the advisor's initial. It breathes
## very slightly so the character feels present.

const BREATH_SPEED := 1.8

var _key := ""
var _color := Color(0.5, 0.56, 0.7)
var _initial := "?"
var _time := 0.0


func set_portrait(key: String, color: Color, initial: String) -> void:
	_key = key
	_color = color
	_initial = initial
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var texture := SpriteLibrary.get_texture(_key)
	if texture == null:
		# Breathe: the silhouette rises and falls by a pixel inside its frame.
		draw_set_transform(Vector2(0, 0.8 * sin(_time * BREATH_SPEED)))
		PlaceholderArt.draw_portrait(self, rect, _color, _initial)
		draw_set_transform(Vector2.ZERO)
		return
	draw_rect(rect, UiStyle.GOLD.darkened(0.45))
	draw_texture_rect(texture, rect.grow(-4.0), false)
	draw_rect(rect, UiStyle.GOLD, false, 2.0)
