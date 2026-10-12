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
	"reload": KEY_R,
}
## Second key for an action that already has one.
const ALT_KEYS := {
	"crouch": KEY_C,
}
const MOUSE := {
	"attack": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}


## Set by a scripted test, which presses keys with no window to capture a mouse in.
var scripted := false


## Is the player at the controls: mouse captured, or a script standing in for them?
func playing() -> bool:
	return scripted or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			scripted = true
		# A run that only exists to take pictures keeps out of the way of whoever is at the desk.
		if a.begins_with("--shot=") or a.begins_with("--out="):
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
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
