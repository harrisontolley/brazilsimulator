extends Node3D
## A handful of cops, simulated on the server and streamed at 10 Hz.
## patrol -> investigate (heard noise) -> chase (saw a crime) -> arrest on contact.
## A chase only lasts while the suspect stays in view: lose them behind a wall or in a
## crowd and the cop searches where they were last seen, then goes back to patrol.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")

enum { PATROL, INVESTIGATE, CHASE, DOWN, SEARCH }

const N := 14
const PATROL_SPEED := 1.8
const INVESTIGATE_SPEED := 4.0
const CHASE_SPEED := 6.4
const ARREST_RANGE := 1.7
const SPOT_RANGE := 22.0
## How long heat lasts once no cop has eyes on the suspect.
const WANTED_TIME := 15.0
const DOWN_TIME := 40.0
## Cops stand a little taller than the crowd.
const HEIGHT := 1.08
## How far away a cop notices a crime, by severity (index 1..3).
const SIGHT := [0.0, 28.0, 45.0, 110.0]
## How far a chasing cop can keep a suspect in view, by heat.
const VIEW_RANGE := [0.0, 40.0, 55.0, 75.0]
## Closer than this nothing hides you but a wall.
const CLOSE_RANGE := 6.0
const LOOK_TICK := 0.2
## Seconds out of view before a cop no longer knows where the suspect is.
const LOSE_TIME := 4.0
const SEARCH_TIME := 10.0
const SEARCH_RADIUS := 12.0
## A cop runs out of puff after this long on one suspect, by heat, and then leaves them be.
const MAX_CHASE := [0.0, 40.0, 60.0, 90.0]
const IGNORE_TIME := 20.0
## Each bystander within COVER_RADIUS of a suspect shortens the range they can be picked out at.
const COVER_RADIUS := 3.5
const COVER := 0.5
## This many people standing along the sight line block it, beyond BLOCK_MIN metres.
const BLOCK_WIDTH := 0.6
const BLOCK_COUNT := 2
const BLOCK_MIN := 12.0
## Feet this far off the ground stick out above the crowd.
const HOP_HEIGHT := 1.2

# server: {pos, state, target, goal, hp, t, cd} plus what it knows of its suspect:
# seen (last known position), sees, lost (seconds out of view), chase_t, look, ignore, ignore_t
var cops: Array = []

var _mm: MultiMesh
var _target := PackedVector3Array()
var _state := PackedByteArray()
var _shown := PackedByteArray()   # state each cop was last drawn in
var _vpos := PackedVector3Array()
var _vyaw := PackedFloat32Array()
var _ev := PackedFloat32Array()    # Kit one-shot event time
var _gun_t := PackedFloat32Array() # pistol stays drawn until this Kit time
var _send_t := 0.0
var _frozen := false


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
	if multiplayer.is_server():
		Crime.noise.connect(_on_noise)
		Crime.crime.connect(_on_crime)


func reset() -> void:
	cops.clear()
	for i in N:
		# Ten walk the calçadão, the rest the back street.
		var p := Vector3(-270.0 + i * 60.0, 0.0, 47.0) if i < 10 else Vector3(-210.0 + (i - 10) * 140.0, 0.0, 105.0)
		cops.append({"pos": p, "state": PATROL, "target": 0, "goal": _patrol_point(), "hp": 150.0, "t": 0.0, "cd": 0.0,
				"seen": p, "sees": false, "lost": 0.0, "chase_t": 0.0, "look": i * LOOK_TICK / N, "ignore": 0, "ignore_t": 0.0})
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
		if moving and s != DOWN:
			_vyaw[i] = lerp_angle(_vyaw[i], Kit.face(to), minf(1.0, 10.0 * delta))
		if s == DOWN and _shown[i] != DOWN:
			_ev[i] = now
		_shown[i] = s

		# Uniform is constant; what the cop is doing reads from gait, beacon and gun.
		var pose := Kit.STAND
		var speed := 0.0
		var flags := Kit.F_POLICE | Kit.F_SUIT
		match s:
			PATROL:
				pose = Kit.WALK
				speed = PATROL_SPEED
			INVESTIGATE, SEARCH:
				pose = Kit.RUN
				speed = INVESTIGATE_SPEED
			CHASE:
				pose = Kit.RUN
				speed = CHASE_SPEED
				flags |= Kit.F_LAMP_ON
			DOWN:
				pose = Kit.DOWN
		if s != DOWN:
			if not moving:
				pose = Kit.STAND
			if _gun_t[i] > now:
				flags |= Kit.F_GUN
		_mm.set_instance_transform(i, Kit.xform(_vpos[i], _vyaw[i], HEIGHT, HEIGHT))
		_mm.set_instance_custom_data(i, Kit.custom(pose, speed, flags, _ev[i]))


## Plays a recoil (attack) or a flinch on cop i. Firing keeps the pistol out for a while.
func fx_event(i: int, attack: bool) -> void:
	if i < 0 or i >= N or _state[i] == DOWN:
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


@rpc("authority", "call_remote", "unreliable")
func cl_cops(ps: PackedVector3Array, states: PackedByteArray) -> void:
	if ps.size() == N and states.size() == N:
		_target = ps
		_state = states


## Server ray test. Returns [cop index, distance]; index -1 on a miss.
func ray_pick(o: Vector3, d: Vector3, max_t: float, radius: float) -> Array:
	var best := -1
	var best_t := max_t
	for i in cops.size():
		if cops[i].state == DOWN:
			continue
		var t := DB.ray_point(o, d, cops[i].pos + Vector3(0, 0.9, 0), radius, best_t)
		if t >= 0.0:
			best = i
			best_t = t
	return [best, best_t]


func srv_damage_cop(i: int, dmg: float, attacker: int) -> void:
	var c = cops[i]
	if c.state == DOWN:
		return
	c.hp -= dmg
	Crime.report_crime(c.pos, attacker, 3)
	if c.hp <= 0.0:
		c.state = DOWN
		c.t = DOWN_TIME
		Net.game.srv_add_drop(c.pos, 0, {"pistol": 1, "ammo": 12})


# --- server ---

func _srv_process(delta: float) -> void:
	var g = Net.game
	for c in cops:
		# Looking is the costly part (it scans the crowd), so each cop does it a few times a second.
		c.look -= delta
		var look: bool = c.look <= 0.0
		if look:
			c.look = LOOK_TICK
		c.ignore_t -= delta
		if c.ignore_t <= 0.0:
			c.ignore = 0
		match c.state:
			PATROL:
				if _move(c, c.goal, PATROL_SPEED, delta):
					c.goal = _patrol_point()
				if look:
					for pid in g.players:
						var pl = g.players[pid]
						if pl.st.heat > 0 and pid != c.ignore and pl.can_fight() and _sees(c, pl, SPOT_RANGE):
							_start_chase(c, pid, pl.global_position)
							break
			INVESTIGATE:
				c.t -= delta
				if _move(c, c.goal, INVESTIGATE_SPEED, delta) or c.t <= 0.0:
					_give_up(c)
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

	# Heat holds while a cop has eyes on you, then cools off.
	for pid in g.players:
		var pl = g.players[pid]
		if pl.st.heat <= 0:
			continue
		var seen := false
		for c in cops:
			if c.state == CHASE and c.target == pid and c.sees:
				seen = true
				break
		pl.wanted_t = WANTED_TIME if seen else pl.wanted_t - delta
		if pl.wanted_t <= 0.0:
			pl.st.heat = 0
			pl.st.seen = false
			g.push_state(pl)
			g.send(pid, "cl_toast", ["You lost the police"])
		elif pl.st.get("seen", false) != seen:
			pl.st.seen = seen
			g.push_state(pl)

	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		var ps := PackedVector3Array()
		var states := PackedByteArray()
		for c in cops:
			ps.append(c.pos)
			states.append(c.state)
		g.bcast("cl_cops", [ps, states], self)


## Can cop c pick this player out right now? Walls block the view; so does a crowd, whether
## the suspect is standing in it or it is in the way. Jumping about above its heads undoes that.
func _sees(c: Dictionary, pl, max_range: float) -> bool:
	var crowd = Net.game.crowd
	var p: Vector3 = pl.global_position
	var d := Vector2(p.x - c.pos.x, p.z - c.pos.z).length()
	if d > max_range:
		return false
	var hidden: bool = d > CLOSE_RANGE and p.y < HOP_HEIGHT
	if hidden and d > max_range / (1.0 + COVER * crowd.count_near(p, COVER_RADIUS)):
		return false
	var q := PhysicsRayQueryParameters3D.create(c.pos + Vector3(0, 1.5, 0), p + Vector3(0, 0.9, 0), 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return false
	return not (hidden and d > BLOCK_MIN and crowd.count_on_segment(c.pos, p, BLOCK_WIDTH) >= BLOCK_COUNT)


func _start_chase(c: Dictionary, pid: int, at: Vector3) -> void:
	c.state = CHASE
	c.target = pid
	c.seen = at
	c.sees = true
	c.lost = 0.0
	c.chase_t = 0.0


func _give_up(c: Dictionary) -> void:
	c.state = PATROL
	c.sees = false
	c.goal = _patrol_point()


## Returns the suspect while the cop should still be after them; otherwise stands the cop down.
func _suspect(c: Dictionary, delta: float):
	var pl = Net.game.players.get(c.target)
	if pl == null or not pl.can_fight() or pl.st.heat <= 0:
		_give_up(c)
		return null
	c.chase_t += delta
	if c.chase_t > MAX_CHASE[clampi(pl.st.heat, 0, 3)]:
		c.ignore = c.target
		c.ignore_t = IGNORE_TIME
		_give_up(c)
		return null
	return pl


func _srv_chase(c: Dictionary, delta: float, look: bool) -> void:
	var g = Net.game
	var pl = _suspect(c, delta)
	if pl == null:
		return
	var heat: int = clampi(pl.st.heat, 0, 3)
	var target: Vector3 = pl.global_position
	if look:
		c.sees = _sees(c, pl, VIEW_RANGE[heat])
	if c.sees:
		c.seen = target
		c.lost = 0.0
	else:
		c.lost += delta
	var d: float = c.pos.distance_to(target)
	if c.sees and d < ARREST_RANGE:
		g.srv_arrest(c.target)
		return
	# Out of view, the cop can only run to where the suspect was last seen.
	var there := _move(c, c.seen, CHASE_SPEED, delta)
	if not c.sees and (there or c.lost > LOSE_TIME):
		c.state = SEARCH
		c.t = SEARCH_TIME
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


## Pokes around where the suspect vanished. Spotting them again resumes the chase.
func _srv_search(c: Dictionary, delta: float, look: bool) -> void:
	var pl = _suspect(c, delta)
	if pl == null:
		return
	if look and _sees(c, pl, SPOT_RANGE):
		c.state = CHASE
		c.sees = true
		c.lost = 0.0
		c.seen = pl.global_position
		return
	c.t -= delta
	if c.t <= 0.0:
		_give_up(c)
	elif _move(c, c.goal, INVESTIGATE_SPEED, delta):
		c.goal = _search_point(c)


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
	c.pos.y = 0.0
	return false


func _on_noise(p: Vector3, radius: float, _pid: int) -> void:
	for c in cops:
		if c.state == PATROL and c.pos.distance_to(p) < radius:
			c.state = INVESTIGATE
			c.goal = p
			c.t = 14.0


func _on_crime(p: Vector3, pid: int, severity: int) -> void:
	var g = Net.game
	var pl = g.players.get(pid)
	if pl == null:
		return
	var seen := false
	for c in cops:
		if c.state != DOWN and c.pos.distance_to(p) < SIGHT[severity]:
			# A fresh crime is fresh aggression, even from a cop who had given up on them.
			_start_chase(c, pid, pl.global_position)
			if c.ignore == pid:
				c.ignore = 0
			seen = true
	if not seen:
		return
	pl.wanted_t = WANTED_TIME
	if pl.st.heat < severity:
		pl.st.heat = severity
		g.push_state(pl)


## Called by Game once a suspect is in custody.
func release_chase(pid: int) -> void:
	for c in cops:
		if (c.state == CHASE or c.state == SEARCH) and c.target == pid:
			_give_up(c)
