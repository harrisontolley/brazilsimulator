extends Control
## The tester's menu, on F5: one big panel of buttons that give you things, spawn things and
## take you places, for trying the game out with a friend. It is in no list of controls on
## purpose. Every button is one request to Game.srv_cheat, which the host carries out for
## whoever pressed it, so a joined player can use it as freely as the host. The lists of
## items are read from DB, so a new weapon or drug turns up here by itself.

signal closed

const UI := preload("res://scenes/ui/ui_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")

const COLUMNS := 5
## Match time, as a percentage of the match: where the sky is for each.
const TIMES := [["Morning", 0], ["Noon", 30], ["Sunset", 82], ["Night", 97]]
## The sorts of person worth asking for, in the order they are likely wanted.
const FOLK := ["tourist", "local", "mafia", "vendor", "malandro", "traficante", "vapor", "olheiro", "velho", "guarda", "seguranca", "preso", "socialite", "magnata"]

var _tabs: TabContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UI.label(26, UI.CANARY, true)
	title.text = "TEST MENU"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := UI.label(18, UI.DIM)
	hint.text = "F5 or Esc to close"
	head.add_child(hint)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)

	_tabs = TabContainer.new()
	col.add_child(_tabs)
	_status = UI.label(18, UI.SEA)
	_status.text = "Click anything. It happens to you."
	col.add_child(_status)

	_weapons()
	_ammo_and_items()
	_drugs()
	_player()
	_spawn()
	_world()
	_teleport()

	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var win := get_viewport_rect().size
	_tabs.custom_minimum_size = Vector2(clampf(win.x * 0.86, 480.0, 1500.0), clampf(win.y * 0.7, 240.0, 900.0))


# --- the tabs ---

func _weapons() -> void:
	var v := _tab("Weapons")
	var g := _grid(v, "")
	_button(g, "ALL WEAPONS", "give_all")
	for id in _of_type("weapon"):
		_button(g, DB.ITEMS[id].name, "give", id)


func _ammo_and_items() -> void:
	var v := _tab("Items")
	var g := _grid(v, "Ammo")
	_button(g, "Refill everything", "refill")
	for id in _of_type("ammo"):
		_button(g, DB.ITEMS[id].name, "give", id)
	var rest: Array = []
	for id in DB.ITEMS.keys():
		if not ["weapon", "ammo", "drug"].has(DB.ITEMS[id].type):
			rest.append(id)
	g = _grid(v, "Food, drink, tools, loot")
	for id in rest:
		_button(g, DB.ITEMS[id].name, "give", id)


func _drugs() -> void:
	var v := _tab("Drugs")
	var g := _grid(v, "Five of each, in your pockets")
	for id in DB.DRUGS:
		_button(g, DB.ITEMS[id].name, "give", id)
	g = _grid(v, "High right now, with no overdose")
	for id in DB.DRUGS:
		_button(g, DB.ITEMS[id].name, "high", id)
	g = _grid(v, "")
	_button(g, "Sober up", "sober")


func _player() -> void:
	var v := _tab("You")
	var g := _grid(v, "Money")
	for amount in [1000, 10000, 100000, 1000000]:
		_button(g, "+$%d" % amount, "money", "", amount)
	g = _grid(v, "Body")
	_button(g, "Heal fully", "heal")
	_button(g, "God mode (toggle)", "god")
	_button(g, "Noclip (toggle)", "", "", 0, func():
		var p = Net.game.local_player
		p.set_noclip(not p.noclip)
		_say("Noclip %s. Jump goes up, crouch goes down, sprint is faster." % ("ON" if p.noclip else "off")))
	_button(g, "Leave jail", "unjail")
	g = _grid(v, "Wanted level")
	for n in 4:
		_button(g, "Heat %d" % n, "heat", "", n)
	_button(g, "Calm crowd and cops", "calm")


func _spawn() -> void:
	var v := _tab("Spawn")
	var g := _grid(v, "Rides")
	_button(g, "Motorbike", "moto")
	_button(g, "Jet ski", "ski")
	g = _grid(v, "People, friendly")
	for id in FOLK:
		_button(g, id.capitalize(), "npc", id, 0)
	g = _grid(v, "People, angry at you")
	for id in FOLK:
		_button(g, id.capitalize(), "npc", id, 1)
	g = _grid(v, "Dogs")
	var breeds: Array = Net.game.dogs.BREEDS
	for k in breeds.size():
		_button(g, "%s" % breeds[k].name.capitalize(), "dog", "friendly", k)
	g = _grid(v, "Dogs, mean")
	for k in breeds.size():
		_button(g, "%s" % breeds[k].name.capitalize(), "dog", "mean", k)
	g = _grid(v, "Other")
	_button(g, "$1,000 on the ground", "drop", "", 1000)
	_button(g, "$20,000 on the ground", "drop", "", 20000)
	_button(g, "Explosion ahead", "boom")


func _world() -> void:
	var v := _tab("World")
	var g := _grid(v, "Time of day")
	for t in TIMES:
		_button(g, t[0], "time", "", t[1])
	g = _grid(v, "Make it happen (a second from now)")
	for ev in Net.game.events.NAMES:
		_button(g, String(ev).capitalize(), "event", ev)


func _teleport() -> void:
	var v := _tab("Teleport")
	var spots: Array = [
		["Hospital", DB.HOSPITAL_POS], ["Prison", DB.PRISON_POS], ["Outside prison", DB.RELEASE_POS],
		["Baile funk", DB.BAILE_POS], ["Boca", DB.BOCA_POS], ["Campinho", DB.CAMPINHO_POS],
		["Yacht", Layout.YACHT_POS], ["Roleta wheel", Layout.WHEEL_POS],
	]
	var g := _grid(v, "Places")
	for s in spots:
		_button(g, s[0], "tp", _vec(s[1]))
	g = _grid(v, "Shops and vendors")
	for vendor in DB.VENDORS:
		if vendor.has("pos"):
			_button(g, String(vendor.name).capitalize(), "tp", _vec(vendor.pos))
	g = _grid(v, "Players")
	var me: int = Net.game.local_player.id
	var others := 0
	for id in Net.game.players.keys():
		if id != me:
			others += 1
			_button(g, "To %s" % Net.game.players[id].pname, "tp", "player:%d" % id)
	if others == 0:
		var none := UI.label(18, UI.DIM)
		none.text = "Nobody else is here yet."
		g.add_child(none)


# --- building blocks ---

## A scrolling page on the tab strip; returns the column to put sections in.
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


## A heading (unless empty) over a grid of buttons.
func _grid(into: VBoxContainer, heading: String) -> GridContainer:
	if heading != "":
		var l := UI.label(20, UI.CANARY, true)
		l.text = heading.to_upper()
		into.add_child(l)
	var g := GridContainer.new()
	g.columns = COLUMNS
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	into.add_child(g)
	return g


## One button. With `what` it asks the host for that; with `local` it just runs that here.
func _button(into: GridContainer, text: String, what: String, arg := "", n := 0, local := Callable()) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	if local.is_valid():
		b.pressed.connect(local)
	else:
		b.pressed.connect(func():
			Net.game.to_server("srv_cheat", [what, arg, n])
			_say(text))
	into.add_child(b)


func _say(text: String) -> void:
	_status.text = text


## Everything in DB.ITEMS of one kind, in the order they are written.
func _of_type(kind: String) -> Array:
	var out: Array = []
	for id in DB.ITEMS.keys():
		if DB.ITEMS[id].type == kind:
			out.append(id)
	return out


func _vec(v: Vector3) -> String:
	return "%.1f,%.1f,%.1f" % [v.x, v.y + 0.5, v.z]
