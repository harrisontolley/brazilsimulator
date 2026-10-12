extends RefCounted
## Shared cartoon character used by the crowd, the police and the players.
##
## One low-poly mesh holds the body and every prop anyone can wear. It is drawn through
## MultiMesh; the vertex shader (shaders/character_pose.gdshaderinc) poses the limbs and
## hides unworn props from per-instance data, so nothing is animated from script.
##
## Instance colour: rgb = top colour, a = look seed (skin, hair, legs).
## Instance custom data: see custom().

const WeaponKit := preload("res://scenes/weapons/weapon_kit.gd")

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
const DANCE := 13
const CHEER := 14
const SIT := 15
const RIDE := 16
const DRUM := 17
const KO := 18
const TACKLED := 19
const HANDS_UP := 20
const CALL := 21
const DRINK := 22
const EAT := 23
const TALK := 24
const PHONE := 25
const DIG := 26
const KEEPUP := 27
const LEAN := 28
const SQUAT := 29
const SIT_DRINK := 30
const SIT_TALK := 31
const SIT_PHONE := 32
const SELFIE := 33
const CROUCH := 34
const GINGA := 35
const CLAP := 36
const LIFT := 37
const WORK := 38

# What is in the right hand (shader `held`). Two and up are guns.
const HELD_NONE := 0
const HELD_KNIFE := 1
const HELD_PISTOL := 2
const HELD_REVOLVER := 3
const HELD_SMG := 4

# Props that follow the hand or the pose rather than a flag bit (shader PROP_*).
const _PROP_HELD := 32
const _PROP_CUP := 41
const _PROP_PHONE := 42
const _PROP_SPADE := 43

# How a body is arranged, for working out where its head is (see zones()).
const STANCE_STAND := 0
const STANCE_CROUCH := 1
const STANCE_SEAT := 2
const STANCE_TOWEL := 3  # on the back, centred on its spot
const STANCE_BACK := 4   # on the back where it fell
const STANCE_FACE := 5   # on the face where it fell
const HEAD_R := 0.23
const BODY_R := 0.3

# Flag bits. The first twelve switch props on; the rest restyle the body. Bit 7 is free.
const F_HAT := 1 << 0
const F_SHADES := 1 << 1
const F_CAMERA := 1 << 2
const F_BUMBAG := 1 << 3
const F_WATCH := 1 << 4
const F_CHAIN := 1 << 5
const F_SHOPBAG := 1 << 6
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
const F_CARRY := 1 << 22  # prop: a vendor's cooler slung in front (a drum, in the DRUM pose)
const F_SHIRTLESS := 1 << 23

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
const _VCOL := 18  # colour carried by the vertex itself (held weapons)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _line: ShaderMaterial
static var _mats: Array[ShaderMaterial] = []  # everything that needs the clock
static var _cheer_until := 0.0
## What the local player is seeing that is not there (shader `trip`): 1 big heads, 2 all cops.
static var trip := 0.0

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
		var k := clampf((_cheer_until - t) / 0.6, 0.0, 1.0)
		for m in _mats:
			m.set_shader_parameter("now", t)
			m.set_shader_parameter("cheer", k)
			m.set_shader_parameter("trip", trip)


## Makes everyone standing about celebrate for `seconds`.
static func cheer(seconds: float) -> void:
	_cheer_until = now() + seconds


## Adds `count` characters under `parent` and returns the MultiMesh that places them.
## `mats` is [body, outline] from rig_materials() for a character posed from script.
static func add_to(parent: Node3D, count: int, aabb: AABB, mats: Array = []) -> MultiMesh:
	if _mesh == null:
		_build()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = count
	if mats.is_empty():
		mats = [_mat, _line]
	for k in 2:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[k]
		mmi.custom_aabb = aabb
		if k == 1:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	return mm


## What `count` characters hold in their hands, as a second layer over the bodies made by
## add_to(). Give each instance exactly the transform, colour and custom data of its owner and
## the shader puts the weapon in the hand; only the one matching the owner's `held` shows.
static func add_held(parent: Node3D, count: int, aabb: AABB, mats: Array = []) -> MultiMesh:
	if _mesh == null:
		_build()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = WeaponKit.held_mesh()
	mm.instance_count = count
	for i in count:
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -50, 0)))
	if mats.is_empty():
		mats = [_mat, _line]
	for k in 2:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[k]
		mmi.custom_aabb = aabb
		if k == 1:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	return mm


## A private [body, outline] pair whose pose comes from script (see char_rig.gd).
static func rig_materials() -> Array:
	if _mesh == null:
		_build()
	var out: Array = []
	for src in [_mat, _line]:
		var m: ShaderMaterial = src.duplicate()
		m.set_shader_parameter("rigged", true)
		_mats.append(m)
		out.append(m)
	return out


static func drop_materials(mats: Array) -> void:
	for m in mats:
		_mats.erase(m)


## Packs the per-instance data. `event` is the now() of the last one-shot: positive for an
## attack, negative for a hit. `prev` and `t0` are the pose being left and when: the shader
## blends from one to the other. Leave them out for a character that has always stood so.
static func custom(pose: int, speed: float, flags: int, event: float, prev := -1, t0 := 0.0, held := 0) -> Color:
	var word := pose | ((pose if prev < 0 else prev) << 6) | (clampi(roundi(speed * 10.0), 0, 255) << 12) | (held << 20)
	return Color(word, t0, flags, event)


## Where to hit a character: [head centre, body from, body to], in its own unscaled space
## (feet at the origin, facing -Z). The numbers follow the mesh and the poses in the shader.
static func zones(stance: int) -> Array:
	match stance:
		STANCE_CROUCH:
			return [Vector3(0, 1.15, -0.3), Vector3(0, 0.25, 0.05), Vector3(0, 0.85, -0.15)]
		STANCE_SEAT:
			return [Vector3(0, 1.22, 0), Vector3(0, 0.45, -0.1), Vector3(0, 0.95, 0)]
		STANCE_TOWEL:
			return [Vector3(0, 0.2, 0.68), Vector3(0, 0.2, -0.6), Vector3(0, 0.2, 0.35)]
		STANCE_BACK:
			return [Vector3(0, 0.2, 1.58), Vector3(0, 0.2, 0.3), Vector3(0, 0.2, 1.25)]
		STANCE_FACE:
			return [Vector3(0, 0.2, -1.58), Vector3(0, 0.2, -0.3), Vector3(0, 0.2, -1.25)]
	return [Vector3(0, 1.6, 0), Vector3(0, 0.3, 0), Vector3(0, 1.25, 0)]


## Tests ray (o, d) against a character at `at`. Returns [distance, DB.ZONE_*], distance -1 on
## a miss. `grow` fattens the zones: a swung fist is not a bullet.
static func ray_hit(o: Vector3, d: Vector3, max_t: float, at: Vector3, yaw: float, scale: float, stance: int, grow := 0.0) -> Array:
	var z := zones(stance)
	var b := Basis(Vector3.UP, yaw) * scale
	var t := DB.ray_point(o, d, at + b * z[0], HEAD_R * scale + grow * 0.5, max_t)
	if t >= 0.0:
		return [t, DB.ZONE_HEAD]
	return [DB.ray_segment(o, d, at + b * z[1], at + b * z[2], BODY_R * scale + grow, max_t), DB.ZONE_BODY]


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
	_mats = [_mat, _line]

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

	# Vendor's cooler on a strap round the neck.
	_box(Vector3(0, 0.98, -0.3), Vector3(0.44, 0.3, 0.3), _TORSO, _WHITE, 23)
	_box(Vector3(0, 1.14, -0.3), Vector3(0.46, 0.05, 0.32), _TORSO, _ACCENT, 23)
	_box(Vector3(0, 1.22, -0.12), Vector3(0.36, 0.03, 0.3), _TORSO, _BLACK, 23)

	# Things that come with a pose: a cup, a phone, a beach spade.
	_box(Vector3(0.245, 0.7, -0.07), Vector3(0.065, 0.11, 0.065), _FORE_R, _WHITE, _PROP_CUP)
	_box(Vector3(0.245, 0.71, -0.06), Vector3(0.075, 0.14, 0.018), _FORE_R, _BLACK, _PROP_PHONE)
	_box(Vector3(0.245, 0.42, -0.06), Vector3(0.03, 0.72, 0.03), _FORE_R, _SACK, _PROP_SPADE)
	_box(Vector3(0.245, 0.0, -0.06), Vector3(0.17, 0.22, 0.03), _FORE_R, _WHITE, _PROP_SPADE)

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
