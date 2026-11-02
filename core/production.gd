class_name Production
extends RefCounted
## Build queues: what a city can build, how long it takes, and what happens
## when an item completes. Buildable items are units (data/units.json) and
## buildings (data/buildings.json); their ids share one namespace.

const UNIT := "unit"
const BUILDING := "building"

static var _checked_ids := false


# --- Item lookups -------------------------------------------------------------

## "unit", "building", or "" for an unknown id.
static func kind(id: String) -> String:
	_check_ids()
	if UnitDefs.has(id):
		return UNIT
	if BuildingDefs.has(id):
		return BUILDING
	return ""


static func get_def(id: String) -> Dictionary:
	match kind(id):
		UNIT:
			return UnitDefs.get_def(id)
		BUILDING:
			return BuildingDefs.get_def(id)
	return {}


static func cost(id: String) -> int:
	return int(get_def(id).get("cost", 0))


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


## Name for news lines: "a Granary", "City Walls".
static func news_name(id: String) -> String:
	var article := String(get_def(id).get("article", "a"))
	var item_name := display_name(id)
	return item_name if article == "" else "%s %s" % [article, item_name]


## Every buildable id: units first, then buildings, in data order.
static func all_items() -> Array[String]:
	var result: Array[String] = []
	for def in UnitDefs.all():
		if def.has("cost"):
			result.append(String(def["id"]))
	for def in BuildingDefs.all():
		result.append(String(def["id"]))
	return result


static func _check_ids() -> void:
	if _checked_ids:
		return
	_checked_ids = true
	for def in BuildingDefs.all():
		if UnitDefs.has(String(def["id"])):
			push_error("Id '%s' is both a unit and a building" % def["id"])


# --- Queue rules --------------------------------------------------------------

## Empty string if `id` may be added to the city's queue, else the reason not.
static func can_enqueue(state: GameState, city: CityState, id: String) -> String:
	if kind(id) == "":
		return "Unknown item"
	if not Research.has_unlocked(state, city.owner, id):
		return "%s needs %s" % [display_name(id), TechDefs.display_name(TechDefs.required_for(id))]
	match kind(id):
		UNIT:
			if not get_def(id).has("cost"):
				return "%s can't be built" % display_name(id)
		BUILDING:
			if city.buildings.has(id):
				return "%s already has %s" % [city.name, display_name(id)]
			if city.queue.has(id):
				return "%s is already queued" % display_name(id)
	return ""


## Why the item can't complete right now (it keeps waiting), or "".
static func blocked_reason(city: CityState, id: String) -> String:
	var min_size := int(get_def(id).get("min_city_size", 1))
	if city.size < min_size:
		return "%s waits for size %d" % [display_name(id), min_size]
	return ""


## Items the city could add to its queue now (locked items are left out).
static func available_items(state: GameState, city: CityState) -> Array[String]:
	var result: Array[String] = []
	for id in all_items():
		if can_enqueue(state, city, id) == "":
			result.append(id)
	return result


## Turns until the item at the head of the queue completes at `production`
## per turn, or -1 if nothing is queued or production is zero.
static func turns_to_complete(city: CityState, production: int) -> int:
	if city.queue.is_empty():
		return -1
	return turns_for(city, city.queue[0], production)


## Turns to build `id` next, counting what is already in the box.
static func turns_for(city: CityState, id: String, production: int) -> int:
	var needed := cost(id) - city.production_box
	if needed <= 0:
		return 1
	if production <= 0:
		return -1
	return ceili(float(needed) / production)


# --- Turn processing ----------------------------------------------------------

## Banks this turn's production and completes the head of the queue if it is
## paid for and not blocked. At most one item completes per turn; leftover
## production carries over to the next item.
static func process(state: GameState, city: CityState, production: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	city.production_box += production
	if city.queue.is_empty():
		return events
	var id := city.queue[0]
	if city.production_box < cost(id) or blocked_reason(city, id) != "":
		return events
	city.production_box -= cost(id)
	city.queue.remove_at(0)
	var event := { "type": "city_built", "city_id": city.id, "item": id }
	match kind(id):
		UNIT:
			var unit := state.add_unit(id, city.owner, city.position)
			unit.home_city = city.id
			event["unit_id"] = unit.id
			var pop_cost := int(get_def(id).get("pop_cost", 0))
			if pop_cost > 0:
				city.size = maxi(1, city.size - pop_cost)
				city.food_box = mini(city.food_box, CityRules.food_box_size(city.size))
				CityRules.auto_assign(state, city)
		BUILDING:
			city.buildings.append(id)
	events.append(event)
	if city.queue.is_empty():
		events.append({ "type": "city_idle", "city_id": city.id })
	return events
