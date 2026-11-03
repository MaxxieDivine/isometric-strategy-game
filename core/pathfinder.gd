class_name Pathfinder
extends RefCounted
## A* over the stacked isometric grid using Movement.enter_cost.

const _UNREACHED := 1 << 30
## Cost of a tile no route may enter, and the cost cost_map gives a tile it
## can't reach.
const BLOCKED := -1
const UNREACHED := _UNREACHED


## Cheapest route from `start` to `goal`, excluding `start`.
## Returns an empty array if `goal` is unreachable or equals `start`.
## `flat`: every passable tile costs 1 (see Movement.enter_cost).
## `extra`: optional per-tile added cost (indexed like the map; BLOCKED
## means never enter), e.g. to steer around danger.
static func find_path(map: MapState, explored: PackedByteArray, start: Vector2i, goal: Vector2i,
		domain: String = "land", flat: bool = false, extra: PackedInt32Array = PackedInt32Array()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal or not map.in_bounds(start) or not map.in_bounds(goal):
		return result
	if _step_cost(map, explored, goal, domain, flat, extra) == Movement.IMPASSABLE:
		return result

	var width := map.width
	var count := width * map.height
	var start_i := IsoGrid.index_of(start, width)
	var goal_i := IsoGrid.index_of(goal, width)
	var best := PackedInt32Array()
	best.resize(count)
	best.fill(_UNREACHED)
	var came_from := PackedInt32Array()
	came_from.resize(count)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)

	var open := MinHeap.new()
	best[start_i] = 0
	open.push(start_i, IsoGrid.step_distance(start, goal))
	while not open.is_empty():
		var i := open.pop()
		if i == goal_i:
			break
		if closed[i] == 1:
			continue
		closed[i] = 1
		for n in IsoGrid.neighbors(IsoGrid.cell_of(i, width), width, map.height):
			var j := IsoGrid.index_of(n, width)
			if closed[j] == 1:
				continue
			var cost := _step_cost(map, explored, n, domain, flat, extra)
			if cost == Movement.IMPASSABLE:
				continue
			var g := best[i] + cost
			if g < best[j]:
				best[j] = g
				came_from[j] = i
				# Every step costs at least 1, so step distance never overestimates.
				# The small tie-breaker prefers nodes closer to the goal.
				var h := IsoGrid.step_distance(n, goal)
				open.push(j, g + h + h * 0.001)

	if came_from[goal_i] == -1:
		return result
	var step := goal_i
	while step != start_i:
		result.push_front(IsoGrid.cell_of(step, width))
		step = came_from[step]
	return result


## Cheapest cost from `start` to every tile (UNREACHED where no route), in a
## Dijkstra flood with the same rules as find_path. For picking the nearest
## of many goals.
static func cost_map(map: MapState, explored: PackedByteArray, start: Vector2i, domain: String = "land",
		flat: bool = false, extra: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var width := map.width
	var best := PackedInt32Array()
	best.resize(width * map.height)
	best.fill(_UNREACHED)
	if not map.in_bounds(start):
		return best
	var closed := PackedByteArray()
	closed.resize(best.size())
	var start_i := IsoGrid.index_of(start, width)
	best[start_i] = 0
	var open := MinHeap.new()
	open.push(start_i, 0)
	while not open.is_empty():
		var i := open.pop()
		if closed[i] == 1:
			continue
		closed[i] = 1
		for n in IsoGrid.neighbors(IsoGrid.cell_of(i, width), width, map.height):
			var j := IsoGrid.index_of(n, width)
			if closed[j] == 1:
				continue
			var cost := _step_cost(map, explored, n, domain, flat, extra)
			if cost == Movement.IMPASSABLE:
				continue
			if best[i] + cost < best[j]:
				best[j] = best[i] + cost
				open.push(j, best[j])
	return best


## Route (excluding `start`) to the cheapest-to-reach tile for which
## `is_goal.call(cell)` is true; on equal cost the lowest row, then column,
## wins. Empty if none is reachable. Stops searching as soon as it finds one,
## so a nearby goal is cheap to find. Same rules as find_path.
static func nearest(map: MapState, explored: PackedByteArray, start: Vector2i, is_goal: Callable,
		domain: String = "land", flat: bool = false, extra: PackedInt32Array = PackedInt32Array()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not map.in_bounds(start):
		return result
	var width := map.width
	var count := width * map.height
	var best := PackedInt32Array()
	best.resize(count)
	best.fill(_UNREACHED)
	var came_from := PackedInt32Array()
	came_from.resize(count)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var start_i := IsoGrid.index_of(start, width)
	best[start_i] = 0
	var open := MinHeap.new()
	open.push(start_i, 0.0)
	var found := -1
	while not open.is_empty():
		var i := open.pop()
		if closed[i] == 1:
			continue
		closed[i] = 1
		var cell := IsoGrid.cell_of(i, width)
		if i != start_i and is_goal.call(cell):
			found = i
			break
		for n in IsoGrid.neighbors(cell, width, map.height):
			var j := IsoGrid.index_of(n, width)
			if closed[j] == 1:
				continue
			var cost := _step_cost(map, explored, n, domain, flat, extra)
			if cost == Movement.IMPASSABLE or best[i] + cost >= best[j]:
				continue
			best[j] = best[i] + cost
			came_from[j] = i
			# The fraction orders equal costs by tile index: row, then column.
			open.push(j, best[j] + float(j) / count)
	if found < 0:
		return result
	var step := found
	while step != start_i:
		result.push_front(IsoGrid.cell_of(step, width))
		step = came_from[step]
	return result


static func _step_cost(map: MapState, explored: PackedByteArray, cell: Vector2i, domain: String, flat: bool,
		extra: PackedInt32Array) -> int:
	var cost := Movement.enter_cost(map, explored, cell, domain, flat)
	if cost == Movement.IMPASSABLE or extra.is_empty():
		return cost
	var added := extra[IsoGrid.index_of(cell, map.width)]
	return Movement.IMPASSABLE if added == BLOCKED else cost + added
