extends Node3D
## The whole beach crowd as packed arrays drawn with MultiMesh — no node per NPC.
##
## Ambient NPCs are a pure function of (match seed, match time), so they cost no
## bandwidth. The server only sends an event when one changes state, plus 10 Hz
## positions for the few that are actively hostile.
##
## Looks and animation come from the shared character kit: each NPC is one instance
## whose pose and props are set here on state changes and played by the shader.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")

enum { AMBIENT, COWER, FLEE, HOSTILE, PARADE, DEAD, GONE }

const COUNT := 2500
const FLEE_SPEED := 5.5
const FLEE_TIME := 10.0
const HOSTILE_SPEED := 4.8
const ROB_RATE := 0.55
const ROB_TICK := 0.1
## Mic level under which a sunbather sleeps on, and how long their bag takes to go through.
const PICK_LOUD := 0.08
const PICK_TIME := 2.5
const BODY_RADIUS := 0.5
const WORLD_AABB := Layout.WORLD_AABB
## cl_npc flag bit: this hostile NPC has a gun out. The low two bits are its wealth tier.
const NPC_SHOOTER := 4
## cl_npc flag bit: a PARADE NPC is dancing along rather than running for cover.
const NPC_DANCE := 8
## cl_npc flag bit: a PARADE NPC is just walking there.
const NPC_STROLL := 16
const STROLL_SPEED := 1.5
const DANCE_SPEED := 1.6
const SHELTER_SPEED := 4.6
const LOCAL_TOPS := [Color(1.0, 0.85, 0.1), Color(0.1, 0.65, 0.3), Color(0.95, 0.95, 0.95), Color(0.3, 0.7, 0.95), Color(0.9, 0.35, 0.2)]

var count := 0
var pos := PackedVector3Array()
var state := PackedByteArray()
var arch := PackedByteArray()
var money := PackedInt32Array()
var hp := PackedFloat32Array()
## NPC indices close to the local player, refreshed at 10 Hz.
var near := PackedInt32Array()

var _home := PackedVector3Array()
var _scale := PackedFloat32Array()
var _width := PackedFloat32Array()
var _lying := PackedByteArray()
var _yaw := PackedFloat32Array()
var _walker := PackedByteArray()
var _walkers := PackedInt32Array()
var _w_dir := PackedVector3Array()
var _w_yaw := PackedFloat32Array()
var _w_len := PackedFloat32Array()
var _w_spd := PackedFloat32Array()
var _w_phase := PackedFloat32Array()
var _leave_t := PackedFloat32Array()
var _leave_order := PackedInt32Array()
var _leave_ptr := 0
var _look := PackedInt32Array()    # Kit clothing flags from the archetype
var _tier := PackedByteArray()     # wealth tier still on show (drops to 0 once robbed)
var _ev := PackedFloat32Array()    # Kit one-shot event time
var _idle := PackedByteArray()     # Kit pose when standing about (dancers, drummers)
var _mm: MultiMesh
var _blood: MultiMesh
var _blood_n := 0
var _active := {}          # idx -> true while FLEE / HOSTILE
var _ov := {}              # idx -> [origin, dir, t0] for FLEE
var _hostile_target := {}  # client: idx -> latest server position
var _shooter := {}         # idx -> true while HOSTILE with a gun
var _moving := {}          # idx -> whether a HOSTILE NPC is currently running
var _dancing := {}         # idx -> how a PARADE NPC is going: 1 dancing, 2 strolling (absent: running)
var _changed := {}         # idx -> last state event, replayed to late joiners

# server only
var _rob := {}      # pid -> {npc, meter, quiet, last}
var _hostile := {}  # idx -> {target, cd, until, shooter}
var _send_t := 0.0


func setup(seed_value: int) -> void:
	for c in get_children():
		c.queue_free()
	_active.clear()
	_ov.clear()
	_hostile_target.clear()
	_shooter.clear()
	_moving.clear()
	_dancing.clear()
	_changed.clear()
	_rob.clear()
	_hostile.clear()
	_walkers.clear()
	near.clear()
	_leave_ptr = 0

	count = COUNT
	pos.resize(count)
	_home.resize(count)
	_w_dir.resize(count)
	_w_yaw.resize(count)
	state.resize(count)
	arch.resize(count)
	_lying.resize(count)
	_walker.resize(count)
	hp.resize(count)
	_scale.resize(count)
	_width.resize(count)
	_yaw.resize(count)
	_w_len.resize(count)
	_w_spd.resize(count)
	_w_phase.resize(count)
	_leave_t.resize(count)
	money.resize(count)
	_look.resize(count)
	_tier.resize(count)
	_ev.resize(count)
	_idle.resize(count)
	_leave_order.resize(count)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tops := PackedColorArray()
	var towels := PackedInt32Array()
	var order: Array = []

	for i in count:
		# Where they spend the day decides a lot about who they are.
		var spot := _spot(rng)
		var roll := rng.randf()
		var ai := 0
		for k in DB.ARCHETYPES.size():
			roll -= DB.ARCHETYPES[k].weight
			if roll <= 0.0:
				ai = k
				break
		if spot.has("arch"):
			ai = _arch_index(spot.arch)
		var a = DB.ARCHETYPES[ai]
		arch[i] = ai
		state[i] = AMBIENT
		hp[i] = a.hp
		money[i] = rng.randi_range(a.money[0], a.money[1])
		_tier[i] = DB.wealth_tier(money[i])
		_ev[i] = 0.0
		_scale[i] = a.scale * rng.randf_range(0.92, 1.08)
		_width[i] = _scale[i] * a.width / a.scale
		_yaw[i] = spot.get("yaw", rng.randf() * TAU)
		_idle[i] = spot.get("idle", Kit.STAND)

		var p: Vector3 = spot.p
		var on_sand := p.z < Layout.PROM_Z
		var walker: bool = rng.randf() < spot.walk
		_home[i] = p
		_lying[i] = 1 if (not walker and on_sand and a.id != "mafia" and not spot.has("idle") and rng.randf() < 0.45) else 0
		_w_dir[i] = spot.dir
		_w_yaw[i] = Kit.face(_w_dir[i])
		var far: float = spot.far
		_w_len[i] = rng.randf_range(minf(15.0, far), far)
		_w_spd[i] = spot.get("speed", rng.randf_range(0.9, 1.7))
		_w_phase[i] = rng.randf() * 140.0
		_walker[i] = 1 if walker else 0
		if walker:
			_walkers.append(i)
		if _lying[i] == 1:
			towels.append(i)

		# A few stragglers never leave; everyone else drains out over the match.
		var stays := rng.randf() < (0.04 if p.z < Layout.WALK_Z else 0.6)
		_leave_t[i] = INF if stays else MatchState.duration * lerpf(0.1, 0.82, pow(rng.randf(), 0.8))
		order.append([_leave_t[i], i])

		# Outfit: the archetype should be readable from the silhouette and colours alone.
		var top: Color
		var look := 0
		match a.id:
			"tourist":
				top = Color.from_hsv(rng.randf(), 0.8, 0.95)
				look = Kit.F_SHORTS
				if rng.randf() < 0.6:
					look |= Kit.F_HAT
				if rng.randf() < 0.45:
					look |= Kit.F_CAMERA
				if rng.randf() < 0.55:
					look |= Kit.F_SUNBURN
			"local":
				top = LOCAL_TOPS[rng.randi() % LOCAL_TOPS.size()]
				look = Kit.F_SHORTS | Kit.F_TANK
			"vendor":
				top = Color(0.98, 0.98, 0.95)
				look = Kit.F_SHORTS | Kit.F_HAT | Kit.F_CARRY
			"traficante":
				top = Color(0.1, 0.1, 0.1)
				look = Kit.F_SHORTS | Kit.F_SHIRTLESS | Kit.F_SHADES | Kit.F_CHAIN | Kit.F_GUN
			_:
				top = Color(0.09, 0.09, 0.11) if rng.randf() < 0.7 else Color(0.95, 0.95, 0.95)
				look = Kit.F_SUIT | Kit.F_SHADES
		if _lying[i] == 1 and rng.randf() < 0.5:
			look |= Kit.F_SHADES
		top.a = rng.randf()
		tops.append(top)
		_look[i] = look | spot.get("look", 0)

	order.sort_custom(func(x, y): return x[0] < y[0])
	for k in count:
		_leave_order[k] = order[k][1]

	_build_meshes(tops, towels)
	for i in count:
		_place(i, _home[i])
		_restyle(i)


func _arch_index(id: String) -> int:
	for k in DB.ARCHETYPES.size():
		if DB.ARCHETYPES[k].id == id:
			return k
	return 0


## Picks where an NPC lives and what they do there: p (home), walk (chance of pacing up
## and down), dir and far (which way and how far), and optionally speed, arch, idle (the
## pose they stand in), look (extra clothing flags) and yaw.
func _spot(rng: RandomNumberGenerator) -> Dictionary:
	var x := rng.randf_range(-292.0, 292.0)
	var along := Vector3.RIGHT
	var roll := rng.randf()
	if roll < 0.52:
		var p := Vector3(x, 0.0, rng.randf_range(-36.0, 37.0))
		if Layout.on_play_area(p, 1.0):
			p.z = rng.randf_range(-36.0, -28.0)
		# Nobody sets up their towel inside a hut.
		return {"p": DB.clear_of_solids(p, 0.5), "walk": 0.3, "dir": Vector3(1.0, 0.0, rng.randf_range(-0.25, 0.25)).normalized(), "far": 70.0}
	if roll < 0.56:
		# Ambulantes working the sand with a cooler of mate and biscoito.
		return {"p": DB.clear_of_solids(Vector3(x, 0.0, rng.randf_range(-30.0, 30.0)), 0.5), "walk": 1.0, "dir": Vector3(1.0, 0.0, rng.randf_range(-0.2, 0.2)).normalized(), "far": 90.0, "arch": "vendor"}
	if roll < 0.6:
		# A kickabout: both sides chasing up and down a pitch.
		var rect: Array = Layout.PITCHES[rng.randi() % Layout.PITCHES.size()]
		var c: Vector3 = rect[0]
		var h: Vector2 = rect[1]
		var run := rng.randf_range(6.0, 14.0)
		var p := c + Vector3(rng.randf_range(-1.0, 1.0) * (h.x - run * 0.5 - 1.0), 0.0, rng.randf_range(-1.0, 1.0) * (h.y - 2.5))
		return {"p": p, "walk": 1.0, "dir": Vector3(1.0, 0.0, rng.randf_range(-0.3, 0.3)).normalized(), "far": run, "speed": rng.randf_range(2.8, 4.5), "arch": "local", "look": Kit.F_SHIRTLESS if rng.randf() < 0.5 else 0}
	if roll < 0.615:
		# Futevolei: two a side, facing the net.
		var rect: Array = Layout.COURTS[rng.randi() % Layout.COURTS.size()]
		var c: Vector3 = rect[0]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		return {"p": c + Vector3(side * rng.randf_range(2.0, 6.5), 0.0, rng.randf_range(-3.0, 3.0)), "walk": 0.0, "dir": along, "far": 1.0, "arch": "local", "yaw": Kit.face(Vector3(-side, 0, 0)), "idle": Kit.STAND, "look": Kit.F_SHIRTLESS}
	if roll < 0.78:
		return {"p": DB.clear_of_solids(Vector3(x, 0.0, rng.randf_range(41.5, 50.0)), 0.5), "walk": 0.8, "dir": along, "far": 70.0}
	if roll < 0.795:
		# Roda de samba on the calçadão: a ring of drummers and the people dancing to them.
		var c: Vector3 = DB.RODAS[rng.randi() % DB.RODAS.size()]
		var a := rng.randf() * TAU
		var drummer := rng.randf() < 0.4
		var r := 2.2 if drummer else rng.randf_range(3.2, 5.0)
		return {"p": c + Vector3(cos(a) * r, 0.0, sin(a) * r * 0.7), "walk": 0.0, "dir": along, "far": 1.0, "arch": "local", "yaw": Kit.face(Vector3(-cos(a), 0, -sin(a))), "idle": Kit.DRUM if drummer else Kit.DANCE, "look": Kit.F_CARRY if drummer else 0}
	if roll < 0.845:
		return {"p": Vector3(x, 0.0, rng.randf_range(70.6, 72.4)), "walk": 0.85, "dir": along, "far": 60.0}
	if roll < 0.915:
		return {"p": Vector3(x, 0.0, rng.randf_range(103.5, 107.5)), "walk": 0.6, "dir": along, "far": 50.0}
	if roll < 0.94:
		var cx: float = Layout.CROSS_X[rng.randi() % Layout.CROSS_X.size()]
		return {"p": Vector3(cx + rng.randf_range(-3.0, 3.0), 0.0, 86.0), "walk": 0.8, "dir": Vector3.BACK, "far": 20.0}
	if roll < 0.955:
		# The baile: everyone on the terrace is dancing.
		var c := DB.BAILE_POS
		return {"p": c + Vector3(rng.randf_range(-9.0, 9.0), 0.0, rng.randf_range(-3.0, 1.2)), "walk": 0.0, "dir": along, "far": 1.0, "arch": "local", "idle": Kit.DANCE, "yaw": Kit.face(Vector3(rng.randf_range(-0.5, 0.5), 0, 1))}
	if roll < 0.963:
		# The boca's soldiers.
		var boca: Vector3 = DB.BOCA_POS
		return {"p": Vector3(boca.x + rng.randf_range(-9.0, 9.0), boca.y - 0.2, boca.z + rng.randf_range(-1.4, 0.6)), "walk": 0.0, "dir": along, "far": 1.0, "arch": "traficante", "yaw": Kit.face(Vector3.FORWARD)}
	# Up in the favela, out on the walkway in front of the houses.
	var t := rng.randi() % Layout.TERRACES
	var z := Layout.FAVELA_Z + t * Layout.TERRACE_D + rng.randf_range(0.6, Layout.BECO - 0.5)
	return {"p": Vector3(x, (t + 1) * Layout.TERRACE_H, z), "walk": 0.35, "dir": along, "far": 30.0}


func _build_meshes(tops: PackedColorArray, towels: PackedInt32Array) -> void:
	_mm = Kit.add_to(self, count, WORLD_AABB)
	for i in count:
		_mm.set_instance_color(i, tops[i])

	var flat := StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.roughness = 0.95

	# Sunbathers lie on a towel, which is what tells them apart from a body.
	var towel := BoxMesh.new()
	towel.size = Vector3(0.9, 0.03, 2.05)
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.mesh = towel
	tmm.instance_count = towels.size()
	for k in towels.size():
		var i := towels[k]
		tmm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, _yaw[i]), _home[i] + Vector3(0, 0.015, 0)))
		tmm.set_instance_color(k, Color.from_hsv(fmod(tops[i].a * 7.0, 1.0), 0.55, 0.95))
	_add_mmi(tmm, flat)

	var pool := CylinderMesh.new()
	pool.top_radius = 0.75
	pool.bottom_radius = 0.75
	pool.height = 0.02
	pool.radial_segments = 14
	pool.rings = 1
	_blood = MultiMesh.new()
	_blood.transform_format = MultiMesh.TRANSFORM_3D
	_blood.mesh = pool
	_blood.instance_count = count
	for i in count:
		_blood.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
	_blood_n = 0
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.02, 0.02)
	red.roughness = 1.0
	_add_mmi(_blood, red)


func _add_mmi(mm: MultiMesh, mat: Material) -> void:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	# Instances move across the whole beach; skip per-frame AABB bookkeeping.
	mmi.custom_aabb = WORLD_AABB
	add_child(mmi)


func _place(i: int, p: Vector3) -> void:
	pos[i] = p
	_mm.set_instance_transform(i, Kit.xform(p, _yaw[i], _width[i], _scale[i]))


func _hide(i: int) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))


## Pushes NPC i's pose and props to the shader. Call after anything that changes how it looks.
func _restyle(i: int) -> void:
	var pose := Kit.STAND
	var speed := 0.0
	var flags: int = _look[i] | Kit.TIER_PROPS[_tier[i]]
	match state[i]:
		AMBIENT:
			if _lying[i] == 1:
				pose = Kit.SUNBATHE
			elif _walker[i] == 1:
				pose = Kit.RUN if _w_spd[i] > 2.5 else Kit.WALK
				speed = _w_spd[i]
			else:
				pose = _idle[i]
		COWER:
			pose = Kit.COWER
		FLEE:
			pose = Kit.FLEE
			speed = FLEE_SPEED
		PARADE:
			pose = [Kit.FLEE, Kit.DANCE, Kit.WALK][_dancing.get(i, 0)]
			speed = _parade_speed(i)
		HOSTILE:
			pose = Kit.AIM if _shooter.has(i) else Kit.FIGHT
			speed = HOSTILE_SPEED if _moving.get(i, false) else 0.0
			flags |= Kit.F_ANGRY
			if _shooter.has(i):
				flags |= Kit.F_GUN
		DEAD:
			pose = Kit.DEAD
			flags = _look[i]
	_mm.set_instance_custom_data(i, Kit.custom(pose, speed, flags, _ev[i]))


## Plays a punch / recoil (attack) or a flinch on NPC i.
func fx_event(i: int, attack: bool) -> void:
	if i < 0 or i >= count or state[i] >= DEAD:
		return
	_ev[i] = Kit.now() if attack else -Kit.now()
	_restyle(i)


func alive_count() -> int:
	var n := 0
	for i in count:
		if state[i] < DEAD:
			n += 1
	return n


func _process(delta: float) -> void:
	if count == 0:
		return
	var t := MatchState.time

	# Thin-out: NPCs leave in a seeded order as the clock runs.
	while _leave_ptr < count and _leave_t[_leave_order[_leave_ptr]] <= t:
		var i := _leave_order[_leave_ptr]
		_leave_ptr += 1
		if state[i] == AMBIENT:
			state[i] = GONE
			_hide(i)

	for i in _walkers:
		if state[i] != AMBIENT or _walker[i] == 0:
			continue
		var length := _w_len[i]
		var u := fposmod(t * _w_spd[i] + _w_phase[i], 2.0 * length)
		var out := u < length
		_yaw[i] = _w_yaw[i] if out else _w_yaw[i] + PI
		_place(i, _home[i] + _w_dir[i] * ((u if out else 2.0 * length - u) - length * 0.5))

	var server := multiplayer.is_server()
	for i in _active.keys():
		if state[i] == FLEE:
			var e = _ov[i]
			var dt: float = t - e[2]
			if dt > FLEE_TIME or dt * FLEE_SPEED > e[3]:
				state[i] = GONE
				_active.erase(i)
				_hide(i)
			else:
				_place(i, e[0] + e[1] * FLEE_SPEED * dt)
		elif state[i] == PARADE:
			# Marching somewhere together; whoever gets there stays there.
			var e = _ov[i]
			var far: float = e[3]
			var d: float = minf((t - e[2]) * _parade_speed(i), far)
			_place(i, e[0] + e[1] * d)
			if d >= far:
				state[i] = AMBIENT
				_home[i] = pos[i]
				_walker[i] = 0
				_lying[i] = 0
				_idle[i] = Kit.DANCE if _dancing.get(i, 0) == 1 else Kit.STAND
				_active.erase(i)
				_restyle(i)
		elif state[i] == HOSTILE:
			if server:
				_srv_hostile(i, delta)
			elif _hostile_target.has(i):
				_hostile_step(i, pos[i].lerp(_hostile_target[i], minf(1.0, 10.0 * delta)), delta)

	if server:
		for pid in _rob.keys():
			_rob[pid].last += delta
			if _rob[pid].last > 0.8:
				_srv_rob_abort(pid)
		_send_t -= delta
		if _send_t <= 0.0 and not _hostile.is_empty():
			_send_t = 0.1
			var idx := PackedInt32Array()
			var ps := PackedVector3Array()
			for i in _hostile:
				idx.append(i)
				ps.append(pos[i])
			Net.game.bcast("cl_npc_pos", [idx, ps], self)


## Moves a hostile NPC to p. It faces where it is running, or the nearest player once it
## has closed in, and swaps between its running and planted stance.
func _hostile_step(i: int, p: Vector3, delta: float) -> void:
	var look := p - pos[i]
	look.y = 0.0
	var moving := look.length() > 1.5 * delta
	if not moving:
		look = _nearest_player(p) - p
		look.y = 0.0
	if look.length_squared() > 0.0001:
		_yaw[i] = lerp_angle(_yaw[i], Kit.face(look), minf(1.0, 12.0 * delta))
	if moving != _moving.get(i, false):
		_moving[i] = moving
		_restyle(i)
	_place(i, p)


func _nearest_player(p: Vector3) -> Vector3:
	var best := p
	var best_d := INF
	for pid in Net.game.players:
		var pl = Net.game.players[pid]
		var d: float = pl.global_position.distance_squared_to(p)
		if d < best_d and not pl.st.dead:
			best = pl.global_position
			best_d = d
	return best


# --- queries ---

func refresh_near(p: Vector3) -> void:
	near.clear()
	for i in count:
		if state[i] < DEAD and absf(pos[i].x - p.x) < 7.0 and absf(pos[i].z - p.z) < 7.0:
			near.append(i)


## Nearest NPC along the ray among those close to the local player, or -1.
func pick_near(o: Vector3, d: Vector3, max_t: float) -> int:
	var best := -1
	var best_t := max_t
	for i in near:
		if state[i] >= DEAD:
			continue
		var t := DB.ray_point(o, d, pos[i] + Vector3(0, 0.3 if is_lying(i) else 0.9, 0), BODY_RADIUS, best_t)
		if t >= 0.0:
			best = i
			best_t = t
	return best


## Flat out on a towel, eyes shut: someone whose bag can be gone through.
func is_lying(i: int) -> bool:
	return _lying[i] == 1 and state[i] == AMBIENT


## Full-crowd ray test (server). Returns [index, distance]; index -1 on a miss.
func ray_pick(o: Vector3, d: Vector3, max_t: float, radius: float) -> Array:
	var best := -1
	var best_t := max_t
	for i in count:
		if state[i] >= DEAD:
			continue
		var c := pos[i]
		if absf(c.x - o.x) > best_t or absf(c.z - o.z) > best_t:
			continue
		var t := DB.ray_point(o, d, c + Vector3(0, 0.9, 0), radius, best_t)
		if t >= 0.0:
			best = i
			best_t = t
	return [best, best_t]


## People on their feet within r of p: how much of a crowd someone there is standing in.
func count_near(p: Vector3, r: float) -> int:
	var n := 0
	for i in count:
		if state[i] >= DEAD or (_lying[i] == 1 and state[i] == AMBIENT) or absf(pos[i].y - p.y) > 2.5:
			continue
		var dx := pos[i].x - p.x
		var dz := pos[i].z - p.z
		if absf(dx) < r and absf(dz) < r and dx * dx + dz * dz < r * r:
			n += 1
	return n


## People on their feet standing within w of the line from a to b, not counting its two ends.
func count_on_segment(a: Vector3, b: Vector3, w: float) -> int:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var len2 := ab.length_squared()
	if len2 < 1.0:
		return 0
	var lo_x := minf(a.x, b.x) - w
	var hi_x := maxf(a.x, b.x) + w
	var lo_z := minf(a.z, b.z) - w
	var hi_z := maxf(a.z, b.z) + w
	var n := 0
	for i in count:
		var c := pos[i]
		if c.x < lo_x or c.x > hi_x or c.z < lo_z or c.z > hi_z:
			continue
		if state[i] >= DEAD or (_lying[i] == 1 and state[i] == AMBIENT):
			continue
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var t := ac.dot(ab) / len2
		if t > 0.05 and t < 0.95 and (ac - ab * t).length_squared() < w * w:
			n += 1
	return n


## Velocity that nudges the local player out of nearby bodies.
func push_out(p: Vector3) -> Vector3:
	var out := Vector3.ZERO
	for i in near:
		if state[i] >= DEAD or (_lying[i] == 1 and state[i] == AMBIENT):
			continue
		var v := p - pos[i]
		var d := Vector2(v.x, v.z).length()
		if absf(v.y) < 1.2 and d < 0.7 and d > 0.01:
			v.y = 0.0
			out += v / d * (0.7 - d) * 8.0
	return out


# --- replication ---

@rpc("authority", "call_remote", "reliable")
func cl_npc(i: int, s: int, p: Vector3, dir: Vector3, t0: float, flags: int) -> void:
	if i < 0 or i >= count:
		return
	state[i] = s
	_changed[i] = [i, s, p, dir, t0, flags]
	_active.erase(i)
	_hostile_target.erase(i)
	_moving.erase(i)
	_tier[i] = flags & 3
	if flags & NPC_SHOOTER:
		_shooter[i] = true
	else:
		_shooter.erase(i)
	_dancing.erase(i)
	match s:
		COWER:
			var threat := _nearest_player(p) - p
			if threat.length_squared() > 0.0001:
				_yaw[i] = Kit.face(threat)
			_place(i, p)
		FLEE:
			_ov[i] = [p, dir, t0, Layout.run_dist(p, dir, FLEE_SPEED * FLEE_TIME)]
			_active[i] = true
			_yaw[i] = Kit.face(dir)
		PARADE:
			_begin_parade(i, p, dir, t0, 1 if flags & NPC_DANCE else (2 if flags & NPC_STROLL else 0))
		HOSTILE:
			_place(i, p)
			_active[i] = true
			_hostile_target[i] = p
		DEAD:
			_ev[i] = Kit.now()
			_place(i, p)
			# The body tips forward, so the pool goes under where the chest lands.
			var chest := p + Basis(Vector3.UP, _yaw[i]) * Vector3(0, 0.012, -1.0 * _scale[i])
			_blood.set_instance_transform(_blood_n % count, Transform3D(Basis(), chest))
			_blood_n += 1
		GONE:
			_hide(i)
	if s != GONE:
		_restyle(i)


## `dir` carries both the heading and, in its length, how far to go.
func _parade_speed(i: int) -> float:
	return [SHELTER_SPEED, DANCE_SPEED, STROLL_SPEED][_dancing.get(i, 0)]


func _begin_parade(i: int, p: Vector3, dir: Vector3, t0: float, mode: int) -> void:
	state[i] = PARADE
	_ov[i] = [p, dir.normalized(), t0, dir.length()]
	_active[i] = true
	_lying[i] = 0
	_yaw[i] = Kit.face(dir)
	if mode > 0:
		_dancing[i] = mode
	else:
		_dancing.erase(i)
	_place(i, p)
	_restyle(i)


## The heavens opened at match time t0: most people out on the open sand run for the
## promenade. Every peer works this out for itself from the same crowd, so it is one message.
@rpc("authority", "call_remote", "reliable")
func cl_shelter(t0: float) -> void:
	for i in count:
		if state[i] != AMBIENT or _walker[i] == 1 or pos[i].y > 1.0 or pos[i].z > 38.0 or (i * 7919) % 100 >= 65:
			continue
		var to_z := 42.0 + (i * 31) % 80 * 0.1
		_begin_parade(i, pos[i], Vector3(((i * 13) % 9 - 4) * 0.6, 0.0, to_z - pos[i].z), t0, 0)


@rpc("authority", "call_remote", "unreliable")
func cl_npc_pos(idx: PackedInt32Array, ps: PackedVector3Array) -> void:
	for k in mini(idx.size(), ps.size()):
		if idx[k] >= 0 and idx[k] < count and state[idx[k]] == HOSTILE:
			_hostile_target[idx[k]] = ps[k]


func snapshot() -> Array:
	return _changed.values()


func apply_snapshot(snap: Array) -> void:
	for e in snap:
		cl_npc(e[0], e[1], e[2], e[3], e[4], e[5])
		if e[1] == DEAD:
			# Died before we joined: already on the ground, not falling over now.
			_ev[e[0]] = Kit.now() - 5.0
			_restyle(e[0])


# --- server: state changes ---

func _srv_set(i: int, s: int, dir := Vector3.ZERO) -> void:
	var flags := DB.wealth_tier(money[i])
	if _hostile.has(i) and _hostile[i].shooter:
		flags |= NPC_SHOOTER
	Net.game.bcast("cl_npc", [i, s, pos[i], dir, MatchState.time, flags], self)


## Sends NPC i `dist` along `dir`: running for shelter (mode 0), dancing with a bloco (1)
## or just walking (2).
func srv_parade(i: int, dir: Vector3, dist: float, mode: int) -> void:
	_hostile.erase(i)
	var flags: int = DB.wealth_tier(money[i]) | [0, NPC_DANCE, NPC_STROLL][mode]
	Net.game.bcast("cl_npc", [i, PARADE, pos[i], dir.normalized() * dist, MatchState.time, flags], self)


## Brings back someone who had left the beach as a fresh arrival with full pockets.
func srv_revive(i: int, at: Vector3, cash: int, dir: Vector3, dist: float) -> void:
	pos[i] = at
	money[i] = cash
	hp[i] = DB.ARCHETYPES[arch[i]].hp
	srv_parade(i, dir, dist, 2)


## Indices of up to `limit` NPCs who have gone home.
func gone(limit: int) -> Array:
	var out: Array = []
	for i in count:
		if state[i] == GONE:
			out.append(i)
			if out.size() >= limit:
				break
	return out


## Everyone minding their own business within r of `at` runs from it.
func srv_scare(at: Vector3, r: float, chance := 1.0) -> void:
	for i in count:
		if state[i] == AMBIENT and absf(pos[i].x - at.x) < r and absf(pos[i].z - at.z) < r and absf(pos[i].y - at.y) < 3.0 and randf() < chance:
			_srv_flee(i, at)


## Two NPCs open fire on each other until one drops or `seconds` pass.
func srv_duel(a: int, b: int, seconds: float) -> void:
	for pair in [[a, b], [b, a]]:
		var i: int = pair[0]
		if state[i] >= DEAD:
			continue
		_hostile[i] = {"target": -1, "duel": pair[1], "cd": randf_range(0.3, 1.2), "until": seconds, "shooter": true}
		_srv_set(i, HOSTILE)
		_yaw[i] = Kit.face(pos[pair[1]] - pos[i])


func _srv_flee(i: int, threat: Vector3) -> void:
	_hostile.erase(i)
	var dir := pos[i] - threat
	dir.y = 0.0
	var b := Layout.band(pos[i].z)
	if pos[i].y > 1.0 or b == 2 or b == 4:
		# In a street or along a terrace there is only up it or down it.
		dir = Vector3(1.0 if dir.x >= 0.0 else -1.0, 0.0, 0.0)
	elif b % 2 == 1:
		dir = Vector3(0.0, 0.0, 1.0 if dir.z >= 0.0 else -1.0)
	else:
		# Bias toward the city so they run off the beach rather than into the sea.
		dir = (dir.normalized() + Vector3(0, 0, 0.6)).normalized()
	_srv_set(i, FLEE, dir)


func _srv_react(i: int, pid: int, threat: Vector3) -> void:
	var a = DB.ARCHETYPES[arch[i]]
	if randf() < a.fight:
		_hostile[i] = {"target": pid, "cd": 0.8, "until": 20.0, "shooter": randf() < a.shoot}
		_srv_set(i, HOSTILE)
	else:
		_srv_flee(i, threat)


func _srv_hostile(i: int, delta: float) -> void:
	var h = _hostile.get(i)
	if h == null:
		return
	var g = Net.game
	h.until -= delta
	if h.has("duel"):
		_srv_duel_tick(i, h, delta)
		return
	var p = g.players.get(h.target)
	if p == null or not p.can_fight() or h.until <= 0.0:
		_srv_flee(i, pos[i] - Vector3(0, 0, 1))
		return
	var to: Vector3 = p.global_position - pos[i]
	var dy := absf(to.y)
	to.y = 0.0
	var d := to.length()
	if d > 60.0:
		_srv_flee(i, p.global_position)
		return
	var step := pos[i]
	# Streets have to be gone round; nobody up on a terrace gives chase at all.
	if d > (12.0 if h.shooter else 1.5) and pos[i].y < 1.0:
		var via := Layout.next_point(pos[i], p.global_position) - pos[i]
		via.y = 0.0
		if via.length() > 0.3:
			step += via.normalized() * HOSTILE_SPEED * delta
	_hostile_step(i, step, delta)
	h.cd -= delta
	if h.cd > 0.0:
		return
	if h.shooter and d < 25.0:
		h.cd = 1.2
		var hit := randf() < 0.55
		var from := pos[i] + Vector3(0, 1.3, 0)
		var to_pt: Vector3 = p.global_position + Vector3(0, 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)))
		g.bcast("cl_fx", [from, to_pt, false, DB.WHO_NPC, i, DB.WHO_PLAYER if hit else DB.WHO_NONE, h.target])
		Crime.report_noise(pos[i], 80.0, -1)
		if hit:
			g.srv_damage(h.target, 14.0, -1)
	elif not h.shooter and d < 2.0 and dy < 2.0:
		h.cd = 1.0
		g.bcast("cl_fx", [pos[i] + Vector3(0, 1.3, 0), p.global_position + Vector3(0, 1.0, 0), true, DB.WHO_NPC, i, DB.WHO_PLAYER, h.target])
		g.srv_damage(h.target, DB.ARCHETYPES[arch[i]].melee, -1)


func _srv_duel_tick(i: int, h: Dictionary, delta: float) -> void:
	var g = Net.game
	var other: int = h.duel
	if h.until <= 0.0 or state[other] >= DEAD:
		_srv_flee(i, pos[other])
		return
	h.cd -= delta
	if h.cd > 0.0:
		return
	h.cd = randf_range(0.7, 1.5)
	var hit := randf() < 0.3
	var to_pt := pos[other] + Vector3(0, 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.0), randf_range(-1.5, 1.5)))
	g.bcast("cl_fx", [pos[i] + Vector3(0, 1.3, 0), to_pt, false, DB.WHO_NPC, i, DB.WHO_NPC if hit else DB.WHO_NONE, other])
	Crime.report_noise(pos[i], 90.0, -1)
	if hit:
		srv_damage_npc(other, 35.0, -1)
		if state[other] == DEAD and randf() < 0.5:
			g.srv_add_drop(pos[other] + Vector3(0.8, 0, 0.5), 0, {"pistol": 1, "ammo": 6})


## Makes an NPC who was minding their own business go after a player, if they are the type.
func srv_provoke(i: int, pid: int) -> void:
	if i < 0 or i >= count or state[i] != AMBIENT or DB.ARCHETYPES[arch[i]].fight <= 0.0:
		return
	_hostile[i] = {"target": pid, "cd": 0.8, "until": 15.0, "shooter": false}
	_srv_set(i, HOSTILE)


func srv_damage_npc(i: int, dmg: float, attacker: int) -> void:
	if i < 0 or i >= count or state[i] >= DEAD:
		return
	var g = Net.game
	hp[i] -= dmg
	for pid in _rob.keys():
		if _rob[pid].npc == i:
			_rob.erase(pid)
	if hp[i] <= 0.0:
		_hostile.erase(i)
		_srv_set(i, DEAD)
		if money[i] > 0:
			g.srv_add_drop(pos[i], money[i], {})
			money[i] = 0
	elif state[i] != HOSTILE:
		var p = g.players.get(attacker)
		_srv_react(i, attacker, p.global_position if p != null else pos[i])


# --- server: robbery ---

## Sent at 10 Hz while a player holds rob on an NPC. `loud` is mic loudness 0..1.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_rob(i: int, loud: float) -> void:
	var pid := Net.sender()
	var g = Net.game
	var p = g.players.get(pid)
	if p == null or not p.can_fight() or i < 0 or i >= count:
		return
	loud = clampf(loud, 0.0, 1.0)
	var r = _rob.get(pid)
	if r == null or r.npc != i:
		if state[i] != AMBIENT:
			return
		if r != null:
			_srv_rob_abort(pid)
		# Someone asleep on a towel can be robbed without a word, if you keep it that way.
		r = {"npc": i, "meter": 0.0, "quiet": 0.0, "last": 0.0, "pick": is_lying(i) and loud < PICK_LOUD}
		_rob[pid] = r
		if not r.pick:
			_srv_set(i, COWER)
	elif state[i] != (AMBIENT if r.pick else COWER):
		_rob.erase(pid)
		return
	if r.pick:
		_srv_pickpocket(pid, p, r, loud)
		return
	if pos[i].distance_to(p.global_position) > 6.0:
		_srv_rob_abort(pid)
		return
	r.last = 0.0

	var a = DB.ARCHETYPES[arch[i]]
	var pressure: float = loud * DB.ITEMS[p.st.equipped].intimidation * p.intimidation_mult()
	r.meter = clampf(r.meter + (pressure - a.resistance) * ROB_RATE * ROB_TICK, 0.0, 1.0)
	# Louder carries further: more police and players hear it.
	if loud > 0.12:
		Crime.report_noise(pos[i], loud * 70.0, pid)
	Crime.report_crime(pos[i], pid, 1)
	r.quiet = r.quiet + ROB_TICK if pressure < a.resistance else maxf(0.0, r.quiet - ROB_TICK)

	if r.meter >= 1.0:
		_rob.erase(pid)
		var cash := money[i]
		var tier := DB.wealth_tier(cash)
		money[i] = 0
		p.st.money += cash
		var msg := "Robbed R$%d" % cash
		# The rich hand over more than cash. It only pays once a fence has bought it.
		var loot := ""
		if _look[i] & Kit.F_CAMERA and randf() < 0.5:
			loot = "camera"
		elif tier == 2 and randf() < 0.6:
			loot = "chain"
		elif tier >= 1 and randf() < 0.4:
			loot = "watch" if randf() < 0.5 else "phone"
		if loot != "":
			g._give(p.st, loot, 1)
			msg += " + %s" % DB.ITEMS[loot].name
		if randf() < a.gun:
			p.st.inv["pistol"] = 1
			p.st.ammo += 6
			msg += " + a pistol"
		g.push_state(p)
		g.send(pid, "cl_toast", [msg])
		g.send(pid, "cl_rob_meter", [0.0])
		_srv_flee(i, p.global_position)
		return
	# Unconvinced victims stop cooperating; mafia may turn on you mid-robbery.
	if r.quiet > 3.0 or randf() < a.fight * 0.12 * ROB_TICK:
		_rob.erase(pid)
		g.send(pid, "cl_rob_meter", [0.0])
		_srv_react(i, pid, p.global_position)
		return
	g.send(pid, "cl_rob_meter", [r.meter])


## Going through a sunbather's bag. Any noise wakes them, and now and then they just wake.
func _srv_pickpocket(pid: int, p, r: Dictionary, loud: float) -> void:
	var g = Net.game
	var i: int = r.npc
	if pos[i].distance_to(p.global_position) > 4.0:
		_rob.erase(pid)
		g.send(pid, "cl_rob_meter", [0.0])
		return
	r.last = 0.0
	r.meter += ROB_TICK / PICK_TIME
	if loud > PICK_LOUD * 2.0 or randf() < 0.035 * ROB_TICK * 10.0:
		_rob.erase(pid)
		g.send(pid, "cl_rob_meter", [0.0])
		g.send(pid, "cl_toast", ["They woke up!"])
		Crime.report_crime(pos[i], pid, 1)
		_lying[i] = 0
		_srv_react(i, pid, p.global_position)
		return
	if r.meter < 1.0:
		g.send(pid, "cl_rob_meter", [r.meter])
		return
	_rob.erase(pid)
	var cash := int(money[i] * 0.6)
	money[i] -= cash
	p.st.money += cash
	var msg := "Lifted R$%d" % cash
	if randf() < 0.35:
		g._give(p.st, "phone", 1)
		msg += " + %s" % DB.ITEMS["phone"].name
	g.push_state(p)
	g.send(pid, "cl_toast", [msg])
	g.send(pid, "cl_rob_meter", [0.0])
	# The bag is lighter; what they are seen wearing stays as it was.
	_srv_set(i, AMBIENT)


func _srv_rob_abort(pid: int) -> void:
	var r = _rob.get(pid)
	_rob.erase(pid)
	if r == null or state[r.npc] != COWER:
		return
	var p = Net.game.players.get(pid)
	_srv_flee(r.npc, p.global_position if p != null else pos[r.npc])


# --- debug ---

## --showcase: lines up one NPC of each look and state in front of `at` (host only).
func debug_showcase(at: Vector3) -> void:
	var used := {}
	var pick := func(want: Callable) -> int:
		for i in count:
			if not used.has(i) and state[i] == AMBIENT and want.call(i):
				used[i] = true
				return i
		return 0
	var stander := func(a: int, tier: int) -> Callable:
		return func(i: int) -> bool: return arch[i] == a and _tier[i] == tier and _walker[i] == 0 and _lying[i] == 0
	var front := at + Vector3(0, 0, -5)
	var back := at + Vector3(0, 0, -8.5)
	var spots := {}
	spots[pick.call(stander.call(0, 0))] = front + Vector3(-7, 0, 0)
	spots[pick.call(stander.call(0, 1))] = front + Vector3(-5, 0, 0)
	spots[pick.call(stander.call(1, 0))] = front + Vector3(-3, 0, 0)
	spots[pick.call(stander.call(2, 2))] = front + Vector3(-1, 0, 0)
	var sunbather: int = pick.call(func(i: int) -> bool: return _lying[i] == 1)
	var cower: int = pick.call(stander.call(0, 1))
	var fighter: int = pick.call(stander.call(1, 0))
	var gunman: int = pick.call(stander.call(2, 2))
	var corpse: int = pick.call(stander.call(0, 1))
	var runner: int = pick.call(stander.call(0, 0))
	for i in count:
		if not used.has(i) and state[i] < DEAD and pos[i].distance_to(front) < 16.0:
			state[i] = GONE
			_hide(i)
	for i in spots:
		_home[i] = spots[i]
		_yaw[i] = PI
		_place(i, spots[i])
	_home[sunbather] = front + Vector3(1.2, 0, 0)
	_yaw[sunbather] = 0.6
	_place(sunbather, _home[sunbather])
	_yaw[cower] = PI
	cl_npc(cower, COWER, front + Vector3(3.6, 0, 0), Vector3.ZERO, 0.0, 1)
	cl_npc(fighter, HOSTILE, front + Vector3(5.4, 0, 0), Vector3.ZERO, 0.0, 0)
	cl_npc(gunman, HOSTILE, front + Vector3(7.2, 0, 0), Vector3.ZERO, 0.0, 2 | NPC_SHOOTER)
	for i in [fighter, gunman]:
		_yaw[i] = PI
		_place(i, pos[i])
	_yaw[corpse] = PI * 0.5
	cl_npc(corpse, DEAD, back + Vector3(-6.5, 0, 0), Vector3.ZERO, 0.0, 0)
	# Timed to be crossing the back row when the screenshot fires at 4 s.
	cl_npc(runner, FLEE, back + Vector3(6.5 - FLEE_SPEED * 3.9, 0, 0), Vector3.RIGHT, MatchState.time, 0)
