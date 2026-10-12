extends RefCounted
## Scripted checks for the street's life: where people can walk, how they take fright, the
## dogs, the heavier weapons, and whether the words on screen fit. Run as --test=<name>.

const Nav := preload("res://scenes/world/nav.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")


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
	var ok: bool = shut == 0 and route_ok and rounds_bad == 0 and crowd._errands.size() > 100 and indoors > 5 and lanes_bad == 0 and stuck == 0 and walked_bad == 0 and flee_bad == 0 and fled > 100 and chase_bad == 0 and cop_bad == 0 and closed < 4.0
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
