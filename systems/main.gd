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
## Touch screens start closer in and may zoom further, so a tile fits a fingertip.
## On touch screens a map tile starts about this many CSS pixels wide, so it
## fits a fingertip whatever the UI scale.
const TOUCH_TILE_CSS := 70.0
const TOUCH_MAX_ZOOM := 3.0
const UNEXPLORED_SWATCH := Color(0.05, 0.06, 0.09)
const NO_CELL := Vector2i(-1, -1)

var state: GameState
var _selected_unit := NO_UNIT
var _open_city := NO_CITY
## Only picks seeds for new games; gameplay randomness lives in GameState.rng.
var _seed_picker := RandomNumberGenerator.new()

@onready var map_view: MapView = $MapView
@onready var territory_layer: TerritoryLayer = $TerritoryLayer
@onready var fog_view: FogView = $FogView
@onready var path_overlay: PathOverlay = $PathOverlay
@onready var highlight: TileHighlight = $TileHighlight
@onready var cities_layer: CitiesLayer = $CitiesLayer
@onready var camps_layer: CampsLayer = $CampsLayer
@onready var units_layer: UnitsLayer = $UnitsLayer
@onready var city_overlay: CityOverlay = $CityOverlay
@onready var camera: MapCamera = $MapCamera
@onready var hud: Hud = $UI/Hud
@onready var info_panel: TileInfoPanel = $UI/TileInfoPanel
@onready var city_panel: CityPanel = $UI/CityPanel
@onready var research_picker: ResearchPicker = $UI/ResearchPicker
@onready var tech_tree: TechTreeView = $UI/TechTreeView
## Built in code (see _build_overlays) so main.tscn stays unchanged.
var wonder_card: WonderCard
var end_screen: EndScreen
## The game ended while a wonder card was up: show the end screen after it.
var _end_screen_pending := false
## The advisor speaking (bottom-left) and its marker on the map.
var advisor_box: AdvisorBox
var advice_marker: AdviceMarker
## Darkens and frames what the camera shows past the map edge.
var map_frame: MapFrame
## Decides compact vs full layout and the UI scale (see UiLayout).
var ui_layout: UiLayout
var options_panel: OptionsPanel
var info_popover: InfoPopover
## Events since the advisor last looked; it looks once per frame at most, so
## an action's events and the selection that follows it are weighed together.
var _advisor_events: Array[Dictionary] = []
var _advisor_pending := false

## The last notification card, so mid-turn news (an auto-picked tech, a
## fight) can be added to it instead of replacing it.
var _card_title := ""
var _card_lines := PackedStringArray()
var _card_highlights := PackedStringArray()
var _card_warnings := PackedStringArray()
## Where clicking the card takes the camera (e.g. spotted barbarians), or NO_CELL.
var _card_jump := NO_CELL
## Tiles the player sees right now (refreshed with the world).
var _visible := PackedByteArray()
## A risky attack waiting for its confirming click, or NO_CELL.
var _pending_attack := NO_CELL
## Touch play: taps, drags and pinches on the map.
var touch_gestures: TouchGestures
## The player is on a touch screen (set by the first touch, or up front on phones).
var _touch_mode := false
## Touch move preview: the tile tapped once (tap it again to go), or NO_CELL.
var _touch_target := NO_CELL
var _preview_path: Array[Vector2i] = []
## R was pressed once mid-game; a second press starts a new world.
var _new_world_armed := false


func _enter_tree() -> void:
	# Runs before the UI children build their labels.
	SymbolFont.install()
	UiText.touch = UiText.is_touch_device()


func _ready() -> void:
	InputActions.ensure_defaults()
	hud.end_turn_requested.connect(_end_turn)
	hud.found_city_requested.connect(_found_city)
	hud.end_turn_confirmed.connect(_confirm_end_turn)
	hud.idle_city_jump_requested.connect(_jump_to_idle_city)
	city_panel.close_requested.connect(_close_city)
	city_panel.enqueue_requested.connect(_enqueue_build)
	city_panel.remove_requested.connect(_remove_from_queue)
	hud.research_clicked.connect(_open_research_picker)
	hud.tech_tree_requested.connect(_toggle_tech_tree)
	research_picker.tech_chosen.connect(_choose_research)
	research_picker.dismissed.connect(_dismiss_research_picker)
	tech_tree.tech_chosen.connect(_choose_research)
	tech_tree.close_requested.connect(tech_tree.hide)
	hud.fortify_requested.connect(_fortify_selected_unit)
	hud.notice_clicked.connect(_jump_to_card_place)
	hud.skip_requested.connect(_skip_selected_unit)
	hud.explore_requested.connect(_explore_selected_unit)
	hud.advisor_toggle_requested.connect(_toggle_advisor)
	hud.options_requested.connect(_toggle_options)
	research_picker.tech_tree_requested.connect(_toggle_tech_tree)
	ui_layout = UiLayout.new()
	ui_layout.name = "UiLayout"
	add_child(ui_layout)
	_build_touch_input()
	_build_overlays()
	ui_layout.changed.connect(_apply_layout)
	_apply_layout()
	_seed_picker.randomize()
	_continue_or_new_game()


func _build_overlays() -> void:
	# A full-screen holder above the HUD, so the overlays can center
	# themselves and play their bursts.
	advisor_box = AdvisorBox.new()
	advisor_box.name = "AdvisorBox"
	advisor_box.avoid = [research_picker, city_panel]
	$UI.add_child(advisor_box)
	advice_marker = AdviceMarker.new()
	add_child(advice_marker)
	map_frame = MapFrame.new()
	add_child(map_frame)
	var overlays := Control.new()
	overlays.name = "Overlays"
	overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(overlays)
	overlays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui := overlays
	wonder_card = WonderCard.new()
	ui.add_child(wonder_card)
	wonder_card.closed.connect(_on_wonder_card_closed)
	end_screen = EndScreen.new()
	ui.add_child(end_screen)
	end_screen.new_game_requested.connect(func() -> void: _new_game(_seed_picker.randi()))
	end_screen.keep_playing_requested.connect(_keep_playing)
	options_panel = OptionsPanel.new()
	ui.add_child(options_panel)
	options_panel.close_requested.connect(options_panel.hide)
	options_panel.ui_scale_changed.connect(func(value: float) -> void:
		ui_layout.set_ui_scale(value)
		_open_options())
	options_panel.layout_changed.connect(func(layout: String) -> void:
		ui_layout.set_layout(layout)
		_open_options())
	options_panel.advisor_toggled.connect(func() -> void:
		_toggle_advisor()
		_open_options())
	info_popover = InfoPopover.new()
	ui.add_child(info_popover)


func _build_touch_input() -> void:
	touch_gestures = TouchGestures.new()
	add_child(touch_gestures)
	touch_gestures.touch_seen.connect(_enter_touch_mode)
	touch_gestures.tapped.connect(_on_tap)
	touch_gestures.long_pressed.connect(_on_long_press)
	touch_gestures.dragged.connect(camera.pan_screen)
	touch_gestures.pinched.connect(camera.zoom_screen)
	if UiText.touch:
		_enter_touch_mode()


func _enter_touch_mode() -> void:
	if _touch_mode:
		return
	_touch_mode = true
	UiText.touch = true
	camera.edge_pan_enabled = false
	camera.max_zoom = TOUCH_MAX_ZOOM
	hud.set_touch_mode(true)
	hud.hide_odds()
	hud.set_hint(_hint_text())
	ui_layout.refresh()


func _hint_text() -> String:
	if _touch_mode:
		return "Tap: select   ·   Tap a tile twice: move/attack   ·   Hold: move onto your units   ·   Drag: pan   ·   Pinch: zoom"
	# Kept short enough to clear the End Turn button at 1280 px wide.
	return "B: found city  ·  F: fortify  ·  X: explore  ·  Space: skip  ·  Enter: end turn  ·  Right-click: move/attack  ·  T: techs  ·  R: new world"


func _unhandled_input(event: InputEvent) -> void:
	if end_screen.visible:
		# The end screen has its own buttons; the map waits behind it.
		get_viewport().set_input_as_handled()
		return
	var mouse := event as InputEventMouse
	if mouse != null and mouse.device == InputEvent.DEVICE_ID_EMULATION:
		# A touch dressed up as a mouse: TouchGestures already handles it.
		return
	if event.is_action_pressed("deselect") and wonder_card.is_showing():
		wonder_card.dismiss()
	elif event.is_action_pressed("end_turn"):
		_end_turn()
	elif event.is_action_pressed("skip_unit"):
		_skip_selected_unit()
	elif event.is_action_pressed("found_city"):
		_found_city()
	elif event.is_action_pressed("tech_tree"):
		_toggle_tech_tree()
	elif event.is_action_pressed("fortify"):
		_fortify_selected_unit()
	elif event.is_action_pressed("explore"):
		_explore_selected_unit()
	elif event.is_action_pressed("deselect"):
		if options_panel.visible:
			options_panel.hide()
		elif tech_tree.visible:
			tech_tree.hide()
		elif research_picker.visible:
			_dismiss_research_picker()
		elif hud.is_idle_prompt_visible():
			hud.hide_idle_prompt()
		elif _open_city != NO_CITY:
			_close_city()
		else:
			_select_unit(NO_UNIT)
			_hide_tile_info()
	elif event.is_action_pressed("regenerate_map"):
		_request_new_world()
	elif event is InputEventMouseButton and event.is_pressed():
		var button := (event as InputEventMouseButton).button_index
		var cell := map_view.world_to_grid(get_global_mouse_position())
		if button == MOUSE_BUTTON_LEFT:
			_on_left_click(cell)
		elif button == MOUSE_BUTTON_RIGHT:
			_order_move(cell)
		else:
			return
	elif event is InputEventMouseMotion:
		_update_attack_odds()
		return
	else:
		return
	get_viewport().set_input_as_handled()


# --- Game flow ----------------------------------------------------------------

## Picks up the autosaved game if there is one, otherwise starts a new world.
func _continue_or_new_game() -> void:
	var saved := SaveSystem.load_game()
	if saved == null:
		_new_game(_seed_picker.randi())
		return
	_start_game(saved)
	var units := state.units_of(PLAYER)
	var focus := state.get_unit(_selected_unit)
	if focus != null:
		_look_at(focus.position)
	elif not state.cities_of(PLAYER).is_empty():
		_look_at(state.cities_of(PLAYER)[0].position)
	elif not units.is_empty():
		_look_at(units[0].position)
	if not state.game_over.is_empty() and not Victory.is_continued(state):
		_show_end_screen()
	elif Research.current(state, PLAYER) == "":
		_open_research_picker()
	print("Continued saved game: turn %d" % state.turn)


func _new_game(map_seed: int) -> void:
	# Turning the advisor off is the player's choice, so it carries over.
	var advisor_on := state.advisor.enabled if state != null else true
	var new_state := GameSetup.new_game(map_seed, MAP_WIDTH, MAP_HEIGHT)
	new_state.advisor.enabled = advisor_on
	_start_game(new_state)
	_queue_advisor([{ "type": "game_started", "player": PLAYER }])
	var units := state.units_of(PLAYER)
	if not units.is_empty():
		_look_at(units[0].position)
	_open_research_picker()
	_autosave()
	print("New game: seed %d, start %s" % [map_seed, units[0].position if not units.is_empty() else Vector2i(-1, -1)])


## R on desktop. Once a game is under way it asks first, because the new world
## replaces the autosave.
func _request_new_world() -> void:
	if state.turn > 1 and not _new_world_armed:
		_new_world_armed = true
		hud.notify("Start a new world?", PackedStringArray(["Press R again to replace this game"]))
		return
	_new_world_armed = false
	_new_game(_seed_picker.randi())


func _look_at(cell: Vector2i) -> void:
	camera.look_at_world(map_view.grid_to_world(cell), _touch_zoom() if _touch_mode else START_ZOOM)


func _touch_zoom() -> float:
	return TOUCH_TILE_CSS / (TerrainTilesetBuilder.TILE_SIZE.x * UiLayout.css_per_unit)


# --- Layout and options ---------------------------------------------------------

## Re-lays out the UI for the current screen (UiLayout decided compact/full,
## touch and scale). Runs at start and on every resize or setting change.
func _apply_layout() -> void:
	var compact := UiLayout.compact
	hud.set_compact(compact)
	city_panel.set_compact(compact)
	research_picker.set_compact(compact)
	info_panel.set_compact(compact)
	hud.set_hint(_hint_text())
	InfoPopover.hide_any()
	if options_panel.visible:
		_open_options()
	if _open_city != NO_CITY:
		_refresh_city_ui()
		_frame_city(state.get_city(_open_city))


func _toggle_options() -> void:
	if options_panel.visible:
		options_panel.hide()
	else:
		_open_options()


func _open_options() -> void:
	var ids := AdvisorDefs.ids()
	options_panel.open({
		"ui_scale": ui_layout.ui_scale_setting,
		"scale": UiLayout.scale,
		"layout": ui_layout.layout_setting,
		"advisor_on": state.advisor.enabled if state != null else true,
		"advisor_name": AdvisorDefs.display_name(ids[0]) if not ids.is_empty() else "The advisor",
		"controls": _controls_text(),
	})


## Every control, one per line (the Options panel; the key-hint line only
## has room for the short version).
func _controls_text() -> String:
	if _touch_mode:
		return "\n".join([
			"Tap: select a unit, city or tile",
			"Tap a tile, then tap it again: move or attack",
			"Hold: move onto your own units, or show a tile",
			"Drag: pan   ·   Pinch: zoom",
			"Hold a stat icon: see it in full",
		])
	return "\n".join([
		"Left-click: select   ·   Right-click: move or attack",
		"B: found city   ·   F: fortify   ·   X: explore   ·   Space: skip",
		"Enter: end turn   ·   T: techs   ·   R: new world   ·   Esc: close",
		"WASD or arrows: pan   ·   Wheel: zoom",
	])


func _autosave() -> void:
	if state != null:
		SaveSystem.save(state)


func _notification(what: int) -> void:
	# Phones and browsers can close the game from the background without
	# warning, so save whenever it loses focus or is asked to close.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave()


## Resets the view and shows `new_state` (a new world or a loaded save).
func _start_game(new_state: GameState) -> void:
	state = new_state
	_new_world_armed = false
	_advisor_events.clear()
	advisor_box.clear()
	advice_marker.hide()
	_refresh_advisor_button()
	units_layer.clear_units()
	cities_layer.clear_cities()
	camps_layer.clear()
	_selected_unit = NO_UNIT
	_pending_attack = NO_CELL
	_close_city()
	_hide_tile_info()
	hud.hide_idle_prompt()
	research_picker.hide()
	tech_tree.hide()
	wonder_card.clear()
	end_screen.hide()
	_end_screen_pending = false
	hud.reset_score()
	_card_title = ""
	_card_jump = NO_CELL
	# Inset by half a tile so the jagged stacked-row edges stay off screen.
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var bounds := map_view.get_grid_world_rect(MAP_WIDTH, MAP_HEIGHT).grow_individual(-half.x, -half.y, -half.x, -half.y)
	camera.set_bounds(bounds)
	map_frame.set_bounds(bounds)
	# The seed is printed to the console (see below); the hint stays short enough to clear the buttons.
	hud.set_hint(_hint_text())
	_refresh_world()
	_select_next_unit()


## End Turn: if a city has nothing to build, ask first (pressing End Turn
## again while asked means "end anyway").
func _end_turn() -> void:
	if hud.is_idle_prompt_visible():
		_confirm_end_turn()
		return
	var idle := state.idle_cities(PLAYER)
	if not idle.is_empty():
		hud.show_idle_prompt(idle[0].id, idle[0].name, idle.size() - 1)
		return
	_confirm_end_turn()


func _confirm_end_turn() -> void:
	if _end_screen_pending:
		# The game just ended under a wonder card: show the result instead.
		_end_screen_pending = false
		wonder_card.clear()
		_show_end_screen()
		return
	hud.hide_idle_prompt()
	_new_world_armed = false
	# Ending the turn moves past any celebration still on screen.
	wonder_card.clear()
	_apply_events(GameActions.end_turn(state))
	_selected_unit = NO_UNIT
	_select_next_unit()
	_autosave()


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


## The selected unit explores on its own until it wakes up (see Exploration).
func _explore_selected_unit() -> void:
	var unit := state.get_unit(_selected_unit)
	if unit == null or unit.exploring or not Exploration.can_explore(unit):
		return
	_apply_events(GameActions.explore_unit(state, unit.id))
	_select_next_unit()


func _fortify_selected_unit() -> void:
	var unit := state.get_unit(_selected_unit)
	if unit == null or UnitDefs.can_found_city(unit.type):
		return
	_apply_events(GameActions.fortify_unit(state, unit.id))
	_select_next_unit()


## `confirmed`: the player already saw the odds (a touch preview), so a
## long-shot attack doesn't ask again.
func _order_move(cell: Vector2i, confirmed: bool = false) -> void:
	var unit := state.get_unit(_selected_unit)
	if unit == null or not state.map.in_bounds(cell):
		return
	# Long-shot attacks need a second click on the same target.
	var defender := _visible_defender(unit, cell)
	if defender != null and Combat.can_attack(unit) and not confirmed:
		var odds := Combat.win_odds(state, unit, defender)
		if odds < Combat.confirm_below_odds() and _pending_attack != cell:
			_pending_attack = cell
			hud.notify("Only %d%% to win" % roundi(odds * 100.0),
				PackedStringArray(["%s the %s again to attack anyway" % [UiText.click(), _unit_name(defender)]]))
			return
	_pending_attack = NO_CELL
	_apply_events(GameActions.move_unit(state, unit.id, cell))
	if unit.needs_orders():
		_select_unit(unit.id)
	else:
		_select_next_unit()


# --- Touch ----------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	var cell := map_view.world_to_grid(_screen_to_world(screen_pos))
	if cell == _touch_target and state.get_unit(_selected_unit) != null:
		# Second tap on the previewed tile: go (even onto your own units).
		_clear_preview()
		_order_move(cell, true)
		return
	_clear_preview()
	_on_left_click(cell, true)


## A long press is the touch right-click: it previews a move there even onto
## your own units or city, and a tap confirms it. Nothing ever moves on a
## press alone. With nothing selected it shows what's on the tile.
func _on_long_press(screen_pos: Vector2) -> void:
	var cell := map_view.world_to_grid(_screen_to_world(screen_pos))
	_clear_preview()
	var unit := state.get_unit(_selected_unit)
	if not state.map.in_bounds(cell):
		return
	if unit == null or cell == unit.position:
		_show_tile_info(cell)
		return
	_preview_move(unit, cell)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


## First tap on a destination: draw the route and say what a second tap does.
func _preview_move(unit: UnitState, cell: Vector2i) -> void:
	var path := Pathfinder.find_path(state.map, state.explored[PLAYER], unit.position, cell,
		UnitDefs.domain(unit.type), UnitDefs.ignores_terrain(unit.type))
	if path.is_empty():
		_clear_preview()
		hud.notify("No known route there")
		return
	_touch_target = cell
	_preview_path = path
	_refresh_paths()
	_update_move_tag()


func _update_move_tag() -> void:
	var unit := state.get_unit(_selected_unit)
	if _touch_target == NO_CELL or unit == null:
		return
	var at := _world_to_screen(map_view.grid_to_world(_touch_target))
	var defender := _visible_defender(unit, _touch_target)
	if defender != null and Combat.can_attack(unit):
		var odds := Combat.win_odds(state, unit, defender)
		hud.show_odds("%d%% to win   ·   tap again to attack" % roundi(odds * 100.0),
			odds >= Combat.confirm_below_odds(), at)
		return
	var turns := Movement.turns_along(unit, _preview_path, state.map, state.explored[PLAYER])
	var arrive := turns[turns.size() - 1] + 1 if not turns.is_empty() else 1
	var text := "Tap again to move"
	if arrive > 1:
		text += "   ·   %d turns" % arrive
	hud.show_move_tag(text, at)


func _clear_preview() -> void:
	if _touch_target == NO_CELL:
		return
	_touch_target = NO_CELL
	_preview_path.clear()
	hud.hide_odds()
	_refresh_paths()


func _process(_delta: float) -> void:
	# Keep the "tap again" tag on its tile while the map pans and zooms.
	if _touch_target != NO_CELL:
		_update_move_tag()


func _on_left_click(cell: Vector2i, from_touch: bool = false) -> void:
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
		if from_touch:
			# Touch never moves on the first tap: show the route and wait.
			_preview_move(selected, cell)
			return
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
	_clear_preview()
	if unit_id != NO_UNIT:
		_close_city()
	var changed := unit_id != _selected_unit
	_selected_unit = unit_id
	var unit := state.get_unit(unit_id)
	if changed and unit != null:
		_queue_advisor([{ "type": "unit_selected", "unit_id": unit_id }])
	if unit != null:
		highlight.hide()
		_show_unit_info(unit)
	elif _open_city == NO_CITY:
		info_panel.hide()
	hud.set_found_city_visible(unit != null and UnitDefs.can_found_city(unit.type))
	hud.set_fortify_visible(unit != null and not UnitDefs.can_found_city(unit.type) and not unit.fortified)
	hud.set_skip_visible(unit != null and unit.needs_orders())
	hud.set_explore_visible(unit != null and not unit.exploring and Exploration.can_explore(unit))
	_pending_attack = NO_CELL
	units_layer.sync(state, _selected_unit, map_view, PLAYER, _visible)
	_update_attack_odds()
	_refresh_paths()
	_refresh_turn_status()


# --- Cities -------------------------------------------------------------------

func _open_city_panel(city_id: int) -> void:
	_select_unit(NO_UNIT)
	highlight.hide()
	info_panel.hide()
	_open_city = city_id
	_refresh_city_ui()
	_frame_city(state.get_city(city_id))


## Keeps the open city in view: above the bottom sheet in the compact
## layout, anywhere central otherwise.
func _frame_city(city: CityState) -> void:
	if city == null:
		return
	var covered := city_panel.covered_fraction()
	if covered > 0.0:
		camera.frame_at(map_view.grid_to_world(city.position), (1.0 - covered) / 2.0)
	else:
		camera.ensure_visible(map_view.grid_to_world(city.position))


func _close_city() -> void:
	if _open_city == NO_CITY:
		return
	_open_city = NO_CITY
	city_panel.hide()
	city_overlay.clear()


func _jump_to_idle_city(city_id: int) -> void:
	hud.hide_idle_prompt()
	if state.get_city(city_id) != null:
		_open_city_panel(city_id)


func _enqueue_build(item_id: String) -> void:
	if _open_city != NO_CITY:
		_apply_events(GameActions.enqueue_build(state, _open_city, item_id))


func _remove_from_queue(index: int) -> void:
	if _open_city != NO_CITY:
		_apply_events(GameActions.remove_from_queue(state, _open_city, index))


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
	var production := CityRules.net_production(state, city)
	var queue_names: Array = []
	var queue_wonders: Array = []
	for id in city.queue:
		queue_names.append(Production.display_name(id))
		queue_wonders.append(Production.is_wonder(id))
	var available: Array = []
	for id in Production.available_items(state, city):
		available.append({
			"id": id,
			"name": Production.display_name(id),
			"cost": Production.cost(id),
			"wonder": Production.is_wonder(id),
			"tooltip": WonderDefs.effect_text(id) if Production.is_wonder(id) else "",
			# Next in line counts the stored production; behind others it starts from zero.
			"turns": Production.turns_for(city, id, production) if city.queue.is_empty() 				else (ceili(float(Production.cost(id)) / production) if production > 0 else -1),
		})
	var building_names: Array = []
	for id in city.buildings:
		building_names.append(Production.display_name(id))
	city_panel.show_city({
		"name": city.name,
		"size": city.size,
		"food_box": city.food_box,
		"food_box_size": CityRules.food_box_size(city.size),
		"food_surplus": CityRules.food_surplus(state, city),
		"turns_to_grow": CityRules.turns_to_grow(state, city),
		"production": production,
		"production_box": city.production_box,
		"upkeep": CityRules.upkeep(state, city),
		"supported": state.units_supported_by(city.id).size(),
		"free_units": CityRules.free_units(),
		"queue": queue_names,
		"current_cost": Production.cost(city.queue[0]) if not city.queue.is_empty() else 0,
		"turns_to_complete": Production.turns_to_complete(city, production),
		"blocked": Production.blocked_reason(city, city.queue[0]) if not city.queue.is_empty() else "",
		"available": available,
		"buildings": building_names,
		"queue_wonders": queue_wonders,
		"wonder_lines": _wonder_status(city),
		"trade": total[Yields.TRADE],
		"science": int(state.players[city.owner]["science"]),
		"science_per_turn": CityRules.science(state, city),
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


## One line per wonder from this city's point of view, to tease what's
## next: built (where), being built, available, or the tech it needs.
func _wonder_status(city: CityState) -> PackedStringArray:
	var parts := PackedStringArray()
	for id in WonderDefs.ids():
		var wonder_name := WonderDefs.display_name(id)
		if Wonders.is_built(state, id):
			var where := Wonders.city_of(state, id)
			var owner := Wonders.owner_of(state, id)
			var by := where.name if where != null and owner == city.owner else "the %s" % state.players[owner]["name"]
			parts.append("★ %s (%s)" % [wonder_name, by])
		elif city.queue.has(id):
			parts.append("%s: building here" % wonder_name)
		elif Wonders.queued_by(state, city.owner, id, city) != null:
			parts.append("%s: building in %s" % [wonder_name, Wonders.queued_by(state, city.owner, id, city).name])
		elif Research.has_unlocked(state, city.owner, id):
			parts.append("%s: available" % wonder_name)
		else:
			parts.append("%s: needs %s" % [wonder_name, TechDefs.display_name(TechDefs.required_for(id))])
	return parts


# --- Wonders and the end of the game --------------------------------------------

func _announce_wonder(event: Dictionary) -> void:
	var id: String = event["wonder"]
	var def := WonderDefs.get_def(id)
	var city := state.get_city(int(event["city_id"]))
	var turn := int(event["turn"])
	wonder_card.announce({
		"name": WonderDefs.display_name(id),
		"effect": WonderDefs.effect_text(id),
		"place": "%s   ·   Turn %d   ·   %s" % [city.name if city != null else "", turn,
			Calendar.format_year(Calendar.year_for_turn(turn))],
		"sprite": String(def.get("sprite", "")),
		"color": Color.html(String(def.get("placeholder_color", "#cccccc"))),
		"letter": String(def.get("letter", "?")),
	})


func _on_wonder_card_closed() -> void:
	if _end_screen_pending:
		_end_screen_pending = false
		_show_end_screen()


func _show_end_screen() -> void:
	if wonder_card.is_showing():
		_end_screen_pending = true
		return
	_close_city()
	research_picker.hide()
	tech_tree.hide()
	hud.hide_idle_prompt()
	advisor_box.clear()
	end_screen.show_result(_end_screen_info())


func _keep_playing() -> void:
	end_screen.hide()
	_apply_events(GameActions.keep_playing(state))
	_autosave()


func _end_screen_info() -> Dictionary:
	var over := state.game_over
	var winner := int(over["winner"])
	var last_turn := int(over["turn"])
	var reason := "The age has ended after %d turns" % last_turn
	if over["reason"] == Victory.WONDER_VICTORY:
		if winner == PLAYER:
			reason = "Wonder Victory!   All the wonders of the world are yours (turn %d)" % last_turn
		else:
			reason = "The %s claimed a Wonder Victory on turn %d" % [state.players[winner]["name"], last_turn]
	var breakdown := Score.breakdown(state, PLAYER)
	var rows: Array = []
	var labels := { "citizens": "Citizens", "techs": "Techs known", "wonders": "Wonders", "camps_destroyed": "Camps destroyed" }
	for part in Score.PARTS:
		var item: Dictionary = breakdown[part]
		rows.append({ "label": labels[part], "detail": "%d × %d" % [item["count"], Score.weight(part)], "points": item["points"] })
	var total := int(breakdown["total"])
	var title := Score.title_for(total)

	var wonders: Array = []
	for id in WonderDefs.ids():
		if Wonders.is_built(state, id):
			var record := Wonders.record(state, id)
			var city := Wonders.city_of(state, id)
			var owner := Wonders.owner_of(state, id)
			var where := city.name if city != null else "a lost city"
			var who := "" if owner == PLAYER else "the %s, " % state.players[owner]["name"]
			wonders.append({ "name": WonderDefs.display_name(id), "mine": owner == PLAYER,
				"detail": "%s%s, turn %d" % [who, where, record["turn"]] })
		else:
			wonders.append({ "name": WonderDefs.display_name(id), "mine": false, "detail": "never built" })

	var series: Array = []
	var markers: Array = []
	for player_id in state.civ_player_ids():
		series.append({ "name": String(state.players[player_id]["name"]),
			"color": Color.html(String(state.players[player_id]["color"])),
			"points": Score.history_of(state, player_id) })
		for id in WonderDefs.ids():
			if Wonders.is_built(state, id) and int(Wonders.record(state, id)["builder"]) == player_id:
				markers.append({ "turn": int(Wonders.record(state, id)["turn"]), "series": series.size() - 1 })

	var moments: Array = []
	for entry: Dictionary in Chronicle.entries(state):
		var player := int(entry["player"])
		var text := ""
		var color := Color(0.75, 0.78, 0.85)
		match String(entry["type"]):
			"city_founded":
				if player == PLAYER:
					text = "Founded %s" % entry["name"]
			"tech_discovered":
				if player == PLAYER:
					text = "Discovered %s" % entry["name"]
					color = Color("#8ec5ee")
			"camp_destroyed":
				if player == PLAYER:
					text = "Destroyed a barbarian camp" + (" near %s" % entry["city"] if entry["city"] != "" else "")
					color = Color("#f2b84e")
			"wonder_built":
				var by := "" if player == PLAYER else "The %s: " % state.players[player]["name"]
				text = "%sCompleted the %s in %s" % [by, entry["name"], entry["city"]]
				color = Color(1.0, 0.86, 0.4)
		if text != "":
			moments.append({ "turn": int(entry["turn"]), "text": text, "color": color })
	return {
		"reason": reason,
		"rating": String(title.get("name", "")),
		"blurb": String(title.get("blurb", "")),
		"score": total,
		"breakdown": rows,
		"wonders": wonders,
		"series": series,
		"markers": markers,
		"moments": moments,
	}


func _refresh_score() -> void:
	var breakdown := Score.breakdown(state, PLAYER)
	var lines := PackedStringArray()
	var labels := { "citizens": "Citizens", "techs": "Techs", "wonders": "Wonders", "camps_destroyed": "Camps destroyed" }
	for part in Score.PARTS:
		var item: Dictionary = breakdown[part]
		lines.append("%s   %d × %d = %d" % [labels[part], item["count"], Score.weight(part), item["points"]])
	var frozen := Victory.is_over(state)
	if frozen:
		lines.append("The game is over: the score is frozen")
	else:
		lines.append("The game ends after turn %d" % state.turn_limit)
	hud.set_score(int(breakdown["total"]), "\n".join(lines), frozen)
	if Victory.show_countdown(state):
		var left := Victory.turns_remaining(state)
		hud.set_countdown("Final turn" if left == 1 else "%d turns remaining" % left, left <= 5)
	else:
		hud.set_countdown("", false)


# --- Research -----------------------------------------------------------------

func _open_research_picker() -> void:
	var current := Research.current(state, PLAYER)
	var options: Array = []
	for id in Research.available(state, PLAYER):
		options.append({
			"id": id,
			"name": TechDefs.display_name(id),
			"turns": Research.turns_to(state, PLAYER, id),
			"unlocks": TurnNews.tech_detail(id),
		})
	if options.is_empty():
		research_picker.hide()
		return
	var title := "Choose next research"
	if current != "":
		title = "Change research"
	elif Research.known(state, PLAYER).is_empty():
		title = "Choose research"
	research_picker.open({
		"title": title,
		"subtitle": "+%d science/turn   ·   %d stored   ·   %s picks the cheapest" % [
			Research.science_per_turn(state, PLAYER), Research.stored(state, PLAYER),
			"Closing" if _touch_mode else "Esc"],
		"current": current,
		"options": options,
	})


func _choose_research(tech_id: String) -> void:
	research_picker.hide()
	tech_tree.hide()
	_apply_events(GameActions.set_research(state, PLAYER, tech_id))


## Closing the picker without a choice researches the cheapest tech.
func _dismiss_research_picker() -> void:
	research_picker.hide()
	_apply_events(GameActions.auto_pick_research(state, PLAYER))


func _toggle_tech_tree() -> void:
	if tech_tree.visible:
		tech_tree.hide()
		return
	var current := Research.current(state, PLAYER)
	var techs: Array[Dictionary] = []
	for def in TechDefs.all():
		var id := String(def["id"])
		var status := "locked"
		# The tree's lines already show what a tech leads to.
		var detail := "Unlocks: " + TurnNews.unlock_names(id) if not TechDefs.unlocks(id).is_empty() else ""
		if Research.knows(state, PLAYER, id):
			status = "known"
		elif id == current:
			status = "current"
			detail = _turns_text(Research.turns_to(state, PLAYER, id))
		elif Research.is_available(state, PLAYER, id):
			status = "available"
		techs.append({
			"id": id,
			"name": TechDefs.display_name(id),
			"tier": TechDefs.tier(id),
			"prerequisites": TechDefs.prerequisites(id),
			"status": status,
			"detail": detail,
		})
	tech_tree.open(techs)


func _turns_text(turns: int) -> String:
	if turns <= 0:
		return "no science yet"
	return "%d turn%s" % [turns, "" if turns == 1 else "s"]


func _refresh_research() -> void:
	var current := Research.current(state, PLAYER)
	hud.set_research({
		"tech_name": TechDefs.display_name(current) if current != "" else "",
		"stored": Research.stored(state, PLAYER),
		"cost": Research.cost(state, PLAYER, current) if current != "" else 0,
		"turns": Research.turns_to(state, PLAYER, current) if current != "" else -1,
		"per_turn": Research.science_per_turn(state, PLAYER),
		"done": current == "" and Research.available(state, PLAYER).is_empty(),
	})
	if research_picker.visible:
		_open_research_picker()


# --- Events → view ------------------------------------------------------------

func _apply_events(events: Array[Dictionary]) -> void:
	var new_turn := -1
	for event in events:
		match event["type"]:
			"unit_moved":
				units_layer.walk(event["unit_id"], map_view.grid_to_world(event["to"]))
			"combat":
				units_layer.play_combat(event, map_view)
			"move_failed":
				hud.notify("No known route there")
			"orders_cancelled":
				hud.notify("%s's route is blocked" % _unit_name(state.get_unit(event["unit_id"])))
			"found_failed":
				hud.notify(event["reason"])
			"city_founded":
				var city := state.get_city(event["city_id"])
				if city.owner == PLAYER:
					# The suggested site has served its purpose.
					advice_marker.hide()
				hud.notify("%s is founded!" % city.name, PackedStringArray(["%s the city to choose what to build" % UiText.click()]))
			"build_failed", "research_failed":
				hud.notify(event["reason"])
			"game_continued":
				hud.notify("The age goes on", PackedStringArray([
					"Your final score stays at %d. Play on as long as you like." % Score.score(state, PLAYER)]))
			"turn_started":
				new_turn = event["turn"]
	_queue_advisor(events)
	var news := TurnNews.describe(state, events, PLAYER)
	var lines: PackedStringArray = news["lines"]
	var highlights: PackedStringArray = news["highlights"]
	var warnings: PackedStringArray = news["warnings"]
	if new_turn != -1:
		# One batched card per turn: no popup spam.
		_card_title = "Turn %d  ·  %s" % [new_turn, _year_text()]
		_card_lines = lines
		_card_highlights = highlights
		_card_warnings = warnings
		_card_jump = news["jump"]
		_show_card(true)
	elif not (lines.is_empty() and highlights.is_empty() and warnings.is_empty()):
		# Mid-turn news (a fight, an auto-pick) joins this turn's card.
		if _card_title == "":
			_card_title = "Turn %d  ·  %s" % [state.turn, _year_text()]
		_card_lines.append_array(lines)
		_card_highlights.append_array(highlights)
		_card_warnings.append_array(warnings)
		if news["jump"] != NO_CELL:
			_card_jump = news["jump"]
		_show_card(not highlights.is_empty())
	_refresh_world()
	for event: Dictionary in news["wonders"]:
		_announce_wonder(event)
	if bool(news["game_over"]):
		_show_end_screen()
		return
	if bool(news["discovered"]):
		_open_research_picker()
	elif new_turn != -1 and research_picker.visible and Research.current(state, PLAYER) != "":
		# Ending the turn with the picker open auto-picked; the choice is made.
		research_picker.hide()


# --- Advisor --------------------------------------------------------------------

func _queue_advisor(events: Array[Dictionary]) -> void:
	if state == null:
		return
	_advisor_events.append_array(events)
	if not _advisor_pending:
		_advisor_pending = true
		_run_advisor.call_deferred()


func _run_advisor() -> void:
	_advisor_pending = false
	var events := _advisor_events.duplicate()
	_advisor_events.clear()
	if state == null or end_screen.visible:
		return
	var message := AdvisorDirector.observe(state, PLAYER, events)
	if message.is_empty():
		return
	advisor_box.say(message)
	var cell: Vector2i = message["highlight"]
	if cell != NO_CELL:
		advice_marker.show_at(map_view.grid_to_world(cell))
		camera.ensure_visible(map_view.grid_to_world(cell))


func _toggle_advisor() -> void:
	AdvisorDirector.set_enabled(state, not state.advisor.enabled)
	if not state.advisor.enabled:
		advisor_box.clear()
		advice_marker.hide()
	_refresh_advisor_button()
	_autosave()


func _refresh_advisor_button() -> void:
	var ids := AdvisorDefs.ids()
	hud.set_advisor_enabled(state.advisor.enabled, AdvisorDefs.display_name(ids[0]) if not ids.is_empty() else "")


func _show_card(celebrate: bool) -> void:
	hud.notify(_card_title, _card_lines, {
		"highlights": _card_highlights,
		"warnings": _card_warnings,
		"celebrate": celebrate,
		"clickable": _card_jump != NO_CELL,
	})


func _jump_to_card_place() -> void:
	if _card_jump != NO_CELL:
		camera.ensure_visible(map_view.grid_to_world(_card_jump))
		_show_tile_info(_card_jump)


func _refresh_world() -> void:
	var explored := state.explored[PLAYER]
	_visible = Fog.compute_visible(state, PLAYER)
	map_view.render(state.map, explored)
	territory_layer.sync(state, map_view, PLAYER)
	fog_view.refresh(state.map.width, state.map.height, explored, _visible)
	cities_layer.sync(state, map_view)
	camps_layer.sync(state, map_view, PLAYER)
	units_layer.sync(state, _selected_unit, map_view, PLAYER, _visible)
	_update_attack_odds()
	_refresh_paths()
	_refresh_city_ui()
	_refresh_research()
	hud.set_turn(state.turn, _year_text())
	_refresh_score()
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
			"active": unit.id == _selected_unit and _touch_target == NO_CELL,
		})
	var selected := state.get_unit(_selected_unit)
	if _touch_target != NO_CELL and selected != null and not _preview_path.is_empty():
		var preview := PackedVector2Array()
		for cell in _preview_path:
			preview.append(map_view.grid_to_world(cell))
		paths.append({
			"start": map_view.grid_to_world(selected.position),
			"points": preview,
			"turns": Movement.turns_along(selected, _preview_path, state.map, state.explored[PLAYER]),
			"active": true,
		})
	path_overlay.show_paths(paths)


func _refresh_turn_status() -> void:
	var idle := state.idle_cities(PLAYER)
	if idle.is_empty():
		hud.hide_idle_prompt()
	hud.set_turn_done(state.units_needing_orders(PLAYER).is_empty() and idle.is_empty())


# --- Info panel ---------------------------------------------------------------

func _show_unit_info(unit: UnitState) -> void:
	var def := UnitDefs.get_def(unit.type)
	var details := "Moves %d/%d   ·   Attack %d   ·   Defense %d   ·   HP %d/%d" % [
		unit.moves_left, unit.max_moves(), int(def.get("attack", 0)), int(def.get("defense", 0)),
		unit.hp, Combat.max_hp()]
	if unit.fortified:
		details += "\nFortified (+%d%% defense until it moves)" % Combat.fortified_percent()
	if unit.exploring:
		details += "\nExploring on its own   ·   give it any order to stop"
	elif unit.has_goal():
		var turns := Movement.path_turns(unit, state.map, state.explored[unit.owner])
		var eta: int = turns.back() + 1 if not turns.is_empty() else 1
		details += "\nHeading to (%d, %d)  ·  %d turn%s" % [unit.goal.x, unit.goal.y, eta, "" if eta == 1 else "s"]
	else:
		var terrain := TerrainDefs.get_def(state.map.get_terrain(unit.position))
		details += "\n%s at (%d, %d)" % [terrain["name"], unit.position.x, unit.position.y]
		if UnitDefs.can_found_city(unit.type):
			var reason := CityRules.can_found(state, unit)
			details += "\n" + (_found_city_hint() if reason == "" else reason)
		elif not Combat.can_attack(unit):
			details += "\nCan't attack   ·   " + ("Tap Explore to scout on its own" if _touch_mode else "X: explore on its own")
		elif not unit.fortified:
			details += "\nTap an enemy twice to attack" if _touch_mode else "\nF: fortify   ·   Right-click an enemy to attack"
	info_panel.show_info(def["name"], details, Color.html(state.players[unit.owner]["color"]))


func _found_city_hint() -> String:
	return "Tap Found City to settle here" if _touch_mode else "Press B to found a city here"


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
	var details := "%s   ·   tile (%d, %d)" % [cost, cell.x, cell.y]
	if TerrainDefs.defense_percent(id) > 0:
		details += "   ·   Defense +%d%%" % TerrainDefs.defense_percent(id)
	var camp := state.camp_at(cell)
	if camp != null and camp.discovered_by.has(PLAYER):
		details += "\nBarbarian camp: move a unit onto it to destroy it"
	if _is_visible(cell):
		for enemy in state.enemy_units_at(cell, PLAYER):
			details += "\nBarbarian %s   ·   HP %d/%d%s" % [_unit_name(enemy), enemy.hp, Combat.max_hp(),
				"   ·   fortified" if enemy.fortified else ""]
	info_panel.show_info(def["name"], details, Color.html(def["placeholder_color"]), y)


func _is_visible(cell: Vector2i) -> bool:
	return not _visible.is_empty() and _visible[IsoGrid.index_of(cell, state.map.width)] == 1


## The enemy that would defend `cell` against `unit`, if the player can see it.
func _visible_defender(unit: UnitState, cell: Vector2i) -> UnitState:
	if not state.map.in_bounds(cell) or not _is_visible(cell):
		return null
	return Combat.best_defender(state, cell, unit)


## "72% to win" beside the mouse while a combat unit is selected and the
## mouse is over a visible enemy.
func _update_attack_odds() -> void:
	if _touch_mode:
		# No hover on touch: the move preview shows the odds instead.
		return
	var unit := state.get_unit(_selected_unit) if state != null else null
	if unit == null or not Combat.can_attack(unit):
		hud.hide_odds()
		return
	var defender := _visible_defender(unit, map_view.world_to_grid(get_global_mouse_position()))
	if defender == null:
		hud.hide_odds()
		return
	var odds := Combat.win_odds(state, unit, defender)
	hud.show_odds("%d%% to win vs %s" % [roundi(odds * 100.0), _unit_name(defender)],
		odds >= Combat.confirm_below_odds(), get_viewport().get_mouse_position())


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
