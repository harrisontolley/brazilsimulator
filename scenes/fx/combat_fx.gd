extends Node3D
## Short-lived combat visuals: tracers, muzzle flashes and comic impact bursts.

var _star: ArrayMesh
var _beam: BoxMesh
var _mats := {}
var _shells := 0


func _ready() -> void:
	# Spiky comic-book burst, billboarded toward the camera.
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	pts.append(Vector3.ZERO)
	for k in 16:
		var r := 1.0 if k % 2 == 0 else 0.45
		pts.append(Vector3(cos(TAU * k / 16), sin(TAU * k / 16), 0.0) * r)
	for k in 16:
		idx.append(0)
		idx.append(1 + k)
		idx.append(1 + (k + 1) % 16)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_INDEX] = idx
	_star = ArrayMesh.new()
	_star.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_beam = BoxMesh.new()
	_beam.size = Vector3(0.06, 0.06, 1.0)


## A punch or shot from `from` landing at `to`. `hit` is whether it struck a character.
func strike(from: Vector3, to: Vector3, melee: bool, hit: bool) -> void:
	if melee:
		if hit:
			_burst(to, 0.6, Color(1.0, 0.85, 0.1))
			_burst(to, 0.32, Color(1.0, 1.0, 1.0))
		else:
			_burst(to, 0.16, Color(1.0, 1.0, 1.0))
		return
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var fwd := (to - from) / length
	var mi := _node(_beam, Color(1.0, 0.95, 0.5))
	var up := Vector3.RIGHT if absf(fwd.y) > 0.99 else Vector3.UP
	mi.transform = Transform3D(Basis.looking_at(fwd, up), (from + to) * 0.5)
	mi.scale = Vector3(1.0, 1.0, length)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.02, 0.02, length), 0.16)
	tw.tween_callback(mi.queue_free)

	_burst(from + fwd * 0.2, 0.3, Color(1.0, 0.8, 0.25))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.position = from
	add_child(light)
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.1)
	lt.tween_callback(light.queue_free)

	if hit:
		_burst(to, 0.42, Color(1.0, 0.15, 0.1))
		_burst(to, 0.2, Color(1.0, 1.0, 1.0))
	else:
		_burst(to, 0.2, Color(0.95, 0.9, 0.75))


## A puff of coloured paper: goals, parades, anything worth celebrating.
func confetti(at: Vector3, pieces := 28, spread := 3.0) -> void:
	var bit := BoxMesh.new()
	bit.size = Vector3(0.14, 0.14, 0.02)
	for k in pieces:
		var mi := _node(bit, Color.from_hsv(randf(), 0.85, 1.0))
		mi.position = at
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		var out := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)) * spread
		var tw := create_tween()
		tw.tween_property(mi, "position", at + out, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "position", at + out * 1.3 - Vector3(0, spread + 1.5, 0), 1.4)
		tw.parallel().tween_property(mi, "rotation", mi.rotation + Vector3(9, 7, 0), 1.4)
		tw.tween_callback(mi.queue_free)


## A firework shell bursting at `at`.
func firework(at: Vector3, color: Color) -> void:
	_burst(at, 9.0, color)
	_burst(at, 5.0, Color.WHITE)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = 60.0
	light.position = at
	add_child(light)
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.7)
	lt.tween_callback(light.queue_free)
	Sfx.play("firework", at, 8.0)


func _burst(p: Vector3, size: float, color: Color) -> void:
	var mi := _node(_star, color, true)
	mi.position = p
	mi.scale = Vector3.ONE * size * 0.3
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, 0.06)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.16)
	tw.tween_callback(mi.queue_free)


func _node(mesh: Mesh, color: Color, billboard := false) -> MeshInstance3D:
	var key := [color, billboard]
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		if billboard:
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Seeing stars: a ring of them going round above someone knocked out, for `seconds`.
func ko_stars(at: Vector3, seconds: float) -> void:
	var ring := Node3D.new()
	ring.position = at
	add_child(ring)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in 4:
		var star := MeshInstance3D.new()
		star.mesh = mesh
		star.material_override = mat
		star.position = Vector3(cos(k * PI / 2.0), 0.0, sin(k * PI / 2.0)) * 0.3
		ring.add_child(star)
	var tw := create_tween()
	tw.tween_property(ring, "rotation:y", seconds * 5.0, seconds)
	tw.tween_callback(ring.queue_free)


## A head hit: a bigger, redder burst, and a spray for a bullet.
func headshot(at: Vector3, shot: bool) -> void:
	_burst(at, 0.75 if shot else 0.6, Color(1.0, 0.1, 0.05))
	_burst(at, 0.3, Color(1.0, 0.95, 0.3))
	if not shot:
		return
	for k in 6:
		var mi := _node(_beam, Color(0.75, 0.03, 0.03))
		mi.position = at
		mi.scale = Vector3(1.0, 1.0, 0.12)
		var to := at + Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.9), randf_range(-0.7, 0.7))
		var tw := create_tween()
		tw.tween_property(mi, "position", to, 0.18)
		tw.parallel().tween_property(mi, "scale", Vector3(0.3, 0.3, 0.02), 0.18)
		tw.tween_callback(mi.queue_free)


## A spent case flicked out to the shooter's right.
func shell(at: Vector3, right: Vector3) -> void:
	if _shells >= 24:
		return
	_shells += 1
	var mi := _node(_beam, Color(0.95, 0.75, 0.2))
	mi.position = at
	mi.scale = Vector3(0.6, 0.6, 0.07)
	var out := at + right * randf_range(0.5, 0.9) + Vector3(0, 0.35, 0)
	var tw := create_tween()
	tw.tween_property(mi, "position", out, 0.12)
	tw.tween_property(mi, "position", Vector3(out.x + right.x * 0.3, maxf(at.y - 1.2, 0.03), out.z + right.z * 0.3), 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		_shells -= 1
		mi.queue_free())
