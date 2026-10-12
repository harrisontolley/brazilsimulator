extends Node
## Registers the input map in code so project.godot stays readable.

const KEYS := {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"sprint": KEY_SHIFT,
	"jump": KEY_SPACE,
	"rob": KEY_E,
	"interact": KEY_F,
	"weapon_1": KEY_1,
	"weapon_2": KEY_2,
	"drug_1": KEY_3,
	"drug_2": KEY_4,
	"drug_3": KEY_5,
	"fake_shout": KEY_V,
	"scores": KEY_TAB,
	"crouch": KEY_CTRL,
	"dive": KEY_Q,
}
## Second key for an action that already has one.
const ALT_KEYS := {
	"crouch": KEY_C,
}
const MOUSE := {
	"attack": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}


func _ready() -> void:
	for action in KEYS:
		var e := InputEventKey.new()
		e.physical_keycode = KEYS[action]
		InputMap.add_action(action)
		InputMap.action_add_event(action, e)
	for action in ALT_KEYS:
		var e := InputEventKey.new()
		e.physical_keycode = ALT_KEYS[action]
		InputMap.action_add_event(action, e)
	for action in MOUSE:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE[action]
		InputMap.add_action(action)
		InputMap.action_add_event(action, e)
