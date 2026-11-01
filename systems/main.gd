extends Node2D
## Session glue: owns the GameState, turns input into GameActions, and feeds
## the resulting events to the view. Selection is view state, not game state.

const MAP_WIDTH := 40
const MAP_HEIGHT := 80
const PLAYER := 0
const NO_UNIT := -1
const START_ZOOM := 1.25
const UNEXPLORED_SWATCH := Color(0.05, 0.06, 0.09)

var state: GameState
var _selected_unit := NO_UNIT
## Only picks seeds for new games; gameplay randomness lives in GameState.rng.
var _seed_picker := RandomNumberGenerator.new()

@onready var map_view: MapView = $MapView
@onready var fog_view: FogView = $FogView
@onready var path_overlay: PathOverlay = $PathOverlay
@onready var highlight: TileHighlight = $TileHighlight
@onready var units_layer: UnitsLayer = $UnitsLayer
@onready var camera: MapCamera = $MapCamera
@onready var hud: Hud = $UI/Hud
@onready var info_panel: TileInfoPanel = $UI/TileInfoPanel


func _ready() -> void:
	InputActions.ensure_defaults()
	hud.end_turn_requested.connect(_end_turn)
	_seed_picker.randomize()
	_new_game(_seed_picker.randi())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("end_turn"):
		_end_turn()
	elif event.is_action_pressed("skip_unit"):
		_skip_selected_unit()
	elif event.is_action_pressed("deselect"):
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
	_selected_unit = NO_UNIT
	_hide_tile_info()
	# Inset by half a tile so the jagged stacked-row edges stay off screen.
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var bounds := map_view.get_grid_world_rect(MAP_WIDTH, MAP_HEIGHT).grow_individual(-half.x, -half.y, -half.x, -half.y)
	camera.set_bounds(bounds)
	hud.set_hint("Seed %d   ·   Space: skip unit   ·   Enter: end turn   ·   Right-click: move   ·   R: new world" % map_seed)
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
		_hide_tile_info()
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
	_selected_unit = unit_id
	var unit := state.get_unit(unit_id)
	if unit != null:
		highlight.hide()
		_show_unit_info(unit)
	else:
		info_panel.hide()
	units_layer.sync(state, _selected_unit, map_view)
	_refresh_paths()
	_refresh_turn_status()


# --- Events → view ------------------------------------------------------------

func _apply_events(events: Array[Dictionary]) -> void:
	for event in events:
		match event["type"]:
			"unit_moved":
				units_layer.walk(event["unit_id"], map_view.grid_to_world(event["to"]))
			"move_failed":
				hud.toast("No known route there")
			"orders_cancelled":
				var unit := state.get_unit(event["unit_id"])
				hud.toast("%s's route is blocked" % _unit_name(unit))
			"turn_started":
				hud.toast("Turn %d  ·  %s" % [event["turn"], _year_text()])
	_refresh_world()


func _refresh_world() -> void:
	var explored := state.explored[PLAYER]
	map_view.render(state.map, explored)
	fog_view.refresh(state.map.width, state.map.height, explored, Fog.compute_visible(state, PLAYER))
	units_layer.sync(state, _selected_unit, map_view)
	_refresh_paths()
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
	info_panel.show_info(def["name"], "Tile (%d, %d)   ·   %s" % [cell.x, cell.y, cost],
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


func _year_text() -> String:
	return Calendar.format_year(Calendar.year_for_turn(state.turn))
