extends RefCounted
## What a player can do with their body for no reason at all: dances, gestures, and two that kill.
##
## An emote is a pose as a function of the time since it started, in the rig's own 24 floats
## (see char_rig.gd), so every machine that knows which emote and when it began draws the same
## frame. The showpieces are choreographed: key poses on the beat of their own tune, arrived at
## with a snap and a little overshoot, with a bounce laid over the top and the feet put back on
## the ground by plant() whatever came of all that. Hands are placed by where they should be, not by guessing at shoulder angles.
##
## Everything here is static and nothing here knows about players, sound or the network.

const CharRig := preload("res://scenes/characters/char_rig.gd")

enum { PASSINHO, FIO, TOMA_L, COSSACO, TRENZINHO, GARGALHADA, POU, SENTAR,
		TCHAU, PALMAS, DAB, CONTINENCIA, FACEPALM, FLEX, SHRUG, BICUDA, CHUPA, COUNT }

## Slices to a page of the wheel.
const PAGE := 8

## name: on the wheel. len: seconds, of the whole thing or of one turn of a loop. loop: goes
## round until stopped. bpm: the tune's and the feet's. sound: a looping Sfx stream. speed:
## metres a second it carries the dancer forward. join: others can fall in with it. kill: the
## moment, reach in metres and half-angle in radians of the blow. react: what onlookers make of it.
const LIST := [
	{"name": "PASSINHO", "len": 7.619, "loop": true, "bpm": 126.0, "sound": "em_passinho", "react": "dance"},
	{"name": "FIO DENTAL", "len": 2.0, "loop": true, "bpm": 120.0, "sound": "em_fio", "react": "dance"},
	{"name": "TOMA O L", "len": 1.714, "loop": true, "bpm": 140.0, "sound": "em_toma", "react": "laugh"},
	{"name": "COSSACO", "len": 1.6, "loop": true, "bpm": 150.0, "sound": "em_cossaco", "speed": 1.1, "join": true, "react": "dance"},
	{"name": "TRENZINHO", "len": 4.138, "loop": true, "bpm": 116.0, "sound": "em_trenzinho", "speed": 1.3, "join": true, "react": "dance"},
	{"name": "GARGALHADA", "len": 4.8, "loop": true, "react": "laugh"},
	{"name": "POU!", "len": 3.3, "kill": {"t": 1.72, "reach": 4.0, "arc": 0.3}, "react": "look"},
	{"name": "SENTAR", "len": 8.0, "loop": true, "react": "none"},
	{"name": "TCHAU", "len": 2.4, "react": "wave"},
	{"name": "PALMAS", "len": 3.0, "react": "clap"},
	{"name": "DAB", "len": 1.8, "react": "laugh"},
	{"name": "CONTINÊNCIA", "len": 2.2, "react": "look"},
	{"name": "FACEPALM", "len": 3.0, "react": "laugh"},
	{"name": "FLEX", "len": 3.4, "react": "look"},
	{"name": "SEI LÁ", "len": 1.8, "react": "none"},
	{"name": "BICUDA", "len": 2.0, "kill": {"t": 1.0, "reach": 1.9, "arc": 0.6, "knock": 9.0}, "react": "look"},
	{"name": "CHUPA", "len": 2.9, "react": "laugh", "show": 0.3},
]

const V2 := Vector2.ZERO
## An arm hanging easy.
const DOWN := Vector3(0.0, 0.07, 0.12)
const UPPER := 0.27
const FORE := 0.28
const THIGH := 0.35
const SHIN := 0.4
## How high a foot's joint sits when the sole is on the ground.
const SOLE := 0.05

# Joints as joints() lists them.
enum { J_HEAD, J_NECK, J_WAIST, J_SH_L, J_EL_L, J_HAND_L, J_SH_R, J_EL_R, J_HAND_R,
		J_HIP_L, J_KNEE_L, J_FOOT_L, J_HIP_R, J_KNEE_R, J_FOOT_R, J_COUNT }
## Pairs of joints that make the stick figure on the wheel.
const BONES := [J_NECK, J_WAIST, J_SH_L, J_SH_R, J_SH_L, J_EL_L, J_EL_L, J_HAND_L, J_SH_R, J_EL_R, J_EL_R, J_HAND_R,
		J_HIP_L, J_HIP_R, J_HIP_L, J_KNEE_L, J_KNEE_L, J_FOOT_L, J_HIP_R, J_KNEE_R, J_KNEE_R, J_FOOT_R]

static var _k := {}


static func has(id: int) -> bool:
	return id >= 0 and id < COUNT


static func info(id: int) -> Dictionary:
	return LIST[id] if has(id) else {}


## Whether `id` has run its course `t` seconds in. Loops never do.
static func over(id: int, t: float) -> bool:
	return not has(id) or (not LIST[id].get("loop", false) and t >= LIST[id].len)


## The body `t` seconds into emote `id`.
static func pose(id: int, t: float) -> PackedFloat32Array:
	if _k.is_empty():
		_make()
	t = maxf(t, 0.0)
	var q: PackedFloat32Array
	match id:
		PASSINHO: q = _passinho(t)
		FIO: q = _fio(t)
		TOMA_L: q = _toma(t)
		COSSACO: q = _cossaco(t)
		TRENZINHO: q = _trenzinho(t)
		GARGALHADA: q = _gargalhada(t)
		POU: q = _pou(t)
		SENTAR: q = _sentar(t)
		TCHAU: q = _tchau(t)
		PALMAS: q = _palmas(t)
		DAB: q = _line(_k.dab, [0.0, 0.22, 0.42, 1.25, 1.7], t, 1.0)
		CONTINENCIA: q = _line(_k.salute, [0.0, 0.25, 0.5, 1.6, 1.85, 2.15], t, 1.0)
		FACEPALM: q = _facepalm(t)
		FLEX: q = _flex(t)
		SHRUG: q = _shrug(t)
		BICUDA: q = _line(_k.bicuda, [0.0, 0.5, 0.9, 1.02, 1.35, 1.9], t, 1.0)
		CHUPA: q = _chupa(t)
		_: q = _k.stand.duplicate()
	# Until here RISE has only been how far off the ground the dancer means to be.
	for i in [2, CharRig.ARM_R + 2, CharRig.LEG_L + 1, CharRig.LEG_R + 1]:
		q[i] = maxf(q[i], 0.0)
	var hop := q[CharRig.RISE]
	plant(q)
	q[CharRig.RISE] += hop
	return q


## How far round the whole body has turned on its feet, in radians.
static func yaw(id: int, t: float) -> float:
	if id == PASSINHO:
		var b := fposmod(t * 126.0 / 60.0, 16.0)
		return TAU * _ease(clampf((b - 12.0) / 2.6, 0.0, 1.0), 0.0)
	if id == POU:
		# Side on, like a duellist.
		return -0.55 * (smoothstep(0.0, 0.5, t) - smoothstep(2.6, 3.2, t))
	return 0.0


# --- where the joints end up ---

## Every joint of a pose in the body's own space, feet at the origin and facing -Z: the same
## sums the shader does, for anything that needs to know where a hand or a foot is.
static func joints(q: PackedFloat32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(J_COUNT)
	var waist := Vector3(0.0, 0.82, 0.0)
	var slide := Vector3(-sin(q[CharRig.SWAY]) * (THIGH + SHIN), q[CharRig.RISE], q[CharRig.SHIFT])
	var chest := Basis(Vector3.RIGHT, -q[CharRig.LEAN]) * Basis(Vector3.BACK, q[CharRig.BEND]) * Basis(Vector3.UP, -q[CharRig.TWIST])
	var neck := Vector3(0.0, 1.4, 0.0)
	var head := Basis(Vector3.RIGHT, -q[CharRig.HEAD]) * Basis(Vector3.BACK, q[CharRig.TILT]) * Vector3(0.0, 0.18, 0.0)
	out[J_HEAD] = waist + chest * (neck + head - waist) + slide
	out[J_NECK] = waist + chest * (neck - waist) + slide
	out[J_WAIST] = waist + slide
	for side in [-1, 1]:
		var a: int = 0 if side < 0 else CharRig.ARM_R
		var sh := Vector3(side * 0.245, 1.3, 0.0)
		var up := _limb(q[a], side * q[a + 1], UPPER)
		var fore := _limb(q[a] + q[a + 2], side * q[a + 1], FORE)
		var j: int = J_SH_L if side < 0 else J_SH_R
		out[j] = waist + chest * (sh - waist) + slide
		out[j + 1] = waist + chest * (sh + up - waist) + slide
		out[j + 2] = waist + chest * (sh + up + fore - waist) + slide
		var l: int = CharRig.LEG_L if side < 0 else CharRig.LEG_R
		var out_by: float = q[CharRig.SWAY] + side * q[CharRig.SPREAD]
		var hip := Vector3(side * 0.095, 0.8, 0.0)
		var thigh := _limb(q[l], out_by, THIGH)
		var shin := _limb(q[l] - q[l + 1], out_by, SHIN)
		j = J_HIP_L if side < 0 else J_HIP_R
		out[j] = hip + slide
		out[j + 1] = hip + thigh + slide
		out[j + 2] = hip + thigh + shin + slide
	return out


## The pose as a flat figure seen from in front, in metres with up positive: for drawing.
static func stick(id: int, t: float) -> PackedVector2Array:
	var j := joints(pose(id, t))
	var turn := Basis(Vector3.UP, yaw(id, t))
	var out := PackedVector2Array()
	out.resize(J_COUNT)
	for i in J_COUNT:
		var p := turn * j[i]
		# Seen from the front, so their right is on our left.
		out[i] = Vector2(-p.x, p.y)
	return out


## A limb `length` long hanging from its joint, swung forward by `fwd` and out sideways by `out_by`.
static func _limb(fwd: float, out_by: float, length: float) -> Vector3:
	return Vector3(sin(out_by) * cos(fwd), -cos(out_by) * cos(fwd), -sin(fwd)) * length


## Shoulder and elbow angles that put a hand at `at`, a point in the chest's own space.
## `side` is -1 for the left arm. A hand above the shoulder gets there over the front unless
## `wide`, when the arm goes up sideways.
static func reach(side: int, at: Vector3, wide := false) -> Vector3:
	var rel := at - Vector3(side * 0.245, 1.3, 0.0)
	rel.x *= side
	var a := Vector2(rel.x, rel.y).length()
	if rel.y > 0.0 and not wide:
		a = -a
	var out_by := atan2(rel.x, -rel.y) if a >= 0.0 else atan2(-rel.x, rel.y)
	var b := -rel.z
	var d := clampf(Vector2(a, b).length(), absf(UPPER - FORE) + 0.01, UPPER + FORE - 0.002)
	var bend := acos(clampf((d * d - UPPER * UPPER - FORE * FORE) / (2.0 * UPPER * FORE), -1.0, 1.0))
	var fwd := atan2(b, a) - atan2(FORE * sin(bend), UPPER + FORE * cos(bend))
	return Vector3(wrapf(fwd, -PI, PI), out_by, bend)


## Moves the body up or down until its lower foot is on the ground.
static func plant(q: PackedFloat32Array) -> PackedFloat32Array:
	q[CharRig.RISE] = 0.0
	var j := joints(q)
	q[CharRig.RISE] = SOLE - minf(j[J_FOOT_L].y, j[J_FOOT_R].y)
	return q


# --- building and sampling ---

## A pose from its arms and legs; everything else by name in `o`.
static func _p(al: Vector3, ar: Vector3, ll := V2, lr := V2, o := {}) -> PackedFloat32Array:
	var q := CharRig.key(al, ar, ll, lr, o.get("spread", 0.0), o.get("lean", 0.0), o.get("head", V2), 0.0, 0.0, 0.0)
	q[CharRig.BROW] = o.get("brow", 0.0)
	q[CharRig.SQUASH] = o.get("squash", 0.0)
	q[CharRig.TWIST] = o.get("twist", 0.0)
	q[CharRig.BEND] = o.get("bend", 0.0)
	q[CharRig.TILT] = o.get("tilt", 0.0)
	q[CharRig.SWAY] = o.get("sway", 0.0)
	q[CharRig.SHIFT] = o.get("shift", 0.0)
	q[CharRig.RISE] = o.get("hop", 0.0)
	return q


## The same pose the other way round.
static func _flip(q: PackedFloat32Array) -> PackedFloat32Array:
	var m := q.duplicate()
	CharRig._mirror(m)
	for i in [CharRig.HEAD + 1, CharRig.TWIST, CharRig.BEND, CharRig.TILT, CharRig.SWAY]:
		m[i] = -m[i]
	return m


## 0..1 eased. `snap` 0 is a plain ease in and out; 1 gets there early, goes a touch past and
## settles, which is what makes a move land on the beat instead of drifting through it.
static func _ease(u: float, snap: float) -> float:
	var soft := u * u * (3.0 - 2.0 * u)
	if snap <= 0.0:
		return soft
	var w := minf(u / 0.6, 1.0)
	var past := sin(PI * maxf(0.0, u - 0.6) / 0.4)
	return lerpf(soft, w * w * w * (w * (w * 6.0 - 15.0) + 10.0) + 0.05 * past * past, snap)


## Key poses round a loop: keys[i] is struck at at[i], and the last entry of `at` is where it
## comes back round to keys[0].
static func _loop(keys: Array, at: Array, u: float, snap := 0.0) -> PackedFloat32Array:
	var n := keys.size()
	u = fposmod(u, at[n])
	for i in n:
		if u < at[i + 1]:
			return CharRig._mix(keys[i], keys[(i + 1) % n], _ease((u - at[i]) / (at[i + 1] - at[i]), snap))
	return keys[0].duplicate()


## Key poses played through once and held at either end.
static func _line(keys: Array, at: Array, u: float, snap := 0.0) -> PackedFloat32Array:
	var n := keys.size()
	if u <= at[0]:
		return keys[0].duplicate()
	for i in n - 1:
		if u < at[i + 1]:
			return CharRig._mix(keys[i], keys[i + 1], _ease((u - at[i]) / (at[i + 1] - at[i]), snap))
	return keys[n - 1].duplicate()


## The spring in the knees: up between beats, a little squashed as each one lands.
static func _bounce(q: PackedFloat32Array, beat: float, height: float) -> void:
	var s := absf(sin(beat * PI))
	q[CharRig.RISE] += height * s
	q[CharRig.SQUASH] += height * 0.5 * (1.0 - s) * (1.0 - s) - height * 0.25 * s


# --- the showpieces ---

## Four phrases of four beats: stamping with the fists pumping, pointing out to each side,
## arms waving overhead, then a turn on the spot that lands wide with the arms thrown out.
static func _passinho(t: float) -> PackedFloat32Array:
	var b := fposmod(t * 126.0 / 60.0, 16.0)
	var ph := int(b / 4.0)
	var q := _passinho_part(ph, b - ph * 4.0)
	var lb := b - ph * 4.0
	if lb < 0.35:
		q = CharRig._mix(_passinho_part((ph + 3) % 4, 4.0), q, _ease(lb / 0.35, 0.0))
	return q


static func _passinho_part(ph: int, b: float) -> PackedFloat32Array:
	var q: PackedFloat32Array
	match ph:
		0:
			q = _loop(_k.pa_stamp, [0.0, 0.5, 1.0], b, 1.0)
			_bounce(q, b * 2.0, 0.035)
		1:
			q = _loop(_k.pa_point, [0.0, 0.6, 1.0, 2.0, 2.6, 3.0, 4.0], b, 1.0)
			_bounce(q, b, 0.02)
		2:
			q = _loop(_k.pa_wave, [0.0, 1.0, 2.0], b, 0.0)
			_bounce(q, b, 0.05)
		_:
			q = _line(_k.pa_spin, [0.0, 0.5, 2.5, 2.95, 3.2, 3.75, 4.0], b, 1.0)
	return q


## Straight arms swung past the hips from one side to the other, twice a beat, the hips going
## the other way each time and every other swing passing one arm behind the back.
static func _fio(t: float) -> PackedFloat32Array:
	var b := t * 120.0 / 60.0 * 2.0
	var q := _loop(_k.fio, [0.0, 1.0, 2.0, 3.0, 4.0], b, 1.0)
	_bounce(q, b, 0.012)
	return q


## One hand making an L on the forehead while the legs gallop and the body rocks.
static func _toma(t: float) -> PackedFloat32Array:
	var b := t * 140.0 / 60.0
	var q := _loop(_k.toma, [0.0, 0.5, 1.0, 1.5, 2.0], b, 0.6)
	_bounce(q, b * 2.0, 0.07)
	# The free arm swings loose, a little behind the legs.
	q[1] += 0.12 * sin((b - 0.15) * TAU)
	q[CharRig.HEAD + 1] += 0.12 * sin(b * PI)
	return q


## Down on the haunches with the arms folded, each leg shot out in front in turn.
static func _cossaco(t: float) -> PackedFloat32Array:
	var b := t * 150.0 / 60.0
	var q := _loop(_k.cossaco, [0.0, 0.5, 1.0, 1.5, 2.0], b, 1.0)
	_bounce(q, b, 0.09)
	q[CharRig.HEAD + 1] += 0.1 * sin(b * PI * 0.5)
	return q


## Three steps and a kick, hands out for the hips of whoever is in front.
static func _trenzinho(t: float) -> PackedFloat32Array:
	var b := t * 116.0 / 60.0
	var q := _loop(_k.trem, [0.0, 1.0, 2.0, 3.0, 3.55, 4.0, 5.0, 6.0, 7.0, 7.55, 8.0], b, 0.7)
	_bounce(q, b, 0.04)
	return q


## Point, then fold up laughing with a hand slapping a knee, then rear back for more.
static func _gargalhada(t: float) -> PackedFloat32Array:
	var u := fposmod(t, 4.8)
	var q := _loop(_k.riso, [0.0, 0.3, 1.1, 1.5, 3.6, 4.1, 4.8], u, 0.8)
	# Shaking with it, hardest when doubled over.
	var bent := smoothstep(1.1, 1.5, u) * (1.0 - smoothstep(3.6, 4.1, u))
	var shake := sin(u * 34.0) * (0.25 + 0.75 * bent)
	q[CharRig.RISE] += 0.012 * shake
	q[CharRig.LEAN] += 0.035 * shake
	q[CharRig.HEAD] += 0.07 * sin(u * 34.0 + 1.0) * (0.3 + bent)
	# The slap.
	var slap := maxf(0.0, sin((u - 1.5) * TAU / 0.7)) * bent
	q[CharRig.ARM_R] += 0.5 * slap
	q[CharRig.ARM_R + 2] += 0.4 * slap
	q[CharRig.TILT] += 0.1 * sin(u * 2.6)
	return q


## Draw, sight along the finger, fire, blow the smoke off, put it away.
static func _pou(t: float) -> PackedFloat32Array:
	var q := _line(_k.pou, [0.0, 0.5, 1.7, 1.78, 2.05, 2.35, 2.75, 3.25], t, 1.0)
	if t > 0.5 and t < 1.7:
		# Taking aim: the hand is never quite still.
		q[CharRig.ARM_R] += 0.02 * sin(t * 5.0)
		q[CharRig.ARM_R + 1] += 0.015 * sin(t * 3.1)
	return q


## Down onto the ground with a knee drawn up, and then nothing much: looking about.
static func _sentar(t: float) -> PackedFloat32Array:
	var q := _line(_k.sentar, [0.0, 0.35, 0.75, 1.0], t, 0.5)
	var k := smoothstep(0.9, 1.4, t)
	q[CharRig.HEAD + 1] += k * (0.5 * sin(t * 0.55) + 0.2 * sin(t * 1.3))
	q[CharRig.HEAD] += k * 0.08 * sin(t * 0.8)
	q[CharRig.TILT] += k * 0.08 * sin(t * 0.4)
	q[CharRig.LEAN] += k * 0.02 * sin(t * 1.6)
	q[CharRig.LEG_R + 1] += k * 0.05 * sin(t * 1.1)
	# Landing on the seat.
	q[CharRig.SQUASH] += 0.1 * smoothstep(0.7, 0.78, t) * (1.0 - smoothstep(0.78, 1.05, t))
	return q


# --- the small ones ---

static func _tchau(t: float) -> PackedFloat32Array:
	var q := _line(_k.tchau, [0.0, 0.35, 2.0, 2.4], t, 1.0)
	var k := smoothstep(0.25, 0.4, t) * (1.0 - smoothstep(1.9, 2.1, t))
	q[CharRig.ARM_R + 1] += k * 0.3 * sin(t * 13.0)
	q[CharRig.ARM_R + 2] += k * 0.15 * sin(t * 13.0 + 0.8)
	return q


static func _palmas(t: float) -> PackedFloat32Array:
	var k := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(2.65, 3.0, t))
	# Hands apart, then together sharply, four times a second.
	var u := fposmod(t * 4.0, 1.0)
	var shut := 1.0 - smoothstep(0.0, 0.5, u) + smoothstep(0.78, 1.0, u)
	var q := CharRig._mix(_k.stand, CharRig._mix(_k.palmas[0], _k.palmas[1], shut), k)
	q[CharRig.HEAD] += k * 0.05 * shut
	q[CharRig.RISE] += k * 0.01 * shut
	return q


static func _facepalm(t: float) -> PackedFloat32Array:
	var q := _line(_k.facepalm, [0.0, 0.45, 2.5, 3.0], t, 0.4)
	var k := smoothstep(0.5, 0.9, t) * (1.0 - smoothstep(2.3, 2.6, t))
	# A slow shake of the head, taking the hand with it.
	q[CharRig.HEAD + 1] += k * 0.16 * sin((t - 0.6) * 4.2)
	q[CharRig.ARM_R + 1] += k * 0.05 * sin((t - 0.6) * 4.2)
	return q


static func _flex(t: float) -> PackedFloat32Array:
	var q := _line(_k.flex, [0.0, 0.3, 0.55, 1.5, 1.75, 2.05, 3.0, 3.4], t, 1.0)
	# Straining.
	var k := smoothstep(0.5, 0.7, t) * (1.0 - smoothstep(2.9, 3.1, t))
	q[CharRig.SQUASH] += k * 0.015 * sin(t * 40.0)
	q[2] += k * 0.05 * sin(t * 9.0)
	q[CharRig.ARM_R + 2] += k * 0.05 * sin(t * 9.0)
	return q


static func _shrug(t: float) -> PackedFloat32Array:
	return _line(_k.shrug, [0.0, 0.3, 1.2, 1.8], t, 1.0)


## Wrists crossed and chopped down at the lap, the hips sent out to meet them, five times
## over, at somebody. A cage fighter's opinion of another cage fighter.
static func _chupa(t: float) -> PackedFloat32Array:
	var k := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(2.5, 2.9, t))
	var q := CharRig._mix(_k.stand, _loop(_k.chupa, [0.0, 0.2, 0.44], t - 0.3, 1.0), k)
	q[CharRig.HEAD + 1] += k * 0.12 * sin(t * 2.4)
	return q


# --- key poses ---

static func _make() -> void:
	var stand := _p(DOWN, DOWN)
	_k.stand = stand

	# Passinho. Stamping: a knee up and the opposite fist, chest turned into it.
	var stamp := _p(Vector3(1.0, 0.15, 1.75), Vector3(-0.35, 0.2, 1.3), Vector2(0.95, 1.35), Vector2(0.0, 0.2),
			{"twist": -0.28, "lean": 0.1, "head": Vector2(0.0, 0.2), "bend": 0.05})
	_k.pa_stamp = [stamp, _flip(stamp)]
	# Pointing: weight on one hip, both arms thrown up and out over the other.
	var gather := _p(Vector3(0.5, 0.1, 1.9), Vector3(0.5, 0.1, 1.9), Vector2(0.45, 0.9), Vector2(0.45, 0.9), {"lean": 0.14, "head": Vector2(0.15, 0.0)})
	var point := _p(Vector3(0.0, 2.25, 0.1), reach(1, Vector3(-0.22, 1.6, -0.22)), Vector2(0.0, 0.05), Vector2(0.1, 0.35),
			{"spread": 0.3, "sway": -0.2, "bend": 0.2, "tilt": 0.15, "twist": 0.25, "head": Vector2(-0.2, 0.45)})
	var point_in := CharRig._mix(point, gather, 0.12)
	_k.pa_point = [point, point_in, gather, _flip(point), _flip(point_in), gather]
	# Waving: both arms overhead leaning one way, hips the other.
	var wave := _p(Vector3(2.75, 0.3, 0.3), Vector3(2.75, -0.25, 0.3), Vector2(0.15, 0.35), Vector2(0.15, 0.35),
			{"spread": 0.12, "sway": -0.16, "bend": 0.22, "tilt": 0.12, "head": Vector2(-0.15, 0.0)})
	_k.pa_wave = [wave, _flip(wave)]
	# The turn: gathered in on one leg, round, down wide, and up with the arms out.
	var tuck := _p(Vector3(0.7, 0.05, 2.1), Vector3(0.7, 0.05, 2.1), Vector2(0.0, 0.1), Vector2(0.9, 1.5), {"lean": 0.05, "hop": 0.03})
	var wide := _p(Vector3(0.1, 1.2, 0.2), Vector3(0.1, 1.2, 0.2), Vector2(0.55, 1.0), Vector2(0.55, 1.0),
			{"spread": 0.42, "lean": 0.2, "squash": 0.12, "head": Vector2(0.2, 0.0)})
	var tada := _p(Vector3(0.0, 2.3, 0.15), Vector3(0.0, 2.3, 0.15), Vector2(0.0, 0.05), Vector2(0.0, 0.05),
			{"spread": 0.3, "lean": -0.12, "head": Vector2(-0.3, 0.0), "hop": 0.02})
	_k.pa_spin = [_flip(wave), tuck, tuck, wide, tada, tada, stamp]

	# Fio dental. `to` is the side the arms go to; the hips go to the other.
	_k.fio = [_fio_key(1, 0), _fio_key(-1, -1), _fio_key(1, 1), _fio_key(-1, 0)]

	# Toma o L: the right hand at the forehead throughout, the legs kicking out in turn.
	var l_hand := reach(1, Vector3(0.07, 1.66, -0.2))
	var kick_l := _p(Vector3(-0.5, 0.25, 0.3), l_hand, Vector2(0.95, 0.1), Vector2(-0.1, 0.35),
			{"sway": 0.12, "bend": -0.1, "lean": -0.12, "tilt": -0.12, "head": Vector2(-0.1, 0.0)})
	var mid_l := _p(Vector3(0.2, 0.2, 0.5), l_hand, Vector2(0.3, 0.7), Vector2(0.1, 0.3), {"lean": 0.02})
	var kick_r := _p(Vector3(0.6, 0.25, 0.3), l_hand, Vector2(-0.1, 0.35), Vector2(0.95, 0.1),
			{"sway": -0.12, "bend": 0.1, "lean": -0.12, "tilt": 0.12, "head": Vector2(-0.1, 0.0)})
	var mid_r := _p(Vector3(0.0, 0.2, 0.5), l_hand, Vector2(0.1, 0.3), Vector2(0.3, 0.7), {"lean": 0.02})
	_k.toma = [kick_l, mid_l, kick_r, mid_r]

	# Cossaco: arms folded high, sat on one heel with the other leg out straight.
	var fold_l := reach(-1, Vector3(0.1, 1.27, -0.2))
	var fold_r := reach(1, Vector3(-0.1, 1.2, -0.23))
	var squat := _p(fold_l, fold_r, Vector2(1.5, 2.35), Vector2(1.5, 2.35), {"spread": 0.25, "lean": 0.1})
	var out_l := _p(fold_l, fold_r, Vector2(1.45, 0.05), Vector2(1.55, 2.45), {"spread": 0.12, "lean": -0.1, "head": Vector2(-0.1, 0.0)})
	_k.cossaco = [out_l, squat, _p(fold_l, fold_r, Vector2(1.55, 2.45), Vector2(1.45, 0.05), {"spread": 0.12, "lean": -0.1, "head": Vector2(-0.1, 0.0)}), squat]

	# Trenzinho: hands forward, stepping, and on the four a kick out with a tip of the head.
	var hold := Vector3(1.15, 0.1, 0.55)
	var step_l := _p(hold, hold, Vector2(0.5, 0.75), Vector2(-0.2, 0.2), {"lean": 0.08, "sway": 0.06, "twist": 0.08})
	var step_r := _flip(step_l)
	var kick := _p(Vector3(1.3, 0.75, 0.6), Vector3(1.3, 0.75, 0.6), Vector2(-0.05, 0.25), Vector2(1.0, 0.15),
			{"lean": -0.1, "sway": 0.16, "bend": 0.16, "tilt": 0.25, "head": Vector2(-0.1, -0.2), "hop": 0.04})
	_k.trem = [step_l, step_r, step_l, kick, step_r, step_r, step_l, step_r, _flip(kick), step_l]

	# Gargalhada.
	var jeer := _p(reach(-1, Vector3(-0.08, 1.0, -0.2)), Vector3(1.5, 0.05, 0.05), Vector2(0.0, 0.1), Vector2(0.15, 0.1),
			{"lean": -0.22, "head": Vector2(-0.3, 0.0), "spread": 0.12, "twist": 0.15})
	var jeer_up := _p(reach(-1, Vector3(-0.08, 1.0, -0.2)), Vector3(1.75, 0.05, 0.25), Vector2(0.0, 0.1), Vector2(0.15, 0.1),
			{"lean": -0.3, "head": Vector2(-0.5, 0.0), "spread": 0.12, "twist": 0.15})
	var bent := _p(reach(-1, Vector3(-0.05, 0.98, -0.2)), Vector3(0.75, 0.1, 0.35), Vector2(0.4, 0.75), Vector2(0.4, 0.75),
			{"lean": 0.75, "head": Vector2(0.35, 0.0), "spread": 0.16})
	var bent_low := _p(reach(-1, Vector3(-0.05, 0.98, -0.2)), Vector3(0.7, 0.1, 0.3), Vector2(0.5, 0.95), Vector2(0.5, 0.95),
			{"lean": 0.9, "head": Vector2(0.15, 0.0), "spread": 0.16})
	_k.riso = [jeer, jeer_up, jeer, bent, bent_low, jeer_up]

	# Pou!
	var hip := reach(-1, Vector3(-0.2, 0.9, 0.02))
	var aim := _p(hip, Vector3(1.55, 0.0, 0.03), Vector2(0.0, 0.1), Vector2(0.0, 0.1),
			{"spread": 0.2, "twist": 0.5, "head": Vector2(0.0, 0.0), "tilt": -0.14, "brow": 1.0})
	var bang := _p(hip, Vector3(2.15, 0.0, 0.5), Vector2(0.0, 0.2), Vector2(0.0, 0.2),
			{"spread": 0.2, "twist": 0.45, "lean": -0.16, "head": Vector2(-0.15, 0.0), "brow": 1.0, "squash": 0.05})
	var settle := _p(hip, Vector3(1.75, 0.0, 0.2), Vector2(0.0, 0.1), Vector2(0.0, 0.1), {"spread": 0.2, "twist": 0.5, "brow": 0.6})
	var blow := _p(hip, reach(1, Vector3(0.1, 1.52, -0.26)), Vector2(0.0, 0.05), Vector2(0.0, 0.05),
			{"spread": 0.2, "twist": 0.3, "head": Vector2(0.1, -0.2), "tilt": 0.08})
	_k.pou = [stand, aim, aim, bang, settle, blow, blow, stand]

	# Sentar: knees give, the seat goes down, one knee stays up with a hand on it.
	var crouch := _p(Vector3(0.6, 0.15, 0.8), Vector3(0.6, 0.15, 0.8), Vector2(1.3, 2.1), Vector2(1.3, 2.1), {"lean": 0.35, "spread": 0.1})
	var sat := _p(reach(-1, Vector3(-0.13, 0.86, -0.26)), reach(1, Vector3(0.13, 1.04, -0.31)), Vector2(1.35, 0.0), Vector2(2.2, 2.5),
			{"lean": 0.08, "spread": 0.1})
	_k.sentar = [stand, crouch, sat, sat]

	# Tchau.
	var hello := _p(Vector3(0.1, 0.12, 0.2), Vector3(0.0, 2.45, 0.35), V2, Vector2(0.0, 0.1),
			{"bend": 0.1, "sway": 0.06, "tilt": -0.14, "head": Vector2(-0.08, 0.0)})
	_k.tchau = [stand, hello, hello, stand]

	# Palmas: apart, together.
	_k.palmas = [
		_p(reach(-1, Vector3(-0.17, 1.24, -0.3)), reach(1, Vector3(0.17, 1.24, -0.3)), V2, V2, {"lean": 0.03}),
		_p(reach(-1, Vector3(-0.012, 1.25, -0.31)), reach(1, Vector3(0.012, 1.25, -0.31)), V2, V2, {"lean": 0.05}),
	]

	# Dab: a dip, then the face goes into one elbow and the other arm shoots out past it.
	var dip := _p(Vector3(0.4, 0.2, 1.0), Vector3(0.4, 0.2, 1.0), Vector2(0.3, 0.6), Vector2(0.3, 0.6), {"lean": 0.12})
	var dab := _p(Vector3(0.0, 2.2, 0.0), reach(1, Vector3(-0.2, 1.62, -0.2)), Vector2(0.0, 0.1), Vector2(0.2, 0.45),
			{"spread": 0.25, "bend": 0.28, "twist": 0.2, "sway": -0.12, "tilt": 0.3, "head": Vector2(0.45, -0.3), "lean": 0.08})
	_k.dab = [stand, dip, dab, dab, stand]

	# Continência.
	var tall := _p(Vector3(-0.05, 0.03, 0.0), Vector3(-0.05, 0.03, 0.0), V2, V2, {"lean": -0.04, "head": Vector2(-0.06, 0.0), "hop": 0.012})
	var salute := _p(Vector3(-0.05, 0.03, 0.0), reach(1, Vector3(0.13, 1.66, -0.16)), V2, V2, {"lean": -0.05, "head": Vector2(-0.08, 0.0), "brow": 0.4})
	_k.salute = [stand, tall, salute, salute, tall, stand]

	# Facepalm.
	var palm := _p(Vector3(0.05, 0.05, 0.1), reach(1, Vector3(0.03, 1.56, -0.24)), V2, Vector2(0.0, 0.1), {"lean": 0.14, "head": Vector2(0.4, 0.0)})
	_k.facepalm = [stand, palm, palm, stand]

	# Flex: everything clenched in front, then one fist to the sky.
	var breath := _p(Vector3(-0.2, 0.5, 0.4), Vector3(-0.2, 0.5, 0.4), Vector2(0.0, 0.1), Vector2(0.0, 0.1), {"lean": -0.08, "head": Vector2(-0.15, 0.0), "spread": 0.15})
	var crab := _p(reach(-1, Vector3(-0.1, 0.98, -0.28)), reach(1, Vector3(0.1, 0.98, -0.28)), Vector2(0.35, 0.7), Vector2(0.35, 0.7),
			{"lean": 0.3, "spread": 0.3, "head": Vector2(-0.1, 0.0), "brow": 1.0})
	var sky := _p(reach(-1, Vector3(-0.22, 0.92, 0.0)), Vector3(2.95, 0.2, 0.15), Vector2(0.0, 0.05), Vector2(0.15, 0.3),
			{"spread": 0.25, "twist": -0.3, "bend": -0.1, "sway": 0.1, "head": Vector2(-0.35, -0.2), "brow": 1.0})
	_k.flex = [stand, breath, crab, crab, breath, sky, sky, stand]

	# Sei lá.
	var shrug := _p(Vector3(0.35, 0.75, 1.5), Vector3(0.35, 0.75, 1.5), V2, V2, {"tilt": 0.22, "head": Vector2(-0.08, 0.15), "hop": 0.02, "lean": -0.03})
	_k.shrug = [stand, shrug, shrug, stand]

	# Bicuda: a step back to load the leg, then all of it through the ball of the foot.
	var load := _p(Vector3(0.9, 0.5, 0.5), Vector3(-0.6, 0.6, 0.4), Vector2(0.25, 0.45), Vector2(-0.9, 1.5),
			{"lean": 0.25, "twist": -0.3, "brow": 1.0, "head": Vector2(0.1, 0.0)})
	var load_deep := _p(Vector3(1.1, 0.5, 0.6), Vector3(-0.8, 0.7, 0.3), Vector2(0.3, 0.6), Vector2(-1.1, 1.8),
			{"lean": 0.3, "twist": -0.4, "brow": 1.0, "head": Vector2(0.1, 0.0)})
	var boot := _p(Vector3(-0.7, 0.7, 0.2), Vector3(0.6, 0.9, 0.3), Vector2(-0.1, 0.1), Vector2(1.75, 0.0),
			{"lean": -0.4, "twist": 0.3, "brow": 1.0, "head": Vector2(0.25, 0.0), "hop": 0.05})
	var follow := _p(Vector3(-0.4, 0.6, 0.3), Vector3(0.4, 0.7, 0.3), Vector2(-0.05, 0.15), Vector2(1.3, 0.5), {"lean": -0.2, "twist": 0.2, "brow": 0.5})
	_k.bicuda = [stand, load, load_deep, boot, follow, stand]

	# Chupa: hips back and the crossed wrists up at the belt, then both sent at each other.
	var cocked := _p(reach(-1, Vector3(0.05, 1.08, -0.27)), reach(1, Vector3(-0.05, 1.05, -0.29)), Vector2(0.4, 0.65), Vector2(0.4, 0.65),
			{"spread": 0.22, "lean": 0.2, "shift": 0.08, "head": Vector2(-0.1, 0.0), "brow": 1.0})
	var thrust := _p(reach(-1, Vector3(0.06, 0.9, -0.14)), reach(1, Vector3(-0.06, 0.88, -0.16)), Vector2(-0.22, 0.4), Vector2(-0.22, 0.4),
			{"spread": 0.22, "lean": -0.34, "shift": -0.2, "head": Vector2(0.12, 0.0), "brow": 1.0, "hop": 0.015})
	_k.chupa = [cocked, thrust]


## One swing of the floss. `to`: which side the arms are on. `back`: which arm, if either, has
## gone round behind.
static func _fio_key(to: int, back: int) -> PackedFloat32Array:
	var arms := [Vector3.ZERO, Vector3.ZERO]
	for i in 2:
		var side: int = -1 if i == 0 else 1
		var behind: bool = back == side
		# Out on its own side an arm just hangs away from the body; across it has to clear the hips.
		var across: bool = side != to
		arms[i] = Vector3(-0.55 if behind else (0.7 if across else 0.3), -0.55 if across else 0.85, 0.05)
	return _p(arms[0], arms[1], Vector2(0.12, 0.25), Vector2(0.12, 0.25),
			{"spread": 0.12, "sway": 0.27 * to, "bend": -0.14 * to, "twist": -0.2 * to, "tilt": 0.08 * to})
