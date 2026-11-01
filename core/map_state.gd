class_name MapState
extends RefCounted
## The world map as plain data: a width × height grid of terrain ids.
## Logical grid coordinates only — no pixels, no Nodes.

var width: int = 0
var height: int = 0
## Row-major terrain ids, index = y * width + x.
var terrain: PackedStringArray = PackedStringArray()


func _init(map_width: int = 0, map_height: int = 0, fill_id: String = "ocean") -> void:
	width = map_width
	height = map_height
	terrain.resize(width * height)
	terrain.fill(fill_id)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_terrain(cell: Vector2i) -> String:
	return terrain[cell.y * width + cell.x]


func set_terrain(cell: Vector2i, id: String) -> void:
	terrain[cell.y * width + cell.x] = id


## Builds a map from rows of terrain symbols (see data/terrain.json).
static func from_rows(rows: Array) -> MapState:
	var map_height := rows.size()
	var map_width: int = (rows[0] as String).length() if map_height > 0 else 0
	var map := MapState.new(map_width, map_height)
	for y in map_height:
		var row: String = rows[y]
		if row.length() != map_width:
			push_error("Map row %d has length %d, expected %d" % [y, row.length(), map_width])
			continue
		for x in map_width:
			map.set_terrain(Vector2i(x, y), TerrainDefs.id_for_symbol(row[x]))
	return map


func to_dict() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"terrain": Array(terrain),
	}


static func from_dict(data: Dictionary) -> MapState:
	var map := MapState.new(int(data["width"]), int(data["height"]))
	map.terrain = PackedStringArray(data["terrain"])
	return map
