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
##   city_built       { city_id, item, unit_id? }   (unit_id when a unit was built)
##   city_idle        { city_id }   (its queue just ran out)
##   city_queue_changed { city_id }
##   build_failed     { city_id, reason }
##   research_set     { player, tech, auto }   (auto: picked for an undecided player)
##   research_failed  { player, reason }
##   tech_discovered  { player, tech }
##   unit_fortified   { unit_id }
##   combat           { attacker_id, defender_id, winner, ... }   (see Combat.resolve)
##   unit_disbanded   { unit_id, unit_type, city_id }   (upkeep the city couldn't pay)
##   camp_spawned     { camp_id, cell }
##   camp_discovered  { player, camp_id, cell }
##   camp_destroyed   { camp_id, cell, player, reward, amount, city_id }
##   barbarian_spawned { unit_id, camp_id }
##   barbarians_spotted { player, unit_id, cell, city_id }
##   city_sacked      { city_id, unit_id, size, production_lost }
##   wonder_built     { city_id, item, wonder, player, turn }   (instead of city_built)
##   wonder_lost      { city_id, wonder, by_player, by_city_id, kept }   (completed
##                    elsewhere; the city keeps `kept` stored production)
##   turns_remaining  { turns }   (countdown milestones near the turn limit)
##   game_over        { reason, winner }   (see Victory)
##   game_continued   {}   (Keep Playing)
##   turn_started     { turn }   (the rest of the turn's events follow it)


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
	unit.fortified = false
	var path := _plan(state, unit, goal)
	if path.is_empty():
		events.append({ "type": "move_failed", "unit_id": unit_id, "goal": goal })
		return events
	unit.goal = goal
	unit.path = path
	events.append_array(_advance(state, unit))
	events.append_array(_sightings(state))
	Chronicle.record(state, events)
	return events


## The unit digs in: it stays put (no orders needed each turn) and defends
## better until it moves again.
static func fortify_unit(state: GameState, unit_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var unit := state.get_unit(unit_id)
	if unit == null:
		return events
	unit.clear_orders()
	unit.fortified = true
	unit.moves_left = 0
	events.append({ "type": "unit_fortified", "unit_id": unit_id })
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
	events.append_array(_sightings(state))
	Chronicle.record(state, events)
	return events


## Moves a citizen onto `cell`, or frees the citizen already working it.
static func toggle_worked_tile(state: GameState, city_id: int, cell: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var city := state.get_city(city_id)
	if city != null and CityRules.toggle_worked_tile(state, city, cell):
		events.append({ "type": "city_tiles_changed", "city_id": city_id })
	return events


## Adds `item_id` (a unit or building id) to the end of the city's queue.
static func enqueue_build(state: GameState, city_id: int, item_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var city := state.get_city(city_id)
	if city == null:
		return events
	var reason := Production.can_enqueue(state, city, item_id)
	if reason != "":
		events.append({ "type": "build_failed", "city_id": city_id, "reason": reason })
		return events
	city.queue.append(item_id)
	events.append({ "type": "city_queue_changed", "city_id": city_id })
	return events


## Removes the queue entry at `index`. Stored production stays in the box.
static func remove_from_queue(state: GameState, city_id: int, index: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var city := state.get_city(city_id)
	if city == null or index < 0 or index >= city.queue.size():
		return events
	city.queue.remove_at(index)
	events.append({ "type": "city_queue_changed", "city_id": city_id })
	return events


## Chooses what the player researches. Stored science is kept on a switch.
static func set_research(state: GameState, player_id: int, tech_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var reason := Research.can_research(state, player_id, tech_id)
	if reason != "":
		events.append({ "type": "research_failed", "player": player_id, "reason": reason })
		return events
	Research.set_research(state, player_id, tech_id)
	events.append({ "type": "research_set", "player": player_id, "tech": tech_id, "auto": false })
	return events


## For a player who hasn't chosen: researches the cheapest available tech.
## Does nothing if research is already set or nothing is left.
static func auto_pick_research(state: GameState, player_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if Research.current(state, player_id) != "":
		return events
	var tech := Research.cheapest_available(state, player_id)
	if tech != "":
		Research.set_research(state, player_id, tech)
		events.append({ "type": "research_set", "player": player_id, "tech": tech, "auto": true })
	return events


## Starts the next turn: undecided players get research auto-picked, cities
## grow and bank yields and science, discoveries are made, units get their
## moves back, then units with orders keep moving. Finally the score is
## recorded and the game may end (turn limit or Wonder Victory).
static func end_turn(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	state.turn += 1
	events.append({ "type": "turn_started", "turn": state.turn })
	# Barbarians move between the player's turns, with last turn's moves.
	events.append_array(Barbarians.act(state))
	for player_id in state.civ_player_ids():
		events.append_array(auto_pick_research(state, player_id))
	for city in state.cities:
		events.append_array(CityRules.process_turn(state, city))
	for player_id in state.civ_player_ids():
		events.append_array(Research.process(state, player_id))
	for unit in state.units:
		Combat.heal(state, unit)
		unit.moved = false
		unit.moves_left = unit.max_moves()
	events.append_array(Barbarians.spawn(state))
	for unit in state.units:
		if unit.has_goal():
			events.append_array(_advance(state, unit))
	events.append_array(_sightings(state))
	Score.record(state)
	events.append_array(Victory.check(state))
	Chronicle.record(state, events)
	return events


## After the game has ended: keep playing with the score frozen.
static func keep_playing(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if Victory.is_over(state) and not Victory.is_continued(state):
		Victory.continue_game(state)
		events.append({ "type": "game_continued" })
	return events


static func _sightings(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for player_id in state.civ_player_ids():
		events.append_array(Barbarians.update_sightings(state, player_id))
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
		if not state.enemy_units_at(next, unit.owner).is_empty():
			# Bumping into an enemy: attack it if that was the order, else stop.
			if next == unit.goal and Combat.can_attack(unit):
				events.append(Combat.resolve(state, unit, Combat.best_defender(state, next, unit)))
			else:
				unit.clear_orders()
				events.append({ "type": "orders_cancelled", "unit_id": unit.id })
			break
		var cost := Movement.enter_cost(state.map, state.explored[unit.owner], next, domain)
		if not Movement.can_enter(unit.moves_left, unit.max_moves(), cost):
			break
		var from := unit.position
		unit.position = next
		unit.moves_left = maxi(0, unit.moves_left - cost)
		unit.path.remove_at(0)
		unit.moved = true
		var revealed := Fog.reveal_around(state, unit.owner, next)
		events.append({ "type": "unit_moved", "unit_id": unit.id, "from": from, "to": next, "revealed": revealed })
		var camp := state.camp_at(next)
		if camp != null and not state.is_barbarian(unit.owner):
			events.append_array(Barbarians.destroy_camp(state, unit, camp))
		if unit.position == unit.goal:
			unit.clear_orders()
	return events
