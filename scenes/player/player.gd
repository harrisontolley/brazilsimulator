extends CharacterBody3D
## One per connected peer on every machine. The owning client drives movement;
## `st` is server-owned state replicated through Game.cl_state.

const CameraRig := preload("res://scenes/player/camera_rig.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const WeaponKit := preload("res://scenes/weapons/weapon_kit.gd")
const CharRig := preload("res://scenes/characters/char_rig.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")

enum { MV_GROUND, MV_AIR, MV_SLIDE, MV_WALLRUN, MV_DIVE, MV_RIDE, MV_CROUCH }

const WALK := 4.5
const SPRINT := 7.0
const JUMP := 5.6
const GRAVITY := 16.0
# Quake-style movement: friction only bites on the ground, and air acceleration is strong
# but only toward a tiny wish speed, so turning with a strafe key held builds speed.
const GROUND_ACCEL := 10.0
const FRICTION := 6.0
const STOP_SPEED := 2.0
const AIR_ACCEL := 60.0
const AIR_WISH_CAP := 0.9
## Below this speed the air also gives plain steering, so a standing jump is controllable.
const AIR_STEER_SPEED := 4.0
const AIR_STEER := 18.0
const AIR_JUMPS := 1
const DOUBLE_JUMP := 5.2
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
const SLIDE_MIN := 5.0
const SLIDE_END := 3.0
const SLIDE_FRICTION := 0.7
const SLIDE_BOOST := 2.5
const SLIDE_CD := 0.8
const SLIDE_HOP := 1.0
## A slide has to last this long before hopping out of it pays a boost.
const SLIDE_HOP_MIN := 0.15
## Slide and slide-hop boosts stop adding speed here; past it only air strafing does.
const BOOST_CAP := 11.5
const STAND_H := 1.5
const CROUCH_H := 0.8
const CROUCH_HEAD := 0.62
## Creeping about bent double: slow, low and hard to spot.
const CROUCH_SPEED := 1.8
const DUCK_HEAD := 0.85
const WALL_MIN_SPEED := 4.5
const WALL_GRAVITY := 2.5
const WALL_TIME := 1.6
const WALL_JUMP_OUT := 6.0
const WALL_JUMP_UP := 5.4
const DIVE_SPEED := 9.5
const DIVE_UP := 3.6
const DIVE_CD := 1.0
const DIVE_RECOVER := 0.3
const RIDE_ROAD := 22.0
const RIDE_SAND := 12.0
const RIDE_ACCEL := 13.0
const RIDE_BRAKE := 24.0
const RIDE_STEER := 2.0
const SENS := 0.0025
const ROB_RANGE := 4.0
const HEAD := Vector3(0, 1.3, 0)
## Kit characters are adult-sized; the players are kids.
const BODY_SCALE := 0.78
const VM_RIGHT := Vector3(0.3, -0.3, -0.75)
const VM_LEFT := Vector3(-0.3, -0.32, -0.7)

var id := 0
var pname := "Kid"
var is_local := false
var st: Dictionary = fresh_state()
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var wanted_t := 0.0  # server only
var rig: Node3D
var target_npc := -1
var robbing := false
## What the legs are doing (MV_*). Simulated by the owner; others get it as net_mv.
var mv := MV_GROUND
## Replicated mv in the low three bits; bit 3 set while wall running with the wall on the right,
## bit 4 while aiming, bits 5-6 count jumps and bit 7 says the last one was in mid-air.
var net_mv := 0
## Camera pitch as others should see it: where the head and gun point.
var net_pitch := 0.0

var _cap: CapsuleShape3D
var _shape: CollisionShape3D
var _crouched := false
var _air_jumps := 0
var _coyote_t := 0.0
var _buffer_t := 0.0
var _jumped := false
var _jump_was := false
var _slide_t := 0.0
var _slide_cd := 0.0
var _dive_cd := 0.0
var _recover_t := 0.0
var _ramp_vy := 0.0
var _wall_n := Vector3.ZERO
var _wall_t := 0.0
var _wall_side := 1.0
# The wall last run or kicked off, which cannot be used again until landing.
var _wall_last := Vector3.ZERO
var _wall_last_d := 0.0

var _ride_spd := 0.0
var _ride_steer := 0.0
var _ram_cd := 0.0

var _vis: Node3D
var _body: MultiMesh
var _held: MultiMesh
var _label: Label3D
var _last_pos := Vector3.ZERO
var _spd := 0.0
var _vy := 0.0
var _ev := 0.0  # Kit one-shot event time
var _pose := 0
var _prev := 0
var _pose_t := 0.0
var _pit := -1       # the hole this player has fallen into
var _pit_jumps := 0
var _pit_cd := 0.0
var _sink := 0.0
var _reload_t := -10.0
var _reload_len := 1.0
var _anim: CharRig
var _mats: Array = []
var _hops := 0
var _hop_air := false
var _hops_seen := 0
var _yaw_was := 0.0
var _turn := 0.0
var _bank := 0.0
# First-person hands.
var _vm: Node3D
var _vm_r: Node3D
var _vm_l: Node3D
var _vm_guns := {}  # Kit.HELD_* -> the model shown in the right hand
var _vm_t := -10.0
var _vm_side := 1.0
var _send_t := 0.0
var _near_t := 0.0
var _rob_t := 0.0
var _attack_t := 0.0
var _voice: AudioStreamPlayer3D
var _voice_rate := 0


static func fresh_state() -> Dictionary:
	return {
		"hp": 100.0, "money": 0, "kills": 0,
		"inv": {"fists": 1}, "equipped": "fists", "ammo": 0,
		"heat": 0, "vis": 0, "hide": -1, "jail": 0.0, "dead": false, "ko": 0.0, "mag": {},
		"drugs": {}, "tol": {}, "bet": {},
	}


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 if is_local else 0
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.32
	_cap.height = STAND_H
	_shape = CollisionShape3D.new()
	_shape.shape = _cap
	_shape.position.y = STAND_H * 0.5
	add_child(_shape)

	_vis = Node3D.new()
	add_child(_vis)
	_anim = CharRig.new()
	_mats = Kit.rig_materials()
	_body = Kit.add_to(_vis, 1, AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5, 3.5, 5)), _mats)
	_held = Kit.add_held(_vis, 1, AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5, 3.5, 5)), _mats)
	for mm in [_body, _held]:
		mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * BODY_SCALE), Vector3.ZERO))
		mm.set_instance_color(0, Color.from_hsv(fmod(id * 0.137, 1.0), 0.75, 0.9, fmod(id * 0.618, 1.0)))
	_last_pos = position

	if is_local:
		rig = CameraRig.new()
		rig.position = HEAD
		add_child(rig)
		_build_viewmodel()
	else:
		_label = Label3D.new()
		_label.text = pname
		_label.font_size = 64
		_label.outline_size = 16
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position.y = 1.75
		_vis.add_child(_label)


func _exit_tree() -> void:
	Kit.drop_materials(_mats)


## Fists and pistol seen in first person, where the body itself is hidden.
func _build_viewmodel() -> void:
	_vm = Node3D.new()
	rig.cam.add_child(_vm)
	var fist := SphereMesh.new()
	fist.radius = 0.06
	fist.height = 0.12
	var arm := CapsuleMesh.new()
	arm.radius = 0.042
	arm.height = 0.5
	var skin := Color(0.85, 0.62, 0.44)
	_vm_r = Node3D.new()
	_vm_l = Node3D.new()
	for hand in [_vm_r, _vm_l]:
		_vm.add_child(hand)
		hand.add_child(_mesh(fist, Vector3.ZERO, skin))
		var fore := _mesh(arm, Vector3(0.0, -0.07, 0.27), skin)
		fore.rotation.x = 1.84
		hand.add_child(fore)
	for held in WeaponKit.MODELS:
		var gun := WeaponKit.node(held)
		# Big and close, the way a gun fills the corner of the eye.
		gun.position = Vector3(0.0, 0.04, -0.06)
		gun.scale = Vector3.ONE * 1.3
		gun.visible = false
		_vm_r.add_child(gun)
		_vm_guns[held] = gun


func _mesh(mesh: Mesh, p: Vector3, c: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = p
	return mi


# --- derived stats (read on both client and server) ---

func drug_phase(drug: String) -> String:
	return st.drugs.get(drug, {}).get("phase", "")


func speed_mult() -> float:
	var m := 1.0
	match drug_phase("cocaine"):
		"high": m *= 1.6
		"down": m *= 0.45
		"od": m *= 0.8
	match drug_phase("weed"):
		"high": m *= 0.75
		"od": m *= 0.35
	return m


func melee_mult() -> float:
	match drug_phase("cocaine"):
		"high": return 2.0
		"down": return 0.6
	return 1.0


func damage_taken_mult() -> float:
	return (0.5 if drug_phase("weed") == "high" else 1.0) * (0.85 if is_drunk() else 1.0)


func is_drunk() -> bool:
	return drug_phase("caipirinha") == "high"


## Dutch courage: a drink makes the shouting land harder.
func intimidation_mult() -> float:
	return 1.4 if is_drunk() else 1.0


func is_sniper() -> bool:
	return drug_phase("meth") == "high"


func mic_mult() -> float:
	return 0.5 if drug_phase("weed") == "od" else 1.0


func can_act() -> bool:
	return not st.dead and not MatchState.ended and st.ko <= 0.0


func can_fight() -> bool:
	return can_act() and st.jail <= 0.0 and st.get("hide", -1) < 0


## Out in the world where the police, the bikes and the shops are: alive and not inside.
func at_large() -> bool:
	return can_act() and st.jail <= 0.0


## How fast this body is covering ground, as anyone watching would judge it.
func ground_speed() -> float:
	return _spd


## Where this player's eyes are, as the host reckons it.
func eye() -> Vector3:
	var m: int = mv if is_local else net_mv & 7
	var h := HEAD.y
	if m == MV_CROUCH:
		h = DUCK_HEAD
	elif m == MV_SLIDE or m == MV_DIVE:
		h = CROUCH_HEAD
	return global_position + Vector3(0, h, 0)


## Kit.STANCE_* for hit testing.
func stance() -> int:
	if st.ko > 0.0:
		return Kit.STANCE_BACK
	var m: int = mv if is_local else net_mv & 7
	return Kit.STANCE_CROUCH if m == MV_CROUCH or m == MV_SLIDE or m == MV_DIVE else Kit.STANCE_STAND


## Bent double and creeping (or keeping still): much harder for a cop to pick out.
func is_crouched() -> bool:
	return (mv if is_local else net_mv & 7) == MV_CROUCH


func is_aiming() -> bool:
	return net_byte() & 16 != 0


func aim_dir() -> Vector3:
	return -rig.cam.global_basis.z


# --- input ---

func _unhandled_input(e: InputEvent) -> void:
	if not is_local:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if e is InputEventMouseMotion and captured:
		# Scales with the aim zoom, not with the speed widening on top of it.
		var s: float = SENS * rig.fov_target / 75.0
		rotate_y(-e.relative.x * s)
		rig.pitch(-e.relative.y * s)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(1)
		elif not captured and not Net.game.hud.shop_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_local:
		return
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and can_act()
	var wish := Vector3.ZERO
	if active:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = global_basis * Vector3(iv.x, 0, iv.y)
		wish.y = 0.0
		wish = wish.normalized()
	var jump_held := active and Input.is_action_pressed("jump")
	# Edge taken here, not from is_action_just_pressed: one press must never read as two taps.
	var jump_tap := jump_held and not _jump_was
	_jump_was = jump_held
	var crouch := active and Input.is_action_pressed("crouch")
	var top := (SPRINT if Input.is_action_pressed("sprint") else WALK) * speed_mult()
	_buffer_t = JUMP_BUFFER if jump_tap else _buffer_t - delta
	_slide_cd -= delta
	_dive_cd -= delta
	_recover_t -= delta
	if _recover_t > 0.0:
		wish = Vector3.ZERO
	_jumped = false

	if st.get("hide", -1) >= 0:
		# Tucked away: keep still. Jumping is the quick way out.
		velocity = Vector3.ZERO
		mv = MV_GROUND
		_set_crouch(false)
		if jump_tap:
			Net.game.to_server("srv_unhide_me")
		return

	_pit_cd -= delta
	if _pit >= 0:
		_in_pit(wish, jump_tap, delta)
		return

	if mv == MV_RIDE:
		_ride(active, delta)
		if _ride_spd > 4.0 and Places.pit_at(global_position) >= 0:
			# Front wheel into somebody's sandcastle excavation.
			knock(-global_basis.z * 3.0 + Vector3(0, 5.0, 0))
			Net.game.to_server("srv_crash", [], Net.game.motos)
		return

	var grounded := is_on_floor()
	if grounded:
		_coyote_t = COYOTE
		_air_jumps = AIR_JUMPS
		_wall_last = Vector3.ZERO
		if mv == MV_AIR or mv == MV_WALLRUN:
			# Holding jump hops straight off again; holding crouch carries the landing into a slide.
			if crouch and not jump_held and _buffer_t <= 0.0 and hspeed() >= SLIDE_MIN:
				_start_slide()
			else:
				mv = MV_GROUND
		elif mv == MV_DIVE and velocity.y <= 0.0:
			_land_dive(crouch)
	else:
		_coyote_t -= delta
		if mv == MV_GROUND or mv == MV_SLIDE or mv == MV_CROUCH:
			mv = MV_AIR
			# Running off the lip of a ramp keeps the climb it had.
			velocity.y = maxf(velocity.y, _ramp_vy)
			_ramp_vy = 0.0

	if active and Input.is_action_just_pressed("dive") and _dive_cd <= 0.0 and mv != MV_DIVE:
		_start_dive(wish)

	match mv:
		MV_GROUND:
			if _crouched and not _set_crouch(false):
				mv = MV_CROUCH
			elif jump_held or _buffer_t > 0.0:
				# Jumping on the landing tick skips friction entirely: that is the bunny hop.
				_jump()
			elif crouch and _recover_t <= 0.0 and hspeed() >= SLIDE_MIN:
				_start_slide()
			elif crouch and _recover_t <= 0.0:
				mv = MV_CROUCH
				_set_crouch(true)
			else:
				_friction(FRICTION, delta)
				_accelerate(wish, top, GROUND_ACCEL * top, delta)
		MV_SLIDE:
			_slide_t += delta
			var hs := hspeed()
			if (jump_held or _buffer_t > 0.0) and _set_crouch(false):
				if _slide_t > SLIDE_HOP_MIN:
					_boost(SLIDE_HOP)
				_jump()
			elif not crouch and _set_crouch(false):
				mv = MV_GROUND
			elif hs < SLIDE_END:
				# Run out of slide with crouch still held, or under something too low to stand in.
				mv = MV_CROUCH
			else:
				_friction(SLIDE_FRICTION, delta)
				_accelerate(wish, 1.5, 12.0, delta)
		MV_CROUCH:
			if (jump_held or _buffer_t > 0.0) and _set_crouch(false):
				_jump()
			elif not crouch and _set_crouch(false):
				mv = MV_GROUND
			else:
				_set_crouch(true)
				_friction(FRICTION, delta)
				_accelerate(wish, CROUCH_SPEED * speed_mult(), GROUND_ACCEL * CROUCH_SPEED, delta)
		MV_AIR:
			if _crouched:
				_set_crouch(false)
			velocity.y -= GRAVITY * delta
			if _buffer_t > 0.0 and _coyote_t > 0.0:
				_jump()
			elif jump_tap and _can_wall() and not _same_wall(get_wall_normal()):
				_wall_jump(get_wall_normal())
			elif jump_tap and _air_jumps > 0:
				_double_jump(wish)
			_accelerate(wish, AIR_WISH_CAP, AIR_ACCEL, delta)
			if hspeed() < AIR_STEER_SPEED:
				_accelerate(wish, AIR_STEER_SPEED, AIR_STEER, delta)
			if mv == MV_AIR and _can_wall() and hspeed() >= WALL_MIN_SPEED and velocity.y > -9.0 and not _same_wall(get_wall_normal()):
				mv = MV_WALLRUN
				_wall_n = get_wall_normal()
				_wall_t = 0.0
				_air_jumps = AIR_JUMPS
				velocity.y = clampf(velocity.y, 2.0, 3.0)
		MV_WALLRUN:
			_wall_run(crouch, delta)
		MV_DIVE:
			velocity.y -= GRAVITY * delta
			_accelerate(wish, AIR_WISH_CAP * 0.5, AIR_ACCEL, delta)

	if grounded and not _jumped and velocity.y < 0.0:
		velocity.y = 0.0
	if st.dead:
		velocity = Vector3.ZERO
		mv = MV_GROUND
		_set_crouch(false)
	floor_snap_length = 0.3 if grounded and not _jumped else 0.0
	var fall := velocity.y
	move_and_slide()
	if is_on_floor():
		# Only steady footing counts as a ramp; a landing or take-off tick moves in y for other reasons.
		# The climb is remembered for a moment, since the body flattens out rounding the lip.
		_ramp_vy = maxf(clampf(get_real_velocity().y, 0.0, hspeed()), _ramp_vy - 12.0 * delta) if grounded and not _jumped else 0.0
		if not grounded:
			rig.dip = clampf(-fall * 0.012, 0.0, 0.22)
	if is_on_floor() and _pit_cd <= 0.0 and mv != MV_DIVE:
		var pit := Places.pit_at(global_position)
		if pit >= 0:
			_pit = pit
			_pit_jumps = 0
			mv = MV_GROUND
			_set_crouch(false)
			velocity = Vector3.ZERO
			rig.dip = 0.22
			Net.game.hud.toast("You fell in a hole!  Jump, and jump again, to climb out")
			Sfx.play("kick", global_position, 2.0, 0.6)
	# Bodies only get in the way of someone on their feet, not sliding past or hopping over.
	if global_position.y < 1.0 and mv != MV_SLIDE and mv != MV_DIVE and mv != MV_CROUCH:
		global_position += Net.game.crowd.push_out(global_position) * delta


## Down a hole: nowhere to go but round the bottom of it until two good jumps get you out.
func _in_pit(wish: Vector3, jump_tap: bool, delta: float) -> void:
	var pit: Dictionary = Places.pits[_pit] if _pit < Places.pits.size() else {}
	if pit.is_empty():
		_pit = -1
		return
	velocity = wish * 1.2
	move_and_slide()
	var off: Vector3 = global_position - pit.pos
	off.y = 0.0
	var room: float = pit.r * 0.55
	if off.length() > room:
		global_position = Vector3(pit.pos.x, global_position.y, pit.pos.z) + off.normalized() * room
	if not jump_tap:
		return
	_pit_jumps += 1
	_anim.jump(CharRig.HOP)
	rig.dip = 0.12
	if _pit_jumps >= 2:
		_pit = -1
		_pit_cd = 1.2
		var out := wish if wish != Vector3.ZERO else -global_basis.z
		velocity = out * 4.5 + Vector3(0, JUMP * 1.15, 0)
		_hop(CharRig.HOP)
		mv = MV_AIR


# --- riding ---

## Called when the server puts this (local) player on a bike.
func start_ride() -> void:
	_set_crouch(false)
	_ride_spd = minf(hspeed(), RIDE_SAND)
	mv = MV_RIDE


## Called when the server takes this (local) player off their bike.
func stop_ride() -> void:
	if mv == MV_RIDE:
		mv = MV_AIR
		_air_jumps = AIR_JUMPS


## How far the bike is banked into its turn, for whoever draws it.
func ride_lean() -> float:
	return _ride_steer if is_local else _bank


## Throttle and brake on W / S, steer with A / D or by looking. Hitting a wall at speed throws you.
func _ride(active: bool, delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	var paved := global_position.z > Layout.ROAD_Z and global_position.y < 1.0
	var top := RIDE_ROAD if paved else RIDE_SAND
	if iv.y < -0.1:
		_ride_spd = move_toward(_ride_spd, top, RIDE_ACCEL * delta)
	elif iv.y > 0.1:
		_ride_spd = move_toward(_ride_spd, -4.0, RIDE_BRAKE * delta)
	else:
		_ride_spd = move_toward(_ride_spd, 0.0, 5.0 * delta)
	# Deep sand drags a fast bike down.
	if _ride_spd > top:
		_ride_spd = move_toward(_ride_spd, top, RIDE_BRAKE * delta)
	var grip := clampf(absf(_ride_spd) / 5.0, 0.0, 1.0) * signf(_ride_spd)
	rotate_y(-iv.x * RIDE_STEER * grip * delta)
	_ride_steer = lerpf(_ride_steer, -iv.x * 0.35 * absf(grip), minf(1.0, 8.0 * delta))

	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = fwd.x * _ride_spd
	velocity.z = fwd.z * _ride_spd
	if is_on_floor():
		velocity.y = 4.6 if active and Input.is_action_just_pressed("jump") else maxf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	floor_snap_length = 0.3 if is_on_floor() and velocity.y <= 0.0 else 0.0
	var before := absf(_ride_spd)
	move_and_slide()
	var after := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if before > 9.0 and after < before * 0.35:
		_ride_spd = 0.0
		knock(-fwd * 4.0 + Vector3(0, 5.0, 0))
		Net.game.to_server("srv_crash", [], Net.game.motos)
		return
	_ride_spd = minf(_ride_spd, after + 2.0) if _ride_spd > 0.0 else _ride_spd

	# Anyone in the way goes over the handlebars' worth of flying.
	_ram_cd -= delta
	if before > Net.game.motos.RAM_SPEED and _ram_cd <= 0.0:
		var hit: int = Net.game.crowd.pick_near(global_position + Vector3(0, 0.9, 0) - fwd * 0.3, fwd, 1.6)
		if hit >= 0:
			_ram_cd = 0.35
			_ride_spd *= 0.8
			Net.game.to_server("srv_ram", [hit], Net.game.motos)


## Thrown through the air by something big: a bus, a crash.
func knock(v: Vector3) -> void:
	if mv == MV_RIDE:
		Net.game.to_server("srv_dismount", [], Net.game.motos)
	velocity = v
	mv = MV_AIR
	_air_jumps = 0
	_coyote_t = 0.0
	_recover_t = 0.5
	_set_crouch(false)
	rig.kick = 0.1


## This player's net_mv as others should see it.
func net_byte() -> int:
	if not is_local:
		return net_mv
	var aiming := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("aim") and can_act()
	return mv | (8 if mv == MV_WALLRUN and _wall_side > 0.0 else 0) | (16 if aiming else 0) | (_hops << 5) | (128 if _hop_air else 0)


## Counts a jump so every peer's copy of this body plays it, even when one hop runs into the next.
func _hop(kind: int) -> void:
	_hops = (_hops + 1) & 3
	_hop_air = kind == CharRig.DOUBLE
	_hops_seen = _hops
	_anim.jump(kind)


func hspeed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _friction(amount: float, delta: float) -> void:
	var s := hspeed()
	if s < 0.05:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var k := maxf(s - maxf(s, STOP_SPEED) * amount * delta, 0.0) / s
	velocity.x *= k
	velocity.z *= k


## Adds speed along `wish` only while the speed already going that way is under `wish_speed`.
func _accelerate(wish: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var add := wish_speed - (velocity.x * wish.x + velocity.z * wish.z)
	if add <= 0.0:
		return
	var a := minf(accel * delta, add)
	velocity.x += wish.x * a
	velocity.z += wish.z * a


## Speeds up along the current heading, as far as BOOST_CAP.
func _boost(amount: float) -> void:
	var s := hspeed()
	if s < 0.1 or s >= BOOST_CAP:
		return
	var k := (s + minf(amount, BOOST_CAP - s)) / s
	velocity.x *= k
	velocity.z *= k


func _jump() -> void:
	velocity.y = JUMP + maxf(_ramp_vy, 0.0)
	_ramp_vy = 0.0
	_buffer_t = 0.0
	_coyote_t = 0.0
	_jumped = true
	_hop(CharRig.HOP)
	mv = MV_AIR


## Second jump in mid-air. Half turns the momentum toward where the keys point.
func _double_jump(wish: Vector3) -> void:
	_air_jumps -= 1
	_buffer_t = 0.0
	_hop(CharRig.DOUBLE)
	velocity.y = DOUBLE_JUMP
	if wish != Vector3.ZERO:
		var s := maxf(hspeed(), WALK)
		var h := (Vector3(velocity.x, 0.0, velocity.z).lerp(wish * s, 0.5)).normalized() * s
		velocity.x = h.x
		velocity.z = h.z


func _start_slide() -> void:
	mv = MV_SLIDE
	_slide_t = 0.0
	_set_crouch(true)
	if _slide_cd <= 0.0:
		_slide_cd = SLIDE_CD
		_boost(SLIDE_BOOST)


func _start_dive(wish: Vector3) -> void:
	var dir := wish
	if dir == Vector3.ZERO:
		dir = -global_basis.z
		dir.y = 0.0
		dir = dir.normalized()
	var s := maxf(hspeed(), DIVE_SPEED * speed_mult())
	velocity.x = dir.x * s
	velocity.z = dir.z * s
	velocity.y = DIVE_UP if is_on_floor() else maxf(velocity.y, DIVE_UP * 0.6)
	_dive_cd = DIVE_CD
	_jumped = true
	mv = MV_DIVE
	_set_crouch(true)


## Crouch held: the dive runs out into a slide. Otherwise a belly flop that costs speed.
func _land_dive(crouch: bool) -> void:
	if crouch and hspeed() >= SLIDE_END:
		mv = MV_SLIDE
		_slide_t = 0.0
		return
	velocity.x *= 0.45
	velocity.z *= 0.45
	_recover_t = DIVE_RECOVER
	mv = MV_GROUND if _set_crouch(false) else MV_CROUCH


## Touching a runnable wall while airborne. No running up the prison walls.
func _can_wall() -> bool:
	return is_on_wall_only() and absf(get_wall_normal().y) < 0.2 and st.jail <= 0.0


func _same_wall(n: Vector3) -> bool:
	return _wall_last != Vector3.ZERO and n.dot(_wall_last) > 0.9 and absf(n.dot(global_position) - _wall_last_d) < 0.8


func _leave_wall(n: Vector3) -> void:
	_wall_last = n
	_wall_last_d = n.dot(global_position)
	mv = MV_AIR


func _wall_jump(n: Vector3) -> void:
	velocity.x += n.x * WALL_JUMP_OUT
	velocity.z += n.z * WALL_JUMP_OUT
	velocity.y = WALL_JUMP_UP
	_air_jumps = AIR_JUMPS
	_buffer_t = 0.0
	_jumped = true
	_hop(CharRig.WALL)
	_leave_wall(n)


func _wall_run(crouch: bool, delta: float) -> void:
	var n := _wall_n
	_wall_side = 1.0 if n.dot(global_basis.x) < 0.0 else -1.0
	_wall_t += delta
	if _buffer_t > 0.0:
		_wall_jump(n)
		return
	var from := global_position + Vector3(0, 0.7, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from - n * 0.8, 1)
	var along := Vector3(velocity.x, 0.0, velocity.z)
	along -= n * along.dot(n)
	var s := along.length()
	if crouch or _wall_t > WALL_TIME or s < WALL_MIN_SPEED * 0.6 or get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		_leave_wall(n)
		return
	along = along / s * maxf(s, minf(s + 8.0 * delta, SPRINT))
	# Lean into the wall to stay on it; gravity creeps back in the longer the run lasts.
	velocity.x = along.x - n.x * 2.0
	velocity.z = along.z - n.z * 2.0
	velocity.y = maxf(velocity.y - (WALL_GRAVITY + 5.0 * _wall_t) * delta, -3.0)


## Shrinks or restores the body. Standing back up fails while something is overhead.
func _set_crouch(on: bool) -> bool:
	if on == _crouched:
		return true
	if not on and test_move(global_transform, Vector3.UP * (STAND_H - CROUCH_H)):
		return false
	_crouched = on
	var h := CROUCH_H if on else STAND_H
	_cap.height = h
	_shape.position.y = h * 0.5
	return true


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		# Server ticks the real timers; mirror them locally for display and movement.
		st.jail = maxf(0.0, st.jail - delta)
		for d in st.drugs:
			st.drugs[d].t = maxf(0.0, st.drugs[d].t - delta)
		for d in st.tol:
			st.tol[d] = maxf(0.0, st.tol[d] - DB.TOLERANCE_DECAY * delta)
	if is_local:
		_vis.visible = (st.dead or not rig.first_person()) and st.get("hide", -1) < 0
		_local_process(delta)
	else:
		_vis.visible = st.get("hide", -1) < 0
		_label.visible = not st.dead
		global_position = global_position.lerp(net_pos, minf(1.0, 14.0 * delta))
		rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, 14.0 * delta))
	_animate(delta)


## Poses the body from how it is moving and shows its worn state from `st`.
func _animate(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	if delta > 0.0:
		var k := minf(1.0, 10.0 * delta)
		_spd = lerpf(_spd, Vector2(moved.x, moved.z).length() / delta, k)
		_vy = lerpf(_vy, moved.y / delta, minf(1.0, 18.0 * delta))
		_turn = lerpf(_turn, angle_difference(_yaw_was, rotation.y) / delta, k)
	_yaw_was = rotation.y

	var m: int = mv if is_local else net_mv & 7
	var side: float = _wall_side if is_local else (1.0 if net_mv & 8 else -1.0)
	if not is_local and (net_mv >> 5) & 3 != _hops_seen:
		_hops_seen = (net_mv >> 5) & 3
		_anim.jump(CharRig.DOUBLE if net_mv & 128 else CharRig.HOP)
	var out: bool = st.ko > 0.0
	# The pose id only says what kind of thing the body is doing; the rig does the posing.
	var pose := Kit.STAND
	if st.dead:
		pose = Kit.DEAD
	elif out:
		pose = Kit.KO
	elif m == MV_RIDE:
		pose = Kit.RIDE
	elif m == MV_SLIDE:
		pose = Kit.SLIDE
	elif m == MV_DIVE:
		pose = Kit.DIVE
	elif m == MV_CROUCH:
		pose = Kit.CROUCH
	elif m == MV_AIR:
		pose = Kit.JUMP
	var held: int = DB.ITEMS[st.equipped].get("held", Kit.HELD_NONE)
	var aim: float = rig.rotation.x if is_local else net_pitch
	_anim.update(delta, m, CharRig.DEAD if st.dead else (CharRig.OUT if out else CharRig.ALIVE), _spd, _vy, _turn, aim, side, held, net_byte() & 16 != 0)
	_anim.apply(_mats)

	# Wall runners tip over with their feet toward the wall; riders and runners bank into a turn.
	_bank = lerpf(_bank, clampf(_turn * _spd * 0.012, -0.35, 0.35), minf(1.0, 8.0 * delta))
	var roll := 0.0
	if st.dead or out:
		roll = 0.0
	elif m == MV_WALLRUN:
		roll = side * 0.4
	elif m == MV_RIDE:
		roll = ride_lean()
	elif m == MV_GROUND:
		roll = _bank * 0.5
	_vis.rotation.z = lerp_angle(_vis.rotation.z, roll, minf(1.0, 10.0 * delta))
	# Anyone standing in a hole is that much shorter.
	var deep: float = Places.depth_at(global_position) if (_pit >= 0 or not is_local) and global_position.y < 0.6 else 0.0
	_sink = lerpf(_sink, deep, minf(1.0, 9.0 * delta))
	_vis.position.y = -_sink

	# Everything another player needs to know about you is worn on the body.
	var flags := clampi(st.heat, 0, 3) << Kit.HEAT_SHIFT
	if st.jail > 0.0:
		flags |= Kit.F_JAIL
	else:
		flags |= Kit.F_SHORTS
	if st.money >= 1000:
		flags |= Kit.F_SACK_L
	elif st.money >= 200:
		flags |= Kit.F_SACK_S
	elif st.money > 0:
		flags |= Kit.F_WAD
	if pose != _pose:
		_prev = _pose
		_pose = pose
		_pose_t = Kit.now()
	var data := Kit.custom(pose, 0.0, flags, _ev, _prev, _pose_t, held)
	_body.set_instance_custom_data(0, data)
	_held.set_instance_custom_data(0, data)


## Plays a punch / recoil (attack) or a flinch on this player's body.
func fx_event(attack: bool) -> void:
	if st.dead:
		return
	_ev = Kit.now() if attack else -Kit.now()
	if is_local and not attack:
		rig.kick = 0.05


## Where this player's shots visibly leave from: the gun in first person, the hand otherwise.
func muzzle() -> Vector3:
	if is_local and rig.first_person():
		return rig.cam.global_transform * Vector3(0.24, -0.16, -0.95)
	var pitch: float = rig.rotation.x if is_local else net_pitch
	return global_position + Vector3(0, 1.0, 0) + global_basis * (Basis(Vector3.RIGHT, pitch) * Vector3(0.2, 0.0, -0.75))


## The gun bucks: the view jumps and only mostly comes back.
func recoil() -> void:
	var k: float = DB.ITEMS[st.equipped].get("recoil", 0.0)
	rig.recoil(k, randf_range(-0.4, 0.4) * k)
	_vm_t = Kit.now()


## A one-off bit of body language started by the host (Game.cl_anim).
func play(what: String, seconds: float) -> void:
	if what == "reload":
		_reload_t = Kit.now()
		_reload_len = seconds
		Sfx.play("reload", global_position + HEAD)


func _animate_viewmodel() -> void:
	_vm.visible = rig.first_person() and not st.dead
	var gun: bool = DB.is_gun(st.equipped)
	for held in _vm_guns:
		_vm_guns[held].visible = held == DB.ITEMS[st.equipped].held
	var dt := Kit.now() - _vm_t
	var e := smoothstep(0.0, 0.06, dt) * (1.0 - smoothstep(0.08, 0.28, dt))
	var sway := Vector3(0.0, sin(Kit.now() * 9.0) * 0.012, 0.0) * minf(_spd / WALK, 1.5)
	_vm_r.position = VM_RIGHT + sway
	_vm_l.position = VM_LEFT - sway
	_vm_r.rotation.x = 0.0
	if gun:
		# Recoil: the pistol jumps back and tips up.
		_vm_r.position = Vector3(0.24, -0.24, -0.7) + sway + Vector3(0.0, 0.03, 0.1) * e
		_vm_r.rotation.x = 0.35 * e
		_vm_l.position = VM_LEFT + Vector3(0.0, -0.12, 0.1)
		# Reloading: the gun drops out of view and comes back up.
		var r := clampf((Kit.now() - _reload_t) / _reload_len, 0.0, 1.0)
		var dip := sin(r * PI)
		_vm_r.position += Vector3(0.0, -0.22, 0.05) * dip
		_vm_r.rotation.x += 0.7 * dip
		_vm_l.position += Vector3(0.12, 0.06, -0.1) * dip
	elif _vm_side > 0.0:
		_vm_r.position += Vector3(-0.2, 0.14, -0.45) * e
	else:
		_vm_l.position += Vector3(0.2, 0.14, -0.45) * e


func _local_process(delta: float) -> void:
	var g = Net.game
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var head := global_position + HEAD
	var dir := aim_dir()
	_animate_viewmodel()

	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.1
		g.crowd.refresh_near(global_position)
	target_npc = g.crowd.pick_near(head, dir, ROB_RANGE) if can_fight() and mv != MV_RIDE else -1

	# Meth: sniper zoom while high, shakes on the way down, twitching on overdose.
	var aiming := captured and Input.is_action_pressed("aim")
	rig.fov_target = (20.0 if is_sniper() else 55.0) if aiming else 75.0
	match drug_phase("meth"):
		"down": rig.shake = 0.012
		"od": rig.shake = 0.04
		_: rig.shake = 0.0

	# Speed reads through the camera: wider view, a lean off the wall, a low head in a slide.
	rig.fov_boost = 0.0 if aiming else clampf((hspeed() - SPRINT) * 1.6, 0.0, 22.0)
	rig.height_target = ((DUCK_HEAD if mv == MV_CROUCH else CROUCH_HEAD) if _crouched else HEAD.y) - _sink
	match mv:
		MV_WALLRUN: rig.roll_target = _wall_side * 0.22
		MV_SLIDE: rig.roll_target = 0.05
		MV_RIDE: rig.roll_target = _ride_steer * 0.5
		_: rig.roll_target = clampf(-velocity.dot(global_basis.x) * 0.004, -0.05, 0.05)
	if is_drunk():
		rig.roll_target += sin(Kit.now() * 1.3) * 0.07

	_attack_t -= delta
	_rob_t -= delta
	robbing = false
	if captured and can_fight():
		if Input.is_action_pressed("attack") and _attack_t <= 0.0:
			_attack_t = DB.ITEMS[st.equipped].cooldown
			# The point on the line of sight level with the head: where the blow starts from.
			var cam: Vector3 = rig.cam.global_position
			g.to_server("srv_attack", [cam + dir * maxf(0.0, (head - cam).dot(dir)), dir])
			if DB.ITEMS[st.equipped].melee:
				_vm_t = Kit.now()
				_vm_side = -_vm_side
		if Input.is_action_just_pressed("reload"):
			g.to_server("srv_reload")
		if Input.is_action_pressed("rob") and target_npc >= 0:
			robbing = true
			if _rob_t <= 0.0:
				_rob_t = 0.1
				g.to_server("srv_rob", [target_npc, Mic.loudness * mic_mult()], g.crowd)
		if Input.is_action_just_pressed("weapon_1"):
			g.to_server("srv_equip", [_next_weapon(DB.MELEE)])
		if Input.is_action_just_pressed("weapon_2"):
			g.to_server("srv_equip", [_next_weapon(DB.GUNS)])
		for d in DB.DRUGS:
			if Input.is_action_just_pressed(DB.ITEMS[d].key):
				g.to_server("srv_use", [d])

	_send_t -= delta
	if _send_t <= 0.0 and not multiplayer.is_server():
		_send_t = 0.05
		g.srv_move.rpc_id(1, global_position, rotation.y, net_byte(), rig.rotation.x)


## The next weapon of this kind the player owns after the one in hand, or the first.
func _next_weapon(kinds: Array) -> String:
	var at: int = kinds.find(st.equipped)
	for k in kinds.size():
		var item: String = kinds[(at + 1 + k) % kinds.size()]
		if st.inv.has(item):
			return item
	return st.equipped


# --- proximity voice playback ---

func voice_push(rate: int, data: PackedByteArray) -> void:
	if _voice == null or rate != _voice_rate:
		if _voice != null:
			_voice.queue_free()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = rate
		gen.buffer_length = 0.5
		_voice = AudioStreamPlayer3D.new()
		_voice.stream = gen
		_voice.unit_size = 8.0
		_voice.max_distance = Mic.VOICE_RANGE + 5.0
		_voice.position = HEAD
		add_child(_voice)
		_voice.play()
		_voice_rate = rate
	var n := data.size() / 2
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var v := data.decode_s16(i * 2) / 32768.0
		frames[i] = Vector2(v, v)
	var pb = _voice.get_stream_playback()
	if pb != null and pb.can_push_buffer(n):
		pb.push_buffer(frames)
