extends Node3D
## Head pivot. Scroll steps between first person (arm length 0) and third person.

const STEPS := [0.0, 2.8, 5.0]
## How far back the view stands to watch its own body dance, at the least.
const WATCH := 3.6

var cam: Camera3D
var shake := 0.0
## One-off jolt that fades by itself, e.g. on taking a hit.
var kick := 0.0
var fov_target := 75.0
## Extra field of view from sheer speed, on top of fov_target.
var fov_boost := 0.0
## Camera lean, e.g. away from a wall being run along.
var roll_target := 0.0
## Head height above the feet; drops for a slide or dive.
var height_target := 1.3
## One-off sink on landing that springs back by itself.
var dip := 0.0
## Where the view sits away from the head, in the body's own axes: out of it, mostly.
var offset := Vector3.ZERO
## Eye to a scope: the view goes to the head whatever distance it was following at.
var scoped := false
## Standing back from the body and free to walk round it: the head has let go of the view.
var watching := false

var _arm: SpringArm3D
var _step := 0
var _t := 0.0
var _roll := 0.0
var _height := 1.3
var _recoil := Vector2.ZERO


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = 0.0
	_arm.collision_mask = 1
	_arm.margin = 0.2
	add_child(_arm)
	# SpringArm repositions its direct child, so shake goes on the camera below it.
	var holder := Node3D.new()
	_arm.add_child(holder)
	cam = Camera3D.new()
	cam.fov = fov_target
	cam.far = 3000.0
	holder.add_child(cam)
	cam.current = true


func zoom(dir: int) -> void:
	_step = clampi(_step + dir, 0, STEPS.size() - 1)


## Walks the view round the body while it is being watched.
func orbit(amount: float) -> void:
	rotation.y = wrapf(rotation.y + amount, -PI, PI)


func pitch(amount: float) -> void:
	rotation.x = clampf(rotation.x + amount, -1.45, 1.45)


## Kicks the view up by `up` radians and sideways by `side`; most of it settles back.
func recoil(up: float, side: float) -> void:
	rotation.x = clampf(rotation.x + up * 0.4, -1.45, 1.45)
	_recoil += Vector2(up * 0.6, side)


func first_person() -> bool:
	return _arm.spring_length < 0.5


func _process(delta: float) -> void:
	var back: float = maxf(STEPS[_step], WATCH) if watching else STEPS[_step]
	_arm.spring_length = lerpf(_arm.spring_length, 0.0 if scoped else back, minf(1.0, (30.0 if scoped else (7.0 if watching else 12.0)) * delta))
	if not watching:
		rotation.y = lerp_angle(rotation.y, 0.0, minf(1.0, 9.0 * delta))
	cam.fov = lerpf(cam.fov, fov_target + fov_boost, minf(1.0, 10.0 * delta))
	_height = lerpf(_height, height_target, minf(1.0, 14.0 * delta))
	position = Vector3(offset.x, _height + offset.y, offset.z)
	_roll = lerpf(_roll, roll_target, minf(1.0, 9.0 * delta))
	_t += delta
	kick = move_toward(kick, 0.0, 0.25 * delta)
	dip = move_toward(dip, 0.0, 1.1 * delta)
	cam.position.y = lerpf(cam.position.y, -dip, minf(1.0, 25.0 * delta))
	_recoil = _recoil.lerp(Vector2.ZERO, minf(1.0, 9.0 * delta))
	cam.rotation = Vector3(sin(_t * 13.0) + sin(_t * 7.3) * 0.5, cos(_t * 11.0) + sin(_t * 5.1) * 0.5, 0.0) * (shake + kick) + Vector3(_recoil.x, _recoil.y, _roll)
