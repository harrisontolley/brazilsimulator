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
const WORLD_AABB := AABB(Vector3(-400, -20, -480), Vector3(800, 105, 690))

## Still water. The sand is flat down to SHORE_Z and falls away from there, so the sea
## starts a few metres further out, where the bed first dips under this.
const SEA_Y := -0.35
## The seabed as [z, height] going out: a paddling shelf, the drop, then the deep.
const SEABED: Array[Vector2] = [Vector2(-38, 0), Vector2(-50, -1.2), Vector2(-80, -6), Vector2(-200, -12), Vector2(-470, -14)]
## Where the bed goes under: the water's edge on a calm day.
const WATER_Z := -41.5
## As far out as anyone gets, and where the current starts turning them back.
const SEA_EDGE_Z := -470.0
const SEA_SOFT_Z := -435.0
const SEA_SOFT_X := 290.0
## The yacht lies at anchor here, bow toward +x: centre, and half its length and beam.
const YACHT_POS := Vector3(70, 0, -215)
const YACHT_HALF := Vector2(23, 4.6)
## How much of a jet ski's hull sits under the water.
const SKI_DRAFT := 0.2
## The swell, as [direction x, direction z, wavenumber, speed in radians a second, height,
## peakedness]. The sea shader is handed this same table, so what is drawn is what floats.
const WAVES: Array = [
	[0.148, 0.989, 0.185, 1.35, 0.28, 1.6],
	[-0.399, 0.917, 0.33, 1.8, 0.14, 1.3],
	[0.8, 0.6, 0.57, 2.36, 0.07, 1.0],
	[-0.919, 0.394, 0.97, 3.08, 0.035, 1.0],
]

## The clock the waves run on: the match clock, kept ticking after the whistle.
static var sea_t := 0.0
## How rough the weather is making it, 0..1.
static var sea_storm := 0.0
## Whether this player's camera is under the surface.
static var cam_under := false

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
## The pitch painted on the prison yard. A goal there buys time, not money.
const YARD_PITCH := [Vector3(8, 0, 121), Vector2(10, 5)]
## Futevolei courts, same shape, with the net across the middle.
const COURTS := [
	[Vector3(-100, 0, 35), Vector2(8, 4)],
	[Vector3(0, 0, 35), Vector2(8, 4)],
	[Vector3(100, 0, 35), Vector2(8, 4)],
]

## Plots in the two building rows (row 0 faces the avenida, row 1 the back street) that the
## street leaves empty for a building you can walk into. `door` and `back` are the x of the
## front and back doorways, `public` how deep from the front the customers' part goes.
const LOTS := [
	{"kind": "cassino", "name": "BINGO ATLÂNTICO", "row": 0, "x0": -24.0, "x1": 24.0, "floors": 3, "door": 8.0, "back": 21.0, "public": 18.5,
			"tint": Color(0.42, 0.1, 0.14), "sign": Color(0.85, 0.6, 0.1), "floor": Color(0.2, 0.2, 0.22), "light": Color(1.0, 0.8, 0.5)},
	{"kind": "boteco", "name": "BOTECO DO ZÉ", "row": 0, "x0": -127.0, "x1": -111.0, "floors": 2, "back": -117.0,
			"tint": Color(0.93, 0.8, 0.45), "sign": Color(0.75, 0.12, 0.1)},
	{"kind": "mercado", "name": "MERCADINHO", "row": 0, "x0": 49.0, "x1": 61.0, "floors": 2,
			"tint": Color(0.8, 0.88, 0.92), "sign": Color(0.1, 0.45, 0.75)},
	{"kind": "farmacia", "name": "FARMÁCIA", "row": 0, "x0": 100.0, "x1": 114.0, "floors": 4, "public": 13.0,
			"tint": Color(0.95, 0.95, 0.95), "sign": Color(0.1, 0.6, 0.3), "light": Color(0.9, 0.95, 1.0)},
	{"kind": "barbearia", "name": "BARBEARIA", "row": 0, "x0": 150.0, "x1": 162.0, "floors": 1,
			"tint": Color(0.85, 0.82, 0.9), "sign": Color(0.15, 0.2, 0.5)},
	{"kind": "presidio", "name": "PRESÍDIO", "row": 1, "x0": -41.0, "x1": 41.0, "floors": 0,
			"tint": Color(0.55, 0.55, 0.57), "sign": Color(0.1, 0.2, 0.6)},
	{"kind": "boteco", "name": "BAR DO PORTUGUÊS", "row": 1, "x0": 100.0, "x1": 114.0, "floors": 1, "back": 107.0,
			"tint": Color(0.75, 0.86, 0.78), "sign": Color(0.1, 0.4, 0.2)},
]


## The lot in `row` that the stretch x0..x1 runs into, or {}.
static func lot_over(row: int, x0: float, x1: float) -> Dictionary:
	for lot in LOTS:
		if lot.row == row and x1 > lot.x0 + 0.05 and x0 < lot.x1 - 0.05:
			return lot
	return {}


## Height of the seabed at z. It only varies with distance from the shore.
static func seabed_y(z: float) -> float:
	if z >= SEABED[0].x:
		return 0.0
	for k in range(1, SEABED.size()):
		var b := SEABED[k]
		if z >= b.x:
			var a := SEABED[k - 1]
			return lerpf(a.y, b.y, (a.x - z) / (a.x - b.x))
	return SEABED[SEABED.size() - 1].y


## How much of the full swell reaches (x, z): it dies away up the beach, is damped in the
## lee of the yacht (so the decks need not rock), and builds in a storm.
static func wave_amp(x: float, z: float) -> float:
	var shore := lerpf(0.18, 1.0, smoothstep(0.0, 50.0, SHORE_Z - z))
	var calm := lerpf(0.3, 1.0, smoothstep(26.0, 70.0, Vector2(x - YACHT_POS.x, z - YACHT_POS.z).length()))
	return shore * calm * (1.0 + 1.5 * sea_storm)


## Height of the water surface at (x, z) at time t.
static func wave_y_at(x: float, z: float, t: float) -> float:
	var h := 0.0
	for w in WAVES:
		var s: float = 0.5 + 0.5 * sin((w[0] * x + w[1] * z) * w[2] - w[3] * t)
		h += w[4] * (2.0 * pow(s, w[5]) - 1.0)
	return SEA_Y + h * wave_amp(x, z)


## Height of the water surface at (x, z) now.
static func wave_y(x: float, z: float) -> float:
	return wave_y_at(x, z, sea_t)


## Which way the surface tilts at (x, z): its rise per metre along x and along z.
static func wave_slope(x: float, z: float) -> Vector2:
	var h := wave_y(x, z)
	return Vector2(wave_y(x + 0.5, z) - h, wave_y(x, z + 0.5) - h) * 2.0


## Hands a material the shape of the sea: anything drawn on the water needs the same waves.
static func sea_params(m: ShaderMaterial) -> void:
	m.set_shader_parameter("shore_z", SHORE_Z)
	m.set_shader_parameter("sea_y", SEA_Y)
	m.set_shader_parameter("yacht_xz", Vector2(YACHT_POS.x, YACHT_POS.z))
	var wa: Array = []
	var wb: Array = []
	for w in WAVES:
		wa.append(Vector4(w[0], w[1], w[2], w[3]))
		wb.append(Vector2(w[4], w[5]))
	m.set_shader_parameter("wave_a", wa)
	m.set_shader_parameter("wave_b", wb)
	m.set_shader_parameter("seabed", SEABED)


## Is p in the sea: out past the water's edge and not up on something above it?
static func wet(p: Vector3) -> bool:
	return p.z < WATER_Z and p.y < SEA_Y + 0.5


## How far under the surface p is; negative above it.
static func depth(p: Vector3) -> float:
	if p.z >= WATER_Z + 3.0:
		return -1.0
	return wave_y(p.x, p.z) - p.y


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
