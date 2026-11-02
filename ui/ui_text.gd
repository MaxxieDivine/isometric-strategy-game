class_name UiText
## Wording that depends on how the player plays: "Tap" on touch screens,
## "Click" with a mouse. View state only, never game state.

## Set before the UI is built on phones, or on the first touch elsewhere.
static var touch := false


static func is_touch_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## "Tap" or "Click".
static func click() -> String:
	return "Tap" if touch else "Click"
