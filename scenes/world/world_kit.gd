extends Node3D
## Builder helpers shared by the pieces of the world.
##
## Plain boxes are batched: _box only records an instance, and _flush turns each stretch of
## the map into one MultiMesh. Call _flush once everything is placed.

const Layout := preload("res://scenes/world/layout.gd")
const Nav := preload("res://scenes/world/nav.gd")

const CHUNK := 150.0
const WOOD := Color(0.62, 0.45, 0.28)

## Materials that brighten as the day ends (shader parameter `night`).
static var night_mats: Array[ShaderMaterial] = []

static var _unit: BoxMesh
static var _flat: StandardMaterial3D
static var _lit: StandardMaterial3D
static var _wall: ShaderMaterial

var _static: StaticBody3D
var _boxes := {}   # chunk -> [transforms, colours]
var _glows := {}
var _towers := {}  # chunk -> [transforms, colours, custom]


func _init_kit() -> void:
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	add_child(_static)
	if _unit == null:
		_unit = BoxMesh.new()
		_flat = _vertex_mat()
		_lit = _vertex_mat()
		_lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wall = ShaderMaterial.new()
		_wall.shader = load("res://shaders/building.gdshader")
		night_mats.append(_wall)


# --- batched boxes ---

func _box(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	_batch(_boxes, p, size, c, rot)


## A box that ignores lighting: lamps, signs, neon.
func _glow(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	_batch(_glows, p, size, c, rot)


## A building: one box whose windows are drawn by the shader. style 0 tower, 1 favela house.
func _tower(p: Vector3, size: Vector3, c: Color, style := 0) -> void:
	_batch(_towers, p, size, c, Vector3.ZERO).append(Color(style, 0, 0, 0))


func _batch(into: Dictionary, p: Vector3, size: Vector3, c: Color, rot: Vector3) -> Array:
	var key := int(floorf(p.x / CHUNK))
	if not into.has(key):
		into[key] = [[], [], []]
	var e: Array = into[key]
	e[0].append(Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), p))
	e[1].append(c)
	return e[2]


func _flush() -> void:
	for kind in [[_boxes, _flat], [_glows, _lit], [_towers, _wall]]:
		var batches: Dictionary = kind[0]
		for key in batches:
			var e: Array = batches[key]
			var mmi := _instances(_unit, kind[1], e[0], e[1], e[2])
			if kind[1] == _lit:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batches.clear()


## A visible box that is also solid and that the crowd keeps clear of.
func _solid(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	_box(p, size, c, rot)
	_collider(p, size, rot)
	DB.solids.append(Transform3D(Basis.from_euler(rot), p) * AABB(size * -0.5, size))


## A visible box that is solid but is not something on the sand to steer the crowd around.
func _block(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	_box(p, size, c, rot)
	_collider(p, size, rot)


func _collider(p: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = p
	cs.rotation = rot
	_static.add_child(cs)
	Nav.add_box(p, size, rot)


# --- everything else ---

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _vertex_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, height: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


func _ball(radius: float, height := -1.0, segs := 10) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0 if height < 0.0 else height
	s.radial_segments = segs
	s.rings = segs / 2
	return s


func _blob(p: Vector3, radii: Vector3, mat: Material) -> void:
	var s := _ball(1.0, 2.0, 24)
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.position = p
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _plane(p: Vector3, size: Vector2, mat: Material) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = p
	add_child(mi)
	return mi


## Fixed sign. Faces +z unless turned by `yaw`.
func _sign(text: String, p: Vector3, px: int, c := Color.WHITE, yaw := 0.0, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = px
	l.outline_size = px / 4
	l.modulate = c
	l.position = p
	l.rotation.y = yaw
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	return l


## One mesh out of several, each part as [mesh, transform, colour]. The colour goes on the
## vertices, so the result draws with _vertex_mat() or any shader that reads COLOR.
static func compose(parts: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for e in parts:
		var src: Array = e[0].get_mesh_arrays()
		var xf: Transform3D = e[1]
		var nb := xf.basis.inverse().transposed()
		var base := v.size()
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		var suv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
		for k in sv.size():
			v.append(xf * sv[k])
			n.append((nb * sn[k]).normalized())
			col.append(e[2])
			uv.append(suv[k])
		for k in src[Mesh.ARRAY_INDEX]:
			idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Shorthand for a compose() part: a box of `size` centred on `p`.
static func part(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> Array:
	var b := BoxMesh.new()
	b.size = size
	return [b, Transform3D(Basis.from_euler(rot), p), c]


func _instances(mesh: Mesh, mat: Material, xforms: Array, colors: Array = [], custom: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi
