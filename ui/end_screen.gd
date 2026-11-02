class_name EndScreen
extends Control
## The end of the game: a title earned by the score, how the game ended, the
## final score and its breakdown, a score-over-time chart, wonders built, and
## the key moments. New Game starts over; Keep Playing closes it and the game
## goes on with the score frozen.

signal new_game_requested
signal keep_playing_requested

const DIM := Color(0, 0, 0, 0.6)
const BRIGHT_GOLD := Color(1.0, 0.86, 0.4)
const MUTED := Color(0.75, 0.78, 0.85)
const SECTION_COLOR := Color(0.6, 0.62, 0.68)

var _rating: Label
var _blurb: Label
var _reason: Label
var _score_label: Label
var _breakdown: GridContainer
var _wonders_box: VBoxContainer
var _chart: ScoreChart
var _legend: HBoxContainer
var _moments: VBoxContainer
var _keep_button: Button
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	var style := UiStyle.panel()
	style.border_color = BRIGHT_GOLD
	style.set_border_width_all(3)
	style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_reason = _label(box, 16, UiStyle.GOLD, true)
	_rating = _label(box, 34, BRIGHT_GOLD, true)
	_rating.add_theme_color_override("font_outline_color", Color(0.3, 0.18, 0.0))
	_rating.add_theme_constant_override("outline_size", 6)
	_blurb = _label(box, 15, MUTED, true)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(260, 0)
	columns.add_child(left)
	_score_label = _label(left, 26, Color.WHITE)
	_breakdown = GridContainer.new()
	_breakdown.columns = 3
	_breakdown.add_theme_constant_override("h_separation", 14)
	_breakdown.add_theme_constant_override("v_separation", 2)
	left.add_child(_breakdown)
	_label(left, 13, SECTION_COLOR).text = "Wonders of the World"
	_wonders_box = VBoxContainer.new()
	_wonders_box.add_theme_constant_override("separation", 2)
	left.add_child(_wonders_box)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	_label(right, 13, SECTION_COLOR).text = "Score over time"
	_chart = ScoreChart.new()
	_chart.custom_minimum_size = Vector2(420, 190)
	right.add_child(_chart)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 12)
	right.add_child(_legend)
	_label(right, 13, SECTION_COLOR).text = "Key moments"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_moments = VBoxContainer.new()
	_moments.add_theme_constant_override("separation", 1)
	_moments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_moments)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var new_game := _button("New Game", Color(0.16, 0.14, 0.1, 0.95))
	new_game.pressed.connect(func() -> void: new_game_requested.emit())
	buttons.add_child(new_game)
	_keep_button = _button("Keep Playing", Color(0.55, 0.38, 0.1, 0.98))
	_keep_button.pressed.connect(func() -> void: keep_playing_requested.emit())
	buttons.add_child(_keep_button)
	hide()


## `info` keys:
##   reason: String, rating: String, blurb: String, score: int
##   breakdown: [{ label, detail ("12 × 2"), points }]
##   wonders: [{ name, detail, mine: bool }]
##   series: [{ name, color, points }] and markers: [{ turn, series }] for the chart
##   moments: [{ turn, text, color }]
func show_result(info: Dictionary) -> void:
	_reason.text = info["reason"]
	_rating.text = info["rating"]
	_blurb.text = info["blurb"]
	_score_label.text = "Final score  %d" % info["score"]
	_clear(_breakdown)
	for row: Dictionary in info["breakdown"]:
		_label(_breakdown, 15, Color.WHITE).text = row["label"]
		_label(_breakdown, 15, MUTED).text = row["detail"]
		var points := _label(_breakdown, 15, BRIGHT_GOLD)
		points.text = str(row["points"])
		points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clear(_wonders_box)
	for wonder: Dictionary in info["wonders"]:
		var line := _label(_wonders_box, 14, BRIGHT_GOLD if bool(wonder["mine"]) else MUTED)
		line.text = "★ %s   %s" % [wonder["name"], wonder["detail"]]
	var series: Array[Dictionary] = []
	series.assign(info["series"])
	var markers: Array[Dictionary] = []
	markers.assign(info.get("markers", []))
	_chart.set_data(series, markers)
	_clear(_legend)
	for entry in series:
		var swatch := _label(_legend, 13, entry["color"])
		swatch.text = "━ %s" % entry["name"]
	_clear(_moments)
	for moment: Dictionary in info["moments"]:
		var line := _label(_moments, 13, moment.get("color", MUTED))
		line.text = "Turn %d   %s" % [moment["turn"], moment["text"]]
	show()
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position = ((get_viewport_rect().size - _panel.size) / 2.0).floor()
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2.ONE * 0.85
	modulate.a = 0.0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.35)
	tween.tween_property(self, "modulate:a", 1.0, 0.25)
	CelebrationBurst.play(self, _panel.position + Vector2(_panel.size.x / 2.0, 40.0), 200.0)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _label(parent: Control, font_size: int, color: Color, centered: bool = false) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _button(text: String, bg: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(170, 0)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_stylebox_override("normal", UiStyle.button(bg))
	button.add_theme_stylebox_override("hover", UiStyle.button(bg.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", UiStyle.button(bg.darkened(0.2)))
	return button
