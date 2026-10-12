extends CanvasLayer
## Whole HUD built in code: status, mic + intimidation meters, noise pings,
## scoreboard, vendor shop and drug screen effects.

const HEAT_TEXT := ["", "WANTED: robbery", "WANTED: assault", "WANTED: armed - police will shoot"]
## By Police.VIS_*: whether they can see you right now.
const VIS_TEXT := ["", "\nSEARCHING - stay out of sight", "\nSPOTTED", "\nHIDDEN - cooling off faster"]
const PING_TIME := 2.5
const PING_RADIUS := 230.0

var shop_open := false

var _root: Control
var _tint: ColorRect
var _blur: ColorRect
var _hp: ProgressBar
var _money: Label
var _weapon: Label
var _drugs: Label
var _effects: Label
var _clock: Label
var _crowd: Label
var _heat: Label
var _speed: Label
var _target: Label
var _prompt: Label
var _mark: Label
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
	_drugs = _label(tl, 16)
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
	help.text = "WASD move  Shift sprint\nHold Space to hop: strafe + turn in the air for speed\nSpace in the air: double jump   at a wall: wall jump\nCtrl / C slide (jump out of it for a boost), or crouch and creep   Q dive\nScroll: first / third person\nLMB attack  RMB aim  R reload   the head is a one-tap; a fist there knocks them out\nHold E + SHOUT to rob (V = fake shout)\nHold E silently on a sunbather to pickpocket\nF use / pick up / shop / hide / take a moto   1 fists / knife   2 guns   3-5 drugs\nRun into a football to dribble, hit it to shoot\nTab scores   Esc free mouse"

	# Bottom centre: robbery.
	var bc := _vbox(Control.PRESET_CENTER_BOTTOM, Vector2(0, -24))
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


func _unhandled_input(e: InputEvent) -> void:
	if shop_open and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("interact")):
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
	_weapon.text = w.name if w.melee else "%s  [%d / %d]" % [w.name, st.mag.get(st.equipped, 0), st.ammo]
	if not w.melee and st.mag.get(st.equipped, 0) == 0:
		_weapon.text += "   R: reload" if st.ammo > 0 else "   EMPTY"
	_mark_t -= delta
	_mark.visible = _mark_t > 0.0

	var lines: Array = []
	var fx: Array = []
	for d in DB.DRUGS:
		var n: int = st.inv.get(d, 0)
		var tol: float = st.tol.get(d, 0.0)
		if n > 0 or tol > 0.01:
			lines.append("[%s] %s x%d   tolerance %d%%" % [DB.ITEMS[d].key.right(1).to_int() + 2, DB.ITEMS[d].name, n, int(tol * 100.0)])
		var phase: String = p.drug_phase(d)
		if phase != "":
			fx.append("%s: %s %ds" % [DB.ITEMS[d].name, {"high": "HIGH", "down": "COMEDOWN", "od": "OVERDOSE"}[phase], ceili(st.drugs[d].t)])
	if p.is_drunk():
		fx.append("Caipirinha: TIPSY %ds" % ceili(st.drugs["caipirinha"].t))
	_drugs.text = "\n".join(lines)
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

	_mic_bar.value = Mic.loudness * p.mic_mult()
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
		_big.text = "IN PRISON  %ds" % ceili(st.jail)
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


func _drug_screen(p, delta: float) -> void:
	var tint := Color(0, 0, 0, 0)
	var blur := 0.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	match p.drug_phase("cocaine"):
		"high": tint = Color(1, 1, 1, 0.06)
		"down": tint = Color(0.2, 0.2, 0.3, 0.3)
		"od": tint = Color(0.9, 0.0, 0.0, 0.15 + 0.3 * pulse)
	match p.drug_phase("weed"):
		"high":
			tint = Color(0.2, 0.7, 0.2, 0.1)
			blur = 0.8
		"od":
			tint = Color(0.1, 0.5, 0.1, 0.3)
			blur = 3.0
	if p.drug_phase("meth") == "od":
		tint = Color(0.5, 0.3, 0.9, 0.2)
		# Paranoia: noises that are not there.
		_fake_ping_t -= delta
		if _fake_ping_t <= 0.0:
			_fake_ping_t = randf_range(0.6, 2.0)
			add_ping(p.global_position + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30)))
	_tint.color = tint
	_blur.visible = blur > 0.0
	_blur.material.set_shader_parameter("amount", blur)


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
