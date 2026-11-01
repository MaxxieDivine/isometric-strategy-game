class_name GameState
extends RefCounted
## The whole game as plain data. Everything a save file needs lives here.

const VERSION := 2

var map: MapState
var turn: int = 1
## [{ "id": int, "name": String, "color": "#rrggbb", "science": int }]
var players: Array[Dictionary] = []
var units: Array[UnitState] = []
var next_unit_id: int = 1
var cities: Array[CityState] = []
var next_city_id: int = 1
## Per player: 1 byte per tile, 1 = explored. Indexed like MapState.terrain.
var explored: Array[PackedByteArray] = []
## All gameplay randomness draws from this, so saves resume deterministically.
var rng := RandomNumberGenerator.new()


# --- Players ------------------------------------------------------------------

## Adds a player and returns its id. Requires `map` to be set.
func add_player(player_name: String, color: String) -> int:
	var player_id := players.size()
	players.append({ "id": player_id, "name": player_name, "color": color, "science": 0 })
	var tiles := PackedByteArray()
	tiles.resize(map.width * map.height)
	explored.append(tiles)
	return player_id


func add_science(player_id: int, amount: int) -> void:
	players[player_id]["science"] = int(players[player_id]["science"]) + amount


func is_explored(owner: int, cell: Vector2i) -> bool:
	return explored[owner][IsoGrid.index_of(cell, map.width)] == 1


# --- Units --------------------------------------------------------------------

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


func remove_unit(unit_id: int) -> void:
	for i in units.size():
		if units[i].id == unit_id:
			units.remove_at(i)
			return


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


# --- Cities -------------------------------------------------------------------

## Founds a size-1 city (no rule checks; see CityRules.can_found).
func add_city(owner: int, cell: Vector2i) -> CityState:
	var city := CityState.new()
	city.id = next_city_id
	next_city_id += 1
	city.name = CityRules.city_name(city.id - 1)
	city.owner = owner
	city.position = cell
	cities.append(city)
	return city


func get_city(city_id: int) -> CityState:
	for city in cities:
		if city.id == city_id:
			return city
	return null


func city_at(cell: Vector2i) -> CityState:
	for city in cities:
		if city.position == cell:
			return city
	return null


## The city whose center is on `cell` or whose citizen works it, if any.
func city_using(cell: Vector2i) -> CityState:
	for city in cities:
		if city.position == cell or city.worked.has(cell):
			return city
	return null


func cities_of(owner: int) -> Array[CityState]:
	var result: Array[CityState] = []
	for city in cities:
		if city.owner == owner:
			result.append(city)
	return result


# --- Saving -------------------------------------------------------------------

func to_dict() -> Dictionary:
	var unit_data: Array = []
	for unit in units:
		unit_data.append(unit.to_dict())
	var city_data: Array = []
	for city in cities:
		city_data.append(city.to_dict())
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
		"cities": city_data,
		"next_city_id": next_city_id,
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
		state.players.append({
			"id": int(entry["id"]),
			"name": entry["name"],
			"color": entry["color"],
			"science": int(entry.get("science", 0)),
		})
	for entry: Variant in data["units"]:
		state.units.append(UnitState.from_dict(entry))
	state.next_unit_id = int(data["next_unit_id"])
	for entry: Variant in data.get("cities", []):
		state.cities.append(CityState.from_dict(entry))
	state.next_city_id = int(data.get("next_city_id", 1))
	for encoded: Variant in data["explored"]:
		state.explored.append(Marshalls.base64_to_raw(encoded))
	state.rng.seed = String(data["rng"]["seed"]).to_int()
	state.rng.state = String(data["rng"]["state"]).to_int()
	return state
