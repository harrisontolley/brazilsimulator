extends Control

var _name: LineEdit
var _ip: LineEdit
var _status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.42, 0.33)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size.x = 360
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "BRAZIL SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.1))
	box.add_child(title)

	_name = LineEdit.new()
	_name.placeholder_text = "Name"
	_name.text = Net.local_name
	box.add_child(_name)

	var host_btn := Button.new()
	host_btn.text = "Host match"
	host_btn.pressed.connect(_host)
	box.add_child(host_btn)

	_ip = LineEdit.new()
	_ip.placeholder_text = "Host IP"
	_ip.text = "127.0.0.1"
	box.add_child(_ip)

	var join_btn := Button.new()
	join_btn.text = "Join match"
	join_btn.pressed.connect(_join)
	box.add_child(join_btn)

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
