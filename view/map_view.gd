class_name MapView
extends TileMapLayer
## Renders a MapState. Reads state only; never modifies it.
## The single place where grid coordinates become screen positions.

var _atlas_by_id: Dictionary = {}


func _ensure_tile_set() -> void:
	if tile_set != null and not _atlas_by_id.is_empty():
		return
	var defs := TerrainDefs.all()
	tile_set = TerrainTilesetBuilder.build(defs)
	for i in defs.size():
		_atlas_by_id[defs[i]["id"]] = Vector2i(i, 0)


func render(map: MapState) -> void:
	_ensure_tile_set()
	clear()
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var id := map.get_terrain(cell)
			if _atlas_by_id.has(id):
				set_cell(cell, TerrainTilesetBuilder.SOURCE_ID, _atlas_by_id[id])


func grid_to_screen(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(screen_pos))


## Bounding rectangle of all drawn tiles, in this layer's local space.
func get_map_pixel_rect() -> Rect2:
	var cells := get_used_cells()
	if cells.is_empty():
		return Rect2()
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var rect := Rect2(map_to_local(cells[0]) - half, half * 2.0)
	for cell in cells:
		rect = rect.merge(Rect2(map_to_local(cell) - half, half * 2.0))
	return rect
