class_name Hud
extends Control
## Top bar (score, research indicator, tech tree and advisor buttons, turn/year), End Turn,
## Found City, Fortify and Skip buttons, key hints, a notification card for batched
## turn news (with highlights and warnings; clickable when it points at a
## place), the attack-odds tag, and the idle-city prompt.

signal end_turn_requested
signal found_city_requested
signal end_turn_confirmed
signal idle_city_jump_requested(city_id: int)
signal research_clicked
signal tech_tree_requested
signal fortify_requested
signal skip_requested
## The turn card was clicked while it pointed at a place on the map.
signal notice_clicked
## The advisor on/off button was pressed.
signal advisor_toggle_requested

const BUTTON_BG := Color(0.16, 0.14, 0.1, 0.95)
const BUTTON_READY_BG := Color(0.55, 0.38, 0.1, 0.98)
const NOTICE_BASE_TIME := 1.6
const NOTICE_TIME_PER_LINE := 0.8
## The turn card sits below the top bar.
const NOTICE_TOP := 96
const SCIENCE_COLOR := Color("#5aa6e0")
const WARNING_COLOR := Color("#f2b84e")
const DANGER_COLOR := Color("#ff7a5c")
const ODDS_GOOD := Color("#9be06b")
const ODDS_BAD := Color("#ff7a5c")

var _turn_label: Label
var _countdown_label: Label
var _score_panel: PanelContainer
var _score_label: Label
var _shown_score := -1
var _end_turn_button: Button
var _found_city_button: Button
var _fortify_button: Button
var _skip_button: Button
var _tree_button: Button
var _advisor_button: Button
var _touch_mode := false
var _notice_warnings: Label
var _notice_clickable := false
var _odds_tag: PanelContainer
var _odds_label: Label
var _hint_label: Label
var _notice: PanelContainer
var _notice_title: Label
var _notice_lines: Label
var _notice_highlights: Label
var _research_panel: PanelContainer
var _research_label: Label
var _research_bar: ProgressBar
var _research_pulse: Tween
var _notice_tween: Tween
var _pulse_tween: Tween
var _turn_done := false
var _idle_prompt: PanelContainer
var _idle_label: Label
var _idle_jump_button: Button
var _idle_city_id := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 6)
	add_child(top_bar)
	_build_score_indicator(top_bar)
	_build_research_indicator(top_bar)
	_tree_button = Button.new()
	_tree_button.text = "Techs (T)"
	_tree_button.focus_mode = Control.FOCUS_NONE
	_tree_button.add_theme_font_size_override("font_size", 15)
	_set_button_bg(_tree_button, BUTTON_BG)
	_tree_button.pressed.connect(func() -> void: tech_tree_requested.emit())
	top_bar.add_child(_tree_button)
	_advisor_button = Button.new()
	_advisor_button.focus_mode = Control.FOCUS_NONE
	_advisor_button.add_theme_font_size_override("font_size", 15)
	_set_button_bg(_advisor_button, BUTTON_BG)
	_advisor_button.pressed.connect(func() -> void: advisor_toggle_requested.emit())
	top_bar.add_child(_advisor_button)
	set_advisor_enabled(true, "")
	var turn_panel := PanelContainer.new()
	turn_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	top_bar.add_child(turn_panel)
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var turn_box := VBoxContainer.new()
	turn_box.add_theme_constant_override("separation", 0)
	turn_panel.add_child(turn_box)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	turn_box.add_child(_turn_label)
	_countdown_label = Label.new()
	_countdown_label.add_theme_font_size_override("font_size", 14)
	_countdown_label.add_theme_color_override("font_color", WARNING_COLOR)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown_label.hide()
	turn_box.add_child(_countdown_label)

	_end_turn_button = _make_button("End Turn", 0)
	_end_turn_button.pressed.connect(func() -> void: end_turn_requested.emit())
	_found_city_button = _make_button("Found City  (B)", 1)
	_found_city_button.pressed.connect(func() -> void: found_city_requested.emit())
	_found_city_button.hide()
	_fortify_button = _make_button("Fortify  (F)", 1)
	_fortify_button.pressed.connect(func() -> void: fortify_requested.emit())
	_fortify_button.hide()
	_skip_button = _make_button("Skip  (Space)", 2)
	_skip_button.pressed.connect(func() -> void: skip_requested.emit())
	_skip_button.hide()
	_build_odds_tag()

	_hint_label = Label.new()
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.add_theme_constant_override("outline_size", 4)
	add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_build_notice()
	_build_idle_prompt()


## "Score 42"; the tooltip has the breakdown. A "+3" floats up when it rises.
func _build_score_indicator(parent: Control) -> void:
	_score_panel = PanelContainer.new()
	_score_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_score_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(_score_panel)
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 18)
	_score_label.add_theme_color_override("font_color", UiStyle.GOLD)
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_child(_score_label)


## `score`: the score to show; `tooltip`: its breakdown; `frozen`: the game is
## over and the player kept playing (the score no longer changes).
func set_score(score: int, tooltip: String, frozen: bool) -> void:
	_score_label.text = ("Final score %d" if frozen else "Score %d") % score
	_score_panel.tooltip_text = tooltip
	if _shown_score >= 0 and score > _shown_score and not frozen:
		_float_text("+%d" % (score - _shown_score), _score_panel)
	_shown_score = score


## Forget the shown score (new game), so the next one doesn't float a "+N".
func reset_score() -> void:
	_shown_score = -1


## "12 turns remaining" under the turn label ("" hides it).
func set_countdown(text: String, urgent: bool) -> void:
	_countdown_label.text = text
	_countdown_label.visible = text != ""
	_countdown_label.add_theme_color_override("font_color", DANGER_COLOR if urgent else WARNING_COLOR)


## A small gold label that rises out of `anchor` and fades.
func _float_text(text: String, anchor: Control) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	label.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	var rect := anchor.get_global_rect()
	label.position = Vector2(rect.get_center().x - 10.0, rect.end.y) - get_global_position()
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y + 26.0, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## "Writing in 4 turns" over a progress bar; clicking opens the research picker.
func _build_research_indicator(parent: Control) -> void:
	_research_panel = PanelContainer.new()
	_research_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_research_panel.custom_minimum_size = Vector2(230, 0)
	_research_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_research_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_research_panel.tooltip_text = "Choose research"
	_research_panel.gui_input.connect(_on_research_input)
	parent.add_child(_research_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_panel.add_child(box)
	_research_label = Label.new()
	_research_label.add_theme_font_size_override("font_size", 15)
	_research_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_research_label)
	_research_bar = ProgressBar.new()
	_research_bar.show_percentage = false
	_research_bar.custom_minimum_size = Vector2(0, 8)
	_research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.04, 0.06)
	bar_bg.border_color = Color(0.3, 0.3, 0.3)
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = SCIENCE_COLOR
	_research_bar.add_theme_stylebox_override("background", bar_bg)
	_research_bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(_research_bar)


func _on_research_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		research_clicked.emit()


## `info` keys: tech_name ("" if nothing is being researched), stored, cost,
## turns (-1 for no science), per_turn, done (true if every tech is known).
func set_research(info: Dictionary) -> void:
	if _research_pulse != null:
		_research_pulse.kill()
		_research_pulse = null
	_research_panel.modulate = Color.WHITE
	var per_turn: int = info["per_turn"]
	_research_label.add_theme_color_override("font_color", Color.WHITE)
	if bool(info["done"]):
		_research_label.text = "All techs known   ·   +%d science" % per_turn
		_research_bar.max_value = 1
		_research_bar.value = 1
		_research_panel.tooltip_text = ""
		return
	var tech_name: String = info["tech_name"]
	if tech_name == "":
		_research_label.text = "Choose research ▸"
		_research_label.add_theme_color_override("font_color", WARNING_COLOR)
		_research_bar.max_value = 1
		_research_bar.value = 0
		_research_panel.tooltip_text = "%d science stored   ·   +%d per turn" % [info["stored"], per_turn]
		_research_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_research_pulse.tween_property(_research_panel, "modulate", Color(1.3, 1.2, 0.9), 0.5)
		_research_pulse.tween_property(_research_panel, "modulate", Color.WHITE, 0.5)
		return
	var turns: int = info["turns"]
	var eta := ("in %d turn%s" % [turns, "" if turns == 1 else "s"]) if turns > 0 else "(no science)"
	_research_label.text = "%s %s" % [tech_name, eta]
	_research_bar.max_value = maxi(1, int(info["cost"]))
	_research_bar.value = mini(int(info["stored"]), int(info["cost"]))
	_research_panel.tooltip_text = "%d / %d science   ·   +%d per turn\nClick to change research" % [
		info["stored"], info["cost"], per_turn]


## A bottom-right button; `slot` 0 is the bottom one, higher slots stack upward.
func _make_button(text: String, slot: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(170, 46)
	button.add_theme_font_size_override("font_size", 18)
	_set_button_bg(button, BUTTON_BG)
	add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_top -= slot * 56
	button.offset_bottom -= slot * 56
	button.pivot_offset = button.custom_minimum_size / 2.0
	return button


func _build_notice() -> void:
	_notice = PanelContainer.new()
	_notice.add_theme_stylebox_override("panel", UiStyle.panel())
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_notice.gui_input.connect(_on_notice_input)
	_notice.modulate.a = 0.0
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, NOTICE_TOP)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_notice.add_child(box)
	_notice_title = Label.new()
	_notice_title.add_theme_font_size_override("font_size", 18)
	_notice_title.add_theme_color_override("font_color", UiStyle.GOLD)
	_notice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_title)
	_notice_highlights = Label.new()
	_notice_highlights.add_theme_font_size_override("font_size", 18)
	_notice_highlights.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_notice_highlights.add_theme_color_override("font_outline_color", Color(0.35, 0.22, 0.0))
	_notice_highlights.add_theme_constant_override("outline_size", 4)
	_notice_highlights.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_highlights)
	_notice_warnings = Label.new()
	_notice_warnings.add_theme_font_size_override("font_size", 17)
	_notice_warnings.add_theme_color_override("font_color", DANGER_COLOR)
	_notice_warnings.add_theme_color_override("font_outline_color", Color(0.25, 0.04, 0.0))
	_notice_warnings.add_theme_constant_override("outline_size", 4)
	_notice_warnings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_warnings)
	_notice_lines = Label.new()
	_notice_lines.add_theme_font_size_override("font_size", 15)
	_notice_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_notice_lines)


## A small card above the buttons: "Rome has nothing to build" with
## [Go to Rome] and [End Turn anyway]. Not modal; the map stays usable.
func _build_idle_prompt() -> void:
	_idle_prompt = PanelContainer.new()
	_idle_prompt.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(_idle_prompt)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_idle_prompt.add_child(box)
	_idle_label = Label.new()
	_idle_label.add_theme_font_size_override("font_size", 16)
	_idle_label.add_theme_color_override("font_color", UiStyle.GOLD)
	box.add_child(_idle_label)
	var hint := Label.new()
	hint.text = "End Turn again to skip"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_idle_jump_button = Button.new()
	_idle_jump_button.focus_mode = Control.FOCUS_NONE
	_idle_jump_button.pressed.connect(func() -> void: idle_city_jump_requested.emit(_idle_city_id))
	row.add_child(_idle_jump_button)
	var anyway := Button.new()
	anyway.text = "End Turn anyway"
	anyway.focus_mode = Control.FOCUS_NONE
	anyway.pressed.connect(func() -> void: end_turn_confirmed.emit())
	row.add_child(anyway)
	for button: Button in [_idle_jump_button, anyway]:
		_set_button_bg(button, BUTTON_BG)
	_idle_prompt.hide()


func show_idle_prompt(city_id: int, city_name: String, other_idle: int) -> void:
	_idle_city_id = city_id
	_idle_label.text = "%s has nothing to build" % city_name
	if other_idle > 0:
		_idle_label.text += "  (+%d more)" % other_idle
	_idle_jump_button.text = "Go to %s" % city_name
	_idle_prompt.show()
	_idle_prompt.reset_size()
	_idle_prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_idle_prompt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_idle_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Sit above the two button slots.
	_idle_prompt.offset_top -= 2 * 56
	_idle_prompt.offset_bottom -= 2 * 56
	_idle_prompt.pivot_offset = _idle_prompt.size / 2.0
	_idle_prompt.scale = Vector2.ONE * 0.85
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) 		.tween_property(_idle_prompt, "scale", Vector2.ONE, 0.15)


func hide_idle_prompt() -> void:
	_idle_prompt.hide()
	_idle_city_id = -1


func is_idle_prompt_visible() -> bool:
	return _idle_prompt.visible


func set_turn(turn: int, year_text: String) -> void:
	_turn_label.text = "Turn %d   ·   %s" % [turn, year_text]


func set_hint(text: String) -> void:
	_hint_label.text = text


func set_found_city_visible(shown: bool) -> void:
	_found_city_button.visible = shown


## Highlights the End Turn button when every unit and city has orders.
func set_turn_done(done: bool) -> void:
	if done == _turn_done:
		return
	_turn_done = done
	if _pulse_tween != null:
		_pulse_tween.kill()
	_end_turn_button.modulate = Color.WHITE
	if done:
		_end_turn_button.text = "End Turn" if _touch_mode else "End Turn  ⏎"
		_set_button_bg(_end_turn_button, BUTTON_READY_BG)
		_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color(1.35, 1.25, 1.0), 0.6)
		_pulse_tween.tween_property(_end_turn_button, "modulate", Color.WHITE, 0.6)
	else:
		_end_turn_button.text = "End Turn"
		_set_button_bg(_end_turn_button, BUTTON_BG)


## Shows one notification card (replacing any current one): a title, then
## highlighted lines (good news, with a celebratory burst), warnings (threats),
## then ordinary lines. Stays up a little longer the more it says.
## `extras` keys (all optional): highlights, warnings (PackedStringArray),
## celebrate (bool, default true), clickable (bool: emits notice_clicked).
func notify(title: String, lines: PackedStringArray = PackedStringArray(), extras: Dictionary = {}) -> void:
	var highlights: PackedStringArray = extras.get("highlights", PackedStringArray())
	var warnings: PackedStringArray = extras.get("warnings", PackedStringArray())
	_notice_clickable = bool(extras.get("clickable", false))
	_notice.mouse_filter = Control.MOUSE_FILTER_STOP if _notice_clickable else Control.MOUSE_FILTER_IGNORE
	_notice_title.text = title
	_notice_highlights.text = "\n".join(highlights)
	_notice_highlights.visible = not highlights.is_empty()
	_notice_warnings.text = "\n".join(warnings) + ("\n(%s to look)" % UiText.click().to_lower() if _notice_clickable else "")
	_notice_warnings.visible = not warnings.is_empty()
	_notice_lines.text = "\n".join(lines)
	_notice_lines.visible = not lines.is_empty()
	_notice.reset_size()
	# Re-center after resizing.
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, NOTICE_TOP)
	if _notice_tween != null:
		_notice_tween.kill()
	_notice.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(NOTICE_BASE_TIME
		+ NOTICE_TIME_PER_LINE * (lines.size() + 2 * highlights.size() + 3 * warnings.size()))
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.4)
	_notice_tween.tween_callback(func() -> void: _notice.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	if bool(extras.get("celebrate", true)) and not highlights.is_empty():
		_celebrate()
	elif not warnings.is_empty():
		_shake_notice()


func _on_notice_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if _notice_clickable and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		notice_clicked.emit()


## A short jolt so a warning card catches the eye.
func _shake_notice() -> void:
	var rest := _notice.position.x
	var tween := create_tween()
	for x: float in [8.0, -7.0, 5.0, -3.0, 0.0]:
		tween.tween_property(_notice, "position:x", rest + x, 0.05)


## The advisor button: "Advisor: on" or "Advisor: off" (`advisor_name` for the tooltip).
func set_advisor_enabled(enabled: bool, advisor_name: String) -> void:
	_advisor_button.text = "Advisor: on" if enabled else "Advisor: off"
	var who := advisor_name if advisor_name != "" else "your advisor"
	_advisor_button.tooltip_text = ("%s offers counsel now and then. Press to turn it off." if enabled
		else "%s keeps quiet. Press to hear their counsel again.") % who
	_advisor_button.modulate = Color.WHITE if enabled else Color(0.7, 0.7, 0.7)


func set_fortify_visible(shown: bool) -> void:
	_fortify_button.visible = shown


func set_skip_visible(shown: bool) -> void:
	_skip_button.visible = shown


## On a touch screen the buttons drop their keyboard shortcuts.
func set_touch_mode(enabled: bool) -> void:
	if enabled == _touch_mode:
		return
	_touch_mode = enabled
	_found_city_button.text = "Found City" if enabled else "Found City  (B)"
	_fortify_button.text = "Fortify" if enabled else "Fortify  (F)"
	_skip_button.text = "Skip" if enabled else "Skip  (Space)"
	_tree_button.text = "Techs" if enabled else "Techs (T)"
	if not _turn_done:
		_end_turn_button.text = "End Turn"


# --- Attack odds ----------------------------------------------------------------

func _build_odds_tag() -> void:
	_odds_tag = PanelContainer.new()
	var style := UiStyle.panel()
	style.set_content_margin_all(5)
	_odds_tag.add_theme_stylebox_override("panel", style)
	_odds_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_odds_tag)
	_odds_label = Label.new()
	_odds_label.add_theme_font_size_override("font_size", 16)
	_odds_tag.add_child(_odds_label)
	_odds_tag.hide()


## A small tag beside the mouse: "72% to win".
func show_odds(text: String, favorable: bool, screen_pos: Vector2) -> void:
	_odds_label.text = text
	_odds_label.add_theme_color_override("font_color", ODDS_GOOD if favorable else ODDS_BAD)
	_odds_tag.show()
	_odds_tag.reset_size()
	_odds_tag.position = _clamped_tag_position(screen_pos + Vector2(18, 10))


## The touch move preview's tag: "Tap again to move · 2 turns".
func show_move_tag(text: String, screen_pos: Vector2) -> void:
	_odds_label.text = text
	_odds_label.add_theme_color_override("font_color", UiStyle.GOLD)
	_odds_tag.show()
	_odds_tag.reset_size()
	_odds_tag.position = _clamped_tag_position(screen_pos + Vector2(18, 10))


func _clamped_tag_position(pos: Vector2) -> Vector2:
	var limit := size - _odds_tag.size - Vector2(4, 4)
	return Vector2(clampf(pos.x, 4.0, maxf(4.0, limit.x)), clampf(pos.y, 4.0, maxf(4.0, limit.y)))


func hide_odds() -> void:
	_odds_tag.hide()


## Pops the card, bursts gold from it, and flashes the research indicator.
func _celebrate() -> void:
	_notice.pivot_offset = _notice.size / 2.0
	_notice.scale = Vector2.ONE * 0.8
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_notice, "scale", Vector2.ONE, 0.25)
	CelebrationBurst.play(self, _notice.position + _notice.size / 2.0, maxf(120.0, _notice.size.x * 0.6))
	var indicator := _research_panel.get_global_rect().get_center() - get_global_position()
	CelebrationBurst.play(self, indicator, 70.0)


func _set_button_bg(button: Button, bg: Color) -> void:
	button.add_theme_stylebox_override("normal", UiStyle.button(bg))
	button.add_theme_stylebox_override("hover", UiStyle.button(bg.lightened(0.15)))
	button.add_theme_stylebox_override("pressed", UiStyle.button(bg.darkened(0.2)))
