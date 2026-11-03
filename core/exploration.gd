class_name Exploration
extends RefCounted
## Auto-explore: a unit heads for the nearest reachable frontier tile (known
## land next to the unknown), re-planning every step, until nothing reachable
## is left to see. Shared logic: the player's exploring units use it, and
## rival AI can call next_target for its own scouts.
##
## Deterministic and RNG-free: targets are chosen by path cost, then row,
## then column. Steers around known barbarian camps and visible barbarian
## units, never attacks, and stops (waking the unit) when it has finished,
## when new barbarians come into its sight, or when it is badly hurt.
## Numbers come from data/exploration.json.

const PATH := "res://data/exploration.json"
const NO_TARGET := Vector2i(-1, -1)
## Why a unit stopped exploring (explore_stopped events).
const FINISHED := "finished"
const BARBARIANS := "barbarians"
const HURT := "hurt"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


## Extra path cost for a tile next to a visible barbarian unit.
static func danger_step_cost() -> int:
	return int(rules().get("danger_step_cost", 6))


static func stop_below_hp_percent() -> int:
	return int(rules().get("stop_below_hp_percent", 50))


static func can_explore(unit: UnitState) -> bool:
	return UnitDefs.domain(unit.type) == "land"


static func is_hurt(unit: UnitState) -> bool:
	return unit.hp * 100 < Combat.max_hp() * stop_below_hp_percent()


## Known land (for land units) with at least one unexplored neighbor.
static func is_frontier(state: GameState, player_id: int, cell: Vector2i) -> bool:
	if not state.is_explored(player_id, cell) or not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
		return false
	for other in IsoGrid.neighbors(cell, state.map.width, state.map.height):
		if not state.is_explored(player_id, other):
			return true
	return false


## Per-tile added path cost for `player_id`'s explorers (Pathfinder `extra`):
## known or visible camps and visible barbarian units are BLOCKED, and tiles
## next to a visible barbarian unit cost danger_step_cost more. Empty when
## there is nothing to avoid.
static func danger_costs(state: GameState, player_id: int) -> PackedInt32Array:
	var map := state.map
	var visible := Fog.compute_visible(state, player_id)
	var costs := PackedInt32Array()
	costs.resize(map.width * map.height)
	var any := false
	for camp in state.camps:
		var i := IsoGrid.index_of(camp.position, map.width)
		if camp.discovered_by.has(player_id) or visible[i] == 1:
			costs[i] = Pathfinder.BLOCKED
			any = true
	for unit in state.units:
		if not state.is_barbarian(unit.owner) or visible[IsoGrid.index_of(unit.position, map.width)] == 0:
			continue
		any = true
		costs[IsoGrid.index_of(unit.position, map.width)] = Pathfinder.BLOCKED
		for cell in IsoGrid.neighbors(unit.position, map.width, map.height):
			var j := IsoGrid.index_of(cell, map.width)
			if costs[j] != Pathfinder.BLOCKED:
				costs[j] += danger_step_cost()
	return costs if any else PackedInt32Array()


## The frontier tile `unit` should head for, or NO_TARGET when none is
## reachable. Safe tiles (not next to a visible barbarian) win over unsafe
## ones; then the cheapest route; then the lowest row and column.
static func next_target(state: GameState, unit: UnitState, extra: PackedInt32Array = PackedInt32Array()) -> Vector2i:
	var route := next_route(state, unit, extra)
	return route.back() if not route.is_empty() else NO_TARGET


## The route to next_target (excluding the unit's tile), or empty.
static func next_route(state: GameState, unit: UnitState, extra: PackedInt32Array = PackedInt32Array()) -> Array[Vector2i]:
	if extra.is_empty():
		extra = danger_costs(state, unit.owner)
	var map := state.map
	var explored := state.explored[unit.owner]
	var domain := UnitDefs.domain(unit.type)
	var flat := UnitDefs.ignores_terrain(unit.type)
	var owner := unit.owner
	var safe_frontier := func(cell: Vector2i) -> bool:
		return is_frontier(state, owner, cell) and not _is_danger(extra, map, cell)
	var route := Pathfinder.nearest(map, explored, unit.position, safe_frontier, domain, flat, extra)
	if route.is_empty() and not extra.is_empty():
		# Nothing safe left: settle for frontier next to danger.
		var any_frontier := func(cell: Vector2i) -> bool: return is_frontier(state, owner, cell)
		route = Pathfinder.nearest(map, explored, unit.position, any_frontier, domain, flat, extra)
	return route


## Barbarian units and camps within `unit`'s sight ("unit:<id>", "camp:<id>").
static func threats_in_sight(state: GameState, unit: UnitState) -> Array[String]:
	var result: Array[String] = []
	var radius := Fog.sight_radius(state.map, unit.position, unit.type)
	for other in state.units:
		if state.is_barbarian(other.owner) and IsoGrid.step_distance(unit.position, other.position) <= radius:
			result.append("unit:%d" % other.id)
	for camp in state.camps:
		if IsoGrid.step_distance(unit.position, camp.position) <= radius:
			result.append("camp:%d" % camp.id)
	return result


## Starts auto-explore. Threats already in sight are noted, so only new ones
## wake the unit. It moves at once with the moves it has left.
static func start(state: GameState, unit: UnitState) -> Array[Dictionary]:
	unit.clear_orders()
	unit.fortified = false
	unit.exploring = true
	unit.explore_ignored = threats_in_sight(state, unit)
	var events: Array[Dictionary] = [{ "type": "unit_exploring", "unit_id": unit.id }]
	events.append_array(explore(state, unit, false))
	return events


## Spends the exploring unit's moves. `turn_start`: new barbarians that came
## into sight since last turn wake it before it moves.
static func explore(state: GameState, unit: UnitState, turn_start: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not unit.exploring:
		return events
	if is_hurt(unit):
		events.append(_stop(unit, HURT))
		return events
	if turn_start and _spotted_new_threat(state, unit):
		events.append(_stop(unit, BARBARIANS))
		return events
	while unit.moves_left > 0:
		var extra := danger_costs(state, unit.owner)
		var path := next_route(state, unit, extra)
		if path.is_empty():
			events.append(_stop(unit, FINISHED))
			break
		var next := path[0]
		var city := state.city_at(next)
		if not state.enemy_units_at(next, unit.owner).is_empty() or (city != null and city.owner != unit.owner):
			# Explorers never attack: wait for the way to clear.
			break
		var cost := Movement.unit_enter_cost(state.map, state.explored[unit.owner], next, unit.type)
		if not Movement.can_enter(unit.moves_left, unit.max_moves(), cost):
			break
		# Don't end the move next to visible barbarians if staying put is safe.
		if unit.moves_left - cost <= 0 and _is_danger(extra, state.map, next) \
				and not _is_danger(extra, state.map, unit.position):
			break
		events.append_array(GameActions.step_unit(state, unit, next, cost))
		if _spotted_new_threat(state, unit):
			events.append(_stop(unit, BARBARIANS))
			break
	return events


## True if a barbarian unit or camp not in sight before is in sight now.
## Forgets threats that have left its sight, so they wake it if they return.
static func _spotted_new_threat(state: GameState, unit: UnitState) -> bool:
	var now := threats_in_sight(state, unit)
	var spotted := false
	var kept: Array[String] = []
	for id in now:
		if unit.explore_ignored.has(id):
			kept.append(id)
		else:
			spotted = true
	unit.explore_ignored = kept
	return spotted


static func _is_danger(extra: PackedInt32Array, map: MapState, cell: Vector2i) -> bool:
	return not extra.is_empty() and extra[IsoGrid.index_of(cell, map.width)] != 0


static func _stop(unit: UnitState, reason: String) -> Dictionary:
	unit.stop_exploring()
	return { "type": "explore_stopped", "unit_id": unit.id, "unit_type": unit.type, "reason": reason,
		"cell": unit.position }
