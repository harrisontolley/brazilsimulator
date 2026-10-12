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
