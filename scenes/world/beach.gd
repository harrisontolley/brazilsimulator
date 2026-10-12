extends "res://scenes/world/world_kit.gd"
## Procedural stylised Rio: sea (-z), sand, wave promenade, and the backdrop of hills.
## The avenida and everything inland of it is built by city.gd.

const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const City := preload("res://scenes/world/city.gd")

const SAND := Color(0.86, 0.74, 0.5)
const LENGTH := 620.0
const PROP_TINTS := [Color(0.95, 0.35, 0.25), Color(0.2, 0.6, 0.9), Color(0.98, 0.8, 0.2), Color(0.25, 0.75, 0.5), Color(0.9, 0.45, 0.75)]
const WHITE := Color(0.95, 0.95, 0.92)
const STEEL := Color(0.75, 0.76, 0.78)

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

var _rng := RandomNumberGenerator.new()
var _cones: Array = []       # parasol canopies: transforms
var _cone_tints: Array = []
var _poles: Array = []
var _balls: Array = []       # small spheres: coconuts, lamp globes
var _ball_tints: Array = []


func _ready() -> void:
	_rng.seed = 1502
	DB.solids.clear()
	Nav.begin()
	_init_kit()
	_environment()
	_ground()
	_hills()
	_decor()
	_palms()
	_vendors()
	_promenade()
	_postos()
	_pitches()
	_parkour()
	_cover()
	_pracas()
	_instances(_cyl(0.0, 1.5, 0.55, 10), _vertex_mat(), _cones, _cone_tints)
	_instances(_cyl(0.04, 0.04, 2.2, 5), _mat(Color(0.9, 0.9, 0.9)), _poles)
	_instances(_ball(1.0, 2.0, 8), _vertex_mat(), _balls, _ball_tints)
	_flush()
	add_child(City.new())
	# Batucada wherever there is a samba circle.
	for roda in DB.RODAS:
		var e := Sfx.emitter("samba", 1.0, 7.0, 75.0)
		e.position = roda + Vector3(0, 1.5, 0)
		add_child(e)


func _environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.62, 0.8, 0.95)
	sky_mat.ground_horizon_color = Color(0.62, 0.8, 0.95)
	sky_mat.ground_bottom_color = Color(0.1, 0.3, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.82, 0.95)
	env.fog_density = 0.0004
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.0
	add_child(sun)
	Settings.shade(sun, env)
	# High over the sea and a little toward Sugarloaf, so the seafront is lit.
	sun.look_at_from_position(Vector3(-0.45, 0.8, -0.5) * 100.0, Vector3.ZERO)


func _ground() -> void:
	_collider(Vector3(0, -0.5, 60), Vector3(800, 1, 360))
	# Invisible limits: beach ends, deep water and the top of the favela.
	_collider(Vector3(-306, 60, 50), Vector3(2, 120, 300))
	_collider(Vector3(306, 60, 50), Vector3(2, 120, 300))
	_collider(Vector3(0, 10, -82), Vector3(700, 20, 2))
	_collider(Vector3(0, 60, Layout.BACK_Z + 1.0), Vector3(700, 120, 2))

	var sand := ShaderMaterial.new()
	sand.shader = load("res://shaders/sand.gdshader")
	sand.set_shader_parameter("dry", SAND)
	_plane(Vector3(0, 0, 0), Vector2(LENGTH + 400, 90), sand)

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
	_plane(Vector3(0, 0.03, 45.3), Vector2(LENGTH + 400, 10.6), prom)
	# Low wall between sand and paving, broken by steps down every so often.
	var x := -500.0
	while x < 500.0:
		_box(Vector3(x + 8.0, 0.2, 40.0), Vector3(16.0, 0.4, 0.35), Color(0.8, 0.78, 0.72))
		x += 20.0
	# Ciclovia along the kerb.
	_box(Vector3(0, 0.03, 51.3), Vector3(LENGTH + 400, 0.04, 1.4), Color(0.7, 0.2, 0.16))
	_box(Vector3(0, 0.04, 50.55), Vector3(LENGTH + 400, 0.04, 0.1), WHITE)
	_box(Vector3(0, 0.08, 52.1), Vector3(LENGTH + 400, 0.16, 0.3), Color(0.75, 0.75, 0.75))


func _hills() -> void:
	var rock := _mat(Color(0.3, 0.36, 0.3))
	var green := _mat(Color(0.16, 0.38, 0.22))
	Layout.hills.clear()
	# Sugarloaf and Urca off the end of the beach, joined by the cable car.
	_blob(Vector3(-520, 0, -150), Vector3(95, 190, 95), rock)
	_blob(Vector3(-440, 0, -40), Vector3(80, 85, 70), rock)
	_blob(Vector3(-640, 0, -40), Vector3(170, 100, 150), green)
	_blob(Vector3(560, 0, -120), Vector3(150, 90, 120), green)
	var a := Vector3(-520, 189, -150)
	var b := Vector3(-440, 84, -40)
	var mid := (a + b) * 0.5
	var cable := MeshInstance3D.new()
	cable.mesh = _box_mesh(Vector3(0.4, 0.4, a.distance_to(b)))
	cable.material_override = _mat(Color(0.15, 0.15, 0.15))
	add_child(cable)
	cable.look_at_from_position(mid, b)
	_box(a + Vector3(0, 3, 0), Vector3(10, 6, 10), WHITE)
	_box(b + Vector3(0, 3, 0), Vector3(10, 6, 10), WHITE)
	# Islands out to sea.
	for isle in [[Vector3(-180, 0, -900), Vector3(90, 40, 50)], [Vector3(120, 0, -1050), Vector3(140, 55, 60)], [Vector3(420, 0, -820), Vector3(60, 28, 40)]]:
		_blob(isle[0], isle[1], rock)
	# Range behind the city, with the statue on the tallest peak.
	for i in 9:
		var c := Vector3(-640 + i * 160.0, 0, 395 + _rng.randf_range(-25, 25))
		var r := Vector3(170, _rng.randf_range(110, 190), 185)
		_blob(c, r, green)
		Layout.hills.append([c, r])
	var peak := Vector3(140, 0, 360)
	_blob(peak, Vector3(120, 260, 130), green)
	Layout.hills.append([peak, Vector3(120, 260, 130)])
	var top := peak + Vector3(0, 258, 0)
	_box(top + Vector3(0, 4, 0), Vector3(9, 8, 9), Color(0.8, 0.8, 0.78))
	_box(top + Vector3(0, 21, 0), Vector3(4.2, 26, 3.4), WHITE)
	_box(top + Vector3(0, 12, 0), Vector3(5.6, 8, 4.4), WHITE)
	_box(top + Vector3(0, 30, 0), Vector3(30, 3, 2.6), WHITE)
	_box(top + Vector3(-14, 28.6, 0), Vector3(3.4, 2.2, 2.4), WHITE, Vector3(0, 0, 0.25))
	_box(top + Vector3(14, 28.6, 0), Vector3(3.4, 2.2, 2.4), WHITE, Vector3(0, 0, -0.25))
	_balls.append(Transform3D(Basis.from_scale(Vector3(2.2, 2.6, 2.2)), top + Vector3(0, 36.5, 0)))
	_ball_tints.append(WHITE)


## Parasols, beach chairs and rental tents: what the sand is covered in.
func _decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 300:
		var p := Vector3(rng.randf_range(-295, 295), 0, rng.randf_range(-30, 36))
		if Layout.on_play_area(p, 2.0):
			continue
		var tint := Color.from_hsv(rng.randf(), 0.75, 0.95)
		_parasol(p, tint)
		if rng.randf() < 0.6:
			var yaw := rng.randf() * TAU
			for side in [-0.6, 0.6]:
				var at := p + Basis(Vector3.UP, yaw) * Vector3(side, 0, 1.0)
				_box(at + Vector3(0, 0.22, 0), Vector3(0.55, 0.06, 1.0), tint.lightened(0.4), Vector3(0.0, yaw, 0.0))
				_box(at + Basis(Vector3.UP, yaw) * Vector3(0, 0.45, -0.6), Vector3(0.55, 0.06, 0.6), tint.lightened(0.4), Vector3(-1.0, yaw, 0.0))
	# Barracas along the waterline: a canopy, a stack of chairs to rent and a flag.
	var x := -280.0
	while x < 285.0:
		var at := Vector3(x + rng.randf_range(-6, 6), 0, rng.randf_range(-33, -29))
		var tint: Color = PROP_TINTS[rng.randi() % PROP_TINTS.size()]
		for cx in [-2.0, 2.0]:
			for cz in [-2.0, 2.0]:
				_box(at + Vector3(cx, 1.2, cz), Vector3(0.08, 2.4, 0.08), STEEL)
		_box(at + Vector3(0, 2.45, 0), Vector3(4.6, 0.1, 4.6), tint)
		_box(at + Vector3(0, 2.25, -2.3), Vector3(4.6, 0.4, 0.05), tint.lightened(0.5))
		_box(at + Vector3(1.4, 0.5, 1.2), Vector3(0.6, 1.0, 0.6), Color(0.95, 0.95, 0.95))
		_box(at + Vector3(-1.3, 0.35, 1.0), Vector3(1.0, 0.7, 0.6), Color(0.2, 0.5, 0.85))
		_box(at + Vector3(2.3, 2.2, 2.3), Vector3(0.05, 4.4, 0.05), STEEL)
		_flag(at + Vector3(2.3, 4.0, 2.3))
		# Shade nobody looks twice into, and a canopy the helicopter cannot see through.
		_collider(at + Vector3(0, 2.45, 0), Vector3(4.6, 0.1, 4.6))
		Places.add_cover(AABB(at - Vector3(2.3, 0.5, 2.3), Vector3(4.6, 3.0, 4.6)), 0.6, false)
		Places.add_hide(at + Vector3(-1.3, 0.2, 0.2), "barraca", at + Vector3(-1.3, 0.2, -0.6))
		x += rng.randf_range(34.0, 46.0)


func _parasol(p: Vector3, tint: Color) -> void:
	_cones.append(Transform3D(Basis(), p + Vector3(0, 2.3, 0)))
	_cone_tints.append(tint)
	_poles.append(Transform3D(Basis(), p + Vector3(0, 1.1, 0)))


## The national flag, flying toward +x from p.
func _flag(p: Vector3) -> void:
	_box(p + Vector3(0.9, 0, 0), Vector3(1.8, 1.2, 0.04), Color(0.0, 0.6, 0.25))
	_box(p + Vector3(0.9, 0, 0), Vector3(0.75, 0.75, 0.06), Color(1.0, 0.85, 0.0), Vector3(0, 0, PI / 4.0))
	_balls.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.05)), p + Vector3(0.9, 0, 0)))
	_ball_tints.append(Color(0.05, 0.15, 0.55))


## Coconut palms: a leaning trunk, a crown of drooping fronds and a few coconuts.
func _palms() -> void:
	var parts: Array = []
	var bark := Color(0.5, 0.4, 0.28)
	var at := Vector3.ZERO
	for k in 5:
		var seg := _cyl(0.2 - k * 0.02, 0.24 - k * 0.02, 1.7, 7)
		var lean := 0.05 + k * 0.035
		parts.append([seg, Transform3D(Basis(Vector3.BACK, lean), at + Vector3(0, 0.8, 0)), bark.darkened(0.12 * (k % 2))])
		at += Basis(Vector3.BACK, lean) * Vector3(0, 1.6, 0)
	for k in 9:
		var yaw := TAU * k / 9.0
		var droop := 0.35 + 0.25 * (k % 3)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -droop)
		var frond := BoxMesh.new()
		frond.size = Vector3(3.4, 0.05, 0.7)
		parts.append([frond, Transform3D(b, at + b * Vector3(1.7, 0, 0)), Color(0.13, 0.5, 0.2).darkened(0.1 * (k % 2))])
		var tip := BoxMesh.new()
		tip.size = Vector3(1.4, 0.04, 0.4)
		var tb := b * Basis(Vector3.BACK, -0.6)
		parts.append([tip, Transform3D(tb, at + b * Vector3(3.3, 0, 0) + tb * Vector3(0.6, 0, 0)), Color(0.16, 0.56, 0.22)])
	for k in 3:
		parts.append([_ball(0.17, -1.0, 6), Transform3D(Basis(), at + Vector3(cos(k * 2.1) * 0.25, -0.25, sin(k * 2.1) * 0.25)), Color(0.3, 0.42, 0.14)])
	var mesh := compose(parts)
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var xf: Array = []
	# A line along the promenade, another down the middle of the avenida, and clumps on the sand.
	for i in 70:
		xf.append(_palm_at(rng, Vector3(-510 + i * 14.6, 0, 41.2)))
	for i in 52:
		var x := -505.0 + i * 19.5
		if absf(x - Layout._nearest(Layout.CROSS_X, x)) > 8.0:
			xf.append(_palm_at(rng, Vector3(x, 0.2, Layout.MEDIAN_Z)))
	for i in 46:
		var p := Vector3(rng.randf_range(-295, 295), 0, rng.randf_range(28, 38))
		if not Layout.on_play_area(p, 3.0):
			xf.append(_palm_at(rng, p))
	_instances(mesh, _vertex_mat(), xf)


func _palm_at(rng: RandomNumberGenerator, p: Vector3) -> Transform3D:
	var s := rng.randf_range(0.85, 1.25)
	return Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), p)


func _vendors() -> void:
	for v in DB.VENDORS:
		if v.pos.z < Layout.ROAD_Z:
			_kiosk(v.pos + Vector3(0, 0, 2.5), v.color, "%s  [F]" % v.name)


func _kiosk(p: Vector3, roof: Color, text: String) -> void:
	_block(p + Vector3(0, 1.2, 0), Vector3(3.2, 2.4, 2.4), Color(0.96, 0.94, 0.88))
	_box(p + Vector3(0, 2.55, -0.3), Vector3(4.6, 0.3, 3.8), roof)
	_box(p + Vector3(0, 2.9, 0), Vector3(3.0, 0.5, 0.2), roof.darkened(0.3))
	_box(p + Vector3(0, 1.05, -1.4), Vector3(3.2, 0.1, 0.5), WOOD)
	_box(p + Vector3(0, 1.7, -1.21), Vector3(2.6, 0.9, 0.04), Color(0.12, 0.14, 0.16))
	_box(p + Vector3(1.9, 0.9, 0.6), Vector3(0.6, 1.8, 0.6), Color(0.9, 0.1, 0.1))
	# A heap of green coconuts by the counter.
	for k in 7:
		_balls.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.17), p + Vector3(-1.9 + (k % 3) * 0.3, 0.17 + (k / 3) * 0.25, -0.9 - (k % 2) * 0.3)))
		_ball_tints.append(Color(0.3, 0.55, 0.2))
	# Tables under parasols on the sea side.
	for side in [-2.4, 0.0, 2.4]:
		var t := p + Vector3(side, 0, -4.2)
		_box(t + Vector3(0, 0.72, 0), Vector3(0.9, 0.06, 0.9), Color(0.95, 0.95, 0.95))
		_box(t + Vector3(0, 0.36, 0), Vector3(0.1, 0.72, 0.1), STEEL)
		var table := Places.new_table()
		for s in 4:
			var off := Vector3(cos(s * PI * 0.5 + 0.6), 0, sin(s * PI * 0.5 + 0.6)) * 0.85
			_box(t + off + Vector3(0, 0.23, 0), Vector3(0.36, 0.46, 0.36), roof.lightened(0.2))
			Places.add_seat(t + off, Kit.face(-off), -1, table)
		_parasol(t, roof.lightened(0.15))
	_sign(text, p + Vector3(0, 3.7, 0), 96, Color.WHITE, 0.0, true)
	Places.add_hide(p + Vector3(0, 0.2, 1.9), "quiosque", p + Vector3(0, 0.2, 2.3))


## Concrete tables with four stools along the calçadão: for dominoes, a beer, an argument.
func _pracas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5381
	var grey := Color(0.74, 0.73, 0.7)
	for i in 14:
		var at := Vector3(-275.0 + i * 42.0 + rng.randf_range(-6.0, 6.0), 0, 44.6)
		var busy := false
		for v in DB.VENDORS:
			busy = busy or (v.pos.z < Layout.ROAD_Z and absf(v.pos.x - at.x) < 7.0)
		for roda in DB.RODAS:
			busy = busy or absf(roda.x - at.x) < 9.0
		if busy:
			continue
		_solid(at + Vector3(0, 0.36, 0), Vector3(0.9, 0.72, 0.9), grey)
		_box(at + Vector3(0, 0.75, 0), Vector3(1.15, 0.07, 1.15), grey.lightened(0.15))
		# A chequer board set into the top.
		for k in 16:
			if (k / 4 + k % 4) % 2 == 0:
				_box(at + Vector3(-0.3 + (k % 4) * 0.2, 0.79, -0.3 + (k / 4) * 0.2), Vector3(0.2, 0.01, 0.2), Color(0.2, 0.2, 0.22))
		var table := Places.new_table()
		for s in 4:
			var off := Vector3(cos(s * PI * 0.5), 0, sin(s * PI * 0.5)) * 0.95
			_box(at + off + Vector3(0, 0.23, 0), Vector3(0.4, 0.46, 0.4), grey.darkened(0.1))
			Places.add_seat(at + off, Kit.face(-off), -1, table)


## Things to duck behind on the open sand: striped windbreaks, upturned fishing boats to
## crawl under, and the scrub along the top of the beach.
func _cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8128
	var n := 0
	while n < 16:
		var p := Vector3(rng.randf_range(-285, 285), 0, rng.randf_range(-22, 26))
		if Layout.on_play_area(p, 3.0):
			continue
		n += 1
		var yaw := rng.randf_range(-0.5, 0.5)
		var tint: Color = PROP_TINTS[rng.randi() % PROP_TINTS.size()]
		_solid(p + Vector3(0, 0.6, 0), Vector3(3.2, 1.2, 0.08), Color(0.97, 0.97, 0.94), Vector3(0, yaw, 0))
		for k in 4:
			_box(p + Basis(Vector3.UP, yaw) * Vector3(-1.2 + k * 0.8, 0.6, 0), Vector3(0.4, 1.2, 0.1), tint, Vector3(0, yaw, 0))
		for side in [-1.6, 1.6]:
			_box(p + Basis(Vector3.UP, yaw) * Vector3(side, 0.75, 0), Vector3(0.06, 1.5, 0.06), WOOD, Vector3(0, yaw, 0))
	for i in 10:
		var p := Vector3(-270.0 + i * 60.0 + rng.randf_range(-12, 12), 0, rng.randf_range(-29, -24))
		var yaw := rng.randf_range(-0.6, 0.6)
		var hull := Color.from_hsv(rng.randf(), 0.55, 0.85)
		_solid(p + Vector3(0, 0.4, 0), Vector3(3.8, 0.8, 1.3), hull, Vector3(0, yaw, 0))
		_box(p + Vector3(0, 0.84, 0), Vector3(3.9, 0.1, 0.16), hull.darkened(0.4), Vector3(0, yaw, 0))
		_box(p + Vector3(0, 0.25, 0), Vector3(3.84, 0.14, 1.34), Color(0.95, 0.95, 0.92), Vector3(0, yaw, 0))
		Places.add_hide(p + Vector3(0, 0.2, 1.4), "barco", p + Vector3(0, 0.2, 1.7))
	# Restinga scrub: no good standing up in, plenty crouched.
	for i in 22:
		var p := Vector3(-290.0 + i * 27.0 + rng.randf_range(-8, 8), 0, rng.randf_range(30.5, 37.5))
		if Layout.on_play_area(p, 3.0):
			continue
		var w := rng.randf_range(3.0, 5.5)
		var d := rng.randf_range(2.0, 3.2)
		for k in 7:
			var g := Color(0.16, 0.42 + rng.randf() * 0.14, 0.18)
			_box(p + Vector3(rng.randf_range(-0.5, 0.5) * w, 0.45, rng.randf_range(-0.5, 0.5) * d), Vector3(rng.randf_range(1.0, 1.7), rng.randf_range(0.7, 1.1), rng.randf_range(1.0, 1.6)), g, Vector3(0, rng.randf() * PI, 0))
		Places.add_cover(AABB(p - Vector3(w * 0.5 + 0.4, 0.5, d * 0.5 + 0.4), Vector3(w + 0.8, 2.5, d + 0.8)), 0.4, true)


## Benches, bins, lamps, pay phones, showers and an outdoor gym along the calçadão.
func _promenade() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	var x := -500.0
	var n := 0
	while x < 500.0:
		# Lamp post with two arms.
		_box(Vector3(x, 3.2, 50.2), Vector3(0.16, 6.4, 0.16), Color(0.2, 0.22, 0.24))
		_box(Vector3(x, 6.3, 50.2), Vector3(0.1, 0.1, 2.6), Color(0.2, 0.22, 0.24))
		_glow(Vector3(x, 6.2, 49.1), Vector3(0.5, 0.14, 0.3), Color(1.0, 0.93, 0.7))
		_glow(Vector3(x, 6.2, 51.3), Vector3(0.5, 0.14, 0.3), Color(1.0, 0.93, 0.7))
		if absf(x) < 310.0:
			var b := Vector3(x + 6.0, 0, 41.4)
			_block(b + Vector3(0, 0.4, 0), Vector3(1.9, 0.1, 0.5), WOOD)
			_box(b + Vector3(0, 0.75, -0.25), Vector3(1.9, 0.5, 0.08), WOOD)
			_box(b + Vector3(-0.8, 0.2, 0), Vector3(0.1, 0.4, 0.5), STEEL)
			_box(b + Vector3(0.8, 0.2, 0), Vector3(0.1, 0.4, 0.5), STEEL)
			# Orange bin.
			_box(Vector3(x + 9.0, 0.55, 41.4), Vector3(0.5, 0.9, 0.5), Color(0.98, 0.5, 0.05))
			_box(Vector3(x + 9.0, 0.05, 41.4), Vector3(0.1, 0.2, 0.1), STEEL)
			if n % 3 == 0:
				_orelhao(Vector3(x - 5.0, 0, 49.4))
			if n % 4 == 2:
				_shower(Vector3(x - 8.0, 0, 38.6))
		x += 21.0
		n += 1
	# Pull-up bars and benches: the open-air gym.
	for gx in [-62.0, 118.0]:
		for k in 3:
			var g := Vector3(gx + k * 2.6, 0, 37.2)
			_block(g + Vector3(-1.0, 1.25, 0), Vector3(0.12, 2.5, 0.12), Color(0.1, 0.45, 0.2))
			_block(g + Vector3(1.0, 1.25, 0), Vector3(0.12, 2.5, 0.12), Color(0.1, 0.45, 0.2))
			_box(g + Vector3(0, 2.2 + k * 0.12, 0), Vector3(2.0, 0.08, 0.08), STEEL)
		_solid(Vector3(gx + 9.0, 0.3, 37.2), Vector3(2.2, 0.6, 0.7), Color(0.1, 0.45, 0.2))
	# Sand castles near the wall.
	for sx in [-205.0, -20.0, 77.0, 232.0]:
		var s := Vector3(sx, 0, 36.6)
		var sand := SAND.darkened(0.12)
		_box(s + Vector3(0, 0.5, 0), Vector3(3.0, 1.0, 3.0), sand)
		_box(s + Vector3(0, 1.3, 0), Vector3(1.6, 0.8, 1.6), sand)
		for cx in [-1.4, 1.4]:
			for cz in [-1.4, 1.4]:
				_box(s + Vector3(cx, 0.8, cz), Vector3(0.6, 1.6, 0.6), sand)
				_cones.append(Transform3D(Basis.from_scale(Vector3(0.3, 1.2, 0.3)), s + Vector3(cx, 1.9, cz)))
				_cone_tints.append(sand)
		_flag(s + Vector3(0, 2.6, 0))
		_box(s + Vector3(0, 2.3, 0), Vector3(0.05, 1.4, 0.05), STEEL)


## Orelhão: the egg-shaped pay phone hood on a post.
func _orelhao(p: Vector3) -> void:
	_box(p + Vector3(0, 0.75, 0), Vector3(0.12, 1.5, 0.12), Color(0.25, 0.25, 0.28))
	for side in [-0.55, 0.55]:
		_balls.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.6, 0.5)), p + Vector3(side, 1.75, 0)))
		_ball_tints.append(Color(0.98, 0.55, 0.05) if side < 0.0 else Color(0.1, 0.35, 0.8))
		_box(p + Vector3(side, 1.45, 0), Vector3(0.2, 0.3, 0.12), Color(0.15, 0.15, 0.15))
	_box(p + Vector3(0, 1.5, 0), Vector3(1.1, 0.08, 0.08), Color(0.25, 0.25, 0.28))


func _shower(p: Vector3) -> void:
	_box(p + Vector3(0, 0.04, 0), Vector3(1.6, 0.08, 1.6), Color(0.6, 0.62, 0.65))
	_box(p + Vector3(0, 1.3, 0), Vector3(0.1, 2.6, 0.1), STEEL)
	_box(p + Vector3(0, 2.55, -0.3), Vector3(0.08, 0.08, 0.6), STEEL)
	_box(p + Vector3(0, 2.45, -0.6), Vector3(0.25, 0.08, 0.25), STEEL)


## Postos: the numbered lifeguard stations every Carioca gives directions by.
func _postos() -> void:
	for i in 6:
		var p := Vector3(-250.0 + i * 100.0, 0, 36.5)
		_solid(p + Vector3(0, 1.6, 0), Vector3(4.4, 3.2, 3.4), WHITE)
		_solid(p + Vector3(0, 3.35, 0), Vector3(5.6, 0.3, 4.6), Color(0.95, 0.5, 0.1))
		_block(p + Vector3(-1.5, 5.2, 0.8), Vector3(1.4, 3.4, 1.4), WHITE)
		_box(p + Vector3(-1.5, 7.0, 0.8), Vector3(1.9, 0.2, 1.9), Color(0.95, 0.5, 0.1))
		_box(p + Vector3(0, 1.4, -1.72), Vector3(1.0, 2.2, 0.06), Color(0.2, 0.45, 0.75))
		# Steps up to the deck from the sand.
		_solid(p + Vector3(3.9, 1.6, 0), Vector3(1.4, 0.25, 7.3), WOOD, Vector3(0.46, PI / 2.0, 0))
		_box(p + Vector3(1.9, 6.0, -1.6), Vector3(0.08, 5.0, 0.08), STEEL)
		_flag(p + Vector3(1.9, 7.8, -1.6))
		_sign("POSTO %d" % (i + 1), p + Vector3(0, 2.4, -1.75), 220, Color(0.1, 0.25, 0.6), PI)
		_sign("POSTO %d" % (i + 1), p + Vector3(0, 2.4, 1.75), 220, Color(0.1, 0.25, 0.6))


## Football pitches roped off on the sand, and the futevolei courts by the wall.
func _pitches() -> void:
	var line := Color(0.98, 0.98, 0.95)
	for rect in Layout.PITCHES:
		var c: Vector3 = rect[0]
		var h: Vector2 = rect[1]
		for side in [-1.0, 1.0]:
			_box(c + Vector3(0, 0.03, side * h.y), Vector3(h.x * 2.0, 0.05, 0.12), line)
			_box(c + Vector3(side * h.x, 0.03, 0), Vector3(0.12, 0.05, h.y * 2.0), line)
			# Goal: two posts, a bar and a sagging net behind.
			var g := c + Vector3(side * h.x, 0, 0)
			for post in [-Layout.GOAL_HALF, Layout.GOAL_HALF]:
				_block(g + Vector3(0, Layout.GOAL_H * 0.5, post), Vector3(0.14, Layout.GOAL_H, 0.14), line)
			_block(g + Vector3(0, Layout.GOAL_H, 0), Vector3(0.14, 0.14, Layout.GOAL_HALF * 2.0 + 0.14), line)
			_block(g + Vector3(side * 1.3, Layout.GOAL_H * 0.5, 0), Vector3(0.06, Layout.GOAL_H, Layout.GOAL_HALF * 2.0), Color(0.85, 0.85, 0.85))
			for post in [-Layout.GOAL_HALF, Layout.GOAL_HALF]:
				_box(g + Vector3(side * 0.65, Layout.GOAL_H * 0.5, post), Vector3(1.3, Layout.GOAL_H, 0.04), Color(0.85, 0.85, 0.85))
			_box(g + Vector3(side * 0.65, Layout.GOAL_H, 0), Vector3(1.3, 0.04, Layout.GOAL_HALF * 2.0), Color(0.85, 0.85, 0.85))
			for cz in [-h.y, h.y]:
				_box(g + Vector3(0, 0.6, cz), Vector3(0.05, 1.2, 0.05), STEEL)
				_box(g + Vector3(0.2, 1.05, cz), Vector3(0.4, 0.25, 0.03), Color(0.95, 0.2, 0.15))
		_box(c + Vector3(0, 0.03, 0), Vector3(0.12, 0.05, h.y * 2.0), line)
	for rect in Layout.COURTS:
		var c: Vector3 = rect[0]
		var h: Vector2 = rect[1]
		for side in [-1.0, 1.0]:
			_box(c + Vector3(0, 0.03, side * h.y), Vector3(h.x * 2.0, 0.05, 0.1), Color(0.1, 0.3, 0.8))
			_box(c + Vector3(side * h.x, 0.03, 0), Vector3(0.1, 0.05, h.y * 2.0), Color(0.1, 0.3, 0.8))
			_block(c + Vector3(0, 1.2, side * (h.y + 0.3)), Vector3(0.12, 2.4, 0.12), Color(0.95, 0.8, 0.1))
		# Slide under it or go round: the net hangs clear of the sand.
		_solid(c + Vector3(0, 1.75, 0), Vector3(0.06, 1.0, h.y * 2.0 + 0.6), Color(0.95, 0.95, 0.95))
		_box(c + Vector3(0, 2.28, 0), Vector3(0.08, 0.08, h.y * 2.0 + 0.6), Color(0.95, 0.8, 0.1))


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
			if not Layout.on_play_area(at, 9.0):
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
		var p := at + Vector3((i - 1) * 7.5, 2.25, side)
		_solid(p, Vector3(9.0, 4.5, 0.4), tint if i != 1 else tint.lightened(0.35))
		# Advertising hoarding: a frame, legs and a pale panel.
		_box(p, Vector3(8.2, 3.6, 0.44), Color(0.97, 0.96, 0.9))
		_box(p + Vector3(0, -0.6, 0), Vector3(7.0, 0.5, 0.46), tint.darkened(0.2))
		_box(p + Vector3(-2.0, 0.6, 0), Vector3(2.4, 1.2, 0.46), tint.lightened(0.2))


## Lifeguard tower: a lookout three metres up, reached by its ramp.
func _lifeguard(at: Vector3) -> void:
	_solid(at + Vector3(0, 1.5, 0), Vector3(3.2, 3.0, 3.2), Color(0.96, 0.96, 0.94))
	_box(at + Vector3(0, 2.6, 0), Vector3(3.3, 0.4, 3.3), Color(0.9, 0.15, 0.12))
	_solid(at + Vector3(0, 1.36, 4.96), Vector3(1.8, 0.3, 7.36), WOOD, Vector3(0.42, 0, 0))
	_box(at + Vector3(1.3, 4.5, -1.3), Vector3(0.1, 3.0, 0.1), Color(0.8, 0.8, 0.8))
	_box(at + Vector3(1.3, 5.7, -0.95), Vector3(0.05, 0.5, 0.7), Color(0.9, 0.15, 0.12))
	# Rail round the deck and a rescue board leaning on the side.
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * 1.55, 3.5, 0), Vector3(0.06, 0.06, 3.2), Color(0.9, 0.15, 0.12))
		_box(at + Vector3(side * 1.55, 3.25, -1.55), Vector3(0.06, 0.5, 0.06), Color(0.9, 0.15, 0.12))
	_box(at + Vector3(0, 3.5, -1.55), Vector3(3.2, 0.06, 0.06), Color(0.9, 0.15, 0.12))
	_box(at + Vector3(-1.85, 1.2, 0), Vector3(0.1, 2.4, 0.55), Color(0.98, 0.8, 0.1), Vector3(0, 0, 0.12))


## Beach hut with a crate beside it as a step up to the roof.
func _hut(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 4.0), Color(0.96, 0.94, 0.88))
	_box(at + Vector3(0, 2.45, 0), Vector3(4.3, 0.12, 4.3), tint)
	_box(at + Vector3(0, 1.0, -2.01), Vector3(1.0, 2.0, 0.05), tint.darkened(0.4))
	_solid(at + Vector3(2.7, 0.45, 0.8), Vector3(1.3, 0.9, 1.3), WOOD)
	# Shuttered window, striped skirting and a surfboard propped by the door.
	_box(at + Vector3(-1.1, 1.5, -2.01), Vector3(0.9, 0.8, 0.05), tint)
	for k in 5:
		_box(at + Vector3(-1.6 + k * 0.8, 0.25, 2.01), Vector3(0.4, 0.5, 0.04), tint)
	_box(at + Vector3(1.4, 1.1, -2.2), Vector3(0.5, 2.1, 0.08), tint.lightened(0.3), Vector3(0.12, 0, 0))


## A kicker ramp into a line of crates to hop along.
func _crate_run(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(-7.0, 0.63, 0), Vector3(2.4, 0.25, 4.5), tint, Vector3(0.33, -PI / 2.0, 0))
	var heights := [0.9, 0.9, 1.7, 0.9]
	for i in heights.size():
		var h: float = heights[i]
		var p := at + Vector3(-1.0 + i * 3.2, h * 0.5, 0)
		_solid(p, Vector3(1.3, h, 1.3), WOOD if i != 2 else WOOD.darkened(0.2))
		# Slats so they read as crates.
		_box(p, Vector3(1.34, 0.08, 1.34), WOOD.darkened(0.35))
		_box(p + Vector3(0, h * 0.5 - 0.05, 0), Vector3(1.36, 0.1, 1.36), WOOD.darkened(0.3))


## A fence whose only way through is a gap too low to pass standing up.
func _slide_fence(at: Vector3, tint: Color) -> void:
	_solid(at + Vector3(0, 1.2, -4.0), Vector3(0.4, 2.4, 5.0), tint)
	_solid(at + Vector3(0, 1.2, 4.0), Vector3(0.4, 2.4, 5.0), tint)
	_solid(at + Vector3(0, 1.7, 0), Vector3(0.4, 1.4, 3.0), tint.darkened(0.3))
	for z in [-6.5, -1.5, 1.5, 6.5]:
		_box(at + Vector3(0, 1.3, z), Vector3(0.5, 2.6, 0.16), tint.darkened(0.45))
