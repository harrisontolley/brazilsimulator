extends Node3D
## Combat visuals: tracers, muzzle flashes and comic impact bursts, and what a fight leaves
## behind it: blood on the ground and up the wall, bullet holes, smoke, fire, scorch marks.
##
## Anything there can be a lot of at once (flying bits, puffs of smoke, marks on surfaces) is
## an instance in a pool that the shader moves by itself; launching one is a few numbers
## written into a slot, and the oldest slot is the one reused.

const BITS := 1400
const PUFFS := 500
const MARKS := 420
const BLOOD := Color(0.5, 0.01, 0.02)
## Marks: shader kinds.
enum { MARK_BLOOD, MARK_HOLE, MARK_SCORCH }


var _star: ArrayMesh
var _beam: BoxMesh
var _mats := {}
var _shells := 0
var _bits: MultiMesh
var _puffs: MultiMesh
var _marks: MultiMesh
var _bit_n := 0
var _puff_n := 0
var _mark_n := 0
var _pool_mats: Array[ShaderMaterial] = []
var _fires: Array = []   # [where, radius, Kit clock time it goes out, next flame]


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

	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_bits = _pool(cube, "res://shaders/fx_bits.gdshader", BITS, true)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	_puffs = _pool(ball, "res://shaders/fx_puff.gdshader", PUFFS, false)
	var flat := PlaneMesh.new()
	flat.size = Vector2.ONE
	_marks = _pool(flat, "res://shaders/fx_decal.gdshader", MARKS, false)


func _pool(mesh: Mesh, shader: String, n: int, shadows: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -80, 0)))
		mm.set_instance_custom_data(i, Color(0, 0, 0, -1000.0))
	var mat := ShaderMaterial.new()
	mat.shader = load(shader)
	_pool_mats.append(mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-400, -10, -120), Vector3(800, 120, 330))
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _clock() -> float:
	return Time.get_ticks_msec() * 0.001


func _process(delta: float) -> void:
	var now := _clock()
	for m in _pool_mats:
		m.set_shader_parameter("now", now)
	# Fires keep throwing up flame for as long as they burn.
	for k in range(_fires.size() - 1, -1, -1):
		var f: Array = _fires[k]
		if now >= f[2]:
			_fires.remove_at(k)
			continue
		if now >= f[3]:
			f[3] = now + 0.045
			var dying: float = clampf((f[2] - now) / 1.5, 0.2, 1.0)
			for j in 3:
				var a := randf() * TAU
				var r: float = sqrt(randf()) * f[1] * dying
				var at: Vector3 = f[0] + Vector3(cos(a) * r, 0.1, sin(a) * r)
				puff(at, Vector3(randf_range(-0.3, 0.3), randf_range(1.8, 3.6) * dying, randf_range(-0.3, 0.3)), randf_range(0.5, 1.0), Color(1.0, randf_range(0.3, 0.62), 0.04, 1.0))
			if randf() < 0.25:
				puff(f[0] + Vector3(randf_range(-1, 1), 1.6, randf_range(-1, 1)), Vector3(0, 1.8, 0), 0.8, Color(0.1, 0.1, 0.1, 0.3))


## Throws one small solid thing from `at` at `vel`. `floor_y` is where the ground is under it.
func bit(at: Vector3, vel: Vector3, size: float, color: Color, floor_y := 0.0) -> void:
	var i := _bit_n % BITS
	_bit_n += 1
	_bits.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)).scaled(Vector3.ONE * size), at))
	_bits.set_instance_color(i, Color(color.r, color.g, color.b, clampf((at.y - floor_y) / 4.0, 0.0, 1.0)))
	_bits.set_instance_custom_data(i, Color(vel.x, vel.y, vel.z, _clock()))


## One puff of something soft at `at`, drifting off at `vel`. `color.a` is how thick it is;
## give it 1 for flame.
func puff(at: Vector3, vel: Vector3, size: float, color: Color) -> void:
	var i := _puff_n % PUFFS
	_puff_n += 1
	_puffs.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), at))
	_puffs.set_instance_color(i, color)
	_puffs.set_instance_custom_data(i, Color(vel.x, vel.y, vel.z, _clock()))


## A puff of grey smoke that hangs where it is put.
func smoke(at: Vector3, size: float, thick := 0.5) -> void:
	puff(at, Vector3(randf_range(-0.2, 0.2), randf_range(0.2, 0.7), randf_range(-0.2, 0.2)), size, Color(0.75, 0.74, 0.72, thick * 0.5))


## A mark on a surface at `at` whose outward normal is `normal`.
func mark(kind: int, at: Vector3, normal: Vector3, size: float, color: Color, seconds := 90.0) -> void:
	var i := _mark_n % MARKS
	_mark_n += 1
	var n := normal.normalized()
	# The square lies in the surface: its own up along the normal, turned at random about it.
	var side := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var b := Basis(side, n, side.cross(n)).rotated(n, randf() * TAU)
	# Lifted a hair off the surface, a different hair each, so they do not fight each other.
	_marks.set_instance_transform(i, Transform3D(b.scaled(Vector3(size, 1.0, size)), at + n * (0.012 + (i % 16) * 0.0012)))
	_marks.set_instance_color(i, color)
	_marks.set_instance_custom_data(i, Color(kind, randf() * 10.0, _clock(), seconds))


## The first solid thing along a to b: {position, normal}, or {} if there is nothing.
func _surface(a: Vector3, b: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))


## Blood from a wound at `at`, made by something travelling along `dir`: a spray out of the
## far side, a splash on the ground underneath, and a smear up whatever is behind.
func blood(at: Vector3, dir: Vector3, amount := 1.0) -> void:
	if not Settings.gore:
		return
	var under := _surface(at, at + Vector3(0, -3.0, 0))
	var floor_y: float = under.position.y if not under.is_empty() else at.y - 1.2
	for k in int(9 * amount):
		var v := dir * randf_range(1.5, 5.5) + Vector3(randf_range(-1.6, 1.6), randf_range(0.2, 2.8), randf_range(-1.6, 1.6))
		bit(at, v, randf_range(0.035, 0.085), BLOOD.lightened(randf() * 0.15), floor_y)
	if not under.is_empty():
		var out := Vector3(dir.x, 0, dir.z) * randf_range(0.2, 0.7)
		mark(MARK_BLOOD, Vector3(at.x + out.x, under.position.y, at.z + out.z), under.normal, randf_range(0.7, 1.3) * sqrt(amount), BLOOD)
	var behind := _surface(at, at + dir * 3.2)
	if not behind.is_empty() and behind.normal.y < 0.7:
		mark(MARK_BLOOD, behind.position, behind.normal, randf_range(0.8, 1.5) * sqrt(amount), BLOOD)


## What a hit does to whoever it hit: `type` is DB.WHO_*, `res` the DB.FX_* bits.
func wound(from: Vector3, to: Vector3, type: int, res: int, melee: bool) -> void:
	if type == DB.WHO_NONE:
		return
	var dir := (to - from).normalized() if from.distance_to(to) > 0.01 else Vector3.FORWARD
	var amount := 0.5 if melee else 1.0
	if res & DB.FX_HEAD:
		amount *= 1.8
	if res & DB.FX_KILL:
		amount *= 1.5
	if melee and res == 0 and randf() < 0.5:
		# Not every punch splits a lip.
		return
	blood(to, dir, amount)


## Somebody caught in the middle of a blast: there is not a body to speak of.
func gibs(at: Vector3) -> void:
	if not Settings.gore:
		return
	var under := _surface(at + Vector3(0, 1, 0), at + Vector3(0, -3.0, 0))
	var floor_y: float = under.position.y if not under.is_empty() else at.y
	for k in 26:
		var v := Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)).normalized() * randf_range(3.0, 9.0)
		var meat := k % 3 != 0
		bit(at + Vector3(0, randf_range(0.5, 1.4), 0), v, randf_range(0.09, 0.2) if meat else randf_range(0.05, 0.1), BLOOD.darkened(randf() * 0.3) if meat else Color(0.9, 0.86, 0.78), floor_y)
	for k in 5:
		var a := randf() * TAU
		var r := randf_range(0.3, 2.6)
		mark(MARK_BLOOD, Vector3(at.x + cos(a) * r, floor_y, at.z + sin(a) * r), Vector3.UP, randf_range(1.0, 2.2), BLOOD)


## A bullet meeting something that is not a person: dust, a spark or two, and a hole.
func impact(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	var hit := _surface(to - dir * 0.4, to + dir * 0.4)
	var n: Vector3 = hit.normal if not hit.is_empty() else -dir
	var at: Vector3 = hit.position if not hit.is_empty() else to
	puff(at + n * 0.1, n * 1.4 + Vector3(0, 0.4, 0), 0.22, Color(0.8, 0.76, 0.66, 0.4))
	for k in 4:
		bit(at + n * 0.05, (n + Vector3(randf_range(-0.7, 0.7), randf_range(-0.2, 0.9), randf_range(-0.7, 0.7))) * randf_range(2.0, 5.0), 0.035, Color(1.0, 0.85, 0.4) if k < 2 else Color(0.6, 0.57, 0.5), at.y - 1.5)
	if not hit.is_empty():
		mark(MARK_HOLE, at, n, 0.22, Color(0.05, 0.05, 0.05), 60.0)


## Everything going up at once at `at`.
func explosion(at: Vector3, radius: float) -> void:
	var under := _surface(at + Vector3(0, 0.5, 0), at + Vector3(0, -4.0, 0))
	var floor_y: float = under.position.y if not under.is_empty() else at.y
	# The flash, and the light it throws on everything round it.
	_burst(at + Vector3(0, 0.6, 0), radius * 0.9, Color(1.0, 0.9, 0.55))
	_burst(at + Vector3(0, 0.6, 0), radius * 0.5, Color(1.0, 1.0, 1.0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 14.0
	light.omni_range = radius * 5.0
	light.position = at + Vector3(0, 1.5, 0)
	add_child(light)
	var lt := create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5)
	lt.tween_callback(light.queue_free)
	# The fireball, rolling up and out and going black.
	for k in 22:
		var v := Vector3(randf_range(-1, 1), randf_range(0.1, 1.3), randf_range(-1, 1)).normalized() * randf_range(2.0, 7.0)
		puff(at + Vector3(0, 0.5, 0) + v * 0.08, v, randf_range(0.9, 1.9) * radius * 0.2, Color(1.0, randf_range(0.3, 0.62), 0.04, 1.0))
	# The smoke that is left hanging over it.
	for k in 14:
		var tw := create_tween()
		tw.tween_interval(0.12 + k * 0.07)
		tw.tween_callback(func() -> void:
			puff(at + Vector3(randf_range(-1.2, 1.2), 0.8 + k * 0.25, randf_range(-1.2, 1.2)), Vector3(randf_range(-0.6, 0.6), randf_range(1.5, 3.5), randf_range(-0.6, 0.6)), randf_range(1.2, 2.2), Color(0.16, 0.15, 0.15, 0.42)))
	# A ring of dust along the ground.
	for k in 18:
		var a := TAU * k / 18.0
		var out := Vector3(cos(a), 0, sin(a))
		puff(Vector3(at.x, floor_y + 0.25, at.z) + out * 0.6, out * radius * 1.4 + Vector3(0, 0.5, 0), 0.9, Color(0.82, 0.76, 0.62, 0.38))
	# Whatever was lying about, and sparks.
	for k in 40:
		var v := Vector3(randf_range(-1, 1), randf_range(0.3, 1.5), randf_range(-1, 1)).normalized() * randf_range(4.0, 15.0)
		var spark := k % 3 == 0
		bit(at + Vector3(0, 0.3, 0), v, randf_range(0.04, 0.07) if spark else randf_range(0.06, 0.17), Color(1.0, 0.75, 0.25) if spark else Color(0.3, 0.28, 0.26).lightened(randf() * 0.25), floor_y)
	if not under.is_empty():
		mark(MARK_SCORCH, under.position, under.normal, radius * 0.95, Color(0.04, 0.035, 0.03), 240.0)


## The blast out of the back of a launcher.
func backblast(at: Vector3, back: Vector3) -> void:
	_burst(at, 0.7, Color(1.0, 0.8, 0.3))
	for k in 7:
		puff(at + back * (0.6 + k * 0.25), back * randf_range(2.0, 6.0) + Vector3(0, 0.6, 0), randf_range(0.4, 0.8), Color(0.82, 0.8, 0.78, 0.4))


## Burning petrol over `radius` round `at` for `seconds`.
func fire(at: Vector3, radius: float, seconds: float) -> void:
	_fires.append([at, radius, _clock() + seconds, 0.0])
	_burst(at + Vector3(0, 0.3, 0), radius * 0.8, Color(1.0, 0.6, 0.15))
	for k in 14:
		var v := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized() * randf_range(2.0, 6.0)
		bit(at + Vector3(0, 0.2, 0), v, 0.05, Color(0.4, 0.6, 0.35), at.y)
	var under := _surface(at + Vector3(0, 0.5, 0), at + Vector3(0, -3.0, 0))
	if not under.is_empty():
		mark(MARK_SCORCH, under.position, under.normal, radius * 2.0, Color(0.05, 0.04, 0.03), 240.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 3.5
	light.omni_range = radius * 3.5
	light.position = at + Vector3(0, 1.0, 0)
	add_child(light)
	var lt := create_tween()
	lt.tween_interval(maxf(seconds - 1.2, 0.1))
	lt.tween_property(light, "light_energy", 0.0, 1.2)
	lt.tween_callback(light.queue_free)


## A punch or shot from `from` landing at `to`. `hit` is whether it struck a character,
## `item` what it was fired from, `lead` false for the pellets after the first (no second flash).
func strike(from: Vector3, to: Vector3, melee: bool, hit: bool, item := "", lead := true) -> void:
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
	# How fat the line is, how long it lingers and how big the flash, by what fired it.
	var thick := 1.0
	var linger := 0.16
	var flash := 0.3
	var tint := Color(1.0, 0.95, 0.5)
	match item:
		"sniper":
			thick = 1.7
			linger = 0.55
			flash = 0.6
			tint = Color(1.0, 1.0, 0.85)
		"shotgun":
			thick = 0.55
			linger = 0.1
			flash = 0.65
		"fuzil":
			thick = 1.15
			flash = 0.45
		"smg":
			thick = 0.8
			flash = 0.24
		"revolver":
			flash = 0.42
	var mi := _node(_beam, tint)
	var up := Vector3.RIGHT if absf(fwd.y) > 0.99 else Vector3.UP
	mi.transform = Transform3D(Basis.looking_at(fwd, up), (from + to) * 0.5)
	mi.scale = Vector3(thick, thick, length)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(0.02, 0.02, length), linger)
	tw.tween_callback(mi.queue_free)

	if lead:
		_burst(from + fwd * 0.2, flash, Color(1.0, 0.8, 0.25))
		puff(from + fwd * 0.3, fwd * 1.5 + Vector3(0, 0.5, 0), flash * 0.6, Color(0.85, 0.84, 0.82, 0.3))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.8, 0.4)
		light.light_energy = 3.0 + flash * 4.0
		light.omni_range = 7.0 + flash * 6.0
		light.position = from
		add_child(light)
		var lt := create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.1)
		lt.tween_callback(light.queue_free)

	if hit:
		_burst(to, 0.42, Color(1.0, 0.15, 0.1))
		_burst(to, 0.2, Color(1.0, 1.0, 1.0))
	else:
		_burst(to, 0.14, Color(0.95, 0.9, 0.75))
		impact(from, to)


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


## Something wet leaving a body in a hurry: an arc of blobs from `at` along `dir`.
func spew(at: Vector3, dir: Vector3, color: Color, blobs := 10) -> void:
	var bit := SphereMesh.new()
	bit.radius = 0.07
	bit.height = 0.14
	bit.radial_segments = 6
	bit.rings = 3
	for k in blobs:
		var mi := _node(bit, color.lightened(randf() * 0.2))
		mi.position = at
		var out := dir * randf_range(0.6, 1.6) + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.4), randf_range(-0.3, 0.3))
		var land := at + out * 1.2
		land.y = maxf(at.y - 1.1, 0.05)
		var tw := create_tween()
		tw.tween_interval(k * 0.03)
		tw.tween_property(mi, "position", at + out * 0.6 + Vector3(0, 0.15, 0), 0.15)
		tw.tween_property(mi, "position", land, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "scale", Vector3(2.0, 0.2, 2.0), 0.1)
		tw.tween_interval(1.5)
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
