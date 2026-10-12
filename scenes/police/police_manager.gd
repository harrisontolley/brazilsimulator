extends Node3D
## A handful of cops, simulated on the server and streamed at 10 Hz.
## patrol -> investigate (heard noise) -> chase (saw a crime) -> arrest on contact.
##
## A cop only knows what it has seen. A crime counts if one was looking that way with a clear
## view; a chase lasts while the suspect stays in sight, then becomes a search of where they
## vanished. Crouching, keeping still, cover, crowds and a hiding place all cut how far off a
## cop can pick someone out, and the whole force shares one budget of puff per suspect.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")

enum { PATROL, INVESTIGATE, CHASE, DOWN, SEARCH, KO }

const N := 14
const PATROL_SPEED := 1.8
const INVESTIGATE_SPEED := 4.0
## By heat. A sprint (7.0) outruns all of them, but only just at the top.
const CHASE_SPEED := [0.0, 5.6, 6.2, 6.6]
const ARREST_RANGE := 1.7
const SPOT_RANGE := 18.0
const DOWN_TIME := 40.0
## Cops stand a little taller than the crowd.
const HEIGHT := 1.08
## How far away a cop looking the right way witnesses a crime, by severity (index 1..3).
const SIGHT := [0.0, 24.0, 36.0, 70.0]
## How far a chasing cop can keep a suspect in view, by heat.
const VIEW_RANGE := [0.0, 36.0, 48.0, 65.0]
## Half the angle a cop sees across: narrow on the beat, wide with the blood up.
const FOV_PATROL := 1.134
const FOV_CHASE := 1.745
## Closer than this nothing hides you but a wall. Half that if you are crouched.
const CLOSE_RANGE := 4.0
## What crouching, crouching dead still, and sprinting do to the range you can be seen at.
const CROUCH_MULT := 0.5
const STILL_MULT := 0.35
const SPRINT_MULT := 1.15
const LOOK_TICK := 0.2
## Seconds out of view before a cop no longer knows where the suspect is.
const LOSE_TIME := 3.0
const SEARCH_TIME := [0.0, 8.0, 12.0, 16.0]
const SEARCH_RADIUS := 12.0
## How many cops will run after one suspect at a time, by heat.
const MAX_PURSUERS := [0, 2, 4, 6]
## Seconds of chasing and searching the force has in it per suspect, by heat. When it is
## spent they all give up, and nobody takes it up again for GRACE_TIME.
const PURSUIT_BUDGET := [0.0, 35.0, 55.0, 80.0]
const ESCALATE_BONUS := 15.0
const GRACE_TIME := 25.0
## Seconds unseen before heat drops one level, by heat.
const HEAT_STEP_TIME := [0.0, 12.0, 18.0, 25.0]
## Tucked away somewhere, it cools this much faster.
const HIDDEN_COOL := 1.5
## A cop who watched you climb into a hiding place from this close just walks over.
const HIDE_SEEN_RANGE := 18.0
## A searching cop passing this close to a hiding place may look in it.
const HIDE_CHECK_R := 3.0
const HIDE_HEAT := [0.0, 0.6, 1.0, 1.5]
## Head start between "found you" and the cuffs.
const GRAB_DELAY := 1.5
## Each bystander within COVER_RADIUS of a suspect shortens the range they can be picked out at.
const COVER_RADIUS := 3.5
const COVER := 0.5
## This many people standing along the sight line block it, beyond BLOCK_MIN metres.
const BLOCK_WIDTH := 0.6
const BLOCK_COUNT := 2
const BLOCK_MIN := 12.0
## Feet this far off the ground stick out above the crowd.
const HOP_HEIGHT := 1.2
## st.vis: what the wanted player's HUD should say.
const VIS_NONE := 0
const VIS_SEARCH := 1
const VIS_SEEN := 2
const VIS_HIDDEN := 3

# server: {pos, yaw, state, target, goal, hp, t, cd} plus what it knows of its suspect:
# seen (last known position), sees, lost (seconds out of view), look, saw_hide, checked, grab
var cops: Array = []

var _mm: MultiMesh
var _target := PackedVector3Array()
var _state := PackedByteArray()
var _shown := PackedByteArray()   # state each cop was last drawn in
var _vpos := PackedVector3Array()
var _vyaw := PackedFloat32Array()
var _ev := PackedFloat32Array()    # Kit one-shot event time
var _gun_t := PackedFloat32Array() # pistol stays drawn until this Kit time
var _pose := PackedByteArray()     # Kit pose now showing
var _prev := PackedByteArray()     # the pose it is blending out of
var _pose_t := PackedFloat32Array()  # Kit.now() when the pose last changed
var _send_t := 0.0
var _frozen := false
var _yaw_to := PackedFloat32Array()  # streamed facing
var _pursuit := {}  # server: pid -> {t, budget, grace}
var _sirens: Array[AudioStreamPlayer3D] = []

## Events tilt the odds (server only): rain shortens how far cops see, a roar of fireworks
## drowns out gunfire, and a blitz pins a few of them to a checkpoint.
var sight_mult := 1.0
var deaf_until := 0.0
var blitz_at := Vector3.ZERO
var blitz_until := 0.0


func _ready() -> void:
	_mm = Kit.add_to(self, N, Layout.WORLD_AABB)
	for i in N:
		_mm.set_instance_color(i, Color(0.1, 0.17, 0.52, fmod(0.07 + i * 0.37, 1.0)))
	_target.resize(N)
	_state.resize(N)
	_shown.resize(N)
	_vpos.resize(N)
	_vyaw.resize(N)
	_ev.resize(N)
	_gun_t.resize(N)
	_pose.resize(N)
	_prev.resize(N)
	_pose_t.resize(N)
	_yaw_to.resize(N)
	for k in 3:
		var s := Sfx.emitter("siren", -3.0, 7.0, 110.0, false)
		add_child(s)
		_sirens.append(s)
	if multiplayer.is_server():
		Crime.noise.connect(_on_noise)
		Crime.crime.connect(_on_crime)


func reset() -> void:
	sight_mult = 1.0
	deaf_until = 0.0
	blitz_until = 0.0
	_pursuit.clear()
	cops.clear()
	for i in N:
		# Ten walk the calçadão, the rest the back street.
		var p := Vector3(-270.0 + i * 60.0, 0.0, 47.0) if i < 10 else Vector3(-210.0 + (i - 10) * 140.0, 0.0, 105.0)
		cops.append({"pos": p, "yaw": 0.0, "state": PATROL, "target": 0, "goal": _patrol_point(), "hp": 150.0, "t": 0.0, "cd": 0.0,
				"seen": p, "sees": false, "lost": 0.0, "look": i * LOOK_TICK / N, "saw_hide": false, "checked": false, "grab": 0.0})
		_target[i] = p
		_vpos[i] = p


func _patrol_point() -> Vector3:
	var x := randf_range(-280.0, 280.0)
	var roll := randf()
	if roll < 0.7:
		return Vector3(x, 0.0, randf_range(-30.0, 50.0))
	if roll < 0.8:
		return Vector3(x, 0.0, 71.5)
	return Vector3(x, 0.0, randf_range(102.0, 108.0))


func _process(delta: float) -> void:
	if multiplayer.is_server() and cops.size() == N and not _frozen:
		_srv_process(delta)
	var now := Kit.now()
	for i in N:
		var s := _state[i]
		var to := _target[i] - _vpos[i]
		to.y = 0.0
		var moving := to.length() > 0.05
		_vpos[i] = _vpos[i].lerp(_target[i], minf(1.0, 12.0 * delta))
		if s != DOWN and s != KO and not _frozen:
			_vyaw[i] = lerp_angle(_vyaw[i], _yaw_to[i], minf(1.0, 10.0 * delta))
		_shown[i] = s

		# Uniform is constant; what the cop is doing reads from gait, beacon and gun.
		var pose := Kit.STAND
		var speed := 0.0
		var flags := Kit.F_POLICE | Kit.F_SUIT
		var held := Kit.HELD_NONE
		match s:
			PATROL:
				pose = Kit.WALK
				speed = PATROL_SPEED
			INVESTIGATE, SEARCH:
				pose = Kit.RUN
				speed = INVESTIGATE_SPEED
			CHASE:
				pose = Kit.RUN
				speed = CHASE_SPEED[2]
				flags |= Kit.F_LAMP_ON
			DOWN:
				pose = Kit.DOWN
			KO:
				pose = Kit.KO
		if s != DOWN and s != KO:
			if not moving:
				pose = Kit.STAND
			if _gun_t[i] > now:
				held = Kit.HELD_PISTOL
		if pose != _pose[i]:
			_prev[i] = _pose[i]
			_pose[i] = pose
			_pose_t[i] = now
		_mm.set_instance_transform(i, Kit.xform(_vpos[i], _vyaw[i], HEIGHT, HEIGHT))
		_mm.set_instance_custom_data(i, Kit.custom(pose, speed, flags, _ev[i], _prev[i], _pose_t[i], held))

	# Sirens ride on the first few cops who are chasing someone.
	var k := 0
	for i in N:
		if _state[i] == CHASE and k < _sirens.size():
			var s := _sirens[k]
			s.position = _vpos[i] + Vector3(0, 1.8, 0)
			if not s.playing and s.stream != null:
				s.play()
			k += 1
	for j in range(k, _sirens.size()):
		if _sirens[j].playing:
			_sirens[j].stop()


## Plays a recoil (attack) or a flinch on cop i. Firing keeps the pistol out for a while.
func fx_event(i: int, attack: bool) -> void:
	if i < 0 or i >= N or _state[i] == DOWN or _state[i] == KO:
		return
	_ev[i] = Kit.now() if attack else -Kit.now()
	if attack:
		_gun_t[i] = Kit.now() + 2.5


## --showcase: pins cop i in place in the given state and stops the simulation (host only).
func debug_pose(i: int, p: Vector3, s: int) -> void:
	_frozen = true
	_target[i] = p
	_vpos[i] = p
	_vyaw[i] = PI
	_state[i] = s


## For tests: one cop at `at` looking along `dir`, standing still, and the rest out of the game.
func debug_solo(at: Vector3, dir: Vector3) -> Dictionary:
	for c in cops:
		c.state = DOWN
		c.t = 1e6
		c.pos = Vector3(280, 0, -30)
	var c: Dictionary = cops[0]
	c.state = PATROL
	c.pos = at
	c.goal = at
	c.hold = true
	c.yaw = Kit.face(dir)
	return c


@rpc("authority", "call_remote", "unreliable")
func cl_cops(ps: PackedVector3Array, states: PackedByteArray, yaws: PackedFloat32Array) -> void:
	if ps.size() == N and states.size() == N and yaws.size() == N:
		_target = ps
		_state = states
		_yaw_to = yaws


## Server ray test. Returns [cop index, distance, DB.ZONE_*]; index -1 on a miss.
func ray_pick(o: Vector3, d: Vector3, max_t: float, grow: float) -> Array:
	var best := -1
	var best_t := max_t
	var zone := DB.ZONE_BODY
	for i in cops.size():
		var c: Dictionary = cops[i]
		if c.state == DOWN:
			continue
		var h := Kit.ray_hit(o, d, best_t, c.pos, c.yaw, HEIGHT, Kit.STANCE_BACK if c.state == KO else Kit.STANCE_STAND, grow)
		if h[0] >= 0.0:
			best = i
			best_t = h[0]
			zone = h[1]
	return [best, best_t, zone]


## `zone` is DB.ZONE_*. A fist to the head can lay a cop out cold for a while instead.
## Returns whether it did.
func srv_damage_cop(i: int, dmg: float, attacker: int, zone := 0, ko := false) -> bool:
	var c = cops[i]
	if c.state == DOWN:
		return false
	Crime.report_crime(c.pos, attacker, 3)
	if ko and zone == DB.ZONE_HEAD and c.state != KO and randf() < DB.KO_CHANCE:
		c.state = KO
		c.t = DB.KO_COP
		c.target = attacker
		Net.game.bcast("cl_ko", [c.pos + Vector3(0, 1.6, 0), DB.KO_COP])
		Net.game.srv_add_drop(c.pos + Vector3(0.6, 0, 0.4), 0, {"pistol": 1, "ammo": 6})
		return true
	c.hp -= dmg
	if c.hp <= 0.0:
		c.state = DOWN
		c.t = DOWN_TIME
		Net.game.srv_add_drop(c.pos, 0, {"pistol": 1, "ammo": 12})
	return false


# --- server ---

func _srv_process(delta: float) -> void:
	var g = Net.game
	for c in cops:
		# Looking is the costly part (it scans the crowd), so each cop does it a few times a second.
		c.look -= delta
		var look: bool = c.look <= 0.0
		if look:
			c.look = LOOK_TICK
		match c.state:
			PATROL:
				if c.get("hold", false):
					pass
				elif c.get("post", false) and MatchState.time < blitz_until:
					_move(c, blitz_at + c.post_off, INVESTIGATE_SPEED, delta)
				elif _move(c, c.goal, PATROL_SPEED, delta):
					c.goal = _patrol_point()
				if look:
					_srv_spot(c)
			INVESTIGATE:
				c.t -= delta
				if _move(c, c.goal, INVESTIGATE_SPEED, delta) or c.t <= 0.0:
					_give_up(c)
				elif look:
					_srv_spot(c)
			CHASE:
				_srv_chase(c, delta, look)
			SEARCH:
				_srv_search(c, delta, look)
			DOWN:
				c.t -= delta
				if c.t <= 0.0:
					c.hp = 150.0
					c.pos = Vector3(randf_range(-280.0, 280.0), 0.0, 47.0)
					_give_up(c)
			KO:
				c.t -= delta
				if c.t <= 0.0:
					# Comes round where they fell, and remembers who did it.
					var pl = g.players.get(c.target)
					if pl != null and pl.at_large() and pl.st.heat > 0:
						_start_chase(c, c.target, c.pos)
						c.sees = false
					else:
						_give_up(c)

	_srv_heat(delta)

	if MatchState.time < blitz_until:
		_srv_blitz_check()

	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		var ps := PackedVector3Array()
		var states := PackedByteArray()
		var yaws := PackedFloat32Array()
		for c in cops:
			ps.append(c.pos)
			states.append(c.state)
			yaws.append(c.yaw)
		g.bcast("cl_cops", [ps, states, yaws], self)


## A cop on the beat keeps an eye out for anyone wanted, or still in prison stripes.
func _srv_spot(c: Dictionary) -> void:
	var g = Net.game
	for pid in g.players:
		var pl = g.players[pid]
		var fugitive: bool = pl.st.get("fug", false)
		if (pl.st.heat <= 0 and not fugitive) or not pl.at_large():
			continue
		var pu = _pursuit.get(pid)
		if pu != null and MatchState.time < pu.grace:
			continue
		if _pursuers(pid) >= MAX_PURSUERS[clampi(maxi(pl.st.heat, 2 if fugitive else 0), 0, 3)]:
			continue
		if _sees(c, pl, SPOT_RANGE * (1.5 if fugitive else 1.0), FOV_PATROL):
			if fugitive and pl.st.heat < 2:
				pl.st.heat = 2
				pl.wanted_t = HEAT_STEP_TIME[2]
				g.push_state(pl)
			_start_chase(c, pid, pl.global_position)
			return


## Heat holds while a cop has eyes on you, then steps down a level at a time. The force's
## shared stamina for each suspect runs down here too.
func _srv_heat(delta: float) -> void:
	var g = Net.game
	for pid in g.players:
		var pl = g.players[pid]
		var heat: int = clampi(pl.st.heat, 0, 3)
		if heat <= 0:
			_pursuit.erase(pid)
			if pl.st.get("vis", VIS_NONE) != VIS_NONE:
				pl.st.vis = VIS_NONE
				g.push_state(pl)
			continue
		var seen := false
		var chased := false
		for c in cops:
			if (c.state == CHASE or c.state == SEARCH) and c.target == pid:
				chased = true
				seen = seen or (c.state == CHASE and c.sees)
		var pu = _pursuit.get(pid)
		if pu == null:
			pu = {"t": 0.0, "budget": PURSUIT_BUDGET[heat], "grace": 0.0}
			_pursuit[pid] = pu
		if chased:
			pu.t += delta
			if pu.t > pu.budget:
				pu.t = 0.0
				pu.budget = PURSUIT_BUDGET[heat]
				pu.grace = MatchState.time + GRACE_TIME
				release_chase(pid)
				seen = false
				g.send(pid, "cl_toast", ["The police are out of puff"])
		var tucked: bool = pl.st.get("hide", -1) >= 0 or Places.cover_at(pl.global_position, pl.is_crouched()) < 1.0 or Places.room_at(pl.global_position) >= 0
		if seen:
			pl.wanted_t = HEAT_STEP_TIME[heat]
		else:
			pl.wanted_t -= delta * (HIDDEN_COOL if tucked else 1.0)
		var vis := VIS_SEEN if seen else (VIS_HIDDEN if tucked else VIS_SEARCH)
		if pl.wanted_t <= 0.0:
			pl.st.heat = heat - 1
			pl.wanted_t = HEAT_STEP_TIME[heat - 1]
			if heat == 1:
				vis = VIS_NONE
				release_chase(pid)
			pl.st.vis = vis
			g.push_state(pl)
			g.send(pid, "cl_toast", ["You lost the police" if heat == 1 else "The heat is dying down"])
		elif pl.st.get("vis", VIS_NONE) != vis:
			pl.st.vis = vis
			g.push_state(pl)


func _pursuers(pid: int) -> int:
	var n := 0
	for c in cops:
		if (c.state == CHASE or c.state == SEARCH) and c.target == pid:
			n += 1
	return n


## Which way cop c is facing, flat.
func _facing(c: Dictionary) -> Vector2:
	return Vector2(-sin(c.yaw), -cos(c.yaw))


## Is p inside what cop c can see: near enough, in front of it, nothing solid between?
func _witness(c: Dictionary, p: Vector3, max_range: float, fov: float, eye_h := 0.9) -> bool:
	var to := Vector2(p.x - c.pos.x, p.z - c.pos.z)
	var d := to.length()
	if d > max_range * sight_mult:
		return false
	if d > 2.0 and to.dot(_facing(c)) < d * cos(fov):
		return false
	var q := PhysicsRayQueryParameters3D.create(c.pos + Vector3(0, 1.5, 0), p + Vector3(0, eye_h, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Can cop c pick this player out right now? They have to be in front of it and in the open:
## walls block the view, so does a crowd whether the suspect is standing in it or it is in the
## way. Crouching, cover and a hiding place all help; sprinting or hopping about does not.
func _sees(c: Dictionary, pl, max_range: float, fov: float) -> bool:
	if pl.st.get("hide", -1) >= 0:
		return false
	var crowd = Net.game.crowd
	var p: Vector3 = pl.global_position
	var d := Vector2(p.x - c.pos.x, p.z - c.pos.z).length()
	var crouched: bool = pl.is_crouched()
	var close := CLOSE_RANGE * (0.5 if crouched else 1.0)
	# At the top heat the helicopter is on you: nothing but a roof hides someone under its light.
	var lit: bool = pl.st.heat >= 3 and not _roofed(p)
	var hidden: bool = d > close and p.y - c.pos.y < HOP_HEIGHT and not lit
	if d > close and not lit:
		var spd: float = pl.ground_speed()
		if crouched:
			max_range *= STILL_MULT if spd < 0.5 else CROUCH_MULT
		elif spd > 6.0:
			max_range *= SPRINT_MULT
		max_range *= Places.cover_at(p, crouched)
	if not _witness(c, p, max_range, fov if d > close else PI, 0.45 if crouched else 0.9):
		return false
	if not hidden:
		return true
	if d > max_range * sight_mult / (1.0 + COVER * crowd.count_near(p, COVER_RADIUS)):
		return false
	return not (d > BLOCK_MIN and crowd.count_on_segment(c.pos, p, BLOCK_WIDTH) >= BLOCK_COUNT)


func _roofed(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.8, 0), p + Vector3(0, 60.0, 0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Pins the four nearest idle cops to a checkpoint at `at` for `seconds`.
func srv_blitz(at: Vector3, seconds: float) -> void:
	blitz_at = at
	blitz_until = MatchState.time + seconds
	var order: Array = cops.duplicate()
	order.sort_custom(func(a, b): return a.pos.distance_squared_to(at) < b.pos.distance_squared_to(at))
	var n := 0
	for c in cops:
		c.post = false
	for c in order:
		if c.state == PATROL and n < 4:
			c.post = true
			c.post_off = Vector3((n % 2) * 4.0 - 2.0, 0.0, (n / 2) * 3.0 - 1.5)
			n += 1


## Anyone walking through the checkpoint with something to hide gets pulled.
func _srv_blitz_check() -> void:
	var g = Net.game
	for pid in g.players:
		var pl = g.players[pid]
		if pl.st.heat > 0 or not pl.at_large() or pl.global_position.distance_to(blitz_at) > 9.0:
			continue
		var dirty: bool = pl.st.inv.has("pistol")
		for item in DB.DRUGS + DB.LOOT:
			dirty = dirty or pl.st.inv.get(item, 0) > 0
		if not dirty:
			continue
		for c in cops:
			if c.get("post", false) and c.state == PATROL and c.pos.distance_to(blitz_at) < 8.0:
				pl.st.heat = 1
				pl.wanted_t = HEAT_STEP_TIME[1]
				g.push_state(pl)
				g.send(pid, "cl_toast", ["BLITZ! They found what you are carrying"])
				_start_chase(c, pid, pl.global_position)
				break


func _start_chase(c: Dictionary, pid: int, at: Vector3) -> void:
	c.state = CHASE
	c.target = pid
	c.seen = at
	c.sees = true
	c.lost = 0.0
	c.saw_hide = false
	c.checked = false
	c.grab = 0.0


func _give_up(c: Dictionary) -> void:
	c.state = PATROL
	c.sees = false
	c.goal = _patrol_point()


## Returns the suspect while the cop should still be after them; otherwise stands the cop down.
func _suspect(c: Dictionary):
	var pl = Net.game.players.get(c.target)
	if pl == null or not pl.at_large() or pl.st.heat <= 0:
		_give_up(c)
		return null
	return pl


func _srv_chase(c: Dictionary, delta: float, look: bool) -> void:
	var g = Net.game
	var pl = _suspect(c)
	if pl == null:
		return
	var heat: int = clampi(pl.st.heat, 0, 3)
	var target: Vector3 = pl.global_position
	var tucked: bool = pl.st.get("hide", -1) >= 0
	if look:
		c.sees = _sees(c, pl, VIEW_RANGE[heat], FOV_CHASE)
	if c.sees:
		c.seen = target
		c.lost = 0.0
	else:
		c.lost += delta
	var d: float = c.pos.distance_to(target)
	c.grab -= delta
	if tucked and c.saw_hide:
		# Watched them climb in: no need to search, just go and haul them out.
		c.seen = target
		c.lost = 0.0
		if d < ARREST_RANGE + 0.8:
			_srv_found(c, pl)
			return
	elif c.sees and d < ARREST_RANGE and c.grab <= 0.0:
		g.srv_arrest(c.target)
		return
	# Out of view, the cop can only run to where the suspect was last seen.
	var there := _move(c, c.seen, CHASE_SPEED[heat], delta)
	if not c.sees and not (tucked and c.saw_hide) and (there or c.lost > LOSE_TIME):
		c.state = SEARCH
		c.t = SEARCH_TIME[heat]
		c.goal = _search_point(c)
		return
	# Armed and dangerous suspects get shot at rather than just chased, and so does anyone
	# getting away from an assault on a stolen bike.
	c.cd -= delta
	var armed: bool = heat >= 3 or (heat >= 2 and g.motos.bike_of(c.target) >= 0)
	if c.sees and armed and d < 30.0 and c.cd <= 0.0:
		c.cd = 1.0
		var hit := randf() < 0.5
		var to_pt := target + Vector3(0, 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)))
		g.bcast("cl_fx", [c.pos + Vector3(0, 1.4, 0), to_pt, false, DB.WHO_COP, cops.find(c), DB.WHO_PLAYER if hit else DB.WHO_NONE, c.target])
		if hit:
			g.srv_damage(c.target, 12.0, -1)


## Pokes around where the suspect vanished, turning to look this way and that. Spotting them
## again resumes the chase, and a hiding place nearby may get looked into.
func _srv_search(c: Dictionary, delta: float, look: bool) -> void:
	var pl = _suspect(c)
	if pl == null:
		return
	var heat: int = clampi(pl.st.heat, 0, 3)
	if look and _sees(c, pl, SPOT_RANGE, FOV_PATROL):
		c.state = CHASE
		c.sees = true
		c.lost = 0.0
		c.seen = pl.global_position
		return
	var hide: int = pl.st.get("hide", -1)
	if hide >= 0 and c.pos.distance_to(pl.global_position) < HIDE_CHECK_R:
		if not c.checked:
			c.checked = true
			if randf() < DB.HIDE_KINDS[Places.hides[hide].kind].find * HIDE_HEAT[heat]:
				_srv_found(c, pl)
				return
	else:
		c.checked = false
	c.t -= delta
	if c.t <= 0.0:
		_give_up(c)
	elif _move(c, c.goal, INVESTIGATE_SPEED, delta):
		c.goal = _search_point(c)
		# A long look round before moving on.
		c.yaw += randf_range(1.5, 3.5)


## Cop c has found the player in their hiding place: out they come, with a second to bolt.
func _srv_found(c: Dictionary, pl) -> void:
	Net.game.srv_unhide(pl.id, true)
	c.state = CHASE
	c.sees = true
	c.lost = 0.0
	c.seen = pl.global_position
	c.saw_hide = false
	c.grab = GRAB_DELAY


## A player just climbed into a hiding place. Any cop who was watching knows exactly where.
func srv_hid(pid: int, at: Vector3) -> void:
	for c in cops:
		if c.state == CHASE and c.target == pid and c.sees and _witness(c, at, HIDE_SEEN_RANGE, FOV_CHASE):
			c.saw_hide = true


func _search_point(c: Dictionary) -> Vector3:
	var a := randf() * TAU
	var p: Vector3 = c.seen + Vector3(cos(a), 0.0, sin(a)) * randf_range(3.0, SEARCH_RADIUS)
	return Layout.snap(Vector3(clampf(p.x, -295.0, 295.0), 0.0, maxf(p.z, -34.0)))


func _move(c: Dictionary, goal: Vector3, speed: float, delta: float) -> bool:
	# Cops stay at street level and go round the blocks, never through them.
	goal = Layout.snap(goal)
	if Vector2(goal.x - c.pos.x, goal.z - c.pos.z).length() < 0.5:
		return true
	var to: Vector3 = Layout.next_point(c.pos, goal) - c.pos
	to.y = 0.0
	var d := to.length()
	if d > 0.01:
		c.pos += to / d * minf(speed * delta, d)
		c.yaw = lerp_angle(c.yaw, Kit.face(to), minf(1.0, 8.0 * delta))
	c.pos.y = 0.0
	return false


func _on_noise(p: Vector3, radius: float, _pid: int) -> void:
	if MatchState.time < deaf_until:
		return
	for c in cops:
		if c.state == PATROL and c.pos.distance_to(p) < radius:
			c.state = INVESTIGATE
			c.goal = p
			c.t = 14.0


## Somebody did something at p. It only matters to the cops who saw it happen.
func _on_crime(p: Vector3, pid: int, severity: int) -> void:
	var g = Net.game
	var pl = g.players.get(pid)
	if pl == null or not pl.at_large():
		return
	var n := _pursuers(pid)
	var seen := false
	for c in cops:
		if c.state == DOWN or c.state == KO or not _witness(c, p, SIGHT[severity], FOV_PATROL if c.state == PATROL else FOV_CHASE):
			continue
		seen = true
		if (c.state == CHASE or c.state == SEARCH) and c.target == pid:
			# Already after them: it just confirms where they are.
			c.state = CHASE
			c.seen = pl.global_position
			c.sees = true
			c.lost = 0.0
		elif n < MAX_PURSUERS[severity]:
			_start_chase(c, pid, pl.global_position)
			n += 1
	if not seen:
		return
	var pu = _pursuit.get(pid)
	if pu == null:
		pu = {"t": 0.0, "budget": PURSUIT_BUDGET[severity], "grace": 0.0}
		_pursuit[pid] = pu
	# A fresh crime in plain view is fresh aggression, even after they had given up.
	pu.grace = 0.0
	if pl.st.heat < severity:
		pu.budget = minf(maxf(pu.budget, PURSUIT_BUDGET[severity]) + ESCALATE_BONUS, PURSUIT_BUDGET[severity] * 1.5)
		pl.st.heat = severity
		pl.st.vis = VIS_SEEN
		g.push_state(pl)
	pl.wanted_t = HEAT_STEP_TIME[clampi(pl.st.heat, 0, 3)]


## Called by Game once a suspect is in custody.
func release_chase(pid: int) -> void:
	for c in cops:
		if (c.state == CHASE or c.state == SEARCH) and c.target == pid:
			_give_up(c)
