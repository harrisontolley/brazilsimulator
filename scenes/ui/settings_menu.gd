extends Control
## The settings panel, built in code like the rest of the interface. Shown from the main menu
## and, in a match, from the pause menu on Esc. Every control writes straight through to
## Settings, which applies and saves it: there is no Apply button to forget.

signal closed

## In a match there are also buttons to carry on, leave, or quit.
var in_game := false

var _list: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer


func _ready() -> void:
	# Fills the screen and dims it; the panel sits in the middle of that whatever the window
	# size, and scrolls rather than run off the edge of a small one.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_panel = PanelContainer.new()
	centre.add_child(_panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(pad)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pad.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 440
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

	_heading("PAUSED" if in_game else "SETTINGS")
	if in_game:
		_button("Resume", func(): closed.emit())

	_heading("Display")
	var modes := _options("Window", Settings.MODES, Settings.mode)
	modes.item_selected.connect(func(k: int):
		Settings.mode = k
		Settings.save())
	var sizes: Array = Settings.sizes()
	var names: Array = []
	for s in sizes:
		names.append("%d x %d" % [s.x, s.y])
	var res := _options("Resolution", names, maxi(sizes.find(Settings.size), 0))
	res.item_selected.connect(func(k: int):
		Settings.size = sizes[k]
		Settings.save())
	_check("V-Sync", Settings.vsync, func(on: bool):
		Settings.vsync = on
		Settings.save())
	var caps: Array = []
	for c in Settings.FPS_CAPS:
		caps.append("Unlimited" if c == 0 else "%d fps" % c)
	var cap := _options("Frame rate limit", caps, maxi(Settings.FPS_CAPS.find(Settings.fps_cap), 0))
	cap.item_selected.connect(func(k: int):
		Settings.fps_cap = Settings.FPS_CAPS[k]
		Settings.save())
	var aa := _options("Anti-aliasing", Settings.MSAA, Settings.msaa)
	aa.item_selected.connect(func(k: int):
		Settings.msaa = k
		Settings.save())
	_check("Shadows", Settings.shadows, func(on: bool):
		Settings.shadows = on
		Settings.save())
	_slider("Field of view", 60.0, 110.0, 1.0, Settings.fov, "%d", func(v: float):
		Settings.fov = v
		Settings.save())

	_heading("Sound")
	_slider("Volume", 0.0, 100.0, 1.0, Settings.volume * 100.0, "%d%%", func(v: float):
		Settings.volume = v / 100.0
		Settings.save())

	_heading("Mouse")
	_slider("Sensitivity", 0.5, 10.0, 0.1, Settings.sens * 1000.0, "%.1f", func(v: float):
		Settings.sens = v / 1000.0
		Settings.save())
	_check("Invert look up / down", Settings.invert_y, func(on: bool):
		Settings.invert_y = on
		Settings.save())

	var note := Label.new()
	note.text = "F11 toggles fullscreen. Changes are saved as you make them."
	note.add_theme_font_size_override("font_size", 12)
	note.modulate = Color(1, 1, 1, 0.6)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(note)

	if in_game:
		_button("Leave match", func(): Net.leave())
		_button("Quit game", func(): get_tree().quit())
	else:
		_button("Back", func(): closed.emit())


## Sizes the scrolling part to its contents, or to what the window has room for.
func _fit() -> void:
	var room: float = get_viewport_rect().size.y - 90.0
	_scroll.custom_minimum_size = Vector2(456, minf(_list.get_combined_minimum_size().y, maxf(room, 160.0)))


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.1))
	_list.add_child(l)


func _button(text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	_list.add_child(b)


## A labelled row; returns the box to put the control in.
func _row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 190
	row.add_child(l)
	_list.add_child(row)
	return row


func _options(text: String, items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	o.selected = selected
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(text).add_child(o)
	return o


func _check(text: String, on: bool, on_toggle: Callable) -> void:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(on_toggle)
	_row(text).add_child(c)


func _slider(text: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var shown := Label.new()
	shown.custom_minimum_size.x = 52
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.text = fmt % (int(value) if fmt.contains("d") else value)
	row.add_child(shown)
	s.value_changed.connect(func(v: float): shown.text = fmt % (int(v) if fmt.contains("d") else v))
	# Save once the handle is let go, not on every pixel of the drag.
	s.drag_ended.connect(func(_moved: bool): on_change.call(s.value))
