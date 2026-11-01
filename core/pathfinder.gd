class_name Pathfinder
extends RefCounted
## A* over the stacked isometric grid using Movement.enter_cost.

const _UNREACHED := 1 << 30


## Cheapest route from `start` to `goal`, excluding `start`.
## Returns an empty array if `goal` is unreachable or equals `start`.
static func find_path(map: MapState, explored: PackedByteArray, start: Vector2i, goal: Vector2i,
		domain: String = "land") -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if start == goal or not map.in_bounds(start) or not map.in_bounds(goal):
		return result
	if Movement.enter_cost(map, explored, goal, domain) == Movement.IMPASSABLE:
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
			var cost := Movement.enter_cost(map, explored, n, domain)
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
