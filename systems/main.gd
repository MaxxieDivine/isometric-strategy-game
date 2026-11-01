extends Node2D
## Session glue: owns the GameState, turns input into GameActions, and feeds
## the resulting events to the view. Selection and the open city panel are
## view state, not game state.

const MAP_WIDTH := 40
const MAP_HEIGHT := 80
const PLAYER := 0
const NO_UNIT := -1
const NO_CITY := -1
const START_ZOOM := 1.25
const UNEXPLORED_SWATCH := Color(0.05, 0.06, 0.09)

var state: GameState
var _selected_unit := NO_UNIT
var _open_city := NO_CITY
## Only picks seeds for new games; gameplay randomness lives in GameState.rng.
var _seed_picker := RandomNumberGenerator.new()

@onready var map_view: MapView = $MapView
@onready var fog_view: FogView = $FogView
@onready var path_overlay: PathOverlay = $PathOverlay
@onready var highlight: TileHighlight = $TileHighlight
@onready var cities_layer: CitiesLayer = $CitiesLayer
@onready var units_layer: UnitsLayer = $UnitsLayer
@onready var city_overlay: CityOverlay = $CityOverlay
@onready var camera: MapCamera = $MapCamera
@onready var hud: Hud = $UI/Hud
@onready var info_panel: TileInfoPanel = $UI/TileInfoPanel
@onready var city_panel: CityPanel = $UI/CityPanel


func _ready() -> void:
	InputActions.ensure_defaults()
	hud.end_turn_requested.connect(_end_turn)
	hud.found_city_requested.connect(_found_city)
	city_panel.close_requested.connect(_close_city)
	_seed_picker.randomize()
	_new_game(_seed_picker.randi())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn"):
		_end_turn()
	elif event.is_action_pressed("skip_unit"):
		_skip_selected_unit()
	elif event.is_action_pressed("found_city"):
		_found_city()
	elif event.is_action_pressed("deselect"):
		if _open_city != NO_CITY:
			_close_city()
		else:
			_select_unit(NO_UNIT)
			_hide_tile_info()
	elif event.is_action_pressed("regenerate_map"):
		_new_game(_seed_picker.randi())
	elif event is InputEventMouseButton and event.is_pressed():
		var button := (event as InputEventMouseButton).button_index
		var cell := map_view.world_to_grid(get_global_mouse_position())
		if button == MOUSE_BUTTON_LEFT:
			_on_left_click(cell)
		elif button == MOUSE_BUTTON_RIGHT:
			_order_move(cell)
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


# --- Game flow ----------------------------------------------------------------

func _new_game(map_seed: int) -> void:
	state = GameSetup.new_game(map_seed, MAP_WIDTH, MAP_HEIGHT)
	units_layer.clear_units()
	cities_layer.clear_cities()
	_selected_unit = NO_UNIT
	_close_city()
	_hide_tile_info()
	# Inset by half a tile so the jagged stacked-row edges stay off screen.
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var bounds := map_view.get_grid_world_rect(MAP_WIDTH, MAP_HEIGHT).grow_individual(-half.x, -half.y, -half.x, -half.y)
	camera.set_bounds(bounds)
	hud.set_hint("Seed %d   ·   B: found city   ·   Space: skip   ·   Enter: end turn   ·   Right-click: move   ·   R: new world" % map_seed)
	_refresh_world()
	var units := state.units_of(PLAYER)
	if not units.is_empty():
		camera.look_at_world(map_view.grid_to_world(units[0].position), START_ZOOM)
	_select_next_unit()
	print("New game: seed %d, start %s" % [map_seed, units[0].position if not units.is_empty() else Vector2i(-1, -1)])


func _end_turn() -> void:
	_apply_events(GameActions.end_turn(state))
	_selected_unit = NO_UNIT
	_select_next_unit()


func _skip_selected_unit() -> void:
	if state.get_unit(_selected_unit) == null:
		return
	_apply_events(GameActions.skip_unit(state, _selected_unit))
	_select_next_unit()


func _found_city() -> void:
	var unit := state.get_unit(_selected_unit)
	if unit == null or not UnitDefs.can_found_city(unit.type):
		return
	_apply_events(GameActions.found_city(state, unit.id))
	if state.get_unit(unit.id) == null:
		_selected_unit = NO_UNIT
		_select_next_unit()


func _order_move(cell: Vector2i) -> void:
	var unit := state.get_unit(_selected_unit)
	if unit == null or not state.map.in_bounds(cell):
		return
	_apply_events(GameActions.move_unit(state, unit.id, cell))
	if unit.needs_orders():
		_select_unit(unit.id)
	else:
		_select_next_unit()


func _on_left_click(cell: Vector2i) -> void:
	if not state.map.in_bounds(cell):
		_close_city()
		_hide_tile_info()
		return

	if _open_city != NO_CITY:
		var open := state.get_city(_open_city)
		if cell != open.position and IsoGrid.step_distance(open.position, cell) <= CityRules.work_radius():
			_toggle_worked_tile(open, cell)
			return
		_close_city()
		if cell == open.position:
			# Clicking the open city again hands over to the units inside it.
			var inside := state.units_at(cell, PLAYER)
			if not inside.is_empty():
				_select_unit(_pick_from_stack(inside))
			return

	var city := state.city_at(cell)
	if city != null and city.owner == PLAYER:
		_open_city_panel(city.id)
		return

	var here := state.units_at(cell, PLAYER)
	var selected := state.get_unit(_selected_unit)
	if not here.is_empty():
		var index := here.find(selected)
		if index == -1:
			_select_unit(_pick_from_stack(here))
			return
		if here.size() > 1:
			# Clicking a stack again cycles through its units.
			_select_unit(here[(index + 1) % here.size()].id)
			return
	elif selected != null:
		_order_move(cell)
		return
	_show_tile_info(cell)


func _pick_from_stack(units: Array[UnitState]) -> int:
	for unit in units:
		if unit.needs_orders():
			return unit.id
	return units[0].id


## Selects the next unit (after the current one, by id) still waiting for orders.
func _select_next_unit() -> void:
	var waiting := state.units_needing_orders(PLAYER)
	if waiting.is_empty():
		_select_unit(NO_UNIT)
		return
	var next := waiting[0]
	for unit in waiting:
		if unit.id > _selected_unit:
			next = unit
			break
	_select_unit(next.id)
	camera.ensure_visible(map_view.grid_to_world(next.position))


func _select_unit(unit_id: int) -> void:
	if unit_id != NO_UNIT:
		_close_city()
	_selected_unit = unit_id
	var unit := state.get_unit(unit_id)
	if unit != null:
		highlight.hide()
		_show_unit_info(unit)
	elif _open_city == NO_CITY:
		info_panel.hide()
	hud.set_found_city_visible(unit != null and UnitDefs.can_found_city(unit.type))
	units_layer.sync(state, _selected_unit, map_view)
	_refresh_paths()
	_refresh_turn_status()


# --- Cities -------------------------------------------------------------------

func _open_city_panel(city_id: int) -> void:
	_select_unit(NO_UNIT)
	highlight.hide()
	info_panel.hide()
	_open_city = city_id
	_refresh_city_ui()
	camera.ensure_visible(map_view.grid_to_world(state.get_city(city_id).position))


func _close_city() -> void:
	if _open_city == NO_CITY:
		return
	_open_city = NO_CITY
	city_panel.hide()
	city_overlay.clear()


func _toggle_worked_tile(city: CityState, cell: Vector2i) -> void:
	var events := GameActions.toggle_worked_tile(state, city.id, cell)
	if events.is_empty():
		var other := state.city_using(cell)
		hud.notify("Worked by %s" % other.name if other != null else "Can't work that tile")
		return
	_apply_events(events)


func _refresh_city_ui() -> void:
	if _open_city == NO_CITY:
		return
	var city := state.get_city(_open_city)
	if city == null:
		_close_city()
		return
	var total := Yields.city_total(state, city)
	city_panel.show_city({
		"name": city.name,
		"size": city.size,
		"food_box": city.food_box,
		"food_box_size": CityRules.food_box_size(city.size),
		"food_surplus": CityRules.food_surplus(state, city),
		"turns_to_grow": CityRules.turns_to_grow(state, city),
		"production": total[Yields.PRODUCTION],
		"production_box": city.production_box,
		"trade": total[Yields.TRADE],
		"science": int(state.players[city.owner]["science"]),
		"working": city.worked.size(),
		"idle": city.idle_citizens(),
	})
	var tiles: Array[Dictionary] = [{
		"pos": map_view.grid_to_world(city.position),
		"yields": Yields.city_center(state.map, city.position),
		"status": "center",
	}]
	for cell in CityRules.work_area(state, city):
		var status := "free"
		if city.locked.has(cell):
			status = "locked"
		elif city.worked.has(cell):
			status = "worked"
		elif not CityRules.is_workable(state, city, cell):
			status = "taken"
		tiles.append({ "pos": map_view.grid_to_world(cell), "yields": Yields.tile(state.map, cell), "status": status })
	city_overlay.show_tiles(tiles)


# --- Events → view ------------------------------------------------------------

func _apply_events(events: Array[Dictionary]) -> void:
	var new_turn := -1
	var city_news := PackedStringArray()
	for event in events:
		match event["type"]:
			"unit_moved":
				units_layer.walk(event["unit_id"], map_view.grid_to_world(event["to"]))
			"move_failed":
				hud.notify("No known route there")
			"orders_cancelled":
				hud.notify("%s's route is blocked" % _unit_name(state.get_unit(event["unit_id"])))
			"found_failed":
				hud.notify(event["reason"])
			"city_founded":
				var city := state.get_city(event["city_id"])
				hud.notify("%s is founded!" % city.name, PackedStringArray(["Click the city to manage its citizens"]))
			"city_grew":
				city_news.append("%s grew to size %d" % [_city_name(event["city_id"]), event["size"]])
			"city_shrank":
				city_news.append("%s starved down to size %d" % [_city_name(event["city_id"]), event["size"]])
			"city_starving":
				city_news.append("%s is starving" % _city_name(event["city_id"]))
			"turn_started":
				new_turn = event["turn"]
	if new_turn != -1:
		# One batched card per turn: no popup spam.
		hud.notify("Turn %d  ·  %s" % [new_turn, _year_text()], city_news)
	_refresh_world()


func _refresh_world() -> void:
	var explored := state.explored[PLAYER]
	map_view.render(state.map, explored)
	fog_view.refresh(state.map.width, state.map.height, explored, Fog.compute_visible(state, PLAYER))
	cities_layer.sync(state, map_view)
	units_layer.sync(state, _selected_unit, map_view)
	_refresh_paths()
	_refresh_city_ui()
	hud.set_turn(state.turn, _year_text())
	_refresh_turn_status()


func _refresh_paths() -> void:
	var paths: Array[Dictionary] = []
	for unit in state.units_of(PLAYER):
		if unit.path.is_empty():
			continue
		var points := PackedVector2Array()
		for cell in unit.path:
			points.append(map_view.grid_to_world(cell))
		paths.append({
			"start": map_view.grid_to_world(unit.position),
			"points": points,
			"turns": Movement.path_turns(unit, state.map, state.explored[unit.owner]),
			"active": unit.id == _selected_unit,
		})
	path_overlay.show_paths(paths)


func _refresh_turn_status() -> void:
	hud.set_turn_done(state.units_needing_orders(PLAYER).is_empty())


# --- Info panel ---------------------------------------------------------------

func _show_unit_info(unit: UnitState) -> void:
	var def := UnitDefs.get_def(unit.type)
	var details := "Moves %d/%d   ·   Attack %d   ·   Defense %d" % [
		unit.moves_left, unit.max_moves(), int(def.get("attack", 0)), int(def.get("defense", 0))]
	if unit.has_goal():
		var turns := Movement.path_turns(unit, state.map, state.explored[unit.owner])
		var eta: int = turns.back() + 1 if not turns.is_empty() else 1
		details += "\nHeading to (%d, %d)  ·  %d turn%s" % [unit.goal.x, unit.goal.y, eta, "" if eta == 1 else "s"]
	else:
		var terrain := TerrainDefs.get_def(state.map.get_terrain(unit.position))
		details += "\n%s at (%d, %d)" % [terrain["name"], unit.position.x, unit.position.y]
		if UnitDefs.can_found_city(unit.type):
			var reason := CityRules.can_found(state, unit)
			details += "\n" + ("Press B to found a city here" if reason == "" else reason)
	info_panel.show_info(def["name"], details, Color.html(state.players[unit.owner]["color"]))


func _show_tile_info(cell: Vector2i) -> void:
	highlight.show_at(map_view.grid_to_world(cell))
	if not state.is_explored(PLAYER, cell):
		info_panel.show_info("Unexplored", "Tile (%d, %d)" % [cell.x, cell.y], UNEXPLORED_SWATCH)
		return
	var id := state.map.get_terrain(cell)
	var def := TerrainDefs.get_def(id)
	var cost := "Impassable on foot" if not TerrainDefs.passable_by_land(id) \
		else "Move cost %d" % TerrainDefs.move_cost(id)
	var y := Yields.tile(state.map, cell)
	info_panel.show_info(def["name"],
		"Tile (%d, %d)   ·   %s\nFood %d   ·   Production %d   ·   Trade %d" % [cell.x, cell.y, cost, y.x, y.y, y.z],
		Color.html(def["placeholder_color"]))


func _hide_tile_info() -> void:
	highlight.hide()
	var unit := state.get_unit(_selected_unit) if state != null else null
	if unit != null:
		_show_unit_info(unit)
	else:
		info_panel.hide()


func _unit_name(unit: UnitState) -> String:
	return String(UnitDefs.get_def(unit.type)["name"]) if unit != null else "A unit"


func _city_name(city_id: int) -> String:
	var city := state.get_city(city_id)
	return city.name if city != null else "A city"


func _year_text() -> String:
	return Calendar.format_year(Calendar.year_for_turn(state.turn))
