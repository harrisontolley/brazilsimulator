extends CanvasLayer
## Whole HUD built in code: what you have and what state you are in round the edges of the
## screen, the crosshair in the middle, and the panels that open over it (shop, games,
## scoreboard, controls, pause).
##
## Health sits bottom left and the weapon bottom right, where the eye drops to in a fight;
## money top left; the clock and anything the game has to tell you top centre; how wanted
## you are top right. Every line of text has a width it wraps or shrinks to, so nothing runs
## off the sides. The look comes from ui_kit.gd.

const HEAT_TEXT := ["", "WANTED  robbery", "WANTED  assault", "WANTED  armed: police will shoot"]
## By Police.VIS_*: whether they can see you right now.
const VIS_TEXT := ["", "SEARCHING: stay out of sight", "SPOTTED", "HIDDEN: cooling off faster"]
const PING_TIME := 2.5
const PING_RADIUS := 230.0
const TOAST_TIME := 3.5
const TOASTS := 3
## How much of each side of the screen the columns in the corners may take.
const SIDE_W := 330.0
const FEED_TIME := 5.0
## The widest a block of text in the middle of the screen is allowed to be.
const TEXT_W := 900.0

const SettingsMenu := preload("res://scenes/ui/settings_menu.gd")
const DrugKit := preload("res://scenes/items/drug_kit.gd")
const UI := preload("res://scenes/ui/ui_kit.gd")
const EmoteWheel := preload("res://scenes/ui/emote_wheel.gd")
const Layout := preload("res://scenes/world/layout.gd")
## What being under water does to the picture.
const UNDER_BLUR := 0.9
const UNDER_WOBBLE := 0.35

const PHASE_TEXT := {"high": "HIGH", "down": "COMEDOWN", "od": "OVERDOSE"}
const SLOT_PX := 56
const HELP := [
	["W A S D", "move"], ["Shift", "sprint"], ["Space", "jump; hold to hop, again in the air, off a wall"],
	["Ctrl / C", "slide, or crouch and creep"], ["Q", "dive"],
	["In the sea", "Ctrl or Q under, Space up, Shift faster; mind your breath"], ["Scroll", "first / third person"],
	["Left mouse", "attack; hold to draw back a throw"], ["Right mouse", "aim; look down a scope"], ["R", "reload"],
	["1  2  3  4", "fists and blades / guns / sniper and launcher / grenades"],
	["E (hold)", "rob: shout at them, or keep quiet over a sunbather"], ["V", "fake a shout"],
	["F", "use, pick up, shop, hide, take a moto or a jet ski"], ["Z  X  G", "pick a drug, take it"],
	["B (hold)", "emotes: point at one and let go; tap to join in, stop, or go again"],
	["Tab", "scores"], ["Esc", "menu and settings"], ["F11", "fullscreen"],
]

var shop_open := false
var _wheel_row: HBoxContainer
var _wheel_call: Label
var _wheel_last: Array[Label] = []
var _wheel_bets: Label
## The buttons of the roleta's betting panel while it is the one that is open.
var _wheel_buttons: Array = []
## The pause menu (Esc) is up: settings, leave, quit. The match carries on behind it.
var menu_open := false
## The emote wheel, for the player to open and steer.
var wheel: EmoteWheel
## What the emote key would do right now, shown when F has nothing to offer.
var join_hint := ""

var _root: Control
var _tint: ColorRect
var _blur: ColorRect
var _hurt: ColorRect
var _scope: ColorRect
var _reticle: UI.Reticle
var _hp: UI.Meter
var _hp_text: Label
var _air: UI.Meter
var _air_cap: Label
var _under_k := 0.0
var _money: Label
var _weapon: Label
var _mag: Label
var _spare: Label
var _reload: ProgressBar
var _slot_tabs: Array = []
var _trip: ColorRect
var _icons := {}        # item id -> the texture of its photograph
var _bar_name: Label
var _hotbar: HBoxContainer
var _slots := {}        # drug id -> {panel, count, tol}
var _slot_ids: Array = []
var _slot_styles: Array = []
var _beat_t := 0.0
var _siren_t := 0.0
var _effects: Label
var _clock: Label
var _crowd: Label
var _heat: Label
var _heat_pips: Array = []
var _speed: Label
var _target: Label
var _prompt: Label
var _result: Label
var _menu: Control
var _hold_bar: ProgressBar
var _rob_bar: ProgressBar
var _mic_bar: ProgressBar
var _toasts: VBoxContainer
var _toast_log: Array = []   # [label, seconds left]
var _feed: VBoxContainer
var _feed_log: Array = []
var _big: Label
var _scores: PanelContainer
var _scores_grid: GridContainer
var _scores_t := 0.0
var _help: PanelContainer
var _shop: PanelContainer
var _shop_scroll: ScrollContainer
var _shop_list: VBoxContainer
var _loot: Label
var _banner: Label
var _banner_t := 0.0
var _ping_nodes: Array = []
var _pings: Array = []  # {pos, t}
var _rob_meter := 0.0
var _rob_show := 0.0
var _slow_t := 0.0
var _fake_ping_t := 0.0
var _winner := ""
var _wrapped: Array = []     # [label, widest it may be]: text that wraps to the screen
var _mid: VBoxContainer
var _top: VBoxContainer
var _hp_was := 100.0
var _hurt_k := 0.0


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.theme()
	add_child(_root)

	_blur = _overlay("res://shaders/blur.gdshader")
	_trip = _overlay("res://shaders/trip.gdshader")
	# Each drug is photographed once, off to one side, and the picture kept.
	for item in DB.DRUGS:
		var studio := DrugKit.icon_viewport(item)
		add_child(studio)
		_icons[item] = studio.get_texture()
	_tint = ColorRect.new()
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0, 0, 0, 0)
	_root.add_child(_tint)
	_hurt = _overlay("res://shaders/hurt.gdshader")
	_scope = _overlay("res://shaders/scope.gdshader")
	_reticle = UI.Reticle.new()
	_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_reticle)

	# Top left: what you have made.
	var tl := _stack(Control.PRESET_TOP_LEFT)
	_money = _text(tl, 38, UI.CANARY, true)
	_loot = _text(tl, 17, Color(0.85, 0.74, 1.0), false, SIDE_W - 20.0)

	# Top centre: the clock, and whatever the game has to say.
	_top = _stack(Control.PRESET_CENTER_TOP)
	_clock = _text(_top, 36, UI.SAND, true)
	_crowd = _text(_top, 15, UI.DIM)
	# The roleta, while you are near it or have money on it: the call, and what came up lately.
	_wheel_row = HBoxContainer.new()
	_wheel_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_wheel_row.add_theme_constant_override("separation", 9)
	_wheel_row.visible = false
	_top.add_child(_wheel_row)
	_wheel_call = UI.label(22, UI.CANARY, true)
	_wheel_row.add_child(_wheel_call)
	for k in 8:
		var n := UI.label(22 if k == 0 else 18, UI.SAND, true)
		_wheel_row.add_child(n)
		_wheel_last.append(n)
	_wheel_bets = _text(_top, 17, UI.SAND, false, TEXT_W)
	_wheel_bets.visible = false
	_banner = _text(_top, 34, Color(1.0, 0.6, 0.15), true, TEXT_W)
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 0)
	_top.add_child(_toasts)

	# Top right: how wanted you are, and who has been dropping whom.
	var tr := _stack(Control.PRESET_TOP_RIGHT)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_END
	pips.add_theme_constant_override("separation", 5)
	tr.add_child(pips)
	for k in 3:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 12)
		pips.add_child(pip)
		_heat_pips.append(pip)
	_heat = _text(tr, 19, UI.GUARANA, true, SIDE_W - 20.0)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 0)
	tr.add_child(_feed)
	var hint := _text(tr, 15, UI.DIM)
	hint.text = "H  controls"

	# Bottom left: what state you are in.
	var bl := _stack(Control.PRESET_BOTTOM_LEFT)
	_effects = _text(bl, 17, Color(1.0, 0.75, 0.3), false, 360.0)
	var vida := _plate(bl)
	var row := HBoxContainer.new()
	vida.add_child(row)
	var cap := UI.label(15, UI.DIM)
	cap.text = "HEALTH"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(cap)
	_hp_text = UI.label(34, UI.SAND, true)
	row.add_child(_hp_text)
	_hp = UI.Meter.new()
	vida.add_child(_hp)
	# Only there while it matters: how much breath is left.
	_air_cap = UI.label(15, UI.DIM)
	_air_cap.text = "BREATH"
	vida.add_child(_air_cap)
	_air = UI.Meter.new()
	_air.color = UI.SEA
	_air.custom_minimum_size = Vector2(250, 12)
	vida.add_child(_air)

	# Bottom right: what is in your hand.
	var br := _stack(Control.PRESET_BOTTOM_RIGHT)
	var arma := _plate(br)
	_weapon = UI.label(18, UI.SEA, true)
	_weapon.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	arma.add_child(_weapon)
	var rounds := HBoxContainer.new()
	rounds.alignment = BoxContainer.ALIGNMENT_END
	rounds.add_theme_constant_override("separation", 6)
	arma.add_child(rounds)
	_mag = UI.label(46, UI.SAND, true)
	rounds.add_child(_mag)
	_spare = UI.label(22, UI.DIM, true)
	_spare.size_flags_vertical = Control.SIZE_SHRINK_END
	rounds.add_child(_spare)
	_reload = ProgressBar.new()
	_reload.custom_minimum_size = Vector2(250, 5)
	_reload.show_percentage = false
	_reload.max_value = 1.0
	arma.add_child(_reload)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_END
	tabs.add_theme_constant_override("separation", 10)
	arma.add_child(tabs)
	for k in 4:
		var tab := UI.label(15, UI.DIM)
		tab.text = "%d %s" % [k + 1, ["HANDS", "GUNS", "HEAVY", "THROWN"][k]]
		tabs.add_child(tab)
		_slot_tabs.append(tab)

	# Bottom centre: what you are doing, and what is in your pockets.
	_mid = _stack(Control.PRESET_CENTER_BOTTOM)
	_target = _text(_mid, 18, UI.SAND, false, 620.0)
	_prompt = _text(_mid, 22, Color(0.75, 1.0, 0.8), true, 620.0)
	_hold_bar = _bar(Color(0.5, 1.0, 0.6))
	_hold_bar.visible = false
	_rob_bar = _bar(UI.CANARY)
	_mic_bar = _bar(Color(0.3, 0.7, 1.0))
	_mic_bar.custom_minimum_size = Vector2(160, 5)
	# The drugs in your pockets: Z / X move along the row, G takes the one lit up.
	_bar_name = _text(_mid, 16, Color(1.0, 0.9, 0.5), false, 620.0)
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 6)
	_mid.add_child(_hotbar)
	_speed = _text(_mid, 20, UI.SAND, true)

	_big = _text(_stack(Control.PRESET_CENTER, Vector2(0, -70)), 44, UI.CANARY, true, TEXT_W)

	for i in 8:
		var dot := ColorRect.new()
		dot.color = Color(1.0, 0.35, 0.1)
		dot.size = Vector2(14, 14)
		dot.visible = false
		_root.add_child(dot)
		_ping_nodes.append(dot)

	_scores = _panel()
	var board := VBoxContainer.new()
	_scores.add_child(board)
	var board_title := UI.label(26, UI.CANARY, true)
	board_title.text = "SCORES"
	board_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(board_title)
	_scores_grid = GridContainer.new()
	_scores_grid.columns = 3
	_scores_grid.add_theme_constant_override("h_separation", 34)
	board.add_child(_scores_grid)

	_help = _panel()
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 22)
	keys.add_theme_constant_override("v_separation", 2)
	_help.add_child(keys)
	for pair in HELP:
		var key := UI.label(18, UI.CANARY, true)
		key.text = pair[0]
		keys.add_child(key)
		var what := UI.label(18, UI.SAND)
		what.text = pair[1]
		keys.add_child(what)

	wheel = EmoteWheel.new()
	_root.add_child(wheel)
	_ignore_mouse(_root)

	# Shop is the one interactive panel, so it is added after the mouse pass.
	_shop = _panel()
	_shop_scroll = ScrollContainer.new()
	_shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shop.add_child(_shop_scroll)
	_shop_list = VBoxContainer.new()
	_shop_list.custom_minimum_size.x = 320
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 6)
	_shop_scroll.add_child(_shop_list)

	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


## A full-screen sheet with a shader on it, hidden until it is wanted.
func _overlay(shader: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	r.material = mat
	r.visible = false
	_root.add_child(r)
	return r


## A column of things pinned to a corner or an edge of the screen, growing away from it.
func _stack(preset: Control.LayoutPreset, nudge := Vector2.ZERO) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(preset)
	var at := nudge
	match preset:
		Control.PRESET_TOP_LEFT:
			at += Vector2(UI.EDGE, UI.EDGE)
		Control.PRESET_TOP_RIGHT:
			at += Vector2(-UI.EDGE, UI.EDGE)
			v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			at += Vector2(UI.EDGE, -UI.EDGE)
			v.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			at += Vector2(-UI.EDGE, -UI.EDGE)
			v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			v.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			at += Vector2(0, UI.EDGE - 8.0)
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_BOTTOM:
			at += Vector2(0, -UI.EDGE)
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
			v.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER:
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
			v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.offset_left = at.x
	v.offset_right = at.x
	v.offset_top = at.y
	v.offset_bottom = at.y
	v.alignment = BoxContainer.ALIGNMENT_END if v.grow_vertical == Control.GROW_DIRECTION_BEGIN else BoxContainer.ALIGNMENT_BEGIN
	v.add_theme_constant_override("separation", 2)
	_root.add_child(v)
	return v


## A line of text in `parent`, aligned the way its column grows. Give it `wide` and it wraps
## at that width, or at the width of the screen if that is less.
func _text(parent: Control, size: int, color := UI.SAND, bold := false, wide := 0.0) -> Label:
	var l := UI.label(size, color, bold)
	match parent.grow_horizontal:
		Control.GROW_DIRECTION_BOTH: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Control.GROW_DIRECTION_BEGIN: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if wide > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.set_meta("size", size)
		_wrapped.append([l, wide])
	parent.add_child(l)
	return l


## One of the two plates at the foot of the screen, with the pavement running along its top.
func _plate(parent: Control) -> VBoxContainer:
	var wave := UI.Wave.new()
	parent.add_child(wave)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.plate())
	parent.add_child(plate)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 2)
	plate.add_child(inside)
	return inside


## A panel in the middle of the screen, shut until it is opened.
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	_root.add_child(p)
	return p


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(240, 10)
	b.show_percentage = false
	b.max_value = 1.0
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", UI.box(color, 2, 0.0))
	if _mid != null:
		_mid.add_child(b)
	return b


## Fits everything that wraps to the screen as it is now.
func _layout() -> void:
	var view := _root.get_viewport_rect().size
	for e in _wrapped:
		var l: Label = e[0]
		var w: float = minf(e[1], view.x - UI.EDGE * 2.0)
		# Whatever is at the foot of the screen in the middle has the two plates either side of it.
		if l.get_parent() == _mid:
			w = minf(w, maxf(view.x - 2.0 * (322.0 + UI.EDGE), 220.0))
		elif l.get_parent() == _top:
			w = _top_w()
		l.custom_minimum_size.x = w
	for e in _toast_log:
		e[0].custom_minimum_size.x = _top_w()
	_shop_scroll.custom_minimum_size = Vector2(minf(_shop_list.get_combined_minimum_size().x + 12.0, view.x - 80.0), minf(_shop_list.get_combined_minimum_size().y, view.y - 120.0))


## How wide the column at the top of the screen can be, with a column either side of it.
func _top_w() -> float:
	return minf(TEXT_W, maxf(_root.get_viewport_rect().size.x - 2.0 * (SIDE_W + UI.EDGE), 240.0))


## Sets a headline, shrunk if it has to be so that its widest line fits across the screen.
func _headline(l: Label, text: String) -> void:
	if l.text == text:
		return
	l.text = text
	l.add_theme_font_size_override("font_size", UI.fit_size(text, l.get_meta("size"), l.custom_minimum_size.x - 8.0))


func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_ignore_mouse(child)


# --- events from Game ---

## A flick across the crosshair when a blow lands: yellow for the head, red for a kill.
func hit_marker(head: bool, kill: bool) -> void:
	_reticle.hit(head, kill)
	var p = Net.game.local_player
	if p != null:
		Sfx.play("tick_kill" if kill else "tick", p.global_position + Vector3(0, 1.4, 0), -4.0 if not kill else 0.0, 1.25 if head else 1.0)


## What F would do right now, and how far through a hold it is.
func set_prompt(text: String, frac: float) -> void:
	_prompt.text = text if text != "" else join_hint
	_hold_bar.visible = frac > 0.0
	_hold_bar.value = frac


## Something the game has to tell you. They stack, newest at the bottom, and fade.
func toast(text: String) -> void:
	for e in _toast_log:
		if e[0].text == text:
			e[1] = TOAST_TIME
			return
	var l := UI.label(21, Color(1.0, 0.9, 0.45))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _top_w()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(l)
	_toast_log.append([l, TOAST_TIME])
	if _toast_log.size() > TOASTS:
		_toast_log[0][0].queue_free()
		_toast_log.pop_front()


## A line in the corner for somebody going down: who, and in what colour.
func feed(text: String, color := UI.SAND) -> void:
	var l := UI.label(16, color)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = SIDE_W - 20.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(l)
	_feed_log.append([l, FEED_TIME])
	if _feed_log.size() > 5:
		_feed_log[0][0].queue_free()
		_feed_log.pop_front()


func set_rob_meter(v: float) -> void:
	_rob_meter = v
	_rob_show = 0.5


func add_ping(pos: Vector3) -> void:
	_pings.append({"pos": pos, "t": PING_TIME})
	if _pings.size() > _ping_nodes.size():
		_pings.pop_front()


## Big announcement across the top: a world event starting.
func banner(text: String) -> void:
	_headline(_banner, text)
	_banner_t = 6.0


func show_winner() -> void:
	var rows := _ranked()
	_winner = rows[0].pname if not rows.is_empty() else ""


func open_shop(vi: int) -> void:
	var v = DB.VENDORS[vi]
	_open_panel(v.name)
	for item in v.stock:
		var def = DB.ITEMS[item]
		var b := Button.new()
		b.text = "%s   R$%d" % [def.name, Net.game.price_at(v, item)]
		if _icons.has(item):
			b.icon = _icons[item]
			b.add_theme_constant_override("icon_max_width", 32)
		if def.type == "food":
			b.text += "   (+%d hp)" % int(def.heal)
		b.pressed.connect(func(): Net.game.to_server("srv_buy", [vi, item]))
		_shop_list.add_child(b)
	if v.get("till", false):
		var b := Button.new()
		b.text = "HOLD UP THE TILL  (needs a gun)"
		b.add_theme_color_override("font_color", UI.GUARANA.lightened(0.25))
		b.pressed.connect(func():
			Net.game.to_server("srv_till", [vi])
			close_shop())
		_shop_list.add_child(b)
	_close_button()


## Jogo do bicho: pick a stake, then an animal.
func open_bicho(vi: int) -> void:
	_open_panel("JOGO DO BICHO   pays %dx   next draw in %ds" % [DB.BICHO_PAYS, int(DB.BICHO_EVERY - fmod(MatchState.time, DB.BICHO_EVERY))])
	var stake := [DB.BETS[0]]
	var stakes := HBoxContainer.new()
	stakes.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(stakes)
	var group := ButtonGroup.new()
	for amount in DB.BETS:
		var b := Button.new()
		b.text = "R$%d" % amount
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = amount == stake[0]
		b.pressed.connect(func(): stake[0] = amount)
		stakes.add_child(b)
	var grid := GridContainer.new()
	# As many across as the window has room for.
	grid.columns = clampi(int((_root.get_viewport_rect().size.x - 140.0) / 130.0), 2, 5)
	_shop_list.add_child(grid)
	for n in DB.BICHOS.size():
		var b := Button.new()
		b.text = "%02d %s" % [n + 1, DB.BICHOS[n]]
		b.custom_minimum_size.x = 120
		b.pressed.connect(func():
			Net.game.to_server("srv_bet", [vi, n, stake[0]])
			close_shop())
		grid.add_child(b)
	_close_button()


## A row of stake buttons; returns the one-element array holding the stake chosen.
func _stakes() -> Array:
	var stake := [Net.game.casino.STAKES[1]]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(row)
	var group := ButtonGroup.new()
	for amount in Net.game.casino.STAKES:
		var b := Button.new()
		b.text = "R$%d" % amount
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = amount == stake[0]
		b.pressed.connect(func(): stake[0] = amount)
		row.add_child(b)
	return stake


func _game_panel(title_text: String, hint: String) -> void:
	_open_panel(title_text)
	_result = Label.new()
	_result.text = hint
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(minf(460.0, _root.get_viewport_rect().size.x - 120.0), 62)
	_result.add_theme_font_size_override("font_size", 21)
	_result.add_theme_color_override("font_color", UI.CANARY)
	_shop_list.add_child(_result)


func open_slot() -> void:
	_game_panel("CAÇA-NÍQUEL", "three of a kind pays; cherries from the left pay a little")
	var stake := _stakes()
	var b := Button.new()
	b.text = "PULL"
	b.pressed.connect(func(): Net.game.to_server("srv_slot", [stake[0]], Net.game.casino))
	_shop_list.add_child(b)
	_close_button()


func open_roulette() -> void:
	_game_panel("ROLETA", "pick a stake, then a bet")
	var stake := _stakes()
	var casino = Net.game.casino
	var grid := GridContainer.new()
	grid.columns = 3
	_shop_list.add_child(grid)
	for kind in 6:
		var b := Button.new()
		b.text = "%s  pays %d:1" % [casino.BETS[kind][0], casino.BETS[kind][1] - 1]
		b.pressed.connect(func(): Net.game.to_server("srv_roulette", [kind, 0, stake[0]], casino))
		grid.add_child(b)
	for dozen in 3:
		var b := Button.new()
		b.text = "%d-%d  pays 2:1" % [dozen * 12 + 1, dozen * 12 + 12]
		b.pressed.connect(func(): Net.game.to_server("srv_roulette", [6, dozen, stake[0]], casino))
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(row)
	var number := SpinBox.new()
	number.min_value = 0
	number.max_value = 36
	number.value = 17
	row.add_child(number)
	var straight := Button.new()
	straight.text = "ON THE NUMBER  pays 35:1"
	straight.pressed.connect(func(): Net.game.to_server("srv_roulette", [7, int(number.value), stake[0]], casino))
	row.add_child(straight)
	_close_button()


## The wheel on the beach. Unlike the tables indoors the bets wait for the spin, so the panel
## stays up for as many as you want to put on, and says how long there is left to do it.
func open_wheel() -> void:
	_game_panel("ROLETA", "pick a stake, then your bets; they all ride on the next spin")
	var stake := _stakes()
	var roleta = Net.game.roleta
	var casino = Net.game.casino
	var bet := func(kind: int, n: int) -> void: Net.game.to_server("srv_bet", [kind, n, stake[0]], roleta)
	var buttons: Array = []
	var grid := GridContainer.new()
	grid.columns = 3
	_shop_list.add_child(grid)
	for kind in 6:
		var b := Button.new()
		b.text = "%s  pays %d:1" % [casino.BETS[kind][0], casino.BETS[kind][1] - 1]
		b.pressed.connect(bet.bind(kind, 0))
		grid.add_child(b)
		buttons.append(b)
	for dozen in 3:
		var b := Button.new()
		b.text = "%d-%d  pays 2:1" % [dozen * 12 + 1, dozen * 12 + 12]
		b.pressed.connect(bet.bind(6, dozen))
		grid.add_child(b)
		buttons.append(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(row)
	var number := SpinBox.new()
	number.min_value = 0
	number.max_value = 36
	number.value = 17
	row.add_child(number)
	var straight := Button.new()
	straight.text = "ON THE NUMBER  pays 35:1"
	straight.pressed.connect(func(): bet.call(7, int(number.value)))
	row.add_child(straight)
	buttons.append(straight)
	_close_button()
	_wheel_buttons = buttons


## How a spin came out for this player.
func wheel_result(text: String, won: bool) -> void:
	if shop_open and not _wheel_buttons.is_empty() and is_instance_valid(_result):
		_result.text = text
	elif won:
		banner(text)
	else:
		toast(text)


## The strip under the clock, and the betting panel if it is up.
func _wheel_tick(p) -> void:
	var roleta = Net.game.roleta
	var ph: Array = roleta.phase_at(MatchState.time)
	var r: int = ph[0]
	var mine: Array = roleta.my_bets if roleta.my_round == r else []
	var near: bool = p.global_position.distance_to(Layout.WHEEL_POS) < 45.0
	var line := ""
	match ph[1]:
		roleta.OPEN: line = "ROLETA   bets close in %d" % ceili(ph[2])
		roleta.SPIN: line = "ROLETA   nada mais..."
		roleta.PAID: line = "ROLETA   %d %s" % [roleta.result_of(r), Net.game.casino.colour(roleta.result_of(r)).to_upper()] if roleta.result_of(r) >= 0 else "ROLETA"
		roleta.SHUT: line = "ROLETA   fechado"
	_wheel_row.visible = near or not mine.is_empty()
	if _wheel_row.visible:
		_wheel_call.text = line
		_wheel_call.add_theme_color_override("font_color", UI.GUARANA.lightened(0.25) if ph[1] == roleta.SPIN or (ph[1] == roleta.OPEN and ph[2] < 5.0) else UI.CANARY)
		var back: int = r - (0 if ph[1] == roleta.PAID else 1)
		for l in _wheel_last:
			while back >= 0 and roleta.result_of(back) < 0:
				back -= 1
			var n: int = roleta.result_of(back)
			l.text = str(n) if n >= 0 else ""
			l.add_theme_color_override("font_color", UI.SEA if n == 0 else (UI.GUARANA.lightened(0.2) if roleta.is_red(n) else UI.SAND))
			back -= 1
	var slip: Array = []
	var staked := 0
	for b in mine:
		slip.append(roleta.bet_text(b))
		staked += b[2]
	_wheel_bets.visible = not mine.is_empty()
	if _wheel_bets.visible:
		_wheel_bets.text = "on the table R$%d:   %s" % [staked, ",   ".join(slip)]
	if shop_open and not _wheel_buttons.is_empty() and is_instance_valid(_result):
		var taking: bool = ph[1] == roleta.OPEN and ph[2] > 0.3
		for b in _wheel_buttons:
			b.disabled = not taking
		if ph[1] != roleta.PAID or mine.is_empty():
			_result.text = "%s\n%s" % [line.trim_prefix("ROLETA   "), ("R$%d on:  %s" % [staked, ",  ".join(slip)]) if not mine.is_empty() else "nothing on the table"]


func open_blackjack() -> void:
	_game_panel("VINTE-E-UM", "house stands on 17; a natural pays 3:2")
	var stake := _stakes()
	var casino = Net.game.casino
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(row)
	var acts := ["DEAL", "HIT", "STAND", "DOUBLE"]
	for k in acts.size():
		var b := Button.new()
		b.text = acts[k]
		b.pressed.connect(func(): Net.game.to_server("srv_bj", [k, stake[0]], casino))
		row.add_child(b)
	_close_button()


func open_dice() -> void:
	_game_panel("DADOS", "two dice each, high roll wins, the banker takes ties")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_list.add_child(row)
	for amount in [5, 20, 50]:
		var b := Button.new()
		b.text = "ROLL FOR R$%d" % amount
		b.pressed.connect(func(): Net.game.to_server("srv_dice", [amount], Net.game.prison))
		row.add_child(b)
	_close_button()


## The outcome of a bet, shown in whichever game panel is open.
func game_result(text: String) -> void:
	if shop_open and is_instance_valid(_result):
		_result.text = text
	else:
		toast(text)


func _open_panel(title_text: String) -> void:
	for c in _shop_list.get_children():
		c.queue_free()
	var title := UI.label(26, UI.CANARY, true)
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 300
	_shop_list.add_child(title)
	_wheel_buttons = []
	_shop.visible = true
	shop_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_button() -> void:
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_shop)
	_shop_list.add_child(close)
	_layout.call_deferred()


func close_shop() -> void:
	_shop.visible = false
	shop_open = false
	_wheel_buttons = []
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Esc: the pause menu, with the settings in it.
func open_pause() -> void:
	if menu_open:
		return
	menu_open = true
	_menu = SettingsMenu.new()
	_menu.in_game = true
	_menu.closed.connect(close_pause)
	_root.add_child(_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_pause() -> void:
	if not menu_open:
		return
	menu_open = false
	_menu.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if menu_open and e.is_action_pressed("ui_cancel"):
		close_pause()
		get_viewport().set_input_as_handled()
	elif shop_open and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact")):
		close_shop()
		get_viewport().set_input_as_handled()


# --- per-frame ---

func _process(delta: float) -> void:
	var g = Net.game
	if g == null or g.local_player == null:
		return
	var p = g.local_player
	var st: Dictionary = p.st

	# Health, and the red that closes in when some of it goes.
	_hp.value = clampf(st.hp / 100.0, 0.0, 1.0)
	_hp_text.text = "%d" % ceili(maxf(st.hp, 0.0))
	_air.value = clampf(p.air / DB.BREATH, 0.0, 1.0)
	_air.visible = p.air < DB.BREATH - 0.05 and not st.dead
	_air_cap.visible = _air.visible
	_under_k = move_toward(_under_k, 1.0 if Layout.cam_under else 0.0, delta * 6.0)
	_hp_text.add_theme_color_override("font_color", UI.GUARANA.lightened(0.2) if st.hp < 30.0 else UI.SAND)
	if st.hp < _hp_was - 0.5:
		_hurt_k = minf(1.0, _hurt_k + (_hp_was - st.hp) / 35.0 + 0.25)
	_hp_was = st.hp
	_hurt_k = move_toward(_hurt_k, 0.0, delta * 1.3)
	var low := clampf((30.0 - st.hp) / 30.0, 0.0, 1.0) * (0.45 + 0.15 * sin(Time.get_ticks_msec() * 0.006)) if not st.dead else 0.6
	_hurt.visible = _hurt_k > 0.01 or low > 0.01
	_hurt.material.set_shader_parameter("amount", maxf(_hurt_k, low))

	_money.text = "R$ %d" % st.money
	_wheel_tick(p)

	# What is in the hand, and how much of it is left.
	var w = DB.ITEMS[st.equipped]
	var kind := DB.kind_of(st.equipped)
	_weapon.text = w.name.to_upper()
	if DB.is_gun(st.equipped):
		var loaded: int = st.mag.get(st.equipped, 0)
		var spare: int = DB.spare(st, st.equipped)
		_mag.text = "%d" % loaded
		_spare.text = "/ %d" % spare
		_mag.add_theme_color_override("font_color", UI.GUARANA.lightened(0.2) if loaded == 0 else UI.SAND)
		if loaded == 0:
			_weapon.text += "   R TO RELOAD" if spare > 0 else "   EMPTY"
	elif kind == "thrown":
		_mag.text = "%d" % st.inv.get(st.equipped, 0)
		_spare.text = "left"
		_mag.add_theme_color_override("font_color", UI.SAND)
	else:
		_mag.text = ""
		_spare.text = ""
	_mag.visible = _mag.text != ""
	_spare.visible = _mag.visible
	var reloading: float = clampf((Time.get_ticks_msec() * 0.001 - p._reload_t) / maxf(p._reload_len, 0.01), 0.0, 1.0)
	_reload.value = reloading if reloading < 1.0 else p.wind_up()
	_reload.modulate.a = 1.0 if _reload.value > 0.0 and _reload.value < 1.0 or p.wind_up() > 0.0 else 0.0
	var groups := [DB.MELEE, DB.GUNS, DB.HEAVY, DB.THROWN]
	for k in 4:
		var has := false
		for item in groups[k]:
			has = has or st.inv.has(item)
		var tab: Label = _slot_tabs[k]
		tab.add_theme_color_override("font_color", UI.CANARY if groups[k].has(st.equipped) else (UI.SAND if has else Color(UI.SAND.r, UI.SAND.g, UI.SAND.b, 0.25)))

	# The crosshair opens with how unsteady the gun is, and gives way to the scope.
	var loose := 0.0
	if kind == "shot":
		loose = w.hip if w.has("scope") and not p.is_aiming() else w.spread
		loose *= 0.6 if p.is_crouched() else (1.5 if p.mv == p.MV_AIR else 1.0)
	_reticle.spread = loose / deg_to_rad(maxf(p.rig.cam.fov, 1.0))
	_reticle.show_cross = not p.scoped and not shop_open and not menu_open and not st.dead and not wheel.open and p.emote() < 0
	_scope.visible = p.scoped and p.rig.first_person()

	_update_hotbar(p)
	var fx: Array = []
	for d in st.drugs:
		var word: String = "TIPSY" if DB.DRINKS.has(d) else ("PUMPED" if d == "ferro" else PHASE_TEXT[st.drugs[d].phase])
		fx.append("%s  %s  %ds" % [DB.ITEMS[d].name, word, ceili(st.drugs[d].t)])
	_effects.text = "\n".join(fx)
	_effects.visible = not fx.is_empty()
	var loot: Array = []
	for item in DB.LOOT:
		if st.inv.get(item, 0) > 0:
			loot.append("%s x%d" % [DB.ITEMS[item].name, st.inv[item]])
	_loot.text = "" if loot.is_empty() else "Stolen: %s. Sell it to the RECEPTADOR up in the favela." % ", ".join(loot)
	if not st.get("bet", {}).is_empty():
		_loot.text += ("\n" if _loot.text != "" else "") + "Bet: R$%d on %s, draw in %ds" % [st.bet.amount, DB.BICHOS[st.bet.animal], int(DB.BICHO_EVERY - fmod(MatchState.time, DB.BICHO_EVERY))]
	_loot.visible = _loot.text != ""
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0

	var left := int(MatchState.time_left())
	_clock.text = "%d:%02d" % [left / 60, left % 60]
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 1.0
		_crowd.text = "%d people on the beach" % g.crowd.alive_count()
	for log in [_toast_log, _feed_log]:
		for k in range(log.size() - 1, -1, -1):
			log[k][1] -= delta
			log[k][0].modulate.a = clampf(log[k][1] / 0.5, 0.0, 1.0)
			if log[k][1] <= 0.0:
				log[k][0].queue_free()
				log.remove_at(k)

	# On a small screen long messages take a lot of room: the oldest gives way.
	if _toast_log.size() > 1 and _toasts.get_combined_minimum_size().y > _root.get_viewport_rect().size.y * 0.3:
		_toast_log[0][0].queue_free()
		_toasts.remove_child(_toast_log[0][0])
		_toast_log.pop_front()

	var heat: int = clampi(st.heat, 0, 3)
	for k in 3:
		_heat_pips[k].add_theme_stylebox_override("panel", UI.box(UI.GUARANA if k < heat else Color(0, 0, 0, 0.45), 2, 0.0))
	_heat.text = HEAT_TEXT[heat]
	if heat > 0 and VIS_TEXT[clampi(st.get("vis", 0), 0, 3)] != "":
		_heat.text += "\n" + VIS_TEXT[clampi(st.get("vis", 0), 0, 3)]
	_heat.visible = heat > 0

	# Speed past a flat-out sprint is momentum the player built; show it warming up.
	var spd: float = p.hspeed()
	_speed.text = "%.1f m/s" % spd
	_speed.visible = spd > p.SPRINT + 0.3
	_speed.add_theme_color_override("font_color", UI.SAND.lerp(Color(1.0, 0.55, 0.15), clampf((spd - p.SPRINT) / 8.0, 0.0, 1.0)))

	_mic_bar.value = p.mic_level()
	_mic_bar.visible = p.mic_level() > 0.02 or p.robbing or p.target_npc >= 0
	_rob_show -= delta
	_rob_bar.visible = _rob_show > 0.0
	_rob_bar.value = _rob_meter
	if p.robbing:
		_target.text = "SHOUT!"
	elif p.target_npc >= 0:
		if g.crowd.is_out(p.target_npc):
			_target.text = "Out cold: hold E to go through their pockets"
		else:
			_target.text = "Hold E and keep QUIET to go through their bag" if g.crowd.is_lying(p.target_npc) else "Hold E and shout to rob"
	elif p.snatch_npc >= 0:
		_target.text = "E: SNATCH!"
	elif p.mv == p.MV_SWIM:
		_target.text = "Ctrl dive   Space up   look where you want to go   Shift faster" if p.head_under() else "Ctrl or Q dive under   Shift crawl   Space climb out"
	elif p.mv == p.MV_RIDE and g.motos.on_ski(p.id):
		_target.text = "W / S throttle   A / D steer   Space hop   F get off"
	elif p.mv == p.MV_RIDE:
		_target.text = "W / S throttle   A / D steer   Space hop   F get off   E snatch from people sitting"
	elif p.is_crouched():
		_target.text = "Crouched: harder to spot, hardest of all keeping still"
	else:
		_target.text = ""
	_target.visible = _target.text != ""
	_prompt.visible = _prompt.text != ""

	if MatchState.ended:
		_headline(_big, "TIME!  %s wins" % _winner)
	elif st.dead:
		_headline(_big, "YOU DIED")
	elif st.jail > 0.0:
		_headline(_big, "IN PRISON  %ds" % ceili(st.jail))
		if _target.text == "":
			_target.text = "Work a shift, score in the yard, win in the ring or pay the gate guard. Or find another way out."
			_target.visible = true
	else:
		_headline(_big, "")
	# The headline sits above the middle of the screen, or under whatever the top has run to.
	var half: float = _root.get_viewport_rect().size.y * 0.5
	var need: float = maxf(-70.0, _top.get_global_rect().end.y + _big.get_combined_minimum_size().y * 0.5 + 10.0 - half)
	var stack: Control = _big.get_parent()
	stack.offset_top = need
	stack.offset_bottom = need

	_scores.visible = MatchState.ended or Input.is_action_pressed("scores")
	_scores_t -= delta
	if _scores.visible and _scores_t <= 0.0:
		_scores_t = 0.5
		for c in _scores_grid.get_children():
			c.queue_free()
		for head in ["PLAYER", "MONEY", "KILLS"]:
			var h := UI.label(16, UI.DIM)
			h.text = head
			_scores_grid.add_child(h)
		for r in _ranked():
			var who := UI.label(22, UI.CANARY if r == p else UI.SAND, true)
			who.text = r.pname
			who.clip_text = true
			who.custom_minimum_size.x = 240
			_scores_grid.add_child(who)
			var cash := UI.label(22, UI.SAND, true)
			cash.text = "R$ %d" % r.st.money
			_scores_grid.add_child(cash)
			var kills := UI.label(22, UI.SAND, true)
			kills.text = "%d" % r.st.kills
			_scores_grid.add_child(kills)
	_help.visible = Input.is_action_pressed("help") and not _scores.visible and not shop_open and not menu_open

	_drug_screen(p, delta)
	_update_pings(p, delta)


func _ranked() -> Array:
	var rows: Array = Net.game.players.values()
	rows.sort_custom(func(a, b): return a.st.money > b.st.money)
	return rows


## One slot per drug carried: its picture, how many, and how close the next one is to too many.
func _update_hotbar(p) -> void:
	var st: Dictionary = p.st
	var held: Array = p.drugs_held()
	if held != _slot_ids:
		_slot_ids = held
		for c in _hotbar.get_children():
			c.queue_free()
		_slots.clear()
		for d in held:
			var panel := PanelContainer.new()
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 1)
			panel.add_child(box)
			var pic := TextureRect.new()
			pic.texture = _icons.get(d)
			pic.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			box.add_child(pic)
			var count := UI.label(15, UI.SAND, true)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count)
			var tol := ProgressBar.new()
			tol.show_percentage = false
			tol.add_theme_stylebox_override("fill", UI.box(UI.GUARANA, 2, 0.0))
			tol.custom_minimum_size = Vector2(SLOT_PX, 4)
			tol.max_value = 1.0
			box.add_child(tol)
			_hotbar.add_child(panel)
			_ignore_mouse(panel)
			_slots[d] = {"panel": panel, "count": count, "tol": tol}
	for d in _slots:
		var e: Dictionary = _slots[d]
		var on: bool = d == p.drug_sel
		e.count.text = "x%d" % st.inv.get(d, 0)
		e.tol.value = st.tol.get(d, 0.0)
		e.panel.add_theme_stylebox_override("panel", _slot_style(on))
	if held.has(p.drug_sel):
		var tol_now: float = st.tol.get(p.drug_sel, 0.0)
		_bar_name.text = "%s   [G]%s" % [DB.ITEMS[p.drug_sel].name, "   one more is too many" if tol_now + DB.TOLERANCE_PER_DOSE > 1.0 else ""]
	else:
		_bar_name.text = ""
	_hotbar.visible = not held.is_empty()


func _slot_style(on: bool) -> StyleBoxFlat:
	if _slot_styles.is_empty():
		for lit in [false, true]:
			var frame := StyleBoxFlat.new()
			frame.bg_color = Color(UI.ASPHALT.r, UI.ASPHALT.g, UI.ASPHALT.b, 0.85 if lit else 0.6)
			frame.set_border_width_all(3 if lit else 1)
			frame.border_color = UI.CANARY if lit else Color(1, 1, 1, 0.2)
			frame.set_corner_radius_all(3)
			frame.set_content_margin_all(4)
			_slot_styles.append(frame)
	return _slot_styles[1 if on else 0]


## What is in the blood does to the picture: tints laid over each other, the worst blur, and
## for the ones that really bend it, colours that turn and a view that sways.
func _drug_screen(p, delta: float) -> void:
	var tint := Color(0, 0, 0, 0)
	var blur := 0.0
	var hue := 0.0
	var sat := 1.0
	var wobble := 0.0
	var dying := false
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	for d in p.st.drugs:
		var def: Dictionary = DB.ITEMS[d]
		var phase: String = p.st.drugs[d].phase
		var look: Array = def.get("screen", {}).get(phase, [])
		if not look.is_empty():
			var c: Color = look[0]
			if phase == "od":
				c.a *= 0.5 + 0.5 * pulse
			# One tint over another, as two sheets of coloured glass would be.
			var a := c.a + tint.a * (1.0 - c.a)
			if a > 0.0:
				tint = Color((c.r * c.a + tint.r * tint.a * (1.0 - c.a)) / a, (c.g * c.a + tint.g * tint.a * (1.0 - c.a)) / a, (c.b * c.a + tint.b * tint.a * (1.0 - c.a)) / a, a)
			blur = maxf(blur, look[1])
		var bend: Array = def.get("trip", {}).get(phase, [])
		if not bend.is_empty():
			hue += bend[0]
			sat = maxf(sat, bend[1]) if bend[1] >= 1.0 else minf(sat, bend[1])
			wobble = maxf(wobble, bend[2])
		dying = dying or (phase == "od" and def.get("od_dmg", 0.0) > 0.0)
	if p.drug_phase("meth") == "od":
		# Paranoia: noises that are not there, and police who are not coming.
		_fake_ping_t -= delta
		if _fake_ping_t <= 0.0:
			_fake_ping_t = randf_range(0.6, 2.0)
			add_ping(p.global_position + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)))
		_siren_t -= delta
		if _siren_t <= 0.0:
			_siren_t = randf_range(3.0, 6.0)
			var a := randf() * TAU
			Sfx.play("whistle", p.global_position + Vector3(cos(a) * 25.0, 1.0, sin(a) * 25.0), 2.0)
			toast(["POLÍCIA! PARADO!", "They know.", "Was that a siren?", "Behind you."][randi() % 4])
	if dying:
		# Your own heart, louder than it should be.
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = 0.55
			Sfx.play("heartbeat", p.global_position + Vector3(0, 1.2, 0), 6.0)
	if _under_k > 0.0:
		# Looking through water: everything blue-green, soft, and never quite still.
		var c := Color(0.02, 0.36, 0.48, 0.42 * _under_k)
		var a := c.a + tint.a * (1.0 - c.a)
		tint = Color((c.r * c.a + tint.r * tint.a * (1.0 - c.a)) / a, (c.g * c.a + tint.g * tint.a * (1.0 - c.a)) / a, (c.b * c.a + tint.b * tint.a * (1.0 - c.a)) / a, a)
		blur = maxf(blur, UNDER_BLUR * _under_k)
		wobble = maxf(wobble, UNDER_WOBBLE * _under_k)
	_tint.color = tint
	_blur.visible = blur > 0.0
	_blur.material.set_shader_parameter("amount", blur)
	_trip.visible = hue != 0.0 or sat != 1.0 or wobble > 0.0
	_trip.material.set_shader_parameter("hue", hue * Time.get_ticks_msec() * 0.001)
	_trip.material.set_shader_parameter("sat", sat)
	_trip.material.set_shader_parameter("wobble", wobble)


func _update_pings(p, delta: float) -> void:
	var centre := _root.size * 0.5
	var cam_xf: Transform3D = p.rig.cam.global_transform.affine_inverse()
	for i in _ping_nodes.size():
		var dot: ColorRect = _ping_nodes[i]
		if i >= _pings.size():
			dot.visible = false
			continue
		var ping = _pings[i]
		ping.t -= delta
		var rel: Vector3 = cam_xf * ping.pos
		var ang := atan2(rel.x, -rel.z)
		dot.position = centre + Vector2(sin(ang), -cos(ang)) * PING_RADIUS - dot.size * 0.5
		dot.color.a = clampf(ping.t / PING_TIME, 0.0, 1.0)
		dot.visible = true
	_pings = _pings.filter(func(e): return e.t > 0.0)
