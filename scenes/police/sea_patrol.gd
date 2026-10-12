extends Node3D
## The police afloat: three officers on jet skis who put out when somebody wanted takes to
## the water, so the sea is not simply the way out of every chase.
##
## Like the officers on land they are run by the host and streamed to everyone else. They
## are simpler men, though: open water needs no route, so each just turns toward whoever he
## is after, goes round the yacht rather than through it, and comes home when it is over.

const Layout := preload("res://scenes/world/layout.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")

enum { DOCK, OUT, BACK, DOWN }

## Where each waits, bows to the sea, in the shallows at the foot of the beach.
const DOCKS := [Vector3(-170, 0, -50), Vector3(0, 0, -50), Vector3(170, 0, -50)]
const SPEED := 21.0
const ACCEL := 9.0
const TURN := 1.7
const HP := 110.0
const SIGHT := 90.0
const FIRE_RANGE := 30.0
const GRAB := 2.4
## How long in the water before they come, how long under before they lose you, and how
## long they look for someone they cannot see.
const LAUNCH_AFTER := 2.0
const UNDER_LOSE := 1.0
const GIVE_UP := 12.0
const DOWN_TIME := 45.0
const HEIGHT := 0.95

var units: Array = []

var _nodes: Array[Node3D] = []
var _bodies: MultiMesh
var _wet := {}       # pid -> seconds they have been in the water while wanted
var _under := {}     # pid -> seconds their head has been under
var _send_t := 0.0
var _wake_t := 0.0


func _ready() -> void:
	var motos = Net.game.motos
	_bodies = Kit.add_to(self, DOCKS.size(), AABB(Vector3(-400, -10, -500), Vector3(800, 30, 520)))
	for i in DOCKS.size():
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = motos.ski_mesh
		mi.material_override = motos.bike_mat
		mi.set_instance_shader_parameter("paint", Color(0.1, 0.17, 0.52))
		n.add_child(mi)
		var siren := Sfx.emitter("siren", -2.0, 9.0, 160.0, false)
		siren.name = "Siren"
		n.add_child(siren)
		var engine := Sfx.emitter("ski", -3.0, 6.0, 110.0, false)
		engine.name = "Engine"
		n.add_child(engine)
		add_child(n)
		_nodes.append(n)
		_bodies.set_instance_color(i, Color(0.1, 0.17, 0.52, fmod(0.37 + i * 0.29, 0.999)))
	reset()


func reset() -> void:
	units.clear()
	for i in DOCKS.size():
		units.append({"pos": DOCKS[i], "yaw": 0.0, "spd": 0.0, "state": DOCK, "target": 0, "hp": HP, "cd": 0.0, "lost": 0.0, "t": 0.0, "ev": 0.0})
	_wet.clear()
	_under.clear()


## Is one of them out and looking straight at player `pid`? (Host.)
func sees(pid: int) -> bool:
	var pl = Net.game.players.get(pid)
	if pl == null or _under.get(pid, 0.0) > UNDER_LOSE:
		return false
	for u in units:
		if u.state == OUT and u.target == pid and u.pos.distance_to(pl.global_position) < SIGHT:
			return true
	return false


func _process(delta: float) -> void:
	var g = Net.game
	if multiplayer.is_server() and MatchState.running and not MatchState.ended:
		_srv_tick(delta)
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 0.1
			var busy := false
			for u in units:
				busy = busy or u.state != DOCK
			if busy or _send_t > -1.0:
				var ps := PackedVector3Array()
				var ys := PackedFloat32Array()
				var ss := PackedByteArray()
				for u in units:
					ps.append(u.pos)
					ys.append(u.yaw)
					ss.append(u.state)
				g.bcast("cl_sea", [ps, ys, ss], self)
	_wake_t -= delta
	for i in units.size():
		var u: Dictionary = units[i]
		var n := _nodes[i]
		var at: Vector3 = u.pos
		var show: Vector3 = n.position.lerp(at, minf(1.0, 12.0 * delta)) if multiplayer.is_server() or n.position.distance_to(at) < 25.0 else at
		var lie := Layout.wave_slope(show.x, show.z).rotated(u.yaw)
		show.y = maxf(Layout.wave_y(show.x, show.z) - Layout.SKI_DRAFT, Layout.seabed_y(show.z))
		var moved: float = n.position.distance_to(show) / maxf(delta, 0.001)
		n.position = show
		n.rotation = Vector3(minf(moved, 24.0) * 0.008 - lie.y * 0.6, lerp_angle(n.rotation.y, u.yaw, minf(1.0, 10.0 * delta)), lie.x * 0.5)
		var out: bool = u.state == OUT or u.state == BACK
		for snd in ["Siren", "Engine"]:
			var e: AudioStreamPlayer3D = n.get_node(snd)
			var want: bool = u.state == OUT if snd == "Siren" else out
			if want and not e.playing and e.stream != null:
				e.play()
			elif not want and e.playing:
				e.stop()
		(n.get_node("Engine") as AudioStreamPlayer3D).pitch_scale = 0.75 + minf(moved, 24.0) / 30.0
		if out and moved > 3.0 and _wake_t <= 0.0:
			var back := Vector3(sin(n.rotation.y), 0, cos(n.rotation.y))
			g.sea_fx.foam(show + back * 1.5, 1.4 + moved * 0.07, 1.6 + moved * 0.05)
			g.sea_fx.spray(show + back * 1.6, back * moved, clampf(moved / 6.0, 1.0, 4.0))
		# The officer: astride it, lamp going while he is after someone; face down in the water if not.
		var flags := Kit.F_POLICE | Kit.F_SUIT | (Kit.F_LAMP_ON if u.state == OUT else 0)
		var pose := Kit.DEAD if u.state == DOWN else Kit.RIDE
		_bodies.set_instance_transform(i, Kit.xform(show + (Vector3(0, -0.5, 0) if u.state == DOWN else Vector3.ZERO), n.rotation.y, HEIGHT, HEIGHT))
		_bodies.set_instance_custom_data(i, Kit.custom(pose, 0.0, flags, u.ev))
	if _wake_t <= 0.0:
		_wake_t = 0.08


@rpc("authority", "call_remote", "unreliable")
func cl_sea(ps: PackedVector3Array, ys: PackedFloat32Array, ss: PackedByteArray) -> void:
	for i in mini(units.size(), ps.size()):
		units[i].pos = ps[i]
		units[i].yaw = ys[i]
		units[i].state = ss[i]


## A flinch or a shot on officer i's body, on every machine.
func fx_event(i: int, attack: bool) -> void:
	if i >= 0 and i < units.size():
		units[i].ev = Kit.now() if attack else -Kit.now()


# --- host ---

func _srv_tick(delta: float) -> void:
	var g = Net.game
	for pid in g.players:
		var pl = g.players[pid]
		_under[pid] = _under.get(pid, 0.0) + delta if pl.head_under() else 0.0
		var at_sea: bool = pl.at_large() and pl.st.heat >= 2 and pl.global_position.z < Layout.WATER_Z - 4.0 and (Layout.wet(pl.global_position) or g.motos.on_ski(pid) or g.yacht.on_board(pl.global_position))
		_wet[pid] = _wet.get(pid, 0.0) + delta if at_sea else 0.0
		if _wet[pid] > LAUNCH_AFTER:
			_srv_launch(pid, 3 if pl.st.heat >= 3 else 2)
	for i in units.size():
		var u: Dictionary = units[i]
		match u.state:
			OUT: _srv_chase(i, u, delta)
			BACK:
				if _srv_steer(u, DOCKS[i], SPEED * 0.6, delta) < 3.0:
					u.state = DOCK
					u.pos = DOCKS[i]
					u.yaw = 0.0
					u.spd = 0.0
			DOWN:
				u.t -= delta
				if u.t <= 0.0:
					u.state = DOCK
					u.pos = DOCKS[i]
					u.yaw = 0.0
					u.hp = HP


## Sends out as many as `want` after player `pid`, nearest first.
func _srv_launch(pid: int, want: int) -> void:
	var at: Vector3 = Net.game.players[pid].global_position
	var have := 0
	for u in units:
		have += 1 if u.state == OUT and u.target == pid else 0
	while have < want:
		var best := -1
		for i in units.size():
			if (units[i].state == DOCK or units[i].state == BACK) and (best < 0 or units[i].pos.distance_to(at) < units[best].pos.distance_to(at)):
				best = i
		if best < 0:
			return
		units[best].state = OUT
		units[best].target = pid
		units[best].lost = 0.0
		units[best].cd = 2.0
		have += 1
		if have == 1:
			Net.game.send(pid, "cl_toast", ["Police jet skis are coming out after you"])


func _srv_chase(i: int, u: Dictionary, delta: float) -> void:
	var g = Net.game
	var pl = g.players.get(u.target)
	if pl == null or not pl.at_large() or pl.st.heat < 2:
		u.state = BACK
		return
	var target: Vector3 = pl.global_position
	var seen: bool = _under.get(u.target, 0.0) <= UNDER_LOSE and u.pos.distance_to(target) < SIGHT
	var ashore: bool = target.z > Layout.WATER_Z + 6.0
	u.lost = 0.0 if seen and not ashore else u.lost + delta
	if u.lost > GIVE_UP:
		u.state = BACK
		g.send(u.target, "cl_toast", ["The police boats have lost you"])
		return
	var d := _srv_steer(u, target, SPEED, delta)
	u.cd -= delta
	if not seen:
		return
	var on_ski: bool = g.motos.on_ski(u.target)
	var armed: bool = pl.st.heat >= 3 or on_ski
	if armed and d < FIRE_RANGE and u.cd <= 0.0 and g._clear(u.pos + Vector3(0, 1.2, 0), target + Vector3(0, 0.6, 0)):
		u.cd = 1.0
		var hit := randf() < (0.3 if pl.swimming() else 0.5)
		var to_pt := target + Vector3(0, 0.5 if pl.swimming() else 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)))
		g.bcast("cl_fx", [u.pos + Vector3(0, 1.3, 0), to_pt, false, DB.WHO_SEACOP, i, DB.WHO_PLAYER if hit else DB.WHO_NONE, u.target])
		if hit:
			g.srv_damage(u.target, 12.0, -1)
	if d < GRAB and absf(target.y - u.pos.y) < 2.0:
		if on_ski:
			# Rammed off it.
			g.motos.srv_release(u.target)
			g.send(u.target, "cl_knock", [Vector3(sin(u.yaw) * -4.0, 5.0, cos(u.yaw) * -4.0)])
			g.srv_damage(u.target, 10.0, -1)
			u.spd *= 0.3
			u.cd = 1.5
		elif pl.swimming():
			# Hauled out of the water by the collar.
			g.srv_arrest(u.target)
			u.state = BACK


## Turns unit u toward `to` and drives it there, round the yacht and clear of the shallows.
## Returns how far there is still to go.
func _srv_steer(u: Dictionary, to: Vector3, top: float, delta: float) -> float:
	var g = Net.game
	var off: Vector3 = to - u.pos
	off.y = 0.0
	var d := off.length()
	var want := off / maxf(d, 0.01)
	# The hull is in the way: slide round it.
	var near: float = g.yacht.reach(u.pos)
	if near < 9.0 and g.yacht.reach(to) > 1.0:
		var away: Vector3 = u.pos - g.yacht.at
		away.y = 0.0
		away = away.normalized()
		var round := Vector3(-away.z, 0, away.x)
		if round.dot(want) < 0.0:
			round = -round
		want = (round + away * clampf((9.0 - near) / 5.0, 0.0, 1.2)).normalized()
	u.yaw = rotate_toward(u.yaw, atan2(-want.x, -want.z), TURN * delta)
	var fwd := Vector3(-sin(u.yaw), 0, -cos(u.yaw))
	var slow := clampf(d / 8.0, 0.25, 1.0) * clampf(fwd.dot(want) + 0.6, 0.3, 1.0)
	u.spd = move_toward(u.spd, top * slow, ACCEL * delta)
	var next: Vector3 = u.pos + fwd * u.spd * delta
	# No further in than there is water to float on, and not through the boat.
	if Layout.seabed_y(next.z) > Layout.SEA_Y - 0.7 or g.yacht.reach(next) < 1.0:
		u.spd = 0.0
		next = u.pos
	next.x = clampf(next.x, -Layout.SEA_SOFT_X, Layout.SEA_SOFT_X)
	next.z = maxf(next.z, Layout.SEA_SOFT_Z)
	u.pos = Vector3(next.x, Layout.SEA_Y, next.z)
	return d


## The officer a shot along (o, d) hits first: [index or -1, distance, DB.ZONE_*].
func ray_pick(o: Vector3, d: Vector3, max_t: float, grow: float) -> Array:
	var best := -1
	var best_t := max_t
	var zone := DB.ZONE_BODY
	for i in units.size():
		var u: Dictionary = units[i]
		if u.state != OUT and u.state != BACK:
			continue
		var at: Vector3 = u.pos
		at.y = Layout.wave_y(at.x, at.z) - Layout.SKI_DRAFT + 0.25
		var h := Kit.ray_hit(o, d, best_t, at, u.yaw, HEIGHT, Kit.STANCE_SEAT, grow)
		if h[0] >= 0.0:
			best = i
			best_t = h[0]
			zone = h[1]
	return [best, best_t, zone]


## True if that finished him.
func srv_damage(i: int, dmg: float, attacker: int) -> bool:
	var u: Dictionary = units[i]
	if u.state != OUT and u.state != BACK:
		return false
	u.hp -= dmg
	if u.state == BACK and attacker > 0:
		u.state = OUT
		u.target = attacker
		u.lost = 0.0
	if u.hp > 0.0:
		return false
	u.state = DOWN
	u.t = DOWN_TIME
	u.spd = 0.0
	Net.game.srv_add_drop(u.pos, 0, {"pistol": 1, "ammo": 12})
	Crime.report_crime(u.pos, attacker, 3)
	return true
