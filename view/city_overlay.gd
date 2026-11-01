class_name CityOverlay
extends Node2D
## While a city panel is open: outlines the work radius, marks worked tiles,
## and shows each tile's yields (dim for unworked tiles). The city tile is
## outlined in gold; worked tiles in white (their citizens are drawn by
## TerritoryLayer).

const CENTER_COLOR := Color(1.0, 0.86, 0.4)
const WORKED_COLOR := Color(1.0, 1.0, 1.0)
const LOCK_COLOR := Color(1.0, 0.86, 0.4)
const LOCK_OFFSET := Vector2(9, -5)
const FREE_COLOR := Color(1.0, 1.0, 1.0)
const TAKEN_COLOR := Color(0.9, 0.3, 0.25)
const YIELD_OFFSET := Vector2(0, 7)

## Each tile: { pos: Vector2, yields: Vector3i, status: String }
## status: "center", "worked", "locked" (hand-placed), "free", or "taken" (another city's).
var _tiles: Array[Dictionary] = []


func show_tiles(tiles: Array[Dictionary]) -> void:
	_tiles = tiles
	queue_redraw()


func clear() -> void:
	_tiles = []
	queue_redraw()


func _draw() -> void:
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0 * 0.94
	for tile in _tiles:
		var pos: Vector2 = tile["pos"]
		var diamond := PackedVector2Array([
			pos + Vector2(0, -half.y), pos + Vector2(half.x, 0), pos + Vector2(0, half.y), pos + Vector2(-half.x, 0),
		])
		var outline := diamond.duplicate()
		outline.append(diamond[0])
		var status: String = tile["status"]
		var yield_alpha := 1.0
		match status:
			"center":
				draw_colored_polygon(diamond, Color(CENTER_COLOR, 0.15))
				draw_polyline(outline, CENTER_COLOR, 3.0)
			"worked", "locked":
				draw_colored_polygon(diamond, Color(WORKED_COLOR, 0.12))
				draw_polyline(outline, Color(WORKED_COLOR, 0.7), 1.5)
				if status == "locked":
					# Hand-placed: a small gold pin beside the citizen.
					draw_circle(pos + LOCK_OFFSET, 3.0, LOCK_COLOR)
					draw_circle(pos + LOCK_OFFSET, 3.0, Color(0, 0, 0, 0.7), false, 1.0)
			"taken":
				draw_colored_polygon(diamond, Color(TAKEN_COLOR, 0.2))
				draw_polyline(outline, Color(TAKEN_COLOR, 0.5), 1.0)
				continue
			_:
				draw_colored_polygon(diamond, Color(FREE_COLOR, 0.05))
				draw_polyline(outline, Color(FREE_COLOR, 0.25), 1.0)
				yield_alpha = 0.5
		YieldArt.draw(self, pos + YIELD_OFFSET, tile["yields"], yield_alpha)
