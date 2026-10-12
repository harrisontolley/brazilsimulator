extends Node3D
## The dogs: strays in packs on the sand, pets on leads, the gang's rottweiler on its corner.
##
## Unlike the crowd these have minds of their own, so the server runs them and sends where
## they are ten times a second, as it does for the police. Which dog is which (breed, coat,
## temper, where it lives) comes from the match seed, so that part costs nothing.
##
## One mesh and one MultiMesh for the lot: the shader (shaders/dog_pose.gdshaderinc) stretches
## the mesh into each breed and plays every animation.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Nav := preload("res://scenes/world/nav.gd")
const Places := preload("res://scenes/world/places.gd")

# Animations (shader A_*).
enum { STAND, TROT, RUN, SIT, LIE, SNIFF, BARK, GROWL, DIG, SCRATCH, PEE, BEG, COWER, DEAD, WAG }
# What a dog is doing.
enum { IDLE, WANDER, FOLLOW, BEGGING, FETCH, WARN, ATTACK, FLEE, HEEL, BARKING, HUNT, GONE }
# What kind of dog it is underneath.
enum { FRIENDLY, SKITTISH, AGGRESSIVE, GUARD, PET }

# Breeds (shader breed ids).
enum { CARAMELO, PITBULL, ROTTWEILER, PASTOR, LABRADOR, SALSICHA, PINSCHER, POODLE }

## size: how big against the model. speed: flat out, m/s. bite: damage. voice: which bark.
## coats: [coat, muzzle/ears/saddle, paws/chest/tail tip] to pick from.
const BREEDS := [
	{"name": "vira-lata caramelo", "size": 1.0, "speed": 6.6, "hp": 45.0, "bite": 9.0, "voice": 1, "coats": [
		[Color(0.8, 0.56, 0.28), Color(0.5, 0.33, 0.15), Color(0.86, 0.66, 0.4)],
		[Color(0.7, 0.45, 0.2), Color(0.3, 0.2, 0.12), Color(0.95, 0.9, 0.8)],
		[Color(0.35, 0.25, 0.18), Color(0.2, 0.15, 0.1), Color(0.8, 0.56, 0.28)],
		[Color(0.9, 0.85, 0.75), Color(0.8, 0.56, 0.28), Color(0.9, 0.85, 0.75)]]},
	{"name": "pitbull", "size": 1.0, "speed": 7.4, "hp": 85.0, "bite": 18.0, "voice": 2, "coats": [
		[Color(0.45, 0.47, 0.52), Color(0.38, 0.4, 0.45), Color(0.95, 0.95, 0.95)],
		[Color(0.6, 0.4, 0.25), Color(0.35, 0.22, 0.14), Color(0.95, 0.93, 0.9)],
		[Color(0.93, 0.92, 0.9), Color(0.5, 0.35, 0.25), Color(0.93, 0.92, 0.9)]]},
	{"name": "rottweiler", "size": 1.2, "speed": 6.8, "hp": 110.0, "bite": 22.0, "voice": 2, "coats": [
		[Color(0.09, 0.08, 0.08), Color(0.6, 0.35, 0.15), Color(0.6, 0.35, 0.15)]]},
	{"name": "pastor alemão", "size": 1.2, "speed": 7.8, "hp": 90.0, "bite": 18.0, "voice": 2, "coats": [
		[Color(0.72, 0.52, 0.28), Color(0.1, 0.08, 0.07), Color(0.72, 0.52, 0.28)]]},
	{"name": "labrador", "size": 1.1, "speed": 6.8, "hp": 70.0, "bite": 10.0, "voice": 1, "coats": [
		[Color(0.92, 0.82, 0.55), Color(0.85, 0.72, 0.45), Color(0.92, 0.82, 0.55)],
		[Color(0.12, 0.1, 0.09), Color(0.1, 0.08, 0.08), Color(0.12, 0.1, 0.09)],
		[Color(0.42, 0.26, 0.15), Color(0.35, 0.2, 0.12), Color(0.42, 0.26, 0.15)]]},
	{"name": "salsicha", "size": 0.75, "speed": 4.6, "hp": 30.0, "bite": 5.0, "voice": 0, "coats": [
		[Color(0.5, 0.26, 0.12), Color(0.38, 0.18, 0.08), Color(0.5, 0.26, 0.12)],
		[Color(0.1, 0.08, 0.08), Color(0.55, 0.32, 0.15), Color(0.55, 0.32, 0.15)]]},
	{"name": "pinscher", "size": 0.55, "speed": 6.2, "hp": 18.0, "bite": 4.0, "voice": 0, "coats": [
		[Color(0.1, 0.08, 0.08), Color(0.6, 0.35, 0.15), Color(0.6, 0.35, 0.15)],
		[Color(0.6, 0.33, 0.15), Color(0.45, 0.24, 0.1), Color(0.6, 0.33, 0.15)]]},
	{"name": "poodle", "size": 0.7, "speed": 5.2, "hp": 25.0, "bite": 4.0, "voice": 0, "coats": [
		[Color(0.96, 0.95, 0.93), Color(0.9, 0.88, 0.86), Color(0.96, 0.95, 0.93)],
		[Color(0.2, 0.2, 0.22), Color(0.14, 0.14, 0.16), Color(0.2, 0.2, 0.22)],
		[Color(0.85, 0.65, 0.45), Color(0.75, 0.55, 0.38), Color(0.85, 0.65, 0.45)]]},
]

## How near a stranger can come before a guard dog says so, and before it stops saying.
const WARN_R := 8.5
const BITE_R := 1.3
const BITE_EVERY := 1.1
## How far from its post a guard dog will go after someone.
const GUARD_LEASH := 24.0
const STATE_LEAD := 16   # cl_dogs state bit: on a lead

var dogs: Array = []
## Where each dog is, for anyone who needs to look (both ends of the wire).
var pos := PackedVector3Array()

var _mm: MultiMesh
var _leads: MultiMesh
var _mats: Array[ShaderMaterial] = []
var _target := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _yaw_to := PackedFloat32Array()
var _state := PackedByteArray()   # animation, plus STATE_LEAD
var _shown := PackedByteArray()   # animation last pushed to the shader
var _prev := PackedByteArray()
var _t0 := PackedFloat32Array()
var _ev := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _send_t := 0.0
var _think := 0
var _ball_was := PackedVector3Array()
var _crowd: Node3D


func setup(seed_value: int, crowd: Node3D) -> void:
	for c in get_children():
		c.queue_free()
	_crowd = crowd
	dogs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0xD06
	# Strays in packs on the sand: mostly wary of people, some anybody's friend.
	for pack in 3:
		var den := _open(Vector3(rng.randf_range(-250.0, 250.0), 0, rng.randf_range(-22.0, 28.0)), rng)
		for k in 3:
			_add(rng, CARAMELO, FRIENDLY if rng.randf() < 0.55 else SKITTISH, _open(den + Vector3(rng.randf_range(-5, 5), 0, rng.randf_range(-5, 5)), rng), 26.0)
	# Dogs that belong to nobody in particular and like everybody.
	for k in 4:
		_add(rng, LABRADOR if k < 3 else POODLE, FRIENDLY, _open(Vector3(rng.randf_range(-270.0, 270.0), 0, rng.randf_range(43.0, 49.0)), rng), 30.0)
	for k in 2:
		_add(rng, SALSICHA, SKITTISH, _open(Vector3(rng.randf_range(-270.0, 270.0), 0, rng.randf_range(102.0, 107.0)), rng), 22.0)
	# The ones to walk round.
	for breed in [PITBULL, PITBULL, PASTOR, PINSCHER, PINSCHER]:
		var at := Vector3(rng.randf_range(-280.0, 280.0), 0, rng.randf_range(101.5, 107.5) if rng.randf() < 0.6 else rng.randf_range(-25.0, 30.0))
		_add(rng, breed, AGGRESSIVE, _open(at, rng), 20.0)
	# The lads on the corner keep something with teeth, and so does the foot of every stair.
	if crowd.acts != null:
		for gi in crowd.acts.gangs:
			_add(rng, ROTTWEILER, GUARD, _open(crowd.acts.groups[gi].pos + Vector3(rng.randf_range(-2.5, 2.5), 0, 1.6), rng), 5.0)
	for k in 2:
		_add(rng, PITBULL, GUARD, _open(Vector3(Layout.STAIR_X[k] + (5.0 if k == 0 else -5.0), 0, 134.0), rng), 5.0)
	# And the ones on a lead, out for their walk.
	var owners: Array = crowd.pet_owners(6)
	for k in owners.size():
		var d := _add(rng, [POODLE, SALSICHA, LABRADOR, PINSCHER, POODLE, SALSICHA][k % 6], PET, crowd.pos[owners[k]], 6.0)
		d.owner = owners[k]
		d.state = HEEL

	var n := dogs.size()
	pos.resize(n)
	_target.resize(n)
	_yaw.resize(n)
	_yaw_to.resize(n)
	_state.resize(n)
	_shown.resize(n)
	_prev.resize(n)
	_t0.resize(n)
	_ev.resize(n)
	_speed.resize(n)
	_shown.fill(255)
	_prev.fill(STAND)
	_ev.fill(0.0)
	_build()
	for i in n:
		var d: Dictionary = dogs[i]
		pos[i] = d.pos
		_target[i] = d.pos
		_yaw[i] = d.yaw
		_yaw_to[i] = d.yaw
		_state[i] = d.anim | (STATE_LEAD if d.temper == PET else 0)
		_mm.set_instance_color(i, Color(d.coat[0].r, d.coat[0].g, d.coat[0].b, rng.randf()))
	if multiplayer.is_server() and not Crime.noise.is_connected(_on_noise):
		Crime.noise.connect(_on_noise)


func _open(p: Vector3, rng: RandomNumberGenerator) -> Vector3:
	p = Nav.nearest_free(Vector3(clampf(p.x, -290.0, 290.0), 0, p.z), 8.0)
	for tries in 6:
		if not Nav.blocked(p):
			break
		p = Vector3(rng.randf_range(-250.0, 250.0), 0, rng.randf_range(-20.0, 28.0))
	return p


func _add(rng: RandomNumberGenerator, breed: int, temper: int, at: Vector3, roam: float) -> Dictionary:
	var b: Dictionary = BREEDS[breed]
	var d := {"breed": breed, "temper": temper, "pos": at, "home": at, "roam": roam, "yaw": rng.randf() * TAU,
			"size": b.size * rng.randf_range(0.9, 1.1), "coat": b.coats[rng.randi() % b.coats.size()],
			"hp": b.hp, "state": IDLE, "anim": [SIT, LIE, STAND, SNIFF][rng.randi() % 4], "t": rng.randf_range(1.0, 8.0),
			"goal": at, "target": -1, "owner": -1, "nav": {}, "speed": 0.0, "cd": 0.0, "until": 0.0, "bored": 0.0,
			"voice_t": 0.0, "npc": -1}
	dogs.append(d)
	return d


func _build() -> void:
	var mesh := _mesh()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = dogs.size()
	_mats.clear()
	for k in 2:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/dog.gdshader" if k == 0 else "res://shaders/dog_outline.gdshader")
		_mats.append(mat)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _mm
		mmi.material_override = mat
		mmi.custom_aabb = Layout.WORLD_AABB
		# The body throws a shadow; the ink line round it does not need to.
		if k == 1:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	# A lead is a thin box from a hand to a collar.
	var strap := BoxMesh.new()
	strap.size = Vector3(0.025, 0.025, 1.0)
	_leads = MultiMesh.new()
	_leads.transform_format = MultiMesh.TRANSFORM_3D
	_leads.mesh = strap
	_leads.instance_count = dogs.size()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.1, 0.1)
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = _leads
	lmi.material_override = red
	lmi.custom_aabb = Layout.WORLD_AABB
	add_child(lmi)
	for i in dogs.size():
		_leads.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))


## The one dog every breed is made from: boxes, each tagged with the part it moves with
## (UV2.x) and whose colour it wears (UV2.y).
static func _mesh() -> ArrayMesh:
	# [centre, size, part, colour slot]
	var boxes := [
		[Vector3(0, 0.42, 0), Vector3(0.26, 0.26, 0.72), 0, 0],
		[Vector3(0, 0.34, -0.32), Vector3(0.2, 0.14, 0.1), 0, 2],
		[Vector3(0, 0.553, 0.03), Vector3(0.21, 0.02, 0.5), 0, 1],
		[Vector3(0, 0.5, -0.39), Vector3(0.17, 0.22, 0.16), 0, 0],
		[Vector3(0, 0.62, -0.5), Vector3(0.22, 0.2, 0.22), 1, 0],
		[Vector3(0, 0.585, -0.67), Vector3(0.115, 0.085, 0.14), 1, 1],
		[Vector3(0, 0.615, -0.745), Vector3(0.05, 0.04, 0.03), 1, 3],
		[Vector3(-0.072, 0.665, -0.612), Vector3(0.035, 0.04, 0.012), 1, 3],
		[Vector3(0.072, 0.665, -0.612), Vector3(0.035, 0.04, 0.012), 1, 3],
		[Vector3(0, 0.523, -0.655), Vector3(0.09, 0.03, 0.13), 2, 1],
		[Vector3(0, 0.54, -0.66), Vector3(0.06, 0.012, 0.1), 2, 4],
		[Vector3(-0.085, 0.755, -0.45), Vector3(0.06, 0.13, 0.04), 3, 1],
		[Vector3(0.085, 0.755, -0.45), Vector3(0.06, 0.13, 0.04), 4, 1],
		[Vector3(0, 0.5, 0.47), Vector3(0.05, 0.05, 0.28), 9, 0],
		[Vector3(0, 0.5, 0.635), Vector3(0.052, 0.052, 0.06), 9, 2],
	]
	for leg in [[-0.09, -0.27, 5], [0.09, -0.27, 6], [-0.09, 0.27, 7], [0.09, 0.27, 8]]:
		boxes.append([Vector3(leg[0], 0.175, leg[1]), Vector3(0.075, 0.25, 0.075), leg[2], 0])
		boxes.append([Vector3(leg[0], 0.03, leg[1] - 0.012), Vector3(0.08, 0.06, 0.1), leg[2], 2])
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var unit := BoxMesh.new()
	var src: Array = unit.get_mesh_arrays()
	var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	for b in boxes:
		var base := v.size()
		for k in sv.size():
			v.append(b[0] + sv[k] * b[1])
			n.append(sn[k])
			uv2.append(Vector2(b[2], b[3]))
		for k in src[Mesh.ARRAY_INDEX]:
			idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _pack(c: Color) -> int:
	return clampi(roundi(c.r * 15.0), 0, 15) | (clampi(roundi(c.g * 15.0), 0, 15) << 4) | (clampi(roundi(c.b * 15.0), 0, 15) << 8)


func _process(delta: float) -> void:
	if dogs.is_empty() or _mm == null:
		return
	var now := Kit.now()
	for m in _mats:
		m.set_shader_parameter("now", now)
	if multiplayer.is_server() and MatchState.running:
		_srv_tick(delta)
	for i in dogs.size():
		var d: Dictionary = dogs[i]
		pos[i] = pos[i].lerp(_target[i], minf(1.0, 12.0 * delta))
		_yaw[i] = lerp_angle(_yaw[i], _yaw_to[i], minf(1.0, 10.0 * delta))
		_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _yaw[i]).scaled(Vector3.ONE * d.size), pos[i]))
		var anim := _state[i] & 15
		if anim != _shown[i]:
			_prev[i] = _shown[i] if _shown[i] != 255 else anim
			_shown[i] = anim
			_t0[i] = now
		var speed := clampi(roundi(_speed[i] / d.size * 5.0), 0, 63)
		_mm.set_instance_custom_data(i, Color(anim | (d.breed << 4) | (_prev[i] << 8) | (speed << 12), _t0[i], _ev[i], _pack(d.coat[1]) | (_pack(d.coat[2]) << 12)))
		var lead := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0))
		if _state[i] & STATE_LEAD and d.owner >= 0 and _crowd.state[d.owner] < _crowd.DEAD:
			var hand: Vector3 = _crowd.pos[d.owner] + Basis(Vector3.UP, _crowd.yaw_of(d.owner)) * Vector3(0.26, 0.82, -0.05)
			var collar := pos[i] + Vector3(0, 0.5 * d.size, 0) + Basis(Vector3.UP, _yaw[i]) * Vector3(0, 0, -0.3 * d.size)
			if hand.distance_to(collar) > 0.05 and hand.distance_to(collar) < 4.0:
				lead = Transform3D(Basis.looking_at(collar - hand, Vector3.UP) * Basis.from_scale(Vector3(1, 1, hand.distance_to(collar))), (hand + collar) * 0.5)
		_leads.set_instance_transform(i, lead)


@rpc("authority", "call_remote", "unreliable")
func cl_dogs(ps: PackedVector3Array, yaws: PackedFloat32Array, states: PackedByteArray, speeds: PackedFloat32Array) -> void:
	if ps.size() == dogs.size() and yaws.size() == ps.size() and states.size() == ps.size() and speeds.size() == ps.size():
		_target = ps
		_yaw_to = yaws
		_state = states
		_speed = speeds


## Dog i snaps its jaws (attack) or yelps and flinches.
@rpc("authority", "call_remote", "unreliable")
func cl_dog_ev(i: int, attack: bool) -> void:
	fx_event(i, attack)


func fx_event(i: int, attack: bool) -> void:
	if i >= 0 and i < dogs.size():
		_ev[i] = Kit.now() if attack else -Kit.now()


# --- server ---

func _srv_tick(delta: float) -> void:
	var g = Net.game
	var n := dogs.size()
	# Each dog has a proper look round a few times a second, a few dogs a frame.
	for k in 3:
		_think = (_think + 1) % n
		_srv_look(dogs[_think], _think)
	if g.balls != null and _ball_was.size() != g.balls.pos.size():
		_ball_was = g.balls.pos.duplicate()
	for i in n:
		var d: Dictionary = dogs[i]
		d.cd -= delta
		d.t -= delta
		d.bored -= delta
		d.voice_t -= delta
		_srv_act(d, i, delta)
		_target[i] = d.pos
		_yaw_to[i] = d.yaw
		_state[i] = d.anim | (STATE_LEAD if d.state == HEEL else 0)
		_speed[i] = d.speed
	if g.balls != null:
		_ball_was = g.balls.pos.duplicate()
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		for pid in g.ready_peers:
			if pid != 1:
				cl_dogs.rpc_id(pid, _target, _yaw_to, _state, _speed)


## The nearest player a dog would take notice of: [pid, distance], pid -1 if nobody.
func _nearest(d: Dictionary) -> Array:
	var best := -1
	var best_d := INF
	for pid in Net.game.players:
		var p = Net.game.players[pid]
		if p.st.dead or not p.at_large() or absf(p.global_position.y - d.pos.y) > 2.5:
			continue
		var dist: float = Vector2(p.global_position.x - d.pos.x, p.global_position.z - d.pos.z).length()
		if dist < best_d:
			best = pid
			best_d = dist
	return [best, best_d]


func _say(d: Dictionary, sound: String, every: float, db := 0.0) -> void:
	if d.voice_t > 0.0:
		return
	d.voice_t = every * randf_range(0.8, 1.3)
	Net.game.bcast("cl_sound", [sound, d.pos + Vector3(0, 0.4, 0)])


func _bark(d: Dictionary, every := 0.4) -> void:
	_say(d, "bark%d" % BREEDS[d.breed].voice, every)


func _idle(d: Dictionary, seconds := -1.0) -> void:
	d.state = IDLE
	d.target = -1
	d.npc = -1
	d.speed = 0.0
	d.t = seconds if seconds > 0.0 else randf_range(3.0, 12.0)
	var on_sand: bool = d.pos.z < Layout.PROM_Z
	var roll := randf()
	if d.temper == GUARD or d.temper == AGGRESSIVE:
		d.anim = SIT if roll < 0.4 else (LIE if roll < 0.7 else STAND)
	elif roll < 0.22:
		d.anim = SIT
	elif roll < 0.42:
		d.anim = LIE
	elif roll < 0.58:
		d.anim = SNIFF
	elif roll < 0.68:
		d.anim = SCRATCH
	elif roll < 0.76:
		d.anim = DIG if on_sand else SNIFF
	elif roll < 0.82:
		d.anim = PEE
	else:
		d.anim = STAND


func _wander(d: Dictionary) -> void:
	var a := randf() * TAU
	var goal: Vector3 = d.home + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, d.roam)
	goal.x = clampf(goal.x, -292.0, 292.0)
	goal.y = 0.0
	if Nav.blocked(goal) or Places.room_at(goal) >= 0 or (goal.z > Layout.ROAD_Z and goal.z < Layout.WALK_Z):
		# Not into a shop, and not out into the traffic.
		_idle(d, 1.0)
		return
	d.state = WANDER
	d.goal = goal
	d.t = 30.0
	d.nav = {}
	d["pace"] = randf_range(1.5, 2.6) if randf() < 0.75 else 0.8


func _flee(d: Dictionary, from: Vector3, far := 20.0) -> void:
	var way := Nav.flee_path(d.pos, from, far * randf_range(0.8, 1.3), dogs.find(d))
	if way.is_empty():
		d.state = IDLE
		d.anim = COWER
		d.t = 4.0
		return
	d.state = FLEE
	d.goal = way[way.size() - 1]
	d.t = 8.0
	d.nav = {}
	d.target = -1


## Dog `d` takes stock of what is going on round it and may change its mind about what to do.
func _srv_look(d: Dictionary, i: int) -> void:
	if d.state == GONE or d.state == FLEE or d.state == ATTACK:
		return
	var g = Net.game
	if d.state == HEEL:
		return
	var who: Array = _nearest(d)
	var pid: int = who[0]
	var dist: float = who[1]
	var p = g.players.get(pid)
	var quick: bool = p != null and Vector2(p.velocity.x, p.velocity.z).length() > 5.5
	match d.temper:
		SKITTISH:
			if p != null and dist < (9.0 if quick else 4.5):
				_say(d, "whine", 2.0)
				_flee(d, p.global_position)
				return
		FRIENDLY:
			if p != null and dist < 6.0 and d.bored <= 0.0 and (d.state == IDLE or d.state == WANDER) and randf() < 0.5:
				d.state = FOLLOW
				d.target = pid
				d.t = randf_range(10.0, 26.0)
				d.nav = {}
				_bark(d)
				return
		AGGRESSIVE, GUARD:
			var from_post: float = d.pos.distance_to(d.home)
			if p != null and not p.is_loved() and dist < WARN_R and d.state != WARN and (d.temper == AGGRESSIVE or from_post < 14.0) and d.bored <= 0.0:
				d.state = WARN
				d.target = pid
				d.t = 2.4 if not quick else 0.6
				d.anim = GROWL
				d.speed = 0.0
				return
	if d.state != IDLE and d.state != WANDER:
		return
	# Things worth barking at: a policeman in a hurry, somebody running for their life.
	for c in g.police.cops:
		if c.state == g.police.CHASE and c.pos.distance_to(d.pos) < 10.0 and d.bored <= 0.0:
			d.state = BARKING
			d.goal = c.pos
			d.t = 2.5
			d.bored = 12.0
			return
	if d.temper != SKITTISH and d.bored <= 0.0:
		var runner: int = _crowd.fleeing_near(d.pos, 8.0)
		if runner >= 0:
			d.state = HUNT
			d.npc = runner
			d.t = randf_range(3.0, 5.0)
			d.bored = 15.0
			d.nav = {}
			return
	# Another dog too close to one that does not share.
	if (d.temper == AGGRESSIVE or d.temper == GUARD) and d.bored <= 0.0:
		for o in dogs:
			if o != d and o.state != GONE and o.pos.distance_to(d.pos) < 3.5:
				d.state = BARKING
				d.goal = o.pos
				d.t = 2.5
				d.bored = 20.0
				if o.temper != AGGRESSIVE and o.temper != GUARD and o.state != HEEL:
					_flee(o, d.pos, 12.0)
				return
	# A ball going past is not something a dog can leave alone.
	if d.temper == FRIENDLY and d.bored <= 0.0 and g.balls != null:
		for b in mini(g.balls.pos.size(), _ball_was.size()):
			var bp: Vector3 = g.balls.pos[b]
			if bp.distance_to(d.pos) < 14.0 and bp.distance_to(_ball_was[b]) > 0.03 and absf(bp.y - d.pos.y) < 3.0:
				d.state = FETCH
				d["ball"] = b
				d.t = 6.0
				d.bored = 10.0
				d.nav = {}
				return
	# Somebody eating is always worth a try.
	if d.temper == FRIENDLY and d.bored <= 0.0 and randf() < 0.08 and _crowd.acts != null:
		for grp in _crowd.acts.groups:
			if grp.has("grill") and grp.pos.distance_to(d.pos) < 40.0:
				var spot: Vector3 = Nav.nearest_free(grp.pos + Vector3(randf_range(-1.5, 1.5), 0, -2.6))
				d.state = WANDER
				d.goal = spot
				d.t = 30.0
				d.nav = {}
				d["pace"] = 2.4
				d["beg"] = grp.pos
				d.bored = 60.0
				return


func _go(d: Dictionary, goal: Vector3, speed: float, delta: float) -> float:
	var to: Vector3 = Nav.steer(d.nav, d.pos, Vector3(goal.x, d.pos.y, goal.z), speed * delta, MatchState.time) - d.pos
	to.y = 0.0
	if to.length() > 0.0005:
		d.pos += to
		d.yaw = lerp_angle(d.yaw, Kit.face(to), minf(1.0, 9.0 * delta))
	d.speed = speed if to.length() > 0.0005 else 0.0
	d.anim = RUN if d.speed > 3.4 else (TROT if d.speed > 0.1 else STAND)
	return Vector2(goal.x - d.pos.x, goal.z - d.pos.z).length()


func _face(d: Dictionary, at: Vector3, delta: float) -> void:
	var to: Vector3 = at - d.pos
	to.y = 0.0
	if to.length() > 0.05:
		d.yaw = lerp_angle(d.yaw, Kit.face(to), minf(1.0, 8.0 * delta))


func _srv_act(d: Dictionary, i: int, delta: float) -> void:
	var g = Net.game
	var breed: Dictionary = BREEDS[d.breed]
	match d.state:
		GONE:
			return
		IDLE:
			d.speed = 0.0
			if d.t <= 0.0:
				_wander(d)
		WANDER:
			var pace: float = d.get("pace", 2.0)
			var left := _go(d, d.goal, pace, delta)
			if pace < 1.2 and d.speed > 0.0:
				d.anim = SNIFF
			if left < 0.6 or d.t <= 0.0 or d.speed == 0.0:
				if d.has("beg"):
					d.state = BEGGING
					d.goal = d.beg
					d.erase("beg")
					d.t = randf_range(7.0, 14.0)
				else:
					_idle(d)
		BEGGING:
			d.speed = 0.0
			_face(d, d.goal, delta)
			d.anim = BEG if fmod(d.t, 5.0) < 2.5 else SIT
			if fmod(d.t, 5.0) > 4.6:
				_say(d, "whine", 3.0)
			if d.t <= 0.0:
				_idle(d)
		FOLLOW:
			var p = g.players.get(d.target)
			if p == null or p.st.dead or not p.at_large() or d.t <= 0.0:
				d.bored = 30.0
				_idle(d)
				return
			var at: Vector3 = p.global_position
			var dist := Vector2(at.x - d.pos.x, at.z - d.pos.z).length()
			if dist > 40.0 or absf(at.y - d.pos.y) > 3.0:
				d.bored = 20.0
				_idle(d)
			elif dist > 2.4:
				_go(d, at, clampf(dist * 0.9, 2.2, breed.speed), delta)
			else:
				d.speed = 0.0
				_face(d, at, delta)
				d.anim = WAG if Vector2(p.velocity.x, p.velocity.z).length() < 1.0 else STAND
				if randf() < delta * 0.25:
					_bark(d)
		FETCH:
			var b: int = d.get("ball", 0)
			if g.balls == null or b >= g.balls.pos.size() or d.t <= 0.0:
				_idle(d)
				return
			var left := _go(d, g.balls.pos[b], breed.speed, delta)
			if left < 0.9:
				_bark(d)
				d.state = IDLE
				d.anim = WAG
				d.speed = 0.0
				d.t = 2.5
		BARKING:
			d.speed = 0.0
			d.anim = BARK
			_face(d, d.goal, delta)
			_bark(d)
			if d.t <= 0.0:
				_idle(d)
		HUNT:
			# Running alongside somebody who is running, shouting at them.
			if d.npc < 0 or _crowd.state[d.npc] != _crowd.FLEE or d.t <= 0.0:
				_idle(d, 2.0)
				return
			var at: Vector3 = _crowd.pos[d.npc]
			if absf(at.y - d.pos.y) > 2.0:
				_idle(d, 2.0)
				return
			_go(d, at + Vector3(0.9, 0, 0.4), breed.speed * 0.9, delta)
			_bark(d, 0.5)
		WARN:
			var p = g.players.get(d.target)
			if p == null or p.st.dead or not p.at_large():
				_idle(d)
				return
			var at: Vector3 = p.global_position
			var dist := Vector2(at.x - d.pos.x, at.z - d.pos.z).length()
			d.speed = 0.0
			d.anim = GROWL
			_face(d, at, delta)
			_say(d, "growl", 1.2)
			if dist < 3.6 or (d.t <= 0.0 and dist < WARN_R):
				d.state = ATTACK
				d.until = 12.0
				d.nav = {}
				_bark(d)
			elif dist > WARN_R + 3.0:
				# Seen off. A few barks after them to make the point.
				d.state = BARKING
				d.goal = at
				d.t = 2.0
				d.bored = 3.0
		ATTACK:
			var p = g.players.get(d.target)
			d.until -= delta
			if p == null or p.st.dead or not p.at_large() or p.is_loved() or d.until <= 0.0:
				d.bored = 8.0
				_idle(d, 2.0)
				return
			var at: Vector3 = p.global_position
			var dist := Vector2(at.x - d.pos.x, at.z - d.pos.z).length()
			if dist > 30.0 or (d.temper == GUARD and d.pos.distance_to(d.home) > GUARD_LEASH) or absf(at.y - d.pos.y) > 2.2:
				# Off its patch, or up somewhere a dog cannot follow: back to the post, grumbling.
				d.bored = 6.0
				d.state = WANDER
				d.goal = d.home
				d.t = 20.0
				d.nav = {}
				d["pace"] = 2.6
				return
			if dist > BITE_R * 0.8:
				_go(d, at, breed.speed, delta)
			else:
				d.speed = 0.0
				_face(d, at, delta)
				d.anim = GROWL
			if dist < BITE_R and d.cd <= 0.0:
				d.cd = BITE_EVERY
				g.bcast("cl_dog_ev", [i, true], self)
				g.bcast("cl_fx", [d.pos + Vector3(0, 0.5, 0), at + Vector3(0, 0.6, 0), true, DB.WHO_DOG, i, DB.WHO_PLAYER, d.target])
				g.bcast("cl_sound", ["bite", d.pos])
				g.srv_damage(d.target, breed.bite, -1)
			elif dist < 6.0:
				_bark(d, 0.7)
		FLEE:
			var left := _go(d, d.goal, breed.speed, delta)
			if left < 0.8 or d.t <= 0.0 or d.speed == 0.0:
				d.state = IDLE
				d.anim = COWER
				d.speed = 0.0
				d.t = randf_range(2.0, 4.0)
				d.bored = 6.0
		HEEL:
			_srv_heel(d, delta)


## A dog on a lead goes where its owner goes, a pace out to the side.
func _srv_heel(d: Dictionary, delta: float) -> void:
	var o: int = d.owner
	var c := _crowd
	if o < 0 or c.state[o] == c.GONE:
		# Nobody on the other end of the lead any more.
		d.temper = SKITTISH
		d.home = d.pos
		d.roam = 20.0
		_idle(d)
		return
	var at: Vector3 = c.pos[o]
	if c.state[o] == c.DEAD or c.state[o] == c.KO:
		# Stays by them, and cries.
		d.speed = 0.0
		d.anim = LIE
		_face(d, at, delta)
		_say(d, "whine", 4.0)
		return
	var heel: Vector3 = at + Basis(Vector3.UP, c.yaw_of(o)) * Vector3(0.75, 0, -0.35)
	var to: Vector3 = heel - d.pos
	to.y = 0.0
	var dist: float = to.length()
	if dist > 12.0:
		d.pos = heel
		return
	if dist > 0.25:
		var speed := clampf(dist * 3.0, 0.6, BREEDS[d.breed].speed)
		d.pos = Nav.slide(d.pos, to / dist * minf(speed * delta, dist))
		d.yaw = lerp_angle(d.yaw, Kit.face(to), minf(1.0, 8.0 * delta))
		d.speed = speed
		d.anim = RUN if speed > 3.4 else TROT
	else:
		d.speed = 0.0
		d.yaw = lerp_angle(d.yaw, c.yaw_of(o), minf(1.0, 4.0 * delta))
		# Whatever the owner has stopped for, the dog has its own business to see to.
		d.anim = [SIT, SNIFF, STAND, SCRATCH][dogs.find(d) % 4] if c.state[o] == c.AMBIENT else COWER
	d.pos.y = at.y


## A bang: most dogs bolt, and the hard ones go off like alarms.
func _on_noise(at: Vector3, radius: float, _pid: int) -> void:
	if radius < 80.0:
		return
	for d in dogs:
		if d.state == GONE or d.state == HEEL or d.state == ATTACK:
			continue
		var dist: float = d.pos.distance_to(at)
		if dist > radius * 0.55:
			continue
		if d.temper == AGGRESSIVE or d.temper == GUARD:
			if d.state == IDLE or d.state == WANDER:
				d.state = BARKING
				d.goal = at
				d.t = 3.0
		elif d.state != FLEE:
			_say(d, "yelp", 1.0)
			_flee(d, at, 26.0)


## Server ray test. Returns [dog index, distance]; index -1 on a miss.
func ray_pick(o: Vector3, dir: Vector3, max_t: float, grow: float) -> Array:
	var best := -1
	var best_t := max_t
	for i in dogs.size():
		var d: Dictionary = dogs[i]
		if d.state == GONE:
			continue
		var c: Vector3 = d.pos
		if absf(c.x - o.x) > best_t or absf(c.z - o.z) > best_t:
			continue
		var s: float = d.size
		var fwd := Basis(Vector3.UP, d.yaw) * Vector3(0, 0, -0.32 * s)
		var mid := c + Vector3(0, 0.42 * s, 0)
		var t := DB.ray_segment(o, dir, mid - fwd, mid + fwd * 1.5, 0.2 * s + 0.06 + grow, best_t)
		if t >= 0.0:
			best = i
			best_t = t
	return [best, best_t]


## Hurts dog i. Returns whether that killed it.
func srv_damage(i: int, dmg: float, attacker: int) -> bool:
	if i < 0 or i >= dogs.size() or dogs[i].state == GONE:
		return false
	var d: Dictionary = dogs[i]
	var g = Net.game
	d.hp -= dmg
	g.bcast("cl_dog_ev", [i, false], self)
	g.bcast("cl_sound", ["yelp", d.pos + Vector3(0, 0.4, 0)])
	var p = g.players.get(attacker)
	if p != null:
		# People do not like to see it.
		_crowd.srv_outrage(d.pos, attacker)
	if d.hp <= 0.0:
		d.state = GONE
		d.anim = DEAD
		d.speed = 0.0
		return true
	if p == null:
		return false
	if d.state == HEEL:
		# Slips its lead.
		d.temper = SKITTISH
		d.home = d.pos
		d.roam = 20.0
	if (d.temper == AGGRESSIVE or d.temper == GUARD) and (d.hp > BREEDS[d.breed].hp * 0.35 or randf() < 0.4):
		d.state = ATTACK
		d.target = attacker
		d.until = 14.0
		d.nav = {}
	else:
		_flee(d, p.global_position, 28.0)
	return false


## Everything living within r of `at`, as [index, distance], for a blast.
func within(at: Vector3, r: float) -> Array:
	var out: Array = []
	for i in dogs.size():
		if dogs[i].state != GONE and dogs[i].pos.distance_to(at) < r:
			out.append([i, dogs[i].pos.distance_to(at)])
	return out


func alive(i: int) -> bool:
	return i >= 0 and i < dogs.size() and dogs[i].state != GONE


# --- for tests and pictures ---

## Stands dog i at `at` showing `anim`, and stops it thinking for itself.
func debug_pose(i: int, at: Vector3, yaw: float, anim: int, speed := 0.0) -> void:
	var d: Dictionary = dogs[i]
	d.state = IDLE
	d.t = 1e6
	d.bored = 1e6
	d.pos = at
	d.yaw = yaw
	d.anim = anim
	d.speed = speed
	d.temper = FRIENDLY
	pos[i] = at
	_yaw[i] = yaw


## One dog of this breed and temper at `at`, minding its own business. Returns its index.
func debug_dog(breed: int, temper: int, at: Vector3) -> int:
	for i in dogs.size():
		var d: Dictionary = dogs[i]
		if d.breed == breed and d.state != GONE:
			d.temper = temper
			d.state = IDLE
			d.anim = SIT
			d.t = 5.0
			d.bored = 0.0
			d.pos = at
			d.home = at
			d.owner = -1
			d.hp = BREEDS[breed].hp
			pos[i] = at
			return i
	return -1
