extends "res://scenes/world/world_kit.gd"
## The yacht lying off the beach, the party on it, and the men paid to keep everyone else off.
##
## It is at anchor and does not move: the decks are ordinary solid ground that happens to
## be out at sea, the guests and guards are ordinary members of the crowd who have been told
## to stay where they are, and the water round the hull is kept calm so none of it has to rock.
##
## From the stern forward: a ramp out of the water onto a low swim platform, the door to the
## cabin below (where the safe is), stairs up to the after deck where the dancing is, the
## saloon with the sun deck on its roof, and the foredeck.

const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")

const WHITE := Color(0.96, 0.96, 0.95)
const NAVY := Color(0.07, 0.1, 0.2)
const TEAK := Color(0.72, 0.52, 0.33)
const GLASS := Color(0.07, 0.11, 0.17)
const CHROME := Color(0.78, 0.8, 0.83)
## Heights of the decks above still water's zero.
const LOW_Y := 0.3
const MAIN_Y := 2.9
const SUN_Y := 5.5
## Along the hull from the middle (bow is +x): the stern end of the swim platform, the
## bulkhead between it and the cabin, the two ends of the saloon, and the bow.
const X_PLAT := -23.0
const X_WALL := -14.0
const X_SAL0 := -4.0
const X_SAL1 := 11.0
const X_BOW := 21.0
const BEAM := 4.4

## How close a stranger gets before the guards take an interest, how close for how long
## before they stop asking, and how far their guns carry.
const WARN_R := 32.0
const CLOSE_R := 10.0
const CLOSE_TIME := 4.0
const GUN_REACH := 48.0
const FORGET_R := 85.0
const RADIO_AFTER := 12.0
const SAFE_TAKE := 9000

## The middle of the hull at the waterline.
var at: Vector3 = Layout.YACHT_POS
## Crowd indices, once the crowd has been set out: the guards, and everybody aboard.
var guards: PackedInt32Array = []
var aboard: PackedInt32Array = []

var _tick_t := 0.0
var _seed := -1
var _warned := {}     # pid -> true while they are inside the warning ring
var _close := {}      # pid -> seconds spent right alongside
var _alarm := {}      # pid -> match time the guards went for them
var _radioed := {}
var _safe_done := false
var _safe_at := Vector3.ZERO


func _ready() -> void:
	_init_kit()
	_hull()
	_decks()
	_fittings()
	_people()
	_flush()
	for m in get_parent().world.sea_mats:
		m.set_shader_parameter("hull", Vector4(at.x + (X_WALL + X_BOW) * 0.5, at.z, (X_BOW - X_WALL) * 0.5 - 0.3, BEAM - 0.3))
	if multiplayer.is_server():
		Net.game.crowd.npc_hit.connect(_on_npc_hit)
		Net.game.crowd.npc_died.connect(_on_npc_died)
		Crime.noise.connect(_on_noise)


func _w(x: float, y: float, z: float) -> Vector3:
	return at + Vector3(x, y, z)


func _hull() -> void:
	var len_main := X_BOW - X_WALL
	var mid := (X_BOW + X_WALL) * 0.5
	# Bottom, and the two sides up to the main deck, with a dark boot stripe at the waterline.
	_block(_w(mid - 2.0, -1.9, 0), Vector3(len_main + 5.0, 0.4, BEAM * 2.0), NAVY)
	for side in [-1.0, 1.0]:
		_block(_w(mid, 0.55, side * (BEAM - 0.15)), Vector3(len_main, 5.0, 0.3), WHITE)
		_box(_w(mid, -0.3, side * (BEAM + 0.01)), Vector3(len_main, 0.5, 0.05), NAVY)
		# The bow comes to a point.
		_block(_w(X_BOW + 2.9, 0.55, side * (BEAM * 0.5 - 0.1)), Vector3(7.4, 5.0, 0.3), WHITE, Vector3(0, side * 0.64, 0))
		_box(_w(X_BOW + 2.9, -0.3, side * (BEAM * 0.5 - 0.05)), Vector3(7.5, 0.5, 0.34), NAVY, Vector3(0, side * 0.64, 0))
		# Portholes along the cabin.
		for k in 6:
			_box(_w(X_WALL + 2.5 + k * 3.4, 1.7, side * (BEAM + 0.01)), Vector3(1.2, 0.5, 0.05), GLASS)
		# Low sides round the swim platform.
		_block(_w((X_PLAT + X_WALL) * 0.5, 0.0, side * (BEAM - 0.15)), Vector3(X_WALL - X_PLAT, 1.6, 0.3), WHITE)
	_block(_w(X_BOW + 1.2, MAIN_Y - 0.1, 0), Vector3(5.5, 0.25, 4.6), TEAK)
	# The bulkhead between platform and cabin, with the door in the middle of it.
	for side in [-1.0, 1.0]:
		_block(_w(X_WALL, 1.46, side * 2.6), Vector3(0.3, 2.62, 3.6), WHITE)
	_block(_w(X_WALL, 2.55, 0), Vector3(0.3, 0.44, 1.7), WHITE)
	_box(_w(X_WALL - 0.16, 2.5, 0), Vector3(0.05, 0.25, 1.5), Color(1.0, 0.85, 0.5))
	_sign("DOLCE VIDA", _w(X_PLAT - 0.2, 0.75, 0), 150, NAVY, -PI / 2.0)
	_box(_w(X_PLAT - 0.05, 0.0, 0), Vector3(0.12, 1.5, BEAM * 2.0 - 0.6), WHITE)
	_collider(_w(X_PLAT + 0.15, -1.0, 0), Vector3(0.3, 2.2, BEAM * 2.0 - 0.6))


func _decks() -> void:
	# The swim platform, and the ramp that runs down off the back of it into the water: the
	# way aboard for anyone who arrives wet.
	_block(_w((X_PLAT + X_WALL) * 0.5, LOW_Y - 0.15, 0), Vector3(X_WALL - X_PLAT, 0.3, BEAM * 2.0 - 0.3), TEAK)
	var run := Vector2(5.0, LOW_Y + 2.0)
	_block(_w(X_PLAT - 2.5, LOW_Y - 1.0 - 0.14, 0), Vector3(run.length(), 0.3, 5.0), TEAK, Vector3(0, 0, atan2(run.y, run.x)))
	# The cabin floor, and the main deck over it.
	_block(_w((X_WALL + 17.0) * 0.5, LOW_Y - 0.15, 0), Vector3(17.0 - X_WALL, 0.3, BEAM * 2.0 - 0.3), Color(0.5, 0.36, 0.26))
	_block(_w((X_WALL + X_BOW) * 0.5, MAIN_Y - 0.13, 0), Vector3(X_BOW - X_WALL, 0.26, BEAM * 2.0), TEAK)
	# Stairs: platform to the after deck up the port side, after deck to the sun deck to starboard.
	_stairs(_w(-20.0, LOW_Y, 3.3), _w(X_WALL + 0.02, MAIN_Y + 0.02, 3.3), 1.5)
	_stairs(_w(-9.2, MAIN_Y, -3.3), _w(X_SAL0 + 0.02, SUN_Y + 0.02, -3.3), 1.5)
	# The saloon, glass down both sides, and the sun deck on top of it.
	_block(_w((X_SAL0 + X_SAL1) * 0.5, (MAIN_Y + SUN_Y) * 0.5, 0), Vector3(X_SAL1 - X_SAL0, SUN_Y - MAIN_Y - 0.26, 5.8), WHITE)
	for side in [-1.0, 1.0]:
		_box(_w((X_SAL0 + X_SAL1) * 0.5, MAIN_Y + 1.45, side * 2.92), Vector3(X_SAL1 - X_SAL0 - 1.2, 1.3, 0.05), GLASS)
	_box(_w(X_SAL0 - 0.02, MAIN_Y + 1.3, 0), Vector3(0.05, 1.9, 4.2), GLASS)
	_box(_w(X_SAL1 + 0.02, MAIN_Y + 1.5, 0), Vector3(0.05, 1.4, 4.8), GLASS)
	_block(_w((X_SAL0 + X_SAL1) * 0.5, SUN_Y - 0.13, 0), Vector3(X_SAL1 - X_SAL0, 0.26, BEAM * 2.0 - 0.6), TEAK)
	# It overhangs the after deck, except where the stairs come up through it.
	_block(_w(X_SAL0 - 1.0, SUN_Y - 0.13, 0.85), Vector3(2.0, 0.26, BEAM * 2.0 - 2.3), TEAK)
	# Rails: low enough to vault, high enough to stop a stroll over the side.
	for side in [-1.0, 1.0]:
		_rail(_w(X_WALL + 1.7 if side > 0.0 else X_WALL, MAIN_Y, side * (BEAM - 0.1)), _w(X_BOW, MAIN_Y, side * (BEAM - 0.1)))
		_rail(_w(X_SAL0 - 2.0 if side > 0.0 else X_SAL0 + 0.2, SUN_Y, side * (BEAM - 0.4)), _w(X_SAL1 + 1.0, SUN_Y, side * (BEAM - 0.4)))
	_rail(_w(X_WALL, MAIN_Y, -BEAM + 0.1), _w(X_WALL, MAIN_Y, 2.4))
	_rail(_w(X_SAL1 + 1.0, SUN_Y, -BEAM + 0.4), _w(X_SAL1 + 1.0, SUN_Y, BEAM - 0.4))
	_rail(_w(X_SAL0 - 2.0, SUN_Y, -2.4), _w(X_SAL0 - 2.0, SUN_Y, BEAM - 0.4))


## A flight of steps from a to b, `wide` across: a ramp to walk on, with treads drawn on it.
func _stairs(a: Vector3, b: Vector3, wide: float) -> void:
	var run := Vector2(b.x - a.x, b.y - a.y)
	var mid := (a + b) * 0.5
	_collider(mid - Vector3(-run.y, run.x, 0).normalized() * 0.12, Vector3(run.length() + 0.3, 0.24, wide), Vector3(0, 0, atan2(run.y, run.x)))
	var n := int(run.y / 0.26)
	for k in n:
		var u := (k + 0.5) / n
		_box(Vector3(lerpf(a.x, b.x, u), lerpf(a.y, b.y, u) - 0.02, a.z), Vector3(run.x / n + 0.04, 0.26, wide), TEAK.darkened(0.12 if k % 2 == 0 else 0.0))


func _rail(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var along := absf(b.x - a.x) > absf(b.z - a.z)
	var size := Vector3(a.distance_to(b), 0.9, 0.08) if along else Vector3(0.08, 0.9, a.distance_to(b))
	_collider(mid + Vector3(0, 0.45, 0), size)
	_box(mid + Vector3(0, 0.9, 0), Vector3(size.x, 0.06, size.z), CHROME)
	_box(mid + Vector3(0, 0.45, 0), Vector3(size.x, 0.6, size.z * 0.3), Color(0.75, 0.85, 0.9))


func _fittings() -> void:
	# After deck: the DJ against the saloon, speakers either side, a bar to port.
	_block(_w(X_SAL0 - 0.9, MAIN_Y + 0.5, 0), Vector3(0.8, 1.0, 2.4), NAVY)
	_glow(_w(X_SAL0 - 1.32, MAIN_Y + 0.55, 0), Vector3(0.04, 0.5, 2.0), Color(1.0, 0.2, 0.7))
	for side in [-1.0, 1.0]:
		_block(_w(X_SAL0 - 0.7, MAIN_Y + 0.8, side * 2.1), Vector3(0.7, 1.6, 0.8), Color(0.08, 0.08, 0.09))
		_box(_w(X_SAL0 - 1.06, MAIN_Y + 1.1, side * 2.1), Vector3(0.04, 0.55, 0.55), Color(0.25, 0.25, 0.28))
	_block(_w(-11.0, MAIN_Y + 0.55, 3.2), Vector3(3.2, 1.1, 0.7), Color(0.3, 0.2, 0.14))
	_box(_w(-11.0, MAIN_Y + 1.13, 3.2), Vector3(3.4, 0.06, 0.9), WHITE)
	for k in 6:
		_box(_w(-12.2 + k * 0.48, MAIN_Y + 1.32, 3.35), Vector3(0.09, 0.32, 0.09), [Color(0.1, 0.5, 0.2), Color(0.7, 0.5, 0.1), Color(0.8, 0.85, 0.9)][k % 3])
	var music := Sfx.emitter("funk", 3.0, 9.0, 150.0)
	music.position = _w(X_SAL0 - 1.0, MAIN_Y + 1.5, 0)
	add_child(music)
	# Party lights over the dancing, and bulbs strung from the mast down to the stern.
	for k in 3:
		var l := OmniLight3D.new()
		l.position = _w(-12.0 + k * 3.2, MAIN_Y + 2.6, [-2.0, 2.0, -1.0][k])
		l.light_color = [Color(1.0, 0.2, 0.7), Color(0.2, 0.7, 1.0), Color(1.0, 0.8, 0.2)][k]
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.shadow_enabled = false
		add_child(l)
	var mast := _w(3.0, SUN_Y + 4.2, 0)
	_block(_w(3.0, SUN_Y + 2.1, 0), Vector3(0.3, 4.2, 0.3), WHITE)
	_box(_w(3.0, SUN_Y + 3.4, 0), Vector3(0.4, 0.12, 2.6), WHITE)
	_box(_w(2.6, SUN_Y + 3.7, 0), Vector3(1.4, 0.25, 0.5), WHITE, Vector3(0, 0, 0.2))
	for run in [[mast, _w(X_PLAT + 0.5, 2.2, 0)], [mast, _w(X_BOW + 3.0, MAIN_Y + 1.0, 0)]]:
		for k in 22:
			var u := (k + 0.5) / 22.0
			var p: Vector3 = run[0].lerp(run[1], u) - Vector3(0, sin(u * PI) * 1.4, 0)
			_glow(p, Vector3(0.14, 0.14, 0.14), [Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.5), Color(0.5, 0.9, 1.0)][k % 3])
	# Sun deck: a hot tub aft, loungers forward of it.
	_block(_w(-1.0, SUN_Y + 0.35, 0), Vector3(3.4, 0.7, 3.4), WHITE)
	_glow(_w(-1.0, SUN_Y + 0.66, 0), Vector3(2.8, 0.1, 2.8), Color(0.35, 0.85, 0.95))
	for k in 3:
		_lounger(_w(5.0 + k * 0.1, SUN_Y, -2.6 + k * 2.6), 0.0)
	# Foredeck: more of them, pointing at the view.
	for k in 4:
		_lounger(_w(14.0, MAIN_Y, -3.0 + k * 2.0), 0.0)
	# Swim platform: a couple of chairs and a rack of towels.
	_box(_w(-17.0, LOW_Y + 0.5, -3.3), Vector3(1.6, 1.0, 0.5), WHITE)
	# The cabin: dim, wood, a bed forward and the safe against the bulkhead beyond it.
	for k in 4:
		_glow(_w(X_WALL + 3.0 + k * 5.5, MAIN_Y - 0.3, 0), Vector3(1.2, 0.05, 0.3), Color(1.0, 0.86, 0.6))
		var l := OmniLight3D.new()
		l.position = _w(X_WALL + 3.0 + k * 5.5, MAIN_Y - 0.8, 0)
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 1.1
		l.omni_range = 6.5
		l.shadow_enabled = false
		add_child(l)
	_block(_w(-8.0, LOW_Y + 0.4, -3.2), Vector3(4.0, 0.8, 1.2), Color(0.85, 0.83, 0.78))
	_block(_w(-8.0, LOW_Y + 0.4, 3.2), Vector3(4.0, 0.8, 1.2), Color(0.85, 0.83, 0.78))
	_block(_w(2.0, LOW_Y + 0.35, 0), Vector3(2.6, 0.7, 3.0), Color(0.9, 0.9, 0.95))
	_block(_w(8.6, LOW_Y + 1.35, 0), Vector3(0.4, 2.7, BEAM * 2.0 - 0.6), Color(0.4, 0.28, 0.2))
	_safe_at = _w(7.6, LOW_Y, 2.6)
	_block(_safe_at + Vector3(0.4, 0.6, 0), Vector3(0.8, 1.2, 0.9), Color(0.2, 0.22, 0.24))
	_box(_safe_at + Vector3(-0.02, 0.65, 0), Vector3(0.05, 0.3, 0.3), CHROME)
	_glow(_safe_at + Vector3(-0.02, 1.05, 0.25), Vector3(0.05, 0.08, 0.08), Color(1.0, 0.15, 0.1))
	Places.add_use(&"yacht_safe", _safe_at + Vector3(-0.7, 0, 0), "crack the safe", 0, 8.0)


func _lounger(p: Vector3, yaw: float) -> void:
	_box(p + Vector3(0, 0.22, 0), Vector3(1.9, 0.12, 0.7), WHITE, Vector3(0, yaw, 0))
	_box(p + Vector3(-0.75, 0.42, 0), Vector3(0.6, 0.1, 0.7), WHITE, Vector3(0, yaw, -0.6))


## Who is aboard. Mostly girls in not very much; three men who paid for all of it; and the
## eight who make sure nobody else comes to the party.
func _people() -> void:
	var stay := {"stay": true, "afloat": true}
	var girl := "socialite"
	var party := [Kit.DANCE, Kit.DANCE, Kit.DANCE, Kit.CHEER, Kit.LAUGH]
	# Dancing on the after deck, facing the DJ more or less.
	var floor_spots := [Vector2(-12.4, -2.4), Vector2(-11.2, -0.6), Vector2(-12.6, 0.9), Vector2(-10.0, -2.9), Vector2(-9.6, 0.4), Vector2(-8.2, -1.4), Vector2(-7.4, 1.6), Vector2(-6.6, -0.2), Vector2(-10.6, 1.9)]
	for k in floor_spots.size():
		Places.add_spot(_w(floor_spots[k].x, MAIN_Y, floor_spots[k].y), -PI / 2.0 + sin(k * 2.3) * 0.7, party, girl, -1, stay)
	Places.add_spot(_w(X_SAL0 - 1.9, MAIN_Y, 0), PI / 2.0, [Kit.CHEER, Kit.DANCE, Kit.WORK], "local", -1, stay)
	# At the bar: one of the owners holding court.
	Places.add_spot(_w(-11.6, MAIN_Y, 2.2), PI, [Kit.DRINK, Kit.TALK, Kit.LAUGH], "magnata", -1, stay)
	Places.add_spot(_w(-10.5, MAIN_Y, 2.3), PI, [Kit.DRINK, Kit.LAUGH, Kit.TALK], girl, -1, stay)
	Places.add_spot(_w(-12.5, MAIN_Y, 2.3), PI * 0.8, [Kit.LAUGH, Kit.DRINK, Kit.SELFIE], girl, -1, stay)
	# Sun deck: the other two on loungers with company, and the hot tub.
	Places.add_spot(_w(5.0, SUN_Y + 0.3, -2.6), PI / 2.0, [Kit.SUNBATHE], "magnata", -1, stay)
	Places.add_spot(_w(5.2, SUN_Y + 0.3, 2.6), PI / 2.0, [Kit.SUNBATHE], "magnata", -1, stay)
	Places.add_spot(_w(5.1, SUN_Y + 0.3, 0.0), PI / 2.0, [Kit.SUNBATHE], girl, -1, stay)
	Places.add_spot(_w(6.8, SUN_Y, -1.4), 2.4, [Kit.DRINK, Kit.TALK, Kit.LAUGH], girl, -1, stay)
	Places.add_spot(_w(6.9, SUN_Y, 1.5), 0.9, [Kit.SELFIE, Kit.TALK, Kit.DRINK], girl, -1, stay)
	Places.add_spot(_w(8.6, SUN_Y, 0.2), PI / 2.0, [Kit.DANCE, Kit.CHEER, Kit.PHOTO], girl, -1, stay)
	Places.add_spot(_w(-1.0, SUN_Y + 0.3, -2.2), PI, [Kit.LEAN, Kit.DRINK, Kit.LAUGH], girl, -1, stay)
	Places.add_spot(_w(-1.0, SUN_Y + 0.3, 2.2), 0.0, [Kit.DRINK, Kit.TALK, Kit.LAUGH], girl, -1, stay)
	# Foredeck: sunbathing, and somebody taking pictures of it.
	for k in 4:
		Places.add_spot(_w(14.0, MAIN_Y + 0.3, -3.0 + k * 2.0), PI / 2.0, [Kit.SUNBATHE], girl, -1, stay)
	Places.add_spot(_w(17.2, MAIN_Y, 0.4), PI / 2.0, [Kit.PHOTO, Kit.SELFIE, Kit.LAUGH], girl, -1, stay)
	# Down on the swim platform, feet nearly in the water.
	Places.add_spot(_w(-17.0, LOW_Y, -2.4), PI / 2.0, [Kit.DRINK, Kit.TALK, Kit.LAUGH], girl, -1, stay)
	Places.add_spot(_w(-18.2, LOW_Y, -1.6), -PI / 2.0, [Kit.TALK, Kit.LAUGH, Kit.DRINK], girl, -1, stay)

	# The guards: two on the platform where people come aboard, one at the head of each
	# flight of stairs, two up top with rifles and a view of everything, one on the cabin
	# door and one sitting on the safe.
	var watch := [Kit.STAND, Kit.LOOK, Kit.STAND]
	for e in [
		[Vector3(-21.6, LOW_Y, -2.0), PI / 2.0, Kit.HELD_PISTOL], [Vector3(-21.2, LOW_Y, 1.4), PI / 2.0, Kit.HELD_SMG],
		[Vector3(X_WALL + 1.0, MAIN_Y, 1.6), PI / 2.0, Kit.HELD_SMG], [Vector3(-5.6, MAIN_Y, -3.4), PI, Kit.HELD_PISTOL],
		[Vector3(X_SAL0 - 1.2, SUN_Y, 3.0), PI / 2.0, Kit.HELD_RIFLE], [Vector3(10.4, SUN_Y, -3.0), -PI / 2.0, Kit.HELD_RIFLE],
		[Vector3(X_WALL + 1.6, LOW_Y, -1.8), PI / 2.0, Kit.HELD_PISTOL], [Vector3(6.4, LOW_Y, -1.0), PI / 2.0, Kit.HELD_SMG],
	]:
		Places.add_spot(at + e[0], e[1], watch, "seguranca", -1, {"stay": true, "afloat": true, "gun": e[2]})


# --- host: the guards ---

## How far p is from the hull (platform and boarding ramp included), in the flat.
func reach(p: Vector3) -> float:
	var mid := (X_PLAT - 4.0 + X_BOW + 5.0) * 0.5
	var half := (X_BOW + 5.0 - (X_PLAT - 4.0)) * 0.5
	return Vector2(maxf(absf(p.x - at.x - mid) - half, 0.0), maxf(absf(p.z - at.z) - BEAM, 0.0)).length()


## Is p standing on some part of the boat?
func on_board(p: Vector3) -> bool:
	return reach(p) <= 0.0 and p.x - at.x > X_PLAT - 0.5 and p.y > LOW_Y - 0.25


func reset() -> void:
	_warned.clear()
	_close.clear()
	_alarm.clear()
	_radioed.clear()
	_safe_done = false
	guards = PackedInt32Array()
	aboard = PackedInt32Array()
	_seed = -1


## Finds the yacht's people among the crowd, once it has been set out for this match.
func _muster() -> void:
	var crowd = Net.game.crowd
	_seed = MatchState.seed_value
	guards = PackedInt32Array()
	aboard = PackedInt32Array()
	var guard: int = crowd._arch_index("seguranca")
	for i in crowd.count:
		if crowd._afloat[i] == 1 and reach(crowd.pos[i]) < 2.0:
			aboard.append(i)
			if crowd.arch[i] == guard:
				guards.append(i)


func _process(delta: float) -> void:
	if not multiplayer.is_server() or not MatchState.running or MatchState.ended:
		return
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = 0.2
	var g = Net.game
	if g.crowd.count == 0:
		return
	if _seed != MatchState.seed_value or aboard.is_empty():
		_muster()
	for pid in g.players:
		var pl = g.players[pid]
		var p: Vector3 = pl.global_position
		var d := reach(p)
		if not pl.at_large() or d > FORGET_R:
			_warned.erase(pid)
			_close.erase(pid)
			_alarm.erase(pid)
			_radioed.erase(pid)
			continue
		if _alarm.has(pid):
			if not _radioed.has(pid) and MatchState.time > _alarm[pid] + RADIO_AFTER:
				# Rich men have the police on the radio.
				_radioed[pid] = true
				Crime.report_tip(p, pid, 3)
				pl.st.heat = maxi(pl.st.heat, 2)
				g.push_state(pl)
				g.send(pid, "cl_toast", ["The yacht has radioed the police"])
			# Anyone who lost sight of them for a while picks them up again.
			for i in guards:
				if g.crowd.state[i] == g.crowd.AMBIENT:
					g.crowd.srv_guard(i, pid, GUN_REACH)
			continue
		if on_board(p):
			_srv_alarm(pid, "Trespasser aboard: the guards open fire!")
			continue
		if d < CLOSE_R:
			_close[pid] = _close.get(pid, 0.0) + 0.2
			if _close[pid] > CLOSE_TIME:
				_srv_alarm(pid, "You were told. The guards open fire!")
				continue
		else:
			_close.erase(pid)
		if d < WARN_R and not _warned.has(pid):
			_warned[pid] = true
			g.send(pid, "cl_toast", ["PRIVATE YACHT.  Armed guards: come any closer and they shoot"])
			g.bcast("cl_sound", ["whistle", _w(X_PLAT, 2.0, 0)])
			for i in guards:
				if g.crowd.state[i] == g.crowd.AMBIENT:
					g.bcast("cl_gawk", [i, p, Kit.AIM_LONG if g.crowd._gun[i] >= Kit.HELD_SHOTGUN else Kit.AIM, true], g.crowd)
		elif d > WARN_R + 8.0 and _warned.has(pid):
			_warned.erase(pid)


## Every guard still standing goes for `pid`, and the party stops.
func _srv_alarm(pid: int, why: String) -> void:
	if _alarm.has(pid):
		return
	var g = Net.game
	_alarm[pid] = MatchState.time
	g.send(pid, "cl_toast", [why])
	g.crowd.srv_panic(_w(-8.0, MAIN_Y, 0), 45.0, g.crowd.FRIGHT_SHOTS, pid, false)
	for i in guards:
		g.crowd.srv_guard(i, pid, GUN_REACH)


func _on_npc_hit(i: int, attacker: int) -> void:
	if attacker > 0 and aboard.has(i):
		_srv_alarm(attacker, "You have started something. The guards open fire!")


## A dead guard leaves what he was carrying on the deck.
func _on_npc_died(i: int, _attacker: int) -> void:
	if not guards.has(i):
		return
	var crowd = Net.game.crowd
	var held: int = crowd._gun[i]
	var item := "fuzil" if held == Kit.HELD_RIFLE else ("smg" if held == Kit.HELD_SMG else "pistol")
	Net.game.srv_add_drop(crowd.pos[i] + Vector3(0.5, 0.2, 0.4), 0, {item: 1, "ammo": 24})


## Shooting anywhere near the boat counts as shooting at it.
func _on_noise(pos: Vector3, radius: float, pid: int) -> void:
	if pid > 0 and radius >= 50.0 and reach(pos) < 45.0 and Net.game.players.has(pid) and Net.game.players[pid].at_large():
		_srv_alarm(pid, "The guards heard that. They open fire!")


## Called by the interact system once a player has worked at the safe long enough.
func srv_safe(p, _act: Dictionary, _arg: int) -> void:
	var g = Net.game
	if _safe_done:
		g.send(p.id, "cl_toast", ["The safe is empty - somebody got here first"])
		return
	_safe_done = true
	p.st.money += SAFE_TAKE
	p.st.heat = maxi(p.st.heat, 2)
	g.push_state(p)
	g.send(p.id, "cl_toast", ["The yacht's safe: R$%d in cash.  Now get off the boat." % SAFE_TAKE])
	g.bcast("cl_sound", ["cash", p.global_position])
	Crime.report_noise(p.global_position, 60.0, p.id)
	Crime.report_crime(p.global_position, p.id, 2)
	_srv_alarm(p.id, "The safe alarm is ringing!")
