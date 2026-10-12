extends "res://scenes/world/world_kit.gd"
## The director: every so often the host starts something big somewhere on the map, so
## there is never a quiet minute.
##
## The host sends one message per event (what, where, when, a seed). Everything a player
## sees of it is built from that message and the match clock, so it stays in step.

const Kit := preload("res://scenes/characters/char_kit.gd")

enum { ARRASTAO, CARRO_FORTE, BLOCO, TIROTEIO, BLITZ, TEMPORAL, GOL, GRINGOS }

const NAMES := ["arrastao", "carroforte", "bloco", "tiroteio", "blitz", "temporal", "gol", "gringos"]
## Seconds of calm between one event ending and the next starting.
const GAP := Vector2(18.0, 34.0)
const FIRST := 25.0
const GANG := 26
const SWEEP_SPEED := 7.5
const SWEEP_LEN := 140.0
const BLOCO_LEN := 110.0
const TRUCK_HP := 220.0

## What is happening now (-1: nothing), where, and from when until when in match time.
var kind := -1
var at := Vector3.ZERO
var t0 := 0.0
var dur := 0.0
## 0..1 while a downpour is on, for the sky and the sound.
var storm := 0.0
## Decaying lightning flash, for the sky.
var flash := 0.0

var _seed := 0
var _dir := 1.0
var _stage: Node3D
var _gang: MultiMesh
var _gang_off: Array = []
var _mover: Node3D
var _rain: GPUParticles3D
var _fx_i := 0
var _fx_t := 0.0

# server only
var _next_t := FIRST
var _last := -1
var _forced := -1
var _forced_x := INF
var _tick := 0.0
var _noise_t := 0.0
var _truck_hp := 0.0
var _attackers := {}
var _guard_cd := 0.0


func _ready() -> void:
	_gang = Kit.add_to(self, GANG, Layout.WORLD_AABB)
	_hide_gang()
	_rain = GPUParticles3D.new()
	_rain.amount = 2200
	_rain.lifetime = 0.7
	_rain.emitting = false
	_rain.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 0.5, 24)
	pm.direction = Vector3(0.18, -1.0, 0.06)
	pm.spread = 2.0
	pm.initial_velocity_min = 26.0
	pm.initial_velocity_max = 31.0
	pm.gravity = Vector3(0, -6, 0)
	_rain.process_material = pm
	var drop := _box_mesh(Vector3(0.03, 0.6, 0.03))
	var dm := _mat(Color(0.78, 0.86, 1.0, 0.5))
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = dm
	_rain.draw_pass_1 = drop
	add_child(_rain)


func _hide_gang() -> void:
	for j in GANG:
		_gang.set_instance_transform(j, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))


## Forces the named event to be the next one, a second from now (debug). "name@x" also
## pins where along the beach it happens.
func force(event_name: String) -> void:
	var bits := event_name.split("@")
	_forced = NAMES.find(bits[0])
	_forced_x = float(bits[1]) if bits.size() > 1 else INF
	_next_t = MatchState.time + 1.0


func snapshot() -> Array:
	return [kind, _seed, at, t0, dur]


func srv_reset() -> void:
	_next_t = FIRST
	_last = -1
	if kind >= 0:
		_srv_end()


func _posto(x: float) -> String:
	return "Posto %d" % (clampi(int((x + 300.0) / 100.0), 0, 5) + 1)


# --- server: choosing and running events ---

func _process(delta: float) -> void:
	var t := MatchState.time
	if multiplayer.is_server() and MatchState.running and not MatchState.ended:
		if kind < 0 and t >= _next_t:
			_srv_begin()
		elif kind >= 0:
			if t >= t0 + dur:
				_srv_end()
			else:
				_srv_tick(t, delta)
	_cl_tick(t, delta)


func _srv_begin() -> void:
	var g = Net.game
	var options: Array = range(NAMES.size())
	options.shuffle()
	var forced := _forced
	_forced = -1
	if forced >= 0:
		options.push_front(forced)
	for k in options:
		if k == _last and k != forced:
			continue
		var spec := _srv_plan(k)
		if spec.is_empty():
			continue
		if k == forced and _forced_x != INF:
			spec.at.x = _forced_x
		_last = k
		g.bcast("cl_event", [k, randi() % 100000, spec.at, MatchState.time, spec.dur], self)
		_srv_started(k)
		return
	_next_t = MatchState.time + 10.0


## Decides where event k would happen and for how long, or {} if it cannot right now.
func _srv_plan(k: int) -> Dictionary:
	var crowd = Net.game.crowd
	match k:
		ARRASTAO:
			return {"at": Vector3(randf_range(-210.0, 70.0), 0, randf_range(-6.0, 22.0)), "dur": SWEEP_LEN / SWEEP_SPEED + 2.0}
		CARRO_FORTE:
			var cx: float = Layout.CROSS_X[randi() % Layout.CROSS_X.size()]
			return {"at": Vector3(cx + 12.0, 0, 71.5), "dur": 45.0}
		BLOCO:
			return {"at": Vector3(randf_range(-190.0, 190.0), 0, 46.0), "dur": BLOCO_LEN / crowd.DANCE_SPEED}
		TIROTEIO:
			var tough: Array = []
			for i in crowd.count:
				if crowd.state[i] == crowd.AMBIENT and DB.ARCHETYPES[crowd.arch[i]].shoot > 0.0 and crowd.pos[i].y < 1.0:
					tough.append(i)
			if tough.size() < 2:
				return {}
			return {"at": crowd.pos[tough[randi() % tough.size()]], "dur": 24.0}
		BLITZ:
			var cx: float = Layout.CROSS_X[randi() % Layout.CROSS_X.size()]
			return {"at": Vector3(cx, 0, 77.0), "dur": 60.0}
		TEMPORAL:
			return {"at": Vector3.ZERO, "dur": 45.0}
		GOL:
			return {"at": Vector3(0, 0, 160), "dur": 12.0}
		GRINGOS:
			if crowd.gone(8).size() < 8:
				return {}
			return {"at": Vector3(randf_range(-240.0, 240.0), 0, 50.5), "dur": 25.0}
	return {}


## Host-side consequences of the event that has just been announced.
func _srv_started(k: int) -> void:
	var g = Net.game
	var crowd = g.crowd
	_tick = 0.0
	_noise_t = 0.0
	match k:
		CARRO_FORTE:
			_truck_hp = TRUCK_HP
			_attackers.clear()
			_guard_cd = 1.0
		BLOCO:
			var n := 0
			for i in crowd.count:
				var p: Vector3 = crowd.pos[i]
				if n < 110 and crowd.state[i] == crowd.AMBIENT and p.y < 1.0 and p.z > 26.0 and p.z < 52.0 and absf(p.x - at.x) < 42.0:
					crowd.srv_parade(i, Vector3(_dir, 0, 0), BLOCO_LEN, 1)
					n += 1
		TIROTEIO:
			var tough: Array = []
			for i in crowd.count:
				if crowd.state[i] == crowd.AMBIENT and DB.ARCHETYPES[crowd.arch[i]].shoot > 0.0 and crowd.pos[i].distance_to(at) < 32.0:
					tough.append(i)
			crowd.srv_scare(at, 18.0, 0.85)
			for j in range(0, mini(tough.size(), 8) - 1, 2):
				crowd.srv_duel(tough[j], tough[j + 1], dur - 2.0)
		BLITZ:
			g.police.srv_blitz(at, dur)
		TEMPORAL:
			g.police.sight_mult = 0.5
			g.bcast("cl_shelter", [t0], crowd)
		GOL:
			g.police.deaf_until = MatchState.time + 15.0
		GRINGOS:
			for i in crowd.gone(26):
				var from := at + Vector3(randf_range(-5.0, 5.0), 0, randf_range(-1.5, 0.0))
				crowd.srv_revive(i, from, randi_range(300, 1100), Vector3(randf_range(-1.0, 1.0), 0, -randf_range(0.3, 1.5)), randf_range(6.0, 28.0))


func _srv_tick(t: float, delta: float) -> void:
	var g = Net.game
	var crowd = g.crowd
	match kind:
		ARRASTAO:
			# The sweep scatters whoever it reaches and shakes the change out of them.
			_tick -= delta
			_noise_t -= delta
			if _tick > 0.0:
				return
			_tick = 0.15
			var front := at + Vector3(_dir * SWEEP_SPEED * (t - t0), 0, 0)
			if _noise_t <= 0.0:
				_noise_t = 1.5
				Crime.report_noise(front, 70.0, -1)
			for i in crowd.count:
				var p: Vector3 = crowd.pos[i]
				if crowd.state[i] != crowd.AMBIENT or absf(p.x - front.x) > 4.0 or absf(p.z - at.z) > 9.0 or p.y > 1.0 or randf() > 0.2:
					continue
				if crowd.money[i] > 0 and randf() < 0.35:
					var lost: int = mini(crowd.money[i], randi_range(8, 40))
					crowd.money[i] -= lost
					g.srv_add_drop(p, lost, {})
				crowd._srv_flee(i, front - Vector3(_dir * 3.0, 0, 0))
		CARRO_FORTE:
			# The guards answer anyone who has had a go at the truck.
			_guard_cd -= delta
			if _guard_cd > 0.0 or _attackers.is_empty():
				return
			_guard_cd = 0.8
			for pid in _attackers:
				var pl = g.players.get(pid)
				if pl == null or not pl.can_fight() or pl.global_position.distance_to(at) > 38.0:
					continue
				var hit := randf() < 0.5
				var from := at + Vector3(4.2 if randf() < 0.5 else -4.2, 1.3, -0.8)
				var to_pt: Vector3 = pl.global_position + Vector3(0, 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)))
				g.bcast("cl_fx", [from, to_pt, false, DB.WHO_NONE, -1, DB.WHO_PLAYER if hit else DB.WHO_NONE, pid])
				if hit:
					g.srv_damage(pid, 14.0, -1)


func _srv_end() -> void:
	var g = Net.game
	g.police.sight_mult = 1.0
	_next_t = MatchState.time + randf_range(GAP.x, GAP.y)
	g.bcast("cl_event", [-1, 0, Vector3.ZERO, 0.0, 0.0], self)


## An attack along a ray during the armoured truck event. Returns the distance to the truck
## if it was hit, or -1.
func srv_strike(o: Vector3, d: Vector3, reach: float, dmg: float, pid: int) -> float:
	if kind != CARRO_FORTE or _truck_hp <= 0.0:
		return -1.0
	var t := DB.ray_point(o, d, at + Vector3(0, 1.3, 0), 2.4, reach)
	if t < 0.0:
		return -1.0
	var g = Net.game
	_truck_hp -= dmg
	_attackers[pid] = true
	Crime.report_crime(at, pid, 3)
	if _truck_hp <= 0.0:
		for k in 7:
			g.srv_add_drop(at + Vector3(randf_range(-4.5, 4.5), 0, randf_range(-3.5, -0.8)), randi_range(250, 600), {})
		g.bcast("cl_sound", ["crash", at])
		g.bcast("cl_toast", ["The carro-forte is open! Cash all over the pavement"])
		_srv_end()
	return t


# --- everyone: what it looks and sounds like ---

@rpc("authority", "call_remote", "reliable")
func cl_event(k: int, seed_value: int, where: Vector3, start: float, length: float) -> void:
	if _stage != null:
		_stage.queue_free()
		_stage = null
	_mover = null
	_hide_gang()
	_rain.emitting = false
	kind = k
	_seed = seed_value
	at = where
	t0 = start
	dur = length
	_dir = 1.0 if seed_value % 2 == 0 else -1.0
	_fx_i = 0
	_fx_t = 0.0
	if k < 0:
		return
	_stage = Node3D.new()
	add_child(_stage)
	var g = Net.game
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var fresh := MatchState.time - start < 3.0
	var text := ""
	match k:
		ARRASTAO:
			text = "ARRASTÃO!  A gang is sweeping the sand near %s" % _posto(at.x)
			_gang_off.clear()
			for j in GANG:
				_gang_off.append(Vector3(rng.randf_range(0.0, 12.0), 0, rng.randf_range(-7.0, 7.0)))
				_gang.set_instance_color(j, Color.from_hsv(rng.randf(), 0.6, 0.9, rng.randf()))
			if fresh:
				Sfx.play("whistle", at, 6.0)
		CARRO_FORTE:
			text = "CARRO-FORTE unloading on the avenida by %s.  Shoot it open" % _posto(at.x)
			_build_truck()
		BLOCO:
			text = "BLOCO DE CARNAVAL coming down the calçadão at %s" % _posto(at.x)
			_build_trio()
		TIROTEIO:
			text = "TIROTEIO!  Shots fired near %s" % (_posto(at.x) if at.z < Layout.WALK_Z else "the back streets")
		BLITZ:
			text = "BLITZ: police checkpoint on a cross street by %s" % _posto(at.x)
			_build_blitz()
		TEMPORAL:
			text = "TEMPORAL!  The sky is coming down"
			_rain.emitting = true
		GOL:
			text = "GOOOOOL DO BRASIL!"
			Kit.cheer(10.0)
			if fresh and g.local_player != null:
				Sfx.play("cheer", g.local_player.global_position + Vector3(0, 3, 0), 6.0)
		GRINGOS:
			text = "ÔNIBUS DE GRINGOS just unloaded at %s.  Fresh wallets" % _posto(at.x)
			_build_coach()
	if fresh:
		g.hud.banner(text)
		if k != TEMPORAL and k != GOL:
			g.hud.add_ping(at)


func _cl_tick(t: float, delta: float) -> void:
	flash = move_toward(flash, 0.0, 3.0 * delta)
	var want_storm := 0.0
	if kind == TEMPORAL:
		want_storm = clampf(minf((t - t0) / 4.0, (t0 + dur - t) / 5.0), 0.0, 1.0)
	storm = move_toward(storm, want_storm, 0.4 * delta)
	Sfx.rain = storm
	if kind < 0:
		return
	var g = Net.game
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	_fx_t -= delta
	match kind:
		ARRASTAO:
			var gone := SWEEP_SPEED * (t - t0)
			for j in GANG:
				var off: Vector3 = _gang_off[j]
				var along := gone - off.x
				if along < 0.0 or along > SWEEP_LEN:
					_gang.set_instance_transform(j, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
					continue
				var p := at + Vector3(_dir * along, 0, off.z + sin(along * 0.2 + j) * 1.2)
				_gang.set_instance_transform(j, Kit.xform(p, Kit.face(Vector3(_dir, 0, 0)), 0.82, 0.82))
				_gang.set_instance_custom_data(j, Kit.custom(Kit.RUN, SWEEP_SPEED, Kit.F_SHORTS | (Kit.F_SHIRTLESS if j % 2 == 0 else Kit.F_TANK), 0.0))
		BLOCO:
			var lead := at + Vector3(_dir * (g.crowd.DANCE_SPEED * (t - t0) + 46.0), 0, 5.3)
			if _mover != null:
				_mover.position = lead
			if _fx_t <= 0.0:
				_fx_t = 0.45
				var over := lead - Vector3(_dir * randf_range(4.0, 90.0), -4.5, randf_range(3.0, 9.0))
				if over.distance_to(eye) < 90.0:
					g.fx.confetti(over, 16, 2.5)
		TEMPORAL:
			_rain.global_position = eye + Vector3(0, 13, 0)
			if _fx_t <= 0.0 and storm > 0.5:
				_fx_t = randf_range(4.0, 9.0)
				flash = 1.0
				Sfx.play("thunder", eye + Vector3(randf_range(-30, 30), 20, randf_range(-30, 30)), 10.0)
		GOL:
			if _fx_t <= 0.0 and _fx_i < 16:
				_fx_t = 0.6
				_fx_i += 1
				g.fx.firework(Vector3(randf_range(-260, 260), randf_range(55, 90), randf_range(150, 200)), Color.from_hsv(randf(), 0.8, 1.0))


func _props(parts: Array, p: Vector3, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = compose(parts)
	mi.material_override = _vertex_mat()
	mi.position = p
	mi.rotation.y = yaw
	_stage.add_child(mi)
	return mi


func _wheel_parts(parts: Array, xs: Array, half_w: float, r := 0.45) -> void:
	for wx in xs:
		for side in [-1.0, 1.0]:
			parts.append([_cyl(r, r, 0.28, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(wx, r, side * half_w)), Color(0.05, 0.05, 0.06)])


func _build_truck() -> void:
	var steel := Color(0.3, 0.33, 0.38)
	var parts: Array = [
		part(Vector3(-0.6, 1.75, 0), Vector3(5.2, 2.6, 2.3), steel),
		part(Vector3(-0.6, 1.3, 0), Vector3(5.24, 0.35, 2.34), Color(0.95, 0.8, 0.1)),
		part(Vector3(2.9, 1.4, 0), Vector3(1.8, 1.9, 2.2), steel.lightened(0.1)),
		part(Vector3(3.3, 1.8, 0), Vector3(1.04, 0.6, 2.0), Color(0.08, 0.11, 0.15)),
		part(Vector3(-3.22, 1.6, 0), Vector3(0.06, 2.0, 1.6), steel.darkened(0.3)),
	]
	_wheel_parts(parts, [-2.2, 2.6], 1.05)
	_props(parts, at, 0.0)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.2, 3.0, 2.3)
	cs.shape = shape
	cs.position = at + Vector3(0, 1.5, 0)
	body.add_child(cs)
	_stage.add_child(body)
	var l := Label3D.new()
	l.text = "VALORES"
	l.font_size = 200
	l.modulate = Color(0.1, 0.1, 0.1)
	l.outline_size = 0
	l.position = at + Vector3(-0.6, 2.2, -1.17)
	l.rotation.y = PI
	_stage.add_child(l)
	# Two guards with their guns out.
	for j in 2:
		var p := at + Vector3(4.2 if j == 0 else -4.2, 0, -0.8)
		_gang.set_instance_color(j, Color(0.12, 0.14, 0.2, 0.3 + j * 0.4))
		_gang.set_instance_transform(j, Kit.xform(p, 0.0, 1.25, 1.1))
		_gang.set_instance_custom_data(j, Kit.custom(Kit.AIM, 0.0, Kit.F_SUIT | Kit.F_SHADES | Kit.F_GUN, 0.0))


## Trio elétrico: the sound truck a bloco follows.
func _build_trio() -> void:
	var parts: Array = [
		part(Vector3(0, 1.6, 0), Vector3(9.0, 2.2, 2.4), Color(0.95, 0.75, 0.1)),
		part(Vector3(0, 3.0, 0), Vector3(8.0, 0.6, 2.2), Color(0.1, 0.5, 0.25)),
		part(Vector3(5.2, 1.3, 0), Vector3(1.6, 1.8, 2.3), Color(0.1, 0.3, 0.7)),
	]
	for k in 4:
		for side in [-1.0, 1.0]:
			parts.append(part(Vector3(-3.0 + k * 2.0, 1.7, side * 1.22), Vector3(1.5, 1.5, 0.06), Color(0.08, 0.08, 0.09)))
			parts.append(part(Vector3(-3.0 + k * 2.0, 1.7, side * 1.26), Vector3(0.9, 0.9, 0.04), Color(0.3, 0.3, 0.32)))
	_wheel_parts(parts, [-3.0, 3.6], 1.1)
	_mover = Node3D.new()
	_stage.add_child(_mover)
	var mi := MeshInstance3D.new()
	mi.mesh = compose(parts)
	mi.material_override = _vertex_mat()
	mi.rotation.y = 0.0 if _dir > 0.0 else PI
	_mover.add_child(mi)
	_mover.add_child(Sfx.emitter("samba", 10.0, 16.0, 190.0))


func _build_blitz() -> void:
	var parts: Array = []
	for k in 6:
		parts.append([_cyl(0.05, 0.28, 0.7, 8), Transform3D(Basis(), Vector3(-3.0 + k * 1.2, 0.35, -2.5 + (k % 2) * 0.5)), Color(1.0, 0.45, 0.05)])
	for side in [-1.0, 1.0]:
		parts.append(part(Vector3(side * 2.6, 0.55, 2.0), Vector3(2.4, 0.3, 0.12), Color(0.95, 0.95, 0.95)))
		parts.append(part(Vector3(side * 2.6, 0.55, 2.0), Vector3(0.8, 0.32, 0.14), Color(0.9, 0.1, 0.1)))
		parts.append(part(Vector3(side * 2.6, 0.25, 2.0), Vector3(0.1, 0.5, 0.5), Color(0.3, 0.3, 0.3)))
	parts.append(part(Vector3(0, 0.62, 5.5), Vector3(4.2, 0.7, 1.8), Color(0.95, 0.95, 0.95)))
	parts.append(part(Vector3(0, 0.62, 5.5), Vector3(1.5, 0.72, 1.82), Color(0.1, 0.2, 0.6)))
	parts.append(part(Vector3(-0.2, 1.22, 5.5), Vector3(2.3, 0.5, 1.62), Color(0.08, 0.11, 0.15)))
	_props(parts, at)
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, 2.0, 5.5)
	light.light_color = Color(0.2, 0.3, 1.0)
	light.light_energy = 4.0
	light.omni_range = 14.0
	_stage.add_child(light)
	var l := Label3D.new()
	l.text = "BLITZ"
	l.font_size = 160
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(1.0, 0.85, 0.1)
	l.position = at + Vector3(0, 3.6, 0)
	_stage.add_child(l)


func _build_coach() -> void:
	var parts: Array = [
		part(Vector3(0, 1.9, 0), Vector3(12.0, 3.0, 2.5), Color(0.96, 0.96, 0.97)),
		part(Vector3(0, 2.5, 0), Vector3(11.4, 1.0, 2.54), Color(0.08, 0.11, 0.15)),
		part(Vector3(0, 1.2, 0), Vector3(12.04, 0.5, 2.54), Color(0.1, 0.55, 0.75)),
	]
	_wheel_parts(parts, [-4.0, 4.0], 1.15, 0.5)
	_props(parts, at + Vector3(0, 0, 2.6))
	var l := Label3D.new()
	l.text = "RIO TOURS"
	l.font_size = 220
	l.modulate = Color(0.1, 0.4, 0.6)
	l.outline_size = 0
	l.position = at + Vector3(0, 1.75, 1.33)
	l.rotation.y = PI
	_stage.add_child(l)
