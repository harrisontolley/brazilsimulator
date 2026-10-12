extends Node3D
## Things that take time to arrive: rockets, grenades and bottles of petrol, and the fires
## the bottles leave behind.
##
## The server flies each one and decides what it hits. Every peer flies its own copy from the
## same start, against the same world, so it is one message when it leaves and one when it
## goes off.

const Layout := preload("res://scenes/world/layout.gd")

enum { ROCKET, GRENADE, MOLOTOV }

const STEP := 1.0 / 60.0
const ROCKET_SPEED := 52.0
const ROCKET_DROP := 1.2
const ROCKET_LIFE := 6.0
const GRAVITY := 15.0
## How much of its speed a grenade keeps off a bounce, and along the ground.
const BOUNCE := 0.42
const ROLL := 0.72
const BURN_EVERY := 0.45

## id -> {kind, pos, vel, t (age), fuse, owner, item, node, rest}
var flying := {}
## Server: [where, radius, match time it burns out, owner pid, damage a tick, next tick]
var fires: Array = []

var _next := 1
var _acc := 0.0
var _meshes := {}


## Server: sends one off. Returns its id.
func srv_launch(kind: int, at: Vector3, vel: Vector3, owner: int, item: String) -> int:
	var id := _next
	_next += 1
	Net.game.bcast("cl_launch", [id, kind, at, vel, owner, item], self)
	return id


@rpc("authority", "call_remote", "reliable")
func cl_launch(id: int, kind: int, at: Vector3, vel: Vector3, owner: int, item: String) -> void:
	var node := Node3D.new()
	node.position = at
	add_child(node)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	mi.material_override = _mat()
	node.add_child(mi)
	var def: Dictionary = DB.ITEMS.get(item, {})
	flying[id] = {"kind": kind, "pos": at, "vel": vel, "t": 0.0, "fuse": def.get("fuse", 0.0), "owner": owner, "item": item,
			"node": node, "rest": false, "trail": 0.0}
	if kind == ROCKET:
		var loop: AudioStreamPlayer3D = Sfx.emitter("rocket", 2.0, 9.0, 120.0)
		node.add_child(loop)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.6, 0.2)
		glow.light_energy = 2.5
		glow.omni_range = 8.0
		node.add_child(glow)


@rpc("authority", "call_remote", "reliable")
func cl_gone(id: int) -> void:
	if flying.has(id):
		flying[id].node.queue_free()
		flying.erase(id)


## Flames on the ground at `at` for `seconds`.
@rpc("authority", "call_remote", "reliable")
func cl_fire(at: Vector3, radius: float, seconds: float) -> void:
	Net.game.fx.fire(at, radius, seconds)
	Sfx.play("smash", at, 3.0)
	var loop: AudioStreamPlayer3D = Sfx.emitter("fire", 0.0, 6.0, 50.0)
	loop.position = at + Vector3(0, 0.5, 0)
	add_child(loop)
	get_tree().create_timer(seconds).timeout.connect(loop.queue_free)


func _process(delta: float) -> void:
	var server := multiplayer.is_server()
	_acc = minf(_acc + delta, 0.1)
	while _acc >= STEP:
		_acc -= STEP
		for id in flying.keys():
			_fly(id, flying[id], server)
	for id in flying:
		var s: Dictionary = flying[id]
		s.node.position = s.pos
		if s.kind == ROCKET:
			if s.vel.length() > 0.1:
				s.node.look_at(s.pos + s.vel, Vector3.UP if absf(s.vel.normalized().y) < 0.98 else Vector3.RIGHT)
			s.trail -= delta
			if s.trail <= 0.0:
				s.trail = 0.02
				Net.game.fx.smoke(s.pos - s.vel.normalized() * 0.5, 0.35, 0.9)
		elif not s.rest:
			s.node.rotate_x(delta * 9.0)
			s.node.rotate_z(delta * 5.0)
	if server:
		_srv_burn()


func _fly(id: int, s: Dictionary, server: bool) -> void:
	var g = Net.game
	s.t += STEP
	if s.kind == ROCKET:
		s.vel.y -= ROCKET_DROP * STEP
	elif not s.rest:
		s.vel.y -= GRAVITY * STEP
	var step: Vector3 = s.vel * STEP
	var to: Vector3 = s.pos + step
	var space := get_world_3d().direct_space_state
	var wall := {} if s.rest else space.intersect_ray(PhysicsRayQueryParameters3D.create(s.pos, to + step.normalized() * 0.08, 1))
	# Somebody in the way stops it as surely as a wall does.
	var body := false
	if server and not s.rest and step.length() > 0.001 and s.t > 0.06:
		var reach: float = (wall.position.distance_to(s.pos) if not wall.is_empty() else step.length()) + 0.1
		var hit: Dictionary = g._ray_hit(s.pos, step.normalized(), reach, 0.12, s.owner if s.t < 0.3 else -1)
		if hit.type != DB.WHO_NONE:
			body = true
			to = s.pos + step.normalized() * hit.t
			wall = {}
	if s.kind == ROCKET:
		if not wall.is_empty() or body or s.t > ROCKET_LIFE:
			s.pos = wall.position + wall.normal * 0.15 if not wall.is_empty() else to
			if server:
				_srv_go_off(id, s)
			else:
				# Stop where it stopped and wait to be told.
				s.vel = Vector3.ZERO
				s.rest = true
			return
		s.pos = to
		return
	if s.kind == MOLOTOV and (not wall.is_empty() or body):
		s.pos = wall.position + wall.normal * 0.05 if not wall.is_empty() else to
		if server:
			_srv_go_off(id, s)
		else:
			s.vel = Vector3.ZERO
			s.rest = true
		return
	if not wall.is_empty():
		var n: Vector3 = wall.normal
		s.pos = wall.position + n * 0.09
		var into: float = s.vel.dot(n)
		# Keep some of what was going along the surface, less of what was going into it.
		s.vel = (s.vel - n * into) * ROLL - n * into * BOUNCE
		if absf(into) > 2.5:
			Sfx.play("clink", s.pos, -2.0)
		if n.y > 0.7 and s.vel.length() < 1.2:
			s.vel = Vector3.ZERO
			s.rest = true
	elif body:
		# Off somebody's chest and down at their feet.
		s.pos = to
		s.vel = Vector3(s.vel.x * -0.12, 0.5, s.vel.z * -0.12)
	else:
		s.pos = to
	var bed := Layout.seabed_y(s.pos.z) - 0.3
	if s.pos.y < bed:
		s.pos.y = bed
		s.vel = Vector3.ZERO
		s.rest = true
	if s.kind == GRENADE and s.t >= s.fuse:
		if server:
			_srv_go_off(id, s)
		elif s.t > s.fuse + 1.5:
			cl_gone(id)


func _srv_go_off(id: int, s: Dictionary) -> void:
	var g = Net.game
	var def: Dictionary = DB.ITEMS[s.item]
	g.bcast("cl_gone", [id], self)
	if s.kind == MOLOTOV:
		var at: Vector3 = s.pos
		if Layout.wet(at):
			# Petrol on the sea: a hiss and nothing else.
			g.bcast("cl_sound", ["splash", at])
			return
		at.y = maxf(Layout.terrace_y(at.z), 0.0) if at.y < Layout.terrace_y(at.z) + 1.2 else at.y
		fires.append([at, def.blast, MatchState.time + def.burn, s.owner, def.damage, 0.0])
		g.bcast("cl_fire", [at, def.blast, def.burn], self)
		Crime.report_noise(at, 60.0, s.owner)
		Crime.report_crime(at, s.owner, 3)
		g.crowd.srv_panic(at, 22.0, g.crowd.FRIGHT_SHOTS, s.owner)
		return
	g.srv_explode(s.pos, def.blast, def.damage, s.owner)


## Whoever is standing in a fire gets burnt, a little at a time.
func _srv_burn() -> void:
	var g = Net.game
	var t := MatchState.time
	for k in range(fires.size() - 1, -1, -1):
		var f: Array = fires[k]
		if t >= f[2]:
			fires.remove_at(k)
			continue
		if t < f[5]:
			continue
		f[5] = t + BURN_EVERY
		g.srv_scorch(f[0], f[1], f[4], f[3])


func _mat() -> StandardMaterial3D:
	if not _meshes.has("mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.6
		_meshes["mat"] = m
	return _meshes["mat"]


func _mesh(kind: int) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var WorldKit = load("res://scenes/world/world_kit.gd")
	var parts: Array = []
	match kind:
		ROCKET:
			# Pointing along -Z, the way look_at aims things.
			var green := Color(0.28, 0.33, 0.2)
			parts = [WorldKit.part(Vector3(0, 0, 0), Vector3(0.09, 0.09, 0.5), green),
					WorldKit.part(Vector3(0, 0, -0.33), Vector3(0.13, 0.13, 0.22), green.darkened(0.2)),
					WorldKit.part(Vector3(0, 0, -0.48), Vector3(0.07, 0.07, 0.1), Color(0.3, 0.3, 0.32)),
					WorldKit.part(Vector3(0, 0, 0.28), Vector3(0.24, 0.02, 0.12), green.darkened(0.3)),
					WorldKit.part(Vector3(0, 0, 0.28), Vector3(0.02, 0.24, 0.12), green.darkened(0.3)),
					WorldKit.part(Vector3(0, 0, 0.3), Vector3(0.06, 0.06, 0.1), Color(1.0, 0.7, 0.2))]
		GRENADE:
			var olive := Color(0.26, 0.34, 0.18)
			parts = [WorldKit.part(Vector3.ZERO, Vector3(0.11, 0.14, 0.11), olive),
					WorldKit.part(Vector3(0, 0, 0), Vector3(0.13, 0.09, 0.13), olive.darkened(0.15)),
					WorldKit.part(Vector3(0, 0.09, 0), Vector3(0.05, 0.05, 0.05), Color(0.55, 0.55, 0.5)),
					WorldKit.part(Vector3(0.03, 0.06, 0), Vector3(0.02, 0.12, 0.03), Color(0.55, 0.55, 0.5))]
		_:
			parts = [WorldKit.part(Vector3.ZERO, Vector3(0.09, 0.18, 0.09), Color(0.35, 0.5, 0.25)),
					WorldKit.part(Vector3(0, 0.13, 0), Vector3(0.04, 0.1, 0.04), Color(0.35, 0.5, 0.25)),
					WorldKit.part(Vector3(0, 0.21, 0), Vector3(0.05, 0.09, 0.02), Color(1.0, 0.55, 0.1))]
	_meshes[kind] = WorldKit.compose(parts)
	return _meshes[kind]
