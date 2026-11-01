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
	draw_centered_text(canvas, Vector2(center.x, top + size.y * 0.42), letter, int(size.y * 0.55), color)


## A walled block in `color` with battlements and a label (the city size).
static func draw_city_block(canvas: CanvasItem, center: Vector2, size: Vector2, color: Color, label: String) -> void:
	var body := Rect2(center - size / 2.0, size)
	var outline := color.darkened(0.6)
	var merlon := Vector2(size.x / 5.0, 4.0)
	for i in [0, 2, 4]:
		var block := Rect2(body.position + Vector2(i * merlon.x, -merlon.y), merlon)
		canvas.draw_rect(block, color)
		canvas.draw_rect(block, outline, false, 1.5)
	canvas.draw_rect(body, color)
	canvas.draw_line(body.position + Vector2(2, 2), Vector2(body.end.x - 2, body.position.y + 2),
		color.lightened(0.35), 2.0)
	canvas.draw_rect(body, outline, false, 1.5)
	draw_centered_text(canvas, center, label, int(size.y * 0.8), color)


## A small yield marker: circle, square, or diamond.
static func draw_yield_pip(canvas: CanvasItem, center: Vector2, color: Color, shape: String, radius: float = 3.5) -> void:
	var outline := Color(0, 0, 0, 0.7 * color.a)
	match shape:
		"square":
			var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			canvas.draw_rect(rect, color)
			canvas.draw_rect(rect, outline, false, 1.0)
		"diamond":
			var r := radius * 1.3
			var points := PackedVector2Array([
				center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0),
			])
			canvas.draw_colored_polygon(points, color)
			points.append(points[0])
			canvas.draw_polyline(points, outline, 1.0)
		_:
			canvas.draw_circle(center, radius, color)
			canvas.draw_circle(center, radius, outline, false, 1.0)


## Text centered on `center`, readable on a `background` of that color.
static func draw_centered_text(canvas: CanvasItem, center: Vector2, text: String, font_size: int, background: Color) -> void:
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := Vector2(center.x - width / 2.0,
		center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	var text_color := Color(0.1, 0.1, 0.12) if background.get_luminance() > 0.6 else Color.WHITE
	canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3,
		background.darkened(0.6))
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
