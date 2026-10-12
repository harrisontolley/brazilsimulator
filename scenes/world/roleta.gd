extends "res://scenes/world/world_kit.gd"
## A Roleta: the casino's wheel out on the sand, seven metres across and tipped up to face
## the beach, with a crowd round it. Lives at Game/Roleta on every peer.
##
## It turns all match on the match clock. Every ROUND seconds: bets are taken, the ball is
## thrown, it runs the rim against the turn of the wheel, comes off the track, rattles
## across the numbers and sits down in one. Everybody bets on the same spin.
##
## The host picks the number as the bets close and sends that one message. Where the wheel
## and the ball are is then a function of (seed, round, number, time), worked backward from
## where the ball has to end up, so every peer draws the same spin and somebody who joins in
## the middle of one sees the rest of it. The people watching are told how to stand from the
## same clock, so they cost nothing to send either.

const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const Casino := preload("res://scenes/world/casino.gd")
const Crowd := preload("res://scenes/crowd/crowd_manager.gd")
const Activities := preload("res://scenes/crowd/activities.gd")
const UI := preload("res://scenes/ui/ui_kit.gd")

enum { OPEN, SPIN, PAID, SHUT }

## One round, and when in it the bets close, the ball is thrown and the number is called.
const ROUND := 40.0
const T_OPEN := 20.0
const T_LAUNCH := 21.0
const T_RESULT := 32.0
## From the throw: when the ball starts to come off the track, when it reaches the numbers,
## and when it has stopped rattling about. T_SKIP is how long the rattling takes.
const T_FALL := 6.4
const T_DROP := 8.2
const T_REST := 10.5
const T_SKIP := T_REST - T_DROP
## Radians a second: the wheel, and the ball as it leaves the track (it is thrown faster).
const TURN := 0.9
const BALL_SLOW := 1.4

const POCKETS := 37
const STEP := TAU / POCKETS
## The numbers in the order they go round a European wheel.
const ORDER := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]

## The wheel from the middle out, in metres: where a ball sits in a pocket, the pockets,
## the ring the numbers are painted on, the slope up to the track, and the rim.
const R_HUB := 0.55
const R_CONE := 1.95
const R_POCKET := 2.2
const R_STEP := 2.45
const R_NUM := 2.65
const R_ENTRY := 2.85
const R_APRON := 3.15
const R_TRACK := 3.34
const R_RIM := 3.5
const R_OUT := 3.8
const H_NUM := 0.06
const H_TRACK := 0.36
const H_RIM := 0.8
const BALL_R := 0.15
## Where the ball waits before the first spin of a match: on top of the turret.
const TURRET_TOP := Vector3(0, 1.2, 0)

## How far it is tipped back from flat on its back, and where its middle is from WHEEL_POS.
const TILT := deg_to_rad(65.0)
const HUB := Vector3(0, 5.0, 1.0)
const DECK_Y := 1.2

const MAX_BETS := 8
const MAX_STAKE := 4000
const BET_REACH := 16.0
## A win this big (over what was staked) is everybody's business.
const HOT_WIN := 1000

const RED := Color(0.78, 0.07, 0.09)
const BLACK := Color(0.07, 0.07, 0.08)
const GREEN := Color(0.05, 0.5, 0.2)
const BRASS := Color(0.86, 0.68, 0.25)
const CHROME := Color(0.82, 0.83, 0.86)
const MAHOGANY := Color(0.36, 0.15, 0.08)
const GOLD := Color(1.0, 0.8, 0.3)

const IDLE_POSES := [Kit.STAND, Kit.TALK, Kit.DRINK, Kit.PHONE, Kit.LOOK, Kit.PHOTO, Kit.LAUGH, Kit.STAND, Kit.TALK]
const READY_POSES := [Kit.LOOK, Kit.POINT, Kit.FILM, Kit.STAND, Kit.CLAP, Kit.STAND]
const WATCH_POSES := [Kit.FILM, Kit.LOOK, Kit.STAND, Kit.POINT, Kit.CLAP, Kit.STAND, Kit.FILM, Kit.PHOTO]
const TENSE_POSES := [Kit.HANDS_UP, Kit.POINT, Kit.FILM, Kit.LOOK, Kit.HANDS_UP, Kit.STAND]
const WON_POSES := [Kit.CHEER, Kit.CHEER, Kit.CLAP, Kit.DANCE, Kit.HANDS_UP, Kit.CHEER]
const LOST_POSES := [Kit.SHRUG, Kit.ARGUE, Kit.LAUGH, Kit.STAND, Kit.SHRUG, Kit.PHONE]

var at: Vector3 = Layout.WHEEL_POS
## Where to stand to bet.
var desk := Vector3.ZERO
## What each round came to, by round; -1 where it is not known (yet).
var results := PackedInt32Array()
## This player's bets as [kind, n, amount], and the round they are on.
var my_bets: Array = []
var my_round := -1
## The last round somebody won big on.
var hot_round := -1

var _wheel: Node3D
var _rotor: Node3D
var _bola: MeshInstance3D
var _bulbs: MultiMesh
var _status: Label3D
var _tote: Array[Label3D] = []
var _roll: AudioStreamPlayer3D
var _t := 0.0
var _was_tr := 0.0
var _was_round := -1
var _tick_k := 0
var _tick_ms := 0
var _bulb_t := 0.0
var _people_t := 0.0
var _shown := ""
var _shown_tote := -2
## Crowd indices of the people watching, and of the man who calls the bets.
var _first := -1
var _watchers := 0
var _caller := -1

# host only
var _bets := {}       # pid -> [[kind, n, amount]] on _bet_round
var _bet_round := -1
var _settled := -1
var _last := {}       # pid -> msec of their last bet
var _force := -1      # a test's say in what comes up next


func _ready() -> void:
	_init_kit()
	_stage()
	_build_wheel()
	_boards()
	_people()
	_flush()


# --- the clock ---

## Which round match time t is in, what is going on in it, and how long that has left.
static func phase_at(t: float) -> Array:
	var r := maxi(int(floorf(t / ROUND)), 0)
	var tr := t - r * ROUND
	if not playable(r):
		return [r, SHUT, 0.0]
	if tr < T_OPEN:
		return [r, OPEN, T_OPEN - tr]
	if tr < T_RESULT:
		return [r, SPIN, T_RESULT - tr]
	return [r, PAID, ROUND - tr]


## Is there time left in the match to see round r through? Nothing is taken on one that
## would be cut short by the whistle.
static func playable(r: int) -> bool:
	return r * ROUND + T_RESULT <= MatchState.duration


func result_of(r: int) -> int:
	return results[r] if r >= 0 and r < results.size() else -1


static func is_red(n: int) -> bool:
	return Casino.REDS.has(n)


static func colour_of(n: int) -> Color:
	return GREEN if n == 0 else (RED if is_red(n) else BLACK)


# --- the spin ---

## Where number n's pocket is round the rotor.
static func pocket_angle(n: int) -> float:
	return -ORDER.find(n) * STEP


## The number whose pocket is at `rel` round the rotor.
static func number_at(rel: float) -> int:
	return ORDER[int(roundf(fposmod(-rel, TAU) / STEP)) % POCKETS]


## How far round the wheel has turned by time t. It never stops.
static func rotor_angle(seed_value: int, t: float) -> float:
	return Activities.h01(seed_value, 0) * TAU + TURN * t


## How fast the ball is thrown in round r.
static func throw_speed(seed_value: int, r: int) -> float:
	return 5.2 + 1.2 * Activities.h01(seed_value, r + 1)


## Height of the wheel's surface r from the middle.
static func surf(r: float) -> float:
	if r >= R_APRON:
		return H_TRACK
	if r >= R_ENTRY:
		return lerpf(H_NUM, H_TRACK, (r - R_ENTRY) / (R_APRON - R_ENTRY))
	if r >= R_STEP:
		return H_NUM
	return lerpf(0.0, H_NUM, clampf((r - (R_STEP - 0.1)) / 0.1, 0.0, 1.0))


## A point on the wheel: `a` round it, r out from the middle, h off its face.
static func spot(a: float, r: float, h: float) -> Vector3:
	return Vector3(-sin(a) * r, h, -cos(a) * r)


## The ball in round r, which comes up `number`, at match time t (at or after the throw):
## its angle round the bowl, how far out it is, and how high.
##
## It leaves the croupier's hand going against the wheel and slows evenly until it comes off
## the track at T_DROP. From there it is carried round with the wheel, skipping back over
## fewer and fewer pockets until at T_REST it is sitting in the one it was always going to.
## Where it is thrown from is worked back from that, so angle and speed join up at T_DROP.
static func ball_state(seed_value: int, r: int, number: int, t: float) -> Vector3:
	var t0 := r * ROUND + T_LAUNCH
	var tau := maxf(t - t0, 0.0)
	var fast := throw_speed(seed_value, r)
	var home := pocket_angle(number)
	var skip := (BALL_SLOW + TURN) * T_SKIP / 3.0
	if tau >= T_REST:
		return Vector3(rotor_angle(seed_value, t) + home, R_POCKET, BALL_R)
	if tau >= T_DROP:
		var u := (tau - T_DROP) / T_SKIP
		var out := R_POCKET + (R_ENTRY - R_POCKET) * (1.0 - u) * (1.0 - u) + 0.1 * (1.0 - u) * sin(3.0 * PI * u)
		return Vector3(rotor_angle(seed_value, t) + home + skip * pow(1.0 - u, 3.0), out, surf(out) + BALL_R + _bounce(u))
	var from := rotor_angle(seed_value, t0 + T_DROP) + home + skip + (fast + BALL_SLOW) * T_DROP * 0.5
	var angle := from - (fast * tau - (fast - BALL_SLOW) * tau * tau / (2.0 * T_DROP))
	var rad := R_TRACK
	var hop := 0.0
	if tau > T_FALL:
		var s := (tau - T_FALL) / (T_DROP - T_FALL)
		rad = R_TRACK - (R_TRACK - R_ENTRY) * s * s
		# Half way down the slope it catches one of the brass studs.
		var k := (tau - (T_FALL + T_DROP) * 0.5) / 0.45
		if k > 0.0 and k < 1.0:
			hop = 0.25 * 4.0 * k * (1.0 - k)
	return Vector3(angle, rad, surf(rad) + BALL_R + hop)


## How high the ball is off the wheel `u` of the way through its rattling about.
static func _bounce(u: float) -> float:
	var knots := [0.0, 0.3, 0.55, 0.74, 0.88]
	var tops := [0.42, 0.26, 0.14, 0.06]
	for k in tops.size():
		if u < knots[k + 1]:
			var x: float = (u - knots[k]) / (knots[k + 1] - knots[k])
			return tops[k] * 4.0 * x * (1.0 - x)
	return 0.0


## Where the ball is on the wheel at match time t, given what this round comes to (-1 if
## that is not known yet) and what the one before did.
static func ball_at(seed_value: int, r: int, number: int, prev: int, t: float) -> Vector3:
	var turn := rotor_angle(seed_value, t)
	var rest := TURRET_TOP if prev < 0 else spot(turn + pocket_angle(prev), R_POCKET, BALL_R)
	var tr := t - r * ROUND
	if number < 0 or tr < T_OPEN:
		return rest
	if tr < T_LAUNCH:
		# Picked out of the last pocket and up to the rim.
		var s := smoothstep(0.0, 1.0, (tr - T_OPEN) / (T_LAUNCH - T_OPEN))
		var go := ball_state(seed_value, r, number, r * ROUND + T_LAUNCH)
		return rest.lerp(spot(go.x, go.y, go.z), s) + Vector3(0, 0.8 * sin(PI * s), 0)
	var b := ball_state(seed_value, r, number, t)
	return spot(b.x, b.y, b.z)


# --- building it ---

## Collects flat-shaded quads into one mesh, each facing whichever way it is told to.
class Shape:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	static func pt(a: float, r: float, h: float) -> Vector3:
		return Vector3(-sin(a) * r, h, -cos(a) * r)

	## a, b, e, d go round its edge; `up` is roughly the way it should face.
	func quad(a: Vector3, b: Vector3, e: Vector3, d: Vector3, col: Color, up: Vector3) -> void:
		var nrm := (e - a).cross(b - a)
		if nrm.length_squared() < 1e-12:
			nrm = (d - a).cross(e - a)
		if nrm.dot(up) < 0.0:
			var swap := b
			b = d
			d = swap
			nrm = -nrm
		nrm = nrm.normalized()
		var base := v.size()
		for p in [a, b, e, d]:
			v.append(p)
			n.append(nrm)
			c.append(col)
		for k in [0, 1, 2, 0, 2, 3]:
			idx.append(base + k)

	## A strip round the wheel from angle a0 to a1, between (r0, h0) and (r1, h1). `face`: 0
	## for one that looks up, 1 for a wall that looks outward, -1 for one that looks in.
	func band(r0: float, h0: float, r1: float, h1: float, a0: float, a1: float, col: Color, face := 0, steps := 1) -> void:
		for s in steps:
			var a := lerpf(a0, a1, float(s) / steps)
			var b := lerpf(a0, a1, float(s + 1) / steps)
			var out := pt((a + b) * 0.5, 1.0, 0.0)
			quad(pt(a, r0, h0), pt(b, r0, h0), pt(b, r1, h1), pt(a, r1, h1), col, Vector3.UP if face == 0 else out * face)

	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		for axis in 3:
			for side in [-1.0, 1.0]:
				var nrm := Vector3.ZERO
				nrm[axis] = side
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var w := Vector3.ZERO
				w[(axis + 2) % 3] = 1.0
				var mid := nrm * h
				var pts: Array = []
				for e in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					pts.append(xf * (mid + u * h * e.x + w * h * e.y))
				quad(pts[0], pts[1], pts[2], pts[3], col, xf.basis * nrm)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


func _w(x: float, y: float, z: float) -> Vector3:
	return at + Vector3(x, y, z)


## The deck it stands on, the steps up at either end, and the frame that holds it up.
func _stage() -> void:
	var red := Color(0.5, 0.08, 0.1)
	_block(_w(0, DECK_Y * 0.5, 0), Vector3(11.0, DECK_Y, 7.0), red)
	_box(_w(0, DECK_Y + 0.01, 0), Vector3(10.6, 0.04, 6.6), Color(0.2, 0.2, 0.22))
	_box(_w(0, DECK_Y - 0.12, -3.52), Vector3(11.0, 0.14, 0.06), GOLD)
	for side in [-1.0, 1.0]:
		_stairs(_w(side * 8.1, 0, -2.4), _w(side * 5.48, DECK_Y + 0.02, -2.4), 1.8)
		_rail(_w(side * 5.45, DECK_Y, -1.4), _w(side * 5.45, DECK_Y, 3.45))
		# The legs of the frame, and the lamp on the corner of the deck.
		_block(_w(side * 3.9, 5.9, 3.0), Vector3(0.4, 9.4, 0.4), Color(0.16, 0.16, 0.18))
		_box(_w(side * 5.42, DECK_Y + 1.1, -3.42), Vector3(0.12, 2.2, 0.12), Color(0.16, 0.16, 0.18))
		_glow(_w(side * 5.42, DECK_Y + 2.35, -3.42), Vector3(0.34, 0.34, 0.34), Color(1.0, 0.9, 0.6))
	_rail(_w(-5.45, DECK_Y, -3.45), _w(5.45, DECK_Y, -3.45))
	_rail(_w(-5.45, DECK_Y, 3.45), _w(5.45, DECK_Y, 3.45))
	# What the wheel leans back on, and something solid where it is.
	var back := HUB - Basis(Vector3.RIGHT, -TILT) * Vector3(0, 0.6, 0)
	_box(at + back, Vector3(5.6, 0.3, 5.6), Color(0.14, 0.14, 0.16), Vector3(-TILT, 0, 0))
	_box(_w(0, 3.2, 3.0), Vector3(8.0, 0.3, 0.3), Color(0.16, 0.16, 0.18))
	_collider(at + HUB, Vector3(R_OUT * 2.0, 1.3, R_OUT * 2.0), Vector3(-TILT, 0, 0))
	# The name over the top, to be read from the sand and from the promenade behind.
	_block(_w(0, 10.6, 3.0), Vector3(8.6, 1.5, 0.3), red)
	_sign("ROLETA", _w(0, 10.6, 2.83), 260, GOLD, PI)
	_sign("ROLETA", _w(0, 10.6, 3.17), 260, GOLD)
	for k in 18:
		var x := -4.25 + k * 0.5
		for y in [9.78, 11.42]:
			_glow(_w(x, y, 2.84), Vector3(0.16, 0.16, 0.08), [Color(1.0, 0.9, 0.5), Color(1.0, 0.35, 0.3)][k % 2])
	for k in 3:
		var l := OmniLight3D.new()
		l.position = _w(-3.4 + k * 3.4, 6.0, -3.6)
		l.light_color = Color(1.0, 0.88, 0.7)
		l.light_energy = 2.2
		l.omni_range = 11.0
		l.shadow_enabled = false
		add_child(l)
	# Where the bets are taken, down on the sand in front.
	desk = _w(0, 0, -6.0)
	_block(_w(0, 0.55, -5.0), Vector3(2.6, 1.1, 0.7), red)
	_box(_w(0, 1.12, -5.0), Vector3(2.8, 0.06, 0.9), Color(0.05, 0.35, 0.16))
	_glow(_w(0, 0.6, -5.36), Vector3(2.2, 0.5, 0.03), Color(0.1, 0.09, 0.08))
	_sign("APOSTAS  [F]", _w(0, 0.6, -5.39), 70, GOLD, PI)
	Places.add_use(&"wheel", desk, "bet on the roleta")


## Steps from a up to b, `wide` across, running along x either way.
func _stairs(a: Vector3, b: Vector3, wide: float) -> void:
	var run := Vector2(b.x - a.x, b.y - a.y)
	var up := Vector3(-run.y, run.x, 0).normalized()
	if up.y < 0.0:
		up = -up
	_collider((a + b) * 0.5 - up * 0.12, Vector3(run.length() + 0.3, 0.24, wide), Vector3(0, 0, atan2(run.y, run.x)))
	var n := int(run.y / 0.24)
	for k in n:
		var u := (k + 0.5) / n
		_box(Vector3(lerpf(a.x, b.x, u), lerpf(a.y, b.y, u) - 0.02, a.z), Vector3(absf(run.x) / n + 0.04, 0.26, wide), Color(0.45, 0.08, 0.1).darkened(0.15 if k % 2 == 0 else 0.0))


func _rail(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var along := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(a.distance_to(b), 0.9, 0.08) if along else Vector3(0.08, 0.9, a.distance_to(b))
	_collider(mid + Vector3(0, 0.45, 0), size)
	_box(mid + Vector3(0, 0.9, 0), Vector3(size.x, 0.06, size.z), BRASS)
	for k in 2:
		_box(mid + Vector3(0, 0.3 + k * 0.3, 0), Vector3(size.x, 0.03, size.z * 0.5), BRASS.darkened(0.2))


func _build_wheel() -> void:
	_wheel = Node3D.new()
	_wheel.transform = Transform3D(Basis(Vector3.RIGHT, -TILT), at + HUB)
	add_child(_wheel)
	var wood := _vertex_mat()
	wood.roughness = 0.55

	# The bowl: what does not turn.
	var bowl := Shape.new()
	var segs := POCKETS * 2
	bowl.band(0.0, -0.4, R_OUT, -0.4, 0.0, TAU, MAHOGANY.darkened(0.5), 0, segs)
	bowl.band(R_OUT, -0.4, R_OUT, H_RIM, 0.0, TAU, MAHOGANY.darkened(0.25), 1, segs)
	bowl.band(R_RIM, H_RIM, R_OUT, H_RIM, 0.0, TAU, MAHOGANY, 0, segs)
	bowl.band(R_RIM, H_TRACK, R_RIM, H_RIM, 0.0, TAU, MAHOGANY.lightened(0.12), -1, segs)
	bowl.band(R_APRON, H_TRACK, R_RIM, H_TRACK, 0.0, TAU, Color(0.2, 0.09, 0.05), 0, segs)
	for s in segs:
		bowl.band(R_ENTRY, H_NUM, R_APRON, H_TRACK, s * TAU / segs, (s + 1) * TAU / segs, MAHOGANY.lightened(0.2 if s % 2 == 0 else 0.26))
	# Brass studs on the slope, turned alternately along it and across it.
	for k in 8:
		var a := (k + 0.5) * TAU / 8.0
		var out := spot(a, 1.0, 0.0)
		var slope := (out * (R_APRON - R_ENTRY) + Vector3.UP * (H_TRACK - H_NUM)).normalized()
		var across := Vector3.UP.cross(out).normalized()
		var normal := across.cross(slope)
		if normal.y < 0.0:
			normal = -normal
		var long := slope if k % 2 == 0 else across
		var mid := spot(a, (R_ENTRY + R_APRON) * 0.5, (H_NUM + H_TRACK) * 0.5) + normal * 0.03
		bowl.box(Transform3D(Basis(long, normal, long.cross(normal)), mid), Vector3(0.46, 0.09, 0.11), BRASS)
	_part(_wheel, bowl.mesh(), wood)

	# The rotor: numbers, pockets, the cone and the turret, turning together.
	_rotor = Node3D.new()
	_wheel.add_child(_rotor)
	var rotor := Shape.new()
	for s in POCKETS:
		var n: int = ORDER[s]
		var a0 := -(s + 0.5) * STEP
		var a1 := -(s - 0.5) * STEP
		var col := colour_of(n)
		rotor.band(R_STEP, H_NUM, R_ENTRY, H_NUM, a0, a1, col)
		rotor.band(R_CONE, 0.0, R_STEP, 0.0, a0, a1, col.darkened(0.45))
		rotor.band(R_STEP, 0.0, R_STEP, H_NUM, a0, a1, CHROME, -1)
		rotor.band(R_CONE, 0.0, R_CONE, 0.14, a0, a1, CHROME, 1)
		rotor.band(R_HUB, 0.62, R_CONE, 0.14, a0, a1, MAHOGANY.lightened(0.1 if s % 2 == 0 else 0.22))
		# The fret between this pocket and the next.
		var out := spot(a0, 1.0, 0.0)
		rotor.box(Transform3D(Basis(out, Vector3.UP, out.cross(Vector3.UP)), spot(a0, (R_CONE + R_STEP) * 0.5, 0.07)), Vector3(R_STEP - R_CONE, 0.14, 0.035), CHROME)
	rotor.band(R_HUB, 0.62, R_HUB, 1.05, 0.0, TAU, BRASS.darkened(0.15), 1, 12)
	rotor.band(0.0, 1.05, R_HUB, 1.05, 0.0, TAU, BRASS, 0, 12)
	# Four arms on the turret, one of them red, so the turning shows from a long way off.
	for k in 4:
		var a := k * PI * 0.5
		var out := spot(a, 1.0, 0.0)
		rotor.box(Transform3D(Basis(out, Vector3.UP, out.cross(Vector3.UP)), spot(a, 0.75, 0.95)), Vector3(1.1, 0.1, 0.12), RED if k == 0 else BRASS)
		rotor.box(Transform3D(Basis(), spot(a, 1.3, 0.95)), Vector3(0.24, 0.24, 0.24), RED if k == 0 else BRASS)
	_part(_rotor, rotor.mesh(), wood)

	# The numbers, standing the right way up as they come over the top.
	var digits: Array = []
	for s in POCKETS:
		var text := TextMesh.new()
		text.text = str(ORDER[s])
		text.font = UI.font(true)
		text.font_size = 60
		text.pixel_size = 0.0055
		text.depth = 0.02
		var out := spot(-s * STEP, 1.0, 0.0)
		digits.append([text, Transform3D(Basis(out.cross(Vector3.UP), out, Vector3.UP), spot(-s * STEP, R_NUM, H_NUM + 0.012)), Color.WHITE])
	var white := _vertex_mat()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_part(_rotor, compose(digits), white).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var ivory := _mat(Color(0.98, 0.97, 0.92), 0.25)
	ivory.emission_enabled = true
	ivory.emission = Color(0.45, 0.45, 0.42)
	_bola = _part(_wheel, _ball(BALL_R, -1.0, 14), ivory)
	_bola.position = TURRET_TOP

	# Bulbs round the rim.
	_bulbs = MultiMesh.new()
	_bulbs.transform_format = MultiMesh.TRANSFORM_3D
	_bulbs.use_colors = true
	_bulbs.mesh = _ball(0.11, -1.0, 6)
	_bulbs.instance_count = 40
	for k in 40:
		_bulbs.set_instance_transform(k, Transform3D(Basis(), spot(k * TAU / 40.0, (R_RIM + R_OUT) * 0.5, H_RIM + 0.06)))
		_bulbs.set_instance_color(k, GOLD)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _bulbs
	mmi.material_override = _lit
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wheel.add_child(mmi)

	_roll = Sfx.emitter("roll", -80.0, 9.0, 110.0)
	_wheel.add_child(_roll)


func _part(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## The two boards on the deck: what is going on now, and what has come up lately.
func _boards() -> void:
	for side in [-1.0, 1.0]:
		_block(_w(side * 4.75, DECK_Y + 1.0, -1.9), Vector3(0.16, 2.0, 0.16), Color(0.16, 0.16, 0.18))
		_box(_w(side * 4.75, DECK_Y + 3.2, -1.9), Vector3(1.5, 2.5, 0.12), Color(0.07, 0.07, 0.08))
		_glow(_w(side * 4.75, DECK_Y + 4.5, -1.9), Vector3(1.6, 0.08, 0.14), GOLD)
		_glow(_w(side * 4.75, DECK_Y + 1.9, -1.9), Vector3(1.6, 0.08, 0.14), GOLD)
	_status = _sign("", _w(-4.75, DECK_Y + 3.2, -1.97), 90, GOLD, PI)
	_status.font = UI.font(true)
	_status.line_spacing = -8.0
	_sign("ÚLTIMOS", _w(4.75, DECK_Y + 4.2, -1.97), 44, GOLD, PI).font = UI.font(true)
	for k in 8:
		var l := _sign("", _w(5.07 - (k % 2) * 0.64, DECK_Y + 3.72 - (k >> 1) * 0.5, -1.97), 76, Color.WHITE, PI)
		l.font = UI.font(true)
		_tote.append(l)


## Three rows of people on the sand looking up at it, the man who calls the bets, and two
## of the casino's own to keep an eye on the takings.
func _people() -> void:
	_first = Places.stands.size()
	var centre := _w(0, 0, -2.0)
	var look := _w(0, 3.0, 1.0)
	var k := 0
	for row in 3:
		var r := 5.4 + row * 1.3
		var n := int(r * deg_to_rad(124.0) / 0.92)
		for j in n:
			var a := deg_to_rad(-62.0) + deg_to_rad(124.0) * (j + 0.5) / n
			var p := centre + Vector3(sin(a) * r, 0, -cos(a) * r)
			p += Vector3(Activities.h01(k, 11) - 0.5, 0, Activities.h01(k, 12) - 0.5) * 0.36
			k += 1
			# An aisle down the middle to the desk.
			if absf(p.x - at.x) < 1.3:
				continue
			var who := "malandro" if Activities.h01(k, 13) < 0.06 else ("local" if Activities.h01(k, 13) < 0.2 else "")
			Places.add_stand(p, Kit.face(look - p) + (Activities.h01(k, 14) - 0.5) * 0.3, Kit.STAND, who)
	_watchers = Places.stands.size() - _first
	_caller = Places.stands.size()
	Places.add_stand(_w(0.2, 0, -4.2), Kit.face(Vector3.FORWARD), Kit.STAND, "mafia")
	for side in [-1.0, 1.0]:
		Places.add_stand(_w(side * 6.6, 0, -4.4), Kit.face(Vector3(-side * 0.4, 0, -1)), Kit.STAND, "seguranca")


# --- every peer: the wheel turning ---

func reset() -> void:
	results = PackedInt32Array()
	my_bets = []
	my_round = -1
	hot_round = -1
	_bets.clear()
	_bet_round = -1
	_settled = -1
	_last.clear()
	_was_round = -1
	_shown_tote = -2


func _process(delta: float) -> void:
	if multiplayer.is_server() and MatchState.running and not MatchState.ended:
		_srv_tick()
	# Its own clock, eased toward the match's so a correction from the host never jerks it.
	var want: float = Layout.sea_t
	var jumped := absf(want - _t) > 1.0
	_t = want if jumped else _t + delta + (want - _t) * minf(1.0, 3.0 * delta)
	var seed_value := MatchState.seed_value
	var ph := phase_at(_t)
	var r: int = ph[0]
	var tr := _t - r * ROUND
	var number := result_of(r)
	_rotor.rotation.y = rotor_angle(seed_value, _t)
	_bola.position = ball_at(seed_value, r, number, result_of(r - 1), _t)
	if not jumped and r == _was_round:
		_sounds(seed_value, r, number, tr)
	else:
		_roll.volume_db = -80.0
	_was_round = r
	_was_tr = tr
	_bulb_t -= delta
	if _bulb_t <= 0.0:
		_bulb_t = 0.08
		_light(ph, tr, number)
		_show(ph, number)
	_people_t -= delta
	if _people_t <= 0.0:
		_people_t = 0.2
		_direct()


func _crossed(tr: float, mark: float) -> bool:
	return _was_tr < mark and tr >= mark


## What it sounds like: the bell, the throw, the ball on the wood, and every fret it crosses.
func _sounds(seed_value: int, r: int, number: int, tr: float) -> void:
	var hub := at + HUB
	var me = Net.game.local_player if Net.game != null else null
	if not playable(r) or me == null or me.global_position.distance_to(hub) > 130.0:
		_roll.volume_db = -80.0
		return
	if _crossed(tr, T_OPEN):
		Sfx.play("bell", hub, 4.0)
	if number < 0:
		_roll.volume_db = -80.0
		return
	if _crossed(tr, T_LAUNCH):
		Sfx.play("throw", hub, 2.0)
	if _crossed(tr, T_LAUNCH + (T_FALL + T_DROP) * 0.5):
		Sfx.play("clink", _bola.global_position, 4.0, 0.8)
	for k in 4:
		if _crossed(tr, T_LAUNCH + T_DROP + [0.0, 0.3, 0.55, 0.74][k] * T_SKIP):
			Sfx.play("tick", _bola.global_position, 5.0 - k, 0.55 + k * 0.05)
	if _crossed(tr, T_RESULT):
		Sfx.play("bell", hub, 6.0, 1.25)
	# (A beat later, by when word of a big win has got round.)
	if _crossed(tr, T_RESULT + 0.35):
		_react(r, number)
	var tau := tr - T_LAUNCH
	if tau < 0.0 or tau > T_REST:
		_roll.volume_db = -80.0
		return
	# The ball against the wheel: how many frets it has gone over, and how fast.
	var here := ball_state(seed_value, r, number, _t)
	var then := ball_state(seed_value, r, number, _t - 0.05)
	var turn := rotor_angle(seed_value, _t)
	var rate := absf((here.x - then.x) / 0.05 - TURN)
	var k := int(floorf((here.x - turn) / STEP))
	var now := Time.get_ticks_msec()
	if k != _tick_k and now - _tick_ms > 65:
		var fast := clampf(rate / 7.0, 0.0, 1.0)
		Sfx.play("tick", _bola.global_position, lerpf(1.0, -5.0, fast), lerpf(0.7, 1.3, fast))
		_tick_ms = now
	_tick_k = k
	var on_wood := clampf(1.0 - (tau - T_FALL) / (T_DROP - T_FALL), 0.0, 1.0) if tau > T_FALL else 1.0
	_roll.volume_db = lerpf(-30.0, 2.0, clampf(rate / 7.0, 0.0, 1.0) * on_wood) if on_wood > 0.02 else -80.0
	_roll.pitch_scale = lerpf(0.6, 1.4, clampf(rate / 7.0, 0.0, 1.0))


## The number is called: what the people watching make of it, to the ear.
func _react(r: int, number: int) -> void:
	var where := _w(0, 1.5, -8.0)
	if hot_round == r:
		Sfx.play("cheer", where, 8.0)
		Net.game.fx.confetti(_w(0, 3.0, -5.5), 40, 4.0)
	elif number == 0:
		Sfx.play("cheer", where, 3.0, 0.55)
	else:
		Sfx.play("cheer", where, 3.0)
		Sfx.play("cheer", where + Vector3(2, 0, 0), 0.0, 0.6)


## The bulbs round the rim: a slow chase while bets are open, red and quick as they close,
## following the ball while it runs, and all of them in the winning colour once it stops.
func _light(ph: Array, tr: float, number: int) -> void:
	var off := Color(0.25, 0.2, 0.1)
	for k in 40:
		var c := off
		match ph[1]:
			OPEN:
				if ph[2] < 5.0:
					c = Color(1.0, 0.25, 0.2) if int(tr * 5.0) % 2 == k % 2 else off
				else:
					c = GOLD if (k + int(tr * 6.0)) % 5 == 0 else off
			SPIN:
				var d := absf(angle_difference(k * TAU / 40.0, atan2(-_bola.position.x, -_bola.position.z)))
				c = Color.WHITE.lerp(off, clampf(d / 0.6, 0.0, 1.0)) if number >= 0 else off
			PAID:
				# (Black does not show on a bulb: a black number flashes gold.)
				var win := colour_of(number).lightened(0.25) if number >= 0 and (number == 0 or is_red(number)) else GOLD
				c = win if (int(tr * 4.0) + k) % 2 == 0 else Color.WHITE
			SHUT:
				c = GOLD.darkened(0.4) if k % 2 == 0 else off
		_bulbs.set_instance_color(k, c)


## The two boards.
func _show(ph: Array, number: int) -> void:
	var text := ""
	var col := GOLD
	match ph[1]:
		OPEN:
			text = "APOSTAS\n%d" % ceili(ph[2])
			col = GOLD if ph[2] >= 5.0 else Color(1.0, 0.35, 0.25)
		SPIN:
			text = "NADA\nMAIS"
			col = Color(1.0, 0.35, 0.25)
		PAID:
			text = "%d\n%s" % [number, Casino.colour(number).to_upper()] if number >= 0 else ""
			col = Color.WHITE if number > 0 and not is_red(number) else colour_of(maxi(number, 0)).lightened(0.3)
		SHUT:
			text = "FECHADO"
			col = Color(0.6, 0.6, 0.6)
	if text != _shown:
		_shown = text
		_status.text = text
		_status.modulate = col
	# The board only learns a number once it has been called.
	var upto: int = ph[0] - (0 if ph[1] == PAID else 1)
	if upto != _shown_tote:
		_shown_tote = upto
		var k := 0
		var r := upto
		while k < _tote.size():
			var n := result_of(r) if r >= 0 else -1
			if r >= 0 and n < 0:
				r -= 1
				continue
			_tote[k].text = str(n) if n >= 0 else ""
			_tote[k].modulate = Color.WHITE if n > 0 and not is_red(n) else colour_of(maxi(n, 0)).lightened(0.35)
			k += 1
			r -= 1


## Tells everybody watching how to stand. Each of them is a moment behind the wheel, and
## each has a colour they are hoping for this round.
func _direct() -> void:
	var g = Net.game
	if g == null or g.crowd == null or g.crowd.count < Crowd.COUNT + _caller + 1:
		return
	var c = g.crowd
	for k in _watchers:
		var lag := 1.2 * Activities.h01(k, 77)
		var ph := phase_at(_t - lag)
		var r: int = ph[0]
		var tr := _t - lag - r * ROUND
		c.act_pose(Crowd.COUNT + _first + k, pose_for(k, ph, tr, result_of(r), hot_round == r), false)
	var now := phase_at(_t)
	var calling: Array = [Kit.WAVE, Kit.POINT, Kit.TALK, Kit.WAVE] if now[1] == OPEN else ([Kit.LOOK, Kit.STAND] if now[1] == SPIN else [Kit.POINT, Kit.WORK, Kit.STAND])
	c.act_pose(Crowd.COUNT + _caller, calling[int(_t / 3.0) % calling.size()], false)


## How watcher k stands `tr` into round ph[0], which comes to `number`.
static func pose_for(k: int, ph: Array, tr: float, number: int, hot: bool) -> int:
	var r: int = ph[0]
	var poses: Array = IDLE_POSES
	var seg := int(tr / 5.0)
	match ph[1]:
		OPEN:
			if ph[2] < 3.0:
				poses = READY_POSES
				seg = 9
		SPIN:
			if number >= 0 and tr > T_LAUNCH + T_FALL:
				poses = TENSE_POSES
				seg = 11
			elif number >= 0:
				poses = WATCH_POSES
				seg = 10 + int(tr / 4.0)
		PAID:
			if number >= 0:
				# Most have a colour; the rest are only here to watch.
				var side := Activities.h01(k * 13 + 5, r)
				var won := number > 0 and side < 0.9 and (side < 0.45) == is_red(number)
				if hot and Activities.h01(k, r + 3) < 0.85:
					won = true
				poses = WON_POSES if won else LOST_POSES
				seg = 20 + int((tr - T_RESULT) / 2.6)
	return poses[int(Activities.h01(k * 31 + seg * 7 + 3, r) * poses.size()) % poses.size()]


# --- bets ---

## A bet as it reads on the slip.
static func bet_text(b: Array) -> String:
	var what: String = Casino.BETS[b[0]][0]
	if b[0] == 6:
		what = "%d-%d" % [b[1] * 12 + 1, b[1] * 12 + 12]
	elif b[0] == 7:
		what = "Nº %d" % b[1]
	return "R$%d %s" % [b[2], what]


@rpc("authority", "call_remote", "reliable")
func cl_spin(r: int, number: int) -> void:
	while results.size() <= r:
		results.append(-1)
	results[r] = number


## Everything that has come up so far, for somebody who has just walked in.
@rpc("authority", "call_remote", "reliable")
func cl_sync(res: PackedInt32Array) -> void:
	results = res
	_shown_tote = -2


@rpc("authority", "call_remote", "reliable")
func cl_bets(r: int, bets: Array) -> void:
	my_round = r
	my_bets = bets


@rpc("authority", "call_remote", "reliable")
func cl_note(text: String) -> void:
	Net.game.hud.game_result(text)


@rpc("authority", "call_remote", "reliable")
func cl_paid(_r: int, number: int, stake: int, back: int) -> void:
	var net := back - stake
	Net.game.hud.wheel_result("%d %s   %sR$%d" % [number, Casino.colour(number).to_upper(), "+" if net >= 0 else "-", absi(net)], net > 0)


@rpc("authority", "call_remote", "reliable")
func cl_hot(r: int, pname: String, net: int) -> void:
	hot_round = r
	Net.game.hud.toast("%s took R$%d off the roleta" % [pname, net])


@rpc("any_peer", "call_remote", "reliable")
func srv_bet(kind: int, n: int, amount: int) -> void:
	var g = Net.game
	var pid := Net.sender()
	var now := Time.get_ticks_msec()
	if now - _last.get(pid, 0) < 150:
		return
	_last[pid] = now
	var p = g.players.get(pid)
	if p == null or not p.at_large() or not MatchState.running or MatchState.ended:
		return
	var ph := phase_at(MatchState.time)
	var r: int = ph[0]
	if ph[1] == SHUT:
		g.send(pid, "cl_note", ["The wheel is shut for the night."], self)
		return
	if ph[1] != OPEN:
		g.send(pid, "cl_note", ["Nada mais!  No more bets."], self)
		return
	var off: Vector3 = p.global_position - at
	if Vector2(off.x, off.z).length() > BET_REACH:
		return
	if kind < 0 or kind >= Casino.BETS.size() or (kind == 6 and (n < 0 or n > 2)) or (kind == 7 and (n < 0 or n > 36)) or not Casino.STAKES.has(amount):
		return
	if MatchState.time < g.casino._banned.get(pid, 0.0):
		g.send(pid, "cl_note", ["Not you. The house has not forgotten."], self)
		return
	if p.st.money < amount:
		g.send(pid, "cl_note", ["You have not got R$%d." % amount], self)
		return
	if _bet_round != r:
		_srv_settle()
		_bets.clear()
		_bet_round = r
	var mine: Array = _bets.get(pid, [])
	var staked := 0
	for b in mine:
		staked += b[2]
	if mine.size() >= MAX_BETS or staked + amount > MAX_STAKE:
		g.send(pid, "cl_note", ["That is the table limit: %d bets, R$%d a spin." % [MAX_BETS, MAX_STAKE]], self)
		return
	mine.append([kind, n if kind >= 6 else 0, amount])
	_bets[pid] = mine
	p.st.money -= amount
	g.casino.bank += amount
	g.push_state(p)
	g.send(pid, "cl_bets", [r, mine.duplicate(true)], self)


## Somebody who leaves with money on the table leaves it there.
func srv_left(pid: int) -> void:
	_bets.erase(pid)
	_last.erase(pid)


func _srv_tick() -> void:
	var t := MatchState.time
	var r := int(floorf(t / ROUND))
	var tr := t - r * ROUND
	# A round that got left behind (a stall, a clock put forward) is still seen through.
	if _bet_round >= 0 and _bet_round < r:
		_srv_settle()
	if tr >= T_OPEN and playable(r):
		_srv_draw(r)
	if tr >= T_RESULT and _bet_round == r:
		_srv_settle()


func _srv_draw(r: int) -> void:
	if result_of(r) >= 0:
		return
	var number := _force if _force >= 0 else randi_range(0, 36)
	_force = -1
	Net.game.bcast("cl_spin", [r, number], self)


## Pays out the round the bets are on, once.
func _srv_settle() -> void:
	var r := _bet_round
	if r < 0 or _settled == r:
		return
	_settled = r
	_srv_draw(r)
	var g = Net.game
	var number := result_of(r)
	for pid in _bets:
		var stake := 0
		var back := 0
		for b in _bets[pid]:
			stake += b[2]
			if Casino.wins(b[0], b[1], number):
				back += b[2] * Casino.BETS[b[0]][1]
		g.casino.bank -= back
		var p = g.players.get(pid)
		if p == null:
			continue
		p.st.money += back
		g.push_state(p)
		g.send(pid, "cl_paid", [r, number, stake, back], self)
		if back > 0:
			g.send(pid, "cl_sound", ["cash", p.global_position])
		if back - stake >= HOT_WIN:
			g.bcast("cl_hot", [r, p.pname, back - stake], self)
	_bets.clear()
