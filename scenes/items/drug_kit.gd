extends RefCounted
## What the drugs (and a box of ammo) look like: one small model each, built from boxes, cans
## and balls. The same model lies on the sand as loot and is photographed once for the HUD,
## so what you pick up is what you see on the hotbar.
##
## Every model sits on the origin, about half a metre across, facing +Z.

const WorldKit := preload("res://scenes/world/world_kit.gd")

const ICON_PX := 96
const WHITE := Color(0.96, 0.96, 0.94)
const STEEL := Color(0.72, 0.74, 0.78)
const DARK := Color(0.1, 0.1, 0.12)

static var _meshes := {}  # item id -> ArrayMesh
static var _mat: StandardMaterial3D


static func has(id: String) -> bool:
	return _parts(id).size() > 0


static func mesh_for(id: String) -> ArrayMesh:
	if not _meshes.has(id):
		_meshes[id] = WorldKit.compose(_parts(id))
	return _meshes[id]


## A node showing item `id`, for a drop on the ground or an icon's photograph.
static func node(id: String) -> MeshInstance3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh_for(id)
	mi.material_override = _mat
	return mi


## A little studio that photographs item `id` once: add it to the tree and use its texture.
## (With no renderer, as in a headless test, the picture is simply blank.)
static func icon_viewport(id: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(ICON_PX, ICON_PX)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	var cam := Camera3D.new()
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.62
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.9, 0.8, 2.0), Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(-1.0, 2.0, 1.5), Vector3.ZERO)
	vp.add_child(node(id))
	return vp


# --- the models ---

static func _box(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> Array:
	return WorldKit.part(p, size, c, rot)


## A can or tube standing on its end at `p`, `r_top` across the top and `r` across the bottom.
static func _cyl(p: Vector3, r: float, h: float, c: Color, rot := Vector3.ZERO, r_top := -1.0) -> Array:
	var m := CylinderMesh.new()
	m.top_radius = r if r_top < 0.0 else r_top
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 1
	return [m, Transform3D(Basis.from_euler(rot), p), c]


static func _ball(p: Vector3, radii: Vector3, c: Color) -> Array:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 10
	m.rings = 5
	return [m, Transform3D(Basis.from_scale(radii * 2.0), p), c]


static func _parts(id: String) -> Array:
	match id:
		"cocaine": return _cocaine()
		"weed": return _weed()
		"meth": return _meth()
		"lanca": return _lanca()
		"bala": return _bala()
		"doce": return _doce()
		"ayahuasca": return _ayahuasca()
		"bomba": return _bomba()
		"rivotril": return _rivotril()
		"ketamine": return _ketamine()
		"guarana": return _guarana()
		"ammo": return _ammo()
	return []


## A mirror with two lines racked up on it, a rolled note and the bag it came out of.
static func _cocaine() -> Array:
	return [
		_box(Vector3(0, -0.12, 0), Vector3(0.52, 0.03, 0.36), Color(0.2, 0.26, 0.34)),
		_box(Vector3(0, -0.1, 0), Vector3(0.46, 0.012, 0.3), Color(0.55, 0.68, 0.8)),
		_box(Vector3(-0.08, -0.085, 0.06), Vector3(0.24, 0.02, 0.03), WHITE),
		_box(Vector3(-0.08, -0.085, -0.02), Vector3(0.24, 0.02, 0.03), WHITE),
		_cyl(Vector3(0.12, -0.07, 0.07), 0.022, 0.2, Color(0.35, 0.65, 0.4), Vector3(PI / 2.0, 0.5, 0)),
		_ball(Vector3(0.1, 0.0, -0.08), Vector3(0.1, 0.09, 0.08), WHITE),
		_box(Vector3(0.1, 0.1, -0.08), Vector3(0.06, 0.05, 0.03), Color(0.8, 0.8, 0.85)),
	]


## A fat bud, orange hairs and all, with a joint leaning on it.
static func _weed() -> Array:
	var g1 := Color(0.25, 0.55, 0.16)
	var g2 := Color(0.38, 0.7, 0.22)
	var out := [
		_cyl(Vector3(0, -0.16, 0), 0.02, 0.1, Color(0.4, 0.3, 0.15)),
		_ball(Vector3(0, -0.04, 0), Vector3(0.15, 0.13, 0.15), g1),
		_ball(Vector3(0.07, 0.06, 0.03), Vector3(0.11, 0.1, 0.1), g2),
		_ball(Vector3(-0.07, 0.07, -0.02), Vector3(0.1, 0.1, 0.1), g2),
		_ball(Vector3(0.0, 0.17, 0.0), Vector3(0.09, 0.1, 0.09), g1),
		_cyl(Vector3(0.2, -0.1, 0.12), 0.022, 0.3, WHITE, Vector3(0, 0.4, 1.25), 0.014),
		_cyl(Vector3(0.335, -0.055, 0.063), 0.024, 0.03, Color(0.95, 0.45, 0.1), Vector3(0, 0.4, 1.25)),
	]
	for k in 6:
		var a := k * 1.05
		out.append(_box(Vector3(cos(a) * 0.12, 0.02 + (k % 3) * 0.07, sin(a) * 0.12), Vector3(0.02, 0.05, 0.02), Color(0.95, 0.5, 0.12), Vector3(a, a, 0.5)))
	return out


## A heap of blue glass.
static func _meth() -> Array:
	var c1 := Color(0.35, 0.75, 0.95)
	var c2 := Color(0.65, 0.92, 1.0)
	return [
		_box(Vector3(0, -0.05, 0), Vector3(0.12, 0.34, 0.1), c1, Vector3(0.2, 0.3, 0.25)),
		_box(Vector3(0.12, -0.08, 0.05), Vector3(0.1, 0.24, 0.09), c2, Vector3(-0.3, 0.8, -0.5)),
		_box(Vector3(-0.13, -0.09, 0.03), Vector3(0.09, 0.22, 0.1), c2, Vector3(0.4, 0.2, 0.7)),
		_box(Vector3(0.02, -0.11, -0.12), Vector3(0.11, 0.18, 0.08), c1, Vector3(-0.6, 1.2, 0.2)),
		_box(Vector3(0.04, -0.13, 0.14), Vector3(0.08, 0.12, 0.08), c1, Vector3(0.9, 0.4, 0.3)),
		_box(Vector3(-0.05, 0.1, 0.02), Vector3(0.06, 0.14, 0.06), c2, Vector3(0.1, 0.9, -0.3)),
	]


## The carnival can: gold, a red band, a white button on top.
static func _lanca() -> Array:
	var gold := Color(0.95, 0.75, 0.15)
	return [
		_cyl(Vector3(0, -0.04, 0), 0.1, 0.34, gold),
		_cyl(Vector3(0, -0.02, 0), 0.103, 0.1, Color(0.85, 0.12, 0.12)),
		_box(Vector3(0, -0.02, 0.1), Vector3(0.1, 0.05, 0.02), WHITE),
		_cyl(Vector3(0, 0.15, 0), 0.1, 0.05, STEEL, Vector3.ZERO, 0.045),
		_cyl(Vector3(0, 0.2, 0), 0.035, 0.06, WHITE),
		_box(Vector3(0, 0.215, 0.04), Vector3(0.025, 0.02, 0.04), Color(0.3, 0.3, 0.32)),
	]


## A pill stood on its edge, smiling.
static func _bala() -> Array:
	var pink := Color(1.0, 0.45, 0.75)
	var flat := Vector3(PI / 2.0, 0, 0)
	var out := [
		_cyl(Vector3.ZERO, 0.21, 0.09, pink, flat),
		_cyl(Vector3.ZERO, 0.19, 0.11, Color(1.0, 0.62, 0.85), flat),
	]
	for z in [0.058, -0.058]:
		out.append(_box(Vector3(-0.065, 0.055, z), Vector3(0.035, 0.06, 0.01), DARK))
		out.append(_box(Vector3(0.065, 0.055, z), Vector3(0.035, 0.06, 0.01), DARK))
		out.append(_box(Vector3(0, -0.075, z), Vector3(0.12, 0.028, 0.01), DARK))
		out.append(_box(Vector3(-0.08, -0.05, z), Vector3(0.03, 0.045, 0.01), DARK, Vector3(0, 0, -0.5)))
		out.append(_box(Vector3(0.08, -0.05, z), Vector3(0.03, 0.045, 0.01), DARK, Vector3(0, 0, 0.5)))
	return out


## A sheet of blotter, every square a different colour.
static func _doce() -> Array:
	var out := [_box(Vector3.ZERO, Vector3(0.4, 0.4, 0.02), WHITE)]
	for row in 3:
		for col in 3:
			var c := Color.from_hsv(fmod(row * 0.31 + col * 0.17, 1.0), 0.8, 1.0)
			for z in [0.012, -0.012]:
				out.append(_box(Vector3((col - 1) * 0.125, (row - 1) * 0.125, z), Vector3(0.105, 0.105, 0.006), c))
	return out


## A clay cup of something brown.
static func _ayahuasca() -> Array:
	var clay := Color(0.72, 0.38, 0.22)
	return [
		_cyl(Vector3(0, -0.03, 0), 0.11, 0.26, clay, Vector3.ZERO, 0.17),
		_cyl(Vector3(0, 0.02, 0), 0.142, 0.04, Color(0.92, 0.82, 0.6), Vector3.ZERO, 0.152),
		_cyl(Vector3(0, 0.095, 0), 0.15, 0.02, Color(0.28, 0.16, 0.08)),
		_cyl(Vector3(0, -0.17, 0), 0.12, 0.03, clay.darkened(0.25)),
		_box(Vector3(0.05, 0.2, 0), Vector3(0.025, 0.14, 0.025), Color(0.3, 0.5, 0.2), Vector3(0, 0, -0.3)),
		_box(Vector3(0.1, 0.27, 0), Vector3(0.09, 0.03, 0.06), Color(0.3, 0.55, 0.2), Vector3(0, 0, 0.4)),
	]


## A loaded syringe across a little amber vial.
static func _bomba() -> Array:
	var lean := Vector3(0, 0, 1.0)
	var along := Vector3(sin(-1.0), cos(-1.0), 0) * -1.0  # the syringe's long axis, needle end
	var mid := Vector3(0.02, 0.03, 0.08)
	return [
		_cyl(Vector3(-0.1, -0.08, -0.06), 0.085, 0.2, Color(0.75, 0.45, 0.1)),
		_cyl(Vector3(-0.1, -0.07, -0.06), 0.088, 0.09, WHITE),
		_cyl(Vector3(-0.1, 0.04, -0.06), 0.05, 0.05, STEEL),
		_cyl(mid, 0.04, 0.26, Color(0.82, 0.9, 0.95), lean),
		_cyl(mid + along * 0.04, 0.042, 0.12, Color(0.95, 0.8, 0.3), lean),
		_cyl(mid + along * 0.2, 0.008, 0.16, STEEL, lean),
		_cyl(mid - along * 0.14, 0.06, 0.015, DARK, lean),
		_cyl(mid - along * 0.2, 0.014, 0.12, DARK, lean),
		_cyl(mid - along * 0.26, 0.045, 0.015, DARK, lean),
	]


## A strip of pills in their foil.
static func _rivotril() -> Array:
	var out := [
		_box(Vector3.ZERO, Vector3(0.46, 0.3, 0.02), STEEL),
		_box(Vector3(0, 0.125, 0.011), Vector3(0.46, 0.05, 0.004), Color(0.15, 0.3, 0.7)),
	]
	for row in 2:
		for col in 4:
			out.append(_ball(Vector3((col - 1.5) * 0.105, -0.085 + row * 0.11, 0.012), Vector3(0.036, 0.036, 0.022), WHITE))
	return out


## A glass vial with a rubber stopper and a flip-off cap.
static func _ketamine() -> Array:
	return [
		_cyl(Vector3(0, -0.06, 0), 0.1, 0.26, Color(0.8, 0.9, 0.95)),
		_cyl(Vector3(0, -0.1, 0), 0.102, 0.15, Color(0.92, 0.96, 1.0)),
		_cyl(Vector3(0, -0.06, 0), 0.104, 0.11, WHITE),
		_box(Vector3(0, -0.04, 0.1), Vector3(0.12, 0.03, 0.012), Color(0.15, 0.35, 0.8)),
		_box(Vector3(0, -0.085, 0.1), Vector3(0.09, 0.02, 0.012), DARK),
		_cyl(Vector3(0, 0.09, 0), 0.1, 0.04, Color(0.8, 0.9, 0.95), Vector3.ZERO, 0.05),
		_cyl(Vector3(0, 0.13, 0), 0.058, 0.05, STEEL),
		_cyl(Vector3(0, 0.165, 0), 0.062, 0.02, Color(0.9, 0.2, 0.2)),
	]


## A sachet of powder with the fruit on the front: red, with its eye open.
static func _guarana() -> Array:
	var green := Color(0.1, 0.5, 0.2)
	var out := [
		_box(Vector3.ZERO, Vector3(0.3, 0.4, 0.06), green),
		_box(Vector3(0, 0.185, 0), Vector3(0.3, 0.03, 0.02), STEEL),
		_box(Vector3(0, -0.185, 0), Vector3(0.3, 0.03, 0.02), STEEL),
	]
	for z in [1.0, -1.0]:
		out.append(_box(Vector3(0, -0.11, 0.032 * z), Vector3(0.3, 0.07, 0.006), Color(1.0, 0.85, 0.1)))
		out.append(_ball(Vector3(0, 0.05, 0.035 * z), Vector3(0.085, 0.085, 0.03), Color(0.85, 0.12, 0.1)))
		out.append(_ball(Vector3(0, 0.05, 0.05 * z), Vector3(0.05, 0.05, 0.025), WHITE))
		out.append(_ball(Vector3(0, 0.05, 0.064 * z), Vector3(0.026, 0.026, 0.016), DARK))
	return out


## A carton of rounds with the top row showing.
static func _ammo() -> Array:
	var out := [
		_box(Vector3(0, -0.06, 0), Vector3(0.36, 0.18, 0.24), Color(0.3, 0.36, 0.2)),
		_box(Vector3(0, -0.06, 0.121), Vector3(0.2, 0.08, 0.004), Color(0.9, 0.8, 0.3)),
	]
	for row in 2:
		for col in 4:
			var p := Vector3((col - 1.5) * 0.08, 0.07, (row - 0.5) * 0.1)
			out.append(_cyl(p, 0.028, 0.1, Color(0.85, 0.65, 0.2)))
			out.append(_cyl(p + Vector3(0, 0.07, 0), 0.026, 0.05, Color(0.7, 0.42, 0.25), Vector3.ZERO, 0.008))
	return out
