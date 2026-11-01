class_name TerritoryLayer
extends Node2D
## Always-on map dressing for cities: an outline around each city's territory
## (only its outer edge) in the civ's border color, and a citizen marker on
## every tile the viewer's cities work. Sits under the fog, so unexplored
## land hides it. View only: reads state, never changes it.
##
## Territory = tiles within a city's work radius. Where radii overlap, the
## tile belongs to the city founded first (lowest id).

const BORDER_WIDTH := 2.5
const BORDER_SHADOW_WIDTH := 5.0
const BORDER_SHADOW := Color(0, 0, 0, 0.4)
const BORDER_TEXTURE_HEIGHT := 6.0
const CITIZEN_HEIGHT := 12.0
const CITIZEN_OFFSET := Vector2(0, 2)
const CITIZEN_FILL := Color(1, 1, 1)
const CITIZEN_OUTLINE := Color(0.08, 0.08, 0.12)

## [{ a: Vector2, b: Vector2, color: Color }] territory edges facing out.
var _edges: Array[Dictionary] = []
## World positions of worked tiles.
var _citizens: PackedVector2Array = PackedVector2Array()
var _border_texture: Texture2D
var _citizen_texture: Texture2D


func sync(state: GameState, map_view: MapView, viewer: int) -> void:
	var rules := CityRules.rules()
	_border_texture = SpriteLibrary.get_texture(String(rules.get("border_sprite", "")))
	_citizen_texture = SpriteLibrary.get_texture(String(rules.get("citizen_sprite", "")))

	var owners := _claim_tiles(state)
	var colors := {}
	for city in state.cities:
		colors[city.id] = _border_color(state, city.owner)

	_edges.clear()
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var corners: Array[Vector2] = [Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0)]
	for cell: Vector2i in owners:
		if not state.is_explored(viewer, cell):
			continue
		var city_id: int = owners[cell]
		var center := map_view.grid_to_world(cell)
		for i in 4:
			var a := center + corners[i]
			var b := center + corners[(i + 1) % 4]
			# The tile across this edge: mirror the tile center over the edge midpoint.
			var across := map_view.world_to_grid(a + b - center)
			if owners.get(across, -1) != city_id:
				_edges.append({ "a": a, "b": b, "color": colors[city_id] })

	_citizens.clear()
	for city in state.cities_of(viewer):
		for cell in city.worked:
			_citizens.append(map_view.grid_to_world(cell))
	queue_redraw()


func clear() -> void:
	_edges.clear()
	_citizens.clear()
	queue_redraw()


## cell -> id of the city that owns it, claimed in founding order.
func _claim_tiles(state: GameState) -> Dictionary:
	var cities := state.cities.duplicate()
	cities.sort_custom(func(x: CityState, y: CityState) -> bool: return x.id < y.id)
	var owners := {}
	for city: CityState in cities:
		for cell in IsoGrid.cells_within(city.position, CityRules.work_radius(), state.map.width, state.map.height):
			if not owners.has(cell):
				owners[cell] = city.id
	return owners


func _border_color(state: GameState, owner: int) -> Color:
	var player := state.players[owner]
	var civ := String(player.get("civ", ""))
	if CivDefs.has(civ) and CivDefs.get_def(civ).has("border_color"):
		return Color.html(String(CivDefs.get_def(civ)["border_color"]))
	return Color.html(String(player["color"]))


func _draw() -> void:
	for edge in _edges:
		var a: Vector2 = edge["a"]
		var b: Vector2 = edge["b"]
		if _border_texture != null:
			_draw_textured_edge(a, b, edge["color"])
			continue
		draw_line(a, b, BORDER_SHADOW, BORDER_SHADOW_WIDTH, true)
	if _border_texture == null:
		# Colored pass after all shadows so neighbors' shadows don't cut across it.
		for edge in _edges:
			var color: Color = edge["color"]
			draw_line(edge["a"], edge["b"], color, BORDER_WIDTH, true)
			# Round off the joints where edges meet at diamond corners.
			draw_circle(edge["a"], BORDER_WIDTH / 2.0, color)
			draw_circle(edge["b"], BORDER_WIDTH / 2.0, color)

	for pos in _citizens:
		var feet := pos + CITIZEN_OFFSET
		if _citizen_texture != null:
			var size := _citizen_texture.get_size()
			draw_texture(_citizen_texture, feet - Vector2(size.x / 2.0, size.y))
		else:
			PlaceholderArt.draw_citizen(self, feet, CITIZEN_HEIGHT, CITIZEN_FILL, CITIZEN_OUTLINE)


## Real border art: the texture stretched along the edge, tinted by civ color.
func _draw_textured_edge(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	draw_set_transform((a + b) / 2.0, (b - a).angle())
	draw_texture_rect(_border_texture,
		Rect2(-length / 2.0, -BORDER_TEXTURE_HEIGHT / 2.0, length, BORDER_TEXTURE_HEIGHT), false, color)
	draw_set_transform(Vector2.ZERO)
