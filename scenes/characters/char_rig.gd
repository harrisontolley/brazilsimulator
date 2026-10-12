extends RefCounted
## Poses one player's body from script and hands the result to the character shader.
##
## The crowd is posed statelessly in the shader, which is cheap but can only cross-fade two
## fixed poses. A player changes what they are doing several times a second, so here every
## joint chases a target pose and the stride keeps its own clock: a hop reads as take-off,
## rise, hang, fall and landing, and nothing snaps when one move interrupts another.
##
## A pose is 20 floats laid out as the shader's rig0..rig4:
## arm_l xyz, spread | arm_r xyz, lean | leg_l xy, leg_r xy | head xy, rise, pitch | brow, shift, squash, -

enum { GROUND, AIR, SLIDE, WALLRUN, DIVE, RIDE, CROUCH }  # Player.MV_*
enum { ALIVE, DEAD, OUT }
enum { HOP, DOUBLE, WALL }

const N := 20
const SPREAD := 3
const ARM_R := 4
const LEAN := 7
const LEG_L := 8
const LEG_R := 10
const HEAD := 12
const RISE := 14
const PITCH := 15
const BROW := 16
const SQUASH := 18
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

## Where the stride is, in radians. Advances with ground covered, not with time.
var phase := 0.0

var _cur := PackedFloat32Array()
var _out := PackedFloat32Array()
var _mode := GROUND
var _mode_t := 1.0
var _state := ALIVE
var _lead := false
var _vy := 0.0
var _t := 0.0
var _land_t := 9.0
var _land_k := 0.0
var _off_t := 9.0
var _tuck_t := 9.0


static func key(arm_l: Vector3, arm_r: Vector3, leg_l: Vector2, leg_r: Vector2, spread := 0.0, lean := 0.0, head := Vector2.ZERO, rise := 0.0, pitch := 0.0, shift := 0.0) -> PackedFloat32Array:
	return PackedFloat32Array([arm_l.x, arm_l.y, arm_l.z, spread, arm_r.x, arm_r.y, arm_r.z, lean, leg_l.x, leg_l.y, leg_r.x, leg_r.y, head.x, head.y, rise, pitch, 0.0, shift, 0.0, 0.0])


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
	if mode != _mode or state != _state:
		if _mode == AIR and mode != AIR and mode != DIVE and mode != RIDE and state == ALIVE:
			land(-_vy)
		_mode = mode
		_state = state
		_mode_t = 0.0
	_mode_t += delta
	_land_t += delta
	_off_t += delta
	_tuck_t += delta
	_vy = vy
	phase = fposmod(phase + TAU * spd / lerpf(1.6, 3.0, smoothstep(1.0, 8.0, spd)) * delta, TAU * 64.0)

	var to: PackedFloat32Array
	var upright := false
	if state == DEAD:
		to = K_DEAD
	elif state == OUT:
		to = K_OUT
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
		_cur[i] = lerpf(_cur[i], to[i], k)

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
		for r in 5:
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
