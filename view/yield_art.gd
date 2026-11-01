class_name YieldArt
extends RefCounted
## Draws rows of yield icons (food, production, trade) from data/yields.json.
## Uses each yield's sprite if one exists, else a colored placeholder pip.

const PATH := "res://data/yields.json"
const ICON_SIZE := 8.0
const SPACING := 8.0
## Rows wider than this squeeze their icons together.
const MAX_ROW_WIDTH := 44.0

static var _defs: Array[Dictionary] = []


static func defs() -> Array[Dictionary]:
	if _defs.is_empty():
		_defs = DataLoader.load_list(PATH, "yields")
	return _defs


## One icon per point of yield, centered on `center`.
static func draw(canvas: CanvasItem, center: Vector2, yields: Vector3i, alpha: float = 1.0) -> void:
	var kinds: Array[int] = []
	for kind in 3:
		for n in yields[kind]:
			kinds.append(kind)
	if kinds.is_empty():
		return
	var spacing := minf(SPACING, MAX_ROW_WIDTH / maxf(1.0, kinds.size() - 1))
	var x := center.x - (kinds.size() - 1) * spacing / 2.0
	for kind in kinds:
		var def := defs()[kind]
		var pos := Vector2(x, center.y)
		var texture := SpriteLibrary.get_texture(String(def.get("sprite", "")))
		if texture != null:
			var rect := Rect2(pos - Vector2.ONE * ICON_SIZE / 2.0, Vector2.ONE * ICON_SIZE)
			canvas.draw_texture_rect(texture, rect, false, Color(1, 1, 1, alpha))
		else:
			var color := Color(Color.html(def["placeholder_color"]), alpha)
			PlaceholderArt.draw_yield_pip(canvas, pos, color, String(def.get("placeholder_shape", "circle")))
		x += spacing
