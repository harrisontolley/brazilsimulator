extends RefCounted
## Map constants and street navigation shared by the world, the crowd, police and traffic.
##
## Inland of the sand the map is bands of z: open ground anyone can cross freely, and rows
## of buildings that can only be passed along a cross street. Rooftops and the favela
## terraces are off this grid: only players get up there.

const X_LIMIT := 300.0
const SHORE_Z := -38.0
const PROM_Z := 40.0
const ROAD_Z := 52.0
const WALK_Z := 70.0
const BLOCK_A_Z := 73.0
const RUA_Z := 99.0
const BLOCK_B_Z := 111.0
const FOOT_Z := 131.0
const FAVELA_Z := 137.0
const BACK_Z := 185.0
const WORLD_AABB := AABB(Vector3(-400, -5, -120), Vector3(800, 90, 330))

## Upper z edge of each band. Even bands are open, odd ones are building rows.
const EDGES: Array[float] = [BLOCK_A_Z, RUA_Z, BLOCK_B_Z, FOOT_Z, FAVELA_Z]
## Streets through the front row of buildings, and the three that carry on up the hill.
const CROSS_X: Array[float] = [-225.0, -135.0, -45.0, 45.0, 135.0, 225.0]
const STAIR_X: Array[float] = [-135.0, 45.0, 225.0]
const CROSS_HALF := 4.0

## Favela terraces: each is TERRACE_D deep and TERRACE_H above the one below.
const TERRACES := 6
const TERRACE_D := 8.0
const TERRACE_H := 3.0
## Houses stand on the back of a terrace, leaving this much walkway along its front.
const BECO := 3.0

## Avenida lanes: the two nearest the sea run toward -x, the others toward +x.
const LANES: Array[float] = [54.2, 57.8, 64.2, 67.8]
const LANE_DIR: Array[float] = [-1.0, -1.0, 1.0, 1.0]
const MEDIAN_Z := 61.0

## Football pitches on the sand as [centre, half size]; the goals are at the two x ends.
const PITCHES := [
	[Vector3(-170, 0, 16), Vector2(17, 9)],
	[Vector3(30, 0, -14), Vector2(17, 9)],
	[Vector3(200, 0, 16), Vector2(17, 9)],
]
const GOAL_HALF := 2.5
const GOAL_H := 2.2
## Futevolei courts, same shape, with the net across the middle.
const COURTS := [
	[Vector3(-100, 0, 35), Vector2(8, 4)],
	[Vector3(0, 0, 35), Vector2(8, 4)],
	[Vector3(100, 0, 35), Vector2(8, 4)],
]

## Rounded hills behind the city as [centre, radii], filled in by the world as it builds them.
static var hills: Array = []


## Height of the hills at (x, z), or 0 where there are none.
static func hill_y(x: float, z: float) -> float:
	var best := 0.0
	for h in hills:
		var c: Vector3 = h[0]
		var r: Vector3 = h[1]
		var k := 1.0 - pow((x - c.x) / r.x, 2.0) - pow((z - c.z) / r.z, 2.0)
		if k > 0.0:
			best = maxf(best, r.y * sqrt(k))
	return best


static func band(z: float) -> int:
	for b in EDGES.size():
		if z < EDGES[b]:
			return b
	return EDGES.size()


static func _gaps(b: int) -> Array[float]:
	return CROSS_X if b == 1 else STAIR_X


static func _nearest(xs: Array[float], x: float) -> float:
	var best := xs[0]
	for c in xs:
		if absf(c - x) < absf(best - x):
			best = c
	return best


## Can someone on foot at street level stand here?
static func walkable(p: Vector3) -> bool:
	if absf(p.x) > X_LIMIT + 5.0:
		return false
	var b := band(p.z)
	if b == EDGES.size():
		return false
	if b % 2 == 0:
		return true
	return absf(p.x - _nearest(_gaps(b), p.x)) <= CROSS_HALF


## The street-level spot nearest p: under a rooftop, that is the street in front of it.
static func snap(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -X_LIMIT, X_LIMIT)
	p.y = 0.0
	var b := band(p.z)
	if b == EDGES.size():
		p.z = FAVELA_Z - 1.0
	elif b % 2 == 1 and absf(p.x - _nearest(_gaps(b), p.x)) > CROSS_HALF:
		var lo := EDGES[b - 1]
		var hi := EDGES[b]
		p.z = lo - 0.8 if p.z - lo < hi - p.z else hi + 0.8
	return p


## Where to head next to get from `from` to `to` on foot without walking through a building.
static func next_point(from: Vector3, to: Vector3) -> Vector3:
	to = snap(to)
	var bf := band(from.z)
	var bt := band(to.z)
	if bf == EDGES.size():
		return to
	if bf % 2 == 1:
		# Inside a cross street: run to whichever end leads on.
		var cx := _nearest(_gaps(bf), from.x)
		if bt == bf and absf(to.x - cx) <= CROSS_HALF:
			return to
		var lo := EDGES[bf - 1] - 1.0
		var hi := EDGES[bf] + 1.0
		var up := bt > bf
		if bt == bf:
			up = hi - from.z < from.z - lo
		return Vector3(cx, 0.0, hi if up else lo)
	if bt == bf:
		return to
	var up := bt > bf
	var row := bf + 1 if up else bf - 1
	var edge := EDGES[bf] if up else EDGES[bf - 1]
	var far := EDGES[row] + 1.0 if up else EDGES[row - 1] - 1.0
	var best := 0.0
	var best_cost := INF
	for cx in _gaps(row):
		var cost := absf(from.x - cx) + absf(cx - to.x)
		if cost < best_cost:
			best = cx
			best_cost = cost
	# Line up with the mouth of the street first, then run its length.
	if absf(from.x - best) > CROSS_HALF - 1.0:
		return Vector3(best, 0.0, edge - 1.0 if up else edge + 1.0)
	return Vector3(best, 0.0, far)


## How far someone can run from `origin` along `dir` before meeting a building, up to max_d.
static func run_dist(origin: Vector3, dir: Vector3, max_d: float) -> float:
	if origin.y > 1.0:
		return max_d
	var d := 0.0
	while d < max_d and walkable(origin + dir * (d + 1.0)):
		d += 1.0
	return d


## Height of the favela ground at p: the terrace it is over, or 0 in front of the hill.
static func terrace_y(z: float) -> float:
	if z < FAVELA_Z:
		return 0.0
	return (floorf((z - FAVELA_Z) / TERRACE_D) + 1.0) * TERRACE_H


static func in_rect(p: Vector3, rect: Array, margin := 0.0) -> bool:
	var c: Vector3 = rect[0]
	var h: Vector2 = rect[1]
	return absf(p.x - c.x) < h.x + margin and absf(p.z - c.z) < h.y + margin


## Index of the pitch or court p is on, or -1.
static func pitch_at(p: Vector3, margin := 0.0) -> int:
	for i in PITCHES.size():
		if in_rect(p, PITCHES[i], margin):
			return i
	return -1


static func on_play_area(p: Vector3, margin := 0.0) -> bool:
	if pitch_at(p, margin) >= 0:
		return true
	for c in COURTS:
		if in_rect(p, c, margin):
			return true
	return false
