class_name PlaceholderArt
extends RefCounted
## Code-drawn stand-ins for missing sprites. View layer only.


## A heraldic shield in `color` with a letter on it, centered on `center`.
static func draw_shield(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color, letter: String) -> void:
	var half_w := size.x / 2.0
	var top := center.y - size.y / 2.0
	var shoulder := top + size.y * 0.55
	var points := PackedVector2Array([
		Vector2(center.x - half_w, top),
		Vector2(center.x + half_w, top),
		Vector2(center.x + half_w, shoulder),
		Vector2(center.x, top + size.y),
		Vector2(center.x - half_w, shoulder),
	])
	canvas.draw_colored_polygon(points, color)
	# Light band across the top for a bit of retro bevel.
	canvas.draw_line(Vector2(center.x - half_w + 2, top + 2), Vector2(center.x + half_w - 2, top + 2),
		color.lightened(0.35), 2.0)
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, color.darkened(0.6), 1.5)

	if letter.is_empty():
		return
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.55)
	var text_width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_center_y := top + size.y * 0.42
	var baseline := Vector2(center.x - text_width / 2.0,
		text_center_y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	var text_color := Color(0.1, 0.1, 0.12) if color.get_luminance() > 0.6 else Color.WHITE
	canvas.draw_string_outline(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3,
		color.darkened(0.6))
	canvas.draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
