class_name GameState
extends RefCounted
## The whole game as plain data. Everything a save file needs lives here.

## 4: players gained `known_techs` and `research`; `science` became the
##    research store. Version 3 saves load with no techs and keep their science.
## 5: units gained hp, fortified, moved, home_city, camp_id, spotted; players
##    gained `barbarian`; barbarian camps and their timers were added. Older
##    saves get a barbarian player and full-health units on load.
## 6: wonders, score history, chronicle, game_over, turn_limit; players gained
##    `camps_destroyed`. Older saves load with no wonders, an empty history,
##    the default turn limit, and 0 camps destroyed.
## 7: `advisor` (AdvisorState: spoken triggers, cooldowns, advice log, its own
##    RNG). Older saves start with a fresh advisor that has said nothing yet.
const VERSION := 7

var map: MapState
var turn: int = 1
## [{ "id": int, "name": String, "color": "#rrggbb", "civ": String,
##    "science": int, "known_techs": Array[String], "research": String }]
## `civ` is an id in data/civs.json (border color etc.); "" for none.
## `science` is stored science toward `research` (see Research).
## `barbarian` marks the barbarian player (no cities, no research, AI moved).
## `camps_destroyed` counts barbarian camps the player cleared (for score).
var players: Array[Dictionary] = []
var units: Array[UnitState] = []
var next_unit_id: int = 1
var cities: Array[CityState] = []
var next_city_id: int = 1
## Per player: 1 byte per tile, 1 = explored. Indexed like MapState.terrain.
var explored: Array[PackedByteArray] = []
var camps: Array[CampState] = []
var next_camp_id: int = 1
## Earliest turn a new barbarian camp may appear (0 = not scheduled yet).
var next_camp_turn: int = 0
## Wonder id -> { "city_id": int, "builder": int, "turn": int } (see Wonders).
var wonders: Dictionary = {}
## [{ "turn": int, "scores": { "<player id>": int } }], one per turn (see Score).
var score_history: Array = []
## Key moments for the end screen (see Chronicle).
var chronicle: Array = []
## {} while playing; the result once the game has ended (see Victory).
var game_over: Dictionary = {}
## The game ends after this turn is played.
var turn_limit: int = 150
## All gameplay randomness draws from this, so saves resume deterministically.
var rng := RandomNumberGenerator.new()
## What the advisors have said and remember. Game rules never read it.
var advisor := AdvisorState.new()


# --- Players ------------------------------------------------------------------

## Adds a player and returns its id. Requires `map` to be set.
func add_player(player_name: String, color: String, civ: String = "", barbarian: bool = false) -> int:
	var player_id := players.size()
	players.append({ "id": player_id, "name": player_name, "color": color, "civ": civ,
		"science": 0, "known_techs": [], "research": "", "barbarian": barbarian, "camps_destroyed": 0 })
	var tiles := PackedByteArray()
	tiles.resize(map.width * map.height)
	explored.append(tiles)
	return player_id


## The barbarian player's id, or -1 if this game has none.
func barbarian_id() -> int:
	for player in players:
		if bool(player.get("barbarian", false)):
			return int(player["id"])
	return -1


## Adds the barbarian player if missing and returns its id.
func ensure_barbarian_player() -> int:
	var id := barbarian_id()
	if id >= 0:
		return id
	var civ := CivDefs.get_def(Barbarians.civ_id())
	return add_player(String(civ["name"]), String(civ["color"]), Barbarians.civ_id(), true)


func is_barbarian(player_id: int) -> bool:
	return player_id >= 0 and player_id < players.size() and bool(players[player_id].get("barbarian", false))


## Ids of players that aren't barbarians.
func civ_player_ids() -> Array[int]:
	var result: Array[int] = []
	for player in players:
		if not bool(player.get("barbarian", false)):
			result.append(int(player["id"]))
	return result


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
	unit.hp = Combat.max_hp()
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


## Units on `cell` not owned by `owner`.
func enemy_units_at(cell: Vector2i, owner: int) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in units:
		if unit.position == cell and unit.owner != owner:
			result.append(unit)
	return result


## Units whose home city is `city_id`, oldest first.
func units_supported_by(city_id: int) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for unit in units:
		if unit.home_city == city_id:
			result.append(unit)
	return result


# --- Camps --------------------------------------------------------------------

func add_camp(cell: Vector2i) -> CampState:
	var camp := CampState.new()
	camp.id = next_camp_id
	next_camp_id += 1
	camp.position = cell
	camps.append(camp)
	return camp


func camp_at(cell: Vector2i) -> CampState:
	for camp in camps:
		if camp.position == cell:
			return camp
	return null


func get_camp(camp_id: int) -> CampState:
	for camp in camps:
		if camp.id == camp_id:
			return camp
	return null


func remove_camp(camp_id: int) -> void:
	for i in camps.size():
		if camps[i].id == camp_id:
			camps.remove_at(i)
			return


## Cities of `owner` with nothing queued.
func idle_cities(owner: int) -> Array[CityState]:
	var result: Array[CityState] = []
	for city in cities:
		if city.owner == owner and city.is_idle():
			result.append(city)
	return result


# --- Saving -------------------------------------------------------------------

## Seed for the advisor's own random stream, derived from the map seed so it
## never shares a sequence with the gameplay RNG.
static func advisor_seed(map_seed: int) -> int:
	return hash("advisor:%d" % map_seed)


func to_dict() -> Dictionary:
	var unit_data: Array = []
	for unit in units:
		unit_data.append(unit.to_dict())
	var city_data: Array = []
	for city in cities:
		city_data.append(city.to_dict())
	var camp_data: Array = []
	for camp in camps:
		camp_data.append(camp.to_dict())
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
		"camps": camp_data,
		"next_camp_id": next_camp_id,
		"next_camp_turn": next_camp_turn,
		"wonders": wonders.duplicate(true),
		"score_history": score_history.duplicate(true),
		"chronicle": chronicle.duplicate(true),
		"game_over": game_over.duplicate(true),
		"turn_limit": turn_limit,
		# 64-bit values as strings: JSON numbers lose precision above 2^53.
		"rng": { "seed": str(rng.seed), "state": str(rng.state) },
		"advisor": advisor.to_dict(),
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
			"civ": String(entry.get("civ", "")),
			"science": int(entry.get("science", 0)),
			# Missing before version 4: start with no techs, nothing chosen.
			"known_techs": _strings(entry.get("known_techs", [])),
			"research": String(entry.get("research", "")),
			"barbarian": bool(entry.get("barbarian", false)),
			"camps_destroyed": int(entry.get("camps_destroyed", 0)),
		})
	for entry: Variant in data["units"]:
		state.units.append(UnitState.from_dict(entry))
	state.next_unit_id = int(data["next_unit_id"])
	for entry: Variant in data.get("cities", []):
		state.cities.append(CityState.from_dict(entry))
	state.next_city_id = int(data.get("next_city_id", 1))
	for encoded: Variant in data["explored"]:
		state.explored.append(Marshalls.base64_to_raw(encoded))
	for entry: Variant in data.get("camps", []):
		state.camps.append(CampState.from_dict(entry))
	state.next_camp_id = int(data.get("next_camp_id", 1))
	state.next_camp_turn = int(data.get("next_camp_turn", 0))
	# Missing before version 6.
	var wonder_data: Dictionary = data.get("wonders", {})
	for id: Variant in wonder_data:
		var record: Dictionary = wonder_data[id]
		state.wonders[String(id)] = { "city_id": int(record["city_id"]), "builder": int(record["builder"]),
			"turn": int(record["turn"]) }
	for entry: Variant in data.get("score_history", []):
		var raw: Dictionary = entry["scores"]
		var scores := {}
		for key: Variant in raw:
			scores[String(key)] = int(raw[key])
		state.score_history.append({ "turn": int(entry["turn"]), "scores": scores })
	for entry: Variant in data.get("chronicle", []):
		state.chronicle.append({ "turn": int(entry["turn"]), "player": int(entry["player"]),
			"type": String(entry["type"]), "name": String(entry["name"]), "city": String(entry.get("city", "")) })
	state.game_over = _game_over_from_data(data.get("game_over", {}))
	state.turn_limit = int(data.get("turn_limit", Victory.default_turn_limit()))
	state.rng.seed = String(data["rng"]["seed"]).to_int()
	state.rng.state = String(data["rng"]["state"]).to_int()
	# Missing before version 7: a fresh advisor.
	if data.has("advisor"):
		state.advisor = AdvisorState.from_dict(data["advisor"])
	else:
		state.advisor.rng.seed = advisor_seed(state.map.generation_seed)
	# Before version 5 there were no barbarians.
	if int(data.get("version", 0)) < 5:
		state.ensure_barbarian_player()
	return state


## JSON turns ints into floats; restore them so a reload is identical.
static func _game_over_from_data(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {}
	var final := {}
	var final_data: Dictionary = data.get("final", {})
	for player: Variant in final_data:
		var entry: Dictionary = final_data[player]
		var breakdown := { "total": int(entry["total"]) }
		for part in Score.PARTS:
			var item: Dictionary = entry.get(part, {})
			breakdown[part] = { "count": int(item.get("count", 0)), "points": int(item.get("points", 0)) }
		final[String(player)] = breakdown
	return { "reason": String(data["reason"]), "turn": int(data["turn"]), "winner": int(data["winner"]),
		"final": final, "continued": bool(data.get("continued", false)) }


static func _strings(data: Array) -> Array:
	var result: Array = []
	for entry: Variant in data:
		result.append(String(entry))
	return result
