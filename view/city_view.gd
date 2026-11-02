class_name CityView
extends Node2D
## Draws one city: its sprite (or placeholder block with the size number)
## a row of building markers, gold wonder stars above it, and its name below.
## Pops when founded, when its size changes, and when a building or wonder is
## added. Wonder stars twinkle slowly.

const BLOCK_SIZE := Vector2(26, 20)
const BODY_OFFSET := Vector2(0, -6)
const NAME_OFFSET_Y := 24.0
const NAME_FONT_SIZE := 13
const MARKER_SIZE := 9.0
const MARKER_GAP := 2.0
const MARKER_Y := 10.0
const WONDER_SIZE := 15.0
## Below the name, where units standing in the city never cover them.
const WONDER_Y := 38.0
const TWINKLE_TIME := 1.6

var city_id := -1

var _city_name := ""
var _color := Color.WHITE
var _texture: Texture2D
var _size := 0
## [{ id, sprite, color, letter }] in build order.
var _buildings: Array[Dictionary] = []
var _buildings_synced := false
## [{ id, sprite, color, letter }] for each wonder in the city.
var _wonders: Array[Dictionary] = []
var _wonders_synced := false
var _shine := 0.0:
	set(value):
		_shine = value
		queue_redraw()
var _twinkle: Tween
var _pop: Tween


func setup(id: int, city_name: String, owner_color: Color, sprite_key: String) -> void:
	city_id = id
	_city_name = city_name
	_color = owner_color
	_texture = SpriteLibrary.get_texture(sprite_key)
	scale = Vector2.ONE * 0.3
	_pop_to_full_size()


func set_city_size(new_size: int) -> void:
	if new_size == _size:
		return
	var changed := _size != 0
	_size = new_size
	queue_redraw()
	if changed:
		scale = Vector2.ONE * 1.3
		_pop_to_full_size()


## `entries`: [{ id, sprite, color, letter }] for each building the city has.
func set_buildings(entries: Array[Dictionary]) -> void:
	if _buildings_synced and entries.size() == _buildings.size():
		return
	# Pop only for a newly finished building, not on the first sync.
	var added := _buildings_synced and entries.size() > _buildings.size()
	_buildings_synced = true
	_buildings = entries
	queue_redraw()
	if added:
		scale = Vector2.ONE * 1.2
		_pop_to_full_size()


## `entries`: [{ id, sprite, color, letter }] for each wonder in the city.
func set_wonders(entries: Array[Dictionary]) -> void:
	if _wonders_synced and entries.size() == _wonders.size():
		return
	var added := _wonders_synced and entries.size() > _wonders.size()
	_wonders_synced = true
	_wonders = entries
	queue_redraw()
	if not _wonders.is_empty() and _twinkle == null:
		_twinkle = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_twinkle.tween_property(self, "_shine", 1.0, TWINKLE_TIME)
		_twinkle.tween_property(self, "_shine", 0.0, TWINKLE_TIME)
	if added:
		scale = Vector2.ONE * 1.5
		_pop_to_full_size()


func _pop_to_full_size() -> void:
	if _pop != null:
		_pop.kill()
	_pop = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.3)


func _draw() -> void:
	if _texture != null:
		draw_texture(_texture, BODY_OFFSET - _texture.get_size() / 2.0)
		PlaceholderArt.draw_centered_text(self, BODY_OFFSET, str(_size), 14, _color)
	else:
		PlaceholderArt.draw_city_block(self, BODY_OFFSET, BLOCK_SIZE, _color, str(_size))

	_draw_buildings()
	_draw_wonders()

	var font := ThemeDB.fallback_font
	var width := font.get_string_size(_city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x
	var pos := Vector2(-width / 2.0, NAME_OFFSET_Y)
	draw_string_outline(font, pos, _city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, 4, Color.BLACK)
	draw_string(font, pos, _city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, Color.WHITE)


func _draw_wonders() -> void:
	var count := _wonders.size()
	if count == 0:
		return
	var step := WONDER_SIZE + 2.0
	var x := -(count - 1) * step / 2.0
	for i in count:
		var entry := _wonders[i]
		var center := Vector2(x, WONDER_Y)
		# Each star twinkles a little out of step with the others.
		var shine := clampf(_shine - 0.25 * i, 0.0, 1.0)
		var texture := SpriteLibrary.get_texture(entry["sprite"])
		if texture != null:
			draw_texture_rect(texture, Rect2(center - Vector2.ONE * WONDER_SIZE / 2.0, Vector2.ONE * WONDER_SIZE), false,
				Color.WHITE.lerp(Color(1.3, 1.25, 1.0), shine))
		else:
			PlaceholderArt.draw_wonder_marker(self, center, WONDER_SIZE, entry["color"], entry["letter"], shine)
		x += step


func _draw_buildings() -> void:
	var count := _buildings.size()
	if count == 0:
		return
	var step := MARKER_SIZE + MARKER_GAP
	var x := -(count - 1) * step / 2.0
	for entry in _buildings:
		var center := Vector2(x, MARKER_Y)
		var texture := SpriteLibrary.get_texture(entry["sprite"])
		if texture != null:
			draw_texture_rect(texture, Rect2(center - Vector2.ONE * MARKER_SIZE / 2.0, Vector2.ONE * MARKER_SIZE), false)
		else:
			PlaceholderArt.draw_building_marker(self, center, MARKER_SIZE, entry["color"], entry["letter"])
		x += step
