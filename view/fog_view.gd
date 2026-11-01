class_name FogView
extends TileMapLayer
## Fog overlay: unexplored tiles are dark, explored-but-unseen tiles are dimmed.

const UNEXPLORED := Vector2i(0, 0)
const DIMMED := Vector2i(1, 0)
const UNEXPLORED_COLOR := Color(0.02, 0.025, 0.04)
const DIMMED_COLOR := Color(0.0, 0.01, 0.04, 0.5)


func _ready() -> void:
	var colors: Array[Color] = [UNEXPLORED_COLOR, DIMMED_COLOR]
	tile_set = TerrainTilesetBuilder.build_diamonds(colors, false)


func refresh(width: int, height: int, explored: PackedByteArray, visible_tiles: PackedByteArray) -> void:
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var i := IsoGrid.index_of(cell, width)
			if explored[i] == 0:
				set_cell(cell, TerrainTilesetBuilder.SOURCE_ID, UNEXPLORED)
			elif visible_tiles[i] == 0:
				set_cell(cell, TerrainTilesetBuilder.SOURCE_ID, DIMMED)
			else:
				erase_cell(cell)
