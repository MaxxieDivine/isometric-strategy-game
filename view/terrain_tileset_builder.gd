class_name TerrainTilesetBuilder
extends RefCounted
## Generates colored-diamond placeholder tiles and isometric, stacked TileSets.

const TILE_SIZE := Vector2i(64, 32)
const SOURCE_ID := 0
## Normalized edge width of the darker diamond outline.
const OUTLINE := 0.07


## One shaded tile per terrain def, in order: def i lives at atlas coords (i, 0).
static func build(defs: Array[Dictionary]) -> TileSet:
	var colors: Array[Color] = []
	for def in defs:
		colors.append(Color.html(def["placeholder_color"]))
	return build_diamonds(colors, true)


## One diamond tile per color at atlas coords (i, 0). `shaded` adds a bevel
## and outline; unshaded tiles are flat fills (used for fog overlays).
static func build_diamonds(colors: Array[Color], shaded: bool) -> TileSet:
	var image := Image.create(TILE_SIZE.x * colors.size(), TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i in colors.size():
		_draw_diamond(image, i * TILE_SIZE.x, colors[i], shaded)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = TILE_SIZE
	for i in colors.size():
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_size = TILE_SIZE
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


static func _draw_diamond(image: Image, offset_x: int, base: Color, shaded: bool) -> void:
	var half := Vector2(TILE_SIZE) / 2.0
	var top := base.lightened(0.1) if shaded else base
	var bottom := base.darkened(0.08) if shaded else base
	var edge := base.darkened(0.4) if shaded else base
	for py in TILE_SIZE.y:
		for px in TILE_SIZE.x:
			var d := absf(px + 0.5 - half.x) / half.x + absf(py + 0.5 - half.y) / half.y
			if d > 1.0:
				continue
			var color := edge if d > 1.0 - OUTLINE else (top if py < half.y else bottom)
			image.set_pixel(offset_x + px, py, color)
