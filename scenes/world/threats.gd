extends Node3D
## What the city does to you when you are not looking: the lads on the corner who want what
## is in your pockets, and the two on a bike who take it without stopping.
##
## The host decides everything. A mugging is ordinary crowd business (two of the gang turn
## hostile and run you down), so it replicates like any other. The bike crew is one message:
## where it starts, which way it goes and when, and every peer draws it from the clock.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")

## Walk within this of a gang with money on you and they may fancy their chances.
const MUG_RANGE := 9.0
const MUG_CHANCE := 0.5
const MUG_MIN_CASH := 80
## Seconds between the whistle and them coming for you: time to run.
const MUG_WARN := 1.5
## They are quick, but a sprint (7.0) leaves them behind.
const MUG_SPEED := 6.0
const MUG_TAKE := 0.35
const MUG_COOLDOWN := 120.0
const GANG_COOLDOWN := 60.0
## Nobody gets jumped in the first minute of a match.
const QUIET_START := 60.0
const SNATCH_EVERY := Vector2(70.0, 130.0)
const SNATCH_SPEED := 14.0
## How far behind you the bike starts: about two and a half seconds of engine getting louder.
const SNATCH_RUNUP := 35.0
const SNATCH_REACH := 1.8
const SNATCH_COOLDOWN := 240.0
const SNATCH_MIN_CASH := 150

# Every peer: the bike on its run, or empty. {pid, from, dir, t0, loot}
var run := {}

var _bike: Node3D
var _riders: MultiMesh
var _engine: AudioStreamPlayer3D
# Host only.
var _t := 0.0
var _inside := {}     # [pid, gang] -> were they in range last tick
var _mug_ok := {}     # pid -> match time they can be mugged again
var _gang_ok := {}    # gang -> match time it will try again
var _pending: Array = []  # {pid, gang, at}
var _snatch_t := 0.0
var _snatch_ok := {}  # pid -> match time the crew may pick them again
var _passed := false


func _ready() -> void:
	_bike = Node3D.new()
	_bike.visible = false
	add_child(_bike)
	var motos = Net.game.motos
	var mi := MeshInstance3D.new()
	mi.mesh = motos.bike_mesh
	mi.material_override = motos.bike_mat
	mi.set_instance_shader_parameter("paint", Color(0.08, 0.08, 0.09))
	_bike.add_child(mi)
	# Driver and the one on the back with the quick hands.
	_riders = Kit.add_to(_bike, 2, AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6)))
	for k in 2:
		_riders.set_instance_color(k, Color(0.1, 0.1, 0.12, 0.3 + k * 0.4))
		_riders.set_instance_transform(k, Kit.xform(Vector3(0, 0, 0.45 * k), 0.0, 0.9, 0.9))
		_riders.set_instance_custom_data(k, Kit.custom(Kit.RIDE, 0.0, Kit.F_SHORTS | Kit.F_HAT | (Kit.F_SHADES if k == 0 else 0), 0.0))
	_engine = Sfx.emitter("engine", 2.0, 6.0, 90.0, false)
	_bike.add_child(_engine)


func reset() -> void:
	run = {}
	_bike.visible = false
	_inside.clear()
	_mug_ok.clear()
	_gang_ok.clear()
	_pending.clear()
	_snatch_ok.clear()
	_snatch_t = randf_range(SNATCH_EVERY.x, SNATCH_EVERY.y) + QUIET_START


func snapshot() -> Dictionary:
	return run


func _process(delta: float) -> void:
	_draw_bike(delta)
	if not multiplayer.is_server() or not MatchState.running or MatchState.ended:
		return
	_srv_snatch_tick(delta)
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_srv_gangs()
	for k in range(_pending.size() - 1, -1, -1):
		if MatchState.time >= _pending[k].at:
			_srv_set_on(_pending[k])
			_pending.remove_at(k)


# --- corner gangs ---

func _srv_gangs() -> void:
	var g = Net.game
	var acts = g.crowd.acts
	if acts == null or MatchState.time < QUIET_START:
		return
	for gi in acts.gangs:
		var grp: Dictionary = acts.groups[gi]
		for pid in g.players:
			var pl = g.players[pid]
			var key := [pid, gi]
			var near: bool = pl.at_large() and pl.st.get("hide", -1) < 0 and g.motos.bike_of(pid) < 0 and absf(pl.global_position.y - grp.pos.y) < 1.5 and pl.global_position.distance_to(grp.pos) < MUG_RANGE
			var was: bool = _inside.get(key, false)
			_inside[key] = near
			if not near or was:
				continue
			# One look as you walk up: are you worth it, and are you trouble?
			if pl.st.money < MUG_MIN_CASH or pl.st.heat > 0 or MatchState.time < _mug_ok.get(pid, 0.0) or MatchState.time < _gang_ok.get(gi, 0.0) or _crew(grp).size() < 2:
				continue
			var chance := MUG_CHANCE
			if DB.is_gun(pl.st.equipped):
				chance *= 0.2
			for other in g.players:
				if other != pid and g.players[other].global_position.distance_to(pl.global_position) < 8.0:
					chance *= 0.5
			if randf() > chance:
				continue
			_mug_ok[pid] = MatchState.time + MUG_COOLDOWN
			_gang_ok[gi] = MatchState.time + GANG_COOLDOWN
			_pending.append({"pid": pid, "gang": gi, "at": MatchState.time + MUG_WARN})
			g.send(pid, "cl_toast", ["PERDEU, PLAYBOY!  They want your money - run"])
			g.bcast("cl_sound", ["whistle", grp.pos + Vector3(0, 1.5, 0)])


## The members of a gang still standing on their corner.
func _crew(grp: Dictionary) -> Array:
	var crowd = Net.game.crowd
	var out: Array = []
	for s in grp.n:
		if crowd.act_free(grp.first + s):
			out.append(grp.first + s)
	return out


func _srv_set_on(m: Dictionary) -> void:
	var g = Net.game
	var pl = g.players.get(m.pid)
	if pl == null or not pl.at_large():
		return
	var crew := _crew(g.crowd.acts.groups[m.gang])
	var at: Vector3 = pl.global_position
	crew.sort_custom(func(a, b): return g.crowd.pos[a].distance_squared_to(at) < g.crowd.pos[b].distance_squared_to(at))
	for k in mini(2, crew.size()):
		g.crowd.srv_mug(crew[k], m.pid, MUG_SPEED)


## Mugger `i` has caught up with player `pid`: down they go, and a cut of their cash goes
## into his pocket. It is still on him if you can get it back before he is gone.
func srv_mugged(i: int, pid: int) -> void:
	var g = Net.game
	var pl = g.players.get(pid)
	if pl == null:
		return
	var take: int = mini(pl.st.money, clampi(int(pl.st.money * MUG_TAKE), 40, 600))
	pl.st.money -= take
	g.crowd.money[i] += take
	var msg := "Mugged for R$%d" % take
	for item in DB.LOOT:
		if pl.st.inv.get(item, 0) > 0:
			pl.st.inv[item] -= 1
			g.crowd.money[i] += DB.ITEMS[item].price / 2
			msg += " and your %s" % DB.ITEMS[item].name
			break
	g.srv_floor(pid, 1.5)
	g.send(pid, "cl_toast", [msg + " - he still has it on him"])
	g.bcast("cl_fx", [g.crowd.pos[i] + Vector3(0, 1.2, 0), pl.global_position + Vector3(0, 0.9, 0), true, DB.WHO_NPC, i, DB.WHO_PLAYER, pid])
	# Job done: the whole corner scatters.
	g.crowd.srv_scatter(i, pl.global_position)


# --- the crew on the bike ---

func _srv_snatch_tick(delta: float) -> void:
	var g = Net.game
	if not run.is_empty():
		var at := _bike_pos(MatchState.time)
		var pl = g.players.get(run.pid)
		var gone: bool = (MatchState.time - run.t0) * SNATCH_SPEED > SNATCH_RUNUP * 2.0 + 30.0
		if not _passed and pl != null and (at - pl.global_position).dot(run.dir) >= 0.0:
			_passed = true
			_srv_grab(pl, at)
		if gone:
			g.bcast("cl_snatch_end", [false, at], self)
		return
	_snatch_t -= delta
	if _snatch_t > 0.0:
		return
	_snatch_t = randf_range(SNATCH_EVERY.x, SNATCH_EVERY.y)
	# Somebody on foot along a street, with something worth the petrol. Richer is likelier.
	var pick = null
	var total := 0.0
	for pid in g.players:
		var pl = g.players[pid]
		var p: Vector3 = pl.global_position
		var street: bool = (p.z > Layout.PROM_Z + 1.0 and p.z < Layout.ROAD_Z - 1.0) or (p.z > Layout.WALK_Z and p.z < Layout.BLOCK_A_Z) or (p.z > Layout.RUA_Z + 1.0 and p.z < Layout.BLOCK_B_Z - 1.0)
		if not street or not pl.at_large() or p.y > 1.0 or pl.st.heat > 1 or pl.st.money < SNATCH_MIN_CASH or g.motos.bike_of(pid) >= 0 or MatchState.time < _snatch_ok.get(pid, 0.0):
			continue
		total += pl.st.money
		if randf() * total < pl.st.money:
			pick = pl
	if pick == null:
		_snatch_t = 10.0
		return
	_snatch_ok[pick.id] = MatchState.time + SNATCH_COOLDOWN
	var dir := Vector3(1.0 if randf() < 0.5 else -1.0, 0, 0)
	var from: Vector3 = pick.global_position - dir * SNATCH_RUNUP
	from.y = 0.0
	g.bcast("cl_snatch", [pick.id, from, dir, MatchState.time], self)


## The bike is level with its mark. Close enough, on their feet and not mid-dive: gone.
func _srv_grab(pl, at: Vector3) -> void:
	var g = Net.game
	var side: float = absf(pl.global_position.z - at.z)
	var m: int = pl.net_byte() & 7
	if side > SNATCH_REACH or pl.global_position.y > 1.0 or m == pl.MV_DIVE or m == pl.MV_SLIDE or not pl.at_large():
		g.send(pl.id, "cl_toast", ["A hand grabbed at you from a passing bike - and missed"])
		return
	var take: int = mini(400, pl.st.money / 4)
	var msg := "Snatched from a bike: R$%d" % take
	pl.st.money -= take
	for item in DB.LOOT:
		if pl.st.inv.get(item, 0) > 0:
			pl.st.inv[item] -= 1
			run["items"] = {item: 1}
			msg += " and your %s" % DB.ITEMS[item].name
			break
	run["loot"] = take
	g.push_state(pl)
	g.send(pl.id, "cl_toast", [msg + " - knock them off it to get it back"])
	g.send(pl.id, "cl_sound", ["punch", pl.global_position])


## An attack along a ray: knocks the crew off if it finds them. Returns the distance, or -1.
func srv_strike(o: Vector3, d: Vector3, reach: float) -> float:
	if run.is_empty():
		return -1.0
	var at := _bike_pos(MatchState.time)
	var t := DB.ray_point(o, d, at + Vector3(0, 1.0, 0), 1.1, reach)
	if t < 0.0:
		return -1.0
	# Everything they took, and what they were carrying, all over the road.
	Net.game.srv_add_drop(at, run.get("loot", 0) + randi_range(100, 300), run.get("items", {}))
	Net.game.bcast("cl_snatch_end", [true, at], self)
	return t


@rpc("authority", "call_remote", "reliable")
func cl_snatch(pid: int, from: Vector3, dir: Vector3, t0: float) -> void:
	run = {"pid": pid, "from": from, "dir": dir, "t0": t0}
	_passed = false
	_bike.rotation = Vector3(0, Kit.face(dir), 0)
	_bike.visible = true
	if _engine.stream != null:
		_engine.play()


@rpc("authority", "call_remote", "reliable")
func cl_snatch_end(crashed: bool, at: Vector3) -> void:
	run = {}
	_bike.visible = false
	_engine.stop()
	if crashed:
		Sfx.play("crash", at, 2.0)
		Net.game.fx.confetti(at + Vector3(0, 1.0, 0))


func _bike_pos(t: float) -> Vector3:
	return run.from + run.dir * SNATCH_SPEED * (t - run.t0)


func _draw_bike(delta: float) -> void:
	if run.is_empty():
		return
	_bike.position = _bike_pos(MatchState.time)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, 1.7, minf(1.0, 3.0 * delta))
