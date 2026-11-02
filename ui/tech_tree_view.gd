class_name TechTreeView
extends PanelContainer
## The whole tech tree: one column per tier, known / researching / available /
## locked techs, and prerequisite lines. Clicking an available tech researches it.

signal tech_chosen(tech_id: String)
signal close_requested

const NODE_SIZE := Vector2(176, 52)
const COLUMN_GAP := 70.0
const ROW_GAP := 12.0
const LINE_WIDTH := 3.0
const STATUS_BG := {
	"known": Color(0.18, 0.36, 0.2, 0.98),
	"current": Color(0.55, 0.38, 0.1, 0.98),
	"available": Color(0.14, 0.2, 0.34, 0.98),
	"locked": Color(0.12, 0.12, 0.14, 0.98),
}
const STATUS_TEXT := {
	"known": "Known",
	"current": "Researching",
	"available": "Available",
	"locked": "Locked",
}
const LINE_KNOWN := Color(0.85, 0.75, 0.45)
const LINE_LOCKED := Color(0.32, 0.33, 0.38)
const MUTED := Color(0.6, 0.62, 0.68)

var _canvas: Control
## [{ from: tech id, to: tech id, known: bool }]
var _links: Array[Dictionary] = []
var _rects: Dictionary = {}
## Tech id -> where its outgoing vertical line sits across the gap (0..1).
var _trunk: Dictionary = {}


func _ready() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)
	var title := Label.new()
	title.text = "Technology"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiStyle.GOLD)
	header.add_child(title)
	for status: String in ["known", "current", "available", "locked"]:
		var swatch := ColorRect.new()
		swatch.color = STATUS_BG[status]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(swatch)
		var label := Label.new()
		label.text = STATUS_TEXT[status]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", MUTED)
		header.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	_canvas = Control.new()
	_canvas.draw.connect(_draw_links)
	box.add_child(_canvas)

	var hint := Label.new()
	hint.text = "Click an available tech to research it   ·   T or Esc to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MUTED)
	box.add_child(hint)
	hide()


## `techs`: Array of { id, name, tier, prerequisites (Array), status
## ("known" | "current" | "available" | "locked"), detail (String) }, in data order.
func open(techs: Array[Dictionary]) -> void:
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	_links.clear()
	_rects.clear()
	_trunk.clear()
	var status_of := {}
	for tech in techs:
		status_of[tech["id"]] = tech["status"]

	var columns := _layout(techs)
	var tallest := 0
	for column: Array in columns:
		tallest = maxi(tallest, column.size())
	var height := tallest * NODE_SIZE.y + (tallest - 1) * ROW_GAP
	for col in columns.size():
		var column: Array = columns[col]
		var column_height := column.size() * NODE_SIZE.y + (column.size() - 1) * ROW_GAP
		var top := (height - column_height) / 2.0
		for row in column.size():
			var tech: Dictionary = column[row]
			var pos := Vector2(col * (NODE_SIZE.x + COLUMN_GAP), top + row * (NODE_SIZE.y + ROW_GAP))
			_rects[tech["id"]] = Rect2(pos, NODE_SIZE)
			# Each source gets its own vertical trunk so lines don't merge.
			_trunk[tech["id"]] = (row + 1.0) / (column.size() + 1.0)
			_canvas.add_child(_make_node(tech, pos))
	for tech in techs:
		for prereq: String in tech["prerequisites"]:
			_links.append({ "from": prereq, "to": tech["id"], "known": status_of.get(prereq, "") == "known" })
	# Lit lines draw last so they stay on top.
	_links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return not a["known"] and b["known"])
	_canvas.custom_minimum_size = Vector2(columns.size() * NODE_SIZE.x + (columns.size() - 1) * COLUMN_GAP, height)
	_canvas.queue_redraw()

	show()
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 0.92
	modulate.a = 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)
	tween.tween_property(self, "modulate:a", 1.0, 0.1)


## Columns by tier. Tier 1 keeps data order; later tiers sort by the average
## row of their prerequisites, so lines cross as little as possible.
func _layout(techs: Array[Dictionary]) -> Array:
	var by_tier := {}
	for tech in techs:
		var tier: int = tech["tier"]
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(tech)
	var tiers := by_tier.keys()
	tiers.sort()
	var row_of := {}
	var columns: Array = []
	for tier: int in tiers:
		var column: Array = by_tier[tier]
		if not columns.is_empty():
			column.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _mean_row(a, row_of) < _mean_row(b, row_of))
		for row in column.size():
			row_of[column[row]["id"]] = row
		columns.append(column)
	return columns


func _mean_row(tech: Dictionary, row_of: Dictionary) -> float:
	var prereqs: Array = tech["prerequisites"]
	if prereqs.is_empty():
		return 0.0
	var total := 0.0
	for prereq: String in prereqs:
		total += float(row_of.get(prereq, 0))
	return total / prereqs.size()


func _make_node(tech: Dictionary, pos: Vector2) -> Button:
	var status: String = tech["status"]
	var button := Button.new()
	button.position = pos
	button.size = NODE_SIZE
	button.focus_mode = Control.FOCUS_NONE
	var detail: String = tech["detail"]
	button.text = tech["name"] if detail == "" else "%s\n%s" % [tech["name"], detail]
	button.add_theme_font_size_override("font_size", 13)
	button.clip_text = true
	var bg: Color = STATUS_BG[status]
	var normal := UiStyle.button(bg)
	normal.set_content_margin_all(4)
	normal.border_color = UiStyle.GOLD if status == "current" else bg.lightened(0.3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("disabled", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.15)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_disabled_color", Color(0.85, 0.88, 0.85) if status == "known" else MUTED)
	if status == "available" or status == "current":
		var id: String = tech["id"]
		button.pressed.connect(func() -> void: tech_chosen.emit(id))
	else:
		button.disabled = true
	return button


## Elbow lines (across, down, across) from each prerequisite to its tech.
func _draw_links() -> void:
	for link in _links:
		if not _rects.has(link["from"]) or not _rects.has(link["to"]):
			continue
		var from_rect: Rect2 = _rects[link["from"]]
		var to_rect: Rect2 = _rects[link["to"]]
		var start := Vector2(from_rect.end.x, from_rect.get_center().y)
		var end := Vector2(to_rect.position.x, to_rect.get_center().y)
		var mid_x := lerpf(start.x, end.x, float(_trunk.get(link["from"], 0.5)))
		var points := PackedVector2Array([start, Vector2(mid_x, start.y), Vector2(mid_x, end.y), end])
		_canvas.draw_polyline(points, LINE_KNOWN if link["known"] else LINE_LOCKED, LINE_WIDTH)
