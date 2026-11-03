class_name MapFrame
extends Node2D
## Dresses the edge of the map, since the camera can show past it: beyond
## the edge is dark (like unexplored land), the last stretch of map fades
## into it, and a thin dim-gold line marks where the world ends. It also
## hides the jagged half-tiles of the stacked rows. View only.

const OUTSIDE := Color(0.02, 0.025, 0.04)
const LINE := Color(0.85, 0.75, 0.45, 0.35)
## How far inside the edge the fade reaches, in world pixels.
const FADE := 28.0
## Far enough out to cover any view, even zoomed all the way out.
const EXTENT := 20000.0

var _rect := Rect2()


func _ready() -> void:
	# Above the map, fog and units, below the UI (a separate canvas layer).
	z_index = 20


## `rect`: the playable map area in world pixels (the camera bounds).
func set_bounds(rect: Rect2) -> void:
	_rect = rect
	queue_redraw()


func _draw() -> void:
	if _rect.size == Vector2.ZERO:
		return
	var r := _rect
	var outer := r.grow(EXTENT)
	# Four solid bands around the map.
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, r.position.y - outer.position.y)), OUTSIDE)
	draw_rect(Rect2(Vector2(outer.position.x, r.end.y), Vector2(outer.size.x, outer.end.y - r.end.y)), OUTSIDE)
	draw_rect(Rect2(Vector2(outer.position.x, r.position.y), Vector2(r.position.x - outer.position.x, r.size.y)), OUTSIDE)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(outer.end.x - r.end.x, r.size.y)), OUTSIDE)
	# A soft fade just inside each edge.
	var inner := r.grow(-FADE)
	var clear := Color(OUTSIDE, 0.0)
	var corners_out := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var corners_in := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for i in 4:
		var j := (i + 1) % 4
		draw_polygon(PackedVector2Array([corners_out[i], corners_out[j], corners_in[j], corners_in[i]]),
			PackedColorArray([OUTSIDE, OUTSIDE, clear, clear]))
	draw_rect(r, LINE, false, 2.0)
