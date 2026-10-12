extends Node3D
## Procedural stylised beach: sea (-z), sand, wave promenade, road, tower blocks (+z).
## Prison yard sits behind the buildings and is only reachable by teleport.

const SAND := Color(0.86, 0.74, 0.5)
const LENGTH := 620.0
const PROP_TINTS := [Color(0.95, 0.35, 0.25), Color(0.2, 0.6, 0.9), Color(0.98, 0.8, 0.2), Color(0.25, 0.75, 0.5), Color(0.9, 0.45, 0.75)]
const WOOD := Color(0.62, 0.45, 0.28)

## Footprint of every solid prop on the sand, shared through DB.solids.
var solids: Array[AABB] = []

var _static: StaticBody3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1502
	_static = StaticBody3D.new()
	_static.collision_layer = 1
	add_child(_static)
	_environment()
	_ground()
	_city()
	_hills()
	_decor()
	_vendors()
	_prison()
	_parkour()
	DB.solids = solids


func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.62, 0.8, 0.95)
	sky_mat.ground_horizon_color = Color(0.62, 0.8, 0.95)
	sky_mat.ground_bottom_color = Color(0.1, 0.3, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.82, 0.95)
	env.fog_density = 0.0004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _ground() -> void:
	_collider(Vector3(0, -0.5, 40), Vector3(800, 1, 320))
	# Invisible limits: beach ends and deep water.
	_collider(Vector3(-306, 10, 0), Vector3(2, 20, 200))
	_collider(Vector3(306, 10, 0), Vector3(2, 20, 200))
	_collider(Vector3(0, 10, -82), Vector3(700, 20, 2))

	_plane(Vector3(0, 0, 0), Vector2(LENGTH + 400, 90), _mat(SAND))
	_plane(Vector3(0, 0.01, -37), Vector2(LENGTH + 400, 8), _mat(SAND.darkened(0.2), 0.4))

	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = load("res://shaders/sea.gdshader")
	var sea := PlaneMesh.new()
	sea.size = Vector2(3000, 1500)
	sea.subdivide_width = 160
	sea.subdivide_depth = 80
	sea.material = sea_mat
	var sea_mi := MeshInstance3D.new()
	sea_mi.mesh = sea
	sea_mi.position = Vector3(0, 0.3, -38 - 750)
	sea_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea_mi)

	var prom := ShaderMaterial.new()
	prom.shader = load("res://shaders/promenade.gdshader")
	_plane(Vector3(0, 0.03, 46), Vector2(LENGTH + 400, 12), prom)
	_box(Vector3(0, 0.08, 52.2), Vector3(LENGTH + 400, 0.16, 0.4), Color(0.75, 0.75, 0.75))
	_plane(Vector3(0, 0.02, 61), Vector2(LENGTH + 400, 18), _mat(Color(0.16, 0.16, 0.18)))
	var dashes: Array = []
	for i in 100:
		dashes.append(Transform3D(Basis(), Vector3(-500 + i * 10.0, 0.04, 61)))
	_multi(_box_mesh(Vector3(3, 0.02, 0.2)), _mat(Color(0.95, 0.9, 0.5)), dashes)


func _city() -> void:
	_collider(Vector3(0, 30, 84), Vector3(1100, 60, 28))
	var x := -520.0
	while x < 520.0:
		var w := _rng.randf_range(18.0, 34.0)
		var h := _rng.randf_range(22.0, 70.0)
		var tint := Color.from_hsv(_rng.randf(), _rng.randf_range(0.0, 0.18), _rng.randf_range(0.82, 0.98))
		_box(Vector3(x + w * 0.5, h * 0.5, 84), Vector3(w - 1.5, h, 26), tint)
		# Balcony bands so towers do not read as blank boxes.
		var bands: Array = []
		for f in int(h / 4.0):
			bands.append(Transform3D(Basis(), Vector3(x + w * 0.5, 3.0 + f * 4.0, 70.8)))
		_multi(_box_mesh(Vector3(w - 3.0, 1.1, 0.5)), _mat(tint.darkened(0.35)), bands)
		x += w
	# Police cars parked on the road.
	for cx in [-150.0, 20.0, 190.0]:
		_box(Vector3(cx, 0.65, 56), Vector3(4.2, 0.9, 1.9), Color(0.95, 0.95, 0.95))
		_box(Vector3(cx, 1.3, 56), Vector3(2.2, 0.6, 1.7), Color(0.1, 0.2, 0.6))
		_box(Vector3(cx, 1.7, 56), Vector3(0.9, 0.15, 0.3), Color(0.9, 0.1, 0.1))
		_collider(Vector3(cx, 0.8, 56), Vector3(4.2, 1.6, 1.9))


func _hills() -> void:
	var rock := _mat(Color(0.3, 0.36, 0.3))
	var green := _mat(Color(0.16, 0.38, 0.22))
	# Sugarloaf off the end of the beach.
	_blob(Vector3(-520, 0, -150), Vector3(95, 190, 95), rock)
	_blob(Vector3(-640, 0, -40), Vector3(170, 100, 150), green)
	_blob(Vector3(560, 0, -120), Vector3(150, 90, 120), green)
	# Range behind the city, with a statue on the tallest peak.
	for i in 9:
		_blob(Vector3(-640 + i * 160.0, 0, 330 + _rng.randf_range(-40, 40)), Vector3(170, _rng.randf_range(110, 190), 150), green)
	_blob(Vector3(140, 0, 300), Vector3(120, 240, 120), green)
	_box(Vector3(140, 253, 300), Vector3(4, 28, 4), Color(0.95, 0.95, 0.92))
	_box(Vector3(140, 260, 300), Vector3(24, 4, 3), Color(0.95, 0.95, 0.92))


func _decor() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.5
	cone.height = 0.55
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 2.2
	var tops: Array = []
	var poles: Array = []
	var colors: Array = []
	for i in 260:
		var p := Vector3(_rng.randf_range(-295, 295), 0, _rng.randf_range(-30, 36))
		tops.append(Transform3D(Basis(), p + Vector3(0, 2.3, 0)))
		poles.append(Transform3D(Basis(), p + Vector3(0, 1.1, 0)))
		colors.append(Color.from_hsv(_rng.randf(), 0.75, 0.95))
	_multi(cone, _vertex_mat(), tops, colors)
	_multi(pole, _mat(Color(0.9, 0.9, 0.9)), poles)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 7.0
	var crown := SphereMesh.new()
	crown.radius = 2.4
	crown.height = 1.8
	var trunks: Array = []
	var crowns: Array = []
	for i in 42:
		var p := Vector3(-300 + i * 14.6, 0, 40.6)
		trunks.append(Transform3D(Basis(), p + Vector3(0, 3.5, 0)))
		crowns.append(Transform3D(Basis(), p + Vector3(0, 7.2, 0)))
	_multi(trunk, _mat(Color(0.45, 0.33, 0.2)), trunks)
	_multi(crown, _mat(Color(0.12, 0.5, 0.2)), crowns)


func _vendors() -> void:
	# Plain kiosks along the promenade, plus the two that sell things.
	for kx in [-240.0, -150.0, 10.0, 170.0, 250.0]:
		_kiosk(Vector3(kx, 0, 49.5), Color(0.9, 0.3, 0.2), "")
	for v in DB.VENDORS:
		var c := Color(0.2, 0.7, 0.3) if v.name == "DEALER" else Color(0.25, 0.25, 0.3)
		_kiosk(v.pos + Vector3(0, 0, 2.5), c, "%s  [F]" % v.name)


func _kiosk(p: Vector3, roof: Color, text: String) -> void:
	_box(p + Vector3(0, 1.2, 0), Vector3(3.2, 2.4, 2.4), Color(0.96, 0.94, 0.88))
	_box(p + Vector3(0, 2.55, 0), Vector3(4.0, 0.3, 3.2), roof)
	_collider(p + Vector3(0, 1.2, 0), Vector3(3.2, 2.4, 2.4))
	if text != "":
		var l := Label3D.new()
		l.text = text
		l.font_size = 96
		l.outline_size = 24
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.position = p + Vector3(0, 3.6, 0)
		add_child(l)


func _prison() -> void:
	var c := DB.PRISON_POS
	var grey := Color(0.4, 0.4, 0.42)
	_plane(Vector3(c.x, 0.03, c.z), Vector2(16, 16), _mat(Color(0.55, 0.55, 0.55)))
	for side in [[Vector3(0, 3, -8), Vector3(16.5, 6, 0.5)], [Vector3(0, 3, 8), Vector3(16.5, 6, 0.5)], [Vector3(-8, 3, 0), Vector3(0.5, 6, 16.5)], [Vector3(8, 3, 0), Vector3(0.5, 6, 16.5)]]:
		_box(Vector3(c.x, 0, c.z) + side[0], side[1], grey)
		_collider(Vector3(c.x, 0, c.z) + side[0], side[1])


## Things to run along, slide under, hop across and hide behind, in two rows down the sand.
## Seeded apart from the decor so adding a prop never reshuffles the rest of the beach.
func _parkour() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var kind := 0
	for row in [Vector2(-22.0, -8.0), Vector2(8.0, 26.0)]:
		var x := -268.0 + rng.randf_range(0.0, 12.0)
		while x < 270.0:
			var at := Vector3(x, 0.0, rng.randf_range(row.x, row.y))
			var tint: Color = PROP_TINTS[rng.randi() % PROP_TINTS.size()]
			match kind % 5:
				0: _wall_lane(at, tint)
				1: _lifeguard(at)
				2: _hut(at, tint)
				3: _crate_run(at, tint)
				4: _slide_fence(at, tint)
			kind += 1
			x += rng.randf_range(30.0, 40.0)
		kind += 2


## Three staggered billboards: run one, kick across to the next.
func _wall_lane(at: Vector3, tint: Color) -> void:
	for i in 3:
		var side := -2.0 if i % 2 == 0 else 2.0
		_solid(at + Vector3((i - 1) * 7.5, 2.25, side), Vector3(9.0, 4.5, 0.4), tint if i != 1 else tint.lightened(0.35))


## Lifeguard tower: a lookout three metres up, reached by its ramp.
func _lifeguard(at: Vector3) -> void:
	_solid(at + Vector3(0, 1.5, 0), Vector3(3.2, 3.0, 3.2), Color(0.96, 0.96, 0.94))
	_box(at + Vector3(0, 2.6, 0), Vector3(3.3, 0.4, 3.3), Color(0.9, 0.15, 0.12))
	_solid(at + Vector3(0, 1.36, 4.96), Vector3(1.8, 0.3, 7.36), WOOD, Vector3(0.42, 0, 0))
	_box(at + Vector3(1.3, 4.5, -1.3), Vector3(0.1, 3.0, 0.1), Color(0.8, 0.8, 0.8))
	_box(at + Vector3(1.3, 5.7, -0.95), Vector3(0.05, 0.5, 0.7), Color(0.9, 0.15, 0.12))


## Beach hut with a crate beside it as a step up to the roof.
func _hut(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 4.0), Color(0.96, 0.94, 0.88))
	_box(at + Vector3(0, 2.45, 0), Vector3(4.3, 0.12, 4.3), tint)
	_box(at + Vector3(0, 1.0, -2.01), Vector3(1.0, 2.0, 0.05), tint.darkened(0.4))
	_solid(at + Vector3(2.7, 0.45, 0.8), Vector3(1.3, 0.9, 1.3), WOOD)


## A kicker ramp into a line of crates to hop along.
func _crate_run(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(-7.0, 0.63, 0), Vector3(2.4, 0.25, 4.5), tint, Vector3(0.33, -PI / 2.0, 0))
	var heights := [0.9, 0.9, 1.7, 0.9]
	for i in heights.size():
		var h: float = heights[i]
		_solid(at + Vector3(-1.0 + i * 3.2, h * 0.5, 0), Vector3(1.3, h, 1.3), WOOD if i != 2 else WOOD.darkened(0.2))


## A fence whose only way through is a gap too low to pass standing up.
func _slide_fence(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(0, 1.2, -4.0), Vector3(0.4, 2.4, 5.0), tint)
	_solid(at + Vector3(0, 1.2, 4.0), Vector3(0.4, 2.4, 5.0), tint)
	_solid(at + Vector3(0, 1.7, 0), Vector3(0.4, 1.4, 3.0), tint.darkened(0.3))


## A visible box that is also solid.
func _solid(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	_box(p, size, c, rot)
	_collider(p, size, rot)
	solids.append(Transform3D(Basis.from_euler(rot), p) * AABB(size * -0.5, size))


# --- helpers ---

func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _vertex_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	return m


func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _box(p: Vector3, size: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = _mat(c)
	mi.position = p
	mi.rotation = rot
	add_child(mi)


func _blob(p: Vector3, radii: Vector3, mat: Material) -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = mat
	mi.position = p
	mi.scale = radii
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _plane(p: Vector3, size: Vector2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = p
	add_child(mi)


func _collider(p: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = p
	cs.rotation = rot
	_static.add_child(cs)


func _multi(mesh: Mesh, mat: Material, xforms: Array, colors: Array = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
