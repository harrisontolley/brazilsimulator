extends RefCounted
## Poses one player's body from script and hands the result to the character shader.
##
## The crowd is posed statelessly in the shader, which is cheap but can only cross-fade two
## fixed poses. A player changes what they are doing several times a second, so here every
## joint chases a target pose and the stride keeps its own clock: a hop reads as take-off,
## rise, hang, fall and landing, and nothing snaps when one move interrupts another.
##
## A pose is 24 floats laid out as the shader's rig0..rig5:
## arm_l xyz, spread | arm_r xyz, lean | leg_l xy, leg_r xy | head xy, rise, pitch | brow, shift, squash, roll |
## twist, bend, tilt, sway
##
## Swimming is its own little repertoire, chosen by speed and by whether the head is under:
## treading water, breaststroke, a front crawl when sprinting, and below the surface a long
## pull-and-glide that points wherever the swimmer is heading.

enum { GROUND, AIR, SLIDE, WALLRUN, DIVE, RIDE, CROUCH, SWIM }  # Player.MV_*
enum { ALIVE, DEAD, OUT }
enum { HOP, DOUBLE, WALL }

const N := 24
const SPREAD := 3
const ARM_R := 4
const LEAN := 7
const LEG_L := 8
const LEG_R := 10
const HEAD := 12
const RISE := 14
const PITCH := 15
const BROW := 16
const SHIFT := 17
const SQUASH := 18
const ROLL := 19
## Chest turned about the spine, toward the body's own left.
const TWIST := 20
## Chest tipped sideways over the hips.
const BEND := 21
## Head on one side.
const TILT := 22
## Hips swung out sideways over feet that stay where they are.
const SWAY := 23
## Vertical speed that reads as a full-strength jump.
const JUMP_V := 5.6
const LAND_TIME := 0.24

static var K_RISE := key(Vector3(1.5, 0.3, 1.0), Vector3(-0.8, 0.3, 0.5), Vector2(1.25, 1.6), Vector2(-0.55, 0.3), 0.0, 0.15, Vector2(-0.15, 0))
static var K_APEX := key(Vector3(0.5, 1.3, 0.6), Vector3(0.5, 1.3, 0.6), Vector2(0.9, 1.5), Vector2(0.5, 1.2), 0.08, 0.05)
static var K_FALL := key(Vector3(0.2, 2.1, 0.3), Vector3(0.2, 2.1, 0.3), Vector2(0.35, 0.25), Vector2(-0.15, 0.45), 0.12, -0.08, Vector2(0.2, 0))
static var K_TUCK := key(Vector3(0.9, 0.2, 1.8), Vector3(0.9, 0.2, 1.8), Vector2(1.5, 2.0), Vector2(1.5, 2.0), 0.0, 0.4, Vector2(0.3, 0))
static var K_SLIDE := key(Vector3(-0.5, 0.5, 0.3), Vector3(0.4, 0.9, 0.5), Vector2(0.3, 0.1), Vector2(0.9, 1.2), 0.0, 0.4, Vector2(0.6, 0), 0.0, 1.0)
static var K_DIVE := key(Vector3(2.9, 0.15, 0.1), Vector3(2.9, 0.15, 0.1), Vector2(-0.1, 0.15), Vector2(-0.25, 0.4), 0.0, 0.0, Vector2(-0.5, 0), 0.25, -1.25, 0.5)
static var K_RIDE := key(Vector3(1.15, 0.12, 0.25), Vector3(1.15, 0.12, 0.25), Vector2(1.0, 1.35), Vector2(1.0, 1.35), 0.32, 0.3, Vector2(-0.25, 0), 0.08)
static var K_DEAD := key(Vector3(0, 2.4, 0.3), Vector3(0, 1.3, 0.6), Vector2(0, 0.2), Vector2(0, 0.6), 0.25, 0.0, Vector2(0, 0.9), 0.0, -PI / 2.0)
static var K_OUT := key(Vector3(0, 1.5, 0.3), Vector3(0, 0.7, 0.9), Vector2(0, 0.2), Vector2(0, 0.6), 0.25, 0.0, Vector2(0, 0.9), 0.0, PI / 2.0)

# Swimming, arms reaching ahead and legs trailing: where each stroke starts from and comes back to.
const ARM_REACH := Vector3(2.9, 0.08, 0.05)
const LEG_TRAIL := Vector2(-0.12, 0.1)

## Where the stride is, in radians. Advances with ground covered, not with time.
var phase := 0.0
## How deep in water the legs are while walking, 0 dry to 1 chest deep. Set before update().
var wade := 0.0
## How far to move the whole body up so a swimmer lies where the water is, for the owner to apply.
var lift := 0.0
## Where the stroke is, in radians: one turn is one full pull.
var stroke := 0.0
## Goes true for the frame a swimming arm enters the water, for whoever makes the splash.
var catch := false
## The whole pose for this frame from somewhere else (an emote), or empty to get on as usual.
## Set before update().
var given := PackedFloat32Array()

var _under := false
var _surf_t := 9.0
var _plunge := 0.0
var _lift_to := 0.0
var _cycles := 0

var _cur := PackedFloat32Array()
var _out := PackedFloat32Array()
var _mode := GROUND
var _mode_t := 1.0
var _state := ALIVE
var _given := false
var _lead := false
var _vy := 0.0
var _t := 0.0
var _land_t := 9.0
var _land_k := 0.0
var _off_t := 9.0
var _tuck_t := 9.0


static func key(arm_l: Vector3, arm_r: Vector3, leg_l: Vector2, leg_r: Vector2, spread := 0.0, lean := 0.0, head := Vector2.ZERO, rise := 0.0, pitch := 0.0, shift := 0.0) -> PackedFloat32Array:
	return PackedFloat32Array([arm_l.x, arm_l.y, arm_l.z, spread, arm_r.x, arm_r.y, arm_r.z, lean, leg_l.x, leg_l.y, leg_r.x, leg_r.y, head.x, head.y, rise, pitch, 0.0, shift, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _init() -> void:
	_cur = _stand(0.0)
	_out = _cur.duplicate()


## A jump of some kind just started. A hop straight off a landing counts as both.
func jump(kind: int) -> void:
	if kind == DOUBLE:
		_tuck_t = 0.0
		return
	if kind == HOP and _mode == AIR and _mode_t > 0.1:
		land(-_vy)
	_lead = not _lead
	_off_t = 0.0


## Feet met the ground at `impact` m/s.
func land(impact: float) -> void:
	_land_t = 0.0
	_land_k = clampf(impact / 9.0, 0.25, 1.0)


## Advances the pose. `turn` is yaw rate, `aim` camera pitch (up positive), `side` the wall's
## side while wall running, `held` the Kit.HELD_* in hand, `aiming` whether sights are up.
func update(delta: float, mode: int, state: int, spd: float, vy: float, turn: float, aim: float, side: float, held: int, aiming: bool) -> void:
	_t += delta
	var told := not given.is_empty() and state == ALIVE and mode == GROUND
	if told != _given:
		# Into a dance or out of one flows like any other change of mind.
		_given = told
		_mode_t = 0.0
	if mode != _mode or state != _state:
		if _mode == AIR and mode != AIR and mode != DIVE and mode != RIDE and mode != SWIM and state == ALIVE:
			land(-_vy)
		if mode == SWIM:
			# Going in hard or head first: hold the dive's line under the water for a moment.
			_plunge = 1.0 if _mode == DIVE or _vy < -3.5 else 0.0
			_under = side > 0.0
			_surf_t = 9.0
		_mode = mode
		_state = state
		_mode_t = 0.0
	_mode_t += delta
	_land_t += delta
	_off_t += delta
	_tuck_t += delta
	_surf_t += delta
	_plunge = maxf(0.0, _plunge - delta / 0.75)
	_vy = vy
	catch = false
	_lift_to = 0.0
	phase = fposmod(phase + TAU * spd / lerpf(1.6, 3.0, smoothstep(1.0, 8.0, spd)) * delta, TAU * 64.0)

	var to: PackedFloat32Array
	var upright := false
	if mode == SWIM and state != ALIVE:
		# Face down and drifting.
		to = K_DEAD.duplicate()
		to[PITCH] = -1.5
		to[SHIFT] = 0.85
		_lift_to = 0.36
	elif state == DEAD:
		to = K_DEAD
	elif state == OUT:
		to = K_OUT
	elif told:
		to = given
	else:
		match mode:
			AIR:
				to = _air(vy)
				upright = true
			SLIDE:
				to = K_SLIDE
			DIVE:
				to = K_DIVE
			RIDE:
				to = K_RIDE
			CROUCH:
				to = _crouch(spd)
				upright = true
			SWIM:
				to = _swim(delta, spd, vy, side > 0.0)
			WALLRUN:
				to = _gait(7.0)
				to[1 if side < 0.0 else ARM_R + 1] = 1.4
				upright = true
			_:
				to = _gait(spd)
				upright = true

	# Chase the target: loosely just after a change so it flows, tightly once settled so a
	# fast stride is not smoothed away.
	var rate := 7.0 if state != ALIVE else lerpf(13.0, 42.0, clampf(_mode_t / 0.25, 0.0, 1.0))
	var k := 1.0 - exp(-rate * delta)
	for i in N:
		if i == 0 or i == ARM_R:
			# The shoulders turn the short way round: a crawling arm goes over the top, not back.
			_cur[i] = wrapf(to[i] + wrapf(_cur[i] - to[i], -PI, PI) * (1.0 - k), -PI, PI)
		else:
			_cur[i] = lerpf(_cur[i], to[i], k)
	lift = lerpf(lift, _lift_to, 1.0 - exp(-9.0 * delta))

	for i in N:
		_out[i] = _cur[i]
	if state != ALIVE:
		return
	# Landing: the knees take it, then spring back.
	var land_k := _land_k * (1.0 - smoothstep(0.0, LAND_TIME, _land_t)) * smoothstep(0.0, 0.04, _land_t)
	if upright:
		_out[LEG_L] += 0.4 * land_k
		_out[LEG_L + 1] += 0.85 * land_k
		_out[LEG_R] += 0.4 * land_k
		_out[LEG_R + 1] += 0.85 * land_k
		_out[RISE] -= 0.15 * land_k
		_out[LEAN] += 0.16 * land_k
		_out[SQUASH] = 0.12 * land_k - 0.07 * (1.0 - smoothstep(0.0, 0.16, _off_t))
		# Head and shoulders follow the eyes and lead into a turn.
		_out[HEAD] -= aim * 0.55
		_out[HEAD + 1] += clampf(turn * 0.07, -0.4, 0.4)
		_out[LEAN] -= aim * 0.14
		if held >= 5 and held <= 8:
			# Something that takes both hands: one on the grip, one out under the barrel.
			_out[ARM_R] = 1.45 + aim * 0.9
			_out[ARM_R + 1] = 0.0
			_out[ARM_R + 2] = 0.05
			_out[0] = 1.4 + aim * 0.9
			_out[1] = -0.5
			_out[2] = 0.3
			_out[LEAN] += 0.08 if aiming else 0.0
		elif held >= 2 and held <= 4:
			_out[ARM_R] = 1.45 + aim * 0.9
			_out[ARM_R + 1] = 0.0
			_out[ARM_R + 2] = 0.05
			if aiming:
				_out[0] = 1.25 + aim * 0.9
				_out[1] = -0.35
				_out[2] = 0.5
		elif held == 1 or held >= 9:
			_out[ARM_R] = 0.55
			_out[ARM_R + 1] = 0.15
			_out[ARM_R + 2] = 1.0


## Writes the pose to a [body, outline] material pair from Kit.rig_materials().
func apply(mats: Array) -> void:
	for m in mats:
		for r in N / 4:
			m.set_shader_parameter("rig%d" % r, Vector4(_out[r * 4], _out[r * 4 + 1], _out[r * 4 + 2], _out[r * 4 + 3]))


func _stand(t: float) -> PackedFloat32Array:
	var sway := sin(t * 1.3) * 0.06
	return key(Vector3(sway, 0.07, 0.12), Vector3(-sway, 0.07, 0.12), Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, Vector2(0, sin(t * 0.5) * 0.3), sin(t * 2.0) * 0.006)


## Standing, walking and running are one stride that grows with speed.
func _gait(spd: float) -> PackedFloat32Array:
	var q := _stand(_t)
	var w := smoothstep(0.15, 1.0, spd)
	if w <= 0.0:
		return q
	var r := smoothstep(3.8, 6.4, spd)
	var s := sin(phase)
	var c := cos(phase)
	var amp := lerpf(0.45, 0.8, r) * w
	var knee := lerpf(0.6, 1.2, r) * w
	var arm := lerpf(0.4, 0.9, r) * w
	var elbow := lerpf(0.12, lerpf(0.25, 1.3, r), w)
	q[0] = -s * arm
	q[2] = elbow
	q[ARM_R] = s * arm
	q[ARM_R + 2] = elbow
	q[LEG_L] = s * amp
	q[LEG_L + 1] = 0.1 * w + knee * maxf(0.0, c)
	q[LEG_R] = -s * amp
	q[LEG_R + 1] = 0.1 * w + knee * maxf(0.0, -c)
	q[LEAN] = lerpf(0.05, 0.22, r) * w
	q[HEAD] = sin(phase * 2.0) * 0.03 * w
	q[HEAD + 1] *= 1.0 - w
	q[RISE] = -0.5 * (1.0 - cos(s * amp)) * lerpf(1.0, 0.4, r)
	if wade > 0.0:
		# Pushing through water: knees high, arms out wide for balance, leaning into it.
		q[1] += 0.5 * wade
		q[ARM_R + 1] += 0.5 * wade
		q[2] += 0.35 * wade
		q[ARM_R + 2] += 0.35 * wade
		q[LEG_L] += 0.25 * wade * maxf(0.0, c)
		q[LEG_R] += 0.25 * wade * maxf(0.0, -c)
		q[LEG_L + 1] += 0.45 * wade * maxf(0.0, c)
		q[LEG_R + 1] += 0.45 * wade * maxf(0.0, -c)
		q[LEAN] += 0.1 * wade
	return q


## Airborne: driven up off one knee, hanging tucked at the top, reaching for the ground on
## the way down. A double jump balls up and kicks out.
func _air(vy: float) -> PackedFloat32Array:
	var v := clampf(vy / JUMP_V, -1.0, 1.0)
	var q := _mix(K_APEX, K_RISE if v > 0.0 else K_FALL, absf(v))
	if v < 0.0:
		# Windmilling a little the longer the drop.
		q[1] += sin(_t * 11.0) * 0.14 * -v
		q[ARM_R + 1] -= sin(_t * 11.0) * 0.14 * -v
	var tuck := 1.0 - smoothstep(0.05, 0.38, _tuck_t)
	if tuck > 0.0:
		q = _mix(q, K_TUCK, tuck)
	if _lead:
		_mirror(q)
	return q


## How far through the stretch a..b of a cycle u is, eased at both ends.
static func _seg(u: float, a: float, b: float) -> float:
	return smoothstep(a, b, u)


## In the water. On top: treading, breaststroke, or a crawl when sprinting. Underneath: a
## long pull and glide, laid along whichever way the body is travelling.
func _swim(delta: float, spd: float, vy: float, under: bool) -> PackedFloat32Array:
	if under != _under:
		_under = under
		if not under:
			_surf_t = 0.0
	var go := Vector2(spd, vy).length() if under else spd
	var before := stroke
	stroke += TAU * (0.5 + go * 0.15) * delta
	if int(stroke / PI) != int(before / PI):
		_cycles += 1
		catch = go > 0.6
	var q: PackedFloat32Array
	if under:
		q = _swim_under(go, spd, vy)
	else:
		var still := _tread()
		var breast := _breast()
		q = _mix(still, breast, smoothstep(0.35, 1.3, spd))
		var fast := smoothstep(3.0, 3.7, spd)
		if fast > 0.0:
			q = _mix(q, _crawl(), fast)
		# Coming up: head thrown back, a heave out of the water for the breath.
		var up := (1.0 - smoothstep(0.0, 0.55, _surf_t)) * smoothstep(0.0, 0.05, _surf_t)
		q[HEAD] -= 0.55 * up
		q[PITCH] *= 1.0 - 0.45 * up
		q[1] += 0.5 * up
		q[ARM_R + 1] += 0.5 * up
	# Lay the body where the water is: its middle on the swimmer's spot, at the right depth.
	var flat := absf(sin(q[PITCH]))
	q[SHIFT] = 0.85 * sin(-q[PITCH])
	_lift_to = (0.42 if under else lerpf(0.2, 0.4, flat)) - 0.66 * cos(q[PITCH]) - 0.13 * flat
	return q


## Staying put: sculling hands, legs going like an egg beater, bobbing with the breath.
func _tread() -> PackedFloat32Array:
	var a := _t * 3.3
	var b := _t * 4.6
	return key(Vector3(0.5 + sin(a) * 0.3, 0.95 + cos(a) * 0.22, 0.5 + sin(a + 1.0) * 0.3),
			Vector3(0.5 + sin(a + PI) * 0.3, 0.95 + cos(a + PI) * 0.22, 0.5 + sin(a + PI + 1.0) * 0.3),
			Vector2(0.4 + sin(b) * 0.5, 0.75 + cos(b) * 0.45), Vector2(0.4 - sin(b) * 0.5, 0.75 - cos(b) * 0.45),
			0.24, 0.06, Vector2(-0.2, sin(_t * 0.6) * 0.25), sin(_t * 2.3) * 0.03, -0.1)


## Breaststroke: sweep out and round, tuck, shoot the arms forward as the legs whip shut, glide.
func _breast() -> PackedFloat32Array:
	var u := fposmod(stroke / TAU, 1.0)
	var out := _seg(u, 0.0, 0.3)
	var tuck := _seg(u, 0.28, 0.46)
	var reach := _seg(u, 0.46, 0.68)
	var arm := ARM_REACH.lerp(Vector3(1.5, 1.2, 0.45), out).lerp(Vector3(1.25, 0.2, 2.2), tuck).lerp(ARM_REACH, reach)
	var bend := _seg(u, 0.26, 0.5)
	var whip := _seg(u, 0.5, 0.64)
	var close := _seg(u, 0.62, 0.84)
	var leg := LEG_TRAIL.lerp(Vector2(0.8, 1.75), bend).lerp(Vector2(-0.05, 0.05), whip)
	var spread := lerpf(lerpf(lerpf(0.05, 0.42, bend), 0.6, whip), 0.05, close)
	# The head comes up to breathe on the pull and goes back down into the glide.
	var breathe := _seg(u, 0.08, 0.28) * (1.0 - _seg(u, 0.42, 0.62))
	var q := key(arm, arm, leg, leg, spread, 0.0, Vector2(lerpf(-0.3, -0.95, breathe), 0), 0.0, lerpf(-1.42, -1.2, breathe))
	q[RISE] = 0.04 * breathe
	return q


## Front crawl: each arm reaches, pulls down the length of the body and comes back over the
## top, the body rolling to let it, the legs fluttering three beats to the stroke.
func _crawl() -> PackedFloat32Array:
	var l := _crawl_arm(stroke)
	var r := _crawl_arm(stroke + PI)
	var kick := stroke * 3.0
	var q := key(l, r,
			Vector2(sin(kick) * 0.3, 0.12 + maxf(0.0, -cos(kick)) * 0.3), Vector2(-sin(kick) * 0.3, 0.12 + maxf(0.0, cos(kick)) * 0.3),
			0.03, 0.0, Vector2.ZERO, 0.0, -1.46)
	# A breath to the side as the right arm clears the water.
	var air := smoothstep(0.35, 0.9, maxf(0.0, -sin(stroke + PI)))
	q[HEAD] = lerpf(-0.12, -0.25, air)
	q[HEAD + 1] = -0.95 * air
	q[ROLL] = 0.42 * sin(stroke + 0.5)
	return q


static func _crawl_arm(ph: float) -> Vector3:
	var s := sin(ph)
	var over := maxf(0.0, -s)
	return Vector3(wrapf(2.9 - fposmod(ph, TAU), -PI, PI), 0.1 + 0.3 * over, 0.55 * maxf(0.0, s) + 1.25 * over)


## Under the surface. Moving: arms sweep from full stretch right back to the thighs, a long
## glide with them at the sides, then they slide up the chest and out again; flat out it is
## all legs, arms locked ahead. Hanging still, it is a slow scull.
func _swim_under(go: float, spd: float, vy: float) -> PackedFloat32Array:
	var u := fposmod(stroke / TAU, 1.0)
	var out := _seg(u, 0.0, 0.22)
	var back := _seg(u, 0.2, 0.42)
	var tuck := _seg(u, 0.66, 0.82)
	var reach := _seg(u, 0.8, 1.0)
	var arm := ARM_REACH.lerp(Vector3(1.7, 1.25, 0.3), out).lerp(Vector3(0.12, 0.22, 0.08), back).lerp(Vector3(1.2, 0.12, 2.3), tuck).lerp(ARM_REACH, reach)
	var kick := stroke * 2.0
	# One big frog kick as the arms come forward, a loose flutter the rest of the time.
	var bend := _seg(u, 0.62, 0.8)
	var whip := _seg(u, 0.8, 0.94)
	var leg_l := Vector2(sin(kick) * 0.22, 0.15 + maxf(0.0, -cos(kick)) * 0.2).lerp(Vector2(0.7, 1.6), bend).lerp(LEG_TRAIL, whip)
	var leg_r := Vector2(-sin(kick) * 0.22, 0.15 + maxf(0.0, cos(kick)) * 0.2).lerp(Vector2(0.7, 1.6), bend).lerp(LEG_TRAIL, whip)
	var spread := lerpf(lerpf(0.04, 0.4, bend), 0.06, whip)
	var q := key(arm, arm, leg_l, leg_r, spread, 0.0, Vector2(-0.5, 0), 0.0, 0.0)
	# Sprinting, or still carrying the speed of a dive: a spear, driven from the hips.
	var dart := maxf(smoothstep(3.3, 3.9, go), _plunge)
	if dart > 0.0:
		var beat := stroke * 4.0
		var streak := key(Vector3(2.95, -0.08, 0.0), Vector3(2.95, -0.08, 0.0),
				Vector2(sin(beat) * 0.34, 0.1 + maxf(0.0, -cos(beat)) * 0.35), Vector2(-sin(beat) * 0.34, 0.1 + maxf(0.0, cos(beat)) * 0.35),
				0.02, sin(beat * 0.5) * 0.08, Vector2(-0.15, 0), 0.0, 0.0)
		q = _mix(q, streak, dart)
	var moving := maxf(smoothstep(0.3, 1.1, go), _plunge)
	if moving < 1.0:
		var a := _t * 2.1
		var hang := key(Vector3(0.7 + sin(a) * 0.25, 1.05 + cos(a) * 0.2, 0.4), Vector3(0.7 + sin(a + PI) * 0.25, 1.05 + cos(a + PI) * 0.2, 0.4),
				Vector2(0.3 + sin(a * 1.3) * 0.35, 0.6 + cos(a * 1.3) * 0.3), Vector2(0.3 - sin(a * 1.3) * 0.35, 0.6 - cos(a * 1.3) * 0.3),
				0.2, 0.05, Vector2(-0.1, 0), 0.0, -0.3)
		q = _mix(hang, q, moving)
	# Nose first, whichever way that is: level, climbing or going straight down.
	var heading := -PI / 2.0 + atan2(vy, maxf(spd, 0.05))
	q[PITCH] = lerpf(-0.3, heading, moving)
	return q


func _crouch(spd: float) -> PackedFloat32Array:
	var w := minf(spd, 1.0)
	var s := sin(phase * 1.6) * w
	var c := cos(phase * 1.6)
	return key(Vector3(0.5 - s * 0.3, 0.15, 1.1), Vector3(0.5 + s * 0.3, 0.15, 1.1),
			Vector2(1.0 + s * 0.4, 1.7 + maxf(0.0, c) * 0.3 * w), Vector2(1.0 - s * 0.4, 1.7 + maxf(0.0, -c) * 0.3 * w),
			0.0, 0.5, Vector2(-0.35, 0), -0.33)


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var q := a.duplicate()
	for i in N:
		q[i] = lerpf(a[i], b[i], k)
	for i in [0, ARM_R]:
		q[i] = lerp_angle(a[i], b[i], k)
	return q


## Swaps left and right, so the other leg leads.
static func _mirror(q: PackedFloat32Array) -> void:
	for i in 3:
		var t := q[i]
		q[i] = q[ARM_R + i]
		q[ARM_R + i] = t
	for i in 2:
		var t := q[LEG_L + i]
		q[LEG_L + i] = q[LEG_R + i]
		q[LEG_R + i] = t
