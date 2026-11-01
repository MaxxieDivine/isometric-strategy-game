class_name UnitState
extends RefCounted
## One unit as plain data.

const NO_GOAL := Vector2i(-1, -1)

var id: int = 0
var type: String = ""
var owner: int = 0
var position: Vector2i = Vector2i.ZERO
var moves_left: int = 0
## Destination of a multi-turn move order, or NO_GOAL.
var goal: Vector2i = NO_GOAL
## Currently planned route to `goal`, excluding the unit's own tile.
var path: Array[Vector2i] = []


func max_moves() -> int:
	return UnitDefs.max_moves(type)


func has_goal() -> bool:
	return goal != NO_GOAL


func clear_orders() -> void:
	goal = NO_GOAL
	path.clear()


## True when the player still has to decide what this unit does this turn.
func needs_orders() -> bool:
	return moves_left > 0 and not has_goal()


func to_dict() -> Dictionary:
	var path_data: Array = []
	for cell in path:
		path_data.append([cell.x, cell.y])
	return {
		"id": id,
		"type": type,
		"owner": owner,
		"position": [position.x, position.y],
		"moves_left": moves_left,
		"goal": [goal.x, goal.y],
		"path": path_data,
	}


static func from_dict(data: Dictionary) -> UnitState:
	var unit := UnitState.new()
	unit.id = int(data["id"])
	unit.type = String(data["type"])
	unit.owner = int(data["owner"])
	unit.position = _cell(data["position"])
	unit.moves_left = int(data["moves_left"])
	unit.goal = _cell(data.get("goal", [-1, -1]))
	for entry: Variant in data.get("path", []):
		unit.path.append(_cell(entry))
	return unit


static func _cell(pair: Variant) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))
