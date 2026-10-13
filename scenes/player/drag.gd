extends Node3D
## Hauling the unconscious about by the head, and throwing them down the street.
##
## The server decides who has hold of whom and why it stops. Everything else is worked out by
## every machine for itself, so a body costs no bandwidth: it is a weight on a rope from its
## hauler's hand, whose position is already replicated like any other player's, and thrown it
## flies the same arc everywhere. NPCs and players are alike to it; only how a body is drawn
## differs. A player victim's own rig flails (see CharRig.FLAIL) and their client puts them
## where the sim says; an NPC is swapped for a rigged puppet while it is being handled.

const Kit := preload("res://scenes/characters/char_kit.gd")
const CharRig := preload("res://scenes/characters/char_rig.gd")
const Crowd := preload("res://scenes/crowd/crowd_manager.gd")
const Nav := preload("res://scenes/world/nav.gd")
const Places := preload("res://scenes/world/places.gd")

const NPC := 0
const PLAYER := 1
## How far from the hauler's feet to the dragged one's, so the head is about where the hands are.
const ROPE := 1.45
const REACH := 3.0
const THROW_SPEED := 8.5
const THROW_LIFT := 4.5
const GRAVITY := 18.0
const THROW_DAMAGE := 5.0
const PUPPETS := 6
const RANSOM_COOLDOWN := 120.0

## hauler pid -> {kind, id, pos, vel, yaw, spd, base}
var hauls := {}
## Bodies in the air: {kind, id, pos, vel, yaw, t, base}
var flung: Array = []

var _ransomed := {}        # player id -> match time they can be held to ransom again
var _puppets: Array = []   # {root, mm, rig, mats, i}
var _puppet_of := {}       # npc index -> puppet


func _exit_tree() -> void:
	for p in _puppets:
		Kit.drop_materials(p.mats)


# --- who has what ---

## The haul `kind`/`id` is part of, or an empty dictionary.
func haul_of(kind: int, id: int) -> Dictionary:
	for pid in hauls:
		var h: Dictionary = hauls[pid]
		if h.kind == kind and h.id == id:
			return h
	for h in flung:
		if h.kind == kind and h.id == id:
			return h
	return {}


func is_hauling(pid: int) -> bool:
	return hauls.has(pid)


func _body_pos(kind: int, id: int) -> Vector3:
	var g = Net.game
	if kind == NPC:
		return g.crowd.pos[id]
	var p = g.players.get(id)
	return p.global_position if p != null else Vector3.ZERO


# --- server ---

@rpc("any_peer", "call_remote", "reliable")
func srv_drag(kind: int, id: int) -> void:
	var g = Net.game
	var pid := Net.sender()
	var p = g.players.get(pid)
	if p == null or not p.can_fight() or hauls.has(pid) or p.st.jail > 0.0 or g.motos.bike_of(pid) >= 0 or p.swimming():
		return
	if not haul_of(kind, id).is_empty():
		return
	var at: Vector3
	var yaw := 0.0
	if kind == NPC:
		if id < 0 or id >= g.crowd.count or g.crowd.state[id] != Crowd.KO:
			return
		at = g.crowd.pos[id]
		yaw = g.crowd.yaw_of(id)
	else:
		var v = g.players.get(id)
		if v == null or v == p or v.st.ko <= 0.0 or v.st.dead or v.st.get("hide", -1) >= 0:
			return
		at = v.global_position
		yaw = v.rotation.y
	if at.distance_to(p.global_position) > REACH + 1.0:
		return
	Crime.report_crime(at, pid, 2)
	g.bcast("cl_haul", [pid, kind, id, true, at, yaw], self)


@rpc("any_peer", "call_remote", "reliable")
func srv_drop() -> void:
	var pid := Net.sender()
	if hauls.has(pid):
		_srv_release(pid)


@rpc("any_peer", "call_remote", "reliable")
func srv_throw(dir: Vector3) -> void:
	var g = Net.game
	var pid := Net.sender()
	if not hauls.has(pid) or dir.length_squared() < 0.01:
		return
	var h: Dictionary = hauls[pid]
	dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3(0, 0, -1)
	var vel := flat * THROW_SPEED + Vector3(0, THROW_LIFT + maxf(dir.y, 0.0) * 4.0, 0)
	g.bcast("cl_throw", [pid, h.kind, h.id, h.pos + Vector3(0, 0.8, 0), vel], self)


## The cell door within reach of `p`, or -1.
func cell_near(p: Vector3, r := 2.8) -> int:
	for k in Places.cells.size():
		if p.distance_to(Places.cells[k].door) < r:
			return k
	return -1


## What the body in hand is worth to somebody who wants it back.
func ransom_for(kind: int, id: int) -> int:
	var g = Net.game
	if kind == NPC:
		var bonus: int = {"mafia": 600, "magnata": 1800, "socialite": 450, "tourist": 150, "traficante": 400, "vapor": 300, "guarda": 250, "seguranca": 300}.get(DB.ARCHETYPES[g.crowd.arch[id]].id, 60)
		return clampi(g.crowd.money[id] * 4 + bonus, 150, 2400)
	var v = g.players.get(id)
	return maxi(50, int(v.st.money * 0.5)) if v != null else 0


## Hands the body over at the steel door: the NPC is not seen again, the player comes round
## inside the lane with less in their pockets and the kidnapper gets paid.
@rpc("any_peer", "call_remote", "reliable")
func srv_ransom() -> void:
	var g = Net.game
	var pid := Net.sender()
	var p = g.players.get(pid)
	if p == null or not hauls.has(pid) or cell_near(p.global_position) < 0:
		return
	var h: Dictionary = hauls[pid]
	var door: Dictionary = Places.cells[cell_near(p.global_position)]
	var pay := ransom_for(h.kind, h.id)
	if h.kind == PLAYER:
		var v = g.players.get(h.id)
		if v == null or MatchState.time < _ransomed.get(h.id, 0.0):
			g.send(pid, "cl_toast", ["Nobody is paying for that one again so soon"])
			return
		_ransomed[h.id] = MatchState.time + RANSOM_COOLDOWN
		pay = mini(pay, v.st.money)
		v.st.money -= pay
		v.st.ko = 0.0
		g.push_state(v)
		_srv_release(pid)
		g.srv_teleport(v.id, door.door + door.face * 1.2)
		g.send(v.id, "cl_toast", ["You were held for ransom. Your family paid R$%d" % pay])
	else:
		var i: int = h.id
		var spot: Vector3 = g.crowd.pos[i]
		_srv_release(pid)
		g.crowd.money[i] = 0
		g.crowd.srv_vanish(i)
		Crime.report_crime(spot, pid, 3)
	p.st.money += pay
	g.push_state(p)
	g.send(pid, "cl_toast", ["RANSOM  +R$%d" % pay])
	g.bcast("cl_sound", ["cash", door.door + Vector3(0, 1.0, 0)])
	Crime.report_tip(door.door, pid, 3)


## Drops the body where it is, and tells everyone where that was.
func _srv_release(pid: int) -> void:
	var h: Dictionary = hauls[pid]
	Net.game.bcast("cl_haul", [pid, h.kind, h.id, false, h.pos, h.yaw], self)


func _srv_tick() -> void:
	var g = Net.game
	for pid in hauls.keys():
		var h: Dictionary = hauls[pid]
		var p = g.players.get(pid)
		var out: bool = p == null or not p.can_fight() or p.st.jail > 0.0 or g.motos.bike_of(pid) >= 0
		if not out:
			out = _gone(h.kind, h.id)
		if out:
			_srv_release(pid)
	for h in flung.duplicate():
		if _gone(h.kind, h.id):
			flung.erase(h)
			_free_body(h.kind, h.id, h.pos, h.yaw)


## Whether the body has come round, died or left, so there is nothing left to haul.
func _gone(kind: int, id: int) -> bool:
	var g = Net.game
	if kind == NPC:
		return g.crowd.state[id] != Crowd.KO
	var v = g.players.get(id)
	return v == null or v.st.ko <= 0.0 or v.st.dead


# --- everywhere ---

@rpc("authority", "call_remote", "reliable")
func cl_haul(hauler: int, kind: int, id: int, on: bool, at: Vector3, yaw: float) -> void:
	var g = Net.game
	if on:
		if hauls.has(hauler):
			_end(hauler)
		hauls[hauler] = {"kind": kind, "id": id, "pos": at, "vel": Vector3.ZERO, "yaw": yaw, "spd": 0.0, "base": at.y}
		_grab(kind, id)
		var p = g.players.get(hauler)
		if p != null:
			p.dragging = true
		Sfx.play("thud", at, -6.0)
		return
	if hauls.has(hauler):
		var h: Dictionary = hauls[hauler]
		h.pos = at
		h.yaw = yaw
		_end(hauler)
	else:
		# A throw landed or the haul was never known here: make sure the body is put down.
		_free_body(kind, id, at, yaw)


@rpc("authority", "call_remote", "reliable")
func cl_throw(hauler: int, kind: int, id: int, from: Vector3, vel: Vector3) -> void:
	var g = Net.game
	var yaw := atan2(-vel.x, -vel.z)
	if hauls.has(hauler):
		hauls.erase(hauler)
	var p = g.players.get(hauler)
	if p != null:
		p.dragging = false
	flung.append({"kind": kind, "id": id, "pos": from, "vel": vel, "yaw": yaw, "t": 0.0, "base": from.y - 0.8})
	_grab(kind, id)
	Sfx.play("whoosh", from, -3.0)


## Late joiners learn who is holding what.
func snapshot() -> Array:
	var out: Array = []
	for pid in hauls:
		var h: Dictionary = hauls[pid]
		out.append([pid, h.kind, h.id, h.pos, h.yaw])
	return out


@rpc("authority", "call_remote", "reliable")
func cl_sync(snap: Array) -> void:
	for e in snap:
		cl_haul(e[0], e[1], e[2], true, e[3], e[4])


## The body becomes this node's to move.
func _grab(kind: int, id: int) -> void:
	var g = Net.game
	if kind == PLAYER:
		var v = g.players.get(id)
		if v != null:
			v.dragged = true
			v.drag_at = v.global_position
			v.drag_yaw = v.rotation.y
		return
	var pup := _take_puppet(id)
	if not pup.is_empty():
		g.crowd._hide(id)


## A haul has stopped on this machine: the body is put down where it lies.
func _end(hauler: int) -> void:
	var g = Net.game
	var h: Dictionary = hauls[hauler]
	hauls.erase(hauler)
	var p = g.players.get(hauler)
	if p != null:
		p.dragging = false
	_free_body(h.kind, h.id, h.pos, h.yaw)


func _free_body(kind: int, id: int, at: Vector3, yaw: float) -> void:
	var g = Net.game
	if kind == PLAYER:
		var v = g.players.get(id)
		if v != null:
			v.dragged = false
			v.drag_fly = 0.0
			v.drag_tumble = false
		return
	_give_back(id)
	g.crowd.haul_end(id, at, yaw)
	if multiplayer.is_server():
		g.crowd.srv_haul_rest(id, at)


# --- puppets ---

func _take_puppet(i: int) -> Dictionary:
	if _puppet_of.has(i):
		return _puppet_of[i]
	var crowd = Net.game.crowd
	var pup: Dictionary = {}
	for p in _puppets:
		if p.i < 0:
			pup = p
			break
	if pup.is_empty():
		if _puppets.size() >= PUPPETS:
			return {}
		var root := Node3D.new()
		add_child(root)
		var mats := Kit.rig_materials()
		var mm := Kit.add_to(root, 1, AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6)), mats)
		pup = {"root": root, "mm": mm, "rig": CharRig.new(), "mats": mats, "i": -1}
		_puppets.append(pup)
	pup.i = i
	pup.root.visible = true
	var look: Color = crowd.look_of(i)
	pup.mm.set_instance_color(0, look)
	# Pose and prop bits are the rig's business; what is worn is the NPC's own flags.
	pup.mm.set_instance_custom_data(0, Color(0.0, 0.0, crowd.flags_of(i), 0.0))
	pup.mm.set_instance_transform(0, Kit.xform(Vector3.ZERO, 0.0, crowd.width_of(i), crowd.scale_of(i)))
	pup.rig.flail_seed = fmod(i * 0.618, 1.0)
	_puppet_of[i] = pup
	return pup


func _give_back(i: int) -> void:
	if not _puppet_of.has(i):
		return
	var pup: Dictionary = _puppet_of[i]
	pup.i = -1
	pup.root.visible = false
	_puppet_of.erase(i)


## A new match: nobody is holding anybody.
func reset() -> void:
	var g = Net.game
	for pid in hauls:
		var p = g.players.get(pid)
		if p != null:
			p.dragging = false
	for h in hauls.values() + flung:
		if h.kind == PLAYER:
			var v = g.players.get(h.id)
			if v != null:
				v.dragged = false
		else:
			_give_back(h.id)
	hauls.clear()
	flung.clear()
	_ransomed.clear()


# --- the sim ---

func _process(delta: float) -> void:
	var g = Net.game
	if g == null or g.crowd == null:
		return
	delta = minf(delta, 0.05)
	for pid in hauls.keys():
		_step_held(pid, hauls[pid], delta)
	for h in flung.duplicate():
		_step_flung(h, delta)
	for pid in hauls:
		_show(hauls[pid], hauls[pid].spd, false)
	for h in flung:
		_show(h, 1.0, true)
	if multiplayer.is_server():
		_srv_tick()


func _step_held(pid: int, h: Dictionary, delta: float) -> void:
	var g = Net.game
	var p = g.players.get(pid)
	if p == null:
		return
	var anchor: Vector3 = p.global_position
	var to := Vector3(h.pos.x - anchor.x, 0.0, h.pos.z - anchor.z)
	var d := to.length()
	if d < 0.01:
		to = Basis(Vector3.UP, p.rotation.y) * Vector3(0, 0, 1)
		d = 1.0
	var dir := to / d
	# A weight on a springy rope: it lags, overshoots and swings wide on a corner.
	var want := anchor + dir * ROPE
	var acc := Vector3(want.x - h.pos.x, 0.0, want.z - h.pos.z) * 55.0
	h.vel += acc * delta
	h.vel *= exp(-7.0 * delta)
	var step: Vector3 = h.vel * delta
	var np: Vector3 = h.pos + step
	if h.pos.y < 1.0 and Nav.ready():
		np = Nav.slide(h.pos, step)
	np.y = h.pos.y
	# Never further from the hands than the rope can reach.
	var off := Vector3(np.x - anchor.x, 0.0, np.z - anchor.z)
	if off.length() > ROPE * 1.4:
		off = off.normalized() * ROPE * 1.4
		np.x = anchor.x + off.x
		np.z = anchor.z + off.z
	h.spd = lerpf(h.spd, clampf((np - h.pos).length() / maxf(delta, 0.001) / 4.0, 0.0, 1.0), minf(1.0, 8.0 * delta))
	h.pos = np
	h.pos.y = _ground(np, anchor.y)
	h.base = anchor.y
	# The head leads: the body lies along the rope with its feet trailing.
	var face := Kit.face(Vector3(h.pos.x - anchor.x, 0.0, h.pos.z - anchor.z))
	h.yaw = lerp_angle(h.yaw, face, minf(1.0, 12.0 * delta))
	_apply(h)


func _step_flung(h: Dictionary, delta: float) -> void:
	var g = Net.game
	h.t += delta
	h.vel.y -= GRAVITY * delta
	var np: Vector3 = h.pos + h.vel * delta
	# A wall stops it dead and drops it.
	var space := get_world_3d().direct_space_state
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(h.pos, np, 1))
	if not wall.is_empty() and absf(wall.normal.y) < 0.5:
		np = wall.position + wall.normal * 0.3
		h.vel.x = wall.normal.x * 1.0
		h.vel.z = wall.normal.z * 1.0
	var ground := _ground(np, h.base)
	if np.y <= ground and h.vel.y < 0.0 or h.t > 4.0:
		np.y = ground
		h.pos = np
		_apply(h)
		_land(h)
		return
	h.pos = np
	_apply(h)


func _land(h: Dictionary) -> void:
	var g = Net.game
	flung.erase(h)
	Sfx.play("thud", h.pos, 2.0)
	g.fx.puff(h.pos + Vector3(0, 0.1, 0), Vector3(0, 0.6, 0), 0.7, Color(0.78, 0.72, 0.62, 0.7))
	if h.kind == PLAYER and g.local_player != null and h.id == g.local_player.id:
		g.local_player.rig.shake = maxf(g.local_player.rig.shake, 0.3)
	if multiplayer.is_server():
		if h.kind == NPC:
			if g.crowd.hp[h.id] > THROW_DAMAGE + 5.0:
				g.crowd.hp[h.id] -= THROW_DAMAGE
		else:
			var v = g.players.get(h.id)
			if v != null and v.st.hp > THROW_DAMAGE + 5.0 and not v.st.get("god", false):
				v.st.hp -= THROW_DAMAGE
				g.push_state(v)
	_free_body(h.kind, h.id, h.pos, h.yaw)


## Writes the body's new place into whatever draws it and whatever hit-tests it.
func _apply(h: Dictionary) -> void:
	var g = Net.game
	if h.kind == PLAYER:
		var v = g.players.get(h.id)
		if v != null:
			v.drag_at = h.pos
			v.drag_yaw = h.yaw
		return
	g.crowd.pos[h.id] = h.pos
	g.crowd.set_yaw(h.id, h.yaw)


func _show(h: Dictionary, fly: float, tumble: bool) -> void:
	if h.kind == PLAYER:
		var v = Net.game.players.get(h.id)
		if v != null:
			v.drag_fly = clampf(0.35 + fly * 0.65, 0.0, 1.0)
			v.drag_tumble = tumble
		return
	if not _puppet_of.has(h.id):
		return
	var pup: Dictionary = _puppet_of[h.id]
	pup.root.global_position = h.pos
	pup.root.rotation.y = h.yaw
	pup.rig.flail = clampf(0.35 + fly * 0.65, 0.0, 1.0)
	pup.rig.tumble = tumble
	pup.rig.update(get_process_delta_time(), CharRig.GROUND, CharRig.FLAIL, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false)
	pup.rig.apply(pup.mats)


## The ground height under `p`: whatever the world's colliders say, or `fallback`.
func _ground(p: Vector3, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, fallback + 1.2, p.z), Vector3(p.x, fallback - 3.0, p.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else fallback
