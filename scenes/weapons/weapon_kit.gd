extends RefCounted
## Weapon models: the imported ones in assets/weapons/, or boxes if a file is missing.
##
## Every weapon is turned into the same "gun space" whatever it was modelled in: the grip at
## the origin, the barrel (or blade) along -Z, the sights up +Y. From there it goes two ways:
## as an ordinary mesh for first person and for loot lying on the ground, and baked into the
## character's own space so the character shader can carry it in the hand (see held_mesh()).

## By Kit.HELD_*. `scale` and `grip` are in the model's own units: how much to shrink it and
## where on it the hand closes. These models all point their barrels along +X.
const MODELS := {
	1: {"path": "res://assets/weapons/faca.glb", "scale": 0.3, "grip": Vector3(-0.05, -0.02, 0.0)},
	2: {"path": "res://assets/weapons/pistola.glb", "scale": 0.15, "grip": Vector3(0.02, -0.05, 0.0)},
	3: {"path": "res://assets/weapons/revolver.glb", "scale": 0.15, "grip": Vector3(0.0, -0.05, 0.0)},
	4: {"path": "res://assets/weapons/smg.glb", "scale": 0.15, "grip": Vector3(0.12, -0.35, 0.0)},
	# Built out of boxes (see _fallback): shotgun, rifle, sniper, launcher, grenade, bottle, bat.
	5: {}, 6: {}, 7: {}, 8: {}, 9: {}, 10: {}, 11: {},
}
## Where a right hand hangs on the character mesh at rest, and the shader ids that tie a
## vertex to that hand (see shaders/character_pose.gdshaderinc and character.gdshader).
const HAND := Vector3(0.245, 0.74, -0.02)
const PROP_HELD := 64
const PART_FORE_R := 5
const SLOT_VCOL := 18
const DARK := Color(0.16, 0.16, 0.17)
const STEEL := Color(0.33, 0.34, 0.35)
const WOOD := Color(0.32, 0.27, 0.23)

static var _parts := {}   # held id -> [vertices, normals, colours, indices] in gun space
static var _meshes := {}  # held id -> ArrayMesh
static var _held: ArrayMesh
static var _mat: StandardMaterial3D


## The weapon as an ordinary mesh in gun space, coloured on its vertices.
static func mesh_for(id: int) -> ArrayMesh:
	if not _meshes.has(id):
		var p: Array = _gun(id)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = p[0]
		arrays[Mesh.ARRAY_NORMAL] = p[1]
		arrays[Mesh.ARRAY_COLOR] = p[2]
		arrays[Mesh.ARRAY_INDEX] = p[3]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_meshes[id] = m
	return _meshes[id]


## A node showing weapon `id`, for a first-person hand or a drop.
static func node(id: int) -> MeshInstance3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.55
		_mat.metallic = 0.3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(id)
	mi.material_override = _mat
	return mi


## Every weapon in one mesh, laid along a hanging right arm in the character's rest space and
## tagged as part of the right forearm. Drawn with the character shader and the owner's own
## instance data, it follows the hand through any pose; the shader shows only the weapon whose
## id matches what is held. Colour rides in UV.y, since instance colour is spoken for.
static func held_mesh() -> ArrayMesh:
	if _held != null:
		return _held
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	# Barrel down the arm, sights forward: raising the arm then points it ahead, sights up.
	var b := Basis(Vector3.RIGHT, -PI / 2.0)
	for id in MODELS:
		var p: Array = _gun(id)
		var base := v.size()
		var pv: PackedVector3Array = p[0]
		var pn: PackedVector3Array = p[1]
		var pc: PackedColorArray = p[2]
		for k in pv.size():
			v.append(HAND + b * pv[k])
			n.append(b * pn[k])
			var c := pc[k]
			uv.append(Vector2(PROP_HELD + id, roundf(c.r * 127.0) + roundf(c.g * 127.0) * 128.0 + roundf(c.b * 127.0) * 16384.0))
			uv2.append(Vector2(PART_FORE_R, SLOT_VCOL))
		for k in p[3]:
			idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	_held = ArrayMesh.new()
	_held.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _held


static func _gun(id: int) -> Array:
	if not _parts.has(id):
		var def: Dictionary = MODELS[id]
		var out: Array = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedInt32Array()]
		if def.has("path") and ResourceLoader.exists(def.path):
			var root: Node = load(def.path).instantiate()
			# Model space has the barrel along +X; gun space wants it along -Z.
			_collect(root, Transform3D(), Transform3D(Basis(Vector3.UP, PI / 2.0) * def.scale, Vector3.ZERO) * Transform3D(Basis(), -def.grip), out)
			root.free()
		if out[0].is_empty():
			_fallback(id, out)
		_parts[id] = out
	return _parts[id]


static func _collect(node: Node, xf: Transform3D, to_gun: Transform3D, out: Array) -> void:
	if node is Node3D:
		xf = xf * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var full := to_gun * xf
		var nb := full.basis.inverse().transposed()
		for s in node.mesh.get_surface_count():
			var arr: Array = node.mesh.surface_get_arrays(s)
			var mat = node.mesh.surface_get_material(s)
			var c: Color = mat.albedo_color if mat is BaseMaterial3D else STEEL
			_add(out, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_INDEX], full, nb, c)
	for child in node.get_children():
		_collect(child, xf, to_gun, out)


static func _add(out: Array, sv: PackedVector3Array, sn: PackedVector3Array, si, xf: Transform3D, nb: Basis, c: Color) -> void:
	var base: int = out[0].size()
	for k in sv.size():
		out[0].append(xf * sv[k])
		out[1].append((nb * sn[k]).normalized())
		out[2].append(c)
	if si == null or si.is_empty():
		for k in sv.size():
			out[3].append(base + k)
	else:
		for k in si:
			out[3].append(base + k)


## Something gun-shaped out of boxes, for when a model file has gone missing.
static func _fallback(id: int, out: Array) -> void:
	var boxes: Array = []
	match id:
		1:
			boxes = [[Vector3(0, 0, 0), Vector3(0.022, 0.03, 0.11), DARK], [Vector3(0, 0, -0.06), Vector3(0.012, 0.05, 0.012), STEEL], [Vector3(0, 0.003, -0.16), Vector3(0.004, 0.032, 0.19), STEEL.lightened(0.3)]]
		3:
			boxes = [[Vector3(0, 0.055, -0.1), Vector3(0.022, 0.026, 0.2), STEEL], [Vector3(0, 0.045, -0.03), Vector3(0.042, 0.042, 0.05), STEEL.lightened(0.1)], [Vector3(0, -0.02, 0.02), Vector3(0.026, 0.1, 0.04), WOOD], [Vector3(0, 0.015, -0.05), Vector3(0.008, 0.03, 0.045), STEEL]]
		4:
			boxes = [[Vector3(0, 0.07, -0.08), Vector3(0.04, 0.06, 0.3), DARK], [Vector3(0, 0.07, -0.28), Vector3(0.018, 0.018, 0.12), STEEL], [Vector3(0, -0.02, 0.0), Vector3(0.03, 0.11, 0.04), DARK], [Vector3(0, -0.06, -0.1), Vector3(0.026, 0.18, 0.035), STEEL], [Vector3(0, 0.07, 0.17), Vector3(0.015, 0.03, 0.2), STEEL]]
		5:
			# Escopeta: two fat barrels' worth of steel, a pump under it, wood behind.
			boxes = [[Vector3(0, 0.06, -0.3), Vector3(0.034, 0.034, 0.62), STEEL], [Vector3(0, 0.028, -0.26), Vector3(0.028, 0.026, 0.46), DARK],
					[Vector3(0, 0.022, -0.3), Vector3(0.046, 0.042, 0.16), WOOD], [Vector3(0, 0.05, 0.0), Vector3(0.04, 0.06, 0.16), DARK],
					[Vector3(0, -0.02, 0.02), Vector3(0.028, 0.09, 0.04), WOOD], [Vector3(0, 0.03, 0.22), Vector3(0.034, 0.075, 0.3), WOOD],
					[Vector3(0, 0.012, -0.03), Vector3(0.008, 0.03, 0.05), DARK]]
		6:
			# Fuzil: the long curved magazine and the wood are what make it one.
			boxes = [[Vector3(0, 0.06, -0.06), Vector3(0.04, 0.06, 0.3), DARK], [Vector3(0, 0.065, -0.42), Vector3(0.018, 0.018, 0.44), STEEL],
					[Vector3(0, 0.05, -0.3), Vector3(0.042, 0.05, 0.2), WOOD], [Vector3(0, 0.092, -0.3), Vector3(0.016, 0.016, 0.26), STEEL],
					[Vector3(0, -0.055, -0.12), Vector3(0.026, 0.13, 0.05), STEEL.darkened(0.2)], [Vector3(0, -0.12, -0.15), Vector3(0.026, 0.06, 0.05), STEEL.darkened(0.2)],
					[Vector3(0, -0.025, 0.02), Vector3(0.028, 0.1, 0.04), WOOD], [Vector3(0, 0.035, 0.25), Vector3(0.032, 0.07, 0.3), WOOD],
					[Vector3(0, 0.105, -0.6), Vector3(0.008, 0.03, 0.01), DARK], [Vector3(0, 0.1, -0.05), Vector3(0.012, 0.02, 0.03), DARK]]
		7:
			# Sniper: mostly barrel, with a glass on top and legs under the front.
			boxes = [[Vector3(0, 0.055, -0.05), Vector3(0.042, 0.06, 0.36), DARK], [Vector3(0, 0.06, -0.62), Vector3(0.02, 0.02, 0.8), STEEL],
					[Vector3(0, 0.06, -1.04), Vector3(0.032, 0.032, 0.09), DARK], [Vector3(0, 0.125, -0.08), Vector3(0.036, 0.036, 0.34), DARK],
					[Vector3(0, 0.125, -0.27), Vector3(0.046, 0.046, 0.05), DARK], [Vector3(0, 0.125, 0.1), Vector3(0.042, 0.042, 0.04), DARK],
					[Vector3(0, 0.092, -0.02), Vector3(0.016, 0.03, 0.03), STEEL], [Vector3(0, 0.092, -0.16), Vector3(0.016, 0.03, 0.03), STEEL],
					[Vector3(0, -0.03, 0.02), Vector3(0.028, 0.1, 0.045), DARK], [Vector3(0, 0.03, 0.3), Vector3(0.036, 0.085, 0.34), WOOD.darkened(0.2)],
					[Vector3(0, -0.04, -0.1), Vector3(0.024, 0.08, 0.05), STEEL.darkened(0.2)],
					[Vector3(-0.03, -0.02, -0.5), Vector3(0.008, 0.16, 0.008), STEEL], [Vector3(0.03, -0.02, -0.5), Vector3(0.008, 0.16, 0.008), STEEL]]
		8:
			# Lança-rojão: a tube over the shoulder with the warhead poking out of the front.
			var green := Color(0.3, 0.34, 0.22)
			boxes = [[Vector3(0, 0.13, 0.0), Vector3(0.075, 0.075, 1.0), green], [Vector3(0, 0.13, 0.52), Vector3(0.1, 0.1, 0.1), green.darkened(0.3)],
					[Vector3(0, 0.13, -0.55), Vector3(0.11, 0.11, 0.16), green.darkened(0.15)], [Vector3(0, 0.13, -0.67), Vector3(0.07, 0.07, 0.1), STEEL],
					[Vector3(0, 0.03, 0.0), Vector3(0.028, 0.13, 0.04), WOOD], [Vector3(0, 0.03, -0.2), Vector3(0.028, 0.12, 0.04), WOOD],
					[Vector3(0, 0.2, -0.1), Vector3(0.02, 0.07, 0.1), DARK], [Vector3(0, 0.13, 0.2), Vector3(0.085, 0.085, 0.22), WOOD.darkened(0.1)]]
		9:
			var olive := Color(0.26, 0.34, 0.18)
			boxes = [[Vector3(0, 0.0, -0.03), Vector3(0.07, 0.09, 0.07), olive], [Vector3(0, 0.0, -0.03), Vector3(0.085, 0.055, 0.085), olive.darkened(0.15)],
					[Vector3(0, 0.06, -0.03), Vector3(0.035, 0.035, 0.035), STEEL.lightened(0.3)], [Vector3(0.022, 0.035, -0.03), Vector3(0.012, 0.08, 0.02), STEEL.lightened(0.3)]]
		10:
			var glass := Color(0.35, 0.5, 0.25)
			boxes = [[Vector3(0, 0.02, -0.03), Vector3(0.065, 0.14, 0.065), glass], [Vector3(0, 0.12, -0.03), Vector3(0.03, 0.08, 0.03), glass],
					[Vector3(0, 0.185, -0.03), Vector3(0.04, 0.07, 0.015), Color(0.9, 0.85, 0.75)], [Vector3(0, 0.0, -0.03), Vector3(0.068, 0.07, 0.068), Color(0.75, 0.55, 0.15)]]
		11:
			# Taco: thin where it is held, fat where it lands.
			boxes = [[Vector3(0, 0, 0.0), Vector3(0.03, 0.03, 0.2), DARK], [Vector3(0, 0, -0.25), Vector3(0.04, 0.04, 0.32), WOOD.lightened(0.25)],
					[Vector3(0, 0, -0.55), Vector3(0.062, 0.062, 0.34), WOOD.lightened(0.3)], [Vector3(0, 0, 0.11), Vector3(0.045, 0.045, 0.03), DARK]]
		_:
			boxes = [[Vector3(0, 0.055, -0.06), Vector3(0.028, 0.034, 0.19), DARK], [Vector3(0, 0.03, -0.09), Vector3(0.024, 0.022, 0.12), STEEL], [Vector3(0, -0.02, 0.015), Vector3(0.026, 0.1, 0.042), WOOD], [Vector3(0, 0.012, -0.045), Vector3(0.008, 0.03, 0.05), DARK], [Vector3(0, 0.078, 0.02), Vector3(0.008, 0.012, 0.012), DARK]]
	for e in boxes:
		var box := BoxMesh.new()
		box.size = e[1]
		var arr: Array = box.get_mesh_arrays()
		_add(out, arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL], arr[Mesh.ARRAY_INDEX], Transform3D(Basis(), e[0]), Basis(), e[2])
