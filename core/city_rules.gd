class_name CityRules
extends RefCounted
## City rules: founding, work radius, citizen auto-assignment, and growth.
## Numbers come from data/cities.json; names from data/city_names.json.

const RULES_PATH := "res://data/cities.json"
const NAMES_PATH := "res://data/city_names.json"

static var _rules: Dictionary = {}
static var _names: PackedStringArray = PackedStringArray()


# --- Data ---------------------------------------------------------------------

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(RULES_PATH)
	return _rules


static func work_radius() -> int:
	return int(rules().get("work_radius", 2))


static func sight_radius() -> int:
	return int(rules().get("sight_radius", 2))


## No new city may be founded this many steps (or fewer) from an existing one.
static func no_city_within() -> int:
	return int(rules().get("no_city_within", 3))


static func food_per_citizen() -> int:
	return int(rules().get("food_per_citizen", 2))


static func food_target() -> int:
	return int(rules().get("auto_assign_food_target", 2))


static func center_bonus() -> Vector3i:
	var bonus: Dictionary = rules().get("center_bonus", {})
	return Vector3i(int(bonus.get("food", 0)), int(bonus.get("production", 0)), int(bonus.get("trade", 0)))


static func food_box_size(city_size: int) -> int:
	return (city_size + 1) * int(rules().get("food_box_per_size", 10))


## The name for the n-th city founded (0-based); cycles with a number if the list runs out.
static func city_name(index: int) -> String:
	if _names.is_empty():
		var data := DataLoader.load_dict(NAMES_PATH)
		_names = PackedStringArray(data.get("names", ["City"]))
	var base := _names[index % _names.size()]
	@warning_ignore("integer_division")
	var round_number := index / _names.size()
	return base if round_number == 0 else "%s %d" % [base, round_number + 1]


# --- Founding -----------------------------------------------------------------

## Empty string if `unit` may found a city where it stands, else the reason it can't.
static func can_found(state: GameState, unit: UnitState) -> String:
	if not UnitDefs.can_found_city(unit.type):
		return "Only settlers can found cities"
	if not TerrainDefs.passable_by_land(state.map.get_terrain(unit.position)):
		return "Cities can't be founded on water"
	for city in state.cities:
		if IsoGrid.step_distance(city.position, unit.position) <= no_city_within():
			return "Too close to %s" % city.name
	return ""


# --- Working tiles ------------------------------------------------------------

## Tiles a city could work: everything within its radius except the center.
static func work_area(state: GameState, city: CityState) -> Array[Vector2i]:
	var area := IsoGrid.cells_within(city.position, work_radius(), state.map.width, state.map.height)
	area.erase(city.position)
	return area


## True if `city` may put a citizen on `cell` (in radius, not another city's).
static func is_workable(state: GameState, city: CityState, cell: Vector2i) -> bool:
	if cell == city.position or IsoGrid.step_distance(city.position, cell) > work_radius():
		return false
	var other := state.city_using(cell)
	return other == null or other == city


static func food_surplus(state: GameState, city: CityState) -> int:
	return Yields.city_total(state, city)[Yields.FOOD] - food_per_citizen() * city.size


## Turns until the city grows, or -1 if it isn't growing.
static func turns_to_grow(state: GameState, city: CityState) -> int:
	var surplus := food_surplus(state, city)
	if surplus <= 0:
		return -1
	var needed := food_box_size(city.size) - city.food_box
	return maxi(1, ceili(float(needed) / surplus))


## Places citizens: hand-placed (locked) tiles stay, the rest are chosen
## automatically. `excluded` tiles are skipped this time only.
static func auto_assign(state: GameState, city: CityState, excluded: Array[Vector2i] = []) -> void:
	var kept: Array[Vector2i] = []
	for cell in city.locked:
		if kept.size() < city.size and is_workable(state, city, cell):
			kept.append(cell)
	city.locked = kept.duplicate()
	city.worked = kept.duplicate()

	var candidates: Array[Vector2i] = []
	var candidate_yields: Array[Vector3i] = []
	for cell in work_area(state, city):
		if not kept.has(cell) and not excluded.has(cell) and is_workable(state, city, cell):
			candidates.append(cell)
			candidate_yields.append(Yields.tile(state.map, cell))

	var base := Yields.city_center(state.map, city.position)
	for cell in kept:
		base += Yields.tile(state.map, cell)
	var food_needed := food_per_citizen() * city.size
	for i in pick_tiles(base[Yields.FOOD], food_needed, candidate_yields, city.size - kept.size()):
		city.worked.append(candidates[i])


## Chooses `count` tiles from `candidates` (indices returned in pick order).
## Food comes first until the surplus reaches the target; after that, tiles
## are picked for food + production together, with trade as a tie-breaker.
static func pick_tiles(base_food: int, food_needed: int, candidates: Array[Vector3i], count: int) -> Array[int]:
	var picked: Array[int] = []
	var food := base_food
	for n in mini(count, candidates.size()):
		var food_first := food - food_needed < food_target()
		var best := -1
		var best_score := -1
		for i in candidates.size():
			if picked.has(i):
				continue
			var score := _tile_score(candidates[i], food_first)
			if score > best_score:
				best = i
				best_score = score
		picked.append(best)
		food += candidates[best][Yields.FOOD]
	return picked


static func _tile_score(y: Vector3i, food_first: bool) -> int:
	if food_first:
		return y[Yields.FOOD] * 100 + y[Yields.PRODUCTION] * 10 + y[Yields.TRADE]
	# Production edges out food on ties so balanced cities lean productive.
	return (y[Yields.FOOD] + y[Yields.PRODUCTION]) * 100 + y[Yields.PRODUCTION] * 10 + y[Yields.TRADE] * 5


## Puts a citizen on `cell`, or frees it if already worked. Returns false if
## the tile can't be used by this city.
static func toggle_worked_tile(state: GameState, city: CityState, cell: Vector2i) -> bool:
	if not is_workable(state, city, cell):
		return false
	if city.worked.has(cell):
		# Free the citizen back to automatic placement, somewhere else for now.
		city.locked.erase(cell)
		var skip_for_now: Array[Vector2i] = [cell]
		auto_assign(state, city, skip_for_now)
		return true
	if city.idle_citizens() == 0:
		city.worked.erase(_least_valuable_tile(state, city))
	city.worked.append(cell)
	city.locked.append(cell)
	return true


## The tile to take a citizen from: the weakest auto-placed one, else the
## oldest hand-placed one.
static func _least_valuable_tile(state: GameState, city: CityState) -> Vector2i:
	var worst := Vector2i(-1, -1)
	var worst_score := 1 << 30
	for cell in city.worked:
		if city.locked.has(cell):
			continue
		var score := _tile_score(Yields.tile(state.map, cell), false)
		if score < worst_score:
			worst = cell
			worst_score = score
	if worst == Vector2i(-1, -1):
		worst = city.locked[0]
		city.locked.remove_at(0)
	return worst


## Science per turn: the city's trade plus building bonuses (e.g. Library +50%).
static func science(state: GameState, city: CityState) -> int:
	var trade := Yields.city_total(state, city)[Yields.TRADE]
	@warning_ignore("integer_division")
	return trade + trade * BuildingDefs.effect(city, "science_percent") / 100


# --- Turn processing ----------------------------------------------------------

## Grows or starves the city, works the build queue, and banks science.
static func process_turn(state: GameState, city: CityState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var total := Yields.city_total(state, city)
	var surplus := total[Yields.FOOD] - food_per_citizen() * city.size
	var box := city.food_box + surplus
	if box >= food_box_size(city.size):
		# A granary keeps part of the full box; otherwise it empties.
		@warning_ignore("integer_division")
		city.food_box = food_box_size(city.size) * BuildingDefs.effect(city, "food_kept_on_growth_percent") / 100
		city.size += 1
		auto_assign(state, city)
		events.append({ "type": "city_grew", "city_id": city.id, "size": city.size })
	elif box < 0:
		city.food_box = 0
		if city.size > 1:
			city.size -= 1
			auto_assign(state, city)
			events.append({ "type": "city_shrank", "city_id": city.id, "size": city.size })
		else:
			events.append({ "type": "city_starving", "city_id": city.id })
	else:
		city.food_box = box
	events.append_array(Production.process(state, city, total[Yields.PRODUCTION]))
	state.add_science(city.owner, science(state, city))
	return events
