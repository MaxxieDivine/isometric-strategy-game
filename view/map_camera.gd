class_name MapCamera
extends Camera2D
## Strategy-map camera: WASD/arrow and screen-edge panning, smooth mouse-wheel
## zoom toward the cursor, always clamped to the map bounds.

## Pan speed in screen pixels per second (constant feel at any zoom).
const PAN_SPEED := 900.0
## Mouse within this many pixels of the window edge pans the camera.
const EDGE_PAN_MARGIN := 12.0
const ZOOM_STEP := 1.15
## Tiles drawn at 2× size at most.
const MAX_ZOOM := 2.0
## Zoom-out stops once the whole map fits, but never below this.
const MIN_ZOOM_FLOOR := 0.2
const ZOOM_SMOOTHING := 14.0
## ensure_visible() moves the camera when a point is within this fraction of the edge.
const FOLLOW_MARGIN := 0.2
const GLIDE_TIME := 0.3

var _bounds := Rect2()
var _min_zoom := MIN_ZOOM_FLOOR
var _target_zoom := 1.0
## Viewport position the current zoom is anchored to (the cursor when zooming).
var _zoom_anchor := Vector2.ZERO
var _mouse_in_window := false
var _glide: Tween
## Off on touch screens, where a finger near the edge isn't a request to pan.
var edge_pan_enabled := true


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)
	get_window().mouse_entered.connect(func() -> void: _mouse_in_window = true)
	get_window().mouse_exited.connect(func() -> void: _mouse_in_window = false)


## Sets the world rect the view must stay inside and recomputes zoom limits.
func set_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	_update_min_zoom()
	_target_zoom = clampf(_target_zoom, _min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * _target_zoom
	_clamp_position()


func look_at_world(world_pos: Vector2, new_zoom: float = 1.0) -> void:
	_stop_glide()
	_target_zoom = clampf(new_zoom, _min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * _target_zoom
	position = world_pos
	_clamp_position()


## Glides to `world_pos` if it's outside the central part of the view.
func ensure_visible(world_pos: Vector2) -> void:
	var half_view := get_viewport_rect().size / 2.0 / zoom.x * (1.0 - FOLLOW_MARGIN)
	if Rect2(position - half_view, half_view * 2.0).has_point(world_pos):
		return
	_stop_glide()
	_glide = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_glide.tween_property(self, "position", _clamped(world_pos), GLIDE_TIME)


## Moves the view by a finger drag: the map follows the finger.
func pan_screen(delta: Vector2) -> void:
	_stop_glide()
	position -= delta / zoom.x
	_clamp_position()


## Pinch zoom: scales by `factor` and keeps the point under `anchor` in place.
func zoom_screen(factor: float, anchor: Vector2) -> void:
	_stop_glide()
	var before := _viewport_to_world(anchor)
	_target_zoom = clampf(zoom.x * factor, _min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * _target_zoom
	position += before - _viewport_to_world(anchor)
	_clamp_position()


func _stop_glide() -> void:
	if _glide != null:
		_glide.kill()
		_glide = null


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_toward(ZOOM_STEP, button.position)
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_toward(1.0 / ZOOM_STEP, button.position)


func _process(delta: float) -> void:
	var direction := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	direction += _edge_pan_direction()
	if direction != Vector2.ZERO:
		_stop_glide()
		position +=direction.limit_length(1.0) * PAN_SPEED * delta / zoom.x

	if not is_equal_approx(zoom.x, _target_zoom):
		var anchor_before := _viewport_to_world(_zoom_anchor)
		var z := lerpf(zoom.x, _target_zoom, 1.0 - exp(-ZOOM_SMOOTHING * delta))
		if absf(z - _target_zoom) < 0.001:
			z = _target_zoom
		zoom = Vector2.ONE * z
		# Keep the point under the cursor fixed while zooming.
		position += anchor_before - _viewport_to_world(_zoom_anchor)

	_clamp_position()


func _zoom_toward(factor: float, viewport_pos: Vector2) -> void:
	_target_zoom = clampf(_target_zoom * factor, _min_zoom, MAX_ZOOM)
	_zoom_anchor = viewport_pos
	get_viewport().set_input_as_handled()


func _edge_pan_direction() -> Vector2:
	if not edge_pan_enabled or not _mouse_in_window or not get_window().has_focus():
		return Vector2.ZERO
	var size := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	var direction := Vector2.ZERO
	if mouse.x < EDGE_PAN_MARGIN:
		direction.x -= 1.0
	elif mouse.x > size.x - EDGE_PAN_MARGIN:
		direction.x += 1.0
	if mouse.y < EDGE_PAN_MARGIN:
		direction.y -= 1.0
	elif mouse.y > size.y - EDGE_PAN_MARGIN:
		direction.y += 1.0
	return direction


func _viewport_to_world(viewport_pos: Vector2) -> Vector2:
	return position + (viewport_pos - get_viewport_rect().size / 2.0) / zoom.x


func _update_min_zoom() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var size := get_viewport_rect().size
	var fit := minf(size.x / _bounds.size.x, size.y / _bounds.size.y)
	_min_zoom = clampf(fit, MIN_ZOOM_FLOOR, MAX_ZOOM)


func _clamp_position() -> void:
	position = _clamped(position)


func _clamped(pos: Vector2) -> Vector2:
	if _bounds.size == Vector2.ZERO:
		return pos
	var half_view := get_viewport_rect().size / 2.0 / zoom.x
	for axis in 2:
		if half_view[axis] * 2.0 >= _bounds.size[axis]:
			pos[axis] = _bounds.get_center()[axis]
		else:
			pos[axis] = clampf(pos[axis],
				_bounds.position[axis] + half_view[axis],
				_bounds.end[axis] - half_view[axis])
	return pos


func _on_viewport_resized() -> void:
	_update_min_zoom()
	_target_zoom = clampf(_target_zoom, _min_zoom, MAX_ZOOM)
	zoom = Vector2.ONE * clampf(zoom.x, _min_zoom, MAX_ZOOM)
	_clamp_position()
