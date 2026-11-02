class_name Barbarians
extends RefCounted
## Barbarian rules: camps appearing, camps spawning units, the barbarian AI,
## city sacking, sightings, and the reward for destroying a camp.
## Numbers come from data/barbarians.json. Barbarians are a player flagged
## `barbarian`; they know the whole map (no fog for their pathfinding).

const PATH := "res://data/barbarians.json"
static var _rules: Dictionary = {}
## An empty explored array means "everything known" to Movement/Pathfinder.
static var ALL_KNOWN := PackedByteArray()


# --- Data ---------------------------------------------------------------------

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


static func civ_id() -> String:
	return String(rules().get("civ", "barbarians"))


static func start_turn() -> int:
	return int(rules().get("start_turn", 15))


static func camp_sprite() -> String:
	return String(rules().get("camp_sprite", "barbarian_camp"))


static func aggro_range() -> int:
	return int(rules().get("aggro_range", 6))


static func wander_radius() -> int:
	return int(rules().get("wander_radius", 3))


static func camp_min_city_distance() -> int:
	return int(rules().get("camp_min_city_distance", 8))


## Camps prefer sites no farther than this from some city (when any exist),
## so they threaten the player instead of appearing at the far end of the map.
static func camp_preferred_max_city_distance() -> int:
	return int(rules().get("camp_preferred_max_city_distance", 12))


static func camp_min_camp_distance() -> int:
	return int(rules().get("camp_min_camp_distance", 5))


## The entry of a staged list ("camp_stages", "unit_stages", "unit_types")
## in effect on `turn`: the last one whose from_turn has been reached.
static func stage(key: String, turn: int) -> Dictionary:
	var result: Dictionary = {}
	for entry: Variant in rules().get(key, []):
		var stage_def: Dictionary = entry
		if turn >= int(stage_def.get("from_turn", 0)):
			result = stage_def
	return result


static func unit_types(turn: int) -> Array[String]:
	var result: Array[String] = []
	for id: Variant in stage("unit_types", turn).get("types", ["warrior"]):
		result.append(String(id))
	return result


static func max_units(turn: int) -> int:
	return int(stage("unit_stages", turn).get("max_units", 0))


static func max_camps(turn: int) -> int:
	return int(stage("camp_stages", turn).get("max_camps", 0))


# --- Camps --------------------------------------------------------------------

## Empty string if a camp may appear on `cell`, else why not. `seen` marks
## tiles any civ player can see right now.
static func camp_site_problem(state: GameState, cell: Vector2i, seen: PackedByteArray) -> String:
	if not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
		return "water"
	if seen[IsoGrid.index_of(cell, state.map.width)] == 1:
		return "visible"
	for city in state.cities:
		if IsoGrid.step_distance(city.position, cell) < camp_min_city_distance():
			return "near a city"
	for camp in state.camps:
		if IsoGrid.step_distance(camp.position, cell) < camp_min_camp_distance():
			return "near a camp"
	if not state.units_at(cell).is_empty():
		return "occupied"
	return ""


## Tiles any civ (non-barbarian) player can currently see.
static func seen_by_civs(state: GameState) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(state.map.width * state.map.height)
	for player_id in state.civ_player_ids():
		var visible := Fog.compute_visible(state, player_id)
		for i in seen.size():
			seen[i] = seen[i] | visible[i]
	return seen


static func barbarian_units(state: GameState) -> Array[UnitState]:
	var id := state.barbarian_id()
	return state.units_of(id) if id >= 0 else ([] as Array[UnitState])


## Start-of-turn spawning: maybe a new camp, then units from camps that are due.
static func spawn(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var barbarian := state.barbarian_id()
	if barbarian < 0 or state.turn < start_turn():
		return events
	if state.next_camp_turn == 0:
		state.next_camp_turn = start_turn()
	if state.turn >= state.next_camp_turn:
		var every := int(stage("camp_stages", state.turn).get("every", 10))
		if state.camps.size() >= max_camps(state.turn):
			state.next_camp_turn = state.turn + every
		else:
			var camp := _place_camp(state)
			if camp == null:
				state.next_camp_turn = state.turn + 1  # No room right now; try again next turn.
			else:
				state.next_camp_turn = state.turn + every
				camp.next_spawn_turn = state.turn
				events.append({ "type": "camp_spawned", "camp_id": camp.id, "cell": camp.position })
	for camp in state.camps:
		if state.turn < camp.next_spawn_turn:
			continue
		camp.next_spawn_turn = state.turn + int(stage("unit_stages", state.turn).get("every", 10))
		if barbarian_units(state).size() >= max_units(state.turn):
			continue
		var types := unit_types(state.turn)
		var unit := state.add_unit(types[state.rng.randi_range(0, types.size() - 1)], barbarian, camp.position)
		unit.camp_id = camp.id
		events.append({ "type": "barbarian_spawned", "unit_id": unit.id, "camp_id": camp.id })
	return events


static func _place_camp(state: GameState) -> CampState:
	var seen := seen_by_civs(state)
	var sites: Array[Vector2i] = []
	var near: Array[Vector2i] = []
	for y in state.map.height:
		for x in state.map.width:
			var cell := Vector2i(x, y)
			if camp_site_problem(state, cell, seen) != "":
				continue
			sites.append(cell)
			if _distance_to_nearest_city(state, cell) <= camp_preferred_max_city_distance():
				near.append(cell)
	var pool := near if not near.is_empty() else sites
	if pool.is_empty():
		return null
	return state.add_camp(pool[state.rng.randi_range(0, pool.size() - 1)])


## Steps to the nearest city of anyone, or a huge number if there are none.
static func _distance_to_nearest_city(state: GameState, cell: Vector2i) -> int:
	var best := 1 << 20
	for city in state.cities:
		best = mini(best, IsoGrid.step_distance(city.position, cell))
	return best


## A civ unit walked into an empty camp: it's destroyed and pays out
## production to the nearest city or science, chosen at random.
static func destroy_camp(state: GameState, unit: UnitState, camp: CampState) -> Array[Dictionary]:
	var reward: Dictionary = rules().get("camp_reward", {})
	var event := { "type": "camp_destroyed", "camp_id": camp.id, "cell": camp.position, "player": unit.owner, "city_id": 0 }
	state.remove_camp(camp.id)
	state.players[unit.owner]["camps_destroyed"] = int(state.players[unit.owner].get("camps_destroyed", 0)) + 1
	var city := _nearest_city(state, unit.owner, camp.position)
	if state.rng.randi_range(0, 1) == 0 and city != null:
		event["reward"] = "production"
		event["amount"] = int(reward.get("production", 25))
		event["city_id"] = city.id
		city.production_box += int(event["amount"])
	else:
		event["reward"] = "science"
		event["amount"] = int(reward.get("science", 25))
		state.add_science(unit.owner, int(event["amount"]))
	var events: Array[Dictionary] = [event]
	return events


static func _nearest_city(state: GameState, owner: int, cell: Vector2i) -> CityState:
	var best: CityState = null
	for city in state.cities_of(owner):
		if best == null or IsoGrid.step_distance(city.position, cell) < IsoGrid.step_distance(best.position, cell):
			best = city
	return best


# --- AI -----------------------------------------------------------------------

## Moves every barbarian: toward the nearest civ unit or city within aggro
## range (attacking when it bumps into one), otherwise wandering near its camp.
static func act(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for unit in barbarian_units(state):
		if state.get_unit(unit.id) == null:
			continue  # Died earlier this phase.
		events.append_array(_act_unit(state, unit))
	return events


## The civ unit or city tile nearest to `unit` within aggro range, or (-1, -1).
static func find_target(state: GameState, unit: UnitState) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := aggro_range() + 1
	for other in state.units:
		if state.is_barbarian(other.owner):
			continue
		var distance := IsoGrid.step_distance(unit.position, other.position)
		if distance < best_distance:
			best = other.position
			best_distance = distance
	for city in state.cities:
		if state.is_barbarian(city.owner):
			continue
		var distance := IsoGrid.step_distance(unit.position, city.position)
		if distance < best_distance:
			best = city.position
			best_distance = distance
	return best


static func _act_unit(state: GameState, unit: UnitState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var guard := 0
	while unit.moves_left > 0 and guard < 8:
		guard += 1
		var target := find_target(state, unit)
		var next := Vector2i(-1, -1)
		if target != Vector2i(-1, -1):
			if IsoGrid.step_distance(unit.position, target) == 1:
				next = target
			else:
				var path := Pathfinder.find_path(state.map, ALL_KNOWN, unit.position, target)
				if not path.is_empty():
					next = path[0]
		if next == Vector2i(-1, -1):
			next = _wander_step(state, unit)
			if next == Vector2i(-1, -1):
				break
			events.append_array(_step(state, unit, next))
			break  # Wandering is one step a turn.
		events.append_array(_step(state, unit, next))
		if state.get_unit(unit.id) == null:
			break
	return events


## Moves into `cell`, attacking whatever civ unit is there, or sacking an
## undefended civ city.
static func _step(state: GameState, unit: UnitState, cell: Vector2i) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var defender := Combat.best_defender(state, cell, unit)
	if defender != null:
		events.append(Combat.resolve(state, unit, defender))
		return events
	var cost := Movement.enter_cost(state.map, ALL_KNOWN, cell, UnitDefs.domain(unit.type))
	if not Movement.can_enter(unit.moves_left, unit.max_moves(), cost):
		unit.moves_left = 0
		return events
	var from := unit.position
	unit.position = cell
	unit.moves_left = maxi(0, unit.moves_left - cost)
	unit.moved = true
	unit.fortified = false
	events.append({ "type": "unit_moved", "unit_id": unit.id, "from": from, "to": cell, "revealed": 0 })
	var city := state.city_at(cell)
	if city != null and not state.is_barbarian(city.owner):
		events.append(sack(state, city, unit))
	return events


## A random neighboring land tile near the unit's camp (or near itself if the
## camp is gone) with no civ unit or city on it.
static func _wander_step(state: GameState, unit: UnitState) -> Vector2i:
	var camp := state.get_camp(unit.camp_id)
	var home := camp.position if camp != null else unit.position
	var options: Array[Vector2i] = []
	for cell in IsoGrid.neighbors(unit.position, state.map.width, state.map.height):
		if not TerrainDefs.passable_by_land(state.map.get_terrain(cell)):
			continue
		if IsoGrid.step_distance(home, cell) > wander_radius():
			continue
		if not state.enemy_units_at(cell, unit.owner).is_empty() or state.city_at(cell) != null:
			continue
		options.append(cell)
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[state.rng.randi_range(0, options.size() - 1)]


## A barbarian walked into an undefended city: it loses a citizen (never
## below size 1) and its stored production, and the raider leaves.
static func sack(state: GameState, city: CityState, raider: UnitState) -> Dictionary:
	city.size = maxi(1, city.size - 1)
	city.food_box = mini(city.food_box, CityRules.food_box_size(city.size))
	var lost := city.production_box
	city.production_box = 0
	CityRules.auto_assign(state, city)
	state.remove_unit(raider.id)
	return { "type": "city_sacked", "city_id": city.id, "unit_id": raider.id, "size": city.size, "production_lost": lost }


# --- Sightings ----------------------------------------------------------------

## For `viewer`: warns about barbarian units that just came into sight and
## marks camps on visible tiles as discovered. A unit that leaves sight and
## comes back warns again.
static func update_sightings(state: GameState, viewer: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.is_barbarian(viewer):
		return events
	var visible := Fog.compute_visible(state, viewer)
	var width := state.map.width
	for unit in barbarian_units(state):
		var seen := visible[IsoGrid.index_of(unit.position, width)] == 1
		if seen and not unit.spotted:
			var city := _nearest_city(state, viewer, unit.position)
			events.append({ "type": "barbarians_spotted", "player": viewer, "unit_id": unit.id,
				"cell": unit.position, "city_id": city.id if city != null else 0 })
		unit.spotted = seen
	for camp in state.camps:
		if not camp.discovered_by.has(viewer) and visible[IsoGrid.index_of(camp.position, width)] == 1:
			camp.discovered_by.append(viewer)
			events.append({ "type": "camp_discovered", "player": viewer, "camp_id": camp.id, "cell": camp.position })
	return events
