class_name SymbolFont
## Gives Godot's built-in UI font a bundled fallback for symbols it lacks
## (✕ ★ → ▸ ⏎ ━ ...). On desktop Godot borrows those from system fonts, but
## a web build has none to borrow and draws empty boxes instead, so the
## fallback keeps every platform looking the same.

const PATH := "res://assets/fonts/DejaVuSans.ttf"


## Adds the fallback once. Call before any UI is built (e.g. in _enter_tree).
static func install() -> void:
	var symbols: Font = load(PATH)
	var base: Font = ThemeDB.fallback_font
	if symbols == null or base == null or base.fallbacks.has(symbols):
		return
	var fallbacks: Array[Font] = base.fallbacks.duplicate()
	fallbacks.append(symbols)
	base.fallbacks = fallbacks
