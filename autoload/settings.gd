extends Node
## The player's own preferences: display, sound, controls. Kept in user://settings.cfg, read
## at launch and written whenever one changes, so the game comes back the way it was left.
##
## Anything that wants a setting reads it from here (Settings.fov, Settings.sens ...); the
## engine-side ones (window, vsync, anti-aliasing, volume) are pushed by apply().

signal changed

## Where they are kept. A test points this somewhere else.
var path := "user://settings.cfg"
enum { WINDOWED, BORDERLESS, FULLSCREEN }
const MODES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MSAA := ["Off", "2x", "4x", "8x"]
const FPS_CAPS := [0, 30, 60, 120, 144, 240]

## Window mode (WINDOWED / BORDERLESS / FULLSCREEN).
var mode := WINDOWED
## Window size when windowed. In fullscreen it sets how finely the 3D view is drawn: the
## picture is rendered at this height and scaled to the screen.
var size := Vector2i(1600, 900)
var vsync := true
## Frames per second to stop at, 0 for no limit.
var fps_cap := 0
## Index into MSAA.
var msaa := 1
var shadows := true
## 0..1.
var volume := 0.8
var fov := 75.0
## Radians of turn per pixel of mouse.
var sens := 0.0025
var invert_y := false
## Remembered from the menu.
var player_name := ""
var last_ip := "127.0.0.1"

# A run driven from the command line for testing leaves the player's window alone.
var _scripted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test=") or a.begins_with("--shot=") or a.begins_with("--out="):
			_scripted = true
	if _scripted:
		return
	_load()
	apply()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F11:
		mode = WINDOWED if mode != WINDOWED else BORDERLESS
		save()
		get_viewport().set_input_as_handled()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	mode = clampi(cfg.get_value("display", "mode", mode), WINDOWED, FULLSCREEN)
	size = cfg.get_value("display", "size", size)
	vsync = cfg.get_value("display", "vsync", vsync)
	fps_cap = cfg.get_value("display", "fps_cap", fps_cap)
	msaa = clampi(cfg.get_value("display", "msaa", msaa), 0, MSAA.size() - 1)
	shadows = cfg.get_value("display", "shadows", shadows)
	volume = clampf(cfg.get_value("audio", "volume", volume), 0.0, 1.0)
	fov = clampf(cfg.get_value("controls", "fov", fov), 60.0, 110.0)
	sens = clampf(cfg.get_value("controls", "sens", sens), 0.0005, 0.01)
	invert_y = cfg.get_value("controls", "invert_y", invert_y)
	player_name = cfg.get_value("player", "name", player_name)
	last_ip = cfg.get_value("player", "last_ip", last_ip)


## Writes everything to disk and puts it into effect.
func save() -> void:
	if _scripted:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("display", "mode", mode)
	cfg.set_value("display", "size", size)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_cap", fps_cap)
	cfg.set_value("display", "msaa", msaa)
	cfg.set_value("display", "shadows", shadows)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("controls", "sens", sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.save(path)
	apply()


## The sizes worth offering on this screen.
func sizes() -> Array:
	var screen := DisplayServer.screen_get_size()
	var out: Array = []
	for s in SIZES:
		if s.x <= screen.x and s.y <= screen.y:
			out.append(s)
	if not out.has(screen):
		out.append(screen)
	return out


func apply() -> void:
	var root := get_tree().root
	var screen := DisplayServer.screen_get_size()
	match mode:
		WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var s := Vector2i(mini(size.x, screen.x), mini(size.y, screen.y))
			if DisplayServer.window_get_size() != s:
				DisplayServer.window_set_size(s)
				DisplayServer.window_set_position(DisplayServer.screen_get_position() + (screen - s) / 2)
			root.scaling_3d_scale = 1.0
		BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			root.scaling_3d_scale = clampf(float(size.y) / screen.y, 0.3, 1.0)
		FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			root.scaling_3d_scale = clampf(float(size.y) / screen.y, 0.3, 1.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][msaa]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if Net.game != null and Net.game.world != null and Net.game.world.sun != null:
		Net.game.world.sun.shadow_enabled = shadows
	changed.emit()
