class_name InputActions
extends RefCounted
## Default key bindings, registered at startup if the project doesn't define them.
## Physical keycodes so WASD stays in place on non-QWERTY layouts.

const DEFAULT_KEYS := {
	"pan_left": [KEY_A, KEY_LEFT],
	"pan_right": [KEY_D, KEY_RIGHT],
	"pan_up": [KEY_W, KEY_UP],
	"pan_down": [KEY_S, KEY_DOWN],
	"end_turn": [KEY_ENTER, KEY_KP_ENTER],
	"skip_unit": [KEY_SPACE],
	"found_city": [KEY_B],
	"deselect": [KEY_ESCAPE],
	"regenerate_map": [KEY_R],
	"tech_tree": [KEY_T],
	"fortify": [KEY_F],
}


static func ensure_defaults() -> void:
	for action: String in DEFAULT_KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in DEFAULT_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			InputMap.action_add_event(action, event)
