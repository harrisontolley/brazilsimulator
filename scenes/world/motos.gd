extends "res://scenes/world/world_kit.gd"
## Motorbikes parked around town that anyone can ride off on.
##
## The server owns who is on which bike. A ridden bike has no movement of its own: it is
## drawn under its rider, whose position is already replicated like any other player's.

const TAKE_RANGE := 3.2
const RAM_SPEED := 7.0
const SPOTS := [
	[Vector3(-262, 0, 70.9), 0.0], [Vector3(-172, 0, 70.9), 0.0], [Vector3(-82, 0, 70.9), 0.0], [Vector3(22, 0, 70.9), 0.0],
	[Vector3(112, 0, 70.9), 0.0], [Vector3(202, 0, 70.9), 0.0], [Vector3(282, 0, 70.9), 0.0],
	[Vector3(-242, 0, 108.2), PI], [Vector3(-152, 0, 108.2), PI], [Vector3(-32, 0, 108.2), PI], [Vector3(62, 0, 108.2), PI],
	[Vector3(162, 0, 108.2), PI], [Vector3(252, 0, 108.2), PI], [Vector3(-20, 0, 134.0), PI / 2.0],
	[Vector3(-120, 0, 44.0), PI / 2.0], [Vector3(60, 0, 44.0), -PI / 2.0],
]
const PAINTS := [Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.12), Color(0.1, 0.3, 0.7), Color(0.9, 0.6, 0.05), Color(0.15, 0.5, 0.25)]

var pos: Array[Vector3] = []
var yaw: Array[float] = []
var rider: Array[int] = []   # peer id, or 0 when parked

var _nodes: Array[Node3D] = []


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vehicle.gdshader")
	var paint := Color(1, 1, 1, 0)
	var dark := Color(0.12, 0.12, 0.13)
	# Faces -Z like the characters, so it can be turned with the rider's own yaw.
	var parts: Array = [
		part(Vector3(0, 0.62, 0), Vector3(0.3, 0.32, 1.3), paint),
		part(Vector3(0, 0.82, 0.25), Vector3(0.34, 0.12, 0.8), dark),
		part(Vector3(0, 0.78, -0.35), Vector3(0.36, 0.26, 0.5), paint),
		part(Vector3(0, 0.95, -0.72), Vector3(0.1, 0.5, 0.1), dark, Vector3(-0.35, 0, 0)),
		part(Vector3(0, 1.16, -0.66), Vector3(0.7, 0.06, 0.06), dark),
		part(Vector3(0, 0.95, -0.86), Vector3(0.2, 0.2, 0.06), Color(1.0, 0.95, 0.8, 2.0)),
		part(Vector3(0, 0.78, 0.72), Vector3(0.2, 0.1, 0.06), Color(0.9, 0.08, 0.05, 2.0)),
		part(Vector3(0.18, 0.4, 0.45), Vector3(0.1, 0.1, 0.8), Color(0.6, 0.6, 0.62)),
	]
	for wz in [-0.78, 0.72]:
		parts.append([_cyl(0.32, 0.32, 0.14, 12), Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0, 0.32, wz)), Color(0.05, 0.05, 0.06)])
	var mesh := compose(parts)
	for i in SPOTS.size():
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.set_instance_shader_parameter("paint", PAINTS[i % PAINTS.size()])
		n.add_child(mi)
		add_child(n)
		_nodes.append(n)
		pos.append(Vector3.ZERO)
		yaw.append(0.0)
		rider.append(0)
	reset()


## Puts every bike back where it starts a match.
func reset() -> void:
	for i in SPOTS.size():
		pos[i] = SPOTS[i][0]
		yaw[i] = SPOTS[i][1]
		rider[i] = 0


func _process(delta: float) -> void:
	var g = Net.game
	for i in _nodes.size():
		var n := _nodes[i]
		var pl = g.players.get(rider[i]) if g != null and rider[i] != 0 else null
		if pl == null:
			# Parked: propped over on its stand.
			n.position = pos[i]
			n.rotation = Vector3(0, yaw[i], 0.22)
			continue
		pos[i] = pl.global_position
		yaw[i] = pl.rotation.y
		n.position = pos[i]
		n.rotation = Vector3(0, yaw[i], lerpf(n.rotation.z, pl.ride_lean(), minf(1.0, 8.0 * delta)))


## Nearest parked bike within reach of p, or -1.
func free_near(p: Vector3) -> int:
	var best := -1
	var best_d := TAKE_RANGE
	for i in pos.size():
		var d := p.distance_to(pos[i])
		if rider[i] == 0 and d < best_d:
			best = i
			best_d = d
	return best


## The bike a player is on, or -1.
func bike_of(pid: int) -> int:
	return rider.find(pid) if pid != 0 else -1


func snapshot() -> Array:
	return [pos, yaw, rider]


func apply_snapshot(snap: Array) -> void:
	for i in mini(pos.size(), snap[0].size()):
		cl_moto(i, snap[2][i], snap[0][i], snap[1][i])


@rpc("any_peer", "call_remote", "reliable")
func srv_mount(i: int) -> void:
	var pid := Net.sender()
	var g = Net.game
	var p = g.players.get(pid)
	if p == null or not p.can_fight() or i < 0 or i >= pos.size() or rider[i] != 0 or bike_of(pid) >= 0:
		return
	if p.global_position.distance_to(pos[i]) > TAKE_RANGE + 2.0:
		return
	# Riding off on somebody's bike is theft if a cop is looking.
	Crime.report_crime(pos[i], pid, 1)
	g.bcast("cl_moto", [i, pid, pos[i], yaw[i]], self)


@rpc("any_peer", "call_remote", "reliable")
func srv_dismount() -> void:
	srv_release(Net.sender())


## Takes a player off their bike, leaving it where they are. Safe to call for anyone.
func srv_release(pid: int) -> void:
	var i := bike_of(pid)
	if i < 0:
		return
	var p = Net.game.players.get(pid)
	var at: Vector3 = p.global_position if p != null else pos[i]
	Net.game.bcast("cl_moto", [i, 0, Vector3(at.x, maxf(at.y, 0.0), at.z), p.rotation.y if p != null else yaw[i]], self)


@rpc("authority", "call_remote", "reliable")
func cl_moto(i: int, pid: int, p: Vector3, y: float) -> void:
	if i < 0 or i >= pos.size():
		return
	var was := rider[i]
	rider[i] = pid
	pos[i] = p
	yaw[i] = y
	var local = Net.game.local_player
	if local == null:
		return
	if pid == local.id:
		local.start_ride()
	elif was == local.id:
		local.stop_ride()


## A rider reporting that they ploughed into NPC `npc`.
@rpc("any_peer", "call_remote", "unreliable")
func srv_ram(npc: int) -> void:
	var pid := Net.sender()
	var g = Net.game
	var p = g.players.get(pid)
	if p == null or bike_of(pid) < 0 or npc < 0 or npc >= g.crowd.count or g.crowd.state[npc] >= g.crowd.DEAD:
		return
	var at: Vector3 = g.crowd.pos[npc]
	if at.distance_to(p.global_position) > 6.0:
		return
	g.bcast("cl_fx", [p.global_position + Vector3(0, 0.8, 0), at + Vector3(0, 0.9, 0), true, DB.WHO_PLAYER, pid, DB.WHO_NPC, npc])
	g.crowd.srv_damage_npc(npc, 35.0, pid)
	Crime.report_crime(at, pid, 2)


## A rider reporting that they hit something solid at speed.
@rpc("any_peer", "call_remote", "reliable")
func srv_crash() -> void:
	var pid := Net.sender()
	if bike_of(pid) >= 0:
		srv_release(pid)
		Net.game.srv_damage(pid, 15.0, -1)
