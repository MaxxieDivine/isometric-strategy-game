class_name TerrainTilesetBuilder
extends RefCounted
## Builds isometric, stacked TileSets: terrain art from each def's `sprite`
## key (assets/sprites/<key>.png, transparent outside the diamond), falling
## back to a generated colored diamond when art is missing.
##
## TILE_SIZE is the map grid (the diamond every view layer projects to). The
## art canvas may be larger than the grid: each image is centered on its
## cell, so the drawn diamond inside the canvas must match TILE_SIZE.

## PREVIEW: 50x30 matches the diamond the current PixelLab tiles draw inside
## their 64x32 canvas. Set back to Vector2i(64, 32) once the tiles are
## regenerated edge to edge; nothing else needs to change.
const TILE_SIZE := Vector2i(50, 30)
const SOURCE_ID := 0
## Normalized edge width of the darker diamond outline.
const OUTLINE := 0.07


## One tile per terrain def, in order: def i lives at atlas coords (i, 0).
static func build(defs: Array[Dictionary]) -> TileSet:
	var art: Array[Image] = []
	var slot := TILE_SIZE
	for def in defs:
		var image := _sprite_image(String(def.get("sprite", "")))
		art.append(image)
		if image != null:
			slot = slot.max(image.get_size())

	var atlas := _blank_atlas(slot, defs.size())
	for i in defs.size():
		var origin := Vector2i(i * slot.x, 0)
		if art[i] != null:
			# Centered in the slot, as Godot centers the slot on the cell.
			var size := art[i].get_size()
			atlas.blit_rect(art[i], Rect2i(Vector2i.ZERO, size), origin + (slot - size) / 2)
		else:
			_draw_diamond(atlas, origin + (slot - TILE_SIZE) / 2, Color.html(def_color(defs[i])), true)
	return _tile_set_from(atlas, slot, defs.size())


## One diamond tile per color at atlas coords (i, 0). `shaded` adds a bevel
## and outline; unshaded tiles are flat fills (used for fog overlays).
static func build_diamonds(colors: Array[Color], shaded: bool) -> TileSet:
	var atlas := _blank_atlas(TILE_SIZE, colors.size())
	for i in colors.size():
		_draw_diamond(atlas, Vector2i(i * TILE_SIZE.x, 0), colors[i], shaded)
	return _tile_set_from(atlas, TILE_SIZE, colors.size())


static func def_color(def: Dictionary) -> String:
	return String(def.get("placeholder_color", "#ff00ff"))


## The art for a sprite key as RGBA8, or null if missing or too small.
static func _sprite_image(key: String) -> Image:
	var texture := SpriteLibrary.get_texture(key)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.get_width() < TILE_SIZE.x or image.get_height() < TILE_SIZE.y:
		push_warning("Terrain sprite '%s' is smaller than the %s grid; using placeholder" % [key, TILE_SIZE])
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image


static func _blank_atlas(slot: Vector2i, count: int) -> Image:
	var image := Image.create(slot.x * count, slot.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


static func _tile_set_from(atlas: Image, slot: Vector2i, count: int) -> TileSet:
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = slot
	# Pads each tile with its own edge pixels so zoomed rendering can't
	# sample the neighboring atlas tile (a classic seam source).
	source.use_texture_padding = true
	for i in count:
		source.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_size = TILE_SIZE
	tile_set.add_source(source, SOURCE_ID)
	return tile_set


## A TILE_SIZE diamond with its top-left corner at `origin`.
static func _draw_diamond(image: Image, origin: Vector2i, base: Color, shaded: bool) -> void:
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
			image.set_pixel(origin.x + px, origin.y + py, color)
