class_name WonderCard
extends PanelContainer
## The big payoff moment: a gold card announcing a finished wonder, with its
## icon, name, effect and where/when it was built. It never blocks the turn
## loop: a click, Esc or End Turn closes it, and it leaves by itself after a
## few seconds. Several wonders in one turn queue up.

signal closed

const SHOW_TIME := 5.5
const ICON_SIZE := 64.0
const CARD_BG := Color(0.16, 0.11, 0.03, 0.96)
const BRIGHT_GOLD := Color(1.0, 0.86, 0.4)
const CARD_WIDTH := 440.0

var _queue: Array[Dictionary] = []
var _title: Label
var _name_label: Label
var _effect_label: Label
var _place_label: Label
var _icon: Control
var _icon_info: Dictionary = {}
var _timer: Tween
var _pop: Tween


func _ready() -> void:
	var style := UiStyle.panel()
	style.bg_color = CARD_BG
	style.border_color = BRIGHT_GOLD
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(22)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 12
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_input)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _label(box, 15, UiStyle.GOLD)
	_title.text = "A WONDER OF THE WORLD"
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	box.add_child(_icon)
	_name_label = _label(box, 30, BRIGHT_GOLD)
	_name_label.add_theme_color_override("font_outline_color", Color(0.3, 0.18, 0.0))
	_name_label.add_theme_constant_override("outline_size", 6)
	_effect_label = _label(box, 17, Color.WHITE)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.custom_minimum_size = Vector2(CARD_WIDTH - 44.0, 0)
	_place_label = _label(box, 14, Color(0.8, 0.78, 0.7))
	var hint := _label(box, 12, Color(0.6, 0.58, 0.5))
	hint.text = "click to continue"
	hide()


func _label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## `info`: { name, effect, place ("Rome · Turn 47 · 1750 BC"), sprite, color, letter }.
func announce(info: Dictionary) -> void:
	_queue.append(info)
	if not visible:
		_show_next()


func is_showing() -> bool:
	return visible


## Closes the current card (and shows the next queued one, if any).
func dismiss() -> void:
	if not visible:
		return
	if _timer != null:
		_timer.kill()
	if _queue.is_empty():
		hide()
		closed.emit()
	else:
		_show_next()


## Drops everything (new game).
func clear() -> void:
	_queue.clear()
	if _timer != null:
		_timer.kill()
	hide()


func _show_next() -> void:
	var info: Dictionary = _queue.pop_front()
	_name_label.text = String(info["name"])
	_effect_label.text = String(info["effect"])
	_place_label.text = String(info["place"])
	_icon_info = info
	_icon.queue_redraw()
	show()
	size = get_combined_minimum_size()
	var area := get_viewport_rect().size
	position = ((area - size) / 2.0 - Vector2(0, area.y * 0.08)).floor()
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 0.6
	modulate.a = 0.0
	if _pop != null:
		_pop.kill()
	_pop = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop.tween_property(self, "scale", Vector2.ONE, 0.35)
	_pop.tween_property(self, "modulate:a", 1.0, 0.2)
	var parent := get_parent() as Control
	if parent != null:
		var center := position + size / 2.0
		CelebrationBurst.play(parent, center, maxf(220.0, size.x * 0.75))
		CelebrationBurst.play(parent, center + Vector2(-size.x * 0.45, -size.y * 0.3), 90.0)
		CelebrationBurst.play(parent, center + Vector2(size.x * 0.45, -size.y * 0.3), 90.0)
	_timer = create_tween()
	_timer.tween_interval(SHOW_TIME)
	_timer.tween_property(self, "modulate:a", 0.0, 0.4)
	_timer.tween_callback(dismiss)


func _draw_icon() -> void:
	if _icon_info.is_empty():
		return
	var center := Vector2(ICON_SIZE, ICON_SIZE) / 2.0
	var texture := SpriteLibrary.get_texture(String(_icon_info.get("sprite", "")))
	if texture != null:
		_icon.draw_texture_rect(texture, Rect2(Vector2.ZERO, Vector2(ICON_SIZE, ICON_SIZE)), false)
	else:
		PlaceholderArt.draw_wonder_marker(_icon, center, ICON_SIZE, _icon_info.get("color", Color.WHITE),
			String(_icon_info.get("letter", "?")), 0.6)


func _on_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
		accept_event()
