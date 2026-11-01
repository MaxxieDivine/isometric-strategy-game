class_name CityState
extends RefCounted
## One city as plain data.

var id: int = 0
var name: String = ""
var owner: int = 0
var position: Vector2i = Vector2i.ZERO
## Number of citizens.
var size: int = 1
var food_box: int = 0
## Accumulated production toward the head of the queue (leftover carries over).
var production_box: int = 0
## Item ids (units or buildings) to build, in order; the first is in progress.
var queue: Array[String] = []
## Ids of buildings this city has completed.
var buildings: Array[String] = []
## Tiles worked by citizens, excluding the center (always worked for free).
var worked: Array[Vector2i] = []
## Subset of `worked` the player placed by hand; auto-assignment keeps these.
var locked: Array[Vector2i] = []


## Citizens without a tile (when the radius has nothing left to work).
func idle_citizens() -> int:
	return maxi(0, size - worked.size())


## True when nothing is queued.
func is_idle() -> bool:
	return queue.is_empty()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"owner": owner,
		"position": [position.x, position.y],
		"size": size,
		"food_box": food_box,
		"production_box": production_box,
		"worked": _cells_to_data(worked),
		"locked": _cells_to_data(locked),
		"queue": Array(queue),
		"buildings": Array(buildings),
	}


static func from_dict(data: Dictionary) -> CityState:
	var city := CityState.new()
	city.id = int(data["id"])
	city.name = String(data["name"])
	city.owner = int(data["owner"])
	city.position = Vector2i(int(data["position"][0]), int(data["position"][1]))
	city.size = int(data["size"])
	city.food_box = int(data["food_box"])
	city.production_box = int(data["production_box"])
	city.worked = _cells_from_data(data.get("worked", []))
	city.locked = _cells_from_data(data.get("locked", []))
	city.queue = _strings_from_data(data.get("queue", []))
	city.buildings = _strings_from_data(data.get("buildings", []))
	return city


static func _strings_from_data(data: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in data:
		result.append(String(entry))
	return result


static func _cells_to_data(cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell in cells:
		result.append([cell.x, cell.y])
	return result


static func _cells_from_data(data: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pair: Variant in data:
		result.append(Vector2i(int(pair[0]), int(pair[1])))
	return result
