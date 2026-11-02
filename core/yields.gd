class_name Yields
extends RefCounted
## Tile and city yields. A yield is a Vector3i: (food, production, trade).

const FOOD := 0
const PRODUCTION := 1
const TRADE := 2
## Effect key names per yield index (see Effects).
const NAMES: Array[String] = ["food", "production", "trade"]


static func tile(map: MapState, cell: Vector2i) -> Vector3i:
	var def := TerrainDefs.get_def(map.get_terrain(cell))
	return Vector3i(int(def.get("food", 0)), int(def.get("production", 0)), int(def.get("trade", 0)))


## A tile as worked by `city`: its terrain plus effects such as
## "tile_trade:ocean" (the Colossus).
static func worked_tile(state: GameState, city: CityState, cell: Vector2i) -> Vector3i:
	var result := tile(state.map, cell)
	var terrain := state.map.get_terrain(cell)
	for i in NAMES.size():
		result[i] += Effects.city_effect(state, city, "tile_%s:%s" % [NAMES[i], terrain])
	return result


## The center tile: its terrain plus the free city-center bonus.
static func city_center(map: MapState, cell: Vector2i) -> Vector3i:
	return tile(map, cell) + CityRules.center_bonus()


## Total per-turn yield of a city: center plus every worked tile, plus flat
## effects such as "city_food" (the Hanging Gardens).
static func city_total(state: GameState, city: CityState) -> Vector3i:
	var total := city_center(state.map, city.position)
	for cell in city.worked:
		total += worked_tile(state, city, cell)
	for i in NAMES.size():
		total[i] += Effects.city_effect(state, city, "city_" + NAMES[i])
	return total
