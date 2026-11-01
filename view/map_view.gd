class_name MapView
extends TileMapLayer
## Renders the terrain of explored tiles. Reads state only; never modifies it.
## The single place where grid coordinates become world (canvas) positions.

var _atlas_by_id: Dictionary = {}


func _ready() -> void:
	# Built up front: grid/world conversions need the tile set before any render.
	_ensure_tile_set()


func _ensure_tile_set() -> void:
	if tile_set != null and not _atlas_by_id.is_empty():
		return
	var defs := TerrainDefs.all()
	tile_set = TerrainTilesetBuilder.build(defs)
	for i in defs.size():
		_atlas_by_id[defs[i]["id"]] = Vector2i(i, 0)


## Draws terrain for explored tiles only, so nothing leaks through the fog.
func render(map: MapState, explored: PackedByteArray) -> void:
	_ensure_tile_set()
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var id := map.get_terrain(cell)
			if explored[IsoGrid.index_of(cell, map.width)] == 1 and _atlas_by_id.has(id):
				set_cell(cell, TerrainTilesetBuilder.SOURCE_ID, _atlas_by_id[id])
			else:
				erase_cell(cell)


func grid_to_world(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))


func world_to_grid(world_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(world_pos))


## World-space bounds of a width × height grid (whether or not tiles are drawn).
func get_grid_world_rect(width: int, height: int) -> Rect2:
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var corners: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(width - 1, 0), Vector2i(0, 1), Vector2i(width - 1, 1),
		Vector2i(0, height - 1), Vector2i(width - 1, height - 1),
		Vector2i(0, height - 2), Vector2i(width - 1, height - 2),
	]
	var rect := Rect2(grid_to_world(corners[0]) - half, half * 2.0)
	for cell in corners:
		rect = rect.merge(Rect2(grid_to_world(cell) - half, half * 2.0))
	return rect
