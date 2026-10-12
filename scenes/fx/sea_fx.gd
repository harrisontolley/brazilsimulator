extends Node3D
## What moving through water throws about: spray, bubbles, rings and trails of foam.
##
## Nobody is told about any of it. Every peer watches where the swimmers and the jet skis
## are and makes its own splashes, so a busy sea costs nothing on the wire. Like the combat
## effects, each kind is a pool of instances the shader moves; the oldest slot gets reused.

const Layout := preload("res://scenes/world/layout.gd")

const DROPS := 700
const RINGS := 160

var _drops: MultiMesh
var _rings: MultiMesh
var _drop_n := 0
var _ring_n := 0
var _drop_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _t := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 6
	ball.rings = 3
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = load("res://shaders/sea_spray.gdshader")
	_drops = _pool(ball, _drop_mat, DROPS, true)
	var flat := PlaneMesh.new()
	flat.size = Vector2(2, 2)
	flat.subdivide_width = 3
	flat.subdivide_depth = 3
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://shaders/sea_ring.gdshader")
	Layout.sea_params(_ring_mat)
	_rings = _pool(flat, _ring_mat, RINGS, false)


func _pool(mesh: Mesh, mat: ShaderMaterial, n: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-400, -30, -500), Vector3(800, 60, 600))
	add_child(mmi)
	return mm


func _process(delta: float) -> void:
	_t += delta
	_drop_mat.set_shader_parameter("now", _t)
	_ring_mat.set_shader_parameter("now", _t)
	_ring_mat.set_shader_parameter("sea_time", Layout.sea_t)
	_ring_mat.set_shader_parameter("sea_storm", Layout.sea_storm)


func _drop(at: Vector3, vel: Vector3, life: float, size: float, kind: float) -> void:
	_drops.set_instance_transform(_drop_n, Transform3D(Basis(), at))
	_drops.set_instance_color(_drop_n, Color(vel.x, vel.y, vel.z, 1.0))
	_drops.set_instance_custom_data(_drop_n, Color(_t, life, size, kind))
	_drop_n = (_drop_n + 1) % DROPS


## A ring spreading on the surface from `at`, ending up `size` metres across.
func ring(at: Vector3, size: float, life := 1.3) -> void:
	_mark(at, size, life, 0.0)


## A patch of foam left lying on the water.
func foam(at: Vector3, size: float, life := 2.6) -> void:
	_mark(at, size, life, 1.0)


func _mark(at: Vector3, size: float, life: float, kind: float) -> void:
	_rings.set_instance_transform(_ring_n, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(at.x, Layout.SEA_Y, at.z)))
	_rings.set_instance_custom_data(_ring_n, Color(_t, life, size * 0.5, kind))
	_ring_n = (_ring_n + 1) % RINGS


## Something hit the water at `at`. `size` runs from a hand slapping it (0.2) to a body
## dropped from a height (1.0) and beyond; `along` is which way it was travelling.
func splash(at: Vector3, size: float, along := Vector3.ZERO) -> void:
	at.y = Layout.wave_y(at.x, at.z)
	var n := int(clampf(size, 0.15, 1.6) * 26.0)
	for k in n:
		var a := _rng.randf() * TAU
		var out := _rng.randf_range(0.4, 2.2) * sqrt(size)
		var v := Vector3(cos(a) * out, _rng.randf_range(1.6, 4.6) * sqrt(size), sin(a) * out) + along * 0.35
		_drop(at + Vector3(cos(a), 0, sin(a)) * 0.15 * size, v, _rng.randf_range(0.5, 1.0), _rng.randf_range(0.04, 0.11) * (0.7 + 0.5 * size), 0.0)
	ring(at, 1.2 + 2.6 * size, 0.9 + 0.7 * size)
	if size > 0.45:
		ring(at, 0.8 + 1.6 * size, 0.6 + 0.4 * size)
		foam(at, 1.0 + 1.8 * size, 1.6 + size)


## Spray kicked back off something moving fast along the surface.
func spray(at: Vector3, back: Vector3, amount: float) -> void:
	at.y = Layout.wave_y(at.x, at.z)
	for k in int(amount):
		var v := back * _rng.randf_range(0.25, 0.6) + Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(1.5, 4.2), _rng.randf_range(-1.6, 1.6))
		_drop(at + Vector3(_rng.randf_range(-0.3, 0.3), 0.05, _rng.randf_range(-0.3, 0.3)), v, _rng.randf_range(0.4, 0.8), _rng.randf_range(0.05, 0.13), 0.0)


## Air let go under water.
func bubbles(at: Vector3, n: int, push := Vector3.ZERO) -> void:
	for k in n:
		var v := push + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.0, 0.6), _rng.randf_range(-0.5, 0.5))
		var rise := maxf(Layout.wave_y(at.x, at.z) - at.y, 0.2)
		_drop(at + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.15, 0.15)), v, minf(rise / 0.9, 3.5), _rng.randf_range(0.03, 0.08), 1.0)
