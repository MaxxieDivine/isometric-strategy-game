class_name Fog
extends RefCounted
## Fog of war: which tiles each player has explored and can currently see.

const BASE_SIGHT := 1


## How far a unit standing on `cell` can see (hills add range).
static func sight_radius(map: MapState, cell: Vector2i) -> int:
	return BASE_SIGHT + TerrainDefs.sight_bonus(map.get_terrain(cell))


## Marks tiles around `cell` explored for `owner`. Returns how many were new.
static func reveal_around(state: GameState, owner: int, cell: Vector2i) -> int:
	var map := state.map
	var tiles := state.explored[owner]
	var newly_explored := 0
	for c in IsoGrid.cells_within(cell, sight_radius(map, cell), map.width, map.height):
		var i := IsoGrid.index_of(c, map.width)
		if tiles[i] == 0:
			tiles[i] = 1
			newly_explored += 1
	# Packed arrays are copied on write; store the updated copy back.
	state.explored[owner] = tiles
	return newly_explored


static func reveal_for_units(state: GameState, owner: int) -> void:
	for unit in state.units_of(owner):
		reveal_around(state, owner, unit.position)


## Tiles `owner`'s units can see right now (1 = visible). Derived, not saved.
static func compute_visible(state: GameState, owner: int) -> PackedByteArray:
	var map := state.map
	var visible := PackedByteArray()
	visible.resize(map.width * map.height)
	for unit in state.units_of(owner):
		for c in IsoGrid.cells_within(unit.position, sight_radius(map, unit.position), map.width, map.height):
			visible[IsoGrid.index_of(c, map.width)] = 1
	return visible
