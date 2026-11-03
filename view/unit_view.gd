class_name UnitView
extends Node2D
## Draws one unit: its sprite (or placeholder shield), a selection ring, a
## stack marker, an HP bar when hurt, and a fortified marker. Animates moves
## step by step and plays its side of a fight (lunge or shake, HP draining,
## fading out if it dies).

const SHIELD_SIZE := Vector2(22, 26)
## The sprite stands slightly above the tile center.
const SPRITE_OFFSET := Vector2(0, -10)
const STEP_TIME := 0.14
const RING_COLOR := Color(1.0, 0.93, 0.55)
const RING_RADIUS := 24.0
const HP_BAR_SIZE := Vector2(24, 4)
const HP_BAR_Y := -30.0
const LUNGE_TIME := 0.12
const DRAIN_TIME := 0.4
const DEATH_TIME := 0.35
## Barbarian shields are dark; a light rim keeps them readable on any terrain.
const DARK_RIM := Color(0.85, 0.75, 0.55)

var unit_id := -1
var selected := false:
	set(value):
		selected = value
		_time = 0.0
		queue_redraw()
var stack_count := 1:
	set(value):
		if value != stack_count:
			stack_count = value
			queue_redraw()

var _letter := ""
var _color := Color.WHITE
var _texture: Texture2D
var _time := 0.0
var _waypoints: Array[Vector2] = []
var _walking := false
var _max_hp := 10
var _hp_shown := 10.0:
	set(value):
		_hp_shown = value
		queue_redraw()
var _fortified := false
## Offset of the body during a lunge or shake.
var _offset := Vector2.ZERO:
	set(value):
		_offset = value
		queue_redraw()
var _fighting := false


func setup(id: int, def: Dictionary, owner_color: Color, max_hp: int) -> void:
	unit_id = id
	# Data may give a short label ("Sc") where first letters would clash.
	_letter = String(def.get("letter", String(def.get("name", "?")).left(1).to_upper()))
	_color = owner_color
	_texture = SpriteLibrary.get_texture(String(def.get("sprite", "")))
	_max_hp = max_hp
	_hp_shown = max_hp


func is_walking() -> bool:
	return _walking


func is_busy() -> bool:
	return _walking or _fighting


## HP and fortify state from the game state (ignored mid-fight; the fight
## animation drains HP itself).
func set_status(hp: int, fortified: bool) -> void:
	if not _fighting:
		_hp_shown = hp
	if fortified != _fortified:
		_fortified = fortified
		queue_redraw()


## Seconds until queued steps finish, so a fight can wait for the walk.
func pending_time() -> float:
	return _waypoints.size() * STEP_TIME + (STEP_TIME if _walking else 0.0)


## Queues a one-tile step; steps play back to back.
func walk_to(world_pos: Vector2) -> void:
	_waypoints.append(world_pos)
	if not _walking:
		_next_step()


func _next_step() -> void:
	if _waypoints.is_empty():
		_walking = false
		return
	_walking = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position", _waypoints.pop_front(), STEP_TIME)
	tween.finished.connect(_next_step)


## Plays this unit's part of a fight after `delay` seconds: the attacker
## lunges toward `toward`, the defender shakes; HP drains to `final_hp`;
## the loser fades out and frees itself.
func play_fight(attacking: bool, toward: Vector2, delay: float, final_hp: int, dies: bool) -> void:
	_fighting = true
	var tween := create_tween()
	tween.tween_interval(delay)
	if attacking:
		var lunge := (toward - position) * 0.4
		tween.tween_property(self, "_offset", lunge, LUNGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "_offset", Vector2.ZERO, LUNGE_TIME * 1.5)
	else:
		tween.tween_interval(LUNGE_TIME * 0.8)
		for x: float in [3.0, -3.0, 2.0, 0.0]:
			tween.tween_property(self, "_offset", Vector2(x, 0), 0.04)
	tween.parallel().tween_property(self, "_hp_shown", float(final_hp), DRAIN_TIME)
	if dies:
		tween.tween_property(self, "modulate:a", 0.0, DEATH_TIME)
		tween.tween_callback(queue_free)
	else:
		tween.tween_callback(func() -> void: _fighting = false)


func _process(delta: float) -> void:
	if selected:
		_time += delta
		queue_redraw()


func _draw() -> void:
	if selected:
		var alpha := 0.55 + 0.45 * sin(_time * 6.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 40, Color(RING_COLOR, alpha), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _fortified:
		_draw_fortification()

	# The selected unit hops gently so it's easy to spot.
	var hop := -2.5 * absf(sin(_time * 4.0)) if selected else 0.0
	var center := SPRITE_OFFSET + Vector2(0, hop) + _offset
	if stack_count > 1:
		_draw_body(center + Vector2(4, -3), _color.darkened(0.35))
	_draw_body(center, _color)
	if _hp_shown < _max_hp:
		_draw_hp_bar(Vector2(0, HP_BAR_Y + hop) + _offset)


func _draw_body(center: Vector2, color: Color) -> void:
	if _texture != null:
		draw_texture(_texture, center - _texture.get_size() / 2.0, Color.WHITE if color == _color else Color(0.6, 0.6, 0.6))
		return
	if color.get_luminance() < 0.2:
		# A light rim behind a dark shield.
		PlaceholderArt.draw_shield(self, center, SHIELD_SIZE + Vector2(4, 4), DARK_RIM, "")
	PlaceholderArt.draw_shield(self, center, SHIELD_SIZE, color, _letter)


## A low stone wall arc in front of the unit.
func _draw_fortification() -> void:
	var stone := Color(0.62, 0.6, 0.55)
	for i in 5:
		var angle := PI * (0.15 + 0.175 * i)
		var at := Vector2(cos(angle) * 17.0, sin(angle) * 7.0 + 2.0)
		var rect := Rect2(at - Vector2(4, 3), Vector2(8, 6))
		draw_rect(rect, stone)
		draw_rect(rect, stone.darkened(0.55), false, 1.0)


func _draw_hp_bar(center: Vector2) -> void:
	var rect := Rect2(center - HP_BAR_SIZE / 2.0, HP_BAR_SIZE)
	var fraction := clampf(_hp_shown / _max_hp, 0.0, 1.0)
	var fill := Color(0.9, 0.25, 0.2).lerp(Color(0.45, 0.85, 0.3), fraction)
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * fraction, rect.size.y)), fill)
