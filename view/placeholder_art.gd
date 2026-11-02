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


## A dark barbarian tent with a flickering campfire beside it. `time` drives the flicker.
static func draw_tent(canvas: CanvasItem, center: Vector2, size: Vector2, time: float) -> void:
	var cloth := Color(0.2, 0.13, 0.08)
	var outline := Color(0.05, 0.03, 0.02)
	var base_y := center.y + size.y / 2.0
	var left := Vector2(center.x - size.x / 2.0, base_y)
	var right := Vector2(center.x + size.x / 2.0 - 6.0, base_y)
	var peak := Vector2(center.x - 3.0, center.y - size.y / 2.0)
	canvas.draw_set_transform(Vector2(center.x, base_y), 0.0, Vector2(1.0, 0.4))
	canvas.draw_circle(Vector2.ZERO, size.x * 0.55, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	var tent := PackedVector2Array([left, peak, right])
	canvas.draw_colored_polygon(tent, cloth)
	# Door flap and a light seam for a bit of bevel.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(peak.x - 3, base_y), Vector2(peak.x, peak.y + size.y * 0.45), Vector2(peak.x + 3, base_y)]), outline)
	canvas.draw_line(peak, left, cloth.lightened(0.3), 1.5)
	tent.append(left)
	canvas.draw_polyline(tent, outline, 1.5)
	# Pole tip and a skull-white pennant so it reads as hostile.
	canvas.draw_line(peak, peak + Vector2(0, -5), outline, 1.5)
	canvas.draw_colored_polygon(PackedVector2Array([peak + Vector2(0, -5), peak + Vector2(7, -3), peak + Vector2(0, -1)]),
		Color(0.85, 0.82, 0.72))
	# Campfire.
	var fire := Vector2(right.x + 4.0, base_y - 2.0)
	var flicker := 1.0 + 0.25 * sin(time * 11.0) + 0.15 * sin(time * 17.0)
	canvas.draw_circle(fire, 3.6 * flicker, Color(0.95, 0.45, 0.1, 0.9))
	canvas.draw_circle(fire + Vector2(0, -1), 1.8 * flicker, Color(1.0, 0.85, 0.35))


## A small building marker: a beveled square in `color` with a letter.
static func draw_building_marker(canvas: CanvasItem, center: Vector2, size: float, color: Color, letter: String) -> void:
	var rect := Rect2(center - Vector2.ONE * size / 2.0, Vector2.ONE * size)
	canvas.draw_rect(rect, color)
	canvas.draw_line(rect.position + Vector2(1, 1), Vector2(rect.end.x - 1, rect.position.y + 1), color.lightened(0.35), 1.5)
	canvas.draw_rect(rect, color.darkened(0.6), false, 1.0)
	draw_centered_text(canvas, center, letter, int(size * 0.8), color)


## A wonder marker: a gold five-pointed star with a colored heart and a
## letter. `shine` (0..1) brightens it for a slow twinkle.
static func draw_wonder_marker(canvas: CanvasItem, center: Vector2, size: float, color: Color, letter: String, shine: float = 0.0) -> void:
	var outer := size / 2.0
	var inner := outer * 0.5
	var points := PackedVector2Array()
	for i in 10:
		var radius := outer if i % 2 == 0 else inner
		points.append(center + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * radius)
	var gold := Color(1.0, 0.82, 0.3).lerp(Color(1.0, 0.97, 0.75), shine)
	canvas.draw_circle(center, outer * (0.95 + 0.25 * shine), Color(1.0, 0.85, 0.4, 0.18 + 0.2 * shine))
	canvas.draw_colored_polygon(points, gold)
	var ring := points.duplicate()
	ring.append(points[0])
	canvas.draw_polyline(ring, Color(0.35, 0.22, 0.05), 1.2, true)
	canvas.draw_circle(center, inner * 0.8, color)
	draw_centered_text(canvas, center, letter, int(size * 0.42), color)


## A little person (a citizen) standing on `feet`, `height` pixels tall:
## light fill with a dark outline and a soft shadow, readable on any terrain.
static func draw_citizen(canvas: CanvasItem, feet: Vector2, height: float, fill: Color, outline: Color) -> void:
	var h := height
	canvas.draw_set_transform(feet, 0.0, Vector2(1.0, 0.45))
	canvas.draw_circle(Vector2.ZERO, h * 0.32, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(Vector2.ZERO)
	var top := feet.y - h * 0.62
	var body := PackedVector2Array([
		Vector2(feet.x - h * 0.26, feet.y),
		Vector2(feet.x - h * 0.22, top + h * 0.07),
		Vector2(feet.x - h * 0.12, top),
		Vector2(feet.x + h * 0.12, top),
		Vector2(feet.x + h * 0.22, top + h * 0.07),
		Vector2(feet.x + h * 0.26, feet.y),
	])
	canvas.draw_colored_polygon(body, fill)
	var ring := body.duplicate()
	ring.append(body[0])
	canvas.draw_polyline(ring, outline, 1.5, true)
	var head := Vector2(feet.x, top - h * 0.18)
	canvas.draw_circle(head, h * 0.2 + 1.3, outline)
	canvas.draw_circle(head, h * 0.2, fill)


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
