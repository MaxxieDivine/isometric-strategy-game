class_name MapState
extends RefCounted
## The world map as plain data: a width × height grid of terrain ids.
## Logical grid coordinates only — no pixels, no Nodes.

var width: int = 0
var height: int = 0
## Seed the map was generated from; regenerating with it reproduces the map.
var generation_seed: int = 0
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


func to_dict() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"seed": generation_seed,
		"terrain": Array(terrain),
	}


static func from_dict(data: Dictionary) -> MapState:
	var map := MapState.new(int(data["width"]), int(data["height"]))
	map.generation_seed = int(data.get("seed", 0))
	map.terrain = PackedStringArray(data["terrain"])
	return map
