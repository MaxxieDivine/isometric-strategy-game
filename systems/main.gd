extends Node2D
## Session glue: owns the game state, hands it to the view, and turns input
## into actions. Tile selection is view state, not game state.

const MAP_WIDTH := 40
const MAP_HEIGHT := 80
const NO_SELECTION := Vector2i(-1, -1)

var map_state: MapState
var _selected_cell := NO_SELECTION
## Only picks seeds for new worlds; gameplay randomness lives in game state.
var _seed_picker := RandomNumberGenerator.new()

@onready var map_view: MapView = $MapView
@onready var highlight: TileHighlight = $TileHighlight
@onready var camera: MapCamera = $MapCamera
@onready var tile_info: TileInfoPanel = $UI/TileInfoPanel
@onready var seed_label: Label = $UI/SeedLabel


func _ready() -> void:
	InputActions.ensure_defaults()
	_seed_picker.randomize()
	_new_world(_seed_picker.randi())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate_map"):
		_new_world(_seed_picker.randi())
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_select(map_view.world_to_grid(get_global_mouse_position()))
		get_viewport().set_input_as_handled()


func _new_world(map_seed: int) -> void:
	map_state = MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, map_seed)
	map_view.render(map_state)
	# Inset by half a tile so the jagged stacked-row edges stay off screen.
	var half := Vector2(TerrainTilesetBuilder.TILE_SIZE) / 2.0
	var bounds := map_view.get_map_world_rect().grow_individual(-half.x, -half.y, -half.x, -half.y)
	camera.set_bounds(bounds)
	camera.look_at_world(bounds.get_center(), 1.0)
	_select(NO_SELECTION)
	seed_label.text = "Seed %d   ·   R: new world" % map_seed
	print("Generated world: seed %d, %d continents" % [map_seed, MapGenerator.count_continents(map_state)])


func _select(cell: Vector2i) -> void:
	if not map_state.in_bounds(cell):
		_selected_cell = NO_SELECTION
		highlight.hide()
		tile_info.hide()
		return
	_selected_cell = cell
	highlight.show_at(map_view.grid_to_world(cell))
	tile_info.show_tile(cell, TerrainDefs.get_def(map_state.get_terrain(cell)))
