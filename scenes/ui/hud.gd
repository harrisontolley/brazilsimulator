extends CanvasLayer
## Whole HUD built in code: status, mic + intimidation meters, noise pings,
## scoreboard, vendor shop and drug screen effects.

const HEAT_TEXT := ["", "WANTED: robbery", "WANTED: assault", "WANTED: armed - police will shoot"]
## By Police.VIS_*: whether they can see you right now.
const VIS_TEXT := ["", "\nSEARCHING - stay out of sight", "\nSPOTTED", "\nHIDDEN - cooling off faster"]
const PING_TIME := 2.5
const PING_RADIUS := 230.0

const SettingsMenu := preload("res://scenes/ui/settings_menu.gd")
const DrugKit := preload("res://scenes/items/drug_kit.gd")

const PHASE_TEXT := {"high": "HIGH", "down": "COMEDOWN", "od": "OVERDOSE"}
const SLOT_PX := 56

var shop_open := false
## The pause menu (Esc) is up: settings, leave, quit. The match carries on behind it.
var menu_open := false

var _root: Control
var _tint: ColorRect
var _blur: ColorRect
var _hp: ProgressBar
var _money: Label
var _weapon: Label
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
var _speed: Label
var _target: Label
var _prompt: Label
var _mark: Label
var _result: Label
var _menu: Control
var _mark_t := 0.0
var _hold_bar: ProgressBar
var _rob_bar: ProgressBar
var _mic_bar: ProgressBar
var _toast: Label
var _big: Label
var _scores: PanelContainer
var _scores_text: Label
var _shop: PanelContainer
var _shop_list: VBoxContainer
var _loot: Label
var _banner: Label
var _banner_t := 0.0
var _ping_nodes: Array = []
var _pings: Array = []  # {pos, t}
var _rob_meter := 0.0
var _rob_show := 0.0
var _toast_t := 0.0
var _slow_t := 0.0
var _fake_ping_t := 0.0
var _winner := ""


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_blur = ColorRect.new()
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var blur_mat := ShaderMaterial.new()
	blur_mat.shader = load("res://shaders/blur.gdshader")
	_blur.material = blur_mat
	_blur.visible = false
	_root.add_child(_blur)
	_trip = ColorRect.new()
	_trip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var trip_mat := ShaderMaterial.new()
	trip_mat.shader = load("res://shaders/trip.gdshader")
	_trip.material = trip_mat
	_trip.visible = false
	_root.add_child(_trip)
	# Each drug is photographed once, off to one side, and the picture kept.
	for item in DB.DRUGS:
		var studio := DrugKit.icon_viewport(item)
		add_child(studio)
		_icons[item] = studio.get_texture()
	_tint = ColorRect.new()
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(0, 0, 0, 0)
	_root.add_child(_tint)

	# Top left: status.
	var tl := _vbox(Control.PRESET_TOP_LEFT, Vector2(16, 16))
	_hp = _bar(Color(0.85, 0.15, 0.15))
	_hp.max_value = 100.0
	tl.add_child(_hp)
	_money = _label(tl, 26, Color(0.4, 1.0, 0.45))
	_weapon = _label(tl, 18)
	_effects = _label(tl, 16, Color(1.0, 0.75, 0.3))
	_loot = _label(tl, 16, Color(0.85, 0.7, 1.0))

	# Top centre: clock and how full the beach still is.
	var tc := _vbox(Control.PRESET_CENTER_TOP, Vector2(0, 12))
	_clock = _label(tc, 30)
	_crowd = _label(tc, 14, Color(1, 1, 1, 0.7))
	_toast = _label(tc, 20, Color(1.0, 0.9, 0.4))

	# Top right: heat and controls.
	var tr := _vbox(Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	_heat = _label(tr, 20, Color(1.0, 0.25, 0.25))
	_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var help := _label(tr, 13, Color(1, 1, 1, 0.65))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.text = "WASD move  Shift sprint\nHold Space to hop: strafe + turn in the air for speed\nSpace in the air: double jump   at a wall: wall jump\nCtrl / C slide (jump out of it for a boost), or crouch and creep   Q dive\nScroll: first / third person\nLMB attack  RMB aim  R reload   the head is a one-tap; a fist there knocks them out\nHold E + SHOUT to rob (V = fake shout)\nHold E silently on a sunbather to pickpocket\nF use / pick up / shop / hide / take a moto   1 fists / knife   2 guns\nZ / X pick a drug   G take it\nRun into a football to dribble, hit it to shoot\nTab scores   Esc menu / settings   F11 fullscreen"

	# Bottom centre: robbery.
	var bc := _vbox(Control.PRESET_CENTER_BOTTOM, Vector2(0, -24))
	# The drugs in your pockets: Z / X move along the row, G takes the one lit up.
	_bar_name = _label(bc, 16, Color(1.0, 0.9, 0.5))
	_hotbar = HBoxContainer.new()
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.add_theme_constant_override("separation", 6)
	bc.add_child(_hotbar)
	_speed = _label(bc, 22)
	_target = _label(bc, 18)
	_prompt = _label(bc, 20, Color(0.75, 1.0, 0.8))
	_hold_bar = _bar(Color(0.5, 1.0, 0.6))
	_hold_bar.max_value = 1.0
	_hold_bar.visible = false
	bc.add_child(_hold_bar)
	_rob_bar = _bar(Color(1.0, 0.8, 0.1))
	_rob_bar.max_value = 1.0
	bc.add_child(_rob_bar)
	_mic_bar = _bar(Color(0.3, 0.7, 1.0))
	_mic_bar.max_value = 1.0
	bc.add_child(_mic_bar)
	_label(bc, 12, Color(1, 1, 1, 0.6)).text = "MIC"
	# The hotbar can be wider than the meters; they keep their own width under it.
	for b in [_hold_bar, _rob_bar, _mic_bar]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var cross := _label(_vbox(Control.PRESET_CENTER, Vector2.ZERO), 22)
	cross.text = "+"
	_mark = _label(_vbox(Control.PRESET_CENTER, Vector2(0, -2)), 34)
	_mark.visible = false
	_big = _label(_vbox(Control.PRESET_CENTER, Vector2(0, -140)), 40, Color(1.0, 0.9, 0.3))
	_banner = _label(_vbox(Control.PRESET_CENTER_TOP, Vector2(0, 120)), 34, Color(1.0, 0.55, 0.15))

	for i in 8:
		var dot := ColorRect.new()
		dot.color = Color(1.0, 0.35, 0.1)
		dot.size = Vector2(14, 14)
		dot.visible = false
		_root.add_child(dot)
		_ping_nodes.append(dot)

	_scores = PanelContainer.new()
	_scores.set_anchors_preset(Control.PRESET_CENTER)
	_scores.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scores.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scores.visible = false
	_root.add_child(_scores)
	_scores_text = Label.new()
	_scores_text.add_theme_font_size_override("font_size", 20)
	_scores.add_child(_scores_text)

	_ignore_mouse(_root)

	# Shop is the one interactive panel, so it is added after the mouse pass.
	_shop = PanelContainer.new()
	_shop.set_anchors_preset(Control.PRESET_CENTER)
	_shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shop.grow_vertical = Control.GROW_DIRECTION_BOTH
	_shop.visible = false
	_root.add_child(_shop)
	_shop_list = VBoxContainer.new()
	_shop_list.custom_minimum_size.x = 280
	_shop.add_child(_shop_list)


func _vbox(preset: Control.LayoutPreset, offset: Vector2) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(preset)
	match preset:
		Control.PRESET_TOP_RIGHT:
			v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_BOTTOM:
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
			v.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER:
			v.grow_horizontal = Control.GROW_DIRECTION_BOTH
			v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.offset_left = offset.x
	v.offset_right = offset.x
	v.offset_top = offset.y
	v.offset_bottom = offset.y
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(v)
	return v


func _label(parent: Control, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if parent.grow_horizontal == Control.GROW_DIRECTION_BOTH else HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(l)
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(240, 16)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	return b


func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in c.get_children():
		if child is Control:
			_ignore_mouse(child)


# --- events from Game ---

## A flick on the crosshair when a blow lands: bigger and red for the head, a cross for a kill.
func hit_marker(head: bool, kill: bool) -> void:
	_mark.text = "✕" if kill else "×"
	_mark.add_theme_color_override("font_color", Color(1.0, 0.2, 0.15) if head else Color.WHITE)
	_mark.add_theme_font_size_override("font_size", 46 if head else 30)
	_mark_t = 0.3 if head else 0.15


## What F would do right now, and how far through a hold it is.
func set_prompt(text: String, frac: float) -> void:
	_prompt.text = text
	_hold_bar.visible = frac > 0.0
	_hold_bar.value = frac


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 3.5


func set_rob_meter(v: float) -> void:
	_rob_meter = v
	_rob_show = 0.5


func add_ping(pos: Vector3) -> void:
	_pings.append({"pos": pos, "t": PING_TIME})
	if _pings.size() > _ping_nodes.size():
		_pings.pop_front()


## Big announcement across the top: a world event starting.
func banner(text: String) -> void:
	_banner.text = text
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
		b.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
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
	grid.columns = 5
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
	_result.custom_minimum_size = Vector2(460, 56)
	_result.add_theme_font_size_override("font_size", 20)
	_result.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
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
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_list.add_child(title)
	_shop.visible = true
	shop_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_button() -> void:
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_shop)
	_shop_list.add_child(close)


func close_shop() -> void:
	_shop.visible = false
	shop_open = false
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

	_hp.value = st.hp
	_money.text = "R$ %d" % st.money
	var w = DB.ITEMS[st.equipped]
	if DB.is_gun(st.equipped):
		_weapon.text = "%s  [%d / %d]" % [w.name, st.mag.get(st.equipped, 0), DB.spare(st, st.equipped)]
	elif DB.kind_of(st.equipped) == "thrown":
		_weapon.text = "%s  x%d" % [w.name, st.inv.get(st.equipped, 0)]
	else:
		_weapon.text = w.name
	if DB.is_gun(st.equipped) and st.mag.get(st.equipped, 0) == 0:
		_weapon.text += "   R: reload" if DB.spare(st, st.equipped) > 0 else "   EMPTY"
	_mark_t -= delta
	_mark.visible = _mark_t > 0.0

	_update_hotbar(p)
	var fx: Array = []
	for d in st.drugs:
		var word: String = "TIPSY" if DB.DRINKS.has(d) else ("PUMPED" if d == "ferro" else PHASE_TEXT[st.drugs[d].phase])
		fx.append("%s: %s %ds" % [DB.ITEMS[d].name, word, ceili(st.drugs[d].t)])
	_effects.text = "\n".join(fx)
	var loot: Array = []
	for item in DB.LOOT:
		if st.inv.get(item, 0) > 0:
			loot.append("%s x%d" % [DB.ITEMS[item].name, st.inv[item]])
	_loot.text = "" if loot.is_empty() else "Stolen: %s\n(sell to the RECEPTADOR up in the favela)" % ", ".join(loot)
	if not st.get("bet", {}).is_empty():
		_loot.text += "\nBet: R$%d on %s  (draw in %ds)" % [st.bet.amount, DB.BICHOS[st.bet.animal], int(DB.BICHO_EVERY - fmod(MatchState.time, DB.BICHO_EVERY))]
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0

	var left := int(MatchState.time_left())
	_clock.text = "%d:%02d" % [left / 60, left % 60]
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 1.0
		_crowd.text = "%d people on the beach" % g.crowd.alive_count()
	_toast_t -= delta
	_toast.visible = _toast_t > 0.0
	_heat.text = HEAT_TEXT[clampi(st.heat, 0, 3)]
	if st.heat > 0:
		_heat.text += VIS_TEXT[clampi(st.get("vis", 0), 0, 3)]

	# Speed past a flat-out sprint is momentum the player built; show it warming up.
	var spd: float = p.hspeed()
	_speed.text = "%.1f m/s" % spd
	_speed.add_theme_color_override("font_color", Color.WHITE.lerp(Color(1.0, 0.55, 0.15), clampf((spd - p.SPRINT) / 8.0, 0.0, 1.0)))

	_mic_bar.value = p.mic_level()
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
	elif p.mv == p.MV_RIDE:
		_target.text = "W / S throttle   A / D steer   Space hop   F get off   E snatch from people sitting"
	elif p.is_crouched():
		_target.text = "Crouched: harder to spot, hardest of all keeping still"
	else:
		_target.text = ""

	if MatchState.ended:
		_big.text = "TIME!  %s wins" % _winner
	elif st.dead:
		_big.text = "YOU DIED"
	elif st.jail > 0.0:
		_big.text = "IN PRISON  %ds\nwork a shift, score in the yard, win in the ring, pay the gate guard - or find another way out" % ceili(st.jail)
	else:
		_big.text = ""

	_scores.visible = MatchState.ended or Input.is_action_pressed("scores")
	if _scores.visible:
		var text := "%-16s %8s %6s\n" % ["PLAYER", "MONEY", "KILLS"]
		for r in _ranked():
			text += "%-16s %8s %6d\n" % [r.pname, "R$%d" % r.st.money, r.st.kills]
		_scores_text.text = text

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
			var count := Label.new()
			count.add_theme_font_size_override("font_size", 13)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(count)
			var tol := _bar(Color(1.0, 0.35, 0.2))
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
			frame.bg_color = Color(0, 0, 0, 0.55 if lit else 0.35)
			frame.set_border_width_all(3 if lit else 1)
			frame.border_color = Color(1.0, 0.85, 0.3) if lit else Color(1, 1, 1, 0.25)
			frame.set_corner_radius_all(6)
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
