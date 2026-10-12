extends Node3D
## Short-lived combat visuals: tracers, muzzle flashes and comic impact bursts.

var _star: ArrayMesh
var _beam: BoxMesh
var _mats := {}


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
