extends Node3D
## What people get up to when nobody is bothering them: eating at a kiosk table, standing
## about talking, queueing, taking selfies, digging holes, keeping a ball up, a capoeira roda,
## a barbecue on the back street, a gang holding up a corner.
##
## Like the rest of the ambient crowd this costs no bandwidth. plan() lays the groups out from
## the match seed, and what each member is doing at any moment is a function of the clock:
## time is cut into segments per group, and a hash of (group, segment) decides who is talking,
## who has the ball, who is on their phone. Every peer works out the same thing.
##
## A child of the crowd, which owns the people; this only tells them how to stand.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")

enum { NONE, CHAT, DINE, QUEUE, SELFIE, DIG, ALTINHA, FRESCOBOL, CAPOEIRA, CHURRASCO, GANG, ROOM }

const BALL_R := 0.2
## Seconds one touch of the ball takes to reach the next player.
const ALTINHA_BEAT := 0.9
const FRESCOBOL_BEAT := 0.55
const PIT_R := 1.25
const PIT_DEPTH := 1.1

## {kind, pos, seed, first, n, period, off, seg, speaker, ball}. `first` is the crowd index
## of member 0; members are consecutive. `speaker` is the member talking now, or -1.
var groups: Array = []
## Corner gangs, as indices into `groups`, for whoever runs the muggings.
var gangs: PackedInt32Array = []

var _crowd: Node3D
var _balls: MultiMesh
var _ball_groups: PackedInt32Array = []
var _rng := RandomNumberGenerator.new()
var _specs: Array = []


## A repeatable number in 0..1 for (a, b).
static func h01(a: int, b: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 15)) * 0x2c1b3c6d
	x = (x ^ (x >> 12)) * 0x297a2d39
	x = x ^ (x >> 15)
	return float(x & 0xFFFFFF) / 16777216.0


## Lays out every group for this match. Returns one spot per member, in order, in the form
## the crowd's own spot picker uses, with `grp` and `slot` added.
func plan(seed_value: int, crowd: Node3D) -> Array:
	_crowd = crowd
	_rng.seed = seed_value ^ 0x5EED
	groups.clear()
	gangs.clear()
	_specs.clear()
	_ball_groups.clear()
	Places.pits.clear()
	_plan_tables()
	_plan_queues()
	_plan_chats()
	_plan_selfies()
	_plan_pits()
	_plan_ball_games()
	_plan_roda()
	_plan_churrascos()
	_plan_gangs()
	_plan_spots()
	_build_props()
	return _specs


func _group(kind: int, pos: Vector3, period: float) -> Dictionary:
	var g := {"kind": kind, "pos": pos, "seed": _rng.randi() & 0xFFFFF, "first": _specs.size(), "n": 0,
			"period": period, "off": _rng.randf() * period, "seg": -1, "speaker": -1, "ball": -1}
	groups.append(g)
	return g


func _member(g: Dictionary, p: Vector3, yaw: float, idle: int, arch := "", look := 0, sit := false) -> void:
	var spec := {"p": p, "walk": 0.0, "dir": Vector3.RIGHT, "far": 1.0, "yaw": yaw, "idle": idle,
			"grp": groups.size() - 1, "slot": g.n, "look": look, "sit": sit}
	if arch != "":
		spec["arch"] = arch
	_specs.append(spec)
	g.n += 1


## A ring of n people round `c` looking in at it.
func _ring(g: Dictionary, c: Vector3, n: int, r: float, idle: int, arch := "", look := 0) -> void:
	var a0 := _rng.randf() * TAU
	for k in n:
		var a := a0 + TAU * k / n + _rng.randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0, sin(a))
		_member(g, c + d * r, Kit.face(-d), idle, arch, look)


func _sand_spot(z_lo: float, z_hi: float, margin: float) -> Vector3:
	var p := Vector3.ZERO
	for tries in 12:
		p = Vector3(_rng.randf_range(-285.0, 285.0), 0.0, _rng.randf_range(z_lo, z_hi))
		if not Layout.on_play_area(p, margin) and DB.clear_of_solids(p, margin) == p:
			break
	return p


# --- planning, one kind at a time ---

## People at the tables the world put out: a table needs company to be worth sitting at.
func _plan_tables() -> void:
	var by_table := {}
	for s in Places.seats:
		if not by_table.has(s.table):
			by_table[s.table] = []
		by_table[s.table].append(s)
	for t in by_table:
		var seats: Array = by_table[t]
		var taken: Array = []
		for s in seats:
			if _rng.randf() < 0.62:
				taken.append(s)
		if taken.size() < 2 and not (taken.size() == 1 and taken[0].get("solo", false)):
			continue
		var c := Vector3.ZERO
		for s in taken:
			c += s.pos
		var g := _group(DINE, c / taken.size(), _rng.randf_range(4.0, 7.0))
		var arch := "tourist" if _rng.randf() < 0.55 else "local"
		for s in taken:
			_member(g, s.pos, s.yaw, Kit.SIT, arch, 0, true)


func _plan_queues() -> void:
	for v in DB.VENDORS:
		if v.kind != "shop" or v.pos.z > Layout.ROAD_Z or _rng.randf() < 0.35:
			continue
		var g := _group(QUEUE, v.pos + Vector3(1.5, 0, 0), 6.0)
		for k in _rng.randi_range(2, 4):
			_member(g, v.pos + Vector3(1.5 + _rng.randf_range(-0.1, 0.1), 0, 0.3 - k * 0.85), Kit.face(Vector3.BACK), Kit.STAND)


func _plan_chats() -> void:
	for k in 46:
		var roll := _rng.randf()
		var x := _rng.randf_range(-288.0, 288.0)
		var c: Vector3
		if roll < 0.4:
			c = DB.clear_of_solids(Vector3(x, 0, _rng.randf_range(42.5, 49.0)), 1.2)
		elif roll < 0.55:
			c = Vector3(x, 0, _rng.randf_range(71.0, 72.0))
		elif roll < 0.75:
			c = Vector3(x, 0, _rng.randf_range(102.5, 107.0))
		else:
			c = _sand_spot(-28.0, 34.0, 2.0)
		var g := _group(CHAT, c, _rng.randf_range(2.6, 4.6))
		_ring(g, c, _rng.randi_range(2, 4), _rng.randf_range(0.65, 0.9), Kit.TALK)


## Tourists at the sea wall, backs to the view.
func _plan_selfies() -> void:
	for k in 12:
		var c := Vector3(_rng.randf_range(-280.0, 280.0), 0, 41.0)
		var g := _group(SELFIE, c, _rng.randf_range(3.0, 5.0))
		for s in _rng.randi_range(2, 3):
			_member(g, c + Vector3(s * 0.55, 0, 0.1 * (s % 2)), Kit.face(Vector3.BACK), Kit.SELFIE if s == 0 else Kit.STAND, "tourist")


## Somebody's dad digging to Japan. The hole is real enough to fall into.
func _plan_pits() -> void:
	for k in 9:
		var c := _sand_spot(-20.0, 26.0, 3.5)
		Places.pits.append({"pos": c, "r": PIT_R, "depth": PIT_DEPTH})
		var g := _group(DIG, c, _rng.randf_range(7.0, 11.0))
		_ring(g, c, _rng.randi_range(1, 3), PIT_R + 0.55, Kit.DIG, "", Kit.F_SHIRTLESS if _rng.randf() < 0.5 else 0)


func _plan_ball_games() -> void:
	for k in 9:
		var c := _sand_spot(-33.0, -23.0, 3.5)
		var g := _group(ALTINHA, c, ALTINHA_BEAT)
		g.ball = _ball_groups.size()
		_ball_groups.append(groups.size() - 1)
		_ring(g, c, _rng.randi_range(3, 5), _rng.randf_range(2.0, 2.6), Kit.KEEPUP, "local", Kit.F_SHIRTLESS if _rng.randf() < 0.6 else 0)
	for k in 6:
		var c := _sand_spot(-34.0, -27.0, 4.5)
		var g := _group(FRESCOBOL, c, FRESCOBOL_BEAT)
		g.ball = _ball_groups.size()
		_ball_groups.append(groups.size() - 1)
		for side in [-1.0, 1.0]:
			_member(g, c + Vector3(side * 3.4, 0, 0), Kit.face(Vector3(-side, 0, 0)), Kit.STAND, "local", Kit.F_SHIRTLESS)


## One capoeira roda on the sand: two in the middle, the rest clapping time.
func _plan_roda() -> void:
	var c := Vector3([-128.0, 62.0, 148.0][_rng.randi() % 3], 0, 22.0)
	var g := _group(CAPOEIRA, c, 1e9)
	for side in [-1.0, 1.0]:
		_member(g, c + Vector3(side * 0.9, 0, 0), Kit.face(Vector3(-side, 0, 0)), Kit.GINGA, "local", Kit.F_SHIRTLESS)
	_ring(g, c, 9, 3.3, Kit.CLAP, "local")


func _plan_churrascos() -> void:
	for k in 5:
		var x := -250.0 + k * 118.0 + _rng.randf_range(-20.0, 20.0)
		var c := Vector3(x, 0, 107.6)
		var g := _group(CHURRASCO, c, _rng.randf_range(4.0, 6.0))
		g["grill"] = c + Vector3(0, 0, 1.3)
		_ring(g, c, _rng.randi_range(4, 6), 1.5, Kit.EAT, "local")


## The lads on the corner. Three corners out of six, different every match, and you can see
## them from down the street, so there is always another way round.
func _plan_gangs() -> void:
	var corners: Array = []
	for cx in Layout.CROSS_X:
		corners.append(Vector3(cx + (6.5 if _rng.randf() < 0.5 else -6.5), 0, 100.8))
	for k in corners.size():
		var j := _rng.randi_range(k, corners.size() - 1)
		var tmp = corners[k]
		corners[k] = corners[j]
		corners[j] = tmp
	for k in 3:
		var c: Vector3 = corners[k]
		var g := _group(GANG, c, _rng.randf_range(6.0, 9.0))
		gangs.append(groups.size() - 1)
		for s in _rng.randi_range(4, 5):
			# Strung out along the wall, backs to it.
			_member(g, c + Vector3((s - 2) * 1.1 + _rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.9, 0.3) if s % 2 == 1 else -1.2), Kit.face(Vector3.BACK), Kit.LEAN, "malandro")


## Whoever the world wanted standing somewhere in particular: bar staff, croupiers, punters
## at the machines, the men on the door. A handful to a group, so each bunch keeps its own time.
func _plan_spots() -> void:
	var g := {}
	for k in Places.spots.size():
		var s: Dictionary = Places.spots[k]
		if k % 6 == 0:
			g = _group(ROOM, s.pos, _rng.randf_range(4.0, 8.0))
			g["poses"] = []
		g.poses.append(s.poses)
		_member(g, s.pos, s.yaw, s.poses[0], s.arch)


## The things groups need that are not people: balls in the air, holes in the sand, grills.
func _build_props() -> void:
	for c in get_children():
		c.queue_free()
	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.roughness = 0.95

	var ball := SphereMesh.new()
	ball.radius = BALL_R
	ball.height = BALL_R * 2.0
	ball.radial_segments = 10
	ball.rings = 5
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.use_colors = true
	_balls.mesh = ball
	_balls.instance_count = _ball_groups.size()
	for k in _ball_groups.size():
		var small: bool = groups[_ball_groups[k]].kind == FRESCOBOL
		_balls.set_instance_color(k, Color(1.0, 0.85, 0.1) if small else Color(0.97, 0.97, 0.97))
	_add(_balls, flat)

	# A pit is a dark mouth with the spoil heaped round it.
	var hole := CylinderMesh.new()
	hole.top_radius = 1.0
	hole.bottom_radius = 1.0
	hole.height = 0.04
	hole.radial_segments = 16
	hole.rings = 1
	var heap := SphereMesh.new()
	heap.radius = 1.0
	heap.height = 1.1
	heap.radial_segments = 8
	heap.rings = 4
	var holes := MultiMesh.new()
	holes.transform_format = MultiMesh.TRANSFORM_3D
	holes.use_colors = true
	holes.mesh = hole
	holes.instance_count = Places.pits.size() * 2
	var heaps := MultiMesh.new()
	heaps.transform_format = MultiMesh.TRANSFORM_3D
	heaps.use_colors = true
	heaps.mesh = heap
	heaps.instance_count = Places.pits.size() * 7
	for k in Places.pits.size():
		var pit: Dictionary = Places.pits[k]
		var p: Vector3 = pit.pos
		holes.set_instance_transform(k * 2, Transform3D(Basis.from_scale(Vector3(pit.r, 1, pit.r)), p + Vector3(0, 0.03, 0)))
		holes.set_instance_color(k * 2, Color(0.42, 0.33, 0.2))
		holes.set_instance_transform(k * 2 + 1, Transform3D(Basis.from_scale(Vector3(pit.r * 0.78, 1, pit.r * 0.78)), p + Vector3(0, 0.04, 0)))
		holes.set_instance_color(k * 2 + 1, Color(0.12, 0.09, 0.06))
		for j in 7:
			var a := TAU * j / 7.0 + k
			var s := 0.32 + h01(k, j) * 0.25
			heaps.set_instance_transform(k * 7 + j, Transform3D(Basis.from_scale(Vector3(s * 1.5, s, s * 1.5)), p + Vector3(cos(a), 0, sin(a)) * (pit.r + 0.25)))
			heaps.set_instance_color(k * 7 + j, Color(0.8, 0.67, 0.44))
	_add(holes, flat)
	_add(heaps, flat)

	# Half an oil drum on legs, coals glowing.
	var drum := BoxMesh.new()
	var grills: Array = []
	for g in groups:
		if g.has("grill"):
			grills.append(g.grill)
	var gm := MultiMesh.new()
	gm.transform_format = MultiMesh.TRANSFORM_3D
	gm.use_colors = true
	gm.mesh = drum
	gm.instance_count = grills.size() * 2
	for k in grills.size():
		gm.set_instance_transform(k * 2, Transform3D(Basis.from_scale(Vector3(1.1, 0.35, 0.55)), grills[k] + Vector3(0, 0.85, 0)))
		gm.set_instance_color(k * 2, Color(0.12, 0.12, 0.13))
		gm.set_instance_transform(k * 2 + 1, Transform3D(Basis.from_scale(Vector3(0.95, 0.04, 0.42)), grills[k] + Vector3(0, 1.04, 0)))
		gm.set_instance_color(k * 2 + 1, Color(1.0, 0.35, 0.05))
	_add(gm, flat)


func _add(mm: MultiMesh, mat: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = Layout.WORLD_AABB
	add_child(mmi)


# --- the clock ---

## Brings every group up to match time `t`. Called by the crowd each frame.
func tick(t: float) -> void:
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var seg := int(floorf((t + g.off) / g.period))
		if seg != g.seg:
			g.seg = seg
			_restage(g, seg)
	for k in _ball_groups.size():
		_balls.set_instance_transform(k, Transform3D(Basis(), _ball_at(groups[_ball_groups[k]], t)))


## Who has the ball in segment `seg`.
func _holder(g: Dictionary, seg: int) -> int:
	if g.kind == FRESCOBOL:
		return seg & 1
	return int(h01(g.seed, seg) * g.n) % g.n


## Tells each member of g what to be doing in segment `seg`.
func _restage(g: Dictionary, seg: int) -> void:
	var c := _crowd
	g.speaker = -1
	match g.kind:
		CHAT:
			var who: int = int(h01(g.seed, seg) * g.n) % g.n
			var laugh := h01(g.seed + 7, seg) < 0.15
			g.speaker = who
			for s in g.n:
				c.act_pose(g.first + s, Kit.TALK, s == who or laugh)
		DINE:
			for s in g.n:
				var h := h01(g.seed + s * 31, seg)
				if h < 0.3:
					c.act_pose(g.first + s, Kit.SIT_DRINK, false)
				elif h < 0.55:
					c.act_pose(g.first + s, Kit.SIT_TALK, true)
					g.speaker = s
				elif h < 0.7:
					c.act_pose(g.first + s, Kit.SIT_PHONE, false)
				else:
					c.act_pose(g.first + s, Kit.SIT_TALK, false)
		QUEUE:
			for s in g.n:
				var h := h01(g.seed + s * 31, seg)
				c.act_pose(g.first + s, Kit.PHONE if h < 0.4 else (Kit.TALK if h < 0.55 else Kit.STAND), h > 0.4 and h < 0.55)
		SELFIE:
			var posing := h01(g.seed, seg) < 0.7
			c.act_pose(g.first, Kit.SELFIE if posing else Kit.PHONE, false)
			for s in range(1, g.n):
				c.act_pose(g.first + s, Kit.TALK if posing else Kit.STAND, posing)
			if not posing:
				g.speaker = 0
		DIG:
			var resting := int(h01(g.seed, seg) * (g.n + 2))
			for s in g.n:
				c.act_pose(g.first + s, Kit.DRINK if s == resting else Kit.DIG, false)
		ALTINHA, FRESCOBOL:
			# Whoever the ball has just reached plays it.
			c.act_event(g.first + _holder(g, seg))
		CHURRASCO:
			for s in g.n:
				var h := h01(g.seed + s * 31, seg)
				c.act_pose(g.first + s, Kit.EAT if h < 0.3 else (Kit.DRINK if h < 0.6 else Kit.TALK), h > 0.8)
				if h > 0.8:
					g.speaker = s
		ROOM:
			for s in g.n:
				var poses: Array = g.poses[s]
				var pose: int = poses[int(h01(g.seed + s * 31, seg) * poses.size()) % poses.size()]
				c.act_pose(g.first + s, pose, pose == Kit.TALK)
				if pose == Kit.TALK:
					g.speaker = s
		GANG:
			for s in g.n:
				var h := h01(g.seed + s * 31, seg)
				var pose := Kit.LEAN if h < 0.4 else (Kit.SQUAT if h < 0.55 else (Kit.PHONE if h < 0.7 else Kit.TALK))
				c.act_pose(g.first + s, pose, h > 0.85)
				if h > 0.85:
					g.speaker = s


## Where a group's ball is at time t: on an arc from whoever played it to whoever is next.
func _ball_at(g: Dictionary, t: float) -> Vector3:
	var u: float = fposmod(t + g.off, g.period) / g.period
	var a: int = g.first + _holder(g, g.seg)
	var b: int = g.first + _holder(g, g.seg + 1)
	if not _crowd.act_free(a) or not _crowd.act_free(b):
		# Game over for now: it lies where it fell.
		return g.pos + Vector3(0, BALL_R, 0)
	var small: bool = g.kind == FRESCOBOL
	var from: Vector3 = _crowd.pos[a] + Vector3(0, 1.0 if small else 0.55, 0)
	var to: Vector3 = _crowd.pos[b] + Vector3(0, 1.0 if small else 0.55, 0)
	var top := 0.5 if small else 1.3 + h01(g.seed, g.seg) * 1.5
	return from.lerp(to, u) + Vector3(0, 4.0 * top * u * (1.0 - u), 0)


## Up to `limit` people talking within r of p, nearest first, as [position, crowd index].
func speakers_near(p: Vector3, r: float, limit: int) -> Array:
	var out: Array = []
	for g in groups:
		if g.speaker < 0 or absf(g.pos.x - p.x) > r or absf(g.pos.z - p.z) > r or absf(g.pos.y - p.y) > 4.0:
			continue
		var i: int = g.first + g.speaker
		if _crowd.act_free(i):
			out.append([_crowd.pos[i], i])
	out.sort_custom(func(a, b): return a[0].distance_squared_to(p) < b[0].distance_squared_to(p))
	if out.size() > limit:
		out.resize(limit)
	return out
