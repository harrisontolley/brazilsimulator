extends Node3D
## Match scene and RPC hub. Lives at /root/Game on every peer.
##
## srv_* run on the host (clients call them through to_server).
## cl_*  run on clients (the host calls them through bcast / send, which also
##       invoke the host's own copy directly).

const Player := preload("res://scenes/player/player.gd")
const Beach := preload("res://scenes/world/beach.gd")
const Ambient := preload("res://scenes/world/ambient.gd")
const Traffic := preload("res://scenes/world/traffic.gd")
const Events := preload("res://scenes/world/events.gd")
const Balls := preload("res://scenes/world/balls.gd")
const Motos := preload("res://scenes/world/motos.gd")
const Crowd := preload("res://scenes/crowd/crowd_manager.gd")
const Police := preload("res://scenes/police/police_manager.gd")
const Dogs := preload("res://scenes/crowd/dog_manager.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const Layout := preload("res://scenes/world/layout.gd")
const CombatFx := preload("res://scenes/fx/combat_fx.gd")
const Interact := preload("res://scenes/player/interact.gd")
const Threats := preload("res://scenes/world/threats.gd")
const Casino := preload("res://scenes/world/casino.gd")
const Prison := preload("res://scenes/world/prison.gd")
const Places := preload("res://scenes/world/places.gd")
const WeaponKit := preload("res://scenes/weapons/weapon_kit.gd")
const DrugKit := preload("res://scenes/items/drug_kit.gd")
const Nav := preload("res://scenes/world/nav.gd")
const LifeTests := preload("res://scenes/life_tests.gd")

const END_SCREEN_TIME := 15.0
const PICKUP_RANGE := 2.6
const VENDOR_RANGE := 4.5
const PICKUP_COUNT := 30
const TILL_COOLDOWN := 120.0

var players := {}       # peer id -> Player node
var ready_peers: Array = []  # server: peers that have loaded this scene
var drops := {}         # drop id -> {pos, money, items, node}
var world: Node3D
var ambient: Node3D
var traffic: Node3D
var motos: Node3D
var balls: Node3D
var events: Node3D
var crowd: Node3D
var police: Node3D
var dogs: Node3D
var hud: CanvasLayer
var fx: Node3D
var interaction: Node
var threats: Node3D
var casino: Node
var prison: Node
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
var _last_hit := {}
var _till_ready := {}   # vendor index -> match time its till is full again
var _reload := {}       # pid -> [weapon, seconds left]
var _ko_immune := {}    # pid -> match time until which they cannot be knocked out again
var _robbed := {}       # pid -> match time until which their pockets are already turned out
var _bicho_round := 0
var _larica := {}       # pid -> match time they may next be sold a snack they did not ask for
var _mirages: Array = []  # things on the sand only someone on doce can see
var _mirage_t := 0.0
var _party_t := 0.0


func _ready() -> void:
	Net.game = self
	Places.clear()
	world = Beach.new()
	add_child(world)
	ambient = Ambient.new()
	ambient.world = world
	add_child(ambient)
	traffic = Traffic.new()
	add_child(traffic)
	motos = Motos.new()
	motos.name = "Motos"
	add_child(motos)
	balls = Balls.new()
	balls.name = "Balls"
	add_child(balls)
	events = Events.new()
	events.name = "Events"
	add_child(events)
	crowd = Crowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	police = Police.new()
	police.name = "Police"
	add_child(police)
	dogs = Dogs.new()
	dogs.name = "Dogs"
	add_child(dogs)
	threats = Threats.new()
	threats.name = "Threats"
	add_child(threats)
	casino = Casino.new()
	casino.name = "Casino"
	add_child(casino)
	prison = Prison.new()
	prison.name = "Prison"
	add_child(prison)
	_players_root = Node3D.new()
	add_child(_players_root)
	_drops_root = Node3D.new()
	add_child(_drops_root)
	fx = CombatFx.new()
	add_child(fx)
	hud = Hud.new()
	add_child(hud)
	interaction = Interact.new()
	interaction.name = "Interact"
	add_child(interaction)
	_setup_interact()
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
		elif a.begins_with("--test="):
			_debug_test(a.trim_prefix("--test="))
		elif a.begins_with("--event=") and multiplayer.is_server():
			events.force(a.trim_prefix("--event="))
		elif a.begins_with("--time="):
			MatchState.time = float(a.trim_prefix("--time="))
		elif a == "--novsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif a.begins_with("--tp="):
			_debug_tp(a.trim_prefix("--tp="))
		elif multiplayer.is_server() and (a.begins_with("--heat=") or a.begins_with("--money=") or a.begins_with("--give=")):
			_debug_state(a)


func _exit_tree() -> void:
	if Net.game == self:
		Net.game = null


func _debug_shot(path: String) -> void:
	var wait := 4.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wait="):
			wait = float(a.trim_prefix("--wait="))
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().create_timer(wait).timeout
	print("fps %d  script %.1f ms  physics %.1f ms  gpu %.2f ms  draws %d  objects %d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


## Puts the local player somewhere: x,y,z[,yaw] in metres and degrees.
func _debug_tp(spec: String) -> void:
	var v := spec.split_floats(",")
	local_player.global_position = Vector3(v[0], v[1], v[2])
	if v.size() > 3:
		local_player.rotation.y = deg_to_rad(v[3])


## Host player state from the command line: --heat=N, --money=N, --give=item:n.
func _debug_state(a: String) -> void:
	var st: Dictionary = local_player.st
	if a.begins_with("--heat="):
		st.heat = int(a.trim_prefix("--heat="))
	elif a.begins_with("--money="):
		st.money = int(a.trim_prefix("--money="))
	else:
		var kv := a.trim_prefix("--give=").split(":")
		_give(st, kv[0], int(kv[1]) if kv.size() > 1 else 1)
	push_state(local_player)


## How a scripted test reports: one line a shell can grep, and the exit code to match.
func debug_result(test: String, ok: bool, detail := "") -> void:
	print("RESULT %s %s %s" % [test, "ok" if ok else "fail", detail])
	get_tree().quit(0 if ok else 1)


## Runs a whole match of traffic through its clock function, with nobody waiting for it,
## and checks that nothing touches, nothing leaves the road, and the seed alone decides
## where everything is.
func _debug_traffic() -> void:
	var seed_value := MatchState.seed_value
	var n: int = traffic.vehicles.size()
	var sample := func() -> PackedVector3Array:
		var out := PackedVector3Array()
		for t in [0.0, 31.7, 263.3, 611.9, 899.0]:
			for i in n:
				out.append(traffic.pos_of(i, t))
		return out
	var before: PackedVector3Array = sample.call()
	traffic.setup(seed_value + 1)
	var differs: bool = sample.call() != before
	traffic.setup(seed_value)
	var same: bool = sample.call() == before
	var half: Array[Vector3] = []
	for v in traffic.vehicles:
		half.append(v.half)
	var at := PackedVector3Array()
	at.resize(n)
	# Sorting along the road means only near neighbours need comparing.
	var keys := PackedFloat64Array()
	keys.resize(n)
	var touching := 0
	var strays := 0
	var first := ""
	for step in 3600:
		var t := step * 0.25
		for i in n:
			var p: Vector3 = traffic.pos_of(i, t)
			at[i] = p
			keys[i] = floorf((p.x + 1000.0) * 100.0) * 1000.0 + i
			if p.z - half[i].z < 52.8 or p.z + half[i].z > 69.4:
				strays += 1
				if first == "":
					first = "vehicle %d off the road at t=%.2f z=%.2f" % [i, t, p.z]
		keys.sort()
		for a in n:
			var i := int(fmod(keys[a], 1000.0))
			for b in range(a + 1, n):
				var j := int(fmod(keys[b], 1000.0))
				var gap := absf(at[j].x - at[i].x)
				if gap > 12.0:
					break
				if gap < half[i].x + half[j].x and absf(at[j].z - at[i].z) < half[i].z + half[j].z:
					touching += 1
					if first == "":
						first = "vehicles %d and %d touch at t=%.2f x=%.1f" % [i, j, t, at[i].x]
	debug_result("traffic", touching == 0 and strays == 0 and same and differs, "vehicles=%d touching=%d strays=%d same_seed_same=%s other_seed_differs=%s %s" % [n, touching, strays, same, differs, first])


## Scripted bits of play, for checking a feature without a hand on the keyboard.
func _debug_test(what: String) -> void:
	await get_tree().create_timer(0.6).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	local_player.rig.zoom(2)
	match what:
		"ride":
			local_player.global_position = Vector3(20, 0.2, 69.5)
			local_player.rotation.y = -PI / 2.0
			await get_tree().create_timer(0.3).timeout
			interact()
			Input.action_press("move_forward")
		"road":
			local_player.global_position = Vector3(0, 0.2, 57.8)
		"traffic":
			_debug_traffic()
		"ball":
			local_player.global_position = Layout.PITCHES[1][0] + Vector3(-4, 0.2, 0)
			local_player.rotation.y = -PI / 2.0
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"jail":
			srv_arrest(1)
		"shop":
			local_player.st.money = 5000
			hud.open_shop(2)
		"bicho":
			hud.open_bicho(7)
		"buy":
			# Walks the money verbs end to end: food, a bet, a pistol, the till, loot to the fence.
			local_player.st.money = 5000
			local_player.st.hp = 40.0
			local_player.global_position = DB.VENDORS[2].pos + Vector3(0, 0.2, -1)
			srv_buy(2, "acai")
			srv_buy(2, "caipirinha")
			local_player.global_position = DB.VENDORS[1].pos + Vector3(0, 0.2, -1)
			srv_buy(1, "pistol")
			srv_equip("pistol")
			local_player.global_position = DB.VENDORS[7].pos + Vector3(0, 0.2, -1)
			srv_bet(7, 3, 200)
			local_player.global_position = DB.VENDORS[2].pos + Vector3(0, 0.2, -1)
			srv_till(2)
			_give(local_player.st, "chain", 2)
			local_player.global_position = DB.VENDORS[10].pos + Vector3(0, 0.2, -1)
			srv_sell(10)
			print("state ", local_player.st)
		"hop":
			# Bunny hops along the promenade, seen from the side: each frame should be a different pose.
			local_player.global_position = Vector3(-20, 0.2, 45)
			local_player.rotation.y = -PI / 2.0
			_debug_side_cam()
			Input.action_press("move_forward")
			Input.action_press("sprint")
			Input.action_press("jump")
			await get_tree().create_timer(1.0).timeout
			await _debug_frames("hop", 8, 0.09)
			debug_result("hop", true)
		"moves":
			# Run, slide, crouch-walk and stand, one frame of each.
			local_player.global_position = Vector3(-20, 0.2, 45)
			local_player.rotation.y = -PI / 2.0
			_debug_side_cam()
			Input.action_press("move_forward")
			Input.action_press("sprint")
			await get_tree().create_timer(0.9).timeout
			await _debug_frames("run", 2, 0.12)
			Input.action_press("crouch")
			await get_tree().create_timer(0.25).timeout
			await _debug_frames("slide", 1, 0.1)
			Input.action_release("sprint")
			await get_tree().create_timer(1.6).timeout
			await _debug_frames("creep", 2, 0.2)
			Input.action_release("move_forward")
			Input.action_release("crouch")
			await get_tree().create_timer(0.6).timeout
			await _debug_frames("stand", 1, 0.1)
			debug_result("moves", true)
		"evade":
			# What a cop can and cannot see: behind its back, crouched, tucked away.
			var pl := local_player
			var cop: Dictionary = police.debug_solo(Vector3(0, 0, 20), Vector3.RIGHT)
			crowd.debug_clear()
			pl.global_position = Vector3(-12, 0.2, 20)
			await get_tree().create_timer(0.3).timeout
			Crime.report_crime(pl.global_position, 1, 1)
			var behind: int = pl.st.heat
			pl.global_position = Vector3(12, 0.2, 20)
			await get_tree().create_timer(0.3).timeout
			var stand: bool = police._sees(cop, pl, 18.0, Police.FOV_PATROL)
			Input.action_press("crouch")
			await get_tree().create_timer(0.6).timeout
			var crouched: bool = police._sees(cop, pl, 18.0, Police.FOV_PATROL)
			Input.action_release("crouch")
			await get_tree().create_timer(0.4).timeout
			Crime.report_crime(pl.global_position, 1, 1)
			var front: int = pl.st.heat
			var hide: int = Places.hide_near(pl.global_position, 400.0)
			pl.global_position = Places.hides[hide].pos
			for act in interaction.acts:
				if act.kind == &"hide" and act.arg == hide:
					interaction.srv_act(act.id, 0)
			await get_tree().create_timer(0.3).timeout
			var tucked: bool = pl.st.hide == hide and not police._sees(cop, pl, 400.0, PI)
			srv_unhide_me()
			await get_tree().create_timer(0.2).timeout
			var ok: bool = behind == 0 and front == 1 and stand and not crouched and tucked and pl.st.hide < 0
			debug_result("evade", ok, "behind %d front %d stand %s crouched %s tucked %s" % [behind, front, stand, crouched, tucked])
		"chase":
			# One cop after someone it can see but not reach: it must run out of puff, and the
			# heat must then die down a level at a time.
			var pl := local_player
			var cop: Dictionary = police.debug_solo(Vector3(0, 0, 20), Vector3.RIGHT)
			crowd.debug_clear()
			pl.global_position = Vector3(10, 0.2, 20)
			await get_tree().create_timer(0.3).timeout
			Crime.report_crime(pl.global_position, 1, 2)
			var heat0: int = pl.st.heat
			# Out of reach on a rooftop over the avenida, in plain view.
			pl.global_position = Vector3(10, 30.0, 20)
			pl.set_physics_process(false)
			Engine.time_scale = 10.0
			var t0 := MatchState.time
			var gave_up := -1.0
			var steps: Array = []
			var heat: int = heat0
			while MatchState.time - t0 < 200.0 and pl.st.heat > 0:
				await get_tree().process_frame
				if gave_up < 0.0 and cop.state == Police.PATROL:
					gave_up = MatchState.time - t0
				if pl.st.heat != heat:
					heat = pl.st.heat
					steps.append("%d@%.0f" % [heat, MatchState.time - t0])
			Engine.time_scale = 1.0
			var budget: float = Police.PURSUIT_BUDGET[2] + Police.ESCALATE_BONUS
			debug_result("chase", heat0 == 2 and gave_up > 0.0 and gave_up < budget + 20.0 and pl.st.heat == 0 and steps.size() == 2, "gave up %.0fs (budget %.0f) steps %s" % [gave_up, budget, steps])
		"headshot":
			# Rays at a standing man's head, chest and over his head; a sunbather; a seated stance.
			crowd.debug_clear()
			var at := Vector3(0, 0, 20)
			var i: int = crowd.debug_stand(at, 0.0)
			var h: float = 1.6 * crowd._scale[i]
			var o := at + Vector3(0, h, -6)
			var head: Array = crowd.ray_pick(o, Vector3(0, 0, 1), 30.0, 0.0)
			var chest: Array = crowd.ray_pick(at + Vector3(0, 0.95, -6), Vector3(0, 0, 1), 30.0, 0.0)
			var over: Array = crowd.ray_pick(at + Vector3(0, h + 0.5, -6), Vector3(0, 0, 1), 30.0, 0.0)
			var seat: Array = Kit.ray_hit(Vector3(0, 1.22, -6), Vector3(0, 0, 1), 30.0, Vector3.ZERO, 0.0, 1.0, Kit.STANCE_SEAT)
			var low: Array = Kit.ray_hit(Vector3(0, 1.6, -6), Vector3(0, 0, 1), 30.0, Vector3.ZERO, 0.0, 1.0, Kit.STANCE_CROUCH)
			# The whole way through: a pistol, aimed at the head, kills in one.
			local_player.global_position = at + Vector3(0, 0.2, -6)
			local_player.rotation.y = PI
			_give(local_player.st, "pistol", 1)
			local_player.st.equipped = "pistol"
			var kills := 0
			for k in 20:
				crowd.hp[i] = 60.0
				crowd.state[i] = Crowd.AMBIENT
				_last_attack.clear()
				local_player.st.mag["pistol"] = 12
				srv_attack(o, Vector3(0, 0, 1))
				if crowd.state[i] == Crowd.DEAD:
					kills += 1
			var ok: bool = head[0] == i and head[2] == DB.ZONE_HEAD and chest[0] == i and chest[2] == DB.ZONE_BODY and over[0] < 0 and seat[1] == DB.ZONE_HEAD and seat[0] > 0.0 and low[0] < 0.0 and kills >= 12
			debug_result("headshot", ok, "head %s chest %s over %s seat %s low %s kills %d/20" % [head, chest, over, seat, low, kills])
		"ko":
			# Fists to the head until he drops, then through his pockets, then he comes round.
			crowd.debug_clear()
			var at := Vector3(0, 0, 20)
			var i: int = crowd.debug_stand(at, 0.0)
			crowd.money[i] = 300
			crowd.hp[i] = 500.0
			local_player.global_position = at + Vector3(0, 0.2, -1.2)
			local_player.rotation.y = PI
			var o := at + Vector3(0, 1.6 * crowd._scale[i], -1.2)
			var punches := 0
			while crowd.state[i] != Crowd.KO and punches < 40:
				_last_attack.clear()
				srv_attack(o, Vector3(0, 0, 1))
				punches += 1
			var out: bool = crowd.state[i] == Crowd.KO
			var before: int = local_player.st.money
			for k in 14:
				crowd.srv_rob(i, 0.9)
				await get_tree().create_timer(0.1).timeout
			var took: int = local_player.st.money - before
			crowd._ko[i][0] = MatchState.time
			await get_tree().create_timer(0.3).timeout
			var woke: bool = crowd.state[i] != Crowd.KO
			debug_result("ko", out and took == 300 and woke, "punches %d took %d woke %s" % [punches, took, woke])
		"weapons":
			# Each weapon in the hand, seen from the side, then down the sights.
			local_player.global_position = Vector3(-20, 0.2, 45)
			local_player.rotation.y = -PI / 2.0
			_debug_side_cam()
			for item in ["knife", "pistol", "revolver", "smg"]:
				_give(local_player.st, item, 1)
				local_player.st.equipped = item
				await get_tree().create_timer(0.5).timeout
				await _debug_frames(item, 1, 0.05)
			local_player.get_child(local_player.get_child_count() - 1).current = false
			local_player.rig.cam.current = true
			local_player.rig.zoom(-2)
			for item in ["knife", "pistol", "revolver", "smg"]:
				local_player.st.equipped = item
				await get_tree().create_timer(0.5).timeout
				await _debug_frames("fp_" + item, 1, 0.05)
			srv_add_drop(Vector3(-17, 0.2, 45), 0, {"smg": 1})
			debug_result("weapons", true)
		"acts":
			# Groups are planned from the seed alone, and everyone at a table is sitting down.
			var a = crowd.acts
			var kinds := {}
			for g in a.groups:
				kinds[g.kind] = kinds.get(g.kind, 0) + 1
			var seated := 0
			for i in crowd.count:
				if crowd._sit[i] == 1 and crowd._idle[i] >= Kit.SIT:
					seated += 1
			var before: Array = []
			for g in a.groups:
				before.append([g.kind, g.pos, g.n])
			crowd.setup(MatchState.seed_value)
			var same: bool = before.size() == crowd.acts.groups.size()
			for k in before.size():
				var g: Dictionary = crowd.acts.groups[k]
				same = same and before[k][0] == g.kind and before[k][1] == g.pos and before[k][2] == g.n
			debug_result("acts", same and kinds.size() >= 9 and seated > 20 and Places.pits.size() >= 5, "groups %d kinds %s seated %d pits %d repeatable %s" % [before.size(), kinds, seated, Places.pits.size(), same])
		"pit":
			# Walk into a hole, stay in it, and jump out in two.
			var pit: Dictionary = Places.pits[0]
			local_player.global_position = pit.pos + Vector3(-3, 0.2, 0)
			local_player.rotation.y = -PI / 2.0
			Input.action_press("move_forward")
			await get_tree().create_timer(1.6).timeout
			var fell: bool = local_player._pit == 0
			await get_tree().create_timer(1.0).timeout
			var held: bool = local_player.global_position.distance_to(pit.pos) < pit.r and local_player._sink > 0.8
			for k in 2:
				Input.action_press("jump")
				await get_tree().create_timer(0.1).timeout
				Input.action_release("jump")
				await get_tree().create_timer(0.15).timeout
			await get_tree().create_timer(1.2).timeout
			var out: bool = local_player._pit < 0 and local_player.global_position.distance_to(pit.pos) > pit.r
			debug_result("pit", fell and held and out, "fell %s held %s out %s" % [fell, held, out])
		"look":
			# One frame of each kind of activity, from a camera stood a little way off it.
			hud.visible = false
			var cam := Camera3D.new()
			cam.fov = 55.0
			add_child(cam)
			cam.current = true
			var seen := {}
			for g in crowd.acts.groups:
				if seen.has(g.kind):
					continue
				seen[g.kind] = true
				cam.look_at_from_position(g.pos + Vector3(4.5, 3.2, -5.5), g.pos + Vector3(0, 0.8, 0))
				await get_tree().create_timer(1.3).timeout
				await _debug_frames("act%d" % g.kind, 1, 0.05)
			debug_result("look", true)
		"mug":
			# Walk up to a corner gang with cash: they whistle, run you down and take a cut,
			# and the one who took it still has it on him.
			var grp: Dictionary = crowd.acts.groups[crowd.acts.gangs[0]]
			local_player.st.money = 1000
			MatchState.time = Threats.QUIET_START + 1.0
			police.debug_solo(Vector3(280, 0, -30), Vector3.RIGHT)
			var mugged := false
			var carrying := 0
			for tries in 30:
				local_player.global_position = grp.pos + Vector3(0, 0.2, 14)
				threats._mug_ok.clear()
				threats._gang_ok.clear()
				await get_tree().create_timer(0.35).timeout
				local_player.global_position = grp.pos + Vector3(0, 0.2, 3)
				for k in 40:
					await get_tree().create_timer(0.2).timeout
					if local_player.st.money < 1000:
						mugged = true
						break
					if threats._pending.is_empty() and crowd._hostile.is_empty() and k > 3:
						break
				if mugged:
					break
			for i in crowd.count:
				if crowd.arch[i] == crowd._arch_index("malandro"):
					carrying = maxi(carrying, crowd.money[i])
			debug_result("mug", mugged and local_player.st.ko > 0.0 and carrying >= 350, "money %d floored %.1f mugger carries %d" % [local_player.st.money, local_player.st.ko, carrying])
		"tip":
			# A crime nobody in uniform saw, a bystander on the phone, then a cop who knows the face.
			crowd.debug_clear()
			var cop: Dictionary = police.debug_solo(Vector3(60, 0, 20), Vector3.RIGHT)
			var i: int = crowd.debug_stand(Vector3(0, 0, 26), 0.0)
			local_player.global_position = Vector3(0, 0.2, 20)
			await get_tree().create_timer(0.2).timeout
			var called := false
			for k in 60:
				crowd._call_ok = 0.0
				Crime.report_crime(local_player.global_position, 1, 2)
				if crowd._calls.has(i):
					called = true
					break
			var unseen: bool = local_player.st.heat == 0
			crowd._calls[i][0] = MatchState.time
			await get_tree().create_timer(0.3).timeout
			var known: bool = police._known.has(1)
			local_player.global_position = Vector3(70, 0.2, 20)
			cop.hold = true
			await get_tree().create_timer(0.6).timeout
			police._srv_spot(cop)
			debug_result("tip", called and unseen and known and local_player.st.heat == 2, "called %s unseen %s known %s heat %d" % [called, unseen, known, local_player.st.heat])
		"indoor":
			# Through the boteco's front door, a drink at the bar, out the back. The world must
			# agree that it is a room with a roof on it.
			var room: Dictionary = Places.rooms[1]
			local_player.global_position = room.doors[0][0] + Vector3(0, 0.2, 0)
			local_player.rotation.y = PI
			Input.action_press("move_forward")
			await get_tree().create_timer(1.4).timeout
			Input.action_release("move_forward")
			var inside: bool = Places.room_at(local_player.global_position) == 1
			var roofed: bool = police._roofed(local_player.global_position)
			var vi := 0
			for k in DB.VENDORS.size():
				if DB.VENDORS[k].name == "BOTECO DO ZÉ":
					vi = k
			local_player.st.money = 500
			local_player.st.hp = 50.0
			local_player.global_position = DB.VENDORS[vi].pos + Vector3(0.3, 0.2, 0)
			await get_tree().create_timer(0.3).timeout
			srv_buy(vi, "espetinho")
			var served: bool = local_player.st.hp > 80.0
			var cop: Dictionary = police.debug_solo(room.doors[0][0] + Vector3(6, 0, -1), Vector3.LEFT)
			cop.hold = false
			var steps := 0
			while Places.room_at(cop.pos) != 1 and steps < 600:
				police._move(cop, local_player.global_position, 6.0, 0.05)
				steps += 1
			var by_door: bool = steps < 600
			debug_result("indoor", inside and roofed and served and by_door, "inside %s roofed %s served %s cop in after %d steps" % [inside, roofed, served, steps])
		"casino":
			# Ten thousand spins should give back about nine tenths; a hand of blackjack plays
			# through; the safe pays a gunman and sets the house on him.
			var total := 0.0
			for k in 20000:
				total += Casino.slot_pays([casino._reel(), casino._reel(), casino._reel()])
			var rtp := total / 20000.0
			var room := 0
			local_player.global_position = Vector3(0, 0.2, 80)
			local_player.st.money = 5000
			await get_tree().create_timer(0.3).timeout
			var m0: int = local_player.st.money
			casino.srv_slot(50)
			casino._last.clear()
			casino.srv_roulette(0, 0, 50)
			casino._last.clear()
			casino.srv_bj(0, 50)
			if casino._hands.has(1):
				casino.srv_bj(2, 0)
			var played: bool = local_player.st.money != m0 or casino.bank != Casino.FLOAT
			var even: bool = local_player.st.money + casino.bank == m0 + Casino.FLOAT
			_give(local_player.st, "pistol", 1)
			local_player.st.equipped = "pistol"
			var before: int = local_player.st.money
			casino.srv_safe(local_player, {}, 0)
			var took: int = local_player.st.money - before
			await get_tree().create_timer(0.3).timeout
			var angry := 0
			for i in crowd.count:
				if crowd.state[i] == Crowd.HOSTILE:
					angry += 1
			debug_result("casino", rtp > 0.8 and rtp < 1.0 and played and even and took > 1000 and angry >= 3 and Places.rooms[room].kind == "cassino", "rtp %.3f played %s books balance %s safe %d bouncers %d" % [rtp, played, even, took, angry])
		"prison":
			# Arrested at the top heat: a long sentence, a shift that shortens it, a fight a
			# guard sees that lengthens it, a beating that does not end it, and a way out
			# through the floor that leaves you a fugitive.
			var pl := local_player
			pl.st.heat = 3
			pl.st.money = 500
			srv_arrest(1)
			await get_tree().create_timer(0.3).timeout
			var long: bool = absf(pl.st.jail - Prison.SENTENCE[3]) < 2.0 and Places.rooms[Places.room_at(pl.global_position)].kind == "presidio"
			var t0: float = pl.st.jail
			prison.srv_work(pl, {}, 0)
			var cut: bool = pl.st.jail < t0 - 10.0 and pl.st.money == 500 + Prison.WORK_PAY
			var t1: float = pl.st.jail
			prison.srv_fight(pl, pl.global_position, false)
			var added: bool = pl.st.jail > t1 + 5.0
			srv_damage(1, 500.0, -1)
			var alive: bool = not pl.st.dead and pl.st.jail > 0.0 and pl.st.ko > 0.0
			var inmates := 0
			for i in crowd.count:
				if crowd.arch[i] == crowd._arch_index("preso"):
					inmates += 1
			_give(pl.st, "colher", 1)
			for k in Prison.DIG_SESSIONS:
				prison._rest.clear()
				prison.srv_dig(pl, {}, 0)
			await get_tree().create_timer(0.3).timeout
			var out: bool = pl.st.jail <= 0.0 and pl.st.fug and pl.st.heat == 2 and Places.room_at(pl.global_position) < 0
			debug_result("prison", long and cut and added and alive and out and inmates > 20, "sentence ok %s work %s guard %s survives %s escaped %s inmates %d" % [long, cut, added, alive, out, inmates])
		"drugs":
			# Every drug gets you high, three in a row is one too many, and each overdose ends
			# the way it should: a bed and a bill, lighter pockets, somewhere else, or the morgue.
			var pl := local_player
			var bad: Array = []
			for d in DB.DRUGS:
				pl.st = Player.fresh_state()
				_give(pl.st, d, 3)
				srv_use(d)
				if pl.drug_phase(d) != "high":
					bad.append(d + " no high")
				srv_use(d)
				srv_use(d)
				if pl.drug_phase(d) != "od" or pl.st.inv.has(d):
					bad.append(d + " no od")
				if (pl.st.ko > 0.0) != DB.ITEMS[d].has("od_floor"):
					bad.append(d + " floor")
			# A moment in each state, so everything that reads it (legs, camera, screen) runs.
			for d in DB.DRUGS:
				for phase in ["high", "down", "od"]:
					pl.st = Player.fresh_state()
					pl.st.drugs[d] = {"phase": phase, "t": 5.0}
					await get_tree().create_timer(0.12).timeout
			pl.st = Player.fresh_state()
			await get_tree().create_timer(0.3).timeout
			var dose := func(d: String, n: int, money: int) -> void:
				pl.st = Player.fresh_state()
				pl.st.money = money
				_give(pl.st, d, n)
				for k in n:
					srv_use(d)
			dose.call("cocaine", 1, 0)
			var coke: bool = is_equal_approx(pl.speed_mult(), 1.6) and is_equal_approx(pl.melee_mult(), 2.0)
			dose.call("lanca", 1, 0)
			var floaty: bool = is_equal_approx(pl.jump_mult(), 1.8) and pl.gravity_mult() < 0.5
			dose.call("ketamine", 1, 0)
			var numb: bool = is_equal_approx(pl.damage_taken_mult(), 0.3)
			dose.call("rivotril", 1, 0)
			var calm: bool = pl.cool_mult() > 2.0 and pl.seen_mult() < 1.0
			pl.st = Player.fresh_state()
			pl.st.drugs["cerveja"] = {"phase": "high", "t": 5.0}
			var beer: bool = pl.is_drunk()
			# Cocaine: the heart stops, and the chemist starts it again for a price.
			dose.call("cocaine", 3, 1000)
			pl.st.hp = 2.0
			_srv_od_tick(pl)
			await get_tree().create_timer(0.2).timeout
			var room := Places.room_at(pl.global_position)
			var bed: bool = not pl.st.dead and pl.st.hp == 50.0 and pl.st.money == 1000 - DB.HOSPITAL_BILL and room >= 0 and Places.rooms[room].kind == "farmacia" and pl.st.drugs.is_empty()
			# Lança: out like a light, and somebody helps themselves.
			pl.global_position = Vector3(-20, 0.2, 20)
			dose.call("lanca", 3, 1000)
			var out: bool = pl.st.ko > 0.0
			pl.st.drugs["lanca"].t = 0.01
			await get_tree().create_timer(0.3).timeout
			var took := false
			for id in drops:
				took = took or drops[id].money == 300
			var robbed: bool = out and pl.st.money == 700 and took
			# Weed: at a kiosk the munchies do the shopping.
			dose.call("weed", 3, 100)
			pl.global_position = DB.VENDORS[2].pos + Vector3(0, 0.2, -1)
			srv_larica()
			var larica: bool = pl.st.money < 100
			# Doce: it ends somewhere else, flat out.
			dose.call("doce", 3, 0)
			var from: Vector3 = pl.global_position
			pl.st.drugs["doce"].t = 0.01
			await get_tree().create_timer(0.3).timeout
			var moved: bool = pl.st.ko > 0.0 and pl.global_position.distance_to(from) > 10.0 and pl.st.drugs.is_empty()
			# Guarana is groceries, as far as a checkpoint cares; bomba is not, and it kills.
			var legal: bool = DB.ITEMS.guarana.get("legal", false) and not DB.ITEMS.bomba.get("legal", false)
			pl.st = Player.fresh_state()
			dose.call("bomba", 3, 0)
			pl.st.hp = 3.0
			_srv_od_tick(pl)
			var dead: bool = pl.st.dead
			debug_result("drugs", bad.is_empty() and coke and floaty and numb and calm and beer and bed and robbed and larica and moved and legal and dead, "each %s coke %s lanca %s ket %s rivotril %s beer %s hospital %s robbed %s larica %s moved %s legal %s dies %s" % [bad, coke, floaty, numb, calm, beer, bed, robbed, larica, moved, legal, dead])
		"drugshot":
			# Every drug lying on the sand, then all of them in the pockets for the hotbar.
			var at := Vector3(-20, 0.0, 28)
			var ids: Array = DB.DRUGS + ["ammo"]
			for id in drops.keys():
				cl_drop_remove(id)
			for k in ids.size():
				srv_add_drop(at + Vector3((k % 6 - 2.5) * 1.5, 0, (k / 6) * 1.8), 0, {ids[k]: 1})
			srv_add_drop(at + Vector3(6.5, 0, 0.9), 250, {"bala": 2, "pistol": 1})
			local_player.global_position = at + Vector3(0, 0.2, 14)
			local_player.rotation.y = 0.0
			crowd.visible = false
			var cam := Camera3D.new()
			cam.fov = 38.0
			add_child(cam)
			cam.look_at_from_position(at + Vector3(0.8, 3.2, 8.5), at + Vector3(0.8, 0.3, 0.9))
			cam.current = true
			hud.visible = false
			await get_tree().create_timer(0.6).timeout
			await _debug_frames("drops", 2, 0.5)
			cam.fov = 20.0
			cam.look_at_from_position(at + Vector3(-1.5, 2.2, 6.5), at + Vector3(-1.5, 0.4, 0.9))
			await _debug_frames("drops_left", 1, 0.05)
			cam.look_at_from_position(at + Vector3(2.2, 2.2, 6.5), at + Vector3(2.2, 0.4, 0.9))
			await _debug_frames("drops_right", 1, 0.05)
			cam.current = false
			local_player.rig.cam.current = true
			hud.visible = true
			for d in DB.DRUGS:
				_give(local_player.st, d, 2)
			local_player.st.tol["bala"] = 0.7
			local_player.drug_sel = "bala"
			await get_tree().create_timer(0.5).timeout
			await _debug_frames("hotbar", 1, 0.05)
			local_player.st.money = 5000
			hud.open_shop(0)
			await get_tree().create_timer(0.3).timeout
			await _debug_frames("shop", 1, 0.05)
			hud.close_shop()
			# What the heavier ones do to the view, among people, and the bed it can end in.
			crowd.visible = true
			local_player.global_position = Vector3(38, 0.2, 43)
			local_player.rotation.y = -PI / 2.0
			local_player.rig.zoom(2)
			for look in [["doce", "high"], ["doce", "od"], ["bala", "high"], ["bomba", "high"], ["ayahuasca", "od"], ["ketamine", "od"]]:
				local_player.st.drugs = {look[0]: {"phase": look[1], "t": 30.0}}
				await get_tree().create_timer(2.0).timeout
				await _debug_frames("%s_%s" % [look[0], look[1]], 1, 0.05)
			local_player.st.drugs = {}
			local_player.global_position = DB.HOSPITAL_POS
			local_player.rotation.y = PI
			await get_tree().create_timer(1.5).timeout
			await _debug_frames("clinic", 1, 0.05)
			debug_result("drugshot", true)
		"settings":
			# Change things, save, forget them, load: they come back. And the menu builds.
			Settings._scripted = false
			Settings.path = "user://settings_test.cfg"
			Settings.mode = Settings.BORDERLESS
			Settings.size = Vector2i(1280, 720)
			Settings.fov = 95.0
			Settings.sens = 0.004
			Settings.volume = 0.3
			Settings.vsync = false
			Settings.save()
			Settings.mode = Settings.WINDOWED
			Settings.size = Vector2i(1600, 900)
			Settings.fov = 75.0
			Settings.sens = 0.0025
			Settings.volume = 0.8
			Settings.vsync = true
			Settings._load()
			var kept: bool = Settings.mode == Settings.BORDERLESS and Settings.size == Vector2i(1280, 720) and is_equal_approx(Settings.fov, 95.0) and is_equal_approx(Settings.sens, 0.004) and is_equal_approx(Settings.volume, 0.3) and not Settings.vsync
			var quiet: bool = absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.3) < 0.01
			hud.open_pause()
			await get_tree().process_frame
			await get_tree().process_frame
			var rows: int = hud._menu._list.get_child_count()
			# In the middle of the window and wholly inside it, at this size and a small one.
			var fits := true
			for win in [Vector2i(1600, 900), Vector2i(800, 480)]:
				get_window().size = win
				get_window().content_scale_size = Vector2i.ZERO
				await get_tree().process_frame
				await get_tree().process_frame
				var view: Rect2 = hud._menu.get_viewport_rect()
				var box: Rect2 = hud._menu._panel.get_global_rect()
				fits = fits and view.encloses(box) and box.get_center().distance_to(view.get_center()) < 4.0 and box.size.y > 150.0
				print("dbg window %s view %s panel %s" % [win, view, box])
			hud.close_pause()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
			Settings._scripted = true
			debug_result("settings", kept and quiet and rows > 12 and fits and not hud.menu_open, "kept %s volume applied %s menu rows %d centred and on screen %s" % [kept, quiet, rows, fits])
		"crouch":
			local_player.global_position = Vector3(-20, 0.2, 45)
			Input.action_press("crouch")
			await get_tree().create_timer(0.5).timeout
			var still: bool = local_player.is_crouched() and local_player.hspeed() < 0.1
			Input.action_press("move_forward")
			await get_tree().create_timer(1.2).timeout
			var spd: float = local_player.hspeed()
			var low: float = local_player.rig.position.y
			Input.action_release("crouch")
			await get_tree().create_timer(0.4).timeout
			var up: bool = not local_player.is_crouched()
			debug_result("crouch", still and up and absf(spd - Player.CROUCH_SPEED) < 0.3 and low < 1.0, "speed %.2f head %.2f" % [spd, low])
		_:
			LifeTests.run(self, what)


## A camera that travels beside the local player, looking at them side on.
func _debug_side_cam() -> void:
	var cam := Camera3D.new()
	cam.fov = 40.0
	local_player.add_child(cam)
	cam.position = Vector3(4.2, 0.9, 0.0)
	cam.rotation.y = PI / 2.0
	cam.current = true
	hud.visible = false
	# Nobody else in the picture.
	crowd.visible = false


## Saves `n` viewport frames `every` seconds apart as <--out dir>/<name>_<k>.png.
func _debug_frames(frame_name: String, n: int, every: float) -> void:
	var dir := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			dir = a.trim_prefix("--out=")
	for k in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [dir, frame_name, k])
		await get_tree().create_timer(every).timeout


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
	cl_init.rpc_id(pid, MatchState.seed_value, MatchState.duration, MatchState.time, MatchState.ended, _players_data(), crowd.snapshot(), drop_data, motos.snapshot(), events.snapshot())
	ready_peers.append(pid)
	bcast("cl_spawn", [pid, pname.left(16), DB.spawn_point(), Player.fresh_state()])


@rpc("authority", "call_remote", "reliable")
func cl_init(seed_value: int, duration: float, time: float, ended: bool, pdata: Array, crowd_snap: Array, drop_data: Array, moto_snap: Array, event: Array) -> void:
	cl_match_start(seed_value, duration, pdata)
	MatchState.time = time
	MatchState.ended = ended
	crowd.apply_snapshot(crowd_snap)
	for d in drop_data:
		cl_drop_add(d[0], d[1], d[2], d[3])
	motos.apply_snapshot(moto_snap)
	if event[0] >= 0:
		events.cl_event(event[0], event[1], event[2], event[3], event[4])


@rpc("authority", "call_remote", "reliable")
func cl_match_start(seed_value: int, duration: float, pdata: Array) -> void:
	MatchState.seed_value = seed_value
	MatchState.duration = duration
	MatchState.time = 0.0
	MatchState.ended = false
	MatchState.running = true
	crowd.setup(seed_value)
	dogs.setup(seed_value, crowd)
	traffic.setup(seed_value)
	motos.reset()
	if local_player != null:
		local_player.stop_ride()
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
	_till_ready.clear()
	_bicho_round = 0
	police.reset()
	threats.reset()
	casino.reset()
	prison.reset()
	balls.reset()
	events.srv_reset()
	var pdata: Array = []
	for id in players:
		var p = players[id]
		p.wanted_t = 0.0
		pdata.append([id, p.pname, DB.spawn_point(), Player.fresh_state()])
	bcast("cl_match_start", [MatchState.seed_value, MatchState.duration, pdata])
	# Loose drugs and ammo scattered on the sand.
	var loot: Array = DB.DRUGS + ["ammo", "ammo", "ammo"]
	for i in PICKUP_COUNT:
		var item: String = loot[randi() % loot.size()]
		srv_add_drop(DB.spawn_point(), 0, {item: 6 if item == "ammo" else 1})


func _on_peer_left(pid: int) -> void:
	ready_peers.erase(pid)
	_respawn.erase(pid)
	motos.srv_release(pid)
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
	_trip(delta)
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

	if int(MatchState.time / DB.BICHO_EVERY) > _bicho_round:
		_bicho_round = int(MatchState.time / DB.BICHO_EVERY)
		_srv_bicho_draw()

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
		var pitches := PackedFloat32Array()
		for id in players:
			var p = players[id]
			ids.append(id)
			ps.append(p.global_position if p.is_local else p.net_pos)
			yaws.append(p.rotation.y if p.is_local else p.net_yaw)
			mvs.append(p.net_byte())
			pitches.append(p.rig.rotation.x if p.is_local else p.net_pitch)
		for pid in ready_peers:
			if pid != 1:
				cl_moves.rpc_id(pid, ids, ps, yaws, mvs, pitches)

	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 2.0
		for pid in ready_peers:
			if pid != 1:
				cl_clock.rpc_id(pid, MatchState.time)


func _srv_tick_player(p: CharacterBody3D, delta: float, od_tick: bool) -> void:
	var st: Dictionary = p.st
	var dirty := false
	var ended: Array = []  # overdoses that have just run their course
	for d in st.drugs.keys():
		var e = st.drugs[d]
		e.t -= delta
		if e.t <= 0.0:
			var comedown: float = DB.ITEMS[d].comedown
			if e.phase == "high" and comedown > 0.0:
				st.drugs[d] = {"phase": "down", "t": comedown}
			else:
				st.drugs.erase(d)
				if e.phase == "od":
					ended.append(d)
			dirty = true
	for d in st.tol:
		st.tol[d] = maxf(0.0, st.tol[d] - DB.TOLERANCE_DECAY * delta)
	if _reload.has(p.id):
		var r: Array = _reload[p.id]
		r[1] -= delta
		if st.equipped != r[0] or not p.can_fight():
			_reload.erase(p.id)
		elif r[1] <= 0.0:
			_reload.erase(p.id)
			var n: int = mini(DB.ITEMS[r[0]].mag - st.mag.get(r[0], 0), st.ammo)
			st.mag[r[0]] = st.mag.get(r[0], 0) + n
			st.ammo -= n
			dirty = true
	if st.ko > 0.0:
		st.ko -= delta
		if st.ko <= 0.0:
			st.ko = 0.0
			dirty = true
	if st.jail > 0.0:
		st.jail -= delta
		if st.jail <= 0.0:
			prison.srv_release(p)
			send(p.id, "cl_toast", ["Time served. Try not to come back."])
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
	for d in ended:
		# Whoever rides one out on their own feet has no need of a bed.
		if DB.ITEMS[d].get("od_end", "") != "hospital":
			_srv_od_end(p, d)
	if od_tick and not st.dead:
		_srv_od_tick(p)


## Half a second of every overdose this player is in the middle of.
func _srv_od_tick(p: CharacterBody3D) -> void:
	for d in p.st.drugs.keys():
		if not p.st.drugs.has(d) or p.st.drugs[d].phase != "od":
			continue
		var def: Dictionary = DB.ITEMS[d]
		var dmg: float = def.get("od_dmg", 0.0)
		# Bala cooks you from the inside, and the sea is the only thing cold enough.
		if d == "bala" and p.in_sea():
			dmg = 0.0
		if d == "ayahuasca" and randf() < 0.4:
			bcast("cl_vomit", [p.id])
		if d == "cocaine" and randf() < 0.5:
			bcast("cl_nosebleed", [p.id])
		if dmg <= 0.0:
			continue
		if p.st.hp - dmg <= 0.0 and def.get("od_end", "") == "hospital":
			_srv_od_end(p, d)
			return
		srv_damage(p.id, dmg / p.damage_taken_mult(), -1)
		if p.st.dead:
			return


## How overdose `d` finishes for whoever is still alive at the end of it (`od_end` in DB.ITEMS):
## in a clinic bed with a bill, on the floor with lighter pockets, somewhere they have no memory
## of going, or just flat on their back for a bit.
func _srv_od_end(p: CharacterBody3D, d: String) -> void:
	var st: Dictionary = p.st
	if st.dead:
		return
	var def: Dictionary = DB.ITEMS[d]
	var kind: String = def.get("od_end", "")
	# Inside, the only place an overdose ends is the floor of wherever you already are.
	if st.jail > 0.0 and (kind == "hospital" or kind == "random"):
		kind = "ko"
	match kind:
		"hospital":
			var bill: int = mini(st.money, DB.HOSPITAL_BILL)
			st.money -= bill
			st.hp = 50.0
			st.drugs.clear()
			st.hide = -1
			police.release_chase(p.id)
			srv_floor(p.id, 2.0)
			srv_teleport(p.id, DB.HOSPITAL_POS)
			send(p.id, "cl_toast", ["You wake up on a drip in the back of the FARMÁCIA.  The bill: R$%d" % bill])
			bcast("cl_toast", ["%s overdosed and got carted off to the chemist" % p.pname])
		"robbed":
			var cash: int = int(st.money * DB.OD_ROBBED)
			st.money -= cash
			push_state(p)
			if cash > 0:
				srv_add_drop(p.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), cash, {})
			send(p.id, "cl_toast", ["You come round. Your pockets are R$%d lighter." % cash])
		"random":
			st.drugs.clear()
			var where := randi() % 3
			if where == 0:
				st.jail = 30.0
				police.release_chase(p.id)
				push_state(p)
				srv_teleport(p.id, DB.PRISON_POS + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
				send(p.id, "cl_toast", ["You wake up in the drunk tank. Nobody will say how you got here."])
			else:
				push_state(p)
				var spot: Vector3 = DB.WAKE_SPOTS[where - 1]
				# Whatever is highest there: a roof, if there is one.
				var roof := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(spot.x, 90.0, spot.z), Vector3(spot.x, 0.0, spot.z), 1))
				if not roof.is_empty():
					spot.y = roof.position.y + 0.3
				srv_teleport(p.id, spot)
				send(p.id, "cl_toast", ["You wake up... here. Where are your shoes?"])
			srv_floor(p.id, 2.5)
		"ko":
			srv_floor(p.id, def.get("od_ko", 3.0))


## Larica: someone too stoned to argue is at a kiosk, and the kiosk is happy to keep serving.
@rpc("any_peer", "call_remote", "reliable")
func srv_larica() -> void:
	var p = players.get(Net.sender())
	if p == null or not p.can_fight() or p.drug_phase("weed") != "od" or MatchState.time < _larica.get(p.id, 0.0):
		return
	_larica[p.id] = MatchState.time + 1.2
	for v in DB.VENDORS:
		if v.stock == DB.FOOD and p.global_position.distance_to(v.pos) < VENDOR_RANGE + 1.5:
			var item: String = ["coco", "espetinho", "acai"][randi() % 3]
			var price := price_at(v, item)
			if p.st.money < price:
				send(p.id, "cl_toast", ["Out of money. Still hungry."])
				return
			p.st.money -= price
			p.st.hp = minf(100.0, p.st.hp + DB.ITEMS[item].heal)
			push_state(p)
			send(p.id, "cl_toast", ["Larica: one more %s  (R$%d)" % [DB.ITEMS[item].name, price]])
			send(p.id, "cl_sound", ["cash", v.pos])
			return


## Someone's stomach turning itself out, for everyone nearby to enjoy.
@rpc("authority", "call_remote", "unreliable")
func cl_vomit(pid: int) -> void:
	var p = players.get(pid)
	if p != null:
		var mouth: Vector3 = p.global_position + Vector3(0, 1.0, 0) - p.global_basis.z * 0.3
		fx.spew(mouth, -p.global_basis.z, Color(0.45, 0.6, 0.15))
		Sfx.play("retch", mouth, 2.0)


@rpc("authority", "call_remote", "unreliable")
func cl_nosebleed(pid: int) -> void:
	var p = players.get(pid)
	if p != null:
		fx.spew(p.global_position + Vector3(0, 1.15, 0) - p.global_basis.z * 0.25, Vector3.DOWN, Color(0.8, 0.05, 0.05), 4)


## What the local player's own head is doing to the world: who looks like what, who is
## dancing, and what is lying on the sand that is not really there.
func _trip(delta: float) -> void:
	var p = local_player
	if p == null:
		return
	var doce: String = p.drug_phase("doce")
	Kit.trip = move_toward(Kit.trip, 2.0 if doce == "od" else (1.0 if doce == "high" else 0.0), 1.5 * delta)

	# Bala: whoever is standing near someone on it catches the mood.
	_party_t -= delta
	if _party_t <= 0.0:
		_party_t = 0.4
		var spots: Array = []
		for pid in players:
			if players[pid].is_loved():
				spots.append(players[pid].global_position)
		crowd.set_party(spots)

	# Doce: loot that was never there.
	_mirage_t -= delta
	if doce != "" and _mirage_t <= 0.0 and _mirages.size() < 6:
		_mirage_t = randf_range(1.5, 4.0)
		var a := randf() * TAU
		var node := Node3D.new()
		node.position = Vector3(p.global_position.x + cos(a) * randf_range(6.0, 16.0), p.global_position.y, p.global_position.z + sin(a) * randf_range(6.0, 16.0))
		var model := DrugKit.node(DB.DRUGS[randi() % DB.DRUGS.size()])
		model.scale = Vector3.ONE * randf_range(1.5, 4.0)
		model.position.y = 0.5
		node.add_child(model)
		_drops_root.add_child(node)
		_mirages.append(node)
	for node in _mirages.duplicate():
		node.rotation.y += delta * 2.0
		if doce == "" or node.position.distance_to(p.global_position) < 2.2:
			if doce != "":
				hud.toast("It was never there.")
			_mirages.erase(node)
			node.queue_free()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_move(pos: Vector3, yaw: float, mv: int, pitch: float) -> void:
	var p = players.get(Net.sender())
	if p != null and not p.is_local:
		p.net_pos = pos
		p.net_yaw = yaw
		p.net_mv = mv & 255
		p.net_pitch = clampf(pitch, -1.5, 1.5)


@rpc("authority", "call_remote", "unreliable_ordered")
func cl_moves(ids: PackedInt32Array, ps: PackedVector3Array, yaws: PackedFloat32Array, mvs: PackedByteArray, pitches: PackedFloat32Array) -> void:
	for i in ids.size():
		var p = players.get(ids[i])
		if p != null and not p.is_local:
			p.net_pos = ps[i]
			p.net_yaw = yaws[i]
			p.net_mv = mvs[i]
			p.net_pitch = pitches[i]


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
func cl_knock(v: Vector3) -> void:
	if local_player != null and not local_player.st.dead:
		local_player.knock(v)


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

## Hurts a player. A bare fist to the head may put them out cold instead; returns whether it did.
func srv_damage(pid: int, amount: float, attacker: int, zone := 0, ko := false) -> bool:
	var p = players.get(pid)
	if p == null or p.st.dead or MatchState.ended or p.st.get("hide", -1) >= 0:
		return false
	if ko and zone == DB.ZONE_HEAD and p.st.ko <= 0.0 and MatchState.time > _ko_immune.get(pid, 0.0) and randf() < DB.KO_CHANCE:
		p.st.ko = DB.KO_PLAYER
		_ko_immune[pid] = MatchState.time + DB.KO_PLAYER + DB.KO_IMMUNE
		motos.srv_release(pid)
		push_state(p)
		bcast("cl_ko", [p.global_position + Vector3(0, 0.6, 0), DB.KO_PLAYER])
		return true
	p.st.hp -= amount * p.damage_taken_mult()
	if p.st.hp <= 0.0:
		_srv_kill(p, attacker)
	push_state(p)
	return false


## Puts a player on the floor for `seconds`: tackled, not hurt.
func srv_floor(pid: int, seconds: float) -> void:
	var p = players.get(pid)
	if p == null or p.st.dead:
		return
	p.st.ko = maxf(p.st.ko, seconds)
	_ko_immune[pid] = MatchState.time + seconds + DB.KO_IMMUNE
	motos.srv_release(pid)
	push_state(p)
	bcast("cl_ko", [p.global_position + Vector3(0, 0.6, 0), seconds])


## Going through the pockets of a player who is out cold: half what they carry.
@rpc("any_peer", "call_remote", "reliable")
func srv_rob_player(victim: int) -> void:
	var p = players.get(Net.sender())
	var v = players.get(victim)
	if p == null or v == null or p == v or not p.can_fight() or v.st.ko <= 0.0 or v.st.dead:
		return
	if p.global_position.distance_to(v.global_position) > 3.5 or _robbed.get(victim, 0.0) > MatchState.time:
		return
	_robbed[victim] = MatchState.time + DB.KO_PLAYER + 1.0
	var cash: int = v.st.money / 2
	v.st.money -= cash
	p.st.money += cash
	var msg := "Robbed %s of R$%d" % [v.pname, cash]
	for item in DB.LOOT:
		if v.st.inv.get(item, 0) > 0:
			v.st.inv[item] -= 1
			_give(p.st, item, 1)
			msg += " + %s" % DB.ITEMS[item].name
			break
	push_state(p)
	push_state(v)
	send(p.id, "cl_toast", [msg])
	send(p.id, "cl_sound", ["cash", v.global_position])
	send(victim, "cl_toast", ["%s went through your pockets" % p.pname])


func _srv_kill(p: CharacterBody3D, attacker: int) -> void:
	var st: Dictionary = p.st
	if st.jail > 0.0:
		# Nobody dies their way out of a sentence: they wake up on the floor with it still to do.
		st.hp = 40.0
		srv_floor(p.id, 6.0)
		return
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
	motos.srv_release(p.id)
	var killer = players.get(attacker)
	if killer != null and killer != p:
		killer.st.kills += 1
		push_state(killer)
		bcast("cl_toast", ["%s killed %s" % [killer.pname, p.pname]])
	else:
		bcast("cl_toast", ["%s died" % p.pname])


## `origin` is where on the attacker's line of sight the blow starts: the point on the camera
## ray beside their head, so a shot goes where the crosshair says in third person too.
@rpc("any_peer", "call_remote", "reliable")
func srv_attack(origin: Vector3, dir: Vector3) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	if p == null or not p.can_fight() or dir.length_squared() < 0.5:
		return
	if p.is_raging() and p.st.equipped != "fists":
		# Too far gone for anything with moving parts.
		p.st.equipped = "fists"
		push_state(p)
	var w = DB.ITEMS[p.st.equipped]
	var now := Time.get_ticks_msec()
	if now - _last_attack.get(pid, 0) < w.cooldown * 1000.0 - 60.0:
		return
	_last_attack[pid] = now

	dir = dir.normalized()
	# Trust the client's line only as far as its own head: no shooting from round a corner.
	var eye: Vector3 = p.eye()
	if origin.distance_to(eye) > 1.5 or not _clear(eye, origin):
		origin = eye
	var reach: float = w.range
	var crouched: bool = p.is_crouched()
	if not w.melee:
		if _reload.has(pid):
			return
		if p.st.mag.get(p.st.equipped, 0) <= 0:
			send(pid, "cl_sound", ["dry", eye])
			_srv_reload(p)
			return
		p.st.mag[p.st.equipped] -= 1
		# Rounds are the shooter's business; nobody else needs every one of them.
		send(pid, "cl_state", [pid, p.st])
		if p.is_sniper():
			reach *= 2.5
		else:
			# Steadier crouched, wilder in the air.
			var spread: float = w.spread * (0.6 if crouched else (1.5 if p.net_byte() & 7 == Player.MV_AIR else 1.0))
			dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()

	var hit := _ray_hit(origin, dir, reach, 0.35 if w.melee else 0.0, pid)
	# A football in the way takes the hit instead, and takes off.
	var ball_t: float = balls.srv_strike(origin, dir, hit.t, pid, 1.0 if w.melee else 1.5)
	if ball_t >= 0.0:
		bcast("cl_fx", [origin, origin + dir * ball_t, w.melee, DB.WHO_PLAYER, pid, DB.WHO_NONE, -1])
		bcast("cl_sound", ["kick", origin + dir * ball_t])
		if not w.melee:
			Crime.report_noise(origin, 90.0, pid)
			Crime.report_crime(origin, pid, 3)
		return
	# And the pair on the bike who just had your wallet.
	var bike_t: float = threats.srv_strike(origin, dir, hit.t)
	if bike_t >= 0.0:
		bcast("cl_fx", [origin, origin + dir * bike_t, w.melee, DB.WHO_PLAYER, pid, DB.WHO_NONE, -1])
		if not w.melee:
			Crime.report_noise(origin, 90.0, pid)
		return
	var dmg: float = w.damage * (p.melee_mult() if w.melee else 1.0)
	# So does the armoured truck, when there is one to crack.
	var truck_t: float = events.srv_strike(origin, dir, hit.t, dmg, pid)
	if truck_t >= 0.0:
		bcast("cl_fx", [origin, origin + dir * truck_t, w.melee, DB.WHO_PLAYER, pid, DB.WHO_NONE, -1])
		if not w.melee:
			Crime.report_noise(origin, 90.0, pid)
		return
	var res := 0
	var ko: bool = w.get("ko", false)
	if hit.type != DB.WHO_NONE and hit.zone == DB.ZONE_HEAD:
		res |= DB.FX_HEAD
		if w.melee:
			dmg *= 1.5
		elif randf() < w.head_kill:
			# One in the head: that is that, most of the time.
			dmg = 9999.0
			res |= DB.FX_KILL
		else:
			dmg *= DB.HEAD_MULT
	match hit.type:
		DB.WHO_PLAYER:
			if srv_damage(hit.id, dmg, pid, hit.zone, ko):
				res |= DB.FX_KO
			if w.melee and p.drug_phase("bomba") != "" and p.drug_phase("bomba") != "down":
				# A fist with a needle behind it: whoever it lands on leaves the ground.
				send(hit.id, "cl_knock", [dir * 9.0 + Vector3(0, 6.0, 0)])
		DB.WHO_COP:
			if police.srv_damage_cop(hit.id, dmg, pid, hit.zone, ko):
				res |= DB.FX_KO
		DB.WHO_NPC:
			if crowd.srv_damage_npc(hit.id, dmg, pid, hit.zone, ko):
				res |= DB.FX_KO
		DB.WHO_DOG:
			if dogs.srv_damage(hit.id, dmg, pid):
				res |= DB.FX_KILL
	bcast("cl_fx", [origin, origin + dir * hit.t, w.melee, DB.WHO_PLAYER, pid, hit.type, hit.id, res])
	if p.st.jail > 0.0 and w.melee and hit.type != DB.WHO_NONE:
		prison.srv_fight(p, origin + dir * hit.t, res & DB.FX_KO != 0)

	if not w.melee:
		Crime.report_noise(origin, 90.0, pid)
		Crime.report_crime(origin, pid, 3)
	elif hit.type != DB.WHO_NONE:
		Crime.report_crime(origin, pid, 2)
		# Inside, a fight is the afternoon's entertainment.
		if p.st.jail <= 0.0:
			crowd.srv_fight_seen(origin + dir * hit.t, pid)


## Nothing solid between a and b.
func _clear(a: Vector3, b: Vector3) -> bool:
	if a.distance_squared_to(b) < 0.0001:
		return true
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1)).is_empty()


## First thing the ray meets: {type (DB.WHO_*), id, t, zone (DB.ZONE_*)}. `grow` fattens bodies.
func _ray_hit(o: Vector3, d: Vector3, max_t: float, grow: float, exclude: int) -> Dictionary:
	var best := {"type": DB.WHO_NONE, "id": -1, "t": max_t, "zone": DB.ZONE_BODY}
	var q := PhysicsRayQueryParameters3D.create(o, o + d * max_t, 1)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	if not wall.is_empty():
		best.t = o.distance_to(wall.position)
	# Inmates and people outside cannot reach each other through the walls.
	var inside: bool = players.has(exclude) and players[exclude].st.jail > 0.0
	for pid in players:
		var p = players[pid]
		if pid == exclude or p.st.dead or p.st.get("hide", -1) >= 0 or (p.st.jail > 0.0) != inside:
			continue
		var h: Array = Kit.ray_hit(o, d, best.t, p.global_position, p.rotation.y if p.is_local else p.net_yaw, Player.BODY_SCALE, p.stance(), grow)
		if h[0] >= 0.0:
			best = {"type": DB.WHO_PLAYER, "id": pid, "t": h[0], "zone": h[1]}
	var c: Array = police.ray_pick(o, d, best.t, grow)
	if c[0] >= 0:
		best = {"type": DB.WHO_COP, "id": c[0], "t": c[1], "zone": c[2]}
	var n: Array = crowd.ray_pick(o, d, best.t, grow)
	if n[0] >= 0:
		best = {"type": DB.WHO_NPC, "id": n[0], "t": n[1], "zone": n[2]}
	var dog: Array = dogs.ray_pick(o, d, best.t, grow)
	if dog[0] >= 0:
		best = {"type": DB.WHO_DOG, "id": dog[0], "t": dog[1], "zone": DB.ZONE_BODY}
	return best


# --- reloading ---

@rpc("any_peer", "call_remote", "reliable")
func srv_reload() -> void:
	var p = players.get(Net.sender())
	if p != null and p.can_fight():
		_srv_reload(p)


func _srv_reload(p) -> void:
	var item: String = p.st.equipped
	if not DB.is_gun(item) or _reload.has(p.id) or p.st.ammo <= 0 or p.st.mag.get(item, 0) >= DB.ITEMS[item].mag:
		return
	_reload[p.id] = [item, DB.ITEMS[item].reload]
	bcast("cl_anim", [p.id, "reload", DB.ITEMS[item].reload])


## A player's body doing something other peers should see: reloading, for now.
@rpc("authority", "call_remote", "reliable")
func cl_anim(pid: int, what: String, seconds: float) -> void:
	var p = players.get(pid)
	if p != null:
		p.play(what, seconds)


## One attack: who threw it, where it went and who (if anyone) it struck. DB.WHO_* types.
@rpc("authority", "call_remote", "unreliable")
## `res` is DB.FX_* bits: a head hit, an outright kill, a knockout.
func cl_fx(from: Vector3, to: Vector3, melee: bool, src_type: int, src_id: int, hit_type: int, hit_id: int, res := 0) -> void:
	_fx_actor(src_type, src_id, true)
	_fx_actor(hit_type, hit_id, false)
	var mine: bool = src_type == DB.WHO_PLAYER and local_player != null and src_id == local_player.id
	if not melee and src_type == DB.WHO_PLAYER:
		var shooter = players.get(src_id)
		if shooter != null:
			from = shooter.muzzle()
			fx.shell(from, shooter.global_basis.x)
	fx.strike(from, to, melee, hit_type != DB.WHO_NONE)
	if not melee:
		Sfx.play("shot", from, 4.0)
	elif hit_type != DB.WHO_NONE:
		Sfx.play("punch", to)
	if hit_type != DB.WHO_NONE and hit_type != DB.WHO_PLAYER and hit_type != DB.WHO_DOG and res & DB.FX_KILL == 0:
		Sfx.play("grunt", to, -3.0, 0.8 + (hit_id * 7 % 50) * 0.01)
	if res & DB.FX_HEAD:
		fx.headshot(to, not melee)
		Sfx.play("headshot", to, 2.0)
	if res & DB.FX_KO:
		Sfx.play("ko", to, 3.0)
	if mine:
		if not melee:
			local_player.recoil()
		if hit_type != DB.WHO_NONE:
			hud.hit_marker(res & DB.FX_HEAD != 0, res & (DB.FX_KILL | DB.FX_KO) != 0)


@rpc("authority", "call_remote", "unreliable")
func cl_sound(sound: String, at: Vector3) -> void:
	Sfx.play(sound, at)


func _fx_actor(type: int, id: int, attack: bool) -> void:
	match type:
		DB.WHO_PLAYER:
			var p = players.get(id)
			if p != null:
				p.fx_event(attack)
		DB.WHO_COP: police.fx_event(id, attack)
		DB.WHO_NPC: crowd.fx_event(id, attack)
		DB.WHO_DOG: dogs.fx_event(id, attack)


## A client reporting that it walked in front of vehicle `vi`.
@rpc("any_peer", "call_remote", "reliable")
func srv_run_over(vi: int) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	var now := Time.get_ticks_msec()
	if p == null or not p.can_fight() or vi < 0 or vi >= traffic.vehicles.size() or now - _last_hit.get(pid, 0) < 800:
		return
	var at: Vector3 = traffic.pos_of(vi, MatchState.time)
	if at.distance_to(p.global_position) > 14.0:
		return
	_last_hit[pid] = now
	bcast("cl_fx", [at + Vector3(0, 1, 0), p.global_position + Vector3(0, 0.8, 0), true, DB.WHO_NONE, -1, DB.WHO_PLAYER, pid])
	srv_damage(pid, traffic.vehicles[vi].damage, -1)


# --- arrest ---

func srv_arrest(pid: int) -> void:
	var p = players.get(pid)
	if p == null or not p.at_large():
		return
	p.st.hide = -1
	p.st.vis = 0
	# Gear and contraband confiscated; cash stays in your pocket.
	p.st.inv = {"fists": 1}
	p.st.equipped = "fists"
	p.st.ammo = 0
	# The more they wanted you, the longer you get.
	p.st.jail = Prison.sentence(p.st.heat)
	p.st.heat = 0
	p.wanted_t = 0.0
	police.release_chase(pid)
	motos.srv_release(pid)
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
		# A gun comes loaded.
		if DB.is_gun(item) and not st.mag.has(item):
			st.mag[item] = DB.ITEMS[item].mag


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
	# A lone drug or box of rounds lies there as itself, with nothing under it.
	var only: String = items.keys()[0] if money == 0 and items.size() == 1 else ""
	if DrugKit.has(only):
		var model := DrugKit.node(only)
		model.scale = Vector3.ONE * 1.6
		model.position.y = 0.2
		turn.add_child(model)
	else:
		var color := Color(0.25, 0.8, 0.35) if money > 0 else Color(0.85, 0.3, 0.8)
		turn.add_child(_drop_part(Vector3(0.55, 0.22, 0.3) if money > 0 else Vector3(0.42, 0.36, 0.42), color))
		if money > 0:
			turn.add_child(_drop_part(Vector3(0.12, 0.24, 0.32), Color(1.0, 0.85, 0.3)))
		# A weapon lies on top where it can be seen for what it is; failing that, a drug does.
		var top := 0.38
		for item in items:
			if DB.ITEMS.has(item) and DB.ITEMS[item].get("held", 0) > 0:
				var gun := WeaponKit.node(DB.ITEMS[item].held)
				gun.scale = Vector3.ONE * 1.8
				gun.position = Vector3(0, top, 0)
				gun.rotation = Vector3(0, PI / 2.0, 1.2)
				turn.add_child(gun)
				top += 0.3
				break
		for item in items:
			if DrugKit.has(item):
				var model := DrugKit.node(item)
				model.position = Vector3(0, top + 0.12, 0)
				turn.add_child(model)
				break
	var parts: Array = []
	if money > 0:
		parts.append("R$%d" % money)
	for item in items:
		parts.append("%s x%d" % [DB.ITEMS[item].name if DB.ITEMS.has(item) and item != "ammo" else item, items[item]])
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
## Uses whatever is in reach, as F would. For scripted tests.
func interact() -> void:
	interaction.press()


## Registers the things F does that this scene owns: vendors, hiding places, bikes, drops.
func _setup_interact() -> void:
	for vi in DB.VENDORS.size():
		var v: Dictionary = DB.VENDORS[vi]
		interaction.add(&"vendor", v.pos, 2.4 if v.get("indoor", false) else VENDOR_RANGE, v.name, vi, {"jail": Interact.INSIDE if v.get("jail", false) else Interact.FREE})
	for hi in Places.hides.size():
		var h: Dictionary = Places.hides[hi]
		interaction.add(&"hide", h.pos, 2.4, "hide " + DB.HIDE_KINDS[h.kind].name, hi)
	for u in Places.uses:
		interaction.add(u.kind, u.pos, 2.2, u.prompt, u.arg, {"hold": u.hold, "jail": u.jail})
	interaction.on(&"work", Callable(), prison.srv_work)
	interaction.on(&"weights", Callable(), prison.srv_weights)
	interaction.on(&"meal", Callable(), prison.srv_meal)
	interaction.on(&"bribe", Callable(), prison.srv_bribe)
	interaction.on(&"bail", Callable(), prison.srv_bail)
	interaction.on(&"dig", Callable(), prison.srv_dig)
	interaction.on(&"climb", Callable(), prison.srv_climb)
	interaction.on(&"dice", func(_a: Dictionary) -> void: hud.open_dice())
	interaction.on(&"slot", func(_a: Dictionary) -> void: hud.open_slot())
	interaction.on(&"roulette", func(_a: Dictionary) -> void: hud.open_roulette())
	interaction.on(&"blackjack", func(_a: Dictionary) -> void: hud.open_blackjack())
	interaction.on(&"cage", Callable(), casino.srv_safe)
	interaction.on(&"clothes", Callable(), _srv_clothes)
	interaction.on(&"vendor", _use_vendor)
	interaction.on(&"hide", Callable(), _srv_hide)
	interaction.on(&"unhide", func(_a: Dictionary) -> void: to_server("srv_unhide_me"))
	interaction.on(&"dismount", func(_a: Dictionary) -> void: to_server("srv_dismount", [], motos))
	interaction.on(&"mount", func(a: Dictionary) -> void: to_server("srv_mount", [a.arg], motos))
	interaction.on(&"pickup", func(a: Dictionary) -> void: to_server("srv_pickup", [a.arg]))
	interaction.on(&"rob_player", func(a: Dictionary) -> void: to_server("srv_rob_player", [a.arg]))
	interaction.provide(_offer_near)


func _use_vendor(a: Dictionary) -> void:
	match DB.VENDORS[a.arg].kind:
		"bicho": hud.open_bicho(a.arg)
		"fence": to_server("srv_sell", [a.arg])
		_: hud.open_shop(a.arg)


## What comes and goes: the way out of a hiding place, a bike to get on or off, loot on the ground.
func _offer_near(p, out: Array) -> void:
	var at: Vector3 = p.global_position
	if p.st.get("hide", -1) >= 0:
		out.append(Interact.offer(&"unhide", at, "climb out", 0, 100))
		return
	if motos.bike_of(p.id) >= 0:
		out.append(Interact.offer(&"dismount", at, "get off", 0, 100))
		return
	if not p.can_fight():
		return
	for pid in players:
		var v = players[pid]
		if v != p and v.st.ko > 0.0 and not v.st.dead and at.distance_to(v.global_position) < 2.5:
			out.append(Interact.offer(&"rob_player", at, "go through %s's pockets" % v.pname, pid, 3, 0.8))
	var bike: int = motos.free_near(at)
	if bike >= 0:
		out.append(Interact.offer(&"mount", at, "take the moto", bike, 2))
	var best := -1
	var best_d := PICKUP_RANGE
	for id in drops:
		var d := at.distance_to(drops[id].pos)
		if d < best_d:
			best = id
			best_d = d
	if best >= 0:
		out.append(Interact.offer(&"pickup", at, "pick up", best, 1))


## A change of clothes: whoever they were looking for, it was not someone dressed like this.
func _srv_clothes(p, _a: Dictionary, _arg: int) -> void:
	if p.st.money < DB.CLOTHES_PRICE:
		send(p.id, "cl_toast", ["Not enough money"])
		return
	p.st.money -= DB.CLOTHES_PRICE
	p.st.fug = false
	p.st.look = randi() % 1000
	police.forget(p.id)
	push_state(p)
	send(p.id, "cl_toast", ["New clothes. Nobody would know you."])
	send(p.id, "cl_sound", ["cash", p.global_position])


# --- hiding ---

func _srv_hide(p, a: Dictionary, _arg: int) -> void:
	if not p.can_fight():
		return
	for pid in players:
		if players[pid].st.get("hide", -1) == a.arg:
			send(p.id, "cl_toast", ["Somebody is already in there"])
			return
	p.st.hide = a.arg
	push_state(p)
	# Anyone who watched you climb in knows exactly where to look.
	police.srv_hid(p.id, a.pos)
	srv_teleport(p.id, a.pos)


@rpc("any_peer", "call_remote", "reliable")
func srv_unhide_me() -> void:
	srv_unhide(Net.sender(), false)


## Out of the hiding place: by choice, or hauled out by the cop who found them.
func srv_unhide(pid: int, found: bool) -> void:
	var p = players.get(pid)
	if p == null or p.st.get("hide", -1) < 0:
		return
	var h: Dictionary = Places.hides[p.st.hide]
	p.st.hide = -1
	push_state(p)
	srv_teleport(pid, h.exit)
	if found:
		send(pid, "cl_toast", ["TE ACHEI!  Run!"])


@rpc("authority", "call_remote", "unreliable")
func cl_ko(at: Vector3, seconds: float) -> void:
	fx.ko_stars(at, seconds)
	Sfx.play("punch", at, 3.0, 0.7)


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
	send(p.id, "cl_sound", ["cash", drop.pos])
	push_state(p)


## The vendor a player is standing at, or null if they are not at vendor `vi`.
func _vendor_for(p, vi: int):
	if p == null or not p.can_fight() or vi < 0 or vi >= DB.VENDORS.size():
		return null
	var v = DB.VENDORS[vi]
	return v if p.global_position.distance_to(v.pos) <= VENDOR_RANGE + 1.5 else null


## What `item` costs at vendor v.
func price_at(v: Dictionary, item: String) -> int:
	return int(DB.ITEMS[item].price * v.get("discount", 1.0))


@rpc("any_peer", "call_remote", "reliable")
func srv_buy(vi: int, item: String) -> void:
	var p = players.get(Net.sender())
	var v = _vendor_for(p, vi)
	if v == null or not v.stock.has(item):
		return
	var def = DB.ITEMS[item]
	var price := price_at(v, item)
	if p.st.money < price or (def.type == "weapon" and p.st.inv.has(item)):
		return
	p.st.money -= price
	match def.type:
		"ammo": p.st.ammo += def.amount
		"weapon":
			_give(p.st, item, 1)
			if DB.is_gun(item):
				p.st.ammo += def.mag
		"food":
			p.st.hp = minf(100.0, p.st.hp + def.heal)
			if def.get("buff", false):
				p.st.drugs[item] = {"phase": "high", "t": def.duration}
		_: _give(p.st, item, 1)
	push_state(p)


## Emptying a kiosk till at gunpoint. It takes a while to fill up again.
@rpc("any_peer", "call_remote", "reliable")
func srv_till(vi: int) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	var v = _vendor_for(p, vi)
	if v == null or not v.get("till", false):
		return
	if not DB.is_gun(p.st.equipped):
		send(pid, "cl_toast", ["Nobody hands over a till to anything less than a gun"])
		return
	if MatchState.time < _till_ready.get(vi, 0.0):
		send(pid, "cl_toast", ["Till is empty - someone got here first"])
		return
	_till_ready[vi] = MatchState.time + TILL_COOLDOWN
	var cash := randi_range(150, 350)
	p.st.money += cash
	push_state(p)
	send(pid, "cl_toast", ["Cleaned out the till: R$%d" % cash])
	send(pid, "cl_sound", ["cash", v.pos])
	Crime.report_noise(v.pos, 55.0, pid)
	Crime.report_crime(v.pos, pid, 2)


## Jogo do bicho: one bet at a time on one of the 25 animals.
@rpc("any_peer", "call_remote", "reliable")
func srv_bet(vi: int, animal: int, amount: int) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	var v = _vendor_for(p, vi)
	if v == null or v.kind != "bicho" or animal < 0 or animal >= DB.BICHOS.size() or not DB.BETS.has(amount):
		return
	if not p.st.bet.is_empty():
		send(pid, "cl_toast", ["You already have a bet riding on the next draw"])
		return
	if p.st.money < amount:
		return
	p.st.money -= amount
	p.st.bet = {"animal": animal, "amount": amount}
	push_state(p)
	send(pid, "cl_toast", ["R$%d on %s. Boa sorte!" % [amount, DB.BICHOS[animal]]])


func _srv_bicho_draw() -> void:
	var winner := randi() % DB.BICHOS.size()
	var any := false
	for id in players:
		var p = players[id]
		if p.st.bet.is_empty():
			continue
		any = true
		if p.st.bet.animal == winner:
			var won: int = p.st.bet.amount * DB.BICHO_PAYS
			p.st.money += won
			send(id, "cl_toast", ["Deu %s!  You won R$%d" % [DB.BICHOS[winner], won]])
			send(id, "cl_sound", ["cash", p.global_position])
		else:
			send(id, "cl_toast", ["Deu %s. Your %s lost." % [DB.BICHOS[winner], DB.BICHOS[p.st.bet.animal]]])
		p.st.bet = {}
		push_state(p)
	if not any:
		return


## Turns everything stolen in a player's pockets into cash.
@rpc("any_peer", "call_remote", "reliable")
func srv_sell(vi: int) -> void:
	var pid := Net.sender()
	var p = players.get(pid)
	var v = _vendor_for(p, vi)
	if v == null or v.kind != "fence":
		return
	var total := 0
	for item in DB.LOOT:
		total += p.st.inv.get(item, 0) * DB.ITEMS[item].price
		p.st.inv.erase(item)
	if total == 0:
		send(pid, "cl_toast", ["Nothing to sell. Bring watches, phones, cameras, chains."])
		return
	p.st.money += total
	push_state(p)
	send(pid, "cl_toast", ["Fenced the lot for R$%d" % total])
	send(pid, "cl_sound", ["cash", v.pos])


@rpc("any_peer", "call_remote", "reliable")
func srv_equip(item: String) -> void:
	var p = players.get(Net.sender())
	if p != null and p.can_act() and not p.is_raging() and p.st.inv.has(item) and DB.ITEMS.has(item) and DB.ITEMS[item].type == "weapon":
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
	var def: Dictionary = DB.ITEMS[item]
	if tol > 1.0:
		p.st.drugs[item] = {"phase": "od", "t": def.od}
		send(p.id, "cl_toast", ["%s: OVERDOSE" % def.name])
		if def.has("od_floor"):
			srv_floor(p.id, def.od_floor)
	else:
		p.st.drugs[item] = {"phase": "high", "t": def.duration}
	push_state(p)
	if def.has("sound"):
		bcast("cl_sound", [def.sound, p.global_position + Vector3(0, 1.2, 0)])
