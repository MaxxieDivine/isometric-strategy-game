class_name CampState
extends RefCounted
## One barbarian camp as plain data.

var id: int = 0
var position: Vector2i = Vector2i.ZERO
## Turn on which the camp next spawns a unit (if under the barbarian cap).
var next_spawn_turn: int = 0
## Player ids that have seen this camp; it stays drawn for them on explored tiles.
var discovered_by: Array[int] = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"position": [position.x, position.y],
		"next_spawn_turn": next_spawn_turn,
		"discovered_by": Array(discovered_by),
	}


static func from_dict(data: Dictionary) -> CampState:
	var camp := CampState.new()
	camp.id = int(data["id"])
	camp.position = Vector2i(int(data["position"][0]), int(data["position"][1]))
	camp.next_spawn_turn = int(data["next_spawn_turn"])
	for entry: Variant in data.get("discovered_by", []):
		camp.discovered_by.append(int(entry))
	return camp
