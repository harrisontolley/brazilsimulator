extends RefCounted
## Where people on foot can and cannot stand: a grid over the whole map, filled in from every
## solid box as the world is built, and the routes round what is in the way.
##
## Every peer builds the same world, so every peer has the same grid; nothing here is networked.
## It is one storey: on the favela terraces "the ground" is the terrace under you.

const Layout := preload("res://scenes/world/layout.gd")

const CELL := 0.5
const X0 := -312.0
const Z0 := -42.0
const W := 1248   # cells along x: out to x = 312
const H := 464    # cells along z: out to z = 190
## A box counts as in the way if any of it is between a shin and a shoulder above the ground.
const LOW := 0.3
const HIGH := 1.5
## How much wider than itself a box is drawn, so nobody walks along a wall with a shoulder in it.
const MARGIN := 0.1
const STEP := 0.25
const FAR := 1.0e6
## The furthest ahead anybody plans a way round things.
const REACH := 38.0

static var _grid: AStarGrid2D


## Empties the grid. The world calls this before it starts building.
static func begin() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, W, H)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = Vector2(X0 + CELL * 0.5, Z0 + CELL * 0.5)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	# The sea, and the strips beyond the ends of the beach.
	_fill(-FAR, Layout.SHORE_Z, -FAR, FAR)
	_fill(-FAR, FAR, -FAR, -Layout.X_LIMIT)
	_fill(-FAR, FAR, Layout.X_LIMIT, FAR)
	# Traffic has the avenida: cross it if you must, but do not walk along it.
	add_cost(AABB(Vector3(-FAR, 0, Layout.ROAD_Z + 0.8), Vector3(2.0 * FAR, 1, 16.6)), 3.0)


static func ready() -> bool:
	return _grid != null


static func _cx(x: float) -> int:
	return int(floorf((x - X0) / CELL))


static func _cz(z: float) -> int:
	return int(floorf((z - Z0) / CELL))


## Blocks every cell whose centre is inside z0..z1, x0..x1.
static func _fill(z0: float, z1: float, x0: float, x1: float) -> void:
	var a := Vector2i(clampi(ceili((x0 - X0) / CELL - 0.5), 0, W), clampi(ceili((z0 - Z0) / CELL - 0.5), 0, H))
	var b := Vector2i(clampi(floori((x1 - X0) / CELL - 0.5) + 1, 0, W), clampi(floori((z1 - Z0) / CELL - 0.5) + 1, 0, H))
	if b.x > a.x and b.y > a.y:
		_grid.fill_solid_region(Rect2i(a, b - a), true)


## Marks the ground a solid box stands on as somewhere nobody can walk.
static func add_box(p: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	if _grid == null:
		return
	var half := size * 0.5
	if rot == Vector3.ZERO:
		var lo := p.y - half.y
		var hi := p.y + half.y
		var z0 := p.z - half.z - MARGIN
		var z1 := p.z + half.z + MARGIN
		if z1 < Layout.FAVELA_Z:
			if hi > LOW and lo < HIGH:
				_fill(z0, z1, p.x - half.x - MARGIN, p.x + half.x + MARGIN)
			return
		# Up the hill the ground rises a terrace at a time, so take it a row at a time.
		for r in range(clampi(ceili((z0 - Z0) / CELL - 0.5), 0, H), clampi(floori((z1 - Z0) / CELL - 0.5) + 1, 0, H)):
			var z := Z0 + (r + 0.5) * CELL
			var g := Layout.terrace_y(z)
			if hi > g + LOW and lo < g + HIGH:
				_fill(z, z, p.x - half.x - MARGIN, p.x + half.x + MARGIN)
		return
	# Turned or tilted: try each cell under it at three heights.
	var basis := Basis.from_euler(rot)
	var inv := basis.inverse()
	var reach := Vector3.ZERO
	for k in 3:
		reach += Vector3(absf(basis[k].x), absf(basis[k].y), absf(basis[k].z)) * half[k]
	if p.y - reach.y > Layout.terrace_y(p.z + reach.z) + HIGH:
		return
	var grown := half + Vector3(MARGIN, 0.0, MARGIN)
	for r in range(clampi(_cz(p.z - reach.z - MARGIN), 0, H), clampi(_cz(p.z + reach.z + MARGIN) + 1, 0, H)):
		var z := Z0 + (r + 0.5) * CELL
		var g := Layout.terrace_y(z)
		for c in range(clampi(_cx(p.x - reach.x - MARGIN), 0, W), clampi(_cx(p.x + reach.x + MARGIN) + 1, 0, W)):
			var x := X0 + (c + 0.5) * CELL
			for y in [g + LOW + 0.05, g + 0.9, g + HIGH - 0.05]:
				var l := inv * (Vector3(x, y, z) - p)
				if absf(l.x) <= grown.x and absf(l.y) <= grown.y and absf(l.z) <= grown.z:
					_grid.set_point_solid(Vector2i(c, r), true)
					break


## Is there something solid where p is? Off the map counts as solid.
static func blocked(p: Vector3) -> bool:
	if _grid == null:
		return false
	var c := Vector2i(_cx(p.x), _cz(p.z))
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return true
	return _grid.is_point_solid(c)


## Can someone walk straight from a to b?
static func clear(a: Vector3, b: Vector3) -> bool:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var n := int(ceilf(d.length() / STEP))
	for k in range(1, n + 1):
		if blocked(a + d * (float(k) / n)):
			return false
	return true


## How far someone can go from `origin` along `dir` before something is in the way, up to max_d.
static func free_run(origin: Vector3, dir: Vector3, max_d: float, step := STEP) -> float:
	if _grid == null:
		return max_d
	var d := 0.0
	var x := origin.x - X0
	var z := origin.z - Z0
	while d < max_d:
		var e := d + step
		var c := Vector2i(int(floorf((x + dir.x * e) / CELL)), int(floorf((z + dir.z * e) / CELL)))
		if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H or _grid.is_point_solid(c):
			break
		d = e
	return minf(d, max_d)


## The open spot nearest p within r, or p itself if it is already open or nothing is.
static func nearest_free(p: Vector3, r := 6.0) -> Vector3:
	if not blocked(p):
		return p
	var ring := CELL
	while ring <= r:
		var best := p
		var best_d := INF
		var n := int(ceilf(TAU * ring / CELL))
		for k in n:
			var a := TAU * k / n
			var q := Vector3(p.x + cos(a) * ring, p.y, p.z + sin(a) * ring)
			if not blocked(q):
				# Prefer the way out that is square on to the wall.
				var d := absf(cos(a)) * absf(sin(a))
				if d < best_d:
					best = q
					best_d = d
		if best_d < INF:
			best.y = Layout.terrace_y(best.z) if p.y > 1.0 else p.y
			return best
		ring += CELL
	return p


## One step of walking: p moved by `step`, sliding along whatever it would have walked into.
static func slide(p: Vector3, step: Vector3) -> Vector3:
	var q := p + step
	if not blocked(q):
		return q
	var along_x := Vector3(q.x, q.y, p.z)
	var along_z := Vector3(p.x, q.y, q.z)
	var ok_x := not blocked(along_x)
	var ok_z := not blocked(along_z)
	if ok_x and (not ok_z or absf(step.x) >= absf(step.z)):
		return along_x
	if ok_z:
		return along_z
	# Somehow inside something already: let them walk out of it.
	return q if blocked(p) else Vector3(p.x, q.y, p.z)


## The corners to walk through to get from a to b round whatever is between them, ending at b
## (or as near as anyone can get). It does not include a.
static func path(a: Vector3, b: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _grid == null:
		out.append(b)
		return out
	var from := nearest_free(a)
	var to := nearest_free(b)
	if clear(from, to):
		out.append(to)
		return out
	var ca := Vector2i(clampi(_cx(from.x), 0, W - 1), clampi(_cz(from.z), 0, H - 1))
	var cb := Vector2i(clampi(_cx(to.x), 0, W - 1), clampi(_cz(to.z), 0, H - 1))
	var cells := _grid.get_point_path(ca, cb, true)
	if cells.is_empty():
		out.append(from)
		return out
	# Pull the string tight: keep only the corners that are needed.
	var pts := PackedVector3Array()
	for c in cells:
		pts.append(Vector3(c.x, a.y, c.y))
	if cells.size() > 0 and Vector2i(_cx(pts[pts.size() - 1].x), _cz(pts[pts.size() - 1].z)) == cb:
		pts[pts.size() - 1] = Vector3(to.x, a.y, to.z)
	var at := from
	var i := 0
	while i < pts.size():
		var j := i
		# Look ahead for the farthest corner still in plain sight.
		var k := mini(pts.size() - 1, i + 48)
		while k > i:
			if clear(at, pts[k]):
				j = k
				break
			k -= 1
		at = pts[j]
		out.append(at)
		i = j + 1
	return out


## Total length of the walk from `from` through `pts`.
static func length(from: Vector3, pts: PackedVector3Array) -> float:
	var d := 0.0
	var at := from
	for p in pts:
		d += Vector2(p.x - at.x, p.z - at.z).length()
		at = p
	return d


## Where someone is after walking `d` from `from` through `pts`, as [position, direction].
static func along(from: Vector3, pts: PackedVector3Array, d: float) -> Array:
	var at := from
	var dir := Vector3.ZERO
	for p in pts:
		var leg := Vector3(p.x - at.x, 0.0, p.z - at.z)
		var l := leg.length()
		if l > 0.001:
			dir = leg / l
			if d <= l:
				var q := at + dir * d
				q.y = lerpf(at.y, p.y, d / l)
				return [q, dir]
			d -= l
		at = p
	return [at, dir]


## A way to run about `dist` from `from`, away from `threat`: a couple of straight legs, each
## as open as can be found. Cheap enough to work out for a whole street at once.
static func flee_path(from: Vector3, threat: Vector3, dist: float, seed := 0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var at := nearest_free(from)
	if at != from:
		out.append(at)
	var away := Vector3(at.x - threat.x, 0.0, at.z - threat.z)
	if away.length() < 0.05:
		away = Vector3(cos(seed * 2.4), 0.0, sin(seed * 2.4))
	away = away.normalized()
	var left := dist
	var legs := 0
	while left > 2.0 and legs < 4:
		var best_dir := Vector3.ZERO
		var best_run := 0.0
		var best_score := 0.0
		# Straight away first, then fanning out to either side.
		for k in 13:
			var turn := (k + 1) / 2 * 0.42 * (1.0 if (k + seed) % 2 == 0 else -1.0)
			var dir := away.rotated(Vector3.UP, turn)
			var run := free_run(at, dir, left, 0.4)
			var score := minf(run, left) * (0.25 + maxf(0.0, dir.dot(away)))
			if score > best_score + 0.01:
				best_score = score
				best_run = run
				best_dir = dir
			# Open ground more or less the right way: no need to look any further round.
			if run >= left * 0.9 and k < 5:
				break
		# The quick look can miss a lamp post; look properly along the way that was picked.
		best_run = free_run(at, best_dir, best_run)
		if best_run < 1.0:
			break
		# Stop short of the wall, so the next leg has room to turn.
		var run := maxf(best_run - 0.5, 0.75) if best_run < left else best_run
		at += best_dir * run
		at.y = Layout.terrace_y(at.z) if from.y > 1.0 else from.y
		out.append(at)
		left -= run
		legs += 1
		# Keep going the way we are going, but still not back toward the trouble.
		away = (best_dir + away * 0.6).normalized()
	return out


## The grid as a picture, one pixel a cell, for looking at.
static func image() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for r in H:
		for c in W:
			img.set_pixel(c, r, Color(0.1, 0.1, 0.12) if _grid.is_point_solid(Vector2i(c, r)) else Color(0.85, 0.82, 0.7))
	return img


static func pixel(p: Vector3) -> Vector2i:
	return Vector2i(clampi(_cx(p.x), 0, W - 1), clampi(_cz(p.z), 0, H - 1))


## Makes the ground inside `box` `times` as long to cross as it looks, so that routes go
## through it only when they have business there.
static func add_cost(box: AABB, times: float) -> void:
	if _grid == null:
		return
	var a := Vector2i(clampi(_cx(box.position.x), 0, W), clampi(_cz(box.position.z), 0, H))
	var b := Vector2i(clampi(_cx(box.end.x) + 1, 0, W), clampi(_cz(box.end.z) + 1, 0, H))
	if b.x > a.x and b.y > a.y:
		_grid.fill_weight_scale_region(Rect2i(a, b - a), times)


## One step for somebody chasing a moving `goal`: straight at it while it is in plain sight,
## round the corners when it is not. `m` is theirs to keep between calls; it remembers the
## way, so that it is only worked out again a couple of times a second.
static func steer(m: Dictionary, pos: Vector3, goal: Vector3, step: float, now: float) -> Vector3:
	# Nobody plans a walk the length of the beach in one go: head for a spot some way toward
	# it and think again from there. (Working out a long way round is what costs.)
	var whole := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	if whole.length() > REACH:
		var near := pos + whole.normalized() * REACH
		near.y = goal.y
		goal = nearest_free(near, 4.0)
	if now >= m.get("t", -1.0) or goal.distance_squared_to(m.get("goal", goal)) > 9.0:
		m.t = now + 0.45 + fmod(pos.x * 13.7 + pos.z * 7.3, 0.2)
		m.goal = goal
		m.k = 0
		m.way = PackedVector3Array() if clear(pos, goal) else path(pos, goal)
		if not m.way.is_empty() and m.way[m.way.size() - 1].distance_to(goal) > 3.0:
			# There is no way there. Looking for one is the dear part, so do not keep on at it.
			m.t = now + 3.0
	var way: PackedVector3Array = m.get("way", PackedVector3Array())
	var k: int = m.get("k", 0)
	var target := goal
	while k < way.size():
		target = way[k]
		if Vector2(target.x - pos.x, target.z - pos.z).length() > 0.45:
			break
		k += 1
		m.k = k
		# Past the last corner: whatever it was they were after, this is as near as it gets.
		target = goal if way.is_empty() else way[way.size() - 1]
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var d := to.length()
	if d < 0.01:
		return pos
	return slide(pos, to / d * minf(step, d))
