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
			if crowd.state[i] == crowd.AMBIENT and Nav.blocked(crowd.pos[i]):
				walked_bad += 1
	MatchState.time = keep
	crowd._process(0.016)
	if img != null:
		img.save_png(out_dir() + "/nav.png")
	var ok: bool = shut == 0 and route_ok and lanes_bad == 0 and stuck == 0 and walked_bad == 0 and flee_bad == 0 and fled > 100 and chase_bad == 0 and cop_bad == 0 and closed < 4.0
	g.debug_result("nav", ok, "doors shut %d route %.0f m ok %s, 20 paths %d ms, walkers %d lanes bad %d walked bad %d, standing in things %d, fled %d cowered %d bad legs %d in %d ms, chase %.0f -> %.1f m in %d frames (%d ms) inside things %d, cops inside things %d %s" % [shut, Nav.length(a, route), route_ok, path_ms, crowd._walkers.size(), lanes_bad, walked_bad, stuck, fled, cowered, flee_bad, flee_ms, start, closed, frames, chase_ms, chase_bad, cop_bad, first])
