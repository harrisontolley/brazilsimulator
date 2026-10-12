extends Control

const SettingsMenu := preload("res://scenes/ui/settings_menu.gd")
const UI := preload("res://scenes/ui/ui_kit.gd")

var _name: LineEdit
var _ip: LineEdit
var _status: Label
var _box: VBoxContainer
var _settings: Control


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var bg := ColorRect.new()
	bg.color = UI.ASPHALT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# The pavement along the foot of the screen, as it runs along the foot of the beach.
	var wave := UI.Wave.new()
	wave.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	wave.custom_minimum_size.y = 46
	wave.offset_top = -46
	add_child(wave)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	_box = box

	var title := Label.new()
	title.text = "BRAZIL SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UI.font(true))
	title.add_theme_font_size_override("font_size", 76)
	title.add_theme_color_override("font_color", UI.CANARY)
	box.add_child(title)

	_name = LineEdit.new()
	_name.placeholder_text = "Name"
	_name.max_length = 16
	_name.text = Settings.player_name if Settings.player_name != "" else Net.local_name
	box.add_child(_name)

	var host_btn := Button.new()
	host_btn.text = "Host match"
	host_btn.pressed.connect(_host)
	box.add_child(host_btn)

	_ip = LineEdit.new()
	_ip.placeholder_text = "Host IP"
	_ip.text = Settings.last_ip
	box.add_child(_ip)

	var join_btn := Button.new()
	join_btn.text = "Join match"
	join_btn.pressed.connect(_join)
	box.add_child(join_btn)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_open_settings)
	box.add_child(settings_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	Net.join_failed.connect(func(): _status.text = "Could not connect.")

	# Quick launch: godot --path . -- --host | --join=IP [--name=X]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			_name.text = a.trim_prefix("--name=")
		elif a == "--host":
			_host.call_deferred()
		elif a.begins_with("--join="):
			_ip.text = a.trim_prefix("--join=")
			_join.call_deferred()


func _open_settings() -> void:
	_box.visible = false
	_settings = SettingsMenu.new()
	_settings.closed.connect(func():
		_settings.queue_free()
		_box.visible = true)
	add_child(_settings)


func _host() -> void:
	_apply_name()
	if not Net.host():
		_status.text = "Could not host on port %d." % Net.PORT


func _join() -> void:
	_apply_name()
	_status.text = "Connecting..."
	if not Net.join(_ip.text.strip_edges()):
		_status.text = "Could not connect."


func _apply_name() -> void:
	var n := _name.text.strip_edges()
	Net.local_name = n if n != "" else "Kid"
	Settings.player_name = n
	Settings.last_ip = _ip.text.strip_edges()
	Settings.save()
