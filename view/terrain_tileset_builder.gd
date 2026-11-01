class_name TerrainTilesetBuilder
extends RefCounted
## Generates placeholder colored-diamond tiles and an isometric, stacked TileSet.

const TILE_SIZE := Vector2i(64, 32)
const SOURCE_ID := 0
## Normalized edge width of the darker diamond outline.
const OUTLINE := 0.07


## Returns a TileSet whose atlas holds one tile per terrain def, in order:
## the def at index i lives at atlas coords (i, 0).
static func build(defs: Array[Dictionary]) -> TileSet:
	var image := Image.create(TILE_SIZE.x * defs.size(), TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in defs.size():
		_draw_diamond(image, i * TILE_SIZE.x, Color.html(defs[i]["placeholder_color"]))

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = TILE_SIZE
	for i in defs.size():
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_size = TILE_SIZE
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


static func _draw_diamond(image: Image, offset_x: int, base: Color) -> void:
	var half := Vector2(TILE_SIZE) / 2.0
	var top := base.lightened(0.1)
	var bottom := base.darkened(0.08)
	var edge := base.darkened(0.4)
	for py in TILE_SIZE.y:
		for px in TILE_SIZE.x:
			var d := absf(px + 0.5 - half.x) / half.x + absf(py + 0.5 - half.y) / half.y
			if d > 1.0:
				continue
			var color := edge if d > 1.0 - OUTLINE else (top if py < half.y else bottom)
			image.set_pixel(offset_x + px, py, color)
