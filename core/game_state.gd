class_name GameState
extends RefCounted
## The whole game as plain data. Everything a save file needs lives here.

const VERSION := 1

var map: MapState
var turn: int = 1
## [{ "id": int, "name": String, "color": "#rrggbb" }]
var players: Array[Dictionary] = []
var units: Array[UnitState] = []
var next_unit_id: int = 1
## Per player: 1 byte per tile, 1 = explored. Indexed like MapState.terrain.
var explored: Array[PackedByteArray] = []
## All gameplay randomness draws from this, so saves resume deterministically.
var rng := RandomNumberGenerator.new()


## Adds a player and returns its id. Requires `map` to be set.
func add_player(player_name: String, color: String) -> int:
	var player_id := players.size()
	players.append({ "id": player_id, "name": player_name, "color": color })
	var tiles := PackedByteArray()
	tiles.resize(map.width * map.height)
	explored.append(tiles)
	return player_id


func add_unit(type: String, owner: int, cell: Vector2i) -> UnitState:
	var unit := UnitState.new()
	unit.id = next_unit_id
	next_unit_id += 1
	unit.type = type
	unit.owner = owner
	unit.position = cell
	unit.moves_left = UnitDefs.max_moves(type)
	units.append(unit)
	return unit


func get_unit(unit_id: int) -> UnitState:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


## Units on a tile, optionally only those of one owner (owner < 0 = everyone).
func units_at(cell: Vector2i, owner: int = -1) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in units:
		if unit.position == cell and (owner < 0 or unit.owner == owner):
			result.append(unit)
	return result


func units_of(owner: int) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in units:
		if unit.owner == owner:
			result.append(unit)
	return result


## Units still waiting for the player's orders this turn, in id order.
func units_needing_orders(owner: int) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in units:
		if unit.owner == owner and unit.needs_orders():
			result.append(unit)
	return result


func is_explored(owner: int, cell: Vector2i) -> bool:
	return explored[owner][IsoGrid.index_of(cell, map.width)] == 1


func to_dict() -> Dictionary:
	var unit_data: Array = []
	for unit in units:
		unit_data.append(unit.to_dict())
	var explored_data: Array = []
	for tiles in explored:
		explored_data.append(Marshalls.raw_to_base64(tiles))
	return {
		"version": VERSION,
		"turn": turn,
		"map": map.to_dict(),
		"players": players.duplicate(true),
		"units": unit_data,
		"next_unit_id": next_unit_id,
		"explored": explored_data,
		# 64-bit values as strings: JSON numbers lose precision above 2^53.
		"rng": { "seed": str(rng.seed), "state": str(rng.state) },
	}


static func from_dict(data: Dictionary) -> GameState:
	var state := GameState.new()
	state.turn = int(data["turn"])
	state.map = MapState.from_dict(data["map"])
	for player: Variant in data["players"]:
		var entry: Dictionary = player
		state.players.append({ "id": int(entry["id"]), "name": entry["name"], "color": entry["color"] })
	for entry: Variant in data["units"]:
		state.units.append(UnitState.from_dict(entry))
	state.next_unit_id = int(data["next_unit_id"])
	for encoded: Variant in data["explored"]:
		state.explored.append(Marshalls.base64_to_raw(encoded))
	state.rng.seed = String(data["rng"]["seed"]).to_int()
	state.rng.state = String(data["rng"]["state"]).to_int()
	return state
