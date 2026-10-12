extends RefCounted
## Shared cartoon character used by the crowd, the police and the players.
##
## One low-poly mesh holds the body and every prop anyone can wear. It is drawn through
## MultiMesh; the vertex shader (shaders/character_pose.gdshaderinc) poses the limbs and
## hides unworn props from per-instance data, so nothing is animated from script.
##
## Instance colour: rgb = top colour, a = look seed (skin, hair, legs).
## Instance custom data: see custom().

# Poses (shader P_*).
const STAND := 0
const WALK := 1
const RUN := 2
const SUNBATHE := 3
const COWER := 4
const FLEE := 5
const FIGHT := 6
const AIM := 7
const DEAD := 8
const DOWN := 9
const JUMP := 10
const SLIDE := 11
const DIVE := 12

# Flag bits. The first twelve switch props on; the rest restyle the body.
const F_HAT := 1 << 0
const F_SHADES := 1 << 1
const F_CAMERA := 1 << 2
const F_BUMBAG := 1 << 3
const F_WATCH := 1 << 4
const F_CHAIN := 1 << 5
const F_SHOPBAG := 1 << 6
const F_GUN := 1 << 7
const F_POLICE := 1 << 8
const F_WAD := 1 << 9
const F_SACK_S := 1 << 10
const F_SACK_L := 1 << 11
const F_SHORTS := 1 << 12
const F_TANK := 1 << 13
const F_SUIT := 1 << 14
const F_LAMP_ON := 1 << 15
const F_ANGRY := 1 << 16
const F_JAIL := 1 << 17
const HEAT_SHIFT := 18  # two bits: wanted level 0..3
const F_SUNBURN := 1 << 20
const F_GOLDWATCH := 1 << 21

## Props shown per wealth tier (DB.wealth_tier).
const TIER_PROPS := [0, F_BUMBAG | F_WATCH, F_CHAIN | F_WATCH | F_GOLDWATCH]

# Parts (shader PART_*).
const _TORSO := 0
const _HEAD := 1
const _ARM_L := 2
const _FORE_L := 3
const _ARM_R := 4
const _FORE_R := 5
const _THIGH_L := 6
const _SHIN_L := 7
const _THIGH_R := 8
const _SHIN_R := 9
const _BROW_L := 10
const _BROW_R := 11

# Palette slots (shader S_*).
const _SKIN := 0
const _TOP := 1
const _BOTTOM := 2
const _HAIR := 3
const _SHOE := 4
const _GOLD := 5
const _BLACK := 6
const _WHITE := 7
const _SHIN := 8
const _EYE := 9
const _LAMP := 10
const _ACCENT := 11
const _SLEEVE := 12
const _FOREARM := 13
const _CASH := 14
const _STRIPE := 15
const _SACK := 16
const _WATCH := 17

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _line: ShaderMaterial

static var _v := PackedVector3Array()
static var _n := PackedVector3Array()
static var _uv := PackedVector2Array()
static var _uv2 := PackedVector2Array()
static var _idx := PackedInt32Array()


## Animation clock shared by every character. One-shot events are stamped with it.
static func now() -> float:
	return Time.get_ticks_msec() * 0.001


## Call once per frame to advance the shader clock.
static func tick() -> void:
	if _mat != null:
		var t := now()
		_mat.set_shader_parameter("now", t)
		_line.set_shader_parameter("now", t)


## Adds `count` characters under `parent` and returns the MultiMesh that places them.
static func add_to(parent: Node3D, count: int, aabb: AABB) -> MultiMesh:
	if _mesh == null:
		_build()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = count
	for mat in [_mat, _line]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.custom_aabb = aabb
		if mat == _line:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	return mm


## `event` is the now() of the last one-shot: positive for an attack, negative for a hit.
## For DEAD and DOWN it is when the fall started.
static func custom(pose: int, speed: float, flags: int, event: float) -> Color:
	return Color(pose, speed, flags, event)


## Yaw that turns a character (which faces -Z) toward `dir`.
static func face(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func xform(p: Vector3, yaw: float, width: float, height: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(width, height, width)), p)


# --- mesh ---

static func _build() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/character.gdshader")
	_line = ShaderMaterial.new()
	_line.shader = load("res://shaders/character_outline.gdshader")

	# Body. Feet at the origin, facing -Z, about 1.8 tall.
	_ell(Vector3(0, 0.82, 0), Vector3(0.17, 0.11, 0.12), _TORSO, _BOTTOM)
	_ell(Vector3(0, 1.08, 0), Vector3(0.2, 0.33, 0.135), _TORSO, _TOP, 0, 10, 6)
	_ell(Vector3(0, 1.58, 0), Vector3(0.2, 0.21, 0.2), _HEAD, _SKIN, 0, 10, 6)
	_ell(Vector3(0, 1.62, 0.025), Vector3(0.21, 0.19, 0.205), _HEAD, _HAIR, 0, 10, 6, 1.6)
	_ell(Vector3(0, 1.555, -0.205), Vector3(0.025, 0.025, 0.03), _HEAD, _SKIN, 0, 6, 3)
	_box(Vector3(0, 1.5, -0.19), Vector3(0.07, 0.015, 0.02), _HEAD, _BLACK)
	for side in [-1.0, 1.0]:
		var left: bool = side < 0.0
		var arm := _ARM_L if left else _ARM_R
		var fore := _FORE_L if left else _FORE_R
		var thigh := _THIGH_L if left else _THIGH_R
		var shin := _SHIN_L if left else _SHIN_R
		var ax: float = side * 0.245
		var lx: float = side * 0.095
		_ell(Vector3(side * 0.075, 1.6, -0.185), Vector3(0.032, 0.042, 0.02), _HEAD, _EYE, 0, 6, 3)
		_box(Vector3(side * 0.075, 1.67, -0.19), Vector3(0.075, 0.018, 0.02), _BROW_L if left else _BROW_R, _BLACK)
		_ell(Vector3(side * 0.215, 1.3, 0), Vector3(0.075, 0.075, 0.075), arm, _SLEEVE, 0, 6, 3)
		_tube(Vector3(ax, 1.3, 0), Vector3(ax, 1.04, 0), 0.058, 0.052, arm, _SLEEVE)
		_tube(Vector3(ax, 1.02, 0), Vector3(ax, 0.8, 0), 0.052, 0.046, fore, _FOREARM)
		_ell(Vector3(ax, 0.75, 0), Vector3(0.058, 0.068, 0.058), fore, _SKIN, 0, 6, 4)
		_tube(Vector3(lx, 0.8, 0), Vector3(lx, 0.47, 0), 0.08, 0.068, thigh, _BOTTOM)
		_tube(Vector3(lx, 0.45, 0), Vector3(lx, 0.11, 0), 0.062, 0.055, shin, _SHIN)
		_box(Vector3(lx, 0.045, -0.045), Vector3(0.13, 0.09, 0.26), shin, _SHOE)
		# Sunglasses lens.
		_ell(Vector3(side * 0.075, 1.605, -0.19), Vector3(0.06, 0.045, 0.03), _HEAD, _BLACK, 2, 6, 3)

	# Props. The number after the slot is the flag bit + 1 that shows it.
	_ell(Vector3(0, 1.74, 0), Vector3(0.33, 0.025, 0.33), _HEAD, _ACCENT, 1, 10, 2)
	_ell(Vector3(0, 1.78, 0), Vector3(0.19, 0.1, 0.19), _HEAD, _ACCENT, 1, 10, 4, 1.74)
	_box(Vector3(0, 1.61, -0.205), Vector3(0.08, 0.015, 0.02), _HEAD, _BLACK, 2)
	_box(Vector3(0, 1.12, -0.165), Vector3(0.13, 0.09, 0.07), _TORSO, _BLACK, 3)
	_ell(Vector3(0, 1.12, -0.21), Vector3(0.035, 0.035, 0.03), _TORSO, _WHITE, 3, 6, 3)
	_ell(Vector3(0.05, 0.88, -0.14), Vector3(0.12, 0.07, 0.07), _TORSO, _ACCENT, 4)
	_ell(Vector3(-0.245, 0.815, 0), Vector3(0.068, 0.035, 0.068), _FORE_L, _WATCH, 5, 6, 2)
	_chain()
	_ell(Vector3(0, 1.265, -0.15), Vector3(0.04, 0.045, 0.03), _TORSO, _GOLD, 6, 6, 3)
	_box(Vector3(-0.245, 0.56, 0), Vector3(0.07, 0.26, 0.24), _FORE_L, _ACCENT, 7)
	# The pistol points down the hanging arm so it points forward once the arm is raised.
	_box(Vector3(0.245, 0.64, -0.03), Vector3(0.045, 0.22, 0.065), _FORE_R, _BLACK, 8)
	# Police: white cap with a black band and brim, gold badges, beacon, hi-vis band, belt.
	_ell(Vector3(0, 1.76, 0), Vector3(0.215, 0.085, 0.215), _HEAD, _WHITE, 9, 10, 4, 1.73)
	_ell(Vector3(0, 1.725, 0), Vector3(0.208, 0.035, 0.208), _HEAD, _BLACK, 9, 10, 2)
	_box(Vector3(0, 1.715, -0.2), Vector3(0.26, 0.02, 0.16), _HEAD, _BLACK, 9)
	_ell(Vector3(0, 1.775, -0.2), Vector3(0.04, 0.045, 0.02), _HEAD, _GOLD, 9, 6, 3)
	_ell(Vector3(0, 1.87, 0), Vector3(0.065, 0.065, 0.065), _HEAD, _LAMP, 9, 6, 3)
	_ell(Vector3(0, 1.1, 0), Vector3(0.208, 0.06, 0.145), _TORSO, _STRIPE, 9, 10, 2)
	_ell(Vector3(-0.09, 1.25, -0.115), Vector3(0.035, 0.04, 0.02), _TORSO, _GOLD, 9, 6, 3)
	_ell(Vector3(0, 0.9, 0), Vector3(0.185, 0.035, 0.135), _TORSO, _BLACK, 9, 10, 2)
	# Loot a player is carrying: pocket wad, back sack, big sack.
	_box(Vector3(0.17, 0.86, -0.04), Vector3(0.05, 0.1, 0.09), _TORSO, _CASH, 10)
	_ell(Vector3(0, 1.1, 0.19), Vector3(0.14, 0.17, 0.11), _TORSO, _SACK, 11)
	_box(Vector3(0, 1.28, 0.19), Vector3(0.14, 0.06, 0.08), _TORSO, _CASH, 11)
	_ell(Vector3(0, 1.12, 0.24), Vector3(0.24, 0.28, 0.19), _TORSO, _SACK, 12)
	_box(Vector3(0, 1.41, 0.24), Vector3(0.26, 0.09, 0.14), _TORSO, _CASH, 12)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	arrays[Mesh.ARRAY_INDEX] = _idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_v.clear()
	_n.clear()
	_uv.clear()
	_uv2.clear()
	_idx.clear()


static func _vert(p: Vector3, n: Vector3, part: int, slot: int, prop: int) -> int:
	_v.append(p)
	_n.append(n)
	_uv.append(Vector2(prop, 0))
	_uv2.append(Vector2(part, slot))
	return _v.size() - 1


## Adds a triangle wound to face away from `inside` (Godot front faces are clockwise).
static func _tri(a: int, b: int, c: int, inside: Vector3) -> void:
	var out := (_v[a] + _v[b] + _v[c]) / 3.0 - inside
	if (_v[b] - _v[a]).cross(_v[c] - _v[a]).dot(out) > 0.0:
		var t := b
		b = c
		c = t
	_idx.append(a)
	_idx.append(b)
	_idx.append(c)


## Ellipsoid. `floor_y` flattens everything below it, turning it into a cap.
static func _ell(c: Vector3, r: Vector3, part: int, slot: int, prop := 0, seg := 8, rings := 4, floor_y := -INF) -> void:
	var base := _v.size()
	for j in rings + 1:
		var lat := PI * j / rings
		for k in (1 if j == 0 or j == rings else seg):
			var lon := TAU * k / seg
			var d := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
			var p := c + d * r
			p.y = maxf(p.y, floor_y)
			_vert(p, (d / r).normalized(), part, slot, prop)
	var last := _v.size() - 1
	for k in seg:
		var k1 := (k + 1) % seg
		_tri(base, base + 1 + k, base + 1 + k1, c)
		_tri(last, last - seg + k, last - seg + k1, c)
		for j in rings - 2:
			var a := base + 1 + j * seg
			_tri(a + k, a + k1, a + seg + k, c)
			_tri(a + k1, a + seg + k1, a + seg + k, c)


## Tapered limb segment with rounded ends.
static func _tube(a: Vector3, b: Vector3, ra: float, rb: float, part: int, slot: int, prop := 0, seg := 6) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(dir)
	var base := _vert(a - dir * ra * 0.7, -dir, part, slot, prop)
	for end in 2:
		for k in seg:
			var d := side * cos(TAU * k / seg) + up * sin(TAU * k / seg)
			_vert((a if end == 0 else b) + d * (ra if end == 0 else rb), d, part, slot, prop)
	var tip := _vert(b + dir * rb * 0.7, dir, part, slot, prop)
	var mid := (a + b) * 0.5
	for k in seg:
		var k1 := (k + 1) % seg
		var r0 := base + 1
		var r1 := base + 1 + seg
		_tri(base, r0 + k, r0 + k1, mid)
		_tri(r0 + k, r0 + k1, r1 + k, mid)
		_tri(r0 + k1, r1 + k1, r1 + k, mid)
		_tri(tip, r1 + k, r1 + k1, mid)


## Box with corner-averaged normals, so the outline hull stays closed.
static func _box(c: Vector3, size: Vector3, part: int, slot: int, prop := 0) -> void:
	var base := _v.size()
	for k in 8:
		var d := Vector3(-1.0 if k & 1 == 0 else 1.0, -1.0 if k & 2 == 0 else 1.0, -1.0 if k & 4 == 0 else 1.0)
		_vert(c + d * size * 0.5, d.normalized(), part, slot, prop)
	for q in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		_tri(base + q[0], base + q[1], base + q[2], c)
		_tri(base + q[0], base + q[2], base + q[3], c)


## Fat gold chain: a ring hanging from the neck down onto the chest.
static func _chain() -> void:
	var centre := Vector3(0, 1.38, -0.02)
	var hang := Vector3(0, -0.09, -0.13)
	var across := Vector3.RIGHT.cross(hang.normalized())
	var seg := 10
	var base := _v.size()
	var mids: Array = []
	for j in seg:
		var u := TAU * j / seg
		var radial := (Vector3.RIGHT * cos(u) + hang.normalized() * sin(u)).normalized()
		var mid := centre + Vector3.RIGHT * 0.14 * cos(u) + hang * sin(u)
		mids.append(mid)
		for k in 4:
			var d := radial * cos(TAU * k / 4) + across * sin(TAU * k / 4)
			_vert(mid + d * 0.024, d, _TORSO, _GOLD, 6)
	for j in seg:
		var j1 := (j + 1) % seg
		var inside: Vector3 = (mids[j] + mids[j1]) * 0.5
		for k in 4:
			var k1 := (k + 1) % 4
			_tri(base + j * 4 + k, base + j * 4 + k1, base + j1 * 4 + k, inside)
			_tri(base + j * 4 + k1, base + j1 * 4 + k1, base + j1 * 4 + k, inside)
