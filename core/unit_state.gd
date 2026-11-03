class_name UnitState
extends RefCounted
## One unit as plain data.

const NO_GOAL := Vector2i(-1, -1)
## home_city / camp_id value for "none".
const NONE := 0

var id: int = 0
var type: String = ""
var owner: int = 0
var position: Vector2i = Vector2i.ZERO
var moves_left: int = 0
## Destination of a multi-turn move order, or NO_GOAL.
var goal: Vector2i = NO_GOAL
## Currently planned route to `goal`, excluding the unit's own tile.
var path: Array[Vector2i] = []
## Hit points; a unit at 0 is destroyed. Set to Combat.max_hp() on creation.
var hp: int = 10
## Fortified units stay put and defend better until they move.
var fortified: bool = false
## Moved or attacked this turn (no field healing next turn).
var moved: bool = false
## City that built and supports this unit (pays upkeep), or NONE.
var home_city: int = NONE
## Barbarians: the camp that spawned this unit, or NONE.
var camp_id: int = NONE
## Barbarians: currently visible to the human player (so a sighting warns once).
var spotted: bool = false
## On auto-explore (see Exploration): moves itself each turn, needs no orders.
var exploring: bool = false
## While exploring: barbarian units and camps already in its sight when it
## last looked ("unit:<id>", "camp:<id>"), so only new ones wake it.
var explore_ignored: Array[String] = []


func max_moves() -> int:
	return UnitDefs.max_moves(type)


func has_goal() -> bool:
	return goal != NO_GOAL


func clear_orders() -> void:
	goal = NO_GOAL
	path.clear()


## True when the player still has to decide what this unit does this turn.
func needs_orders() -> bool:
	return moves_left > 0 and not has_goal() and not fortified and not exploring


## Ends auto-explore (a new order, or it woke up).
func stop_exploring() -> void:
	exploring = false
	explore_ignored.clear()


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
		"hp": hp,
		"fortified": fortified,
		"moved": moved,
		"home_city": home_city,
		"camp_id": camp_id,
		"spotted": spotted,
		"exploring": exploring,
		"explore_ignored": Array(explore_ignored),
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
	# Missing before save version 5: full health, unfortified, no home.
	unit.hp = int(data.get("hp", Combat.max_hp()))
	unit.fortified = bool(data.get("fortified", false))
	unit.moved = bool(data.get("moved", false))
	unit.home_city = int(data.get("home_city", NONE))
	unit.camp_id = int(data.get("camp_id", NONE))
	unit.spotted = bool(data.get("spotted", false))
	# Missing before save version 8: not exploring.
	unit.exploring = bool(data.get("exploring", false))
	for entry: Variant in data.get("explore_ignored", []):
		unit.explore_ignored.append(String(entry))
	return unit


static func _cell(pair: Variant) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))
