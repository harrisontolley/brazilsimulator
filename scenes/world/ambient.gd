extends "res://scenes/world/world_kit.gd"
## Life that is only there to be looked at: birds, kites, boats, dogs, aircraft, clouds,
## and the sun going down over the match. All of it is a function of the match clock, so
## it costs no bandwidth and every player sees the same sky.

## Sun direction (toward the sun), sun colour and energy, sky top, sky horizon, ambient
## colour and energy, and how far into the night it is, at fractions of the match.
const DAY := [
	[0.0, Vector3(-0.45, 0.8, -0.5), Color(1.0, 0.95, 0.85), 1.0, Color(0.16, 0.45, 0.85), Color(0.62, 0.8, 0.95), Color(0.72, 0.78, 0.9), 0.55, 0.0],
	[0.55, Vector3(-0.7, 0.5, -0.45), Color(1.0, 0.88, 0.7), 1.0, Color(0.18, 0.42, 0.8), Color(0.75, 0.8, 0.85), Color(0.75, 0.76, 0.82), 0.55, 0.0],
	[0.82, Vector3(-0.9, 0.16, -0.35), Color(1.0, 0.6, 0.32), 0.9, Color(0.24, 0.3, 0.62), Color(1.0, 0.62, 0.38), Color(0.8, 0.62, 0.6), 0.5, 0.45],
	[1.0, Vector3(-0.9, 0.04, -0.3), Color(0.95, 0.42, 0.35), 0.3, Color(0.07, 0.09, 0.26), Color(0.7, 0.36, 0.4), Color(0.42, 0.42, 0.62), 0.5, 1.0],
]

## Set by Game before this enters the tree.
var world: Node3D
## Where the police helicopter is, for anyone who wants to hear it.
var heli_pos := Vector3(0, 60, 40)
## True while the helicopter has someone in its light.
var heli_hunting := false

var _birds: MultiMesh
var _bird_n := 0
var _kites: MultiMesh
var _strings: MultiMesh
var _kite_at: Array = []
var _boats: MultiMesh
var _boat_home: Array = []
var _skis: MultiMesh
var _surf: MultiMesh
var _heads: MultiMesh
var _head_home: Array = []
var _volley: MultiMesh
var _clouds: MultiMesh
var _cloud_home: Array = []
var _banner: Node3D
var _heli: Node3D
var _rotor: Node3D
var _spot: SpotLight3D
var _gondola: Node3D
var _ship: Node3D
var _gliders: Array = []
var _day_t := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8086
	_build_birds(rng)
	_build_kites(rng)
	_build_sea(rng)
	_build_sky(rng)
	_apply_day()


func _build_birds(rng: RandomNumberGenerator) -> void:
	var white := Color.WHITE
	var mesh := compose([
		part(Vector3.ZERO, Vector3(0.14, 0.12, 0.5), white),
		part(Vector3(-0.4, 0.08, 0), Vector3(0.8, 0.03, 0.24), white, Vector3(0, 0, -0.28)),
		part(Vector3(0.4, 0.08, 0), Vector3(0.8, 0.03, 0.24), white, Vector3(0, 0, 0.28)),
	])
	_bird_n = 64
	var xf: Array = []
	var tint: Array = []
	for i in _bird_n:
		xf.append(Transform3D())
		# Gulls over the water, black urubus wheeling above the hill.
		tint.append(Color(0.96, 0.96, 0.96, rng.randf()) if i < 44 else Color(0.08, 0.08, 0.09, rng.randf()))
	_birds = _free_multi(mesh, xf, tint)


func _build_kites(rng: RandomNumberGenerator) -> void:
	var mesh := compose([
		part(Vector3.ZERO, Vector3(0.9, 0.9, 0.03), Color.WHITE, Vector3(0, 0, PI / 4.0)),
		part(Vector3(0, -1.1, 0), Vector3(0.08, 1.2, 0.02), Color(0.9, 0.9, 0.9)),
	])
	var xf: Array = []
	var tint: Array = []
	for i in 16:
		var t := rng.randi() % Layout.TERRACES
		_kite_at.append([Vector3(rng.randf_range(-280, 280), (t + 2) * Layout.TERRACE_H, Layout.FAVELA_Z + t * Layout.TERRACE_D + 5.0), rng.randf_range(14.0, 30.0), rng.randf() * TAU])
		xf.append(Transform3D())
		tint.append(Color.from_hsv(rng.randf(), 0.8, 1.0))
	_kites = _free_multi(mesh, xf, tint)
	_strings = _free_multi(_box_mesh(Vector3(0.02, 0.02, 1.0)), xf, [], false)
	_strings.get_meta("node").material_override = _mat(Color(0.9, 0.9, 0.9))


func _build_sea(rng: RandomNumberGenerator) -> void:
	# Fishing boats and sail boats riding at anchor, drifting a little.
	var hull := compose([
		part(Vector3(0, 0.3, 0), Vector3(4.6, 0.9, 1.5), Color.WHITE),
		part(Vector3(2.5, 0.45, 0), Vector3(1.0, 0.6, 1.1), Color.WHITE, Vector3(0, 0, 0.5)),
		part(Vector3(-0.8, 1.1, 0), Vector3(1.3, 0.9, 1.1), Color(0.95, 0.95, 0.95)),
		part(Vector3(0.6, 2.6, 0), Vector3(0.08, 4.4, 0.08), Color(0.6, 0.5, 0.4)),
		part(Vector3(1.4, 2.6, 0), Vector3(1.5, 3.2, 0.03), Color(0.97, 0.97, 0.94)),
	])
	var xf: Array = []
	var tint: Array = []
	for i in 14:
		_boat_home.append([Vector3(rng.randf_range(-420, 420), 0.35, rng.randf_range(-260, -95)), rng.randf() * TAU, rng.randf_range(0.8, 1.6)])
		xf.append(Transform3D())
		tint.append(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.8), 0.9))
	_boats = _free_multi(hull, xf, tint)

	var ski := compose([
		part(Vector3(0, 0.25, 0), Vector3(2.2, 0.5, 0.8), Color.WHITE),
		part(Vector3(0.4, 0.7, 0), Vector3(0.3, 0.5, 0.6), Color(0.1, 0.1, 0.1)),
		part(Vector3(-0.3, 0.95, 0), Vector3(0.35, 0.8, 0.4), Color(0.9, 0.6, 0.4)),
	])
	xf.clear()
	tint.clear()
	for i in 4:
		xf.append(Transform3D())
		tint.append(Color.from_hsv(i * 0.27, 0.8, 1.0))
	_skis = _free_multi(ski, xf, tint)

	var board := compose([
		part(Vector3(0, 0.05, 0), Vector3(0.5, 0.08, 2.0), Color.WHITE),
		part(Vector3(0, 0.6, 0.1), Vector3(0.3, 1.0, 0.3), Color(0.75, 0.52, 0.36)),
		part(Vector3(0, 1.2, 0.1), Vector3(0.26, 0.26, 0.26), Color(0.75, 0.52, 0.36)),
	])
	xf.clear()
	tint.clear()
	for i in 12:
		xf.append(Transform3D())
		tint.append(Color.from_hsv(rng.randf(), 0.5, 1.0))
	_surf = _free_multi(board, xf, tint)

	# Heads of the people who went for a swim.
	xf.clear()
	tint.clear()
	for i in 90:
		_head_home.append(Vector3(rng.randf_range(-290, 290), 0.25, rng.randf_range(-58.0, -41.0)))
		xf.append(Transform3D())
		tint.append([Color(0.96, 0.76, 0.6), Color(0.66, 0.45, 0.3), Color(0.45, 0.3, 0.2), Color(0.85, 0.62, 0.44)][i % 4])
	_heads = _free_multi(_ball(0.2, -1.0, 6), xf, tint)

	xf.clear()
	for i in Layout.COURTS.size():
		xf.append(Transform3D())
	_volley = _free_multi(_ball(0.16, -1.0, 8), xf, [])
	_volley.get_meta("node").material_override = _mat(Color(0.98, 0.98, 0.95))

	# A liner and a tanker out on the horizon.
	_ship = Node3D.new()
	add_child(_ship)
	var liner := MeshInstance3D.new()
	liner.mesh = compose([
		part(Vector3(0, 6, 0), Vector3(170, 12, 24), Color(0.96, 0.96, 0.97)),
		part(Vector3(-5, 15, 0), Vector3(130, 6, 20), Color(0.9, 0.92, 0.95)),
		part(Vector3(-8, 21, 0), Vector3(100, 6, 17), Color(0.96, 0.96, 0.97)),
		part(Vector3(-20, 28, 0), Vector3(9, 9, 8), Color(0.1, 0.2, 0.5)),
		part(Vector3(10, 28, 0), Vector3(9, 9, 8), Color(0.1, 0.2, 0.5)),
		part(Vector3(0, 1.5, 0), Vector3(171, 3, 24.4), Color(0.12, 0.15, 0.3)),
	])
	liner.material_override = _vertex_mat()
	_ship.add_child(liner)
	var tanker := MeshInstance3D.new()
	tanker.mesh = compose([
		part(Vector3(0, 4, 0), Vector3(230, 9, 34), Color(0.5, 0.14, 0.1)),
		part(Vector3(0, 9, 0), Vector3(180, 1.5, 28), Color(0.55, 0.5, 0.45)),
		part(Vector3(-95, 18, 0), Vector3(20, 20, 26), Color(0.93, 0.93, 0.9)),
	])
	tanker.material_override = _vertex_mat()
	tanker.position = Vector3(900, 0, -500)
	_ship.add_child(tanker)


func _build_sky(rng: RandomNumberGenerator) -> void:
	var xf: Array = []
	for i in 16:
		_cloud_home.append([Vector3(rng.randf_range(-1400, 1400), rng.randf_range(260, 420), rng.randf_range(-900, 700)), Vector3(rng.randf_range(90, 220), rng.randf_range(18, 34), rng.randf_range(60, 120))])
		xf.append(Transform3D())
	_clouds = _free_multi(_ball(1.0, 2.0, 10), xf, [], false)
	var cm := _mat(Color(1, 1, 1, 0.85))
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_clouds.get_meta("node").material_override = cm

	# Banner plane up and down the coast.
	_banner = Node3D.new()
	add_child(_banner)
	var body := MeshInstance3D.new()
	body.mesh = compose([
		part(Vector3.ZERO, Vector3(7.0, 1.1, 1.1), Color(0.95, 0.85, 0.1)),
		part(Vector3(0.6, 0.4, 0), Vector3(1.6, 0.15, 10.0), Color(0.95, 0.85, 0.1)),
		part(Vector3(-3.1, 0.8, 0), Vector3(0.9, 1.5, 0.12), Color(0.85, 0.2, 0.1)),
		part(Vector3(-3.1, 0.3, 0), Vector3(0.9, 0.1, 3.2), Color(0.85, 0.2, 0.1)),
		part(Vector3(-30.0, 0, 0), Vector3(34.0, 5.0, 0.1), Color(0.98, 0.98, 0.95)),
		part(Vector3(-8.5, 0, 0), Vector3(9.0, 0.05, 0.05), Color(0.2, 0.2, 0.2)),
	])
	body.material_override = _vertex_mat()
	_banner.add_child(body)
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "CERVEJA GELADA  R$5"
		l.font_size = 640
		l.outline_size = 0
		l.modulate = Color(0.85, 0.1, 0.1)
		l.double_sided = false
		l.position = Vector3(-30.0, 0, side * 0.08)
		l.rotation.y = 0.0 if side > 0.0 else PI
		_banner.add_child(l)

	# Police helicopter.
	_heli = Node3D.new()
	add_child(_heli)
	var hb := MeshInstance3D.new()
	hb.mesh = compose([
		part(Vector3(0, 0, 0), Vector3(2.0, 1.8, 3.6), Color(0.1, 0.18, 0.5)),
		part(Vector3(0, 0.2, -1.3), Vector3(1.7, 1.0, 1.2), Color(0.15, 0.2, 0.25)),
		part(Vector3(0, 0.3, 3.6), Vector3(0.4, 0.5, 4.2), Color(0.92, 0.92, 0.92)),
		part(Vector3(0, 1.0, 5.5), Vector3(0.12, 1.6, 0.6), Color(0.1, 0.18, 0.5)),
		part(Vector3(0, -1.2, 0), Vector3(2.2, 0.1, 3.0), Color(0.2, 0.2, 0.2)),
	])
	hb.material_override = _vertex_mat()
	_heli.add_child(hb)
	_rotor = Node3D.new()
	_rotor.position.y = 1.2
	_heli.add_child(_rotor)
	for k in 2:
		var blade := MeshInstance3D.new()
		blade.mesh = _box_mesh(Vector3(10.0, 0.06, 0.35))
		blade.material_override = _mat(Color(0.15, 0.15, 0.15))
		blade.rotation.y = k * PI / 2.0
		_rotor.add_child(blade)
	_heli.add_child(Sfx.emitter("heli", 6.0, 24.0, 300.0))
	_spot = SpotLight3D.new()
	_spot.rotation.x = -PI / 2.0
	_spot.spot_range = 120.0
	_spot.spot_angle = 9.0
	_spot.light_energy = 0.0
	_spot.light_color = Color(0.9, 0.95, 1.0)
	_heli.add_child(_spot)

	# Cable car between the two peaks, and hang gliders coming off the hills.
	_gondola = Node3D.new()
	add_child(_gondola)
	var gm := MeshInstance3D.new()
	gm.mesh = compose([part(Vector3(0, -3, 0), Vector3(5, 4, 4), Color(0.9, 0.15, 0.1)), part(Vector3(0, -0.5, 0), Vector3(0.3, 1.2, 0.3), Color(0.2, 0.2, 0.2))])
	gm.material_override = _vertex_mat()
	_gondola.add_child(gm)
	for i in 3:
		var g := MeshInstance3D.new()
		g.mesh = compose([
			part(Vector3(-1.6, 0, 0.5), Vector3(3.6, 0.05, 1.6), Color.from_hsv(i * 0.31, 0.8, 1.0), Vector3(0, 0.35, 0)),
			part(Vector3(1.6, 0, 0.5), Vector3(3.6, 0.05, 1.6), Color.from_hsv(i * 0.31 + 0.1, 0.8, 1.0), Vector3(0, -0.35, 0)),
			part(Vector3(0, -0.9, 0.6), Vector3(0.3, 0.3, 1.4), Color(0.2, 0.2, 0.25)),
		])
		g.material_override = _vertex_mat()
		add_child(g)
		_gliders.append(g)


## A MultiMesh whose instances roam the whole map, so it is never culled. `shadows`: whether
## it is near enough the ground for its shadow to be worth drawing.
func _free_multi(mesh: Mesh, xf: Array, tint: Array, shadows := true) -> MultiMesh:
	var mmi := _instances(mesh, _vertex_mat(), xf, tint)
	mmi.custom_aabb = AABB(Vector3(-1500, -5, -1200), Vector3(3000, 500, 2000))
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.multimesh.set_meta("node", mmi)
	return mmi.multimesh


func _process(delta: float) -> void:
	var t := MatchState.time
	_day_t -= delta
	var ev = Net.game.events if Net.game != null else null
	if _day_t <= 0.0 or (ev != null and (ev.storm > 0.0 or ev.flash > 0.0)):
		_day_t = 0.5
		_apply_day()

	for i in _bird_n:
		var gull := i < 44
		var ph := i * 2.399
		var c := Vector3(sin(ph * 3.1) * 280.0, 0, -40.0 + cos(ph * 1.7) * 60.0) if gull else Vector3(sin(ph * 3.1) * 260.0, 0, 170.0 + cos(ph * 1.7) * 30.0)
		var r := 14.0 + fmod(ph * 7.0, 26.0)
		var a := t * (0.35 if gull else 0.16) * (1.0 if i % 2 == 0 else -1.0) + ph
		var p := c + Vector3(cos(a) * r, (14.0 if gull else 60.0) + sin(t * 0.3 + ph) * 5.0 + fmod(ph, 12.0), sin(a) * r)
		var flap := sin(t * (7.0 if gull else 1.2) + ph) * 0.35
		var b := Basis(Vector3.UP, -a + (0.0 if i % 2 == 0 else PI)) * Basis(Vector3.BACK, 0.35 * (1.0 if i % 2 == 0 else -1.0)) * Basis.from_scale(Vector3(1.6, 1.6 + flap, 1.6) * (1.0 if gull else 2.2))
		_birds.set_instance_transform(i, Transform3D(b, p))

	for i in _kite_at.size():
		var k: Array = _kite_at[i]
		var hold: Vector3 = k[0]
		var ph: float = k[2]
		var p := hold + Vector3(sin(t * 0.7 + ph) * 5.0 + 6.0, k[1] + sin(t * 1.3 + ph) * 2.0, -8.0 + cos(t * 0.5 + ph) * 4.0)
		_kites.set_instance_transform(i, Transform3D(Basis(Vector3.FORWARD, sin(t * 2.0 + ph) * 0.3) * Basis(Vector3.RIGHT, -0.5), p))
		var mid := (hold + p) * 0.5
		_strings.set_instance_transform(i, Transform3D(Basis.looking_at(p - hold, Vector3.UP) * Basis.from_scale(Vector3(1, 1, hold.distance_to(p))), mid))

	for i in _boat_home.size():
		var h: Array = _boat_home[i]
		var home: Vector3 = h[0]
		var ph: float = h[1]
		var p := home + Vector3(sin(t * 0.05 + ph) * 12.0, sin(t * 1.1 + ph) * 0.12, cos(t * 0.04 + ph) * 8.0)
		var b := Basis(Vector3.UP, ph + sin(t * 0.06 + ph) * 0.4) * Basis(Vector3.RIGHT, sin(t * 0.9 + ph) * 0.06) * Basis.from_scale(Vector3.ONE * h[2])
		_boats.set_instance_transform(i, Transform3D(b, p))

	for i in 4:
		# Jet skis carve long figure eights just beyond the swimmers.
		var a := t * 0.22 + i * 1.7
		var p := Vector3(-200.0 + i * 130.0 + sin(a) * 90.0, 0.3 + absf(sin(t * 3.0 + i)) * 0.15, -85.0 + sin(a * 2.0) * 22.0)
		var v := Vector3(cos(a) * 90.0, 0, cos(a * 2.0) * 44.0)
		_skis.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(-v.z, v.x)) * Basis(Vector3.BACK, 0.12), p))

	for i in 12:
		# Surfers sit out the back, then ride a wave in.
		var ph := i * 1.9
		var u := fposmod(t * 0.08 + ph * 0.13, 1.0)
		var ride := smoothstep(0.6, 1.0, u)
		var p := Vector3(-270.0 + i * 49.0 + sin(ph) * 14.0 + ride * 14.0, 0.25 + sin(t * 1.4 + ph) * 0.1, lerpf(-78.0, -44.0, ride))
		_surf.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.4 + ride * 0.5), p))

	for i in _head_home.size():
		var home: Vector3 = _head_home[i]
		_heads.set_instance_transform(i, Transform3D(Basis(), home + Vector3(sin(t * 0.3 + i) * 1.5, sin(t * 1.5 + i * 0.7) * 0.1, cos(t * 0.25 + i) * 1.0)))

	for i in Layout.COURTS.size():
		var c: Vector3 = Layout.COURTS[i][0]
		var u := fposmod(t * 0.55 + i * 0.37, 2.0)
		var k := u if u < 1.0 else 2.0 - u
		_volley.set_instance_transform(i, Transform3D(Basis(), c + Vector3(lerpf(-5.0, 5.0, k), 1.2 + sin(fposmod(u, 1.0) * PI) * 3.2, sin(i + floorf(t * 0.55)) * 1.5)))

	for i in _cloud_home.size():
		var h: Array = _cloud_home[i]
		var home: Vector3 = h[0]
		var p := home + Vector3(fposmod(t * 4.0 + home.x + 1400.0, 2800.0) - 1400.0 - home.x, 0, 0)
		_clouds.set_instance_transform(i, Transform3D(Basis.from_scale(h[1]), p))

	var px := fposmod(t * 32.0, 2400.0) - 1200.0
	_banner.position = Vector3(px, 70.0 + sin(t * 0.2) * 4.0, -130.0)
	_ship.position = Vector3(fposmod(t * 2.5, 3000.0) - 1500.0, 0, -1150.0)
	var gk := 0.5 + 0.5 * sin(t * 0.08)
	_gondola.position = Vector3(-520, 189, -150).lerp(Vector3(-440, 84, -40), gk)
	for i in _gliders.size():
		var u := fposmod(t * 0.012 + i * 0.33, 1.0)
		var a := u * 9.0 + i * 2.0
		var g: MeshInstance3D = _gliders[i]
		g.position = Vector3(120.0 + i * 60.0 - u * 260.0 + cos(a) * 40.0, lerpf(190.0, 30.0, u), lerpf(250.0, -20.0, u) + sin(a) * 40.0)
		g.rotation = Vector3(0.1, -a, 0.3)
	_fly_heli(t, delta)


## The helicopter circles the coast until somebody is wanted badly enough to follow.
func _fly_heli(t: float, delta: float) -> void:
	var centre := Vector3(sin(t * 0.05) * 220.0, 0, 60.0)
	var radius := 60.0
	var best := 1
	heli_hunting = false
	if Net.game != null:
		for pid in Net.game.players:
			var pl = Net.game.players[pid]
			if pl.st.heat > best and not pl.st.dead and pl.st.jail <= 0.0:
				best = pl.st.heat
				centre = pl.global_position
				radius = 22.0
				heli_hunting = pl.st.heat >= 3
	var a := t * 0.45
	var goal := centre + Vector3(cos(a) * radius, 58.0, sin(a) * radius)
	var before := heli_pos
	heli_pos = heli_pos.lerp(goal, minf(1.0, 0.8 * delta))
	_heli.position = heli_pos
	var v := heli_pos - before
	if v.length() > 0.001:
		_heli.rotation.y = lerp_angle(_heli.rotation.y, atan2(-v.x, -v.z), minf(1.0, 3.0 * delta))
	_heli.rotation.x = -0.12
	_rotor.rotation.y += 30.0 * delta
	_spot.light_energy = lerpf(_spot.light_energy, 40.0 if heli_hunting else 0.0, minf(1.0, 4.0 * delta))
	if heli_hunting:
		_spot.look_at(centre + Vector3(0, 1, 0), Vector3.FORWARD)


func _apply_day() -> void:
	if world == null:
		return
	var f := clampf(MatchState.time / maxf(MatchState.duration, 1.0), 0.0, 1.0)
	var k := 0
	while k < DAY.size() - 2 and f > DAY[k + 1][0]:
		k += 1
	var a: Array = DAY[k]
	var b: Array = DAY[k + 1]
	var u := clampf((f - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var dir: Vector3 = a[1].lerp(b[1], u).normalized()
	world.sun.look_at_from_position(dir * 100.0, Vector3.ZERO)
	world.sun.light_color = a[2].lerp(b[2], u)
	world.sun.light_energy = lerpf(a[3], b[3], u)
	world.sky_mat.sky_top_color = a[4].lerp(b[4], u)
	world.sky_mat.sky_horizon_color = a[5].lerp(b[5], u)
	world.sky_mat.ground_horizon_color = a[5].lerp(b[5], u)
	world.env.fog_light_color = a[5].lerp(b[5], u)
	world.env.ambient_light_color = a[6].lerp(b[6], u)
	world.env.ambient_light_energy = lerpf(a[7], b[7], u)
	# A downpour greys everything out; lightning whites it for an instant.
	var ev = Net.game.events if Net.game != null else null
	var storm: float = ev.storm if ev != null else 0.0
	var flash: float = ev.flash if ev != null else 0.0
	var grey := Color(0.3, 0.33, 0.38)
	world.sun.light_energy = world.sun.light_energy * (1.0 - 0.75 * storm) + flash * 2.5
	world.sky_mat.sky_top_color = world.sky_mat.sky_top_color.lerp(grey.darkened(0.3), storm * 0.9)
	world.sky_mat.sky_horizon_color = world.sky_mat.sky_horizon_color.lerp(grey, storm * 0.9)
	world.sky_mat.ground_horizon_color = world.sky_mat.sky_horizon_color
	world.env.fog_light_color = world.sky_mat.sky_horizon_color
	world.env.fog_density = lerpf(0.0004, 0.007, storm)
	world.env.ambient_light_energy += flash * 0.8
	var night := lerpf(a[8], b[8], u)
	for m in night_mats:
		m.set_shader_parameter("night", night)
