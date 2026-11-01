class_name GameActions
extends RefCounted
## The commands the UI can issue. Each one changes GameState and returns a
## list of events ({ "type": ..., ... }) that the view turns into animation.
##
## Event types:
##   unit_moved       { unit_id, from, to, revealed }
##   move_failed      { unit_id, goal }
##   orders_cancelled { unit_id }
##   unit_skipped     { unit_id }
##   unit_removed     { unit_id }
##   found_failed     { unit_id, reason }
##   city_founded     { city_id }
##   city_tiles_changed { city_id }
##   city_grew        { city_id, size }
##   city_shrank      { city_id, size }
##   city_starving    { city_id }
##   turn_started     { turn }   (city events of the new turn follow it)


## Orders a unit to go to `goal`. It moves as far as it can now and keeps
## going on later turns.
static func move_unit(state: GameState, unit_id: int, goal: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var unit := state.get_unit(unit_id)
	if unit == null:
		return events
	if goal == unit.position:
		unit.clear_orders()
		return events
	var path := _plan(state, unit, goal)
	if path.is_empty():
		events.append({ "type": "move_failed", "unit_id": unit_id, "goal": goal })
		return events
	unit.goal = goal
	unit.path = path
	events.append_array(_advance(state, unit))
	return events


## The unit does nothing more this turn (keeps any multi-turn orders).
static func skip_unit(state: GameState, unit_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var unit := state.get_unit(unit_id)
	if unit != null:
		unit.moves_left = 0
		events.append({ "type": "unit_skipped", "unit_id": unit_id })
	return events


## The settler founds a city where it stands and is consumed.
static func found_city(state: GameState, unit_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var unit := state.get_unit(unit_id)
	if unit == null:
		return events
	var reason := CityRules.can_found(state, unit)
	if reason != "":
		events.append({ "type": "found_failed", "unit_id": unit_id, "reason": reason })
		return events
	var city := state.add_city(unit.owner, unit.position)
	state.remove_unit(unit_id)
	Fog.reveal_radius(state, city.owner, city.position, CityRules.sight_radius())
	CityRules.auto_assign(state, city)
	events.append({ "type": "unit_removed", "unit_id": unit_id })
	events.append({ "type": "city_founded", "city_id": city.id })
	return events


## Moves a citizen onto `cell`, or frees the citizen already working it.
static func toggle_worked_tile(state: GameState, city_id: int, cell: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var city := state.get_city(city_id)
	if city != null and CityRules.toggle_worked_tile(state, city, cell):
		events.append({ "type": "city_tiles_changed", "city_id": city_id })
	return events


## Starts the next turn: cities grow and bank yields, units get their moves
## back, then units with orders keep moving.
static func end_turn(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.turn += 1
	events.append({ "type": "turn_started", "turn": state.turn })
	for city in state.cities:
		events.append_array(CityRules.process_turn(state, city))
	for unit in state.units:
		unit.moves_left = unit.max_moves()
	for unit in state.units:
		if unit.has_goal():
			events.append_array(_advance(state, unit))
	return events


static func _plan(state: GameState, unit: UnitState, goal: Vector2i) -> Array[Vector2i]:
	return Pathfinder.find_path(state.map, state.explored[unit.owner], unit.position, goal,
		UnitDefs.domain(unit.type))


## Steps the unit along its route while it has moves. The route is re-planned
## each step, because moving reveals terrain that may change the best path.
static func _advance(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var domain := UnitDefs.domain(unit.type)
	while unit.has_goal() and unit.moves_left > 0:
		var path := _plan(state, unit, unit.goal)
		if path.is_empty():
			unit.clear_orders()
			events.append({ "type": "orders_cancelled", "unit_id": unit.id })
			break
		unit.path = path
		var next := path[0]
		var cost := Movement.enter_cost(state.map, state.explored[unit.owner], next, domain)
		if not Movement.can_enter(unit.moves_left, unit.max_moves(), cost):
			break
		var from := unit.position
		unit.position = next
		unit.moves_left = maxi(0, unit.moves_left - cost)
		unit.path.remove_at(0)
		var revealed := Fog.reveal_around(state, unit.owner, next)
		events.append({ "type": "unit_moved", "unit_id": unit.id, "from": from, "to": next, "revealed": revealed })
		if unit.position == unit.goal:
			unit.clear_orders()
	return events
