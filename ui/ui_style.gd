class_name UiStyle
extends RefCounted
## Shared look for HUD panels and buttons.

const PANEL_BG := Color(0.08, 0.09, 0.13, 0.92)
const GOLD := Color(0.85, 0.75, 0.45)


static func panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	return style


static func button(bg: Color) -> StyleBoxFlat:
	var style := panel()
	style.bg_color = bg
	style.set_content_margin_all(8)
	return style
