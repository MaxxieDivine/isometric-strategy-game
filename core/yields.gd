class_name Yields
extends RefCounted
## Tile and city yields. A yield is a Vector3i: (food, production, trade).

const FOOD := 0
const PRODUCTION := 1
const TRADE := 2


static func tile(map: MapState, cell: Vector2i) -> Vector3i:
	var def := TerrainDefs.get_def(map.get_terrain(cell))
	return Vector3i(int(def.get("food", 0)), int(def.get("production", 0)), int(def.get("trade", 0)))


## The center tile: its terrain plus the free city-center bonus.
static func city_center(map: MapState, cell: Vector2i) -> Vector3i:
	return tile(map, cell) + CityRules.center_bonus()


## Total per-turn yield of a city: center plus every worked tile.
static func city_total(state: GameState, city: CityState) -> Vector3i:
	var total := city_center(state.map, city.position)
	for cell in city.worked:
		total += tile(state.map, cell)
	return total
