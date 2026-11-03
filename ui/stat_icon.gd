class_name StatIcon
extends Control
## One small stat icon: food, production, trade, science or turns. Uses the
## sprite `icon_<stat>` when assets/sprites has it, else a code-drawn
## placeholder (PlaceholderArt.draw_stat_icon).

const SCIENCE_COLOR := Color("#5aa6e0")
const TURNS_COLOR := Color(0.85, 0.75, 0.45)

var stat := ""


static func make(stat_name: String, icon_size: float) -> StatIcon:
	var icon := StatIcon.new()
	icon.stat = stat_name
	icon.custom_minimum_size = Vector2.ONE * icon_size
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


## The sprite key for a stat's icon.
static func sprite_key(stat_name: String) -> String:
	return "icon_" + stat_name


static func color_of(stat_name: String) -> Color:
	match stat_name:
		"science":
			return SCIENCE_COLOR
		"turns":
			return TURNS_COLOR
		"score":
			return Color(1.0, 0.82, 0.3)
	for def in YieldArt.defs():
		if String(def["id"]) == stat_name:
			return Color.html(String(def["placeholder_color"]))
	return Color.WHITE


func set_stat(stat_name: String) -> void:
	stat = stat_name
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var texture := SpriteLibrary.get_texture(sprite_key(stat))
	if texture != null:
		draw_texture_rect(texture, rect, false)
	else:
		PlaceholderArt.draw_stat_icon(self, rect, stat, color_of(stat))
