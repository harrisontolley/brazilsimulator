extends RefCounted
## Scripted checks for the street's life: where people can walk, how they take fright, the
## dogs, the heavier weapons, and whether the words on screen fit. Run as --test=<name>.

const Nav := preload("res://scenes/world/nav.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")

## What _cast_of(4242) came to before the wheel was built.
const CAST := [281228236, 438102235, 2323301200]


static func out_dir() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			return a.trim_prefix("--out=")
	return ""


## Runs the test called `what`. False if there is no such test here.
static func run(g: Node, what: String) -> bool:
	match what:
		"nav":
			await _nav(g)
		"poses":
			await _poses(g)
		"panic":
			await _panic(g)
		"dogs":
			await _dogs(g)
		"hudfit":
			await _hudfit(g)
		"perf":
			await _perf(g)
		"swim":
			await _swim(g)
		"swimlook":
			await _swimlook(g)
		"jetski":
			await _jetski(g)
		"yacht":
			await _yacht(g)
		"seacops":
			await _seacops(g)
		"cast":
			await _cast(g)
		"roleta":
			await _roleta(g)
		"roletanet":
			await _roleta_net(g)
		"arsenal", "shotgun", "sniper", "rocket", "grenade", "molotov":
			await _arsenal(g, what)
		_:
			return false
	return true


## The longest stretch of the walk from a to b that is inside something solid, in metres.
## Clipping the corner of a lamp post is nothing; going through a wall is not.
static func _through(a: Vector3, b: Vector3) -> float:
	var n := int(ceilf(a.distance_to(b) / 0.1))
	var worst := 0
	var run := 0
	for k in range(1, n + 1):
		run = run + 1 if Nav.blocked(a.lerp(b, float(k) / n)) else 0
		worst = maxi(worst, run)
	return worst * 0.1


## Properly inside something, not just brushing the corner of it.
static func _inside(p: Vector3) -> bool:
	return Nav.blocked(p) and Nav.blocked(p + Vector3(0.2, 0, 0)) and Nav.blocked(p - Vector3(0.2, 0, 0)) and Nav.blocked(p + Vector3(0, 0, 0.2)) and Nav.blocked(p - Vector3(0, 0, 0.2))


static func _nav(g: Node) -> void:
	var t0 := Time.get_ticks_msec()
	var img: Image = Nav.image() if out_dir() != "" else null
	# Every door has to be somewhere a person can walk through.
	var shut := 0
	var first := ""
	for room in Places.rooms:
		# Nobody walks into the prison: its door is only where the vans pull up.
		if room.kind == "presidio":
			continue
		for d in room.doors:
			if Nav.blocked(d[0]) or Nav.blocked(d[1]) or not Nav.clear(d[0], d[1]):
				shut += 1
				if first == "":
					first = "door of %s shut at %s" % [room.name, d[0]]
	# And a walk from the sand to the back street has to go round the buildings, not through.
	var a := Vector3(-80, 0, 20)
	var b := Vector3(-80, 0, 104)
	var route: PackedVector3Array = Nav.path(a, b)
	var route_ok := not route.is_empty() and route[route.size() - 1].distance_to(b) < 1.5 and Nav.length(a, route) > 100.0
	var at := a
	for p in route:
		route_ok = route_ok and Nav.clear(at, p)
		if img != null:
			img.set_pixelv(Nav.pixel(p), Color(1, 0, 0))
		at = p
	var path_ms := Time.get_ticks_msec()
	for k in 20:
		Nav.path(Vector3(-250 + k * 25, 0, 45), Vector3(-250 + k * 25 + 30, 0, 105))
	path_ms = Time.get_ticks_msec() - path_ms
	# Nobody's beat takes them through anything.
	var crowd = g.crowd
	var lanes_bad := 0
	for i in crowd._walkers:
		var half: Vector3 = crowd._w_dir[i] * crowd._w_len[i] * 0.5
		if not Nav.clear(crowd._home[i] - half, crowd._home[i] + half) or Nav.blocked(crowd._home[i] - half):
			lanes_bad += 1
			if first == "":
				first = "walker %d lane from %s" % [i, crowd._home[i] - half]
	# Nor does anybody's round of the shops.
	var rounds_bad := 0
	for r in crowd._rounds:
		for j in range(1, r.pts.size()):
			if _through(r.pts[j - 1], r.pts[j]) > 0.3:
				rounds_bad += 1
				if first == "":
					first = "round goes through something %s -> %s" % [r.pts[j - 1], r.pts[j]]
	var indoors := 0
	for r in crowd._rounds:
		for p in r.pts:
			if Places.room_at(p) >= 0:
				indoors += 1
				break
	var stuck := 0
	for i in crowd.count:
		if crowd._walker[i] == 0 and crowd._grp[i] < 0 and Nav.blocked(crowd.pos[i]):
			stuck += 1
			if first == "":
				first = "npc %d stands in something at %s" % [i, crowd.pos[i]]
	# Frighten a few hundred people, indoors and out: every leg of every run has to be open.
	var fled := 0
	var cowered := 0
	var flee_bad := 0
	var flee_ms := Time.get_ticks_msec()
	for i in range(0, crowd.count, 7):
		if crowd.state[i] != crowd.AMBIENT:
			continue
		crowd._srv_flee(i, crowd.pos[i] + Vector3(2.0, 0, 1.0))
		if crowd.state[i] != crowd.FLEE:
			cowered += 1
			continue
		fled += 1
		var pts: PackedVector3Array = crowd._ov[i][0]
		# Somebody sitting at a table has to get up from it first.
		for j in range(2 if Nav.blocked(pts[0]) else 1, pts.size()):
			if _through(pts[j - 1], pts[j]) > 0.3:
				flee_bad += 1
				if first == "":
					first = "npc %d flees through something %s -> %s" % [i, pts[j - 1], pts[j]]
				if img != null:
					img.set_pixelv(Nav.pixel(pts[j - 1]), Color(1, 0, 1))
	flee_ms = Time.get_ticks_msec() - flee_ms
	# Somebody angry on the promenade, and the player the far side of a block: he has to
	# come round by the street, and so do the police.
	var pl = g.local_player
	pl.global_position = Vector3(-52, 0.2, 103)
	var angry := -1
	for i in crowd.count:
		if crowd.state[i] == crowd.AMBIENT and crowd.pos[i].distance_to(Vector3(-52, 0, 48)) < 12.0:
			angry = i
			break
	crowd._hostile[angry] = {"target": 1, "cd": 99.0, "until": 60.0, "shooter": false}
	crowd._srv_set(angry, crowd.HOSTILE)
	var chase_bad := 0
	var cop_bad := 0
	var start: float = crowd.pos[angry].distance_to(pl.global_position)
	var frames := 0
	for k in 5:
		await g.get_tree().process_frame
	var chase_ms := Time.get_ticks_msec()
	while frames < 2400 and crowd.pos[angry].distance_to(pl.global_position) > 3.0:
		await g.get_tree().process_frame
		frames += 1
		pl.st.hp = 100.0
		if crowd.state[angry] != crowd.HOSTILE:
			break
		if Nav.blocked(crowd.pos[angry]):
			chase_bad += 1
		for c in g.police.cops:
			if Nav.blocked(c.pos):
				cop_bad += 1
				if first == "":
					first = "cop in something at %s" % c.pos
	chase_ms = Time.get_ticks_msec() - chase_ms
	var closed: float = crowd.pos[angry].distance_to(pl.global_position)
	# The same again with the clock run on, through the code that really moves them.
	var keep: float = MatchState.time
	var walked_bad := 0
	for k in 40:
		MatchState.time = 7.0 + k * 21.3
		crowd._process(0.016)
		for i in crowd._walkers:
			if crowd.state[i] == crowd.AMBIENT and crowd._walker[i] == 1 and _inside(crowd.pos[i]):
				walked_bad += 1
		for i in crowd._errands:
			if crowd.state[i] == crowd.AMBIENT and crowd._walker[i] == 1 and _inside(crowd.pos[i]):
				walked_bad += 1
	MatchState.time = keep
	crowd._process(0.016)
	if img != null:
		img.save_png(out_dir() + "/nav.png")
	var ok: bool = shut == 0 and route_ok and rounds_bad == 0 and crowd._errands.size() > 100 and indoors > 1 and lanes_bad == 0 and stuck == 0 and walked_bad == 0 and flee_bad == 0 and fled > 100 and chase_bad == 0 and cop_bad == 0 and closed < 4.0
	g.debug_result("nav", ok, "doors shut %d route %.0f m ok %s, 20 paths %d ms, rounds %d (%d go indoors, %d legs bad) walked by %d, walkers %d lanes bad %d walked bad %d, standing in things %d, fled %d cowered %d bad legs %d in %d ms, chase %.0f -> %.1f m in %d frames (%d ms) inside things %d, cops inside things %d %s" % [shut, Nav.length(a, route), route_ok, path_ms, crowd._rounds.size(), indoors, rounds_bad, crowd._errands.size(), crowd._walkers.size(), lanes_bad, walked_bad, stuck, fled, cowered, flee_bad, flee_ms, start, closed, frames, chase_ms, chase_bad, cop_bad, first])


static func _camera(g: Node, at: Vector3, look: Vector3, fov := 40.0) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 3000.0
	g.add_child(cam)
	cam.look_at_from_position(at, look)
	cam.current = true
	g.hud.visible = false
	return cam


static func _snap(g: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	if out_dir() != "":
		g.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir(), name])


## Every new pose in a row, photographed twice a moment apart.
static func _poses(g: Node) -> void:
	var crowd = g.crowd
	var poses := [Kit.WAVE, Kit.POINT, Kit.ARGUE, Kit.SHRUG, Kit.LAUGH, Kit.STRETCH, Kit.PUSHUP, Kit.SMOKE, Kit.YAWN,
			Kit.LOOK, Kit.TIE, Kit.HUG, Kit.BEG, Kit.STAGGER, Kit.TEXT_WALK, Kit.LIMP, Kit.CRAWL, Kit.SCREAM,
			Kit.PANIC, Kit.SWEEP, Kit.PHOTO, Kit.FILM, Kit.AIM_LONG, Kit.AIM_SHOULDER, Kit.PREACH, Kit.STAND, Kit.WALK]
	var keep: Array = []
	for k in poses.size():
		keep.append(k)
	crowd.debug_only(keep)
	g.local_player.global_position = Vector3(0, 0.2, 30)
	var base := Vector3(150, 0, -10)
	for k in poses.size():
		crowd.debug_pose(k, base + Vector3((k % 9 - 4) * 1.5, 0, -(k / 9) * 30.0), PI * 0.82, poses[k], true)
	for row in 3:
		var mid := base + Vector3(0, 0, -row * 30.0)
		var cam := _camera(g, mid + Vector3(3.5, 2.0, 11.5), mid + Vector3(0, 0.9, 0), 38.0)
		for shot in 2:
			await g.get_tree().create_timer(0.55).timeout
			await _snap(g, "poses_%d_%d" % [row, shot])
		cam.queue_free()
	g.debug_result("poses", true, "%d poses" % poses.size())


## Punch somebody in a busy street: the people round about should see it and deal with it,
## nobody should run through a wall doing so, and nobody should be spirited away.
static func _panic(g: Node) -> void:
	var crowd = g.crowd
	var pl = g.local_player
	# The busiest stretch of promenade there is.
	var victim := -1
	var most := 0
	for i in range(0, crowd.count, 3):
		if crowd.state[i] != crowd.AMBIENT or crowd.pos[i].z < 41.0 or crowd.pos[i].z > 50.0 or crowd._lying[i] == 1 or crowd._walker[i] == 1:
			continue
		var n: int = crowd.count_near(crowd.pos[i], 12.0)
		if n > most:
			most = n
			victim = i
	var at: Vector3 = crowd.pos[victim]
	var near: Array = []
	var alive_before: int = 0
	for i in crowd.count:
		if crowd.state[i] < crowd.DEAD:
			alive_before += 1
		if i != victim and crowd.state[i] == crowd.AMBIENT and crowd.pos[i].distance_to(at) < 12.0:
			near.append(i)
	var where := {}
	for i in near:
		where[i] = crowd.pos[i]
	pl.global_position = at + Vector3(0, 0.2, -1.2)
	pl.rotation.y = PI
	crowd.hp[victim] = 500.0
	var cam: Camera3D = null
	if out_dir() != "":
		cam = _camera(g, at + Vector3(7, 9, -13), at + Vector3(0, 0.5, 2), 55.0)
		await g.get_tree().create_timer(0.4).timeout
		await _snap(g, "panic_0")
	g._last_attack.clear()
	g.srv_attack(at + Vector3(0, 1.5 * crowd._scale[victim], -1.2), Vector3(0, 0, 1))
	var shots := [0.9, 2.2, 4.5]
	var reacted := 0
	var t := 0.0
	var inside := 0
	var stuck := {}
	for k in shots.size():
		while t < shots[k]:
			await g.get_tree().process_frame
			t += g.get_process_delta_time()
			for i in near:
				# Whoever was sitting at a table has to get up from it first.
				if crowd.state[i] == crowd.FLEE and crowd._ov[i][5] and Nav.blocked(crowd.pos[i]) and not Nav.blocked(where[i]) and not stuck.has(i):
					stuck[i] = crowd.pos[i]
					inside += 1
		if cam != null:
			await _snap(g, "panic_%d" % (k + 1))
	var ran := 0
	var stared := 0
	var far := 0
	for i in near:
		if crowd.state[i] == crowd.FLEE or crowd.state[i] == crowd.COWER or crowd.pos[i].distance_to(where[i]) > 3.0:
			ran += 1
			if crowd.pos[i].distance_to(at) > 14.0:
				far += 1
		elif crowd.state[i] == crowd.HOSTILE or [Kit.FILM, Kit.POINT, Kit.LOOK].has(int(crowd._idle[i])):
			stared += 1
	var alive_after := 0
	for i in crowd.count:
		if crowd.state[i] < crowd.DEAD:
			alive_after += 1
	var ok: bool = near.size() >= 8 and ran + stared >= near.size() * 0.6 and ran >= near.size() * 0.4 and far >= ran * 0.5 and inside == 0 and alive_after == alive_before and crowd._scream_ms > 0
	g.debug_result("panic", ok, "bystanders %d ran %d (got clear %d) stared %d, inside things %d, vanished %d, screamed %s " % [near.size(), ran, far, stared, inside, alive_before - alive_after, crowd._scream_ms > 0] + str(stuck))


## Somewhere on the sand with nothing within r of it.
static func _clearing(r: float) -> Vector3:
	for x in range(-200, 200, 7):
		for z in range(-22, 24, 5):
			var c := Vector3(x, 0, z)
			var ok := not Layout.on_play_area(c, r)
			for a in 16:
				for d in [r, r * 0.6, r * 0.3]:
					ok = ok and not Nav.blocked(c + Vector3(cos(a * TAU / 16.0), 0, sin(a * TAU / 16.0)) * d)
			if ok:
				return c
	return Vector3(0, 0, 0)


## One of every breed for the camera, every trick they know, and then the three kinds of
## dog there are to meet: one that goes for you, one that runs, one that can be killed.
static func _dogs(g: Node) -> void:
	var dogs = g.dogs
	var D = dogs
	var pl = g.local_player
	var base := _clearing(11.0)
	var breeds := {}
	for i in dogs.dogs.size():
		if not breeds.has(dogs.dogs[i].breed):
			breeds[dogs.dogs[i].breed] = i
	if out_dir() != "":
		g.crowd.debug_only([])
		pl.global_position = base + Vector3(0, 0.2, 40)
		var used := {}
		for b in breeds:
			used[breeds[b]] = true
			dogs.debug_pose(breeds[b], base + Vector3((b - 3.5) * 1.5, 0, 0), PI * 0.6, D.STAND)
		var anims := [D.TROT, D.RUN, D.SIT, D.LIE, D.SNIFF, D.BARK, D.GROWL, D.DIG, D.SCRATCH, D.PEE, D.BEG, D.COWER, D.DEAD, D.WAG]
		var k := 0
		for i in dogs.dogs.size():
			if used.has(i) or k >= anims.size():
				continue
			dogs.debug_pose(i, base + Vector3((k % 7 - 3) * 1.7, 0, -3.0 - (k / 7) * 2.6), PI * 0.6, anims[k], 2.0 if anims[k] == D.TROT else (6.0 if anims[k] == D.RUN else 0.0))
			used[i] = true
			k += 1
		for i in dogs.dogs.size():
			if not used.has(i):
				dogs.debug_pose(i, Vector3(250, 0, -30), 0.0, D.SIT)
		var cam := _camera(g, base + Vector3(0.5, 2.6, 6.5), base + Vector3(0, 0.3, -3.2), 50.0)
		for shot in 2:
			await g.get_tree().create_timer(0.45).timeout
			await _snap(g, "dogs_%d" % shot)
		cam.queue_free()
		cam = _camera(g, base + Vector3(0.0, 1.3, 5.5), base + Vector3(0, 0.35, 0), 60.0)
		await g.get_tree().create_timer(0.3).timeout
		await _snap(g, "dogs_breeds")
		cam.queue_free()
		g.debug_result("dogs", breeds.size() == 8, "pictures of %d breeds" % breeds.size())
		return
	# Everybody else out of the way.
	for i in dogs.dogs.size():
		dogs.debug_pose(i, Vector3(-250 + i * 3, 0, -30), 0.0, D.SIT)
	g.crowd.debug_only([])
	var inside := 0
	# One that goes for you.
	pl.global_position = base + Vector3(0, 0.2, 0)
	pl.st.hp = 100.0
	var mean: int = dogs.debug_dog(D.PITBULL, D.AGGRESSIVE, base + Vector3(6.5, 0, 0))
	var warned := false
	var t := 0.0
	while t < 9.0 and pl.st.hp >= 100.0:
		await g.get_tree().process_frame
		t += g.get_process_delta_time()
		warned = warned or dogs.dogs[mean].state == D.WARN
		if Nav.blocked(dogs.dogs[mean].pos):
			inside += 1
	var bitten: bool = pl.st.hp < 100.0
	var bite_t := t
	# A bullet settles it.
	var pick: Array = dogs.ray_pick(pl.global_position + Vector3(0, 1.2, 0), (dogs.dogs[mean].pos + Vector3(0, 0.4, 0) - pl.global_position - Vector3(0, 1.2, 0)).normalized(), 30.0, 0.0)
	var killed: bool = dogs.srv_damage(mean, 9999.0, 1)
	await g.get_tree().create_timer(0.3).timeout
	var dead: bool = killed and not dogs.alive(mean) and (dogs._state[mean] & 15) == D.DEAD
	# One that wants nothing to do with you.
	pl.st.hp = 100.0
	pl.global_position = base + Vector3(-40, 0.2, 0)
	var shy: int = dogs.debug_dog(D.CARAMELO, D.SKITTISH, base + Vector3(-37.0, 0, 0))
	t = 0.0
	while t < 4.0:
		await g.get_tree().process_frame
		t += g.get_process_delta_time()
		if Nav.blocked(dogs.dogs[shy].pos):
			inside += 1
	var fled: float = dogs.dogs[shy].pos.distance_to(pl.global_position)
	# And one that thinks you are wonderful.
	pl.global_position = base + Vector3(-80, 0.2, 10)
	var pal: int = dogs.debug_dog(D.LABRADOR, D.FRIENDLY, base + Vector3(-76.0, 0, 10))
	t = 0.0
	var followed := false
	while t < 6.0 and not followed:
		await g.get_tree().process_frame
		t += g.get_process_delta_time()
		followed = dogs.dogs[pal].state == D.FOLLOW
	var ok: bool = breeds.size() == 8 and warned and bitten and pick[0] == mean and dead and fled > 10.0 and followed and inside == 0 and pl.st.hp >= 100.0
	g.debug_result("dogs", ok, "breeds %d dogs %d, warned %s bitten %s after %.1f s, ray found it %s, died %s, shy one %.1f m off, friend follows %s, inside things %d" % [breeds.size(), dogs.dogs.size(), warned, bitten, bite_t, pick[0] == mean, dead, fled, followed, inside])


## Puts `item` in the local player's hands, loaded, with plenty to spare.
static func _arm(g: Node, item: String) -> void:
	var st: Dictionary = g.local_player.st
	g._give(st, item, 3 if DB.kind_of(item) == "thrown" else 1)
	if DB.is_gun(item):
		st.mag[item] = DB.ITEMS[item].mag
		g._give(st, DB.feed_of(item), 20)
	st.equipped = item
	g._last_attack.clear()
	g._reload.clear()


## Stands crowd member i at `at` with `hp` to lose.
static func _dummy(g: Node, i: int, at: Vector3, hp := 100.0) -> void:
	g.crowd.debug_pose(i, at, 0.0, Kit.STAND)
	g.crowd.hp[i] = hp


## Everybody back to the far end of the beach with no hard feelings, and the player mended.
static func _reset(g: Node) -> void:
	g.crowd._hostile.clear()
	g.crowd._active.clear()
	g.crowd._ov.clear()
	g.crowd._calm.clear()
	g.crowd._waves.clear()
	for k in 40:
		_dummy(g, k, Vector3(-280 + k * 2, 0, -34))
	g.local_player.st.hp = 100.0
	g.local_player.st.ko = 0.0


## The heavier end of the armoury, one piece at a time. `only` runs just that part.
static func _arsenal(g: Node, only: String) -> void:
	var crowd = g.crowd
	var pl = g.local_player
	var keep: Array = []
	for k in 40:
		keep.append(k)
	crowd.debug_only(keep)
	for i in g.dogs.dogs.size():
		g.dogs.debug_pose(i, Vector3(-250 + i * 3, 0, -30), 0.0, g.dogs.SIT)
	for k in 40:
		_dummy(g, k, Vector3(-280 + k * 2, 0, -34))
	var base := _clearing(11.0)
	var eye := Vector3(0, 1.25, 0)
	var out: Array = []
	var ok := true
	pl.global_position = base + Vector3(0, 0.05, 0)
	pl.st.hp = 100.0
	await g.get_tree().create_timer(0.3).timeout

	if only == "arsenal" or only == "shotgun":
		# Close up it takes a man apart; down the beach it stings.
		_dummy(g, 0, base + Vector3(0, 0, -4), 1000.0)
		_dummy(g, 1, base + Vector3(8, 0, -30), 1000.0)
		_arm(g, "shotgun")
		g.srv_attack(base + eye, (crowd.pos[0] + Vector3(0, 1.0, 0) - base - eye).normalized())
		var near: float = 1000.0 - crowd.hp[0]
		g._last_attack.clear()
		g.srv_attack(base + eye, (crowd.pos[1] + Vector3(0, 1.0, 0) - base - eye).normalized())
		var far: float = 1000.0 - crowd.hp[1]
		var good: bool = near > 60.0 and far < near * 0.5 and pl.st.mag.shotgun == 3
		ok = ok and good
		out.append("shotgun %s: %.0f at 4 m, %.0f at 31 m" % [good, near, far])

	if only == "arsenal" or only == "sniper":
		_reset(g)
		# Through the first man and into the one behind him, from the far end of the beach.
		# Along the sand, wherever there is that much of it with nothing standing on it.
		var from := base
		var along := Vector3(1, 0, 0)
		for dz in [0.0, 6.0, -6.0, 12.0, -12.0, 18.0, -18.0, 24.0]:
			for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var a: Vector3 = base + Vector3(0, 1.0, dz)
				if g._clear(a, a + dir * 156.0) and g._clear(a + Vector3(0, -0.6, 0), a + dir * 156.0 + Vector3(0, -0.6, 0)) and from == base:
					from = base + Vector3(0, 0, dz) + Vector3(0.001, 0, 0)
					along = dir
		pl.global_position = from + Vector3(0, 0.05, 0)
		_dummy(g, 2, from + along * 150.0)
		_dummy(g, 3, from + along * 153.0)
		_arm(g, "sniper")
		Input.action_press("aim")
		await g.get_tree().create_timer(0.4).timeout
		var scoped: bool = pl.scoped and pl.is_aiming() and pl.rig.fov_target < 15.0
		g.srv_attack(from + eye, (crowd.pos[2] + Vector3(0, 1.0, 0) - from - eye).normalized())
		Input.action_release("aim")
		pl.global_position = base + Vector3(0, 0.05, 0)
		var good: bool = scoped and crowd.state[2] == crowd.DEAD and crowd.state[3] == crowd.DEAD
		ok = ok and good
		out.append("sniper %s: scoped %s, first %s, one behind %s" % [good, scoped, crowd.state[2] == crowd.DEAD, crowd.state[3] == crowd.DEAD])
		await g.get_tree().create_timer(0.2).timeout

	if only == "arsenal" or only == "rocket":
		_reset(g)
		# It takes its time getting there, kills what it lands among, and a wall is cover.
		_dummy(g, 4, base + Vector3(0, 0, -30))
		_dummy(g, 5, base + Vector3(2.5, 0, -31))
		_dummy(g, 6, base + Vector3(-22, 0, -30))
		_arm(g, "rpg")
		pl.st.hp = 100.0
		g.srv_attack(base + eye, (crowd.pos[4] + Vector3(0, 0.3, 0) - base - eye).normalized())
		var flew: bool = g.shots.flying.size() == 1 and crowd.state[4] != crowd.DEAD
		var t := 0.0
		while t < 3.0 and not g.shots.flying.is_empty():
			await g.get_tree().process_frame
			t += g.get_process_delta_time()
		var wall := AABB()
		for box in DB.solids:
			if box.size.y > 3.0 and minf(box.size.x, box.size.z) < 1.0 and maxf(box.size.x, box.size.z) > 6.0:
				wall = box
				break
		var n := Vector3(1, 0, 0) if wall.size.x < wall.size.z else Vector3(0, 0, 1)
		var mid := wall.get_center()
		mid.y = 0.0
		_dummy(g, 7, mid + n * 3.5)
		_dummy(g, 8, mid - n * 1.6)
		g.srv_explode(mid + n * 2.2 + Vector3(0, 0.3, 0), 7.5, 230.0, 1)
		var good: bool = flew and t > 0.3 and t < 2.0 and crowd.state[4] == crowd.DEAD and crowd.state[5] == crowd.DEAD and crowd.state[6] != crowd.DEAD and pl.st.hp >= 100.0 and wall.size.y > 0.0 and crowd.state[7] == crowd.DEAD and crowd.state[8] != crowd.DEAD
		ok = ok and good
		out.append("rocket %s: flew %.2f s, target %s, beside it %s, 22 m off spared %s, shooter spared %s, open side of wall %s, behind wall spared %s" % [good, t, crowd.state[4] == crowd.DEAD, crowd.state[5] == crowd.DEAD, crowd.state[6] != crowd.DEAD, pl.st.hp >= 100.0, crowd.state[7] == crowd.DEAD, crowd.state[8] != crowd.DEAD])

	if only == "arsenal" or only == "grenade":
		_reset(g)
		# Thrown, it lands, bounces, rolls and then goes off, among whoever is standing there.
		for k in 8:
			_dummy(g, 10 + k, base + Vector3(-4.0 + (k % 2) * 8.0, 0, -9.0 - (k / 2) * 4.0))
		for k in 5:
			_dummy(g, 20 + k, base + Vector3(0, 0, -10.0 - k * 3.0))
		_arm(g, "grenade")
		pl.st.hp = 100.0
		var had: int = pl.st.inv.grenade
		g.srv_attack(base + eye, Vector3(0, 0.25, -1).normalized(), 0.45)
		var id: int = g.shots.flying.keys()[0] if not g.shots.flying.is_empty() else -1
		var bounces := 0
		var was_vy := 0.0
		var t := 0.0
		var last := base
		while t < 5.0 and g.shots.flying.has(id):
			var s: Dictionary = g.shots.flying[id]
			if was_vy < -1.0 and s.vel.y > 0.3:
				bounces += 1
			was_vy = s.vel.y
			last = s.pos
			await g.get_tree().process_frame
			t += g.get_process_delta_time()
		var dead := 0
		for k in range(10, 25):
			if crowd.state[k] == crowd.DEAD:
				dead += 1
		var good: bool = id >= 0 and bounces >= 1 and absf(t - 2.6) < 0.4 and last.distance_to(base) > 6.0 and dead >= 1 and pl.st.inv.get("grenade", 0) == had - 1
		ok = ok and good
		out.append("grenade %s: %d bounces, went off at %.2f s %.0f m away, killed %d, %d left in the pocket" % [good, bounces, t, last.distance_to(base), dead, pl.st.inv.get("grenade", 0)])

	if only == "arsenal" or only == "molotov":
		_reset(g)
		# It breaks where it lands and whoever is standing there burns and runs.
		var side := base + Vector3(9, 0, 0)
		_dummy(g, 30, side + Vector3(0, 0, -8), 400.0)
		_arm(g, "molotov")
		pl.global_position = side + Vector3(0, 0.05, 0)
		await g.get_tree().create_timer(0.2).timeout
		g.srv_attack(side + eye, Vector3(0, 0.33, -1).normalized(), 0.0)
		var t := 0.0
		while t < 3.0 and g.shots.fires.is_empty():
			await g.get_tree().process_frame
			t += g.get_process_delta_time()
		var lit: bool = not g.shots.fires.is_empty()
		var where: Vector3 = g.shots.fires[0][0] if lit else Vector3.ZERO
		await g.get_tree().create_timer(1.6).timeout
		var burnt: float = 400.0 - crowd.hp[30]
		var good: bool = lit and where.distance_to(crowd.pos[30]) < 9.0 and burnt > 10.0 and crowd.state[30] != crowd.AMBIENT
		ok = ok and good
		out.append("molotov %s: lit %s %.1f m from him, burnt %.0f, he is %s" % [good, lit, where.distance_to(crowd.pos[30]) if lit else -1.0, burnt, "running" if crowd.state[30] == crowd.FLEE else str(crowd.state[30])])
		if out_dir() != "":
			var cam := _camera(g, side + Vector3(6, 3.0, 2), where + Vector3(0, 0.5, 0), 55.0)
			await _snap(g, "molotov")
			cam.queue_free()

	if out_dir() != "":
		# One for the album: a rocket into a crowd, seen from the side.
		var spot := base + Vector3(-12, 0, 0)
		for k in 8:
			_dummy(g, 32 + k, spot + Vector3(cos(k * 0.8) * 2.2, 0, -14 + sin(k * 0.8) * 2.2), 60.0)
		var cam := _camera(g, spot + Vector3(11, 3.5, -8), spot + Vector3(0, 1.0, -14), 55.0)
		g.hud.visible = false
		g.srv_explode(spot + Vector3(0, 0.3, -14), 7.5, 230.0, 1)
		for k in 3:
			await g.get_tree().create_timer([0.06, 0.3, 1.2][k]).timeout
			await _snap(g, "boom_%d" % k)
		cam.queue_free()
	g.debug_result(only, ok, "; ".join(out))


## Every control under `c` that is showing and has something in it, as [path, rect].
static func _showing(c: Control, out: Array) -> void:
	if not c.is_visible_in_tree():
		return
	if (c is Label and c.text != "") or c is PanelContainer or c is ProgressBar or c is TextureRect:
		out.append([str(c.get_path()).get_file() + ":" + (c.text.left(24) if c is Label else c.get_class()), c.get_global_rect()])
	for child in c.get_children():
		if child is Control:
			_showing(child, out)


## Fill every line on the HUD with the longest thing it will ever have to say, at three
## window sizes, and check that all of it is on the screen and none of it is on top of the
## plates at the foot of it.
static func _hudfit(g: Node) -> void:
	var hud = g.hud
	var pl = g.local_player
	var st: Dictionary = pl.st
	st.money = 1234567
	st.heat = 3
	st.vis = 1
	st.hp = 64.0
	for item in DB.LOOT:
		st.inv[item] = 12
	st.bet = {"amount": 500, "animal": 3}
	for d in ["cocaine", "meth", "bala"]:
		st.drugs[d] = {"phase": "high", "t": 99.0}
		st.inv[d] = 3
	_arm(g, "rpg")
	g._give(st, "grenade", 3)
	pl.pname = "WWWWWWWWWWWWWWWW"
	var worst := ""
	var bad := 0
	var checked := 0
	var sizes := [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 600)]
	for k in sizes.size():
		g.get_window().size = sizes[k]
		g.get_window().content_scale_size = Vector2i.ZERO
		await g.get_tree().process_frame
		await g.get_tree().process_frame
		for stage in 3:
			st.jail = 300.0 if stage == 1 else 0.0
			MatchState.ended = stage == 2
			hud._winner = pl.pname
			hud.banner("ARRASTÃO! A gang of thirty is sweeping the sand from Posto 4 toward the Arpoador taking everything")
			for n in 4:
				hud.toast("%d: %s paid the gate guard R$1500 and walked out of the Presídio the front way, bold as brass" % [n, pl.pname])
			hud.feed("Killed WWWWWWWWWWWWWWWW  (head)")
			hud.feed("Knocked out a traficante")
			hud.set_prompt("F: hold up the till at BAR DO PORTUGUÊS (needs a gun, and somebody will call it in)", 0.5)
			hud.set_rob_meter(0.5)
			Input.action_press("scores") if stage == 0 else Input.action_release("scores")
			for f in 4:
				await g.get_tree().process_frame
			var all: Array = []
			_showing(hud._root, all)
			var view: Rect2 = hud._root.get_viewport_rect().grow(1.0)
			var plates: Array = []
			var middle: Array = []
			for e in all:
				checked += 1
				if not view.encloses(e[1]):
					bad += 1
					if worst == "":
						worst = "%s at %s is off a %s screen" % [e[0], e[1], sizes[k]]
			# The column at the foot of the screen must clear the two plates beside it.
			var mid_rect: Rect2 = hud._mid.get_global_rect()
			for side in [hud._hp.get_global_rect(), hud._reload.get_global_rect()]:
				if mid_rect.intersects(side):
					bad += 1
					if worst == "":
						worst = "middle column %s on top of a plate %s at %s" % [mid_rect, side, sizes[k]]
			# And the column at the top must clear the corners, and its parts each other.
			var top: Rect2 = hud._top.get_global_rect()
			for side in [hud._loot.get_global_rect(), hud._money.get_global_rect(), hud._heat.get_global_rect(), hud._feed.get_global_rect()]:
				if top.intersects(side):
					bad += 1
					if worst == "":
						worst = "top column %s on top of a corner %s at %s" % [top, side, sizes[k]]
			if hud._banner.get_global_rect().intersects(hud._toasts.get_global_rect()) or top.intersects(hud._big.get_global_rect()):
				bad += 1
				if worst == "":
					worst = "top column %s runs into the headline %s at %s" % [top, hud._big.get_global_rect(), sizes[k]]
			if out_dir() != "" and k < 2:
				await _snap(g, "hud_%d_%d" % [sizes[k].x, stage])
	Input.action_release("scores")
	MatchState.ended = false
	st.jail = 0.0
	g.debug_result("hudfit", bad == 0 and checked > 100, "%d things checked at %d sizes, %d off screen or overlapping %s" % [checked, sizes.size(), bad, worst])


## Average milliseconds a frame over `n` frames.
static func _frame_ms(g: Node, n: int) -> float:
	for k in 10:
		await g.get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for k in n:
		await g.get_tree().process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


## What each part of the street costs a frame, found by switching it off and looking again.
static func _perf(g: Node) -> void:
	g.local_player.global_position = Vector3(-30, 0.2, 44)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await g.get_tree().create_timer(2.0).timeout
	var out: Array = []
	var all: float = await _frame_ms(g, 150)
	out.append("everything %.2f" % all)
	for part in ["hud", "dogs", "crowd", "fx", "shots", "police", "traffic", "ambient", "events", "motos", "balls"]:
		var node: Node = g.get(part)
		node.set_process(false)
		var ms: float = await _frame_ms(g, 100)
		node.set_process(true)
		out.append("%s %.2f" % [part, all - ms])
	g.local_player.set_process(false)
	g.local_player.set_physics_process(false)
	var ms: float = await _frame_ms(g, 100)
	out.append("player %.2f" % [all - ms])
	g.debug_result("perf", true, "ms a frame: " + ", ".join(out))


static func _wait(g: Node, seconds: float) -> void:
	await g.get_tree().create_timer(seconds).timeout


static func _keys_up() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "dive", "attack"]:
		Input.action_release(a)


## Waits until `check` says so, or for `limit` seconds. How long it took, or -1.
static func _until(g: Node, limit: float, check: Callable) -> float:
	var t := 0.0
	while t < limit:
		if check.call():
			return t
		await g.get_tree().process_frame
		t += g.get_process_delta_time()
	return -1.0


## Into the sea and back: wading, floating, ducking under, running out of breath, coming up,
## going in off a height, and walking out up the beach.
static func _swim(g: Node) -> void:
	var p = g.local_player
	var bad: Array = []
	p.global_position = Vector3(0, 0.1, -39)
	p.rotation.y = 0.0
	p.rig.rotation.x = 0.0
	await _wait(g, 0.4)
	Input.action_press("move_forward")
	var waded := await _until(g, 15.0, func(): return p.mv == p.MV_SWIM)
	if waded < 0.0:
		bad.append("never floated, z %.1f y %.2f mv %d" % [p.global_position.z, p.global_position.y, p.mv])
	var in_z: float = p.global_position.z
	await _wait(g, 2.0)
	var sea: float = Layout.wave_y(p.global_position.x, p.global_position.z)
	var ride: float = sea - p.global_position.y
	if absf(ride - p.FLOAT) > 0.3:
		bad.append("floating %.2f under the surface" % ride)
	if p.head_under():
		bad.append("head under while swimming on top")
	if p.can_attack():
		bad.append("can still attack")
	var slow: float = p.hspeed()
	Input.action_press("sprint")
	await _wait(g, 1.5)
	var quick: float = p.hspeed()
	Input.action_release("sprint")
	if quick < slow + 1.0:
		bad.append("crawl no faster: %.1f vs %.1f" % [quick, slow])
	# Under.
	Input.action_press("crouch")
	var ducked := await _until(g, 3.0, func(): return p.head_under())
	await _wait(g, 1.5)
	var down: float = Layout.wave_y(p.global_position.x, p.global_position.z) - p.global_position.y
	if ducked < 0.0 or down < 1.5:
		bad.append("did not dive: %.2f down" % down)
	# Out of breath.
	g._air[p.id] = 0.6
	var hp0: float = p.st.hp
	await _wait(g, 2.5)
	var lost: float = hp0 - p.st.hp
	if lost < DB.DROWN_DMG:
		bad.append("no drowning: lost %.0f" % lost)
	Input.action_release("crouch")
	Input.action_release("move_forward")
	Input.action_press("jump")
	var up := await _until(g, 8.0, func(): return not p.head_under())
	Input.action_release("jump")
	if up < 0.0:
		bad.append("never surfaced")
	await _wait(g, 1.5)
	var hp1: float = p.st.hp
	await _wait(g, 1.5)
	if p.st.hp < hp1:
		bad.append("still drowning on the surface")
	# In from a height: straight under, then back up without touching anything.
	p.global_position = Vector3(40, 7.0, -120)
	p.velocity = Vector3.ZERO
	await _until(g, 1.0, func(): return p.mv != p.MV_SWIM)
	var hit := await _until(g, 4.0, func(): return p.mv == p.MV_SWIM)
	var went_under := await _until(g, 1.0, func(): return p.head_under())
	var back := await _until(g, 8.0, func(): return p.mv == p.MV_SWIM and not p.head_under())
	if hit < 0.0 or went_under < 0.0 or back < 0.0:
		bad.append("drop in: hit %.1f under %.1f back %.1f" % [hit, went_under, back])
	# A running dive off the sand.
	p.global_position = Vector3(-60, 0.1, -37)
	p.rotation.y = 0.0
	await _wait(g, 0.3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _until(g, 6.0, func(): return p.global_position.z < -47.0)
	Input.action_press("dive")
	await _wait(g, 0.1)
	Input.action_release("dive")
	var dived := await _until(g, 3.0, func(): return p.mv == p.MV_SWIM)
	if dived < 0.0:
		bad.append("dive did not end in the water: mv %d z %.1f" % [p.mv, p.global_position.z])
	_keys_up()
	await _wait(g, 2.0)
	# And home.
	p.rotation.y = PI
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var out := await _until(g, 40.0, func(): return p.mv != p.MV_SWIM and p.is_on_floor() and p.global_position.z > Layout.WATER_Z)
	_keys_up()
	if out < 0.0:
		bad.append("never walked out: z %.1f mv %d" % [p.global_position.z, p.mv])
	g.debug_result("swim", bad.is_empty(), "afloat after %.1f s at z %.1f riding %.2f, crawl %.1f vs %.1f m/s, dived %.2f m, drowning took %.0f, dry after %.1f s  %s" % [waded, in_z, ride, quick, slow, down, lost, out, "; ".join(bad)])


## Every way of swimming, photographed from the side: for looking at, not for passing.
static func _swimlook(g: Node) -> void:
	var p = g.local_player
	var cam := _camera(g, Vector3.ZERO, Vector3.FORWARD, 30.0)
	var shoot := func(name: String, high := 0.7):
		var at: Vector3 = p.global_position
		cam.look_at_from_position(at + Vector3(3.6, high, 1.2), at + Vector3(0, 0.35, -0.3))
		await _snap(g, name)
	p.global_position = Vector3(0, -1.0, -100)
	p.rotation.y = 0.0
	p.rig.rotation.x = 0.0
	await _wait(g, 2.0)
	await shoot.call("swim_tread")
	Input.action_press("move_forward")
	for k in 4:
		await _wait(g, 0.9 + 0.31 * k)
		await shoot.call("swim_breast%d" % k)
	Input.action_press("sprint")
	await _wait(g, 1.5)
	for k in 4:
		await _wait(g, 0.23)
		await shoot.call("swim_crawl%d" % k)
	Input.action_release("sprint")
	Input.action_press("crouch")
	await _wait(g, 0.35)
	await shoot.call("swim_duck")
	await _wait(g, 0.8)
	Input.action_release("crouch")
	for k in 4:
		await _wait(g, 0.3)
		await shoot.call("swim_under%d" % k, -0.3)
	Input.action_press("sprint")
	await _wait(g, 1.2)
	await shoot.call("swim_dart", -0.3)
	_keys_up()
	await _wait(g, 1.2)
	await shoot.call("swim_hang", -0.3)
	p.global_position = Vector3(0, 0.1, -42.5)
	await _wait(g, 0.5)
	Input.action_press("move_forward")
	await _wait(g, 0.9)
	await shoot.call("swim_wade")
	_keys_up()
	g.debug_result("swimlook", true)


## A jet ski from the row in the shallows: on, out to sea flat out, back in until it grounds,
## off; then onto another from the water.
static func _jetski(g: Node) -> void:
	var p = g.local_player
	var bad: Array = []
	p.global_position = Vector3(-30, -0.4, -45.8)
	p.rotation.y = 0.0
	await _wait(g, 0.6)
	g.interact()
	var on := await _until(g, 2.0, func(): return p.mv == p.MV_RIDE and g.motos.on_ski(p.id))
	if on < 0.0:
		bad.append("did not get on: mv %d" % p.mv)
	Input.action_press("move_forward")
	await _wait(g, 5.0)
	var fast: float = p.hspeed()
	var out_z: float = p.global_position.z
	var off: float = p.global_position.y - (Layout.wave_y(p.global_position.x, p.global_position.z) - g.motos.DRAFT)
	if fast < 18.0 or out_z > -90.0:
		bad.append("slow: %.1f m/s, got to z %.0f" % [fast, out_z])
	if absf(off) > 0.9:
		bad.append("%.2f m off the water" % off)
	# Round and back up the beach.
	Input.action_press("move_left")
	await _until(g, 6.0, func(): return absf(angle_difference(p.rotation.y, PI)) < 0.25)
	Input.action_release("move_left")
	var beached := await _until(g, 20.0, func(): return p.global_position.z > -46.0 and p.hspeed() < 2.5)
	var at_z: float = p.global_position.z
	if beached < 0.0 or at_z > -30.0:
		bad.append("did not ground: z %.1f at %.1f m/s" % [at_z, p.hspeed()])
	_keys_up()
	g.interact()
	var down := await _until(g, 2.0, func(): return p.mv != p.MV_RIDE and g.motos.bike_of(p.id) < 0)
	if down < 0.0:
		bad.append("did not get off")
	# From the water.
	var spot: Vector3 = g.motos.pos[g.motos.SPOTS.size() + 6]
	p.global_position = Vector3(spot.x + 1.5, -1.0, spot.z)
	await _until(g, 3.0, func(): return p.mv == p.MV_SWIM)
	await _wait(g, 0.5)
	g.interact()
	var swum := await _until(g, 2.0, func(): return p.mv == p.MV_RIDE and g.motos.on_ski(p.id))
	if swum < 0.0:
		bad.append("could not climb on from the water: mv %d" % p.mv)
	g.debug_result("jetski", bad.is_empty(), "on after %.1f s, %.1f m/s out to z %.0f riding %.2f off the surface, grounded at z %.1f, off %.1f, on from the water %.1f  %s" % [on, fast, out_z, off, at_z, down, swum, "; ".join(bad)])


## The yacht: who is aboard, the warning, swimming up the ramp, what the guards do about it,
## what the guests do, a dead guard's gun, and the safe.
static func _yacht(g: Node) -> void:
	var p = g.local_player
	var y = g.yacht
	var crowd = g.crowd
	var bad: Array = []
	await _wait(g, 1.0)
	var girls := 0
	var rich := 0
	for i in y.aboard:
		var id: String = DB.ARCHETYPES[crowd.arch[i]].id
		girls += 1 if id == "socialite" else 0
		rich += 1 if id == "magnata" else 0
	if y.guards.size() != 8 or girls < 18 or rich != 3:
		bad.append("aboard %d: %d guards, %d girls, %d rich" % [y.aboard.size(), y.guards.size(), girls, rich])
	# Swimming in from astern: warned, not shot.
	p.st.hp = 100000.0
	p.global_position = y.at + Vector3(y.X_PLAT - 30.0, -0.9, 0)
	p.rotation.y = -PI / 2.0
	await _wait(g, 1.5)
	var warned: bool = y._warned.has(p.id) and not y._alarm.has(p.id)
	if not warned or p.st.hp < 100000.0:
		bad.append("warning: warned %s alarm %s lost %.0f" % [y._warned.has(p.id), y._alarm.has(p.id), 100000.0 - p.st.hp])
	# Up the ramp and aboard.
	p.global_position = y.at + Vector3(y.X_PLAT - 7.0, -0.9, 0)
	Input.action_press("move_forward")
	var boarded := await _until(g, 10.0, func(): return y.on_board(p.global_position) and p.mv != p.MV_SWIM)
	_keys_up()
	if boarded < 0.0:
		bad.append("could not get aboard: at %s mv %d" % [p.global_position - y.at, p.mv])
	var alarmed := await _until(g, 2.0, func(): return y._alarm.has(p.id))
	var hp0: float = p.st.hp
	await _wait(g, 6.0)
	var shot: float = hp0 - p.st.hp
	var armed := 0
	for i in y.guards:
		armed += 1 if crowd.state[i] == crowd.HOSTILE else 0
	var scared := 0
	for i in y.aboard:
		if not y.guards.has(i) and crowd.state[i] != crowd.AMBIENT:
			scared += 1
	if alarmed < 0.0 or shot < 14.0 or armed < 6 or scared < 12:
		bad.append("alarm %.1f, shot for %.0f, %d guards up, %d guests scared" % [alarmed, shot, armed, scared])
	# Up the stairs to the after deck.
	p.global_position = y.at + Vector3(-20.5, y.LOW_Y + 0.1, 3.3)
	p.rotation.y = -PI / 2.0
	Input.action_press("move_forward")
	var climbed := await _until(g, 6.0, func(): return p.global_position.y > y.MAIN_Y - 0.1 and p.is_on_floor())
	_keys_up()
	if climbed < 0.0:
		bad.append("stairs: stuck at %s" % (p.global_position - y.at))
	# A guard dies and leaves his gun where he fell.
	var before: int = g.drops.size()
	var guard: int = y.guards[2]
	crowd.srv_damage_npc(guard, 9999.0, p.id)
	await _wait(g, 0.4)
	var gun_y := -99.0
	for id in g.drops:
		var d: Dictionary = g.drops[id]
		if d.pos.distance_to(crowd.pos[guard]) < 2.5 and not d.items.is_empty():
			gun_y = d.pos.y
	if g.drops.size() <= before or absf(gun_y - y.MAIN_Y) > 0.4:
		bad.append("guard's gun: %d drops, at y %.2f" % [g.drops.size() - before, gun_y])
	# The safe pays once.
	var m0: int = p.st.money
	y.srv_safe(p, {}, 0)
	y.srv_safe(p, {}, 0)
	var paid: int = p.st.money - m0
	if paid != y.SAFE_TAKE or p.st.heat < 2:
		bad.append("safe paid %d, heat %d" % [paid, p.st.heat])
	g.debug_result("yacht", bad.is_empty(), "%d aboard (%d guards, %d girls, %d rich); warned %s; aboard after %.1f s, alarm %.1f, shot for %.0f in 6 s by %d guards, %d guests scared; stairs %.1f s; gun at y %.2f; safe %d  %s" % [y.aboard.size(), y.guards.size(), girls, rich, warned, boarded, alarmed, shot, armed, scared, climbed, gun_y, paid, "; ".join(bad)])


## Wanted and in the water: the boats come out, shoot, keep the heat up, lose a diver, and
## go home again; and they can be shot off their skis.
static func _seacops(g: Node) -> void:
	var p = g.local_player
	var sp = g.sea_patrol
	var bad: Array = []
	p.st.hp = 100000.0
	p.st.heat = 3
	p.wanted_t = 30.0
	g.push_state(p)
	p.global_position = Vector3(20, -1.0, -120)
	var out := await _until(g, 6.0, func(): return sp.units.any(func(u): return u.state == sp.OUT))
	var n := 0
	for u in sp.units:
		n += 1 if u.state == sp.OUT else 0
	if out < 0.0 or n < 2:
		bad.append("launch: %.1f s, %d out" % [out, n])
	var near := await _until(g, 20.0, func(): return sp.units.any(func(u): return u.state == sp.OUT and u.pos.distance_to(p.global_position) < 28.0))
	var hp0: float = p.st.hp
	await _until(g, 12.0, func(): return p.st.hp < hp0 or p.st.jail > 0.0)
	var shot: float = hp0 - p.st.hp
	if near < 0.0 or (shot <= 0.0 and p.st.jail <= 0.0):
		bad.append("no fire: near %.1f, lost %.0f" % [near, shot])
	var seen: bool = sp.sees(p.id)
	# One of them shot off his ski.
	var k := 0
	for i in sp.units.size():
		if sp.units[i].state == sp.OUT:
			k = i
	var u: Dictionary = sp.units[k]
	var from: Vector3 = u.pos + Vector3(6, 1.0, 0)
	var aim: Vector3 = (u.pos + Vector3(0, 0.6, 0) - from).normalized()
	var pick: Array = sp.ray_pick(from, aim, 20.0, 0.0)
	var killed: bool = sp.srv_damage(k, 999.0, p.id)
	if pick[0] != k or not killed or u.state != sp.DOWN:
		bad.append("shooting one: picked %d of %d, killed %s" % [pick[0], k, killed])
	# Under, and they lose sight.
	p.st.jail = 0.0
	p.st.heat = 3
	p.global_position = Vector3(-60, -1.0, -150)
	await _until(g, 3.0, func(): return p.mv == p.MV_SWIM)
	g._air[p.id] = 9999.0
	Input.action_press("crouch")
	var lost := await _until(g, 6.0, func(): return not sp.sees(p.id) and p.head_under())
	if lost < 0.0:
		bad.append("diving did not lose them")
	_keys_up()
	g.debug_result("seacops", bad.is_empty(), "out after %.1f s (%d of them), alongside after %.1f s, shot for %.0f, seen %s, one killed %s, lost by diving %.1f s  %s" % [out, n, near, shot, seen, killed, lost, "; ".join(bad)])


## What the crowd's casting comes to for `seed_value`: who everybody is, what groups there
## are, and where everybody well away from the wheel spends the day. Only the first
## `Crowd.COUNT` are counted: whoever is added after them has dice of their own.
static func _cast_of(g: Node, seed_value: int) -> Array:
	var c = g.crowd
	c.setup(seed_value)
	var dice: Array = []
	var far: Array = []
	for i in mini(c.count, 2500):
		# (Somebody on a round of the shops keeps time by how long the round is, and one of the
		# rounds has to go the long way past the wheel.)
		dice.append([c.arch[i], c.money[i], c._scale[i], c._look[i], c._gun[i], c._afloat[i], c._grp[i], c._w_phase[i] if c._round[i] < 0 else 0.0, c._leave_t[i], c._round[i], c._mm.get_instance_color(i)])
		if absf(c._origin[i].x - Layout.WHEEL_POS.x) > 60.0:
			far.append([i, c._origin[i], c._walker[i], c._w_len[i], c._lying[i]])
	var groups: Array = []
	for gr in c.acts.groups:
		if gr.kind <= c.acts.PHOTO:
			groups.append([gr.kind, gr.n, gr.first, gr.seed])
	return [hash(dice), hash(groups), hash(far)]


## Nobody who was already in the crowd is anybody else for the wheel having been built, and
## nobody is standing on it.
static func _cast(g: Node) -> void:
	var c = g.crowd
	var got := _cast_of(g, 4242)
	var on_stage := 0
	for i in mini(c.count, 2500):
		if c._walker[i] == 0 and Layout.on_wheel(c._origin[i]):
			on_stage += 1
	# The same again with nobody standing round the wheel at all.
	var keep: Array = Places.stands.duplicate()
	Places.stands.clear()
	var bare := _cast_of(g, 4242)
	Places.stands.append_array(keep)
	c.setup(MatchState.seed_value)
	g.debug_result("cast", got == CAST and bare == CAST and on_stage == 0, "cast %s without the wheel's people %s wanted %s, %d on the stage" % [got, bare, CAST, on_stage])


## How much of mesh m's area faces up, and how many of its triangles are wound against
## their own normals (so would be drawn from the wrong side).
static func _facing(m: Mesh) -> Array:
	var arrays := m.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var up := 0.0
	var all := 0.0
	var inside_out := 0
	for k in range(0, idx.size(), 3):
		var a := v[idx[k]]
		var face := (v[idx[k + 2]] - a).cross(v[idx[k + 1]] - a)
		var area := face.length()
		if area < 1e-9:
			continue
		all += area
		if n[idx[k]].y > 0.9:
			up += area
		if face.dot(n[idx[k]]) < 0.0:
			inside_out += 1
	return [snappedf(up / maxf(all, 0.001), 0.01), inside_out]


## The wheel on the beach: the ball always ends in the pocket that was called and never
## jumps on the way there, the rounds keep time, bets are taken and refused when they should
## be, a win pays what it says, somebody joining late sees the same wheel, there is a crowd
## watching that knows what is going on, and you can get up on the deck.
static func _roleta(g: Node) -> void:
	var w = g.roleta
	var p = g.local_player
	var crowd = g.crowd
	var bad: Array = []
	var seed_value := MatchState.seed_value
	await _wait(g, 0.5)

	# The ball.
	var missed := 0
	var jump := 0.0
	var stride := 0.0
	for r in 6:
		for n in 37:
			var t1: float = r * w.ROUND + w.T_LAUNCH + w.T_REST + 0.7
			var b: Vector3 = w.ball_state(seed_value, r, n, t1)
			if w.number_at(b.x - w.rotor_angle(seed_value, t1)) != n or absf(b.y - w.R_POCKET) > 0.001 or absf(b.z - w.BALL_R) > 0.001:
				missed += 1
			for mark in [0.0, w.T_FALL, w.T_DROP, w.T_REST]:
				var tm: float = r * w.ROUND + w.T_LAUNCH + mark
				jump = maxf(jump, w.ball_at(seed_value, r, n, 5, tm - 0.0002).distance_to(w.ball_at(seed_value, r, n, 5, tm + 0.0002)))
	for n in [0, 17, 26]:
		var was: Vector3 = w.ball_at(seed_value, 3, n, 5, 3 * w.ROUND + w.T_OPEN)
		for k in int((w.T_RESULT - w.T_OPEN) * 120.0):
			var now: Vector3 = w.ball_at(seed_value, 3, n, 5, 3 * w.ROUND + w.T_OPEN + (k + 1) / 120.0)
			stride = maxf(stride, was.distance_to(now))
			was = now
	if missed > 0 or jump > 0.02 or stride > 0.3:
		bad.append("ball: %d wrong pockets, jump %.3f m at a join, %.2f m in a tick" % [missed, jump, stride])

	# The clock.
	var phases := [w.phase_at(5.0), w.phase_at(20.5), w.phase_at(33.0), w.phase_at(40.1), w.phase_at(MatchState.duration - 10.0)]
	if phases[0][1] != w.OPEN or phases[1][1] != w.SPIN or phases[2][1] != w.PAID or phases[3][0] != 1 or phases[3][1] != w.OPEN or absf(phases[3][2] - (w.T_OPEN - 0.1)) > 0.01 or phases[4][1] != w.SHUT:
		bad.append("phases %s" % [phases])

	# What was built: a rotor and numbers that face up out of the wheel, drawn the right way
	# round to be seen from that side.
	var digits: Mesh = w._rotor.get_child(1).mesh
	var faces: Array = []
	for m in [w._rotor.get_child(0).mesh, digits, w._wheel.get_child(0).mesh]:
		faces.append(_facing(m))
	if w._rotor.get_child_count() < 2 or digits.get_aabb().size.x < 5.0 or faces[0][0] < 0.5 or faces[1][0] < 0.3 or faces[0][1] > 0 or faces[1][1] > 20 or faces[2][1] > 0 or Places.uses[Places.uses.size() - 1].kind != &"wheel":
		bad.append("built: numbers span %s; [share facing up, triangles inside out] rotor %s numbers %s bowl %s" % [digits.get_aabb().size, faces[0], faces[1], faces[2]])

	# Bets.
	p.st.hp = 100000.0
	p.st.money = 20000
	p.global_position = w.desk + Vector3(0, 0.2, 0)
	MatchState.time = 2.0
	await _wait(g, 0.2)
	var m0: int = p.st.money
	var bank0: int = g.casino.bank
	var took := func(kind: int, n: int, amount: int) -> bool:
		var before: int = p.st.money
		w._last.clear()
		w.srv_bet(kind, n, amount)
		return p.st.money == before - amount
	var ok: bool = took.call(0, 0, 50)
	var refused: bool = not took.call(0, 0, 55) and not took.call(9, 0, 50) and not took.call(7, 37, 50) and not took.call(6, 3, 50)
	p.global_position = w.desk + Vector3(100, 0.2, 0)
	refused = refused and not took.call(0, 0, 50)
	p.global_position = w.desk + Vector3(0, 0.2, 0)
	ok = ok and took.call(7, 17, 50) and took.call(6, 1, 10)
	for k in 5:
		ok = ok and took.call(0, 0, 10)
	var ninth: bool = took.call(0, 0, 10)
	if not ok or not refused or ninth or w.my_bets.size() != 8:
		bad.append("bets: taken %s, bad ones refused %s, a ninth %s, slip %d" % [ok, refused, ninth, w.my_bets.size()])
	# Seventeen comes up: the red loses, the number pays 35 to 1, the middle dozen 2 to 1.
	w._force = 17
	MatchState.time = w.T_OPEN - 0.1
	var drawn := await _until(g, 2.0, func(): return w.result_of(0) >= 0)
	var late: bool = took.call(0, 0, 50)
	MatchState.time = w.T_RESULT - 0.1
	var settled := await _until(g, 2.0, func(): return w._settled == 0)
	var won: int = p.st.money - m0
	if drawn < 0.0 or settled < 0.0 or late or w.result_of(0) != 17 or won != 1830 - 160 or p.st.money + g.casino.bank != m0 + bank0:
		bad.append("spin: drawn %.1f settled %.1f, came up %d, late bet %s, won %d, books %d" % [drawn, settled, w.result_of(0), late, won, p.st.money + g.casino.bank - m0 - bank0])
	# The table limit, in the next round.
	MatchState.time = w.ROUND + 2.0
	await _wait(g, 0.2)
	var big := 0
	for k in 5:
		big += 1 if took.call(1, 0, 1000) else 0
	if big != 4:
		bad.append("limit: %d bets of 1000 taken" % big)

	# Somebody walking in half way through.
	var seen: PackedInt32Array = w.results.duplicate()
	var here: Vector3 = w.ball_at(seed_value, 0, w.result_of(0), -1, 27.0)
	w.cl_sync(PackedInt32Array())
	var blank: bool = w.result_of(0) < 0
	w.cl_sync(seen)
	if not blank or w.result_of(0) != 17 or w.ball_at(seed_value, 0, w.result_of(0), -1, 27.0) != here:
		bad.append("late joiner sees another wheel")

	# The crowd: there, looking at it, and doing different things as the spin goes on.
	var facing := 0
	var look: Vector3 = w.at + Vector3(0, 0, 1.0)
	for k in w._watchers:
		var i: int = crowd.COUNT + w._first + k
		var to: Vector3 = (look - crowd.pos[i]) * Vector3(1, 0, 1)
		if crowd.state[i] == crowd.AMBIENT and crowd._grp[i] == crowd._stand_grp and absf(angle_difference(crowd.yaw_of(i), Kit.face(to))) < 0.5 and not Nav.blocked(crowd.pos[i]):
			facing += 1
	var mixes: Array = []
	for t in [2.0 * w.ROUND + 8.0, 2.0 * w.ROUND + w.T_LAUNCH + w.T_FALL + 1.2, 2.0 * w.ROUND + w.T_RESULT + 2.0]:
		MatchState.time = t
		await _wait(g, 1.8)
		var mix := {}
		for k in w._watchers:
			var pose: int = crowd._idle[crowd.COUNT + w._first + k]
			mix[pose] = mix.get(pose, 0) + 1
		mixes.append(mix)
	var keen: int = mixes[1].get(Kit.HANDS_UP, 0) + mixes[1].get(Kit.FILM, 0) + mixes[1].get(Kit.POINT, 0)
	var glad: int = mixes[2].get(Kit.CHEER, 0) + mixes[2].get(Kit.CLAP, 0) + mixes[2].get(Kit.DANCE, 0)
	var sorry: int = mixes[2].get(Kit.SHRUG, 0) + mixes[2].get(Kit.ARGUE, 0)
	if w._watchers < 30 or facing < w._watchers - 1 or mixes[0].get(Kit.HANDS_UP, 0) > 0 or mixes[0].size() < 4 or keen < 12 or glad + sorry < 14 or w.result_of(2) < 0:
		bad.append("crowd: %d watching, %d facing it; waiting %s, as it drops %s, after %s" % [w._watchers, facing, mixes[0], mixes[1], mixes[2]])
	# One of them takes fright and the rest carry on.
	var runner: int = crowd.COUNT + w._first + 3
	crowd._srv_flee(runner, w.at)
	await _wait(g, 0.6)
	if crowd.state[runner] != crowd.FLEE or crowd._grp[runner] != -1:
		bad.append("runner: state %d group %d" % [crowd.state[runner], crowd._grp[runner]])

	# What it costs to keep turning, a frame, in the middle of a spin.
	MatchState.time = 3.0 * w.ROUND + w.T_LAUNCH + 3.0
	await _wait(g, 0.3)
	var usec := Time.get_ticks_usec()
	for k in 500:
		w._process(0.008)
	var cost: float = (Time.get_ticks_usec() - usec) / 500000.0
	if cost > 0.4:
		bad.append("costs %.2f ms a frame" % cost)

	# The panel.
	MatchState.time = 3.0 * w.ROUND + 4.0
	g.hud.open_wheel()
	await _wait(g, 0.3)
	var panel: bool = g.hud.shop_open and g.hud._wheel_buttons.size() == 10 and not g.hud._wheel_buttons[0].disabled
	MatchState.time = 3.0 * w.ROUND + w.T_OPEN + 1.0
	await _wait(g, 0.3)
	panel = panel and g.hud._wheel_buttons[0].disabled and g.hud._wheel_row.visible
	g.hud.close_shop()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not panel:
		bad.append("panel")

	# Up the steps onto the deck.
	p.global_position = w.at + Vector3(8.8, 0.2, -2.4)
	p.rotation.y = PI / 2.0
	await _wait(g, 0.3)
	Input.action_press("move_forward")
	var up := await _until(g, 6.0, func(): return p.global_position.y > w.DECK_Y - 0.1 and p.global_position.x < w.at.x + 5.2 and p.is_on_floor())
	_keys_up()
	if up < 0.0:
		bad.append("steps: stuck at %s" % (p.global_position - w.at))
	g.debug_result("roleta", bad.is_empty(), "ball true to the call, %.3f m at the joins, %.2f m a tick; 8 bets taken, 17 paid %d; %d watching, %d keen, %d glad %d sorry; deck in %.1f s; %.3f ms a frame  %s" % [jump, stride, won, w._watchers, keen, glad, sorry, up, cost, "; ".join(bad)])


## For a second peer, joined to a host whose match is already some way in (--join=IP
## --test=roletanet): it is told what has come up already, sees the same ball as the host
## would, and a bet goes up to the host and an answer comes back.
static func _roleta_net(g: Node) -> void:
	var w = g.roleta
	var p = g.local_player
	var bad: Array = []
	var told := await _until(g, 30.0, func(): return w.result_of(int(MatchState.time / w.ROUND) - 1) >= 0 or w.result_of(int(MatchState.time / w.ROUND)) >= 0)
	if told < 0.0 or g.multiplayer.is_server():
		bad.append("never heard what had come up (results %s, server %s)" % [w.results, g.multiplayer.is_server()])
	p.global_position = w.desk + Vector3(0, 0.2, 0)
	await _until(g, 45.0, func(): return w.phase_at(MatchState.time)[1] == w.OPEN and w.phase_at(MatchState.time)[2] < w.T_OPEN - 1.5)
	# Nothing in their pockets, so the answer is no; but it is an answer.
	g.to_server("srv_bet", [0, 0, 10], w)
	var answered := await _until(g, 3.0, func(): return g.hud._toast_log.any(func(e): return e[0].text.begins_with("You have not got")))
	if answered < 0.0:
		bad.append("no answer to a bet")
	var r := int(MatchState.time / w.ROUND)
	var spun := await _until(g, 30.0, func(): return w.result_of(r) >= 0)
	await _wait(g, 3.0)
	var ball: Vector3 = w._bola.position
	var want: Vector3 = w.ball_at(MatchState.seed_value, r, w.result_of(r), w.result_of(r - 1), w._t)
	if spun < 0.0 or ball.distance_to(want) > 0.5 or absf(w._t - MatchState.time) > 0.3:
		bad.append("spin: heard after %.1f, ball %.2f m from where it should be, clock out by %.2f" % [spun, ball.distance_to(want), w._t - MatchState.time])
	g.debug_result("roletanet", bad.is_empty(), "told after %.1f s, answered in %.2f s, round %d came up %d  %s" % [told, answered, r, w.result_of(r), "; ".join(bad)])
