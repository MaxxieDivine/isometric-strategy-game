extends Node2D
## Session glue: owns the game state and hands it to the view.

const FRAME_MARGIN := 0.95

var map_state: MapState

@onready var map_view: MapView = $MapView
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	map_state = SampleMap.create()
	map_view.render(map_state)
	_frame_camera()
	get_viewport().size_changed.connect(_frame_camera)


func _frame_camera() -> void:
	var rect := map_view.get_map_pixel_rect()
	if rect.size == Vector2.ZERO:
		return
	var viewport_size := get_viewport_rect().size
	var zoom := minf(viewport_size.x / rect.size.x, viewport_size.y / rect.size.y) * FRAME_MARGIN
	camera.position = map_view.position + rect.get_center()
	camera.zoom = Vector2(zoom, zoom)
