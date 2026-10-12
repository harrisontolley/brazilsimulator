extends CharacterBody3D
## One per connected peer on every machine. The owning client drives movement;
## `st` is server-owned state replicated through Game.cl_state.

const CameraRig := preload("res://scenes/player/camera_rig.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")
const WeaponKit := preload("res://scenes/weapons/weapon_kit.gd")
const CharRig := preload("res://scenes/characters/char_rig.gd")
const Layout := preload("res://scenes/world/layout.gd")
const Places := preload("res://scenes/world/places.gd")

enum { MV_GROUND, MV_AIR, MV_SLIDE, MV_WALLRUN, MV_DIVE, MV_RIDE, MV_CROUCH, MV_SWIM }

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
## Swimming: breaststroke and crawl on top, and the same pair under water.
const SWIM_SPEED := 2.4
const SWIM_FAST := 4.3
const SWIM_UNDER := 2.8
const SWIM_UNDER_FAST := 4.1
const SWIM_ACCEL := 7.0
## How far below the surface a floating body's feet-end sits, and how far below it has to be
## before the head has gone under.
const FLOAT := 0.55
const SWIM_HEAD := 0.8
## Water this deep takes you off your feet; this shallow and you can stand again.
const SWIM_IN := 1.0
const SWIM_OUT := 0.85
const SWIM_EYE := 0.78
const CLIMB_TIME := 0.42
## A jet ski: quicker than a bike on sand, turns on its tail, and stops dead on the beach.
const SKI_SPEED := 24.0
const SKI_ACCEL := 11.0
const SKI_STEER := 2.3
const ROB_RANGE := 4.0
const HEAD := Vector3(0, 1.3, 0)
## Kit characters are adult-sized; the players are kids.
const BODY_SCALE := 0.78
const VM_RIGHT := Vector3(0.3, -0.3, -0.75)
const VM_LEFT := Vector3(-0.3, -0.32, -0.7)
## How long an arm takes to draw all the way back.
const THROW_WIND := 0.9
## Ayahuasca: how fast the wandering eye flies, and how far from the body it may go.
const SPIRIT_SPEED := 14.0
const SPIRIT_REACH := 70.0
## How much bigger a body on bomba stands.
const BULK := 1.25

var id := 0
var pname := "Kid"
var is_local := false
var st: Dictionary = fresh_state()
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var wanted_t := 0.0  # server only
var rig: Node3D
var target_npc := -1
## While riding: someone close enough to grab something off as you pass, or -1.
var snatch_npc := -1
var robbing := false
## The drug the hotbar has picked out: what G takes.
var drug_sel := ""
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

var _swim_under := false
var _plunge_t := 0.0
var _climb_t := -1.0
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _edge_told := false
## Seconds of breath left, as this machine reckons it. The host keeps the count that matters.
var air := DB.BREATH
var _was_m := MV_GROUND
var _was_under := false
var _vel := Vector3.ZERO
var _step_i := 0
var _bubble_t := 0.0

var _on_ski := false
var _ski_sea := 0.0
var _ski_wet := true
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
var _look := 0
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
var _wind := -1.0   # seconds an arm has been drawn back to throw, -1 when it is not
## Eye to the scope of whatever is in hand, for the HUD to draw it.
var scoped := false
var _send_t := 0.0
var _near_t := 0.0
var _rob_t := 0.0
var _attack_t := 0.0
var _voice: AudioStreamPlayer3D
var _voice_rate := 0
# Where the eyes have wandered off to while the body stays behind, in world axes from the head.
var _fly := Vector3.ZERO
var _forced_t := 0.0


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
		if held == Kit.HELD_LAUNCHER:
			# The tube sits on the shoulder, off to the side of the picture, not across it.
			gun.position = Vector3(0.12, 0.0, 0.2)
			gun.scale = Vector3.ONE * 0.95
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


## Every active drug's say on `stat` (see the `fx` tables in DB.ITEMS), multiplied together.
func _fx(stat: String) -> float:
	var m := 1.0
	for d in st.drugs:
		m *= DB.ITEMS[d].get("fx", {}).get(st.drugs[d].phase, {}).get(stat, 1.0)
	return m


## The same for the stats that pile up rather than multiply: camera shake and sway.
func _fx_sum(stat: String) -> float:
	var v := 0.0
	for d in st.drugs:
		v += DB.ITEMS[d].get("fx", {}).get(st.drugs[d].phase, {}).get(stat, 0.0)
	return v


func speed_mult() -> float:
	return _fx("speed")


func melee_mult() -> float:
	return _fx("melee")


func damage_taken_mult() -> float:
	return _fx("taken")


func jump_mult() -> float:
	return _fx("jump")


func gravity_mult() -> float:
	return _fx("grav")


func recoil_mult() -> float:
	return _fx("recoil")


## How fast the police lose interest, and how far off one can pick this player out.
func cool_mult() -> float:
	return _fx("cool")


func seen_mult() -> float:
	return _fx("seen")


func is_drunk() -> bool:
	for d in DB.DRINKS:
		if drug_phase(d) == "high":
			return true
	return false


## Dutch courage: a drink makes the shouting land harder.
func intimidation_mult() -> float:
	return 1.4 if is_drunk() else 1.0


func is_sniper() -> bool:
	return drug_phase("meth") == "high"


## Cocaine past the limit: cannot shut up. The mic reads as shouting whatever comes out of it.
func is_gabbling() -> bool:
	return drug_phase("cocaine") == "od"


func mic_mult() -> float:
	return _fx("mic")


## What the mic is worth right now, drugs and all.
func mic_level() -> float:
	return maxf(Mic.loudness, 0.7) if is_gabbling() else Mic.loudness * mic_mult()


## Out of the body on ayahuasca: the eyes go wandering and the legs stay put.
func is_spirit() -> bool:
	return drug_phase("ayahuasca") != ""


## Roid rage: swinging at whatever is nearest, and in no state to work a gun.
func is_raging() -> bool:
	return drug_phase("bomba") == "od"


## A bad trip: left is right and forward is back.
func is_inverted() -> bool:
	return drug_phase("doce") == "od"


## Loved up: nobody near feels like a fight, and everybody feels like dancing.
func is_loved() -> bool:
	return drug_phase("bala") == "high"


## Standing in the sea, which is the one thing that cools an overheating body down.
func in_sea() -> bool:
	return Layout.wet(global_position)


func swimming() -> bool:
	return (mv if is_local else net_mv & 7) == MV_SWIM


## Swimming with the head below the surface: holding a breath.
func head_under() -> bool:
	var p := global_position
	return swimming() and p.y + SWIM_HEAD < Layout.wave_y(p.x, p.z)


## The drugs in this player's pockets, in hotbar order.
func drugs_held() -> Array:
	var out: Array = []
	for d in DB.DRUGS:
		if st.inv.get(d, 0) > 0:
			out.append(d)
	return out


func can_act() -> bool:
	return not st.dead and not MatchState.ended and st.ko <= 0.0


## Able to hit, be hit, pick things up. Inmates can; what they cannot do is leave.
func can_fight() -> bool:
	return can_act() and st.get("hide", -1) < 0


## Able to use what is in hand: not something to try while keeping afloat.
func can_attack() -> bool:
	return can_fight() and not swimming()


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
	if m == MV_SWIM:
		h = SWIM_EYE
	elif m == MV_CROUCH:
		h = DUCK_HEAD
	elif m == MV_SLIDE or m == MV_DIVE:
		h = CROUCH_HEAD
	return global_position + Vector3(0, h, 0)


## Kit.STANCE_* for hit testing.
func stance() -> int:
	if st.ko > 0.0:
		return Kit.STANCE_BACK
	var m: int = mv if is_local else net_mv & 7
	return Kit.STANCE_CROUCH if m == MV_CROUCH or m == MV_SLIDE or m == MV_DIVE or m == MV_SWIM else Kit.STANCE_STAND


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
	var captured := Controls.playing()
	if e is InputEventMouseMotion and captured:
		# Scales with the aim zoom, not with the speed widening on top of it.
		var s: float = Settings.sens * rig.fov_target / Settings.fov
		var flip := -1.0 if is_inverted() else 1.0
		rotate_y(-e.relative.x * s * flip)
		rig.pitch(e.relative.y * s * (1.0 if Settings.invert_y else -1.0) * flip)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.zoom(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.zoom(1)
		elif not captured and not Net.game.hud.shop_open and not Net.game.hud.menu_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif e.is_action_pressed("ui_cancel"):
		Net.game.hud.open_pause()


func _physics_process(delta: float) -> void:
	if not is_local:
		return
	var active := Controls.playing() and can_act()
	var wish := Vector3.ZERO
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	if is_inverted():
		iv = -iv
	if is_spirit():
		# The keys move the eyes; the legs are not listening.
		_spirit(iv, delta)
		iv = Vector2.ZERO
		active = false
	else:
		_fly = _fly.lerp(Vector3.ZERO, minf(1.0, 6.0 * delta))
	wish = global_basis * Vector3(iv.x, 0, iv.y)
	wish.y = 0.0
	wish = wish.normalized()
	var forced := _forced_wish(delta) if can_act() else Vector3.ZERO
	if forced != Vector3.ZERO:
		wish = forced
	var jump_held := active and Input.is_action_pressed("jump")
	# Edge taken here, not from is_action_just_pressed: one press must never read as two taps.
	var jump_tap := jump_held and not _jump_was
	_jump_was = jump_held
	var crouch := active and Input.is_action_pressed("crouch")
	var top := (SPRINT if Input.is_action_pressed("sprint") or drug_phase("guarana") == "od" else WALK) * speed_mult()
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

	# The sea: afloat, or going in, or only wading.
	var sea := Layout.wave_y(global_position.x, global_position.z)
	var deep := sea - global_position.y if global_position.z < Layout.WATER_Z + 3.0 else -1.0
	if mv == MV_SWIM:
		_swim(iv, active, jump_held, jump_tap, crouch, sea, delta)
		return
	if deep > SWIM_IN or (deep > 0.6 and not is_on_floor() and _no_footing(sea)):
		_enter_water()
		return
	if deep > 0.15:
		top *= lerpf(1.0, 0.45, clampf(deep / SWIM_IN, 0.0, 1.0))

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
			velocity.y -= GRAVITY * gravity_mult() * delta
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


# --- drugs that take the wheel ---

## Where an overdose is walking this body whether its owner likes it or not, or zero.
func _forced_wish(delta: float) -> Vector3:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if drug_phase("guarana") == "od":
		# Legs with a mind of their own: flat out, straight ahead. Steering is all that is left.
		return fwd
	if drug_phase("bala") == "od":
		# Cannot stop dancing: two steps one way, two steps the other.
		return global_basis.x * signf(sin(Kit.now() * 5.0))
	if drug_phase("weed") == "od":
		# Larica. The nearest kiosk, and everything on its menu.
		var best := Vector3.ZERO
		var best_d := 1e9
		for v in DB.VENDORS:
			if v.stock == DB.FOOD and global_position.distance_to(v.pos) < best_d:
				best_d = global_position.distance_to(v.pos)
				best = v.pos
		_forced_t -= delta
		if best_d < 3.5:
			if _forced_t <= 0.0:
				_forced_t = 1.5
				Net.game.to_server("srv_larica")
			return Vector3.ZERO
		var to := best - global_position
		to.y = 0.0
		return to.normalized()
	if is_raging():
		# Going for whoever is nearest.
		var crowd = Net.game.crowd
		var near := -1
		var near_d := 8.0
		for i in crowd.near:
			var d: float = crowd.pos[i].distance_to(global_position)
			if d < near_d and not crowd.is_out(i):
				near_d = d
				near = i
		if near >= 0:
			var to: Vector3 = crowd.pos[near] - global_position
			to.y = 0.0
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, 6.0 * delta))
			return to.normalized() if near_d > 1.6 else Vector3.ZERO
	return Vector3.ZERO


## Ayahuasca: the view drifts free of the head. High, the keys fly it about; overdosed, it is
## shut out and can only hang there watching the body be sick.
func _spirit(iv: Vector2, delta: float) -> void:
	if drug_phase("ayahuasca") == "od":
		_fly = _fly.lerp(global_basis * Vector3(0.0, 2.5, 4.0), minf(1.0, 2.0 * delta))
		return
	var b: Basis = rig.cam.global_basis
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	_fly += (b.x * iv.x + b.z * iv.y + Vector3.UP * up) * SPIRIT_SPEED * delta
	_fly = _fly.limit_length(SPIRIT_REACH)
	# Not through the floor.
	_fly.y = maxf(_fly.y, 0.3 - global_position.y - HEAD.y)


# --- swimming ---

## Is the bottom here too far down to stand on with a head above `sea`?
func _no_footing(sea: float) -> bool:
	var from := global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, sea - SWIM_IN - 0.15, from.z), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Off the feet and into the water. Walking in just floats you; falling or diving in carries
## you under on the line you arrived on.
func _enter_water() -> void:
	var hard := velocity.y < -3.5 or mv == MV_DIVE
	mv = MV_SWIM
	_set_crouch(true)
	_swim_under = hard
	_plunge_t = 0.55 if hard else 0.0
	_climb_t = -1.0
	if hard:
		velocity.x *= 0.72
		velocity.z *= 0.72
		velocity.y = maxf(velocity.y * 0.55, -7.5)
		rig.dip = 0.16
	else:
		velocity.y *= 0.3


func _leave_water(to: int) -> void:
	mv = to
	_swim_under = false
	_climb_t = -1.0
	_air_jumps = AIR_JUMPS
	if not _set_crouch(false):
		mv = MV_CROUCH


## Afloat. On the surface the keys swim you about where you face; Ctrl (or Q) ducks under,
## and down there you go where you look, Space up and Ctrl down, until the surface again.
func _swim(iv: Vector2, active: bool, jump_held: bool, jump_tap: bool, crouch: bool, sea: float, delta: float) -> void:
	if _climb_t >= 0.0:
		_climb(delta)
		return
	var d := sea - global_position.y
	_plunge_t -= delta
	if d < 0.2 or global_position.z > Layout.WATER_Z + 3.0:
		# Lifted clear of it: carried off, or thrown.
		_leave_water(MV_AIR)
		return
	if _plunge_t <= 0.0 and can_act() and (sea - Layout.seabed_y(global_position.z) < SWIM_OUT or (is_on_floor() and d < 0.95 and not _swim_under)):
		# Shallow enough to put the feet down.
		_leave_water(MV_GROUND)
		return
	var fast := active and Input.is_action_pressed("sprint")
	if _swim_under:
		var b: Basis = rig.cam.global_basis
		var wish := b * Vector3(iv.x, 0, iv.y) + Vector3.UP * ((1.0 if jump_held else 0.0) - (1.0 if crouch else 0.0))
		wish = wish.limit_length(1.0)
		if _plunge_t > 0.0:
			# Still spending the speed of the dive.
			velocity = velocity.move_toward(Vector3.ZERO, 5.5 * delta) + wish * 4.0 * delta
		else:
			# Left alone, a body with air in it drifts up.
			var want := wish * (SWIM_UNDER_FAST if fast else SWIM_UNDER) * speed_mult() if wish != Vector3.ZERO else Vector3(0, 0.75, 0)
			velocity = velocity.move_toward(want, SWIM_ACCEL * delta)
		# Nothing swims up out of the top of the sea.
		if d <= FLOAT and velocity.y > 0.0:
			velocity.y = 0.0
		if d < FLOAT + 0.14 and velocity.y >= -0.05 and _plunge_t <= 0.0 and not crouch:
			_swim_under = false
	else:
		var wish := global_basis * Vector3(iv.x, 0, iv.y)
		wish.y = 0.0
		wish = wish.normalized()
		var h := Vector3(velocity.x, 0, velocity.z).move_toward(wish * (SWIM_FAST if fast else SWIM_SPEED) * speed_mult(), SWIM_ACCEL * delta)
		velocity.x = h.x
		velocity.z = h.z
		# Riding the swell: sprung to the surface, so a wave lifts you rather than swallowing you.
		velocity.y = move_toward(velocity.y, clampf((d - FLOAT) * 7.0, -2.5, 3.5), 26.0 * delta)
		if active and (crouch or Input.is_action_just_pressed("dive")):
			# Duck dive: head down, heels up, gone.
			_swim_under = true
			velocity.y = minf(velocity.y, -2.8)
			velocity += -global_basis.z * 1.2
		elif active and (jump_tap or (is_on_wall() and iv.y < -0.1)):
			_try_climb(sea)
	_sea_edge(delta)
	floor_snap_length = 0.0
	move_and_slide()


## Something to haul out onto, right in front and not far above the water? Then up it.
func _try_climb(sea: float) -> void:
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var over := global_position + fwd * 0.8
	var q := PhysicsRayQueryParameters3D.create(Vector3(over.x, sea + 1.5, over.z), Vector3(over.x, sea - 0.4, over.z), 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.7 or hit.position.y > sea + 1.45:
		return
	# Nothing in the way where the body will end up.
	var clear := PhysicsRayQueryParameters3D.create(hit.position + Vector3(0, 0.2, 0), hit.position + Vector3(0, STAND_H, 0), 1)
	if not get_world_3d().direct_space_state.intersect_ray(clear).is_empty():
		return
	_climb_t = 0.0
	_climb_from = global_position
	_climb_to = hit.position + Vector3(0, 0.02, 0)
	velocity = Vector3.ZERO


## Hauling out: up the side first, then over the edge.
func _climb(delta: float) -> void:
	_climb_t += delta
	var k := clampf(_climb_t / CLIMB_TIME, 0.0, 1.0)
	var up := smoothstep(0.0, 0.7, k)
	var along := smoothstep(0.45, 1.0, k)
	global_position = Vector3(lerpf(_climb_from.x, _climb_to.x, along), lerpf(_climb_from.y, _climb_to.y, up), lerpf(_climb_from.z, _climb_to.z, along))
	if k >= 1.0:
		velocity = Vector3.ZERO
		_leave_water(MV_GROUND)


## Too far out, and the current brings you back whether you like it or not.
func _sea_edge(delta: float) -> void:
	var p := global_position
	var over := Vector3(maxf(absf(p.x) - Layout.SEA_SOFT_X, 0.0) * -signf(p.x), 0, maxf(Layout.SEA_SOFT_Z - p.z, 0.0))
	if over == Vector3.ZERO:
		_edge_told = false
		return
	global_position += over.normalized() * minf(over.length() / 10.0, 1.0) * 7.0 * delta
	if not _edge_told:
		_edge_told = true
		Net.game.hud.toast("The current is too strong out here")


# --- riding ---

## Called when the server puts this (local) player on a bike.
func start_ride() -> void:
	_set_crouch(false)
	_ride_spd = minf(hspeed(), RIDE_SAND)
	_on_ski = Net.game.motos.on_ski(id)
	_ski_sea = Layout.wave_y(global_position.x, global_position.z)
	_swim_under = false
	_climb_t = -1.0
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
	if _on_ski:
		_ride_water(active, delta)
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	if Layout.depth(global_position) > 0.75:
		# Motorbikes do not float.
		_ride_spd = 0.0
		Net.game.to_server("srv_dismount", [], Net.game.motos)
		Net.game.hud.toast("The sea got into the engine")
		return
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


## A jet ski. It only goes where there is water under it: the hull sits on the swell, leaves
## it off the back of a wave taken fast, and on sand it is a heavy thing to push.
func _ride_water(active: bool, delta: float) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	var p := global_position
	var sea := Layout.wave_y(p.x, p.z) - Layout.SKI_DRAFT
	var afloat := sea - Layout.seabed_y(p.z) > 0.25 and p.z < Layout.WATER_Z + 2.0
	var on_water := afloat and p.y <= sea + 0.05
	if not afloat:
		# Beached. It can be backed off, slowly.
		_ride_spd = move_toward(_ride_spd, -1.6 if iv.y > 0.1 else 0.0, 45.0 * delta)
	elif not on_water:
		pass
	elif iv.y < -0.1:
		_ride_spd = move_toward(_ride_spd, SKI_SPEED * speed_mult(), SKI_ACCEL * delta)
	elif iv.y > 0.1:
		_ride_spd = move_toward(_ride_spd, -3.0, 16.0 * delta)
	else:
		_ride_spd = move_toward(_ride_spd, 0.0, 6.5 * delta)
	# It steers with its jet: nothing at a standstill, everything flat out.
	var grip := clampf(absf(_ride_spd) / 6.0, 0.0, 1.0) * signf(_ride_spd) * (1.0 if on_water or not afloat else 0.25)
	rotate_y(-iv.x * SKI_STEER * grip * delta)
	_ride_steer = lerpf(_ride_steer, -iv.x * 0.4 * absf(grip), minf(1.0, 7.0 * delta))

	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	velocity.x = fwd.x * _ride_spd
	velocity.z = fwd.z * _ride_spd
	# The water holds it up and no more: when the wave drops away faster than the hull falls,
	# it flies.
	var rising := (sea - _ski_sea) / maxf(delta, 0.0001)
	_ski_sea = sea
	velocity.y -= GRAVITY * delta
	if afloat and p.y <= sea + 0.05:
		velocity.y = maxf(velocity.y, clampf(rising, -6.0, 6.0) + (sea - p.y) * 14.0)
		if active and Input.is_action_just_pressed("jump") and _ride_spd > 4.0:
			velocity.y = maxf(velocity.y, 4.4)
	if on_water and not _ski_wet and absf(_ride_spd) > 6.0:
		# Back down off a wave.
		Net.game.sea_fx.splash(p + fwd * 0.8, 0.7, fwd * _ride_spd)
		Sfx.play("splash", p, -4.0, 1.2)
		rig.dip = 0.08
	_ski_wet = on_water
	floor_snap_length = 0.0
	var before := absf(_ride_spd)
	_sea_edge(delta)
	move_and_slide()
	var after := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if before > 9.0 and after < before * 0.35 and afloat:
		# Into the side of something.
		_ride_spd = 0.0
		knock(-fwd * 4.0 + Vector3(0, 5.0, 0))
		Net.game.to_server("srv_crash", [], Net.game.motos)
		return
	_ride_spd = minf(_ride_spd, after + 2.0) if _ride_spd > 0.0 else _ride_spd


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
	var aiming := Controls.playing() and Input.is_action_pressed("aim") and can_act()
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
	velocity.y = JUMP * jump_mult() + maxf(_ramp_vy, 0.0)
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
	velocity.y = DOUBLE_JUMP * jump_mult()
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
		# Looking out of your own eyes there is no body in the way, but it still has a shadow.
		var seen: bool = st.dead or not rig.first_person() or _fly.length() > 0.5
		_vis.visible = st.get("hide", -1) < 0
		for k in _vis.get_child_count():
			var part: GeometryInstance3D = _vis.get_child(k)
			if k % 2 == 1:
				part.visible = seen
			else:
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if seen else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
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

	if delta > 0.0:
		_vel = _vel.lerp(moved / delta, minf(1.0, 14.0 * delta))
	var m: int = mv if is_local else net_mv & 7
	var side: float = _wall_side if is_local else (1.0 if net_mv & 8 else -1.0)
	var under := head_under()
	if m == MV_SWIM:
		side = 1.0 if under else -1.0
	_anim.wade = clampf(Layout.depth(global_position) / SWIM_IN, 0.0, 1.0) if m == MV_GROUND or m == MV_CROUCH else 0.0
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
	elif m == MV_DIVE or m == MV_SWIM:
		pose = Kit.DIVE
	elif m == MV_CROUCH:
		pose = Kit.CROUCH
	elif m == MV_AIR:
		pose = Kit.JUMP
	# Both hands are busy in the water: whatever was in them is tucked away.
	var held: int = DB.ITEMS[st.equipped].get("held", Kit.HELD_NONE) if m != MV_SWIM else Kit.HELD_NONE
	var aim: float = rig.rotation.x if is_local else net_pitch
	_anim.update(delta, m, CharRig.DEAD if st.dead else (CharRig.OUT if out else CharRig.ALIVE), _spd, _vy, _turn, aim, side, held, net_byte() & 16 != 0)
	_anim.apply(_mats)
	_water_fx(m, under, delta)

	# Wall runners tip over with their feet toward the wall; riders and runners bank into a turn.
	_bank = lerpf(_bank, clampf(_turn * _spd * 0.012, -0.35, 0.35), minf(1.0, 8.0 * delta))
	var roll := 0.0
	if st.dead or out:
		roll = 0.0
	elif m == MV_WALLRUN:
		roll = side * 0.4
	elif m == MV_RIDE:
		roll = ride_lean()
	elif m == MV_SWIM:
		roll = clampf(_turn * 0.06, -0.3, 0.3)
	elif m == MV_GROUND:
		roll = _bank * 0.5
	_vis.rotation.z = lerp_angle(_vis.rotation.z, roll, minf(1.0, 10.0 * delta))
	# Bomba shows: everyone can see who has been at the needle.
	var bulk := BULK if drug_phase("bomba") in ["high", "od"] else 1.0
	_vis.scale = _vis.scale.lerp(Vector3(bulk, 1.0 + (bulk - 1.0) * 0.4, bulk), minf(1.0, 3.0 * delta))
	# Anyone standing in a hole is that much shorter.
	var deep: float = Places.depth_at(global_position) if (_pit >= 0 or not is_local) and global_position.y < 0.6 else 0.0
	_sink = lerpf(_sink, deep, minf(1.0, 9.0 * delta))
	_vis.position.y = _anim.lift - _sink

	# Everything another player needs to know about you is worn on the body.
	var flags := clampi(st.heat, 0, 3) << Kit.HEAT_SHIFT
	if st.jail > 0.0 or st.get("fug", false):
		flags |= Kit.F_JAIL
	else:
		flags |= Kit.F_SHORTS
	if st.get("look", 0) != _look:
		_look = st.get("look", 0)
		for mm in [_body, _held]:
			mm.set_instance_color(0, Color.from_hsv(fmod((id + _look) * 0.137, 1.0), 0.75, 0.9, fmod(id * 0.618, 1.0)))
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


## The splashes this body makes: going in, coming up, each stroke, each step in the shallows.
## Every machine works these out for itself from what it can see the body doing.
func _water_fx(m: int, under: bool, delta: float) -> void:
	var fx = Net.game.sea_fx
	var p := global_position
	var fwd := -global_basis.z
	if m == MV_SWIM and _was_m != MV_SWIM:
		var big := clampf(_vel.length() / 9.0, 0.3, 1.4)
		fx.splash(p, big, _vel)
		Sfx.play("splash" if big > 0.5 else "plop", p, lerpf(-8.0, 3.0, minf(big, 1.0)))
		if under:
			fx.bubbles(p + Vector3(0, 0.3, 0), int(10 * big) + 4, _vel * 0.3)
	elif m != MV_SWIM and _was_m == MV_SWIM and not st.dead:
		fx.splash(p, 0.3)
		Sfx.play("plop", p, -6.0)
	if m == MV_SWIM and under != _was_under and _was_m == MV_SWIM:
		fx.splash(p + fwd * 0.3, 0.35 if under else 0.45, _vel)
		Sfx.play("plop", p, -4.0)
		if not under and air < DB.BREATH * 0.6 and is_local:
			Sfx.play("gasp", p + Vector3(0, 0.6, 0), -2.0)
	if m == MV_SWIM and not st.dead:
		if _anim.catch:
			if under:
				fx.bubbles(p + fwd * 0.5 + Vector3(0, 0.4, 0), 3, _vel * 0.2)
			else:
				# A hand going in ahead, and the wash off the shoulders when it is a sprint.
				var hand := p + fwd * 0.7 + global_basis.x * (0.25 if _step_i % 2 == 0 else -0.25)
				fx.splash(hand, 0.14 + minf(_spd, 4.5) * 0.03, _vel)
				if _spd > 3.0:
					fx.foam(p - fwd * 0.6, 1.3, 1.6)
				Sfx.play("plop", p, -15.0 + minf(_spd, 4.5) * 1.6, 1.3)
				_step_i += 1
		_bubble_t -= delta
		if under and _bubble_t <= 0.0:
			# Breath let out a little at a time.
			_bubble_t = randf_range(1.1, 2.0)
			fx.bubbles(p + fwd * 0.55 + Vector3(0, 0.45, 0), 4)
			Sfx.play("bubbles", p, -12.0)
	elif (m == MV_GROUND or m == MV_CROUCH) and _anim.wade > 0.1 and _spd > 1.0:
		var step := int(_anim.phase / PI)
		if step != _step_i:
			_step_i = step
			fx.splash(p + fwd * 0.3, 0.12 + 0.2 * _anim.wade, _vel)
			Sfx.play("plop", p, -14.0 + 6.0 * _anim.wade, 1.15)
	_was_m = m
	_was_under = under


## Plays a punch / recoil (attack) or a flinch on this player's body.
func fx_event(attack: bool) -> void:
	if st.dead:
		return
	_ev = Kit.now() if attack else -Kit.now()
	if is_local and not attack:
		rig.kick = 0.05


## How far back the arm is drawn to throw: 0 not at all, 1 as hard as it goes.
func wind_up() -> float:
	return clampf(_wind / THROW_WIND, 0.0, 1.0) if _wind >= 0.0 else 0.0


## Where this player's shots visibly leave from: the gun in first person, the hand otherwise.
func muzzle() -> Vector3:
	if is_local and rig.first_person():
		return rig.cam.global_transform * DB.ITEMS[st.equipped].get("muzzle", Vector3(0.24, -0.16, -0.95))
	var pitch: float = rig.rotation.x if is_local else net_pitch
	return global_position + Vector3(0, 1.0, 0) + global_basis * (Basis(Vector3.RIGHT, pitch) * Vector3(0.2, 0.0, -0.75))


## The gun bucks: the view jumps and only mostly comes back.
func recoil() -> void:
	var k: float = DB.ITEMS[st.equipped].get("recoil", 0.0) * recoil_mult()
	rig.recoil(k, randf_range(-0.4, 0.4) * k)
	_vm_t = Kit.now()


## A one-off bit of body language started by the host (Game.cl_anim).
func play(what: String, seconds: float) -> void:
	if what == "reload":
		_reload_t = Kit.now()
		_reload_len = seconds
		Sfx.play("reload", global_position + HEAD)


func _animate_viewmodel() -> void:
	_vm.visible = rig.first_person() and not st.dead and not scoped
	if mv == MV_SWIM:
		# Your own hands, pulling the water past.
		for held in _vm_guns:
			_vm_guns[held].visible = false
		var u := fposmod(_anim.stroke / TAU, 1.0)
		var pull := smoothstep(0.0, 0.35, u) * (1.0 - smoothstep(0.4, 0.6, u))
		var go := minf(_vel.length() / SWIM_SPEED, 1.0)
		_vm_r.rotation.x = 0.0
		_vm_r.position = Vector3(0.16 + 0.3 * pull * go, -0.3 - 0.12 * pull * go, -0.8 + 0.35 * pull * go)
		_vm_l.position = Vector3(-0.16 - 0.3 * pull * go, -0.3 - 0.12 * pull * go, -0.8 + 0.35 * pull * go)
		return
	var gun: bool = DB.is_gun(st.equipped)
	var long_gun: bool = DB.ITEMS[st.equipped].get("held", 0) >= Kit.HELD_SHOTGUN and gun
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
		if long_gun:
			# Both hands on it: the left out along the barrel.
			_vm_r.position = Vector3(0.2, -0.26, -0.55) + sway + Vector3(0.0, 0.02, 0.14) * e
			_vm_r.rotation.x = 0.16 * e
			_vm_l.position = Vector3(0.1, -0.2, -0.95) + sway + Vector3(0.0, 0.02, 0.14) * e
		# Reloading: the gun drops out of view and comes back up.
		var r := clampf((Kit.now() - _reload_t) / _reload_len, 0.0, 1.0)
		var dip := sin(r * PI)
		_vm_r.position += Vector3(0.0, -0.22, 0.05) * dip
		_vm_r.rotation.x += 0.7 * dip
		_vm_l.position += Vector3(0.12, 0.06, -0.1) * dip
	elif DB.kind_of(st.equipped) == "thrown":
		# Drawn back over the shoulder as it winds up, then over the top.
		var k := wind_up()
		_vm_r.position += Vector3(0.05, 0.22, 0.3) * k + Vector3(-0.15, 0.2, -0.5) * e
	elif DB.ITEMS[st.equipped].get("held", 0) == Kit.HELD_BAT:
		_vm_r.position += Vector3(-0.35, 0.05, -0.3) * e
		_vm_r.rotation.x = -0.9 * e
	elif _vm_side > 0.0:
		_vm_r.position += Vector3(-0.2, 0.14, -0.45) * e
	else:
		_vm_l.position += Vector3(0.2, 0.14, -0.45) * e


func _local_process(delta: float) -> void:
	var g = Net.game
	var captured := Controls.playing()
	var head := global_position + HEAD
	var dir := aim_dir()
	_animate_viewmodel()

	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.1
		g.crowd.refresh_near(global_position)
	target_npc = g.crowd.pick_near(head, dir, ROB_RANGE) if can_attack() and mv != MV_RIDE else -1
	snatch_npc = g.crowd.pick_snatch(global_position, -global_basis.z) if can_fight() and mv == MV_RIDE and _ride_spd > 6.0 else -1

	# Meth: sniper zoom while high. Whatever else is in the blood shakes or sways the view.
	var aiming := captured and Input.is_action_pressed("aim")
	var glass: float = DB.ITEMS[st.equipped].get("scope", 0.0)
	scoped = aiming and glass > 0.0 and can_attack() and mv != MV_RIDE
	rig.scoped = scoped
	rig.fov_target = (Settings.fov / glass if scoped else (20.0 if is_sniper() else Settings.fov * 0.73)) if aiming else Settings.fov
	rig.shake = _fx_sum("shake")
	# Ketamine past the limit: the view lifts out of the body lying on the floor.
	if drug_phase("ketamine") == "od":
		_fly = _fly.lerp(Vector3(0.0, 9.0, 0.0), minf(1.0, 0.25 * delta))
	rig.offset = global_basis.inverse() * _fly

	# Speed reads through the camera: wider view, a lean off the wall, a low head in a slide.
	rig.fov_boost = 0.0 if aiming else clampf((hspeed() - SPRINT) * 1.6, 0.0, 22.0)
	rig.height_target = ((DUCK_HEAD if mv == MV_CROUCH else CROUCH_HEAD) if _crouched else HEAD.y) - _sink
	if mv == MV_SWIM:
		rig.height_target = 0.5 if _swim_under else SWIM_EYE
	# Breath: spent with the head under, got back three times as fast in the air.
	air = maxf(0.0, air - delta) if head_under() else minf(DB.BREATH, air + delta * 3.0)
	match mv:
		MV_WALLRUN: rig.roll_target = _wall_side * 0.22
		MV_SLIDE: rig.roll_target = 0.05
		MV_RIDE: rig.roll_target = _ride_steer * 0.5
		MV_SWIM: rig.roll_target = clampf(-velocity.dot(global_basis.x) * 0.012, -0.08, 0.08)
		_: rig.roll_target = clampf(-velocity.dot(global_basis.x) * 0.004, -0.05, 0.05)
	rig.roll_target += sin(Kit.now() * 1.3) * _fx_sum("sway")
	if scoped:
		# Nobody holds a rifle perfectly still: the picture drifts, less so crouched.
		var drift := 0.0016 * (0.35 if _crouched else 1.0) * (1.0 + hspeed() * 0.6)
		rig.rotation.x = clampf(rig.rotation.x + sin(Kit.now() * 1.1) * drift * delta * 4.0, -1.45, 1.45)
		rotate_y(cos(Kit.now() * 0.8) * drift * delta * 4.0)

	_attack_t -= delta
	_rob_t -= delta
	robbing = false
	if captured and can_attack():
		var w: Dictionary = DB.ITEMS[st.equipped]
		var kind := DB.kind_of(st.equipped)
		# The point on the line of sight level with the head: where the blow starts from.
		var cam: Vector3 = rig.cam.global_position
		var from := cam + dir * maxf(0.0, (head - cam).dot(dir))
		if kind == "thrown":
			# Hold to draw the arm back, let go to throw: the longer, the further.
			if Input.is_action_pressed("attack") and _attack_t <= 0.0:
				_wind = maxf(_wind, 0.0) + delta
			elif _wind >= 0.0:
				g.to_server("srv_attack", [from, dir, wind_up()])
				_attack_t = w.cooldown
				_vm_t = Kit.now()
				_wind = -1.0
		else:
			_wind = -1.0
			# A fist or a machine gun goes on for as long as it is asked to; anything else
			# wants the trigger let go between shots.
			var pulled: bool = Input.is_action_pressed("attack") if (w.melee or w.get("auto", false)) else Input.is_action_just_pressed("attack")
			if (pulled or is_raging()) and _attack_t <= 0.0:
				_attack_t = w.cooldown
				g.to_server("srv_attack", [from, dir])
				if w.melee:
					_vm_t = Kit.now()
					_vm_side = -_vm_side
		if Input.is_action_just_pressed("reload"):
			g.to_server("srv_reload")
		if Input.is_action_just_pressed("rob") and snatch_npc >= 0:
			g.to_server("srv_snatch", [snatch_npc], g.crowd)
		if Input.is_action_pressed("rob") and target_npc >= 0:
			robbing = true
			if _rob_t <= 0.0:
				_rob_t = 0.1
				g.to_server("srv_rob", [target_npc, mic_level()], g.crowd)
		if Input.is_action_just_pressed("weapon_1"):
			g.to_server("srv_equip", [_next_weapon(DB.MELEE)])
		if Input.is_action_just_pressed("weapon_2"):
			g.to_server("srv_equip", [_next_weapon(DB.GUNS)])
		if Input.is_action_just_pressed("weapon_3"):
			g.to_server("srv_equip", [_next_weapon(DB.HEAVY)])
		if Input.is_action_just_pressed("weapon_4"):
			g.to_server("srv_equip", [_next_weapon(DB.THROWN)])
		var held := drugs_held()
		if not held.has(drug_sel):
			drug_sel = held[0] if not held.is_empty() else ""
		elif Input.is_action_just_pressed("drug_next") or Input.is_action_just_pressed("drug_prev"):
			var step := 1 if Input.is_action_just_pressed("drug_next") else -1
			drug_sel = held[posmod(held.find(drug_sel) + step, held.size())]
		if drug_sel != "" and Input.is_action_just_pressed("drug_use"):
			g.to_server("srv_use", [drug_sel])

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
