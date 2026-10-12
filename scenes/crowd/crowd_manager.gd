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
const Activities := preload("res://scenes/crowd/activities.gd")
const Babble := preload("res://scenes/crowd/babble.gd")
const Places := preload("res://scenes/world/places.gd")
const Nav := preload("res://scenes/world/nav.gd")

## Everything before DEAD is somebody who is still there to be dealt with.
enum { AMBIENT, COWER, FLEE, HOSTILE, PARADE, KO, DEAD, GONE }

const COUNT := 2500
const FLEE_SPEED := 5.5
## How far someone runs from trouble before they stop and look back.
const FLEE_DIST := 42.0
## How long before someone who ran comes back to where they were.
const CALM_TIME := 50.0
const HOSTILE_SPEED := 4.8
const ROB_RATE := 0.55
const ROB_TICK := 0.1
## Mic level under which a sunbather sleeps on, and how long their bag takes to go through.
const PICK_LOUD := 0.08
const PICK_TIME := 2.5
## Someone out cold takes no time at all to go through, and will not wake for it.
const PICK_TIME_KO := 1.0
## A hold-up in progress is one crime that goes on, not ten a second.
const ROB_CRIME_EVERY := 1.0
const BODY_RADIUS := 0.5
const WORLD_AABB := Layout.WORLD_AABB
## cl_npc flag bit: this hostile NPC has a gun out. The low two bits are its wealth tier.
const NPC_SHOOTER := 4
## cl_npc flag bit: a PARADE NPC is dancing along rather than running for cover.
const NPC_DANCE := 8
## cl_npc flag bit: a PARADE NPC is just walking there.
const NPC_STROLL := 16
## cl_run flag bit: at the end of the run they are gone for good.
const NPC_VANISH := 32
## cl_run flag bit: walking back to where they started the day, to pick up where they left off.
const NPC_HOME := 64
## cl_run flag bits: hurt and limping, or too hurt to do more than crawl.
const NPC_HURT := 128
const NPC_CRAWL := 256
## What is going on, as far as the people near it are concerned (srv_panic).
const FRIGHT_FIGHT := 1
const FRIGHT_SHOTS := 2
const FRIGHT_BLAST := 3
## How near a punch has to land for people to scatter, and how many can take fright at once.
const FIGHT_RANGE := 15.0
const BLAST_RANGE := 70.0
const GAWK_TIME := 9.0
## People with somewhere to be: how many rounds there are, and how many walk each.
const ROUNDS := 44
const ROUND_SHARE := 4
const STROLL_SPEED := 1.5
const DANCE_SPEED := 1.6
const SHELTER_SPEED := 4.6
## Gunfire this close sends people running; a crime this close may get someone's phone out.
const PANIC_RANGE := 45.0
const PANIC_MAX := 110
const CALL_RANGE := 14.0
const CALL_CHANCE := 0.3
const CALL_TIME := 4.0
## How close a bike has to pass to someone to grab what they are holding.
const SNATCH_RANGE := 3.4
## How many of the crowd can have something in their hand at once.
const HELD_POOL := 64
const NO_POSE := 255
## What a stroller might stop to do, and how people stand after a fright.
const PAUSE_POSES := [Kit.PHONE, Kit.LOOK, Kit.PHOTO, Kit.PHONE, Kit.STAND, Kit.TIE, Kit.WAVE, Kit.STRETCH, Kit.YAWN, Kit.SMOKE, Kit.POINT, Kit.CALL, Kit.SELFIE, Kit.STAND, Kit.SHRUG]
const SHAKEN_POSES := [Kit.LOOK, Kit.FILM, Kit.CALL, Kit.SQUAT, Kit.LOOK, Kit.PHONE, Kit.POINT]
const LOCAL_TOPS := [Color(1.0, 0.85, 0.1), Color(0.1, 0.65, 0.3), Color(0.95, 0.95, 0.95), Color(0.3, 0.7, 0.95), Color(0.9, 0.35, 0.2)]

var count := 0
var pos := PackedVector3Array()
var state := PackedByteArray()
var arch := PackedByteArray()
var money := PackedInt32Array()
var hp := PackedFloat32Array()
## NPC indices close to the local player, refreshed at 10 Hz.
var near := PackedInt32Array()

const PARTY_RANGE := 10.0
var _party := {}           # idx -> true while dancing along with someone on bala
## What the ambient crowd is up to in groups: tables, ball games, gangs (see activities.gd).
var acts: Node3D

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
var _w_stop := PackedFloat32Array()   # seconds a walker stands still in each cycle (0: never)
var _w_cycle := PackedFloat32Array()  # length of that cycle
var _w_pause := PackedByteArray()     # Kit pose a walker has stopped to strike, 0 while walking
var _errands := PackedInt32Array()    # walkers who go from place to place rather than up and down
var _round := PackedInt32Array()      # which of _rounds each of them walks, -1 for everybody else
var _rounds: Array = []               # {pts, stops: [[metres along, seconds, pose]], time}
var _w_pose := PackedByteArray()      # how they walk: Kit.WALK, or head down in a phone, or the worse for drink
var _origin := PackedVector3Array()   # where they started the day
var _was := PackedByteArray()         # what they were doing there: 1 walking, 2 lying
var _leave_t := PackedFloat32Array()
var _leave_order := PackedInt32Array()
var _leave_ptr := 0
var _look := PackedInt32Array()    # Kit clothing flags from the archetype
var _tier := PackedByteArray()     # wealth tier still on show (drops to 0 once robbed)
var _ev := PackedFloat32Array()    # Kit one-shot event time
var _idle := PackedByteArray()     # Kit pose when standing about (dancers, drummers)
var _gun := PackedByteArray()      # 1: carries a pistol openly (the boca's soldiers)
var _grp := PackedInt32Array()     # activity group they belong to, -1 once they have left it
var _sit := PackedByteArray()      # 1: sitting down
var _gest := PackedByteArray()     # 1: the one doing the talking
var _babble: Node3D
var _pose := PackedByteArray()     # Kit pose now showing, NO_POSE before the first
var _prev := PackedByteArray()     # the pose it is blending out of
var _pose_t := PackedFloat32Array()  # Kit.now() when the pose last changed
var _scream_ms := 0
var _mm: MultiMesh
var _held: MultiMesh
var _held_slot := {}   # idx -> slot in _held
var _held_free: Array[int] = []
var _blood: MultiMesh
var _blood_n := 0
var _active := {}          # idx -> true while FLEE / HOSTILE
var _ov := {}              # idx -> [corners to run through, t0, speed, length, flags] for FLEE / PARADE
var _hostile_target := {}  # client: idx -> latest server position
var _shooter := {}         # idx -> true while HOSTILE with a gun
var _moving := {}          # idx -> whether a HOSTILE NPC is currently running
var _dancing := {}         # idx -> how a PARADE NPC is going: 1 dancing, 2 strolling (absent: running)
var _changed := {}         # idx -> last state event, replayed to late joiners

# server only
var _rob := {}      # pid -> {npc, meter, quiet, last}
var _hostile := {}  # idx -> {target, cd, until, shooter}
var _ko := {}       # idx -> [match time they come round, pid who did it]
var _calls := {}    # idx -> [match time the call goes through, where, pid, severity]
var _cower := {}    # idx -> match time someone cowering indoors gets up again
var _calm := {}     # idx -> match time someone who ran goes back to where they were
var _gawk := {}     # idx -> match time someone who stopped to stare gets on with their day
var _waves: Array = []   # [match time, where, radius, level, pid]: fright still spreading
var _bodies: Array = []  # where the dead are lying, for passers-by to come across
var _body_k := 0
var _body_t := 0.0
var _fight_ok := 0.0
var _panic_ok := 0.0
var _call_ok := 0.0
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
	_ko.clear()
	_calls.clear()
	_cower.clear()
	_calm.clear()
	_gawk.clear()
	_waves.clear()
	_bodies.clear()
	_fight_ok = 0.0
	_panic_ok = 0.0
	_call_ok = 0.0
	if multiplayer.is_server() and not Crime.noise.is_connected(_on_noise):
		Crime.noise.connect(_on_noise)
		Crime.crime.connect(_on_crime)
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
	_w_stop.resize(count)
	_w_cycle.resize(count)
	_w_pause.resize(count)
	_w_pause.fill(0)
	_w_pose.resize(count)
	_round.resize(count)
	_round.fill(-1)
	_errands.clear()
	_origin.resize(count)
	_was.resize(count)
	_leave_t.resize(count)
	money.resize(count)
	_look.resize(count)
	_tier.resize(count)
	_ev.resize(count)
	_idle.resize(count)
	_gun.resize(count)
	_grp.resize(count)
	_sit.resize(count)
	_gest.resize(count)
	_gest.fill(0)
	_pose.resize(count)
	_prev.resize(count)
	_pose_t.resize(count)
	_pose.fill(NO_POSE)
	_prev.fill(NO_POSE)
	_pose_t.fill(0.0)
	_leave_order.resize(count)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tops := PackedColorArray()
	var towels := PackedInt32Array()
	var order: Array = []
	# Whoever has somewhere to be is placed first; everyone else fills in round them.
	acts = Activities.new()
	add_child(acts)
	var planned: Array = acts.plan(seed_value, self)
	_babble = Babble.new()
	add_child(_babble)

	for i in count:
		# Where they spend the day decides a lot about who they are.
		var spot: Dictionary = planned[i] if i < planned.size() else _spot(rng)
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
		_grp[i] = spot.get("grp", -1)
		_sit[i] = 1 if spot.get("sit", false) else 0

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
		# People out for a stroll stop now and then; people running or playing do not.
		_w_cycle[i] = rng.randf_range(16.0, 55.0)
		_w_stop[i] = rng.randf_range(2.5, 7.0) if _w_spd[i] < 2.5 and rng.randf() < 0.8 else 0.0
		var style := rng.randf()
		_w_pose[i] = Kit.WALK
		if a.id != "vendor" and _w_spd[i] < 2.5:
			if style < 0.1:
				_w_pose[i] = Kit.TEXT_WALK
			elif style < 0.125 and not on_sand:
				# Somebody started early.
				_w_pose[i] = Kit.STAGGER
				_w_spd[i] = 0.7
		if walker:
			# The lane runs only as far each way as there is nothing to walk into.
			p = Nav.nearest_free(p)
			var half := _w_len[i] * 0.5
			var fwd := maxf(Nav.free_run(p, _w_dir[i], half) - 0.5, 0.0)
			var back := maxf(Nav.free_run(p, -_w_dir[i], half) - 0.5, 0.0)
			p += _w_dir[i] * (fwd - back) * 0.5
			_w_len[i] = fwd + back
			while _w_len[i] > 3.0 and not Nav.clear(p - _w_dir[i] * _w_len[i] * 0.5, p + _w_dir[i] * _w_len[i] * 0.5):
				_w_len[i] *= 0.8
			walker = _w_len[i] > 3.0
			_home[i] = p
		elif _grp[i] < 0:
			p = Nav.nearest_free(p)
			_home[i] = p
		_walker[i] = 1 if walker else 0
		if walker:
			_walkers.append(i)
		if _lying[i] == 1:
			towels.append(i)
		_origin[i] = _home[i]
		_was[i] = (1 if walker else 0) | (2 if _lying[i] == 1 else 0)
		# Left to themselves on a pavement, people get their phones out or hunker down.
		if not walker and not on_sand and _lying[i] == 0 and not spot.has("idle"):
			var habit := rng.randf()
			if habit < 0.22:
				_idle[i] = Kit.PHONE
			elif habit < 0.3:
				_idle[i] = Kit.SQUAT
			elif habit < 0.36:
				_idle[i] = Kit.CALL

		# A few stragglers never leave; everyone else drains out over the match.
		# People with a job to do indoors, or nowhere else they are allowed to be, stay put.
		var stays := rng.randf() < (0.5 if _grp[i] >= 0 else (0.04 if p.z < Layout.WALK_Z else 0.6)) or (_grp[i] >= 0 and Places.room_at(p) >= 0)
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
			"preso":
				top = Color(1.0, 0.45, 0.05)
				look = Kit.F_JAIL
			"guarda":
				top = Color(0.1, 0.17, 0.52)
				look = Kit.F_POLICE | Kit.F_SUIT
			"malandro":
				top = [Color(0.55, 0.05, 0.08), Color(0.08, 0.08, 0.1), Color(0.95, 0.95, 0.95)][rng.randi() % 3]
				look = Kit.F_SHORTS | Kit.F_TANK | Kit.F_CHAIN
				if rng.randf() < 0.6:
					look |= Kit.F_HAT
				if rng.randf() < 0.5:
					look |= Kit.F_SHADES
			"traficante":
				top = Color(0.1, 0.1, 0.1)
				look = Kit.F_SHORTS | Kit.F_SHIRTLESS | Kit.F_SHADES | Kit.F_CHAIN
			_:
				top = Color(0.09, 0.09, 0.11) if rng.randf() < 0.7 else Color(0.95, 0.95, 0.95)
				look = Kit.F_SUIT | Kit.F_SHADES
		if _lying[i] == 1 and rng.randf() < 0.5:
			look |= Kit.F_SHADES
		top.a = rng.randf()
		tops.append(top)
		_look[i] = look | spot.get("look", 0)
		_gun[i] = 1 if a.id == "traficante" else 0

	_plan_rounds(rng)
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
	if roll < 0.585:
		# A kickabout: both sides chasing up and down a pitch.
		var rect: Array = Layout.PITCHES[rng.randi() % Layout.PITCHES.size()]
		var c: Vector3 = rect[0]
		var h: Vector2 = rect[1]
		var run := rng.randf_range(6.0, 14.0)
		var p := c + Vector3(rng.randf_range(-1.0, 1.0) * (h.x - run * 0.5 - 1.0), 0.0, rng.randf_range(-1.0, 1.0) * (h.y - 2.5))
		return {"p": p, "walk": 1.0, "dir": Vector3(1.0, 0.0, rng.randf_range(-0.3, 0.3)).normalized(), "far": run, "speed": rng.randf_range(2.8, 4.5), "arch": "local", "look": Kit.F_SHIRTLESS if rng.randf() < 0.5 else 0}
	if roll < 0.595:
		# Futevolei: two a side, facing the net.
		var rect: Array = Layout.COURTS[rng.randi() % Layout.COURTS.size()]
		var c: Vector3 = rect[0]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		return {"p": c + Vector3(side * rng.randf_range(2.0, 6.5), 0.0, rng.randf_range(-3.0, 3.0)), "walk": 0.0, "dir": along, "far": 1.0, "arch": "local", "yaw": Kit.face(Vector3(-side, 0, 0)), "idle": Kit.STAND, "look": Kit.F_SHIRTLESS}
	if roll < 0.61:
		# Joggers pounding the ciclovia.
		return {"p": Vector3(x, 0.0, rng.randf_range(50.9, 51.7)), "walk": 1.0, "dir": along, "far": 140.0, "speed": rng.randf_range(3.0, 3.9), "look": Kit.F_TANK | Kit.F_SHORTS}
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
	_held = Kit.add_held(self, HELD_POOL, WORLD_AABB)
	_held_slot.clear()
	_held_free.clear()
	for k in HELD_POOL:
		_held_free.append(HELD_POOL - 1 - k)

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
	var xf := Kit.xform(p, _yaw[i], _width[i], _scale[i])
	_mm.set_instance_transform(i, xf)
	if _held_slot.has(i):
		_held.set_instance_transform(_held_slot[i], xf)


func _hide(i: int) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
	_drop_held(i)


## Gives NPC i a slot in the held layer, or takes it away. With every slot taken they go
## without: the gun is still there as far as the game is concerned.
func _show_held(i: int, data: Color) -> void:
	if not _held_slot.has(i):
		if _held_free.is_empty():
			return
		_held_slot[i] = _held_free.pop_back()
		_held.set_instance_color(_held_slot[i], _mm.get_instance_color(i))
	var k: int = _held_slot[i]
	_held.set_instance_custom_data(k, data)
	_held.set_instance_transform(k, Kit.xform(pos[i], _yaw[i], _width[i], _scale[i]))


func _drop_held(i: int) -> void:
	if _held_slot.has(i):
		_held.set_instance_transform(_held_slot[i], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
		_held_free.append(_held_slot[i])
		_held_slot.erase(i)


## Pushes NPC i's pose and props to the shader. Call after anything that changes how it looks.
func _restyle(i: int) -> void:
	var pose := Kit.STAND
	var speed := 0.0
	var flags: int = _look[i] | Kit.TIER_PROPS[_tier[i]]
	var held: int = Kit.HELD_PISTOL if _gun[i] == 1 else Kit.HELD_NONE
	match state[i]:
		AMBIENT:
			if _lying[i] == 1:
				pose = Kit.SUNBATHE
			elif _walker[i] == 1:
				if _w_pause[i] != 0:
					pose = _w_pause[i]
				else:
					pose = Kit.RUN if _w_spd[i] > 2.5 else _w_pose[i]
					speed = _w_spd[i]
			elif _party.has(i):
				pose = Kit.DANCE
			else:
				pose = _idle[i]
				speed = float(_gest[i])
		COWER:
			pose = Kit.COWER
		FLEE:
			var e: Array = _ov.get(i, [])
			if e.is_empty():
				pose = Kit.FLEE
			elif not e[5]:
				# Rooted to the spot for the moment it takes to believe it.
				pose = Kit.SCREAM if i % 3 != 0 else Kit.COWER
			elif e[4] & NPC_CRAWL:
				pose = Kit.CRAWL
				speed = 2.0
			elif e[4] & NPC_HURT:
				pose = Kit.LIMP
				speed = 2.5
			else:
				pose = [Kit.FLEE, Kit.PANIC, Kit.RUN, Kit.PANIC][i % 4]
				speed = e[2]
		PARADE:
			pose = [Kit.FLEE, Kit.DANCE, Kit.WALK][_dancing.get(i, 0)]
			speed = _ov[i][2] if _ov.has(i) else STROLL_SPEED
		HOSTILE:
			pose = Kit.AIM if _shooter.has(i) else Kit.FIGHT
			speed = HOSTILE_SPEED if _moving.get(i, false) else 0.0
			flags |= Kit.F_ANGRY
			if _shooter.has(i):
				held = Kit.HELD_PISTOL
		KO:
			pose = Kit.KO
			held = Kit.HELD_NONE
		DEAD:
			pose = Kit.DEAD
			flags = _look[i]
			held = Kit.HELD_NONE
	if pose != _pose[i]:
		_prev[i] = _pose[i]
		_pose[i] = pose
		_pose_t[i] = Kit.now()
	var data := Kit.custom(pose, speed, flags, _ev[i], -1 if _prev[i] == NO_POSE else _prev[i], _pose_t[i], held)
	_mm.set_instance_custom_data(i, data)
	if held != Kit.HELD_NONE:
		_show_held(i, data)
	else:
		_drop_held(i)


## Is NPC i still at their activity, free to be told what to do?
func act_free(i: int) -> bool:
	return state[i] == AMBIENT and _grp[i] >= 0


## Their activity wants NPC i in `pose` now; `gest` marks the one doing the talking.
func act_pose(i: int, pose: int, gest: bool) -> void:
	if not act_free(i) or (_idle[i] == pose and (_gest[i] == 1) == gest):
		return
	_idle[i] = pose
	_gest[i] = 1 if gest else 0
	_restyle(i)


## A touch of the ball, a swing of the bat: the one-shot on NPC i.
func act_event(i: int) -> void:
	if act_free(i):
		_ev[i] = Kit.now()
		_restyle(i)


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

	if acts != null:
		acts.tick(t)
		_babble.tick(delta, acts)

	for i in _walkers:
		if state[i] != AMBIENT or _walker[i] == 0:
			continue
		var length := _w_len[i]
		var tw := t
		if _w_stop[i] > 0.0:
			# Each cycle is a stretch of walking and then a stop; only the walking moves them on.
			var cyc := _w_cycle[i]
			var at := t + i * 7.31
			var k := floorf(at / cyc)
			var walk := cyc - _w_stop[i]
			var ph := at - k * cyc
			tw = k * walk + minf(ph, walk)
			var pause := _pause_pose(i, int(k)) if ph > walk else 0
			if pause != _w_pause[i]:
				_w_pause[i] = pause
				_restyle(i)
		var u := fposmod(tw * _w_spd[i] + _w_phase[i], 2.0 * length)
		var out := u < length
		# Turning round at the end of the lane takes a moment, as it does for anyone.
		_yaw[i] = lerp_angle(_yaw[i], _w_yaw[i] if out else _w_yaw[i] + PI, minf(1.0, 7.0 * delta))
		_place(i, _home[i] + _w_dir[i] * ((u if out else 2.0 * length - u) - length * 0.5))

	for i in _errands:
		if state[i] != AMBIENT or _walker[i] == 0:
			continue
		var r: Dictionary = _rounds[_round[i]]
		var left := fposmod(t + _w_phase[i], _w_cycle[i])
		var spd := _w_spd[i]
		var at := 0.0
		var pause := 0
		# Walk to the next stop, stand there a while, walk on.
		for stop in r.stops:
			var leg: float = (stop[0] - at) / spd
			if left < leg:
				at += left * spd
				left = -1.0
				break
			left -= leg
			at = stop[0]
			if left < stop[1]:
				pause = stop[2]
				left = -1.0
				break
			left -= stop[1]
		if left > 0.0:
			at += left * spd
		if pause != _w_pause[i]:
			_w_pause[i] = pause
			_restyle(i)
		var where: Array = Nav.along(r.pts[0], r.pts, at)
		if pause == 0 and where[1] != Vector3.ZERO:
			_yaw[i] = lerp_angle(_yaw[i], Kit.face(where[1]), minf(1.0, 7.0 * delta))
		_place(i, where[0])

	var server := multiplayer.is_server()
	for i in _active.keys():
		if state[i] == FLEE or state[i] == PARADE:
			var e: Array = _ov[i]
			if t < e[1]:
				continue
			if not e[5]:
				e[5] = true
				_restyle(i)
			var d: float = (t - e[1]) * e[2]
			var far: float = e[3]
			var at: Array = Nav.along(e[0][0], e[0], minf(d, far))
			if at[1] != Vector3.ZERO:
				_yaw[i] = lerp_angle(_yaw[i], Kit.face(at[1]), minf(1.0, 9.0 * delta))
			_place(i, at[0])
			if d >= far:
				_end_run(i, e[4])
		elif state[i] == HOSTILE:
			if server:
				_srv_hostile(i, delta)
			elif _hostile_target.has(i):
				_hostile_step(i, pos[i].lerp(_hostile_target[i], minf(1.0, 10.0 * delta)), delta)

	if server:
		for i in _cower.keys():
			if state[i] != COWER:
				_cower.erase(i)
			elif t >= _cower[i]:
				var robbing := false
				for pid in _rob:
					robbing = robbing or _rob[pid].npc == i
				if not robbing:
					_cower.erase(i)
					_srv_set(i, AMBIENT)
		for k in range(_waves.size() - 1, -1, -1):
			if t >= _waves[k][0]:
				var w: Array = _waves[k]
				_waves.remove_at(k)
				srv_panic(w[1], w[2], w[3], w[4], false)
		for i in _gawk.keys():
			if t >= _gawk[i]:
				_gawk.erase(i)
				if state[i] == AMBIENT:
					Net.game.bcast("cl_gawk", [i, pos[i], Kit.STAND, false], self)
		# Now and then somebody walks up on a body.
		if not _bodies.is_empty() and t >= _body_t:
			_body_t = t + 1.5
			_body_k = (_body_k + 1) % _bodies.size()
			srv_panic(_bodies[_body_k], 7.0, FRIGHT_FIGHT, -1, false)
		for i in _calm.keys():
			if t >= _calm[i]:
				# One a frame: working out the way home is not free.
				_calm.erase(i)
				_srv_go_home(i)
				break
		for i in _calls.keys():
			var call: Array = _calls[i]
			if state[i] != AMBIENT:
				# Hung up on, one way or another.
				_calls.erase(i)
			elif t >= call[0]:
				_calls.erase(i)
				Crime.report_tip(call[1], call[2], call[3])
				Net.game.bcast("cl_call", [i, false], self)
		for i in _ko.keys():
			if t >= _ko[i][0]:
				# Comes round with a sore head and a grudge, or just legs it.
				var who: int = _ko[i][1]
				_ko.erase(i)
				if state[i] == KO:
					var pl = Net.game.players.get(who)
					_srv_react(i, who, pl.global_position if pl != null else pos[i])
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

## Bala is catching: anyone idling within a few metres of one of `spots` starts to dance.
func set_party(spots: Array) -> void:
	var now := {}
	for at in spots:
		for i in count:
			if state[i] == AMBIENT and absf(pos[i].x - at.x) < PARTY_RANGE and absf(pos[i].z - at.z) < PARTY_RANGE and absf(pos[i].y - at.y) < 3.0:
				now[i] = true
	for i in _party.keys():
		if not now.has(i):
			_party.erase(i)
			_restyle(i)
	for i in now:
		if not _party.has(i):
			_party[i] = true
			_restyle(i)


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
		var t := DB.ray_point(o, d, pos[i] + Vector3(0, 0.3 if _down(i) else (0.65 if _sit[i] == 1 else 0.9), 0), BODY_RADIUS, best_t)
		if t >= 0.0:
			best = i
			best_t = t
	return best


## Flat out on a towel, eyes shut: someone whose bag can be gone through.
func is_lying(i: int) -> bool:
	return _lying[i] == 1 and state[i] == AMBIENT


## Knocked out: pockets there for the taking.
func is_out(i: int) -> bool:
	return state[i] == KO


## On the ground one way or another, so not part of the standing crowd.
func _down(i: int) -> bool:
	return state[i] == KO or (_lying[i] == 1 and state[i] == AMBIENT)


## Kit.STANCE_* of NPC i, for working out where its head is.
func stance(i: int) -> int:
	if state[i] == KO:
		return Kit.STANCE_BACK
	if _lying[i] == 1 and state[i] == AMBIENT:
		return Kit.STANCE_TOWEL
	if state[i] == COWER:
		return Kit.STANCE_CROUCH
	if _sit[i] == 1 and state[i] == AMBIENT:
		return Kit.STANCE_SEAT
	return Kit.STANCE_STAND


## Full-crowd ray test (server). Returns [index, distance, DB.ZONE_*]; index -1 on a miss.
func ray_pick(o: Vector3, d: Vector3, max_t: float, grow: float) -> Array:
	var best := -1
	var best_t := max_t
	var zone := DB.ZONE_BODY
	var flat := Vector2(d.x, d.z)
	for i in count:
		if state[i] >= DEAD:
			continue
		var c := pos[i]
		var to := Vector2(c.x - o.x, c.z - o.z)
		if absf(to.x) > best_t or absf(to.y) > best_t:
			continue
		# Nowhere near the line: no need for the careful test.
		if absf(to.x * flat.y - to.y * flat.x) > 2.2:
			continue
		var h := Kit.ray_hit(o, d, best_t, c, _yaw[i], _scale[i], stance(i), grow)
		if h[0] >= 0.0:
			best = i
			best_t = h[0]
			zone = h[1]
	return [best, best_t, zone]


## People on their feet within r of p: how much of a crowd someone there is standing in.
func count_near(p: Vector3, r: float) -> int:
	var n := 0
	for i in count:
		if state[i] >= DEAD or _down(i) or absf(pos[i].y - p.y) > 2.5:
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
		if state[i] >= DEAD or _down(i):
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
		if state[i] >= DEAD or _down(i):
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
	_changed[i] = ["cl_npc", [i, s, p, dir, t0, flags]]
	_ov.erase(i)
	if s != AMBIENT and s != COWER:
		# Whatever they were in the middle of, they are not going back to it.
		_grp[i] = -1
		_sit[i] = 0
		_gest[i] = 0
		if _idle[i] != Kit.DANCE and _idle[i] != Kit.DRUM:
			_idle[i] = Kit.STAND
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
		HOSTILE:
			_place(i, p)
			_active[i] = true
			_hostile_target[i] = p
		KO:
			_walker[i] = 0
			_lying[i] = 0
			_home[i] = p
			_place(i, p)
		DEAD:
			_ev[i] = Kit.now()
			_place(i, p)
			if absf(MatchState.time - t0) < 1.0:
				Sfx.play("die", p + Vector3(0, 1.0, 0), 0.0, 0.8 + (i * 7 % 50) * 0.01)
			# The body tips forward, so the pool goes under where the chest lands.
			var chest := p + Basis(Vector3.UP, _yaw[i]) * Vector3(0, 0.012, -1.0 * _scale[i])
			_blood.set_instance_transform(_blood_n % count, Transform3D(Basis(), chest))
			_blood_n += 1
		GONE:
			_hide(i)
	if s != GONE:
		_restyle(i)


## NPC i sets off through the corners in `pts` (the first is where they are now): running
## from something (FLEE) or going somewhere (PARADE).
@rpc("authority", "call_remote", "reliable")
func cl_run(i: int, s: int, pts: PackedVector3Array, t0: float, flags: int) -> void:
	if i < 0 or i >= count or pts.size() < 2 or (s != FLEE and s != PARADE):
		return
	_changed[i] = ["cl_run", [i, s, pts, t0, flags]]
	_begin_run(i, s, pts, t0, flags)


func _run_speed(i: int, s: int, flags: int) -> float:
	if s == FLEE:
		if flags & NPC_CRAWL:
			return 0.7
		if flags & NPC_HURT:
			return 2.1
		# Not everybody is as quick on their feet.
		return FLEE_SPEED * (0.82 + (i * 37 % 100) * 0.0035)
	if flags & NPC_DANCE:
		return DANCE_SPEED
	return STROLL_SPEED if flags & (NPC_STROLL | NPC_HOME) else SHELTER_SPEED


func _begin_run(i: int, s: int, pts: PackedVector3Array, t0: float, flags: int) -> void:
	state[i] = s
	_grp[i] = -1
	_sit[i] = 0
	_gest[i] = 0
	_lying[i] = 0
	_w_pause[i] = 0
	_hostile_target.erase(i)
	_moving.erase(i)
	_shooter.erase(i)
	_tier[i] = flags & 3
	var waits := t0 > MatchState.time
	_ov[i] = [pts, t0, _run_speed(i, s, flags), Nav.length(pts[0], pts), flags, not waits]
	_active[i] = true
	_walker[i] = 0
	if flags & NPC_DANCE:
		_dancing[i] = 1
	elif flags & (NPC_STROLL | NPC_HOME):
		_dancing[i] = 2
	else:
		_dancing.erase(i)
	if waits:
		# Turn to look at it first.
		_home[i] = pos[i]
		_yaw[i] = Kit.face(pts[0] - pts[1]) if pts[0].distance_to(pts[1]) > 0.1 else _yaw[i]
		_place(i, pos[i])
		if s == FLEE:
			_scream(i)
	elif MatchState.time - t0 < 0.5:
		_place(i, pts[0])
	_restyle(i)


## Some people scream. Whether NPC i is one of them is theirs for the day, so every peer
## hears the same people; how many at once is up to each listener's ears.
func _scream(i: int) -> void:
	if i % 100 >= 30 or pos[i].distance_to(Net.game.local_player.global_position if Net.game.local_player != null else pos[i]) > 70.0:
		return
	var now := Time.get_ticks_msec()
	if now - _scream_ms < 160:
		return
	_scream_ms = now
	Sfx.play("scream%d" % (i % 4), pos[i] + Vector3(0, 1.5, 0), 3.0, 0.85 + (i * 13 % 40) * 0.01)


## NPC i has got where they were running to.
func _end_run(i: int, flags: int) -> void:
	var fled := state[i] == FLEE
	_active.erase(i)
	_ov.erase(i)
	if flags & NPC_VANISH:
		state[i] = GONE
		_hide(i)
		return
	state[i] = AMBIENT
	_home[i] = pos[i]
	_walker[i] = 0
	_lying[i] = 0
	if flags & NPC_HOME:
		_resume(i)
	elif fled:
		# Far enough. Turn round and see what is happening back there.
		_yaw[i] += PI
		_idle[i] = _shaken_pose(i)
		_place(i, pos[i])
		if multiplayer.is_server():
			_calm[i] = MatchState.time + CALM_TIME * (0.6 + (i * 53 % 100) * 0.01)
	else:
		_idle[i] = Kit.DANCE if _dancing.get(i, 0) == 1 else Kit.STAND
	_dancing.erase(i)
	_restyle(i)


## Lays out the rounds some people walk instead of a beat: a few places on one side of the
## avenida, the way between them, and what there is to do at each. Several people share a
## round, strung out along it.
func _plan_rounds(rng: RandomNumberGenerator) -> void:
	_rounds.clear()
	# Somewhere to stand in every shop and bar, and at every stall.
	var indoors: Array = []
	for room in Places.rooms:
		var box: AABB = room.public
		if room.get("kind", "") == "presidio" or box.size.x < 2.0 or box.size.z < 2.0:
			continue
		for k in 3:
			var p := Vector3(rng.randf_range(box.position.x + 1.0, box.end.x - 1.0), 0.0, rng.randf_range(box.position.z + 1.0, box.end.z - 1.0))
			if not Nav.blocked(p):
				indoors.append(p)
	var stalls: Array = []
	for v in DB.VENDORS:
		if not v.get("indoor", false) and v.pos.y < 1.0:
			var p: Vector3 = Nav.nearest_free(v.pos + Vector3(1.4, 0, -1.2), 3.0)
			if not Nav.blocked(p):
				stalls.append(Vector3(p.x, 0.0, p.z))
	var built := 0
	var tries := 0
	while built < ROUNDS and tries < ROUNDS * 3:
		tries += 1
		var beach := rng.randf() < 0.45
		var x0 := rng.randf_range(-270.0, 270.0)
		var stops: Array = []
		for k in rng.randi_range(3, 4):
			var roll := rng.randf()
			var x := x0 + rng.randf_range(-45.0, 45.0)
			var p: Vector3
			var pose := 0
			if beach:
				if roll < 0.3:
					# Down to the water for a look at it.
					p = Vector3(x, 0, rng.randf_range(-35.0, -31.0))
					pose = [Kit.LOOK, Kit.PHOTO, Kit.STRETCH, Kit.STAND][rng.randi() % 4]
				elif roll < 0.55:
					# Over the sea wall, where the view is.
					p = Vector3(x, 0, rng.randf_range(41.2, 42.2))
					pose = [Kit.SELFIE, Kit.PHOTO, Kit.LOOK, Kit.SMOKE, Kit.PHONE][rng.randi() % 5]
				else:
					p = Vector3(x, 0, rng.randf_range(43.0, 49.5))
					pose = [Kit.PHONE, Kit.STAND, Kit.DRINK, Kit.YAWN, Kit.CALL, Kit.TIE][rng.randi() % 6]
			elif roll < 0.5 and not indoors.is_empty():
				p = indoors[rng.randi() % indoors.size()]
				pose = [Kit.STAND, Kit.DRINK, Kit.LOOK, Kit.PHONE, Kit.TALK][rng.randi() % 5]
			elif roll < 0.75:
				p = Vector3(x, 0, rng.randf_range(70.8, 72.2))
				pose = [Kit.PHONE, Kit.SMOKE, Kit.STAND, Kit.CALL, Kit.LOOK][rng.randi() % 5]
			else:
				p = Vector3(x, 0, rng.randf_range(101.5, 107.0))
				pose = [Kit.SMOKE, Kit.PHONE, Kit.STAND, Kit.STRETCH][rng.randi() % 4]
			if beach and roll > 0.8 and not stalls.is_empty():
				# Something cold from whoever is selling it.
				var best: Vector3 = stalls[0]
				for q in stalls:
					if q.z < Layout.ROAD_Z and absf(q.x - x) < absf(best.x - x):
						best = q
				if best.z < Layout.ROAD_Z:
					p = best
					pose = Kit.DRINK
			# Not so far along the street that it is a day's walk.
			if absf(p.x - x0) > 90.0:
				continue
			p = Nav.nearest_free(Vector3(clampf(p.x, -292.0, 292.0), 0, p.z))
			if not Nav.blocked(p):
				stops.append([p, rng.randf_range(4.0, 11.0), pose])
		if stops.size() < 3:
			continue
		# String the legs together, there and round and back to the start.
		var pts := PackedVector3Array([stops[0][0]])
		var marks: Array = []
		var far := 0.0
		var ok := true
		for k in stops.size():
			var a: Vector3 = stops[k][0]
			var b: Vector3 = stops[(k + 1) % stops.size()][0]
			var leg := Nav.path(a, b)
			if leg.is_empty() or leg[leg.size() - 1].distance_to(b) > 1.0:
				ok = false
				break
			far += Nav.length(a, leg)
			pts.append_array(leg)
			var next: Array = stops[(k + 1) % stops.size()]
			marks.append([far, next[1], next[2]])
		if not ok or far < 30.0:
			continue
		_rounds.append({"pts": pts, "stops": marks, "far": far})
		built += 1
	if _rounds.is_empty():
		return
	# Hand them to the strollers of the promenade and the pavements, a few to each.
	var taken := 0
	var rest := PackedInt32Array()
	for i in _walkers:
		if taken < _rounds.size() * ROUND_SHARE and _home[i].z > Layout.PROM_Z and _home[i].y < 1.0 and _w_spd[i] < 2.5 and _w_pose[i] != Kit.STAGGER and DB.ARCHETYPES[arch[i]].id != "vendor":
			var r: Dictionary = _rounds[taken % _rounds.size()]
			# Each walks it at their own pace, so each has their own time round.
			var time: float = r.far / _w_spd[i]
			for stop in r.stops:
				time += stop[1]
			_round[i] = taken % _rounds.size()
			_w_cycle[i] = time
			_w_phase[i] = time * (float(taken / _rounds.size()) + rng.randf()) / ROUND_SHARE
			_home[i] = r.pts[0]
			_origin[i] = r.pts[0]
			_errands.append(i)
			taken += 1
		else:
			rest.append(i)
	_walkers = rest


## NPC i goes back to what they were doing when the day started, if they are where they
## were doing it: lying on the towel, or walking the same stretch of pavement.
func _resume(i: int) -> void:
	_idle[i] = Kit.STAND
	_gest[i] = 0
	var off := pos[i] - _origin[i]
	if _round[i] >= 0:
		if off.length() < 1.5:
			# Start the round again from the top.
			_home[i] = _origin[i]
			_walker[i] = 1
			_w_pause[i] = 0
			_w_phase[i] = fposmod(-MatchState.time, _w_cycle[i])
	elif _was[i] & 1:
		var along := off.dot(_w_dir[i])
		if absf(along) <= _w_len[i] * 0.5 and (off - _w_dir[i] * along).length() < 1.5:
			# Pick the lane up from where they are standing on it.
			_home[i] = _origin[i]
			_walker[i] = 1
			_w_pause[i] = 0
			_w_phase[i] = fposmod(along + _w_len[i] * 0.5 - _walk_time(i, MatchState.time) * _w_spd[i], 2.0 * _w_len[i])
	elif off.length() < 1.5:
		_home[i] = _origin[i]
		_lying[i] = 1 if _was[i] & 2 else 0
		_place(i, _home[i])


## The walking a stroller has done by match time t, with their stops taken out.
func _walk_time(i: int, t: float) -> float:
	if _w_stop[i] <= 0.0:
		return t
	var cyc := _w_cycle[i]
	var at := t + i * 7.31
	var k := floorf(at / cyc)
	var walk := cyc - _w_stop[i]
	return k * walk + minf(at - k * cyc, walk)


## What walker i stops to do the k-th time they stop.
func _pause_pose(i: int, k: int) -> int:
	var poses: Array = PAUSE_POSES
	return poses[absi(i * 7919 + k * 104729) % poses.size()]


## How someone stands once they have run far enough.
func _shaken_pose(i: int) -> int:
	var poses: Array = SHAKEN_POSES
	return poses[i * 31 % poses.size()]


## The corners to walk through from `from` to `to` without going through anything,
## starting with `from` itself.
func _walk_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	if Nav.clear(from, to):
		pts.append(to)
	else:
		pts.append_array(Nav.path(from, to))
	return pts


## The heavens opened at match time t0: most people out on the open sand run for the
## promenade. Every peer works this out for itself from the same crowd, so it is one message.
@rpc("authority", "call_remote", "reliable")
func cl_shelter(t0: float) -> void:
	for i in count:
		if state[i] != AMBIENT or _walker[i] == 1 or pos[i].y > 1.0 or pos[i].z > 38.0 or (i * 7919) % 100 >= 65:
			continue
		var to_z := 42.0 + (i * 31) % 80 * 0.1
		var to := Nav.nearest_free(Vector3(pos[i].x + ((i * 13) % 9 - 4) * 0.6, 0.0, to_z))
		_begin_run(i, PARADE, _walk_to(pos[i], to), t0, _tier[i])


@rpc("authority", "call_remote", "unreliable")
func cl_npc_pos(idx: PackedInt32Array, ps: PackedVector3Array) -> void:
	for k in mini(idx.size(), ps.size()):
		if idx[k] >= 0 and idx[k] < count and state[idx[k]] == HOSTILE:
			_hostile_target[idx[k]] = ps[k]


func snapshot() -> Array:
	return _changed.values()


func apply_snapshot(snap: Array) -> void:
	for e in snap:
		callv(e[0], e[1])
		var i: int = e[1][0]
		if e[0] == "cl_npc" and (e[1][1] == DEAD or e[1][1] == KO):
			# Went down before we joined: already on the ground, not falling over now.
			_pose_t[i] = Kit.now() - 5.0
			_restyle(i)


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
	var d := dir.normalized()
	var from := Nav.nearest_free(pos[i])
	var to := from + d * dist
	# As far that way as the street allows; round whatever is in the way if it is something small.
	if not Nav.clear(from, to):
		var open := Nav.free_run(from, d, dist)
		to = Nav.nearest_free(to) if open < dist * 0.5 else from + d * maxf(open - 0.5, 0.5)
	Net.game.bcast("cl_run", [i, PARADE, _walk_to(from, to), MatchState.time, flags], self)


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


## NPC i runs from `threat`: out of the door if they are indoors and have the nerve, then
## as far as it takes. `vanish`: they are not seen again.
func _srv_flee(i: int, threat: Vector3, vanish := false, delay := 0.0) -> void:
	_hostile.erase(i)
	_calm.erase(i)
	_gawk.erase(i)
	var from := pos[i]
	var pts := PackedVector3Array([from])
	var room := Places.room_at(from)
	if room >= 0:
		var r: Dictionary = Places.rooms[room]
		var door: Array = []
		# The door to make for is the one that is not past whatever they are running from.
		for d in r.doors:
			if door.is_empty() or d[1].distance_to(from) - d[1].distance_to(threat) < door[1].distance_to(from) - door[1].distance_to(threat):
				door = d
		var way := PackedVector3Array()
		if not vanish and (r.get("kind", "") == "presidio" or door.is_empty() or randf() < 0.4):
			door = []
		else:
			way = Nav.path(from, door[1])
		if door.is_empty() or way.is_empty() or way[way.size() - 1].distance_to(door[1]) > 1.5:
			# Nowhere to run to: down on the floor until it is over.
			_cower[i] = MatchState.time + 20.0
			if state[i] != COWER:
				_srv_set(i, COWER)
			return
		pts.append_array(way)
		pts.append(door[0])
		from = door[0]
	pts.append_array(Nav.flee_path(from, threat, FLEE_DIST * randf_range(0.7, 1.25), i))
	if pts.size() < 2:
		if state[i] != COWER:
			_cower[i] = MatchState.time + 12.0
			_srv_set(i, COWER)
		return
	var flags: int = DB.wealth_tier(money[i]) | (NPC_VANISH if vanish else 0)
	var full: float = DB.ARCHETYPES[arch[i]].hp
	if hp[i] < full * 0.25:
		flags |= NPC_CRAWL
	elif hp[i] < full * 0.6:
		flags |= NPC_HURT
	Net.game.bcast("cl_run", [i, FLEE, pts, MatchState.time + delay, flags], self)


## NPC i stops what they are doing to stare at `at` in `pose` (filming it, pointing at it),
## or with on false gets on with their day.
@rpc("authority", "call_remote", "reliable")
func cl_gawk(i: int, at: Vector3, pose: int, on: bool) -> void:
	if i < 0 or i >= count or state[i] != AMBIENT:
		return
	if not on:
		_resume(i)
		_restyle(i)
		return
	_grp[i] = -1
	_sit[i] = 0
	_gest[i] = 0
	_walker[i] = 0
	_lying[i] = 0
	_w_pause[i] = 0
	_home[i] = pos[i]
	_idle[i] = pose
	var to := at - pos[i]
	if Vector2(to.x, to.z).length() > 0.1:
		_yaw[i] = Kit.face(to)
	_place(i, pos[i])
	_restyle(i)


## Something frightening has happened at `at`: a punch thrown, shots, a bomb. Everyone
## minding their own business within `radius` deals with it in their own way: most run, some
## freeze, some get a phone out to film it, and the hard cases come over. `pid` did it.
func srv_panic(at: Vector3, radius: float, level: int, pid: int, spread := true) -> void:
	var t := MatchState.time
	var who = Net.game.players.get(pid)
	var loved: bool = who != null and who.is_loved()
	var n := 0
	for i in count:
		if state[i] != AMBIENT or absf(pos[i].x - at.x) > radius or absf(pos[i].z - at.z) > radius or absf(pos[i].y - at.y) > 4.0:
			continue
		var d := pos[i].distance_to(at)
		if d > radius:
			continue
		var a = DB.ARCHETYPES[arch[i]]
		var nerve: float = a.fight
		var near := 1.0 - d / (radius * 1.3)
		# Asleep on a towel, it takes more to notice.
		if _lying[i] == 1 and level == FRIGHT_FIGHT and d > 6.0:
			continue
		if nerve > 0.5:
			# The ones who live by it do not run from it. Now and then one takes it personally.
			if level == FRIGHT_FIGHT and who != null and not loved and d < 9.0 and randf() < 0.12 and Places.room_at(pos[i]) < 0:
				_hostile[i] = {"target": pid, "cd": 0.8, "until": 14.0, "shooter": false}
				_srv_set(i, HOSTILE)
			elif level == FRIGHT_FIGHT and _grp[i] < 0 and randf() < 0.3 and not _gawk.has(i):
				_gawk[i] = t + GAWK_TIME
				Net.game.bcast("cl_gawk", [i, at, Kit.POINT if randf() < 0.5 else Kit.LOOK, true], self)
			continue
		if randf() > (1.02 - nerve) * (0.25 + near):
			continue
		# A scuffle is something to film from a safe distance. Gunfire is not.
		if level == FRIGHT_FIGHT and d > 7.0 and randf() < 0.3:
			if not _gawk.has(i):
				_gawk[i] = t + GAWK_TIME * randf_range(0.7, 1.4)
				Net.game.bcast("cl_gawk", [i, at, Kit.FILM if randf() < 0.7 else Kit.POINT, true], self)
			continue
		# It reaches the ones further off a moment later, and nobody reacts on the instant.
		_srv_flee(i, at, false, d / 28.0 + randf_range(0.08, 0.5))
		n += 1
		if n >= PANIC_MAX:
			break
	if spread and n > 3:
		# People who did not see it see everybody else running.
		_waves.append([t + 1.1, at, radius * 1.6, level, pid])


## Sends someone who ran back to where they started the day.
func _srv_go_home(i: int) -> void:
	if state[i] != AMBIENT or _grp[i] >= 0 or pos[i].distance_to(_origin[i]) < 2.0 or absf(pos[i].y - _origin[i].y) > 1.0:
		return
	var pts := _walk_to(pos[i], _origin[i])
	if pts[pts.size() - 1].distance_to(_origin[i]) > 2.0:
		return
	Net.game.bcast("cl_run", [i, PARADE, pts, MatchState.time, DB.wealth_tier(money[i]) | NPC_HOME], self)


func _srv_react(i: int, pid: int, threat: Vector3) -> void:
	var a = DB.ARCHETYPES[arch[i]]
	var who = Net.game.players.get(pid)
	# Nobody can stay angry at someone that happy.
	if randf() < a.fight and not (who != null and who.is_loved()):
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
		# The street plan says which corner to make for; the grid gets them there round the furniture.
		var goal: Vector3 = p.global_position
		var via: Vector3 = Places.route(pos[i], goal, Layout.next_point) if Places.room_at(pos[i]) >= 0 or Places.room_at(goal) >= 0 else Layout.next_point(pos[i], goal)
		via.y = pos[i].y
		step = Nav.steer(h, pos[i], via, h.get("speed", HOSTILE_SPEED) * delta, MatchState.time)
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
	elif h.get("mug", false) and d < 1.8 and dy < 2.0:
		# Not here to fight: one shove, a hand in the pocket, and away.
		_hostile.erase(i)
		g.threats.srv_mugged(i, h.target)
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


## Every NPC of archetype `kind` within r of `at` goes for player `pid`, guns out if they have them.
func srv_alarm(kind: String, at: Vector3, r: float, pid: int) -> void:
	var a := _arch_index(kind)
	for i in count:
		if arch[i] == a and state[i] == AMBIENT and pos[i].distance_to(at) < r:
			_hostile[i] = {"target": pid, "cd": 0.6, "until": 40.0, "shooter": randf() < DB.ARCHETYPES[a].shoot}
			_srv_set(i, HOSTILE)


## Did anyone of archetype `kind` within r of `at` see what `pid` just did? The nearest one
## who did comes over to deal with it.
func srv_witness(kind: String, at: Vector3, r: float, pid: int) -> bool:
	var a := _arch_index(kind)
	var best := -1
	var best_d := r
	for i in count:
		if arch[i] == a and state[i] == AMBIENT and pos[i].distance_to(at) < best_d:
			best = i
			best_d = pos[i].distance_to(at)
	if best < 0:
		return false
	_hostile[best] = {"target": pid, "cd": 0.6, "until": 8.0, "shooter": false}
	_srv_set(best, HOSTILE)
	return true


## Sends NPC i after a player to take their money off them rather than to hurt them.
func srv_mug(i: int, pid: int, speed: float) -> void:
	if i < 0 or i >= count or state[i] != AMBIENT:
		return
	_hostile[i] = {"target": pid, "cd": 0.2, "until": 12.0, "shooter": false, "mug": true, "speed": speed}
	_srv_set(i, HOSTILE)


## Mugger i has what he came for: he and anyone else on the job with him run for it.
func srv_scatter(i: int, from: Vector3) -> void:
	for j in _hostile.keys():
		if _hostile[j].get("mug", false):
			_hostile.erase(j)
			_srv_flee(j, from, true)
	if state[i] == HOSTILE:
		_srv_flee(i, from, true)


## Gunfire: anyone near who is the running kind, runs. The ones who live by it stay put.
func _on_noise(p: Vector3, radius: float, pid: int) -> void:
	if radius < 80.0 or MatchState.time < _panic_ok:
		return
	_panic_ok = MatchState.time + 1.5
	srv_panic(p, PANIC_RANGE if radius < 140.0 else BLAST_RANGE, FRIGHT_SHOTS if radius < 140.0 else FRIGHT_BLAST, pid)


## Somebody has been hit at `at` by `pid`, with a fist or a blade: the people round about see it.
func srv_fight_seen(at: Vector3, pid: int) -> void:
	if MatchState.time < _fight_ok:
		return
	_fight_ok = MatchState.time + 0.6
	srv_panic(at, FIGHT_RANGE, FRIGHT_FIGHT, pid)


## A crime with people about: now and then one of them gets a phone out. Unless something
## stops them, the police hear where it happened and what you look like.
func _on_crime(p: Vector3, pid: int, severity: int) -> void:
	var g = Net.game
	if MatchState.time < _call_ok or not g.players.has(pid):
		return
	for i in count:
		if state[i] != AMBIENT or _lying[i] == 1 or _calls.has(i) or DB.ARCHETYPES[arch[i]].fight > 0.5:
			continue
		var d := pos[i].distance_to(p)
		if d < 3.0 or d > CALL_RANGE:
			continue
		_call_ok = MatchState.time + 6.0
		if randf() < CALL_CHANCE:
			_calls[i] = [MatchState.time + CALL_TIME, p, pid, severity]
			g.bcast("cl_call", [i, true], self)
			g.send(pid, "cl_toast", ["Someone is calling the police!"])
		return


## NPC i gets their phone out to ring the police, or puts it away again.
@rpc("authority", "call_remote", "reliable")
func cl_call(i: int, on: bool) -> void:
	if i < 0 or i >= count or state[i] != AMBIENT:
		return
	_grp[i] = -1
	_sit[i] = 0
	_walker[i] = 0
	_home[i] = pos[i]
	_idle[i] = Kit.CALL if on else Kit.STAND
	_restyle(i)


## Someone sitting down or busy with a phone within arm's reach of a passing bike, or -1.
func pick_snatch(p: Vector3, fwd: Vector3) -> int:
	var best := -1
	var best_d := SNATCH_RANGE
	for i in near:
		if state[i] != AMBIENT or not (_sit[i] == 1 or _idle[i] == Kit.SELFIE or _idle[i] == Kit.PHONE or _idle[i] == Kit.CALL):
			continue
		var to := pos[i] - p
		to.y = 0.0
		var d := to.length()
		if d < best_d and to.dot(fwd) > -0.5 * d:
			best = i
			best_d = d
	return best


## A rider reaching out as they pass. Faster is cleaner; fumble it and you may come off.
@rpc("any_peer", "call_remote", "reliable")
func srv_snatch(i: int) -> void:
	var pid := Net.sender()
	var g = Net.game
	var p = g.players.get(pid)
	if p == null or not p.at_large() or g.motos.bike_of(pid) < 0 or i < 0 or i >= count or state[i] != AMBIENT:
		return
	if pos[i].distance_to(p.global_position) > SNATCH_RANGE + 3.0:
		return
	var speed: float = p.ground_speed()
	Crime.report_crime(pos[i], pid, 1)
	if randf() > clampf(0.35 + speed / 40.0, 0.35, 0.9):
		g.send(pid, "cl_toast", ["Fumbled it!"])
		if randf() < 0.15:
			g.motos.srv_release(pid)
			g.srv_floor(pid, 1.2)
		_srv_react(i, pid, p.global_position)
		return
	var msg := ""
	if _idle[i] == Kit.SELFIE or _idle[i] == Kit.PHONE or _idle[i] == Kit.CALL or _idle[i] == Kit.SIT_PHONE:
		g._give(p.st, "phone", 1)
		msg = "Snatched a %s" % DB.ITEMS["phone"].name
	elif _tier[i] == 2:
		g._give(p.st, "chain", 1)
		msg = "Snatched a %s" % DB.ITEMS["chain"].name
	else:
		var cash := int(money[i] * 0.3)
		money[i] -= cash
		p.st.money += cash
		msg = "Snatched R$%d" % cash
	g.push_state(p)
	g.send(pid, "cl_toast", [msg])
	g.send(pid, "cl_sound", ["cash", pos[i]])
	_calls.erase(i)
	_srv_flee(i, p.global_position)


## Makes an NPC who was minding their own business go after a player, if they are the type.
func srv_provoke(i: int, pid: int) -> void:
	if i < 0 or i >= count or state[i] != AMBIENT or DB.ARCHETYPES[arch[i]].fight <= 0.0:
		return
	_hostile[i] = {"target": pid, "cd": 0.8, "until": 15.0, "shooter": false}
	_srv_set(i, HOSTILE)


## Hurts NPC i. `ko` says the blow can knock them out: to the head it may, and one that would
## have killed with bare hands always does instead. Returns whether they went out cold.
func srv_damage_npc(i: int, dmg: float, attacker: int, zone := 0, ko := false) -> bool:
	if i < 0 or i >= count or state[i] >= DEAD:
		return false
	var g = Net.game
	for pid in _rob.keys():
		if _rob[pid].npc == i:
			_rob.erase(pid)
	if ko and state[i] != KO and ((zone == DB.ZONE_HEAD and randf() < DB.KO_CHANCE) or hp[i] - dmg <= 0.0):
		hp[i] = maxf(hp[i] - dmg, 5.0)
		_hostile.erase(i)
		_ko[i] = [MatchState.time + DB.KO_NPC, attacker]
		_srv_set(i, KO)
		g.bcast("cl_ko", [pos[i] + Vector3(0, 0.7, 0), DB.KO_NPC])
		return true
	hp[i] -= dmg
	if hp[i] <= 0.0:
		_hostile.erase(i)
		_ko.erase(i)
		_srv_set(i, DEAD)
		# A killing is seen from further off than a scuffle.
		srv_panic(pos[i], 24.0, FRIGHT_SHOTS, attacker)
		_bodies.append(pos[i])
		if _bodies.size() > 24:
			_bodies.pop_front()
		if money[i] > 0:
			g.srv_add_drop(pos[i], money[i], {})
			money[i] = 0
	elif state[i] != HOSTILE and state[i] != KO:
		var p = g.players.get(attacker)
		_srv_react(i, attacker, p.global_position if p != null else pos[i])
	return false


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
		if state[i] != AMBIENT and state[i] != KO:
			return
		if r != null:
			_srv_rob_abort(pid)
		# Someone asleep on a towel can be robbed without a word, if you keep it that way.
		# Someone out cold can be robbed however loud you like.
		var out := state[i] == KO
		r = {"npc": i, "meter": 0.0, "quiet": 0.0, "last": 0.0, "crime": 0.0, "out": out, "pick": out or (is_lying(i) and loud < PICK_LOUD)}
		_rob[pid] = r
		if not r.pick:
			_srv_set(i, COWER)
	elif state[i] != (KO if r.out else (AMBIENT if r.pick else COWER)):
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
	r.crime -= ROB_TICK
	if r.crime <= 0.0:
		r.crime = ROB_CRIME_EVERY
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
			g._give(p.st, "pistol", 1)
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
	if r.out:
		r.meter += ROB_TICK / PICK_TIME_KO
		if r.meter >= 1.0:
			_rob.erase(pid)
			_srv_strip(pid, p, i)
		else:
			g.send(pid, "cl_rob_meter", [r.meter])
		return
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


## Everything NPC i has on them goes to player p: cash, whatever they were wearing, maybe a gun.
func _srv_strip(pid: int, p, i: int) -> void:
	var g = Net.game
	var a = DB.ARCHETYPES[arch[i]]
	var cash := money[i]
	var tier := DB.wealth_tier(cash)
	money[i] = 0
	p.st.money += cash
	var msg := "Took R$%d" % cash
	var loot := ""
	if _look[i] & Kit.F_CAMERA:
		loot = "camera"
	elif tier == 2:
		loot = "chain"
	elif tier >= 1:
		loot = "watch" if randf() < 0.5 else "phone"
	if loot != "":
		g._give(p.st, loot, 1)
		msg += " + %s" % DB.ITEMS[loot].name
	if randf() < a.gun:
		g._give(p.st, "pistol", 1)
		p.st.ammo += 6
		msg += " + a pistol"
	g.push_state(p)
	g.send(pid, "cl_toast", [msg])
	g.send(pid, "cl_rob_meter", [0.0])
	g.send(pid, "cl_sound", ["cash", pos[i]])
	# Pockets turned out for all to see; still out cold.
	_srv_set(i, KO)


func _srv_rob_abort(pid: int) -> void:
	var r = _rob.get(pid)
	_rob.erase(pid)
	if r == null or state[r.npc] != COWER:
		return
	var p = Net.game.players.get(pid)
	_srv_flee(r.npc, p.global_position if p != null else pos[r.npc])


# --- debug ---

## For tests: brings one plain local to stand at `at` and returns their index.
func debug_stand(at: Vector3, yaw: float) -> int:
	var i := 0
	while arch[i] != 1:
		i += 1
	state[i] = AMBIENT
	_walker[i] = 0
	_lying[i] = 0
	_idle[i] = Kit.STAND
	_grp[i] = -1
	_sit[i] = 0
	_home[i] = at
	_yaw[i] = yaw
	hp[i] = 60.0
	_place(i, at)
	_restyle(i)
	return i


## For tests: everybody goes home, so nothing but walls is in the way.
func debug_clear() -> void:
	for i in count:
		state[i] = GONE
		_hide(i)


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
	cl_run(runner, FLEE, PackedVector3Array([back + Vector3(6.5 - FLEE_SPEED * 3.9, 0, 0), back + Vector3(60, 0, 0)]), MatchState.time, 0)


## Stands NPC i at `at` in `pose`, for looking at. `lively`: as the one doing the talking.
func debug_pose(i: int, at: Vector3, yaw: float, pose: int, lively := false) -> void:
	state[i] = AMBIENT
	_walker[i] = 0
	_lying[i] = 0
	_grp[i] = -1
	_sit[i] = 0
	_gest[i] = 1 if lively else 0
	_idle[i] = pose
	_yaw[i] = yaw
	_home[i] = at
	_place(i, at)
	_restyle(i)


## Takes everybody off the beach except `keep`, for a picture of just them.
func debug_only(keep: Array) -> void:
	for i in count:
		if not keep.has(i):
			state[i] = GONE
			_hide(i)
