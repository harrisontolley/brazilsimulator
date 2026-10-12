extends "res://scenes/world/world_kit.gd"
## Footballs. The host simulates them as rigid bodies and streams where they are; everyone
## else just draws them. Run into one to dribble it, hit it to shoot, score for cash.

const Kit := preload("res://scenes/characters/char_kit.gd")

const RADIUS := 0.22
const GOAL_PAY := 60
const SHOT_SPEED := 21.0

## Where each ball starts and returns to.
var homes: Array[Vector3] = []
var pos := PackedVector3Array()

var _vis: Array[Node3D] = []
var _target := PackedVector3Array()
# server only
var _bodies: Array[RigidBody3D] = []
var _last: Array[int] = []        # who touched each ball last
var _reset: Array[float] = []     # seconds until a dead ball goes back to its spot
var _touch := {}                  # [pid, ball] -> time of last dribble touch
var _was := {}                    # pid -> position last tick, to know how fast they move
var _send_t := 0.0
var _npc_t := 0.0


func _ready() -> void:
	for rect in Layout.PITCHES:
		homes.append(rect[0] + Vector3(0, 0.3, 0))
	homes.append(DB.CAMPINHO_POS + Vector3(0, 0.4, 0.5))
	homes.append(Layout.YARD_PITCH[0] + Vector3(0, 0.3, 0))
	homes.append(Vector3(-60, 0.3, 2))
	homes.append(Vector3(118, 0.3, -4))
	var black := Color(0.08, 0.08, 0.08)
	var parts: Array = [[_ball(RADIUS, -1.0, 12), Transform3D(), Color.WHITE]]
	for d in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		parts.append(part(d * RADIUS * 0.9, Vector3.ONE * 0.13, black))
	var mesh := compose(parts)
	var server := multiplayer.is_server()
	for i in homes.size():
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.material_override = _vertex_mat()
		n.position = homes[i]
		add_child(n)
		_vis.append(n)
		pos.append(homes[i])
		_target.append(homes[i])
		if not server:
			continue
		var b := RigidBody3D.new()
		b.collision_layer = 4
		b.collision_mask = 1
		b.mass = 0.45
		b.continuous_cd = true
		b.linear_damp = 0.5
		b.angular_damp = 1.2
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.55
		pm.friction = 0.8
		b.physics_material_override = pm
		var shape := SphereShape3D.new()
		shape.radius = RADIUS
		var cs := CollisionShape3D.new()
		cs.shape = shape
		b.add_child(cs)
		b.position = homes[i]
		add_child(b)
		_bodies.append(b)
		_last.append(0)
		_reset.append(0.0)


func reset() -> void:
	for i in _bodies.size():
		_put_back(i)


func _put_back(i: int) -> void:
	var b := _bodies[i]
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.global_position = homes[i]
	_last[i] = 0
	_reset[i] = 0.0


func _process(delta: float) -> void:
	for i in _vis.size():
		var n := _vis[i]
		var to := _target[i]
		var step := to - n.position
		n.position = n.position.lerp(to, minf(1.0, 16.0 * delta))
		pos[i] = n.position
		# Roll with the ground it covers.
		var flat := Vector3(step.x, 0, step.z)
		if flat.length() > 0.002:
			n.rotate(flat.cross(Vector3.DOWN).normalized(), flat.length() * 16.0 * delta / RADIUS)


func _physics_process(delta: float) -> void:
	if _bodies.is_empty():
		return
	var g = Net.game
	for pid in g.players:
		var pl = g.players[pid]
		var at: Vector3 = pl.global_position
		var vel: Vector3 = (at - _was.get(pid, at)) / delta
		_was[pid] = at
		var speed := Vector2(vel.x, vel.z).length()
		if not pl.can_fight() or speed < 1.0 or speed > 40.0:
			continue
		for i in _bodies.size():
			var b := _bodies[i]
			var d: Vector3 = b.global_position - at
			if absf(d.y) > 1.3 or Vector2(d.x, d.z).length() > 0.7:
				continue
			var key := [pid, i]
			var now := Time.get_ticks_msec()
			if now - _touch.get(key, 0) < 250:
				continue
			_touch[key] = now
			_last[i] = pid
			b.linear_velocity = Vector3(vel.x, 0, vel.z) * 1.25 + Vector3(vel.x, 0, vel.z).normalized() * 2.0 + Vector3(0, 1.8, 0)

	for i in _bodies.size():
		var b := _bodies[i]
		var p := b.global_position
		if _reset[i] > 0.0:
			_reset[i] -= delta
			if _reset[i] <= 0.0:
				_put_back(i)
			continue
		var scored := _goal_at(p)
		if scored:
			_reset[i] = 2.5
			var pl = g.players.get(_last[i])
			if pl != null and pl.st.jail > 0.0:
				# Inside, a goal is worth time.
				g.prison.srv_cut(pl, g.prison.GOAL_CUT, "GOOOOL")
				g.bcast("cl_goal", [p, ""], self)
			else:
				if pl != null:
					pl.st.money += GOAL_PAY
					g.push_state(pl)
				g.bcast("cl_goal", [p, pl.pname if pl != null else ""], self)
		elif p.z < Layout.SHORE_Z - 6.0 or absf(p.x) > Layout.X_LIMIT + 4.0 or p.y < -2.0:
			_reset[i] = 3.0

	# A hard shot into somebody stings, and a local might come looking for whoever kicked it.
	_npc_t -= delta
	if _npc_t <= 0.0:
		_npc_t = 0.1
		for i in _bodies.size():
			var b := _bodies[i]
			var v := b.linear_velocity
			if v.length() < 9.0:
				continue
			var hit: Array = g.crowd.ray_pick(b.global_position - Vector3(0, 0.6, 0), v.normalized(), 1.0, 0.7)
			if hit[0] < 0:
				continue
			g.bcast("cl_fx", [b.global_position, b.global_position, true, DB.WHO_NONE, -1, DB.WHO_NPC, hit[0]])
			b.linear_velocity = Vector3(-v.x * 0.35, 3.0, -v.z * 0.35)
			if _last[i] != 0 and randf() < 0.3:
				g.crowd.srv_provoke(hit[0], _last[i])

	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.066
		var ps := PackedVector3Array()
		for b in _bodies:
			ps.append(b.global_position)
		g.bcast("cl_balls", [ps], self)


## Is p inside one of the goals?
func _goal_at(p: Vector3) -> bool:
	if p.y > Layout.GOAL_H:
		return false
	for rect in Layout.PITCHES + [Layout.YARD_PITCH]:
		var c: Vector3 = rect[0]
		var h: Vector2 = rect[1]
		var past := absf(p.x - c.x) - h.x
		if past > 0.25 and past < 1.3 and absf(p.z - c.z) < Layout.GOAL_HALF:
			return true
	return false


## A blast at `at` sends every ball within `radius` of it flying.
func srv_blast(at: Vector3, radius: float) -> void:
	for i in _bodies.size():
		var b := _bodies[i]
		var to := b.global_position - at
		if to.length() < radius and _reset[i] <= 0.0:
			b.linear_velocity = (to.normalized() + Vector3(0, 0.7, 0)).normalized() * SHOT_SPEED * 1.6 * (1.0 - to.length() / radius * 0.6)


## An attack along a ray: sends the first ball it meets flying. Returns the distance, or -1.
func srv_strike(o: Vector3, d: Vector3, reach: float, pid: int, power: float) -> float:
	for i in _bodies.size():
		var b := _bodies[i]
		var t := DB.ray_point(o, d, b.global_position, 0.75, reach)
		if t < 0.0 or _reset[i] > 0.0:
			continue
		var aim := Vector3(d.x, maxf(d.y, 0.0) + 0.22, d.z).normalized()
		b.linear_velocity = aim * SHOT_SPEED * power
		_last[i] = pid
		return t
	return -1.0


@rpc("authority", "call_remote", "unreliable")
func cl_balls(ps: PackedVector3Array) -> void:
	if ps.size() == _target.size():
		_target = ps


@rpc("authority", "call_remote", "reliable")
func cl_goal(at: Vector3, who: String) -> void:
	var g = Net.game
	g.fx.confetti(at + Vector3(0, 1.5, 0))
	Kit.cheer(4.0)
	Sfx.play("cheer", at)
	Sfx.play("whistle", at)
	if who != "":
		g.hud.toast("GOOOOL!  %s  +R$%d" % [who, GOAL_PAY])
