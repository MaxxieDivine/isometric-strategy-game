class_name InfoPopover
extends PanelContainer
## A small floating card with the full text behind a compact chip or
## indicator (long-press or tap a chip; tap a top-bar chip for its panel).
## One at a time: showing another replaces it. Tap it to close; it also
## fades after a while. Never blocks the map.

const MAX_WIDTH := 340.0
const SHOW_TIME := 5.0

## The one popover in the UI (view state), so any chip can use it.
static var current: InfoPopover

var _title: Label
var _body: Label
var _tween: Tween


func _ready() -> void:
	current = self
	add_theme_stylebox_override("panel", UiStyle.panel())
	mouse_filter = Control.MOUSE_FILTER_STOP
	top_level = true
	z_index = 50
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", UiLayout.BODY_FONT + 2)
	_title.add_theme_color_override("font_color", UiStyle.GOLD)
	box.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_size_override("font_size", UiLayout.BODY_FONT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed:
			accept_event()
			dismiss())
	hide()


## Shows `body` (and `title`, if any) next to `anchor` (a global rect).
static func show_text(title: String, body: String, anchor: Rect2) -> void:
	if current != null and is_instance_valid(current):
		current._show(title, body, anchor)


static func hide_any() -> void:
	if current != null and is_instance_valid(current):
		current.dismiss()


func dismiss() -> void:
	if _tween != null:
		_tween.kill()
	hide()


func _show(title: String, body: String, anchor: Rect2) -> void:
	_title.text = title
	_title.visible = title != ""
	_body.text = body
	_body.visible = body != ""
	_body.custom_minimum_size = Vector2.ZERO
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	if _body.get_combined_minimum_size().x > MAX_WIDTH:
		# Wrap, measured at the width it will have (a wrapped label reports its
		# height for its current width).
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.custom_minimum_size = Vector2(MAX_WIDTH, 0)
		_body.size = Vector2(MAX_WIDTH, 0)
	show()
	size = Vector2.ZERO
	reset_size()
	var view := get_viewport_rect().size
	var pos := Vector2(anchor.get_center().x - size.x / 2.0, anchor.end.y + 6.0)
	if pos.y + size.y > view.y - 4.0:
		pos.y = anchor.position.y - size.y - 6.0
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view.x - size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, view.y - size.y - 4.0))
	global_position = pos
	if _tween != null:
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(SHOW_TIME)
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(hide)
