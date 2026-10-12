extends "res://scenes/world/world_kit.gd"
## The buildings you can walk into: a casino, bars, a corner shop, a chemist, a barber.
##
## Each takes a lot the street rows leave empty (Layout.LOTS). The storeys above stay one box
## like every other building, and its underside is the ceiling, so the helicopter and anyone's
## line of sight treat it as the roof it is. The ground floor is real walls with a doorway and
## open window frames: you can see in, shoot in and dive out, and a wall is still a wall.
##
## Everything usable inside is registered with Places (the room, its doors, seats, hiding
## places, people standing about) and with the interact system by Game.

const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const Interact := preload("res://scenes/player/interact.gd")

const H := 3.5
const T := 0.3
const DOOR_W := 1.8
const DOOR_H := 2.5
const TILE := Color(0.82, 0.8, 0.74)
const PLASTER := Color(0.93, 0.9, 0.82)
const DARK := Color(0.14, 0.14, 0.16)
const STEEL := Color(0.72, 0.73, 0.75)
const FELT := Color(0.08, 0.42, 0.2)

var _rng := RandomNumberGenerator.new()
var _lights: Array = []  # [room index, Node3D]
var _t := 0.0


func _ready() -> void:
	_rng.seed = 7741
	_init_kit()
	for lot in Layout.LOTS:
		if lot.kind == "presidio":
			_presidio(lot)
			continue
		var room := _shell(lot)
		match lot.kind:
			"cassino": _cassino(lot, room)
			"boteco": _boteco(lot, room)
			"mercado": _mercado(lot, room)
			"farmacia": _farmacia(lot, room)
			"barbearia": _barbearia(lot, room)
	_flush()


## Lamps only burn in the rooms near the local player.
func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var g = Net.game
	if g == null or g.local_player == null:
		return
	var at: Vector3 = g.local_player.global_position
	for e in _lights:
		var box: AABB = Places.rooms[e[0]].box
		e[1].visible = box.grow(40.0).has_point(at)


## Walls, floor, ceiling and the storeys above for one lot. Returns its room index.
func _shell(lot: Dictionary) -> int:
	var z0: float = Layout.BLOCK_A_Z if lot.row == 0 else Layout.BLOCK_B_Z
	var z1: float = Layout.RUA_Z if lot.row == 0 else Layout.FOOT_Z
	var x0: float = lot.x0
	var x1: float = lot.x1
	var w := x1 - x0
	var depth := z1 - z0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var tint: Color = lot.tint
	var up: float = H * lot.floors
	var wall := Color(tint.r, tint.g, tint.b)

	# Above: an ordinary building, standing on the ground floor's walls.
	if lot.floors > 0:
		var skin := tint
		skin.a = 0.37
		_tower(Vector3(cx, H + up * 0.5, cz), Vector3(w - 0.3, up, depth), skin)
		_collider(Vector3(cx, H + up * 0.5, cz), Vector3(w, up, depth))
	else:
		_block(Vector3(cx, H + 0.15, cz), Vector3(w, 0.3, depth), wall.darkened(0.2))
	_box(Vector3(cx, 0.03, cz), Vector3(w - T, 0.06, depth - T), lot.get("floor", TILE))
	_box(Vector3(cx, H - 0.04, cz), Vector3(w - T, 0.08, depth - T), PLASTER)

	for x in [x0 + T * 0.5, x1 - T * 0.5]:
		_block(Vector3(x, H * 0.5, cz), Vector3(T, H, depth), wall)
	var door_x: float = lot.get("door", cx)
	var doors: Array = [[Vector3(door_x, 0, z0 - 1.3), Vector3(door_x, 0, z0 + 1.3)]]
	var front: Array = [[door_x, DOOR_W, 0.0, DOOR_H]]
	var wx := x0 + 2.4
	while wx < x1 - 2.0:
		if absf(wx - door_x) > 2.6:
			front.append([wx, 2.4, 1.0, 2.5])
		wx += 3.6
	_wall_with(z0, x0, x1, front, wall)
	var back: Array = []
	if lot.has("back"):
		back.append([lot.back, DOOR_W, 0.0, DOOR_H])
		doors.append([Vector3(lot.back, 0, z1 + 1.3), Vector3(lot.back, 0, z1 - 1.3)])
	_wall_with(z1, x0, x1, back, wall.darkened(0.12))

	# Out front: a lit sign, an awning, a step.
	var name_w := minf(w - 2.0, lot.name.length() * 0.62 + 1.2)
	_glow(Vector3(cx, 4.2, z0 - 0.12), Vector3(name_w, 1.0, 0.12), lot.sign)
	_sign(lot.name, Vector3(cx, 4.2, z0 - 0.2), 150, Color(1.0, 0.97, 0.85), PI)
	_block(Vector3(cx, 3.3, z0 - 1.0), Vector3(w - 1.0, 0.12, 2.0), lot.sign.darkened(0.25))
	_box(Vector3(door_x, 0.05, z0 - 0.3), Vector3(DOOR_W + 0.6, 0.1, 0.8), TILE.darkened(0.2))

	var room := Places.add_room({"name": lot.name, "kind": lot.kind,
			"box": AABB(Vector3(x0, -0.5, z0), Vector3(w, H + 0.5, depth)),
			"public": AABB(Vector3(x0 + T, -0.5, z0 + T), Vector3(w - T * 2.0, H + 0.5, lot.get("public", depth) - T * 2.0)),
			"doors": doors, "cops": true})
	var lamps := Node3D.new()
	add_child(lamps)
	for k in 2:
		var l := OmniLight3D.new()
		l.position = Vector3(cx + (k - 0.5) * w * 0.45, 3.0, cz + (0.5 - k) * depth * 0.35)
		l.omni_range = maxf(w, depth) * 0.7
		l.light_energy = 1.6
		l.light_color = lot.get("light", Color(1.0, 0.9, 0.75))
		l.shadow_enabled = false
		lamps.add_child(l)
		_glow(l.position + Vector3(0, 0.38, 0), Vector3(1.2, 0.06, 0.3), Color(1.0, 0.95, 0.85))
	_lights.append([room, lamps])
	return room


## A wall along x at depth z with holes in it: each opening is [centre x, width, bottom, top].
func _wall_with(z: float, x0: float, x1: float, openings: Array, tint: Color) -> void:
	openings.sort_custom(func(a, b): return a[0] < b[0])
	var x := x0
	for o in openings:
		var lo: float = o[0] - o[1] * 0.5
		var hi: float = o[0] + o[1] * 0.5
		if lo > x:
			_block(Vector3((x + lo) * 0.5, H * 0.5, z), Vector3(lo - x, H, T), tint)
		if o[2] > 0.0:
			_block(Vector3(o[0], o[2] * 0.5, z), Vector3(o[1], o[2], T), tint)
			_box(Vector3(o[0], o[2] + 0.03, z), Vector3(o[1] + 0.1, 0.06, T + 0.14), tint.lightened(0.25))
		_block(Vector3(o[0], (o[3] + H) * 0.5, z), Vector3(o[1], H - o[3], T), tint)
		x = hi
	if x1 > x:
		_block(Vector3((x + x1) * 0.5, H * 0.5, z), Vector3(x1 - x, H, T), tint)


## A table with stools round it that people can be sat at.
func _table(at: Vector3, room: int, stools := 4, tint := WOOD) -> void:
	_block(at + Vector3(0, 0.36, 0), Vector3(0.14, 0.72, 0.14), DARK)
	_box(at + Vector3(0, 0.75, 0), Vector3(0.95, 0.06, 0.95), tint)
	var table := Places.new_table()
	for s in stools:
		var off := Vector3(cos(s * TAU / stools + 0.5), 0, sin(s * TAU / stools + 0.5)) * 0.85
		_box(at + off + Vector3(0, 0.23, 0), Vector3(0.36, 0.46, 0.36), tint.darkened(0.3))
		Places.add_seat(at + off, Kit.face(-off), room, table)


## A counter running along x with somebody to serve behind it.
func _counter(at: Vector3, length: float, tint: Color, room: int) -> void:
	_block(at + Vector3(0, 0.55, 0), Vector3(length, 1.1, 0.7), tint)
	_box(at + Vector3(0, 1.13, 0), Vector3(length + 0.2, 0.06, 0.9), tint.lightened(0.3))
	Places.add_spot(at + Vector3(0, 0, 1.1), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.TALK, Kit.PHONE], "local", room)


## Shelves against the back wall, stocked with coloured odds and ends.
func _shelves(at: Vector3, length: float, rows := 3) -> void:
	_block(at + Vector3(0, 1.1, 0), Vector3(length, 2.2, 0.4), WOOD.darkened(0.25))
	for r in rows:
		_box(at + Vector3(0, 0.55 + r * 0.6, -0.22), Vector3(length, 0.05, 0.3), WOOD)
		var x := -length * 0.5 + 0.2
		while x < length * 0.5 - 0.1:
			_box(at + Vector3(x, 0.72 + r * 0.6, -0.24), Vector3(0.12, 0.28, 0.12), Color.from_hsv(_rng.randf(), 0.7, 0.9))
			x += _rng.randf_range(0.18, 0.4)


## A cupboard big enough to stand in with the door shut.
func _cupboard(at: Vector3, room: int, out: Vector3) -> void:
	_block(at + Vector3(0, 1.05, 0), Vector3(1.1, 2.1, 0.7), WOOD.darkened(0.35))
	_box(at + Vector3(0, 1.05, 0) + out * 0.36, Vector3(0.04, 1.9, 0.04) if absf(out.x) > 0.5 else Vector3(0.04, 1.9, 0.04), STEEL)
	Places.add_hide(at + out * 1.0 + Vector3(0, 0.2, 0), "armario", at + out * 1.3 + Vector3(0, 0.2, 0), room)


func _z0(lot: Dictionary) -> float:
	return Layout.BLOCK_A_Z if lot.row == 0 else Layout.BLOCK_B_Z


func _z1(lot: Dictionary) -> float:
	return Layout.RUA_Z if lot.row == 0 else Layout.FOOT_Z


# --- what is in each ---

## A bar: counter and bottles down one side, tables down the other, more out on the pavement.
func _boteco(lot: Dictionary, room: int) -> void:
	var z0 := _z0(lot)
	var z1 := _z1(lot)
	var cx: float = (lot.x0 + lot.x1) * 0.5
	var bar := Vector3(lot.x0 + 2.6, 0, z0 + 6.5)
	_block(bar + Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 8.0), WOOD.darkened(0.2))
	_box(bar + Vector3(0, 1.13, 0), Vector3(0.9, 0.06, 8.2), WOOD.lightened(0.2))
	Places.add_spot(bar + Vector3(-1.1, 0, 0), Kit.face(Vector3.RIGHT), [Kit.STAND, Kit.TALK], "local", room)
	for k in 12:
		_box(Vector3(lot.x0 + 0.5, 1.4 + (k % 3) * 0.5, z0 + 3.2 + (k / 3) * 1.8), Vector3(0.12, 0.34, 0.12), Color.from_hsv(_rng.randf(), 0.6, 0.8))
	for k in 5:
		Places.add_spot(bar + Vector3(0.95, 0, -3.2 + k * 1.6), Kit.face(Vector3.LEFT), [Kit.DRINK, Kit.TALK, Kit.DRINK, Kit.PHONE], "local", room)
	for row in 3:
		for col in 2:
			_table(Vector3(cx + 1.0 + col * 3.4, 0, z0 + 4.0 + row * 5.0), room)
	# Out on the pavement, where the bikes go past.
	for k in 3:
		_table(Vector3(lot.x0 + 2.5 + k * ((lot.x1 - lot.x0 - 5.0) / 2.0), 0, z0 - 2.3 if lot.row == 1 else z0 - 1.9), -1, 3)
	_cupboard(Vector3(lot.x1 - 1.2, 0, z1 - 1.0), room, Vector3.FORWARD)
	_glow(Vector3(cx, 2.6, z1 - 0.3), Vector3(2.2, 0.7, 0.08), Color(1.0, 0.25, 0.2))
	_sign("BRAHMA", Vector3(cx, 2.6, z1 - 0.36), 90, Color.WHITE, PI)


func _mercado(lot: Dictionary, room: int) -> void:
	var z0 := _z0(lot)
	var z1 := _z1(lot)
	var cx: float = (lot.x0 + lot.x1) * 0.5
	_counter(Vector3(lot.x0 + 3.0, 0, z0 + 3.0), 3.4, Color(0.2, 0.5, 0.75), room)
	for k in 3:
		for side in [-1.0, 1.0]:
			_shelves(Vector3(cx + 1.2 * side + 1.5, 0, z0 + 9.0 + k * 4.5), 0.4)
		_block(Vector3(cx + 1.5, 1.0, z0 + 9.0 + k * 4.5), Vector3(2.8, 2.0, 0.5), WOOD.darkened(0.3))
		for j in 10:
			_box(Vector3(cx + 0.3 + (j % 5) * 0.55, 0.7 + (j / 5) * 0.7, z0 + 9.0 + k * 4.5 - 0.3), Vector3(0.3, 0.4, 0.14), Color.from_hsv(_rng.randf(), 0.75, 0.9))
			_box(Vector3(cx + 0.3 + (j % 5) * 0.55, 0.7 + (j / 5) * 0.7, z0 + 9.0 + k * 4.5 + 0.3), Vector3(0.3, 0.4, 0.14), Color.from_hsv(_rng.randf(), 0.75, 0.9))
	_shelves(Vector3(cx, 0, z1 - 0.6), lot.x1 - lot.x0 - 3.0)
	# A rail of shirts: a change of clothes for anyone who needs to look like someone else.
	_block(Vector3(lot.x1 - 1.2, 1.5, z0 + 5.0), Vector3(0.08, 0.08, 3.0), STEEL)
	for k in 7:
		_box(Vector3(lot.x1 - 1.2, 1.1, z0 + 3.8 + k * 0.4), Vector3(0.5, 0.7, 0.06), Color.from_hsv(_rng.randf(), 0.7, 0.9))
	Places.add_use(&"clothes", Vector3(lot.x1 - 2.0, 0, z0 + 5.0), "buy a change of clothes  R$%d" % DB.CLOTHES_PRICE)
	_cupboard(Vector3(lot.x0 + 1.0, 0, z1 - 1.4), room, Vector3.RIGHT)
	for k in 4:
		Places.add_spot(Vector3(cx - 2.0 + _rng.randf_range(-1.0, 1.0), 0, z0 + 7.0 + k * 4.2), _rng.randf() * TAU, [Kit.STAND, Kit.PHONE, Kit.STAND], "", room)


func _farmacia(lot: Dictionary, room: int) -> void:
	var z0 := _z0(lot)
	var z1 := _z1(lot)
	var cx: float = (lot.x0 + lot.x1) * 0.5
	_counter(Vector3(cx, 0, z0 + 9.0), lot.x1 - lot.x0 - 4.0, Color(0.95, 0.95, 0.97), room)
	_shelves(Vector3(cx, 0, z0 + 11.5), lot.x1 - lot.x0 - 3.0, 3)
	_glow(Vector3(cx, 2.8, z0 + 11.2), Vector3(0.9, 0.25, 0.06), Color(0.1, 0.8, 0.3))
	_glow(Vector3(cx, 2.8, z0 + 11.2), Vector3(0.25, 0.9, 0.06), Color(0.1, 0.8, 0.3))
	for k in 3:
		_block(Vector3(lot.x0 + 1.0, 0.25, z0 + 2.5 + k * 1.0), Vector3(0.5, 0.5, 0.5), Color(0.25, 0.5, 0.8))
	# The stock room behind is not for customers.
	_wall_with(z0 + 13.0, lot.x0, lot.x1, [[lot.x1 - 2.0, DOOR_W, 0.0, DOOR_H]], PLASTER)
	_cupboard(Vector3(lot.x0 + 1.2, 0, z1 - 1.0), room, Vector3.FORWARD)
	for k in 2:
		Places.add_spot(Vector3(cx - 2.5 + k * 3.0, 0, z0 + 7.6), Kit.face(Vector3.BACK), [Kit.STAND, Kit.PHONE], "", room)


func _barbearia(lot: Dictionary, room: int) -> void:
	var z0 := _z0(lot)
	var z1 := _z1(lot)
	var cx: float = (lot.x0 + lot.x1) * 0.5
	for k in 3:
		var at := Vector3(lot.x0 + 2.2, 0, z0 + 3.5 + k * 3.2)
		_block(at + Vector3(0, 0.3, 0), Vector3(0.7, 0.6, 0.7), Color(0.6, 0.08, 0.08))
		_box(at + Vector3(-0.3, 0.9, 0), Vector3(0.12, 0.7, 0.7), Color(0.6, 0.08, 0.08))
		_box(Vector3(lot.x0 + 0.4, 1.7, at.z), Vector3(0.06, 1.3, 1.6), Color(0.7, 0.85, 0.95))
		_box(Vector3(lot.x0 + 0.6, 1.0, at.z), Vector3(0.4, 0.06, 1.6), WOOD)
		var seat := Places.add_seat(at + Vector3(0, 0.16, 0), Kit.face(Vector3.LEFT), room, Places.new_table())
		Places.seats[seat]["solo"] = true
		Places.add_spot(at + Vector3(0.9, 0, 0.3), Kit.face(Vector3.LEFT), [Kit.WORK, Kit.TALK, Kit.WORK], "local", room)
	# The pole outside, and somewhere to wait.
	_glow(Vector3(lot.x0 + 0.6, 1.8, z0 - 0.4), Vector3(0.22, 1.1, 0.22), Color(0.9, 0.15, 0.15))
	_glow(Vector3(lot.x0 + 0.6, 1.8, z0 - 0.4), Vector3(0.23, 0.25, 0.23), Color(0.95, 0.95, 0.95))
	for k in 3:
		_block(Vector3(lot.x1 - 1.0, 0.25, z0 + 3.0 + k * 1.1), Vector3(0.6, 0.5, 0.6), DARK)
		Places.add_seat(Vector3(lot.x1 - 1.0, 0.04, z0 + 3.0 + k * 1.1), Kit.face(Vector3.LEFT), room, Places.new_table())
	Places.add_use(&"clothes", Vector3(cx, 0, z0 + 12.0), "a shave and a clean shirt  R$%d" % DB.CLOTHES_PRICE)
	_block(Vector3(cx, 0.55, z0 + 13.0), Vector3(2.4, 1.1, 0.6), WOOD)
	_cupboard(Vector3(lot.x1 - 1.2, 0, z1 - 1.0), room, Vector3.FORWARD)


## The bingo hall that is not a bingo hall: slots along the walls, roulette and blackjack in
## the middle, a bar, the bicho, and a cage at the back with the takings in it.
func _cassino(lot: Dictionary, room: int) -> void:
	var z0 := _z0(lot)
	var z1 := _z1(lot)
	var cage_z := z1 - 7.5
	# Caça-níqueis down both side walls.
	for side in [-1.0, 1.0]:
		for k in 6:
			var at := Vector3((lot.x0 + 1.0) if side < 0.0 else (lot.x1 - 1.0), 0, z0 + 2.6 + k * 2.2)
			var tint := Color.from_hsv(_rng.randf(), 0.75, 0.85)
			_block(at + Vector3(0, 0.95, 0), Vector3(0.8, 1.9, 0.9), tint.darkened(0.45))
			_glow(at + Vector3(-side * 0.41, 1.35, 0), Vector3(0.04, 0.5, 0.66), tint)
			_glow(at + Vector3(-side * 0.41, 1.85, 0), Vector3(0.04, 0.16, 0.7), Color(1.0, 0.85, 0.2))
			_box(at + Vector3(-side * 0.5, 0.85, 0), Vector3(0.22, 0.08, 0.7), STEEL)
			_box(at + Vector3(-side * 0.3, 1.25, 0.5), Vector3(0.06, 0.5, 0.06), STEEL)
			Places.add_use(&"slot", at + Vector3(-side * 1.1, 0, 0), "play the caça-níquel", k)
			if _rng.randf() < 0.55:
				Places.add_spot(at + Vector3(-side * 1.0, 0, 0), Kit.face(Vector3(side, 0, 0)), [Kit.WORK, Kit.STAND, Kit.WORK, Kit.PHONE], "", room)
	# Roleta.
	for k in 2:
		var at := Vector3(-9.0 + k * 18.0, 0, z0 + 6.0)
		_block(at + Vector3(0, 0.45, 0), Vector3(3.6, 0.9, 1.9), WOOD.darkened(0.4))
		_box(at + Vector3(0.5, 0.92, 0), Vector3(2.4, 0.04, 1.6), FELT)
		_block(at + Vector3(-1.2, 0.98, 0), Vector3(1.0, 0.16, 1.0), WOOD.darkened(0.55))
		_glow(at + Vector3(-1.2, 1.08, 0), Vector3(0.75, 0.04, 0.75), Color(0.75, 0.1, 0.1))
		_glow(at + Vector3(-1.2, 1.1, 0), Vector3(0.3, 0.06, 0.3), Color(0.9, 0.8, 0.3))
		Places.add_use(&"roulette", at + Vector3(0.4, 0, -1.6), "play roleta", k)
		Places.add_spot(at + Vector3(-0.4, 0, 1.5), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.TALK, Kit.STAND], "local", room)
		for j in 2:
			Places.add_spot(at + Vector3(1.0 + j * 0.9, 0, -1.5), Kit.face(Vector3.BACK), [Kit.STAND, Kit.CLAP, Kit.PHONE, Kit.STAND], "", room)
	# Vinte-e-um.
	for k in 3:
		var at := Vector3(-11.0 + k * 11.0, 0, z0 + 12.5)
		_block(at + Vector3(0, 0.45, 0), Vector3(2.6, 0.9, 1.3), WOOD.darkened(0.4))
		_box(at + Vector3(0, 0.92, 0), Vector3(2.4, 0.04, 1.15), FELT)
		for c in 4:
			_box(at + Vector3(-0.6 + c * 0.4, 0.95, -0.2), Vector3(0.2, 0.01, 0.3), Color(0.97, 0.97, 0.95))
		Places.add_use(&"blackjack", at + Vector3(0, 0, -1.3), "play vinte-e-um", k)
		Places.add_spot(at + Vector3(0, 0, 1.2), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.TALK], "local", room)
		var table := Places.new_table()
		for s in 2:
			_box(at + Vector3(-0.7 + s * 1.4, 0.23, -1.0), Vector3(0.36, 0.46, 0.36), DARK)
			Places.add_seat(at + Vector3(-0.7 + s * 1.4, 0, -1.0), Kit.face(Vector3.BACK), room, table)
	# The cage: a counter behind bars, and the door the staff use.
	_wall_with(cage_z, lot.x0, lot.x1, [[0.0, 6.0, 1.1, 2.6], [lot.x1 - 3.0, DOOR_W, 0.0, DOOR_H]], Color(0.3, 0.05, 0.08))
	for k in 13:
		_block(Vector3(-3.0 + k * 0.5, 1.85, cage_z), Vector3(0.06, 1.5, 0.06), STEEL)
	_glow(Vector3(0, 3.0, cage_z - 0.2), Vector3(2.4, 0.5, 0.06), Color(1.0, 0.8, 0.2))
	_sign("CAIXA", Vector3(0, 3.0, cage_z - 0.26), 110, DARK, PI)
	_block(Vector3(0, 0.6, cage_z + 3.0), Vector3(3.0, 1.2, 1.2), Color(0.25, 0.27, 0.3))
	_glow(Vector3(0, 0.75, cage_z + 2.38), Vector3(0.4, 0.4, 0.04), Color(0.9, 0.8, 0.3))
	Places.add_use(&"cage", Vector3(0, 0, cage_z + 1.8), "empty the safe  (needs a gun)", 0, 6.0)
	Places.add_spot(Vector3(0, 0, cage_z + 1.2), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.WORK], "local", room)
	_cupboard(Vector3(lot.x0 + 1.2, 0, z1 - 1.0), room, Vector3.FORWARD)
	# The bicho has a desk here too, out of the weather.
	_block(Vector3(-14.0, 0.5, cage_z - 1.0), Vector3(2.2, 1.0, 0.7), Color(0.85, 0.6, 0.1))
	_sign("JOGO DO BICHO  [F]", Vector3(-14.0, 1.6, cage_z - 1.4), 60, Color.WHITE, PI)
	Places.add_spot(Vector3(-14.0, 0, cage_z - 0.3), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.PHONE], "local", room)
	# The house keeps men on the door and men on the floor.
	for at in [Vector3(-2.2, 0, z0 - 1.0), Vector3(2.2, 0, z0 - 1.0)]:
		Places.add_spot(at, Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.LEAN], "seguranca", -1)
	for at in [Vector3(-16.0, 0, z0 + 16.0), Vector3(16.0, 0, z0 + 9.0), Vector3(lot.x1 - 4.5, 0, cage_z - 1.2)]:
		Places.add_spot(at, _rng.randf() * TAU, [Kit.STAND, Kit.STAND, Kit.CALL], "seguranca", room)
	# Red carpet, gold light.
	_box(Vector3(0, 0.07, z0 + 9.0), Vector3(8.0, 0.02, 17.0), Color(0.5, 0.05, 0.1))
	for k in 8:
		_glow(Vector3(lot.x0 + 3.0 + k * 6.0, 3.3, z0 + 0.5), Vector3(0.3, 0.3, 0.3), Color.from_hsv(k * 0.13, 0.8, 1.0))


# --- the presídio ---

## A wall along z at x, `h` high, with doorways: each gap is [centre z, width].
func _wall_z(x: float, z0: float, z1: float, gaps: Array, h: float, tint: Color) -> void:
	gaps.sort_custom(func(a, b): return a[0] < b[0])
	var z := z0
	for gap in gaps:
		var lo: float = gap[0] - gap[1] * 0.5
		if lo > z:
			_block(Vector3(x, h * 0.5, (z + lo) * 0.5), Vector3(0.4, h, lo - z), tint)
		_block(Vector3(x, (DOOR_H + h) * 0.5, gap[0]), Vector3(0.4, h - DOOR_H, gap[1]), tint)
		z = gap[0] + gap[1] * 0.5
	if z1 > z:
		_block(Vector3(x, h * 0.5, (z + z1) * 0.5), Vector3(0.4, h, z1 - z), tint)


## The prison, with the police station's front desk in one corner of it. Cells down the west
## side, showers, a yard open to the sky behind bars, a canteen and a workshop to the east.
func _presidio(lot: Dictionary) -> void:
	var grey: Color = lot.tint
	var dark := grey.darkened(0.3)
	var inside := Interact.INSIDE
	var wh := 7.0
	# The shell: nobody gets in or out over these.
	_block(Vector3(-29.0, wh * 0.5, 111.3), Vector3(24.2, wh, 0.6), Color(0.9, 0.9, 0.92))
	_block(Vector3(-16.0, (DOOR_H + wh) * 0.5, 111.3), Vector3(DOOR_W, wh - DOOR_H, 0.6), Color(0.9, 0.9, 0.92))
	_block(Vector3(12.95, wh * 0.5, 111.3), Vector3(56.1, wh, 0.6), Color(0.9, 0.9, 0.92))
	_block(Vector3(0, wh * 0.5, 130.7), Vector3(82, wh, 0.6), grey)
	for x in [-40.7, 40.7]:
		_block(Vector3(x, wh * 0.5, 121), Vector3(0.6, wh, 20), grey)
	_collider(Vector3(0, wh + 0.3, 121), Vector3(82, 0.6, 20))
	_box(Vector3(0, 0.03, 121), Vector3(81, 0.06, 19), Color(0.55, 0.55, 0.55))
	# Roofs over the buildings, bars over the yard.
	for slab in [[-25.0, 32.0], [33.0, 16.0]]:
		_box(Vector3(slab[0], wh + 0.1, 121), Vector3(slab[1], 0.2, 20), dark)
	for k in 35:
		_box(Vector3(-9.0 + k, wh, 121), Vector3(0.12, 0.12, 19), DARK)
	for k in 5:
		_box(Vector3(8, wh + 0.05, 113.0 + k * 4.0), Vector3(34, 0.16, 0.16), DARK)
	# Inside walls.
	_wall_z(-23.0, 111.6, 130.4, [[126.0, DOOR_W]], wh, grey)
	_wall_z(-9.0, 121.0, 130.4, [[126.0, DOOR_W]], wh, grey)
	_wall_z(25.0, 111.6, 130.4, [[116.0, DOOR_W], [126.0, DOOR_W]], wh, grey)
	_block(Vector3(-16.0, wh * 0.5, 121.0), Vector3(14.4, wh, 0.4), grey)
	_block(Vector3(33.0, wh * 0.5, 121.0), Vector3(16.4, wh, 0.4), grey)
	# The visiting window between the front desk and the yard: bars, and a gap to talk through.
	_block(Vector3(-9.0, 0.55, 116.3), Vector3(0.4, 1.1, 9.4), grey)
	_block(Vector3(-9.0, 4.8, 116.3), Vector3(0.4, 4.4, 9.4), grey)
	_block(Vector3(-9.0, 1.85, 112.6), Vector3(0.4, 1.5, 2.0), grey)
	_block(Vector3(-9.0, 1.85, 119.8), Vector3(0.4, 1.5, 2.4), grey)
	for k in 13:
		_block(Vector3(-9.0, 1.85, 113.8 + k * 0.4), Vector3(0.08, 1.5, 0.08), STEEL)

	# The front desk (the only part the public, and the police, walk into).
	var lobby := Places.add_room({"name": "DELEGACIA", "kind": "delegacia", "box": AABB(Vector3(-23, -0.5, 111), Vector3(14, wh + 0.5, 10)),
			"public": AABB(Vector3(-22.6, -0.5, 111.6), Vector3(13.2, wh + 0.5, 9.0)),
			"doors": [[Vector3(-16, 0, 109.7), Vector3(-16, 0, 112.9)]], "cops": true})
	var room := Places.add_room({"name": lot.name, "kind": "presidio", "box": AABB(Vector3(-41, -0.5, 111), Vector3(82, wh + 0.5, 20)),
			"public": AABB(Vector3(-41, -0.5, 111), Vector3.ZERO),
			"doors": [[Vector3(8, 0, 109.7), Vector3(8, 0, 112.9)]], "cops": false})
	_box(Vector3(0, 5.6, 110.95), Vector3(82, 1.0, 0.1), lot.sign)
	_sign("DELEGACIA", Vector3(-16, 5.6, 110.88), 200, Color.WHITE, PI)
	_sign("PRESÍDIO", Vector3(14, 5.6, 110.88), 200, Color.WHITE, PI)
	for x in [-18.0, -14.0]:
		_glow(Vector3(x, 3.2, 110.9), Vector3(0.4, 0.4, 0.3), Color(0.2, 0.4, 1.0))
	_block(Vector3(-16.0, 0.55, 117.5), Vector3(5.0, 1.1, 0.8), WOOD.darkened(0.2))
	Places.add_spot(Vector3(-16.0, 0, 118.6), Kit.face(Vector3.FORWARD), [Kit.STAND, Kit.WORK, Kit.PHONE], "guarda", lobby)
	Places.add_use(&"bail", Vector3(-16.0, 0, 116.4), "pay a friend's bail")
	for k in 3:
		_block(Vector3(-21.6, 0.25, 113.5 + k * 1.2), Vector3(0.6, 0.5, 0.9), dark)
	# The gate everyone leaves by in the end, one way or another.
	_block(Vector3(8, 2.6, 111.75), Vector3(4.2, 5.2, 0.25), Color(0.25, 0.28, 0.32))
	for k in 9:
		_box(Vector3(6.2 + k * 0.45, 2.6, 111.9), Vector3(0.08, 5.0, 0.08), STEEL)
	Places.add_spot(Vector3(6.0, 0, 113.2), Kit.face(Vector3.BACK), [Kit.STAND, Kit.STAND, Kit.LEAN], "guarda", room)
	Places.add_use(&"bribe", Vector3(7.2, 0, 113.6), "slip the guard something", 0, 0.0, inside)

	# Cell block: six cells down the wall, bars for fronts.
	for k in 6:
		var z := 113.1 + k * 3.1
		_block(Vector3(-33.4, 1.6, z + 1.55), Vector3(14.4, 3.2, 0.25), grey.lightened(0.08))
		_block(Vector3(-38.6, 0.35, z), Vector3(2.0, 0.7, 0.9), dark)
		_box(Vector3(-38.6, 0.76, z), Vector3(1.9, 0.12, 0.8), Color(0.8, 0.78, 0.7))
		_block(Vector3(-38.6, 1.75, z), Vector3(2.0, 0.12, 0.9), dark)
		for j in 5:
			_box(Vector3(-26.2, 1.6, z - 1.2 + j * 0.3), Vector3(0.07, 3.2, 0.07), STEEL)
		_box(Vector3(-26.2, 3.2, z), Vector3(0.1, 0.1, 3.0), STEEL)
		Places.add_spot(Vector3(-30.0 - (k % 3) * 2.0, 0, z + 0.2), _rng.randf() * TAU, [Kit.SQUAT, Kit.STAND, Kit.LEAN, Kit.TALK], "preso", room)
	Places.add_use(&"dig", Vector3(-37.2, 0, 116.2), "the loose flagstone under the bunk", 0, 4.0, inside)
	# Showers.
	_box(Vector3(-16.0, 0.05, 125.7), Vector3(13.2, 0.04, 9.0), Color(0.75, 0.86, 0.9))
	for k in 4:
		_box(Vector3(-21.0 + k * 3.2, 2.3, 130.1), Vector3(0.1, 0.1, 0.7), STEEL)
		_box(Vector3(-21.0 + k * 3.2, 2.2, 129.7), Vector3(0.3, 0.1, 0.3), STEEL)

	# The yard.
	var pitch: Vector3 = Layout.YARD_PITCH[0]
	var half: Vector2 = Layout.YARD_PITCH[1]
	_box(pitch + Vector3(0, 0.07, 0), Vector3(half.x * 2.0, 0.02, half.y * 2.0), Color(0.3, 0.5, 0.36))
	_box(pitch + Vector3(0, 0.08, 0), Vector3(0.12, 0.02, half.y * 2.0), Color(0.95, 0.95, 0.95))
	for side in [-1.0, 1.0]:
		var gx: float = pitch.x + side * half.x
		for post in [-Layout.GOAL_HALF, Layout.GOAL_HALF]:
			_block(Vector3(gx, 1.1, pitch.z + post), Vector3(0.12, 2.2, 0.12), Color(0.95, 0.95, 0.95))
		_block(Vector3(gx, 2.2, pitch.z), Vector3(0.12, 0.12, Layout.GOAL_HALF * 2.0 + 0.12), Color(0.95, 0.95, 0.95))
	# Weights: a bench, a bar, a pile of plates cast in a bucket.
	_block(Vector3(-5.5, 0.25, 113.6), Vector3(0.5, 0.5, 1.6), dark)
	_box(Vector3(-5.5, 1.1, 113.2), Vector3(1.9, 0.07, 0.07), STEEL)
	for side in [-0.9, 0.9]:
		_box(Vector3(-5.5 + side, 1.1, 113.2), Vector3(0.12, 0.5, 0.5), DARK)
		_box(Vector3(-5.5 + side * 0.5, 0.55, 113.2), Vector3(0.07, 1.1, 0.07), STEEL)
	Places.add_use(&"weights", Vector3(-5.5, 0, 114.8), "lift", 0, 4.0, inside)
	for x in [-7.4, -3.4]:
		Places.add_spot(Vector3(x, 0, 114.0), Kit.face(Vector3.BACK), [Kit.LIFT, Kit.LIFT, Kit.STAND], "preso", room)
	# Dice on an upturned crate.
	_block(Vector3(21.5, 0.3, 113.8), Vector3(0.9, 0.6, 0.9), WOOD)
	for k in 2:
		_box(Vector3(21.3 + k * 0.3, 0.66, 113.8), Vector3(0.1, 0.1, 0.1), Color(0.97, 0.97, 0.95))
	Places.add_spot(Vector3(21.5, 0, 112.8), Kit.face(Vector3.BACK), [Kit.SQUAT, Kit.SQUAT, Kit.TALK], "preso", room)
	Places.add_spot(Vector3(22.7, 0, 114.2), Kit.face(Vector3.LEFT), [Kit.SQUAT, Kit.CLAP], "preso", room)
	Places.add_use(&"dice", Vector3(20.6, 0, 114.8), "throw dice with the banker", 0, 0.0, inside)
	# The rinha: a ring chalked on the concrete. What happens in it is nobody's business.
	var ring := Vector3(21.0, 0, 127.0)
	for k in 16:
		var a := TAU * k / 16.0
		_box(ring + Vector3(cos(a) * 3.2, 0.07, sin(a) * 3.2), Vector3(1.3, 0.02, 0.14), Color(0.95, 0.9, 0.6), Vector3(0, -a + PI / 2.0, 0))
	for k in 4:
		var a := 0.6 + k * 1.5
		Places.add_spot(ring + Vector3(cos(a) * 4.2, 0, sin(a) * 4.2), Kit.face(Vector3(-cos(a), 0, -sin(a))), [Kit.CLAP, Kit.STAND, Kit.TALK], "preso", room)
	# The hook somebody left in the back wall, and the man who can get you things.
	_glow(Vector3(16.0, 5.2, 130.3), Vector3(0.3, 0.3, 0.3), Color(0.6, 0.4, 0.2))
	Places.add_use(&"climb", Vector3(16.0, 0, 129.4), "the hook in the wall", 0, 3.0, inside)
	Places.add_spot(Vector3(-6.0, 0, 128.6), Kit.face(Vector3.FORWARD), [Kit.LEAN, Kit.LEAN, Kit.SQUAT], "preso", room)
	_sign("CONTRABANDO  [F]", Vector3(-6.0, 2.4, 129.9), 60, Color(0.9, 0.9, 0.9), PI)
	for k in 9:
		Places.add_spot(Vector3(-6.0 + _rng.randf_range(0.0, 28.0), 0, 113.0 + _rng.randf_range(0.0, 16.0)), _rng.randf() * TAU, [Kit.STAND, Kit.TALK, Kit.SQUAT, Kit.LEAN], "preso", room)
	for at in [Vector3(-7.5, 0, 123.0), Vector3(23.5, 0, 121.0), Vector3(10.0, 0, 129.6)]:
		Places.add_spot(at, _rng.randf() * TAU, [Kit.STAND, Kit.STAND, Kit.LEAN], "guarda", room)

	# Canteen and workshop.
	_block(Vector3(38.5, 0.55, 116.3), Vector3(0.8, 1.1, 5.0), STEEL.darkened(0.3))
	Places.add_spot(Vector3(39.6, 0, 116.3), Kit.face(Vector3.LEFT), [Kit.STAND, Kit.WORK], "preso", room)
	Places.add_use(&"meal", Vector3(37.4, 0, 116.3), "queue for a meal", 0, 0.0, inside)
	for k in 3:
		_table(Vector3(28.5 + k * 3.2, 0, 114.2 + (k % 2) * 3.6), room, 4, STEEL)
	for k in 4:
		var at := Vector3(28.0 + k * 3.4, 0, 129.2)
		_block(at + Vector3(0, 0.45, 0), Vector3(2.2, 0.9, 0.9), WOOD)
		_box(at + Vector3(0.3, 1.0, 0), Vector3(0.5, 0.2, 0.3), STEEL)
		Places.add_use(&"work", at + Vector3(0, 0, -1.2), "do a shift at the bench", k, 5.0, inside)
		if k % 2 == 1:
			Places.add_spot(at + Vector3(0.9, 0, -1.1), Kit.face(Vector3.BACK), [Kit.WORK, Kit.WORK, Kit.STAND], "preso", room)

	var lamps := Node3D.new()
	add_child(lamps)
	for at in [Vector3(-33, 5.5, 121), Vector3(-16, 5.5, 116), Vector3(-16, 5.5, 126), Vector3(33, 5.5, 116), Vector3(33, 5.5, 126)]:
		var l := OmniLight3D.new()
		l.position = at
		l.omni_range = 14.0
		l.light_energy = 1.5
		l.light_color = Color(0.95, 0.95, 1.0)
		l.shadow_enabled = false
		lamps.add_child(l)
	_lights.append([room, lamps])
