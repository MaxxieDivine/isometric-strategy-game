class_name IsoGrid
extends RefCounted
## Grid math for the isometric "stacked" layout: odd rows are shifted half a
## tile to the right, and each row sits half a tile below the previous one.
## Logical grid only — pixel projection lives in MapView.

## The 4 edge-sharing (diagonal-on-screen) neighbors, for even and odd rows.
const _EDGE_EVEN: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 1), Vector2i(0, 1)]
const _EDGE_ODD: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, 1), Vector2i(1, 1)]
## The 4 corner-sharing neighbors (straight left/right/up/down on screen).
const _CORNER: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -2), Vector2i(0, 2)]


## All 8 in-bounds neighbors of a cell.
static func neighbors(cell: Vector2i, width: int, height: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var edge := _EDGE_ODD if cell.y % 2 == 1 else _EDGE_EVEN
	for offset: Vector2i in edge + _CORNER:
		var n := cell + offset
		if n.x >= 0 and n.y >= 0 and n.x < width and n.y < height:
			result.append(n)
	return result


## Number of single steps (to any of the 8 neighbors) between two cells.
static func step_distance(a: Vector2i, b: Vector2i) -> int:
	var da := _diamond(b) - _diamond(a)
	return maxi(absi(da.x), absi(da.y))


## All in-bounds cells within `radius` steps of `center` (including it).
static func cells_within(center: Vector2i, radius: int, width: int, height: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(maxi(0, center.y - 2 * radius), mini(height, center.y + 2 * radius + 1)):
		for x in range(maxi(0, center.x - radius - 1), mini(width, center.x + radius + 2)):
			var cell := Vector2i(x, y)
			if step_distance(center, cell) <= radius:
				result.append(cell)
	return result


## Position of a cell's center on the undistorted ground plane, in tile units.
## Use this for distances and noise sampling so shapes aren't squashed.
static func ground_position(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5 + 0.5 * (cell.y % 2), 0.5 + cell.y * 0.5)


## Size of the whole map on the ground plane, in tile units.
static func ground_size(width: int, height: int) -> Vector2:
	return Vector2(width + 0.5, (height + 1) * 0.5)


static func index_of(cell: Vector2i, width: int) -> int:
	return cell.y * width + cell.x


static func cell_of(index: int, width: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % width, index / width)


## Diamond-axis coordinates: each step changes u and/or v by at most 1,
## so step distance is the Chebyshev distance in (u, v). Valid for y >= 0.
static func _diamond(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + ((cell.y + 1) >> 1), cell.x - (cell.y >> 1))
