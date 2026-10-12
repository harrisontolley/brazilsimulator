extends Node3D
## Match scene and RPC hub. Lives at /root/Game on every peer.
##
## srv_* run on the host (clients call them through to_server).
## cl_*  run on clients (the host calls them through bcast / send, which also
##       invoke the host's own copy directly).

const Player := preload("res://scenes/player/player.gd")
const Beach := preload("res://scenes/world/beach.gd")
const Crowd := preload("res://scenes/crowd/crowd_manager.gd")
const Police := preload("res://scenes/police/police_manager.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const CombatFx := preload("res://scenes/fx/combat_fx.gd")

const END_SCREEN_TIME := 15.0
const PICKUP_RANGE := 2.6
const VENDOR_RANGE := 4.5
const PICKUP_COUNT := 30

var players := {}       # peer id -> Player node
var ready_peers: Array = []  # server: peers that have loaded this scene
var drops := {}         # drop id -> {pos, money, items, node}
var crowd: Node3D
var police: Node3D
var hud: CanvasLayer
var fx: Node3D
var local_player: CharacterBody3D

var _players_root: Node3D
var _drops_root: Node3D
var _next_drop := 1
var _move_t := 0.0
var _clock_t := 0.0
var _end_t := 0.0
var _od_t := 0.0
var _last_attack := {}
var _last_ping := {}
var _respawn := {}


func _ready() -> void:
	Net.game = self
	add_child(Beach.new())
	crowd = Crowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	police = Police.new()
	police.name = "Police"
	add_child(police)
	_players_root = Node3D.new()
	add_child(_players_root)
	_drops_root = Node3D.new()
	add_child(_drops_root)
	fx = CombatFx.new()
	add_child(fx)
	hud = Hud.new()
	add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if multiplayer.is_server():
		ready_peers = [1]
		multiplayer.peer_disconnected.connect(_on_peer_left)
		Crime.noise.connect(_on_noise)
		_make_player(1, Net.local_name, DB.spawn_point())
		_srv_start_match()
	else:
		srv_client_ready.rpc_id(1, Net.local_name)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_debug_shot(a.trim_prefix("--shot="))
		elif a == "--showcase" and multiplayer.is_server():
			_debug_showcase()
		elif a.begins_with("--cam="):
			_debug_cam(a.trim_prefix("--cam="))
		elif a.begins_with("--time="):
			MatchState.time = float(a.trim_prefix("--time="))


func _exit_tree() -> void:
	if Net.game == self:
		Net.game = null


func _debug_shot(path: String) -> void:
	await get_tree().create_timer(4.0).timeout
	print("fps ", Engine.get_frames_per_second())
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## Fixed camera for --shot: x,y,z,yaw,pitch in metres and degrees.
func _debug_cam(spec: String) -> void:
	var v := spec.split_floats(",")
	var cam := Camera3D.new()
	cam.far = 3000.0
	cam.fov = 70.0
	add_child(cam)
	cam.position = Vector3(v[0], v[1], v[2])
	cam.rotation_degrees = Vector3(v[4], v[3], 0.0)
	cam.current = true
	hud.visible = false


## Stages every character look and state in front of a fixed camera, for --shot.
func _debug_showcase() -> void:
	var at := Vector3(0, 0, 10)
	var back := at + Vector3(0, 0, -8.5)
	local_player.global_position = back + Vector3(1, 0.2, 0)
	local_player.rotation.y = PI
	local_player.rig.zoom(1)
	local_player.st.money = 1500
	local_player.st.heat = 2
	crowd.debug_showcase(at)
	police.debug_pose(0, back + Vector3(-4, 0, 0), Police.PATROL)
	police.debug_pose(1, back + Vector3(-1.5, 0, 0), Police.CHASE)
	police.debug_pose(2, back + Vector3(3.5, 0, 0), Police.DOWN)
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.look_at_from_position(at + Vector3(0, 3.0, 2.5), at + Vector3(0, 0.6, -6.5))
	cam.current = true
	await get_tree().create_timer(3.88).timeout
	cl_fx(back + Vector3(-1.5, 1.5, -0.4), back + Vector3(1, 0.9, 0), false, DB.WHO_COP, 1, DB.WHO_PLAYER, 1)
	cl_fx(at + Vector3(5.4, 1.3, -5), at + Vector3(5.4, 1.3, -4.2), true, DB.WHO_NPC, -1, DB.WHO_NONE, 0)


# --- rpc plumbing ---

func send(pid: int, method: StringName, args: Array = [], node: Node = self) -> void:
	if pid == multiplayer.get_unique_id():
		node.callv(method, args)
	else:
		Callable(node, "rpc_id").callv([pid, method] + args)


func bcast(method: StringName, args: Array = [], node: Node = self) -> void:
	for pid in ready_peers:
		send(pid, method, args, node)


func to_server(method: StringName, args: Array = [], node: Node = self) -> void:
	send(1, method, args, node)


# --- joining / match lifecycle ---

@rpc("any_peer", "call_remote", "reliable")
func srv_client_ready(pname: String) -> void:
	var pid := Net.sender()
	if players.has(pid):
		return
	var drop_data: Array = []
	for id in drops:
		drop_data.append([id, drops[id].pos, drops[id].money, drops[id].items])
	cl_init.rpc_id(pid, MatchState.seed_value, MatchState.duration, MatchState.time, MatchState.ended, _players_data(), crowd.snapshot(), drop_data)
	ready_peers.append(pid)
	bcast("cl_spawn", [pid, pname.left(16), DB.spawn_point(), Player.fresh_state()])


@rpc("authority", "call_remote", "reliable")
func cl_init(seed_value: int, duration: float, time: float, ended: bool, pdata: Array, crowd_snap: Array, drop_data: Array) -> void:
	cl_match_start(seed_value, duration, pdata)
	MatchState.time = time
	MatchState.ended = ended
	crowd.apply_snapshot(crowd_snap)
	for d in drop_data:
		cl_drop_add(d[0], d[1], d[2], d[3])


@rpc("authority", "call_remote", "reliable")
func cl_match_start(seed_value: int, duration: float, pdata: Array) -> void:
	MatchState.seed_value = seed_value
	MatchState.duration = duration
	MatchState.time = 0.0
	MatchState.ended = false
	MatchState.running = true
	crowd.setup(seed_value)
	for id in drops.keys():
		cl_drop_remove(id)
	for e in pdata:
		cl_spawn(e[0], e[1], e[2], e[3])
	hud.toast("Match started. Richest kid at the whistle wins.")


@rpc("authority", "call_remote", "reliable")
func cl_spawn(id: int, pname: String, pos: Vector3, st: Dictionary) -> void:
	var p = players.get(id)
	if p == null:
		p = _make_player(id, pname, pos)
	p.st = st
	p.net_pos = pos
	p.global_position = pos
	p.velocity = Vector3.ZERO


@rpc("authority", "call_remote", "reliable")
func cl_despawn(id: int) -> void:
	var p = players.get(id)
	if p != null:
		players.erase(id)
		p.queue_free()


func _make_player(id: int, pname: String, pos: Vector3) -> CharacterBody3D:
	var p := Player.new()
	p.id = id
	p.pname = pname
	p.is_local = id == multiplayer.get_unique_id()
	p.name = str(id)
	p.position = pos
	p.net_pos = pos
	players[id] = p
	_players_root.add_child(p)
	if p.is_local:
		local_player = p
	return p


func _players_data() -> Array:
	var out: Array = []
	for id in players:
		var p = players[id]
		out.append([id, p.pname, p.global_position, p.st])
	return out


func _srv_start_match() -> void:
	MatchState.seed_value = randi()
	_respawn.clear()
	police.reset()
	var pdata: Array = []
	for id in players:
		var p = players[id]
		p.wanted_t = 0.0
		pdata.append([id, p.pname, DB.spawn_point(), Player.fresh_state()])
	bcast("cl_match_start", [MatchState.seed_value, MatchState.duration, pdata])
	# Loose drugs and ammo scattered on the sand.
	var loot := ["cocaine", "weed", "meth", "ammo"]
	for i in PICKUP_COUNT:
		var item: String = loot[randi() % loot.size()]
		srv_add_drop(DB.spawn_point(), 0, {item: 6 if item == "ammo" else 1})


func _on_peer_left(pid: int) -> void:
	ready_peers.erase(pid)
	_respawn.erase(pid)
	if players.has(pid):
		bcast("cl_despawn", [pid])


# --- per-frame ---

func _process(delta: float) -> void:
	Kit.tick()
	# Loot turns and bobs so it catches the eye on the sand.
	var spin := Kit.now()
	for id in drops:
		var turn: Node3D = drops[id].turn
		turn.rotation.y = spin * 1.6 + id
		turn.position.y = 0.3 + sin(spin * 2.5 + id) * 0.08
	if multiplayer.is_server():
		_srv_process(delta)


func _srv_process(delta: float) -> void:
	if MatchState.ended:
		_end_t -= delta
		if _end_t <= 0.0:
			_srv_start_match()
		return
	if MatchState.time >= MatchState.duration:
		_end_t = END_SCREEN_TIME
		bcast("cl_match_end")
		return

	_od_t += delta
	var od_tick := _od_t >= 0.5
	if od_tick:
		_od_t = 0.0
	for id in players.keys():
		_srv_tick_player(players[id], delta, od_tick)

	_move_t -= delta
	if _move_t <= 0.0 and ready_peers.size() > 1:
		_move_t = 0.05
		var ids := PackedInt32Array()
		var ps := PackedVector3Array()
		var yaws := PackedFloat32Array()
		var mvs := PackedByteArray()
		for id in players:
			var p = players[id]
			ids.append(id)
			ps.append(p.global_position if p.is_local else p.net_pos)
			yaws.append(p.rotation.y if p.is_local else p.net_yaw)
			mvs.append(p.net_byte())
		for pid in ready_peers:
			if pid != 1:
				cl_moves.rpc_id(pid, ids, ps, yaws, mvs)

	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 2.0
		for pid in ready_peers:
			if pid != 1:
				cl_clock.rpc_id(pid, MatchState.time)


func _srv_tick_player(p: CharacterBody3D, delta: float, od_tick: bool) -> void:
	var st: Dictionary = p.st
	var dirty := false
	for d in st.drugs.keys():
		var e = st.drugs[d]
		e.t -= delta
		if e.t <= 0.0:
			var comedown: float = DB.ITEMS[d].comedown
			if e.phase == "high" and comedown > 0.0:
				st.drugs[d] = {"phase": "down", "t": comedown}
			else:
				st.drugs.erase(d)
			dirty = true
	for d in st.tol:
		st.tol[d] = maxf(0.0, st.tol[d] - DB.TOLERANCE_DECAY * delta)
	if st.jail > 0.0:
		st.jail -= delta
		if st.jail <= 0.0:
			st.jail = 0.0
			dirty = true
			srv_teleport(p.id, DB.RELEASE_POS + Vector3(randf_range(-6, 6), 0, 0))
	if _respawn.has(p.id):
		_respawn[p.id] -= delta
		if _respawn[p.id] <= 0.0:
			_respawn.erase(p.id)
			st.dead = false
			st.hp = 100.0
			dirty = true
			srv_teleport(p.id, DB.spawn_point())
	if dirty:
		push_state(p)
	# Cocaine overdose: heart gives out.
	if od_tick and p.drug_phase("cocaine") == "od":
		srv_damage(p.id, 3.0, -1)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_move(pos: Vector3, yaw: float, mv: int) -> void:
	var p = players.get(Net.sender())
	if p != null and not p.is_local:
		p.net_pos = pos
		p.net_yaw = yaw
		p.net_mv = mv & 15


@rpc("authority", "call_remote", "unreliable_ordered")
func cl_moves(ids: PackedInt32Array, ps: PackedVector3Array, yaws: PackedFloat32Array, mvs: PackedByteArray) -> void:
	for i in ids.size():
		var p = players.get(ids[i])
		if p != null and not p.is_local:
			p.net_pos = ps[i]
			p.net_yaw = yaws[i]
			p.net_mv = mvs[i]


@rpc("authority", "call_remote", "unreliable_ordered")
func cl_clock(time: float) -> void:
	if absf(MatchState.time - time) > 0.25:
		MatchState.time = time


@rpc("authority", "call_remote", "reliable")
func cl_match_end() -> void:
	MatchState.ended = true
	hud.show_winner()


# --- player state ---

func push_state(p: CharacterBody3D) -> void:
	bcast("cl_state", [p.id, p.st])


@rpc("authority", "call_remote", "reliable")
func cl_state(id: int, st: Dictionary) -> void:
	var p = players.get(id)
	if p != null:
		p.st = st


func srv_teleport(pid: int, pos: Vector3) -> void:
	var p = players.get(pid)
	if p == null:
		return
	p.net_pos = pos
	p.global_position = pos
	send(pid, "cl_teleport", [pos])


@rpc("authority", "call_remote", "reliable")
func cl_teleport(pos: Vector3) -> void:
	if local_player != null:
		local_player.global_position = pos
		local_player.velocity = Vector3.ZERO


@rpc("authority", "call_remote", "reliable")
func cl_toast(text: String) -> void:
	hud.toast(text)


@rpc("authority", "call_remote", "unreliable")
func cl_rob_meter(v: float) -> void:
	hud.set_rob_meter(v)


@rpc("authority", "call_remote", "unreliable")
func cl_ping(pos: Vector3) -> void:
	hud.add_ping(pos)


# --- combat ---

func srv_damage(pid: int, amount: float, attacker: int) -> void:
	var p = players.get(pid)
	if p == null or not p.can_fight():
		return
	p.st.hp -= amount * p.damage_taken_mult()
	if p.st.hp <= 0.0:
		_srv_kill(p, attacker)
	push_state(p)


func _srv_kill(p: CharacterBody3D, attacker: int) -> void:
	var st: Dictionary = p.st
	var items: Dictionary = st.inv.duplicate()
	items.erase("fists")
	if st.ammo > 0:
		items["ammo"] = st.ammo
	if st.money > 0 or not items.is_empty():
		srv_add_drop(p.global_position, st.money, items)
	var kills: int = st.kills
	p.st = Player.fresh_state()
	p.st.kills = kills
	p.st.hp = 0.0
	p.st.dead = true
	p.wanted_t = 0.0
	_respawn[p.id] = DB.RESPAWN_TIME
	police.release_chase(p.id)
	var killer = players.get(attacker)
	if killer != null and killer != p:
		killer.st.kills += 1
		push_state(killer)
		bcast("cl_toast", ["%s killed %s" % [killer.pname, p.pname]])
	else:
		bcast("cl_toast", ["%s died" % p.pname])


@rpc("any_peer", "call_remote", "reliable")
func srv_attack(dir: Vector3) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	if p == null or not p.can_fight() or dir.length_squared() < 0.5:
		return
	var w = DB.ITEMS[p.st.equipped]
	var now := Time.get_ticks_msec()
	if now - _last_attack.get(pid, 0) < w.cooldown * 1000.0 - 60.0:
		return
	_last_attack[pid] = now

	dir = dir.normalized()
	var origin: Vector3 = p.global_position + Player.HEAD
	var reach: float = w.range
	var radius := 0.9 if w.melee else 0.5
	if not w.melee:
		if p.st.ammo <= 0:
			return
		p.st.ammo -= 1
		push_state(p)
		if p.is_sniper():
			reach *= 2.5
		else:
			dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * w.spread).normalized()

	var hit := _ray_hit(origin, dir, reach, radius, pid)
	var dmg: float = w.damage * (p.melee_mult() if w.melee else 1.0)
	match hit.type:
		DB.WHO_PLAYER: srv_damage(hit.id, dmg, pid)
		DB.WHO_COP: police.srv_damage_cop(hit.id, dmg, pid)
		DB.WHO_NPC: crowd.srv_damage_npc(hit.id, dmg, pid)
	bcast("cl_fx", [origin, origin + dir * hit.t, w.melee, DB.WHO_PLAYER, pid, hit.type, hit.id])

	if not w.melee:
		Crime.report_noise(origin, 90.0, pid)
		Crime.report_crime(origin, pid, 3)
	elif hit.type != DB.WHO_NONE:
		Crime.report_crime(origin, pid, 2)


func _ray_hit(o: Vector3, d: Vector3, max_t: float, radius: float, exclude: int) -> Dictionary:
	var best := {"type": DB.WHO_NONE, "id": -1, "t": max_t}
	var q := PhysicsRayQueryParameters3D.create(o, o + d * max_t, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		best.t = o.distance_to(wall.position)
	for pid in players:
		var p = players[pid]
		if pid == exclude or not p.can_fight():
			continue
		var t := DB.ray_point(o, d, p.global_position + Vector3(0, 0.8, 0), radius, best.t)
		if t >= 0.0:
			best = {"type": DB.WHO_PLAYER, "id": pid, "t": t}
	var c: Array = police.ray_pick(o, d, best.t, radius)
	if c[0] >= 0:
		best = {"type": DB.WHO_COP, "id": c[0], "t": c[1]}
	var n: Array = crowd.ray_pick(o, d, best.t, radius)
	if n[0] >= 0:
		best = {"type": DB.WHO_NPC, "id": n[0], "t": n[1]}
	return best


## One attack: who threw it, where it went and who (if anyone) it struck. DB.WHO_* types.
@rpc("authority", "call_remote", "unreliable")
func cl_fx(from: Vector3, to: Vector3, melee: bool, src_type: int, src_id: int, hit_type: int, hit_id: int) -> void:
	_fx_actor(src_type, src_id, true)
	_fx_actor(hit_type, hit_id, false)
	if not melee and src_type == DB.WHO_PLAYER and local_player != null and src_id == local_player.id and local_player.rig.first_person():
		from = local_player.muzzle()
	fx.strike(from, to, melee, hit_type != DB.WHO_NONE)


func _fx_actor(type: int, id: int, attack: bool) -> void:
	match type:
		DB.WHO_PLAYER:
			var p = players.get(id)
			if p != null:
				p.fx_event(attack)
		DB.WHO_COP: police.fx_event(id, attack)
		DB.WHO_NPC: crowd.fx_event(id, attack)


# --- arrest ---

func srv_arrest(pid: int) -> void:
	var p = players.get(pid)
	if p == null or not p.can_fight():
		return
	# Gear and contraband confiscated; cash stays in your pocket.
	p.st.inv = {"fists": 1}
	p.st.equipped = "fists"
	p.st.ammo = 0
	p.st.heat = 0
	p.st.jail = DB.JAIL_TIME
	p.wanted_t = 0.0
	police.release_chase(pid)
	push_state(p)
	srv_teleport(pid, DB.PRISON_POS + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	bcast("cl_toast", ["%s got arrested" % p.pname])


func _on_noise(pos: Vector3, radius: float, pid: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ping.get(pid, 0) < 800:
		return
	_last_ping[pid] = now
	for id in ready_peers:
		var p = players.get(id)
		if id != pid and p != null and p.global_position.distance_to(pos) < radius:
			send(id, "cl_ping", [pos])


# --- items, drops, vendors ---

func _give(st: Dictionary, item: String, n: int) -> void:
	if item == "ammo":
		st.ammo += n
	else:
		st.inv[item] = st.inv.get(item, 0) + n


func srv_add_drop(pos: Vector3, money: int, items: Dictionary) -> void:
	bcast("cl_drop_add", [_next_drop, Vector3(pos.x, 0.0, pos.z), money, items])
	_next_drop += 1


@rpc("authority", "call_remote", "reliable")
func cl_drop_add(id: int, pos: Vector3, money: int, items: Dictionary) -> void:
	# Cash is a banded stack of green notes; anything else is a magenta crate.
	var root := Node3D.new()
	root.position = pos
	var turn := Node3D.new()
	root.add_child(turn)
	var color := Color(0.25, 0.8, 0.35) if money > 0 else Color(0.85, 0.3, 0.8)
	turn.add_child(_drop_part(Vector3(0.55, 0.22, 0.3) if money > 0 else Vector3(0.42, 0.36, 0.42), color))
	if money > 0:
		turn.add_child(_drop_part(Vector3(0.12, 0.24, 0.32), Color(1.0, 0.85, 0.3)))
	var parts: Array = []
	if money > 0:
		parts.append("R$%d" % money)
	for item in items:
		parts.append("%s x%d" % [item, items[item]])
	var label := Label3D.new()
	label.text = ", ".join(parts)
	label.font_size = 40
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.85
	root.add_child(label)
	_drops_root.add_child(root)
	drops[id] = {"pos": pos, "money": money, "items": items, "node": root, "turn": turn}


func _drop_part(size: Vector3, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.4
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	return mi


@rpc("authority", "call_remote", "reliable")
func cl_drop_remove(id: int) -> void:
	if drops.has(id):
		drops[id].node.queue_free()
		drops.erase(id)


## Local F key: open a vendor if one is close, otherwise grab the nearest drop.
func interact() -> void:
	var at := local_player.global_position
	for vi in DB.VENDORS.size():
		if at.distance_to(DB.VENDORS[vi].pos) < VENDOR_RANGE:
			hud.open_shop(vi)
			return
	var best := -1
	var best_d := PICKUP_RANGE
	for id in drops:
		var d := at.distance_to(drops[id].pos)
		if d < best_d:
			best = id
			best_d = d
	if best >= 0:
		to_server("srv_pickup", [best])


@rpc("any_peer", "call_remote", "reliable")
func srv_pickup(id: int) -> void:
	var p = players.get(Net.sender())
	if p == null or not p.can_fight() or not drops.has(id):
		return
	var drop = drops[id]
	if p.global_position.distance_to(drop.pos) > PICKUP_RANGE + 1.5:
		return
	p.st.money += drop.money
	for item in drop.items:
		_give(p.st, item, drop.items[item])
	bcast("cl_drop_remove", [id])
	push_state(p)


@rpc("any_peer", "call_remote", "reliable")
func srv_buy(vi: int, item: String) -> void:
	var p = players.get(Net.sender())
	if p == null or not p.can_fight() or vi < 0 or vi >= DB.VENDORS.size():
		return
	var v = DB.VENDORS[vi]
	if not v.stock.has(item) or p.global_position.distance_to(v.pos) > VENDOR_RANGE + 1.5:
		return
	var def = DB.ITEMS[item]
	if p.st.money < def.price or (def.type == "weapon" and p.st.inv.has(item)):
		return
	p.st.money -= def.price
	match def.type:
		"ammo": p.st.ammo += def.amount
		"weapon":
			p.st.inv[item] = 1
			p.st.ammo += 12
		_: _give(p.st, item, 1)
	push_state(p)


@rpc("any_peer", "call_remote", "reliable")
func srv_equip(item: String) -> void:
	var p = players.get(Net.sender())
	if p != null and p.can_act() and p.st.inv.has(item) and DB.ITEMS[item].type == "weapon":
		p.st.equipped = item
		push_state(p)


@rpc("any_peer", "call_remote", "reliable")
func srv_use(item: String) -> void:
	var p = players.get(Net.sender())
	if p == null or not p.can_fight() or not DB.DRUGS.has(item) or p.st.inv.get(item, 0) <= 0:
		return
	p.st.inv[item] -= 1
	if p.st.inv[item] <= 0:
		p.st.inv.erase(item)
	# Each dose stacks tolerance; past 1.0 the hit becomes an overdose instead.
	var tol: float = p.st.tol.get(item, 0.0) + DB.TOLERANCE_PER_DOSE
	p.st.tol[item] = tol
	if tol > 1.0:
		p.st.drugs[item] = {"phase": "od", "t": DB.ITEMS[item].od}
	else:
		p.st.drugs[item] = {"phase": "high", "t": DB.ITEMS[item].duration}
	push_state(p)
