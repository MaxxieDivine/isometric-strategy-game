class_name AdvisorBox
extends HBoxContainer
## An advisor speaking: a framed portrait in the bottom-left corner with a
## short speech box beside it. Never blocks the map: only the portrait and the
## box take clicks. Clicking either, or ✕, dismisses it; otherwise it fades
## on its own (the timer pauses while the mouse is over it). It slides to the
## right of `avoid` (the research picker) while that is open.

signal dismissed

const PORTRAIT_SIZE := Vector2(76, 92)
const SPEECH_WIDTH := 290.0
const MARGIN := 12.0
## Room left below for the key-hint line (matches the research picker).
const BOTTOM_CLEARANCE := 40.0
const BASE_TIME := 6.0
const TIME_PER_CHAR := 0.06
const REVEAL_CHARS_PER_SECOND := 120.0
const TAIL_WIDTH := 10.0
const MUTED := Color(0.62, 0.65, 0.72)

## Stay clear of this control (to its right) while it is visible.
var avoid: Control

var _portrait: AdvisorPortrait
var _tail: Control
var _speech: PanelContainer
var _name_label: Label
var _title_label: Label
var _text_label: Label
var _time_left := 0.0
var _closing := false
var _x := MARGIN
## Extra drop below the resting place, tweened to 0 as the box slides in.
var _slide := 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	alignment = BoxContainer.ALIGNMENT_BEGIN

	_portrait = AdvisorPortrait.new()
	_portrait.custom_minimum_size = PORTRAIT_SIZE
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_END
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait.gui_input.connect(_on_click)
	add_child(_portrait)

	_tail = Control.new()
	_tail.custom_minimum_size = Vector2(TAIL_WIDTH, 0)
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above the speech box, so the tail's base covers the box's border.
	_tail.z_index = 1
	_tail.draw.connect(_draw_tail)
	add_child(_tail)

	_speech = PanelContainer.new()
	var style := UiStyle.panel()
	style.set_corner_radius_all(6)
	style.content_margin_top = 6
	_speech.add_theme_stylebox_override("panel", style)
	_speech.size_flags_vertical = Control.SIZE_SHRINK_END
	_speech.mouse_filter = Control.MOUSE_FILTER_STOP
	_speech.gui_input.connect(_on_click)
	add_child(_speech)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech.add_child(box)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.add_theme_color_override("font_color", UiStyle.GOLD)
	header.add_child(_name_label)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", MUTED)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_title_label)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(dismiss)
	header.add_child(close)
	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 15)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(SPEECH_WIDTH, 0)
	box.add_child(_text_label)
	hide()


## Shows a message from AdvisorDirector.observe (name, title, portrait,
## placeholder_color, text).
func say(message: Dictionary) -> void:
	var speaker := String(message.get("name", ""))
	_name_label.text = speaker
	_title_label.text = "  " + String(message.get("title", ""))
	_portrait.set_portrait(String(message.get("portrait", "")),
		Color.html(String(message.get("placeholder_color", "#8899aa"))), speaker.left(1).to_upper())
	var text := String(message.get("text", ""))
	_text_label.text = text
	_text_label.visible_ratio = 0.0
	_time_left = BASE_TIME + TIME_PER_CHAR * text.length()
	_closing = false
	show()
	reset_size()
	_place(true)
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	_slide = 18.0
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2)
	_tween.tween_property(self, "_slide", 0.0, 0.25)
	_tween.tween_property(_text_label, "visible_ratio", 1.0, text.length() / REVEAL_CHARS_PER_SECOND)
	_tail.queue_redraw()


func is_showing() -> bool:
	return visible and not _closing


## Closes the box (quickly) and emits `dismissed`.
func dismiss() -> void:
	if not is_showing():
		return
	_fade_out(0.15)
	dismissed.emit()


## Hides at once (new game, advisor turned off).
func clear() -> void:
	if _tween != null:
		_tween.kill()
	_closing = false
	hide()


func _fade_out(duration: float) -> void:
	_closing = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, duration)
	_tween.tween_callback(hide)


func _process(delta: float) -> void:
	if not visible:
		return
	_place(false, delta)
	if _closing:
		return
	var mouse := get_global_mouse_position()
	var hovered := _speech.get_global_rect().has_point(mouse) or _portrait.get_global_rect().has_point(mouse)
	if not hovered:
		_time_left -= delta
		if _time_left <= 0.0:
			_fade_out(0.6)


## Bottom-left above the key hints; glides right of `avoid` while it's open.
func _place(snap: bool, delta: float = 0.0) -> void:
	var target := MARGIN
	if avoid != null and avoid.visible:
		target = avoid.get_global_rect().end.x + MARGIN
	_x = target if snap else lerpf(_x, target, minf(1.0, delta * 12.0))
	position.x = _x
	# Recomputed every frame: the wrapped text settles its height a frame late.
	position.y = get_viewport_rect().size.y - size.y - BOTTOM_CLEARANCE + _slide


func _on_click(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		dismiss()


## The speech box's little tail pointing at the portrait.
func _draw_tail() -> void:
	var h := _tail.size.y
	var y := h - PORTRAIT_SIZE.y * 0.55
	var points := PackedVector2Array([Vector2(TAIL_WIDTH + 2, y - 8), Vector2(0, y), Vector2(TAIL_WIDTH + 2, y + 8)])
	_tail.draw_colored_polygon(points, UiStyle.PANEL_BG)
	_tail.draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), UiStyle.GOLD, 2.0, true)
