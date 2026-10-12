extends "res://scenes/world/world_kit.gd"
## Traffic on the avenida. Every vehicle's position is a function of the match clock and
## the match seed, so all players see the same cars in the same place without a byte sent.
## The whole road stops together for a few seconds in every cycle, which is when to cross.
##
## Nothing here steers or looks where it is going. The two lanes of a direction share one
## moving frame, each vehicle owns a stretch of that frame nobody else may enter, and all
## the misbehaviour (surging, weaving, changing lane, stalling, pulling in at a bus stop,
## driving drunk) is a closed-form offset that stays inside the owner's stretch. Motoboys
## ride the lane divider of the city-side pair in a faster frame of their own, and cars
## there only change lane at moments when no bike is alongside.

const LOOP := 1100.0
const CYCLE := 40.0
const GO := 28.0
const BRAKE := 2.0
const HALT := 8.0
## Both lanes of a direction cruise at this, so neighbours never drift into each other.
const PAIR_SPEED := 12.5
## Motoboys go this much faster than the cars they filter past.
const MOTO_PACE := 1.5
## Road time for a motoboy to lap the cars. Lane-change plans repeat on it, which is what
## lets one pass over the plan at setup vouch for the whole match.
const SUPER := LOOP / (PAIR_SPEED * (MOTO_PACE - 1.0))
## The same vehicles are built every match; the seed only decides who does what and where.
const FLEET_SEED := 5150
## Clear road kept at each end of a vehicle's stretch, beyond everything it can do.
const PAD := 1.2
## Two lanes whose queues end within this of each other count as level.
const LEVEL := 4.0
## How far the outer faces of a vehicle may stray in each lane. The gap in the city-side
## pair is the motoboys' corridor.
const LANE_EDGES := [Vector2(52.9, 55.9), Vector2(56.1, 59.4), Vector2(62.6, 65.5), Vector2(66.5, 69.3)]
const DIVIDER_Z := 66.0
const MOTO_SWAY := 0.08

## Seconds of road time a lane change takes. Short enough to look like a decision, long
## enough that the nose never swings past about 12 degrees.
const CHANGE_TIME := 2.5
const CHANGE_TRIES := 8
## The most a lane changer's speed may wander (m/s) and its line may weave (m). Both add
## to the swing of the nose in mid-change, so changers get less of each than the rest.
const CHANGER_SURGE := 1.0
const CHANGER_SWAY := 0.2
## Role counts per direction. Every one of these costs road, so they are budgets.
const CHANGERS := 16
## Fewer on the city side, where the buses already do the stopping.
const STALLERS := [7, 3]
const BENDERS := 1
const DRUNKS := 2

## A stall, in road seconds: brake to nothing, sit, pull away, then run at CATCH_UP times
## the cruise until the lost ground is made up and ease back.
const STALL_BRAKE := 1.0
const STALL_PULL := 2.0
const STALL_EASE := 1.0
const CATCH_UP := 1.3
const STALL_CHANCE := 0.8
const STALL_HOLD_MIN := 2.0
## A stalled car gets a second horn once it has cost the one behind this long.
const HONK_AGAIN := 2.2
## Shelters on the city-side kerb, as built by the city.
const BUS_STOPS := [-180.0, -90.0, 0.0, 90.0, 180.0]
## Which shelters a bus serves on one lap, as bits. Never two neighbours: it needs the
## road between stops to make up the time before braking again.
const BUS_PATTERNS := [0b01001, 0b10010, 0b10001, 0b00100, 0b00001, 0b00010, 0b01000, 0b10000, 0]
const BUS_HOLD := 2.5
## Road seconds either side of a stop over which a bus drifts to the kerb and back.
const BUS_SWAY := 3.0
## Road seconds after passing a shelter by which a bus that stopped there is back on time.
const BUS_CLEAR := 21.0
## A fender-bender: the car that cut in stops dead and the one behind stops this much later.
const BEND_HOLD := 3.0
const BEND_AFTER := 0.3
const BEND_DELAY := 0.25
const BEND_GAP := 4.2

## Beyond this nobody can be standing, so a vehicle only needs moving now and then.
const FAR_X := 340.0
const HEAR_X := 110.0
## Slower than this a vehicle nudges; it does not run anyone down.
const RUN_DOWN_SPEED := 2.5
const VEL_STEP := 0.05

enum { CAR, TAXI, BUS, KOMBI, MOTO, TRUCK, COP }
enum { PLAIN, STALLER, BUS_STOPPER, CHANGER, FOLLOWER, DRUNK }

## Paint for body panels: vertex alpha 0 means "use this vehicle's paint".
const P := Color(1, 1, 1, 0)
const GLASS := Color(0.08, 0.11, 0.15)
const TYRE := Color(0.05, 0.05, 0.06)
const LAMP := Color(1.0, 0.95, 0.8, 2.0)
const TAIL := Color(0.9, 0.08, 0.05, 2.0)

## One entry per vehicle: {body, kind, lane (home lane), half (half size), damage}.
var vehicles: Array = []

var _kinds: Array = []  # [mesh, size, damage, how many, paints]
var _mat_v: ShaderMaterial
var _hit_cd := 0.0
var _seed := 0
var _tick := 0
## Seconds the vehicle last asked about is behind its schedule; a by-product of _track.
var _lag := 0.0
var _bodies: Array[AnimatableBody3D] = []

# Per-vehicle parameters, all rewritten by setup(). Packed because every one of them is
# read for every vehicle on every physics tick.
var _mode := PackedInt32Array()
var _dir := PackedFloat32Array()
var _pace := PackedFloat32Array()
var _c := PackedFloat32Array()      # centre of its stretch, along the frame
var _back := PackedFloat32Array()   # how far the stretch reaches behind the centre
var _front := PackedFloat32Array()
var _wa := PackedFloat32Array()     # surge: metres, rad/s, phase
var _ww := PackedFloat32Array()
var _wp := PackedFloat32Array()
var _z0 := PackedFloat32Array()     # weave: centre line, metres, rad/s, phase
var _zb := PackedFloat32Array()
var _zk := PackedFloat32Array()
var _zp := PackedFloat32Array()
var _pa := PackedFloat32Array()     # three more whose meaning depends on the mode
var _pb := PackedFloat32Array()
var _pc := PackedFloat32Array()
var _plans: Array[PackedFloat32Array] = []  # lane changers: road times, repeating on SUPER
var _behind := PackedInt32Array()   # who gets to sound the horn
var _stage := PackedByteArray()
var _far := PackedByteArray()


## Road time: runs with the clock while traffic flows and stands still while it is stopped.
static func warp(t: float) -> float:
	var u := fposmod(t, CYCLE)
	var g := u
	if u > GO + BRAKE + HALT:
		g = GO + BRAKE * 0.5 + pow(u - GO - BRAKE - HALT, 2.0) / (2.0 * BRAKE)
	elif u > GO + BRAKE:
		g = GO + BRAKE * 0.5
	elif u > GO:
		g = u - pow(u - GO, 2.0) / (2.0 * BRAKE)
	return floorf(t / CYCLE) * (GO + BRAKE) + g


## How fast traffic is moving right now, 0 (stopped) to 1.
static func flow(t: float) -> float:
	var u := fposmod(t, CYCLE)
	if u > GO + BRAKE + HALT:
		return (u - GO - BRAKE - HALT) / BRAKE
	if u > GO + BRAKE:
		return 0.0
	if u > GO:
		return 1.0 - (u - GO) / BRAKE
	return 1.0


func _ready() -> void:
	_mat_v = ShaderMaterial.new()
	_mat_v.shader = load("res://shaders/vehicle.gdshader")
	_build_kinds()
	var rng := RandomNumberGenerator.new()
	rng.seed = FLEET_SEED
	for k in _kinds.size():
		var paints: Array = _kinds[k][4]
		for n in int(_kinds[k][3]):
			_spawn(k, paints[rng.randi() % paints.size()])
	# One kombi is somebody's sound system and one truck sells gas to a jingle.
	_loud(KOMBI, "funk")
	_loud(TRUCK, "samba")
	var n := vehicles.size()
	for a in [_mode, _dir, _pace, _c, _back, _front, _wa, _ww, _wp, _z0, _zb, _zk, _zp, _pa, _pb, _pc, _behind, _stage, _far]:
		a.resize(n)
	_plans.resize(n)
	setup(FLEET_SEED)


func _spawn(k: int, paint: Color) -> void:
	var kind: Array = _kinds[k]
	var size: Vector3 = kind[1]
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = kind[0]
	mi.material_override = _mat_v
	mi.set_instance_shader_parameter("paint", paint)
	body.add_child(mi)
	add_child(body)
	_bodies.append(body)
	vehicles.append({"body": body, "kind": k, "lane": 0, "half": size * 0.5, "damage": kind[2]})


## Hangs a music loop on the first vehicle of a kind.
func _loud(kind: int, sound: String) -> void:
	for v in vehicles:
		if v.kind == kind:
			var e := Sfx.emitter(sound, 3.0, 8.0, 90.0)
			e.position.y = 2.0
			v.body.add_child(e)
			return


func _wheels(parts: Array, xs: Array, half_w: float, r := 0.34) -> void:
	for wx in xs:
		for side in [-1.0, 1.0]:
			parts.append([_cyl(r, r, 0.24, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(wx, r, side * half_w)), TYRE])


func _build_kinds() -> void:
	var car_paints := [Color(0.85, 0.85, 0.87), Color(0.1, 0.1, 0.12), Color(0.7, 0.08, 0.08), Color(0.12, 0.28, 0.6), Color(0.5, 0.52, 0.55), Color(0.2, 0.45, 0.3), Color(0.75, 0.75, 0.78)]
	# Hatchback.
	var car: Array = [
		part(Vector3(0, 0.62, 0), Vector3(4.1, 0.7, 1.8), P),
		part(Vector3(-0.25, 1.2, 0), Vector3(2.3, 0.5, 1.62), GLASS),
		part(Vector3(-0.25, 1.47, 0), Vector3(2.2, 0.06, 1.6), P),
		part(Vector3(2.06, 0.72, 0.6), Vector3(0.04, 0.16, 0.4), LAMP),
		part(Vector3(2.06, 0.72, -0.6), Vector3(0.04, 0.16, 0.4), LAMP),
		part(Vector3(-2.06, 0.72, 0), Vector3(0.04, 0.14, 1.5), TAIL),
		part(Vector3(2.08, 0.4, 0), Vector3(0.1, 0.22, 1.84), Color(0.12, 0.12, 0.13)),
		part(Vector3(-2.08, 0.4, 0), Vector3(0.1, 0.22, 1.84), Color(0.12, 0.12, 0.13)),
	]
	_wheels(car, [-1.3, 1.3], 0.86)
	_kinds.append([compose(car), Vector3(4.2, 1.5, 1.85), 35.0, 66, car_paints])

	# Rio taxi: yellow with the blue stripe.
	var taxi: Array = [
		part(Vector3(0, 0.62, 0), Vector3(4.3, 0.7, 1.8), Color(0.98, 0.8, 0.05)),
		part(Vector3(0, 0.62, 0), Vector3(4.32, 0.16, 1.82), Color(0.1, 0.25, 0.7)),
		part(Vector3(-0.2, 1.2, 0), Vector3(2.4, 0.5, 1.62), GLASS),
		part(Vector3(-0.2, 1.47, 0), Vector3(2.3, 0.06, 1.6), Color(0.98, 0.8, 0.05)),
		part(Vector3(-0.2, 1.6, 0), Vector3(0.5, 0.18, 0.3), Color(1.0, 1.0, 0.9, 2.0)),
		part(Vector3(2.16, 0.72, 0), Vector3(0.04, 0.16, 1.5), LAMP),
		part(Vector3(-2.16, 0.72, 0), Vector3(0.04, 0.14, 1.5), TAIL),
	]
	_wheels(taxi, [-1.35, 1.35], 0.86)
	_kinds.append([compose(taxi), Vector3(4.4, 1.5, 1.85), 35.0, 26, [Color.WHITE]])

	# City bus: the roof is somewhere to ride.
	var bus: Array = [
		part(Vector3(0, 1.7, 0), Vector3(11.0, 2.7, 2.5), P),
		part(Vector3(0, 2.25, 0), Vector3(10.4, 0.95, 2.54), GLASS),
		part(Vector3(5.52, 1.9, 0), Vector3(0.04, 1.5, 2.2), GLASS),
		part(Vector3(0, 0.75, 0), Vector3(11.04, 0.25, 2.54), Color(0.95, 0.95, 0.95)),
		part(Vector3(5.52, 2.85, 0), Vector3(0.06, 0.3, 1.6), Color(1.0, 0.7, 0.1, 2.0)),
		part(Vector3(5.53, 0.7, 0.9), Vector3(0.04, 0.2, 0.4), LAMP),
		part(Vector3(5.53, 0.7, -0.9), Vector3(0.04, 0.2, 0.4), LAMP),
		part(Vector3(-5.53, 0.8, 0), Vector3(0.04, 0.2, 2.2), TAIL),
		part(Vector3(1.0, 3.12, 0), Vector3(2.0, 0.16, 1.4), Color(0.8, 0.8, 0.8)),
	]
	_wheels(bus, [-3.6, 3.6], 1.18, 0.48)
	_kinds.append([compose(bus), Vector3(11.0, 3.05, 2.5), 60.0, 12, [Color(0.1, 0.4, 0.75), Color(0.9, 0.45, 0.05), Color(0.1, 0.55, 0.3), Color(0.8, 0.12, 0.12), Color(0.95, 0.85, 0.2)]])

	# Kombi, two-tone.
	var kombi: Array = [
		part(Vector3(0, 0.75, 0), Vector3(4.3, 0.9, 1.75), P),
		part(Vector3(0, 1.55, 0), Vector3(4.3, 0.75, 1.75), Color(0.95, 0.94, 0.9)),
		part(Vector3(0.1, 1.55, 0), Vector3(3.6, 0.45, 1.78), GLASS),
		part(Vector3(2.16, 1.5, 0), Vector3(0.04, 0.5, 1.4), GLASS),
		part(Vector3(2.16, 0.9, 0.55), Vector3(0.05, 0.25, 0.25), LAMP),
		part(Vector3(2.16, 0.9, -0.55), Vector3(0.05, 0.25, 0.25), LAMP),
		part(Vector3(-2.16, 0.8, 0), Vector3(0.04, 0.16, 1.4), TAIL),
	]
	_wheels(kombi, [-1.35, 1.35], 0.84)
	_kinds.append([compose(kombi), Vector3(4.4, 1.95, 1.8), 40.0, 22, [Color(0.25, 0.6, 0.75), Color(0.85, 0.3, 0.2), Color(0.95, 0.75, 0.2), Color(0.3, 0.55, 0.3)]])

	# Motoboy with the delivery box on the back.
	var moto: Array = [
		part(Vector3(0, 0.6, 0), Vector3(1.5, 0.35, 0.3), P),
		part(Vector3(0.6, 0.95, 0), Vector3(0.1, 0.5, 0.6), Color(0.15, 0.15, 0.16)),
		part(Vector3(-0.1, 1.15, 0), Vector3(0.35, 0.75, 0.42), Color(0.2, 0.25, 0.6)),
		part(Vector3(0.0, 1.68, 0), Vector3(0.3, 0.3, 0.3), Color(0.9, 0.9, 0.92)),
		part(Vector3(0.25, 1.2, 0.2), Vector3(0.5, 0.1, 0.1), Color(0.2, 0.25, 0.6)),
		part(Vector3(0.25, 1.2, -0.2), Vector3(0.5, 0.1, 0.1), Color(0.2, 0.25, 0.6)),
		part(Vector3(-0.75, 1.1, 0), Vector3(0.55, 0.55, 0.5), Color(0.9, 0.15, 0.1)),
		part(Vector3(0.82, 0.8, 0), Vector3(0.05, 0.14, 0.14), LAMP),
	]
	for wx in [-0.65, 0.7]:
		moto.append([_cyl(0.3, 0.3, 0.12, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(wx, 0.3, 0)), TYRE])
	_kinds.append([compose(moto), Vector3(2.0, 1.4, 0.7), 20.0, 10, [Color(0.1, 0.1, 0.1), Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.7)]])

	# Garbage truck in municipal orange.
	var truck: Array = [
		part(Vector3(2.6, 1.3, 0), Vector3(2.0, 2.0, 2.3), Color(0.98, 0.5, 0.05)),
		part(Vector3(3.1, 1.8, 0), Vector3(1.04, 0.8, 2.1), GLASS),
		part(Vector3(-0.9, 1.7, 0), Vector3(5.0, 2.6, 2.4), Color(0.98, 0.5, 0.05)),
		part(Vector3(-0.9, 1.7, 0), Vector3(5.04, 0.3, 2.44), Color(0.95, 0.95, 0.95)),
		part(Vector3(-3.6, 1.2, 0), Vector3(0.6, 1.6, 2.3), Color(0.3, 0.3, 0.32)),
		part(Vector3(3.62, 0.8, 0), Vector3(0.04, 0.2, 1.9), LAMP),
		part(Vector3(-3.92, 0.9, 0), Vector3(0.04, 0.2, 2.0), TAIL),
	]
	_wheels(truck, [-2.4, -1.2, 2.5], 1.1, 0.45)
	_kinds.append([compose(truck), Vector3(7.6, 3.0, 2.4), 60.0, 10, [Color.WHITE]])

	# Police patrol car.
	var cop: Array = [
		part(Vector3(0, 0.62, 0), Vector3(4.2, 0.7, 1.8), Color(0.95, 0.95, 0.95)),
		part(Vector3(0, 0.62, 0), Vector3(1.5, 0.72, 1.82), Color(0.1, 0.2, 0.6)),
		part(Vector3(-0.25, 1.2, 0), Vector3(2.3, 0.5, 1.62), GLASS),
		part(Vector3(-0.25, 1.47, 0), Vector3(2.2, 0.06, 1.6), Color(0.95, 0.95, 0.95)),
		part(Vector3(-0.25, 1.58, 0.4), Vector3(0.3, 0.15, 0.5), Color(0.2, 0.35, 1.0, 2.0)),
		part(Vector3(-0.25, 1.58, -0.4), Vector3(0.3, 0.15, 0.5), Color(1.0, 0.1, 0.1, 2.0)),
		part(Vector3(2.12, 0.72, 0), Vector3(0.04, 0.16, 1.5), LAMP),
		part(Vector3(-2.12, 0.72, 0), Vector3(0.04, 0.14, 1.5), TAIL),
	]
	_wheels(cop, [-1.3, 1.3], 0.86)
	_kinds.append([compose(cop), Vector3(4.2, 1.6, 1.85), 35.0, 8, [Color.WHITE]])


## Deals out the match's traffic: who drives how, in which lane, on which stretch of road.
## Same seed, same road on every peer; the nodes themselves are left alone.
func setup(seed_value: int) -> void:
	_seed = seed_value & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for a in [_pa, _pb, _pc]:
		a.fill(0.0)
	_mode.fill(PLAIN)
	_behind.fill(-1)
	_stage.fill(0)
	_far.fill(0)
	var order: Array = range(vehicles.size())
	_shuffle(order, rng)
	var sides: Array = [[], []]
	var bikes: Array = []
	var dealt := PackedInt32Array()
	dealt.resize(_kinds.size())
	for i: int in order:
		_plans[i] = PackedFloat32Array()
		var k: int = vehicles[i].kind
		if k == MOTO:
			bikes.append(i)
		else:
			# Alternating by kind gives each direction its share of buses and trucks.
			sides[dealt[k] % 2].append(i)
			dealt[k] += 1
	var partner := {}
	for p in 2:
		_cast(p, sides[p], partner, rng)
		_pack(p, sides[p], partner, rng)
	_pack_bikes(bikes, rng)
	for p in 2:
		for i: int in sides[p]:
			if _mode[i] == CHANGER:
				_plan_changes(i, partner.get(i, -1), bikes if p == 1 else [], rng)
			elif _mode[i] == STALLER:
				_behind[i] = _follower(i)


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held = a[i]
		a[i] = a[j]
		a[j] = held


## Gives the vehicles of one direction their roles and works out how much road each role
## needs: its own length, its surge either way, and behind it the ground a stall loses.
func _cast(p: int, list: Array, partner: Dictionary, rng: RandomNumberGenerator) -> void:
	var drunks := DRUNKS if p == 0 else 0
	var benders := BENDERS
	var changers := CHANGERS
	var stallers: int = STALLERS[p]
	var lead := -1
	for i: int in list:
		var k: int = vehicles[i].kind
		var half: Vector3 = vehicles[i].half
		var nimble := k != BUS and k != TRUCK
		var amp := rng.randf_range(0.6, 2.4) if nimble else rng.randf_range(0.3, 1.0)
		var rate := rng.randf_range(0.3, 0.7)
		var phase := rng.randf() * TAU
		var mode := PLAIN
		var lag := 0.0
		if k == BUS:
			# Only the city-side kerb has shelters.
			if p == 1:
				mode = BUS_STOPPER
				lag = _lag_peak(BUS_HOLD)
		elif k == CAR and drunks > 0:
			drunks -= 1
			mode = DRUNK
			amp = rng.randf_range(2.5, 3.2)
			rate = rng.randf_range(0.5, 0.75)
		elif nimble and benders > 0 and lead < 0:
			mode = CHANGER
			amp = minf(amp, CHANGER_SURGE / rate)
			lead = i
		elif nimble and benders > 0:
			# Surging in step with the car ahead is what lets it sit this close.
			benders -= 1
			mode = FOLLOWER
			amp = _wa[lead]
			rate = _ww[lead]
			phase = _wp[lead]
			lag = _lag_peak(BEND_HOLD)
			partner[lead] = i
		elif nimble and changers > 0:
			changers -= 1
			mode = CHANGER
			amp = minf(amp, CHANGER_SURGE / rate)
		elif stallers > 0:
			stallers -= 1
			mode = STALLER
			_pa[i] = rng.randf_range(35.0, 70.0)
			_pb[i] = rng.randf() * _pa[i]
			_pc[i] = rng.randf_range(2.5, 4.0)
			lag = _lag_peak(_pc[i])
		_mode[i] = mode
		_dir[i] = Layout.LANE_DIR[p * 2]
		_pace[i] = PAIR_SPEED
		_wa[i] = amp
		_ww[i] = rate
		_wp[i] = phase
		_back[i] = half.x + amp + PAD + lag * PAIR_SPEED
		_front[i] = half.x + amp + PAD
		if mode == FOLLOWER:
			# The pair stall together, so the leader needs no room of its own behind it.
			_front[i] = half.x + BEND_GAP
			_back[lead] = vehicles[lead].half.x
			lead = -1


## Lays one direction's vehicles end to end along the frame, each in the emptier lane,
## with anything that uses both lanes holding its stretch in both. Those wait their turn
## until the two lanes are nearly level, since whatever one lane is behind by is wasted.
func _pack(p: int, list: Array, partner: Dictionary, rng: RandomNumberGenerator) -> void:
	var queue: Array = []
	for i: int in list:
		if _mode[i] != FOLLOWER:
			queue.append(i)
	_shuffle(queue, rng)
	var cur := [0.0, 0.0]
	var placed: Array = []  # [start of stretch, vehicle, share of the spare road]
	var waiting: Array = []
	for lead: int in queue:
		if _mode[lead] == CHANGER or _mode[lead] == DRUNK:
			waiting.append(lead)
			continue
		_place(p, lead, -1, cur, placed, rng)
		while not waiting.is_empty() and absf(cur[0] - cur[1]) < LEVEL:
			var next: int = waiting.pop_front()
			_place(p, next, partner.get(next, -1), cur, placed, rng)
	for lead: int in waiting:
		_place(p, lead, partner.get(lead, -1), cur, placed, rng)
	_spread(placed, maxf(cur[0], cur[1]))


## Puts one vehicle, and the follower it may have, at the head of the queue in a lane.
func _place(p: int, lead: int, follower: int, cur: Array, placed: Array, rng: RandomNumberGenerator) -> void:
	var side := rng.randi() % 2
	for i: int in ([follower, lead] if follower >= 0 else [lead]):
		var both := _mode[i] != PLAIN and _mode[i] != STALLER and _mode[i] != BUS_STOPPER
		if vehicles[i].kind == BUS:
			# Kerb lanes are the first of the sea-side pair and the second of the other.
			side = p
		elif not both and cur[0] != cur[1]:
			side = 0 if cur[0] < cur[1] else 1
		var start: float = maxf(cur[0], cur[1]) if both else cur[side]
		var end := start + _back[i] + _front[i]
		if both:
			cur[0] = end
			cur[1] = end
		else:
			cur[side] = end
		_home(i, p * 2 + side, rng)
		# A leader takes no spare road, or it would open up between it and its follower.
		placed.append([start, i, 0.0 if follower >= 0 and i == lead else pow(rng.randf(), 3.0)])


## Motoboys: one file along the divider, in their own faster frame.
func _pack_bikes(bikes: Array, rng: RandomNumberGenerator) -> void:
	var cur := 0.0
	var placed: Array = []
	for i: int in bikes:
		var half: Vector3 = vehicles[i].half
		vehicles[i].lane = 2
		_dir[i] = 1.0
		_pace[i] = PAIR_SPEED * MOTO_PACE
		_wa[i] = rng.randf_range(0.3, 0.8)
		_ww[i] = rng.randf_range(0.4, 0.8)
		_wp[i] = rng.randf() * TAU
		_z0[i] = DIVIDER_Z
		_zb[i] = MOTO_SWAY
		_zk[i] = rng.randf_range(0.5, 1.1)
		_zp[i] = rng.randf() * TAU
		_back[i] = half.x + _wa[i] + PAD
		_front[i] = _back[i]
		placed.append([cur, i, pow(rng.randf(), 3.0)])
		cur += _back[i] + _front[i]
	_spread(placed, cur)


## Shares the road left over between the packed stretches. Each start only ever moves
## further along than the one before it, so nothing that was clear can come to overlap.
func _spread(placed: Array, used: float) -> void:
	if used > LOOP:
		push_error("Traffic needs %d m of a %d m loop; vehicles will overlap." % [used, LOOP])
	placed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var total := 1.0
	for e: Array in placed:
		total += e[2]
	var slack := maxf(LOOP - used, 0.0)
	var run := 0.0
	for e: Array in placed:
		run += e[2]
		_c[e[1]] = e[0] + slack * run / total + _back[e[1]]


## Settles where across its lane a vehicle sits and how much it weaves about that line.
func _home(i: int, lane: int, rng: RandomNumberGenerator) -> void:
	var hz: float = vehicles[i].half.z
	vehicles[i].lane = lane
	var lo: float = LANE_EDGES[lane].x + hz
	var hi: float = LANE_EDGES[lane].y - hz
	var sway := minf(rng.randf_range(0.1, 0.45), (hi - lo) * 0.5)
	_zk[i] = rng.randf_range(0.5, 1.1)
	_zp[i] = rng.randf() * TAU
	match _mode[i]:
		BUS_STOPPER:
			# Runs along the divider side of its lane so there is some kerb to pull in to.
			sway = 0.0
			_z0[i] = lo
			_pc[i] = hi - lo
		CHANGER:
			var olo: float = LANE_EDGES[lane ^ 1].x + hz
			var ohi: float = LANE_EDGES[lane ^ 1].y - hz
			sway = minf(minf(sway, CHANGER_SWAY), (ohi - olo) * 0.5)
			_z0[i] = rng.randf_range(lo + sway, hi - sway)
			# One lane's width across where it fits, never more.
			_pa[i] = clampf(_z0[i] + Layout.LANES[lane ^ 1] - Layout.LANES[lane], olo + sway, ohi - sway) - _z0[i]
			_pb[i] = -1.0
		FOLLOWER:
			_z0[i] = rng.randf_range(lo + sway, hi - sway)
			_pb[i] = -1.0
		DRUNK:
			# Two slow swings that never quite line up, across the full width of both lanes.
			lo = LANE_EDGES[lane & ~1].x + hz
			hi = LANE_EDGES[lane | 1].y - hz
			_z0[i] = (lo + hi) * 0.5
			sway = (hi - lo) * 0.5 * 0.68
			_zk[i] = 0.8
			_pa[i] = 1.2
			_pb[i] = rng.randf() * TAU
			_pc[i] = (hi - lo) * 0.5 * 0.32
		_:
			_z0[i] = rng.randf_range(lo + sway, hi - sway)
	_zb[i] = sway


## Picks the moments a changer swaps lanes, an even number per SUPER so it ends where it
## began. Each is drawn until it lands where no motoboy is passing; if one cannot be
## found the car keeps its lane for the whole match.
func _plan_changes(i: int, follower: int, bikes: Array, rng: RandomNumberGenerator) -> void:
	var count := 2 * rng.randi_range(2, 5)
	var step := SUPER / count
	var lag := _lag_peak(BEND_HOLD) if follower >= 0 else 0.0
	var plan := PackedFloat32Array()
	for k in count:
		var at := -1.0
		for attempt in CHANGE_TRIES:
			var c := step * (k + 0.1 + 0.6 * rng.randf())
			if _divider_clear(i, c, lag, bikes):
				at = c
				break
		if at < 0.0:
			return
		plan.append(at)
	_plans[i] = plan
	if follower >= 0:
		# The bump comes just after the leader cuts back in front of its follower.
		_pb[i] = plan[1] + CHANGE_TIME + BEND_AFTER
		_pb[follower] = _pb[i] + BEND_DELAY
		_behind[i] = follower


## Whether every motoboy stays off vehicle i's stretch for a lane change starting at road
## time `at`. A car that may be running `lag` seconds late takes that much longer over it
## and may be that much further back.
func _divider_clear(i: int, at: float, lag: float, bikes: Array) -> bool:
	var gain := PAIR_SPEED * (MOTO_PACE - 1.0)
	var from := at - 0.2
	var took := CHANGE_TIME + lag + 0.4
	var rear := _c[i] - _back[i] - lag * PAIR_SPEED
	var length := _back[i] + _front[i] + lag * PAIR_SPEED
	for m: int in bikes:
		var gap := fposmod(_c[m] - _back[m] + gain * from - rear, LOOP)
		if gap < length or gap + _back[m] + _front[m] + gain * took > LOOP:
			return false
	return true


## The vehicle next behind i in its lane.
func _follower(i: int) -> int:
	var best := LOOP
	var found := -1
	for j in vehicles.size():
		if j == i or vehicles[j].kind == MOTO or vehicles[j].lane != vehicles[i].lane:
			continue
		var gap := fposmod(_c[i] - _c[j], LOOP)
		if gap < best:
			best = gap
			found = j
	return found


## Repeatable noise in 0..1 from three integers, the same on every peer.
static func _h(a: int, b: int, c: int) -> float:
	var x := ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) & 0xffffffff
	x = ((x ^ (x >> 15)) * 0x2c1b3c6d) & 0xffffffff
	x = ((x ^ (x >> 12)) * 0x297a2d39) & 0xffffffff
	x ^= x >> 15
	return float(x & 0xffffff) / 16777216.0


## Seconds lost `s` seconds into a stall that sits still for `hold`.
static func _lag_at(s: float, hold: float) -> float:
	if s <= 0.0:
		return 0.0
	if s < STALL_BRAKE:
		return s * s / (2.0 * STALL_BRAKE)
	s -= STALL_BRAKE
	var lost := STALL_BRAKE * 0.5
	if s < hold:
		return lost + s
	s -= hold
	lost += hold
	if s < STALL_PULL:
		return lost + s - CATCH_UP * s * s / (2.0 * STALL_PULL)
	s -= STALL_PULL
	lost += STALL_PULL * (1.0 - CATCH_UP * 0.5)
	var gain := CATCH_UP - 1.0
	var run := (lost - gain * STALL_EASE * 0.5) / gain
	if s < run:
		return lost - gain * s
	s -= run
	if s < STALL_EASE:
		return gain * (STALL_EASE * 0.5 - s + s * s / (2.0 * STALL_EASE))
	return 0.0


## The most a stall with this hold ever loses, in seconds.
static func _lag_peak(hold: float) -> float:
	return STALL_BRAKE * 0.5 + hold + STALL_PULL * (1.0 - CATCH_UP * 0.5)


## How long a stall with this hold takes from first braking to being back on time.
static func _lag_span(hold: float) -> float:
	var gain := CATCH_UP - 1.0
	return STALL_BRAKE + hold + STALL_PULL + (_lag_peak(hold) - gain * STALL_EASE * 0.5) / gain + STALL_EASE


## A staller's road time is cut into windows; a hash of the window says whether it stalls
## in that one, when, and for how long.
func _stall_lag(i: int, w: float) -> float:
	var window := _pa[i]
	var s := w + _pb[i]
	var n := floorf(s / window)
	var key := int(n)
	if _h(_seed, i, key) > STALL_CHANCE:
		return 0.0
	var hold := lerpf(STALL_HOLD_MIN, _pc[i], _h(_seed, i + 7919, key))
	var start := _h(_seed, i + 15838, key) * (window - _lag_span(hold))
	return _lag_at(s - n * window - start, hold)


## Vehicle i at road time w, as (distance along the loop, z, sideways slope of its path).
## Everything it does is driven by its own clock `tau`, which is road time less whatever
## it has lost to stalling, so a car that is stopped is not also sliding sideways.
func _track(i: int, w: float) -> Vector3:
	var mode := _mode[i]
	var tau := w
	var z := _z0[i]
	var dz := 0.0
	if mode == STALLER:
		tau -= _stall_lag(i, w)
	elif mode == CHANGER:
		if _pb[i] >= 0.0:
			tau -= _lag_at(fposmod(w - _pb[i], SUPER), BEND_HOLD)
		var plan := _plans[i]
		var at := fposmod(tau, SUPER)
		var k := -1
		for j in plan.size():
			if plan[j] > at:
				break
			k = j
		if k >= 0:
			var u := minf((at - plan[k]) / CHANGE_TIME, 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var rate := 6.0 * u * (1.0 - u) / CHANGE_TIME
			if k % 2 == 0:
				z += _pa[i] * e
				dz += _pa[i] * rate
			else:
				z += _pa[i] * (1.0 - e)
				dz -= _pa[i] * rate
	elif mode == FOLLOWER:
		if _pb[i] >= 0.0:
			tau -= _lag_at(fposmod(w - _pb[i], SUPER), BEND_HOLD)
	elif mode == BUS_STOPPER:
		var d := _c[i] + PAIR_SPEED * w
		var lap := floorf(d / LOOP)
		var stops: int = BUS_PATTERNS[int(_h(_seed, i, int(lap)) * BUS_PATTERNS.size())]
		var x := d - lap * LOOP - LOOP * 0.5
		for k in BUS_STOPS.size():
			if (stops & (1 << k)) == 0:
				continue
			# Seconds since it was due at the shelter; it brakes early to stop level with it.
			var s: float = (x - BUS_STOPS[k]) / PAIR_SPEED
			if s > -BUS_SWAY and s < BUS_CLEAR:
				tau -= _lag_at(s + STALL_BRAKE * 0.5, BUS_HOLD)
				var u := (s - w + tau) / BUS_SWAY
				if absf(u) < 1.0:
					var q := 1.0 - u * u
					z += _pc[i] * q * q
					dz -= _pc[i] * 4.0 * u * q / BUS_SWAY
	elif mode == DRUNK:
		var swing := _pa[i] * tau + _pb[i]
		z += _pc[i] * sin(swing)
		dz += _pc[i] * _pa[i] * cos(swing)
	_lag = w - tau
	var surge := _ww[i] * tau + _wp[i]
	var weave := _zk[i] * tau + _zp[i]
	var a := _c[i] + _pace[i] * tau + _wa[i] * sin(surge)
	z += _zb[i] * sin(weave)
	dz += _zb[i] * _zk[i] * cos(weave)
	return Vector3(fposmod(a, LOOP), z, dz / (_pace[i] + _wa[i] * _ww[i] * cos(surge)))


## Where vehicle i is at match time t. The one answer to that question, on every peer.
func pos_of(i: int, t: float) -> Vector3:
	var at := _track(i, warp(t))
	return Vector3(_dir[i] * (at.x - LOOP * 0.5), 0.0, at.y)


## How fast vehicle i is really moving at match time t, which the cycle alone cannot say.
func vel_of(i: int, t: float) -> Vector3:
	var d := pos_of(i, t + VEL_STEP) - pos_of(i, t - VEL_STEP)
	if absf(d.x) > LOOP * 0.5:
		d.x -= signf(d.x) * LOOP
	return d / (2.0 * VEL_STEP)


## Horns and the crunch. Local sound only, set off by the same clock on every peer.
func _react(i: int, ear: Vector3) -> void:
	var stage := 0 if _lag < 0.1 else (1 if _lag < HONK_AGAIN else 2)
	var was := _stage[i]
	_stage[i] = stage
	if stage <= was or _behind[i] < 0:
		return
	var at: Vector3 = _bodies[i].global_position
	if absf(at.x - ear.x) > HEAR_X:
		return
	if _mode[i] == CHANGER and stage == 1:
		Sfx.play("crash", at + Vector3(0, 0.8, 0), 2.0)
	else:
		Sfx.play("horn", _bodies[_behind[i]].global_position + Vector3(0, 1, 0), -2.0, 0.9 + 0.3 * _h(_seed, i, _tick))


func _physics_process(delta: float) -> void:
	var t := MatchState.time
	var w := warp(t)
	var g = Net.game
	var pl = g.local_player if g != null else null
	var ear: Vector3 = pl.global_position if pl != null else Vector3(INF, 0, 0)
	_tick += 1
	for i in vehicles.size():
		if _far[i] == 1 and ((i + _tick) & 7) != 0:
			continue
		var at := _track(i, w)
		var x := _dir[i] * (at.x - LOOP * 0.5)
		_far[i] = 1 if absf(x) > FAR_X else 0
		_bodies[i].global_transform = Transform3D(Basis(Vector3.UP, atan2(-at.z, _dir[i])), Vector3(x, 0.0, at.y))
		if _mode[i] == STALLER or _mode[i] == CHANGER:
			_react(i, ear)
	_hit_cd -= delta
	if pl == null or _hit_cd > 0.0 or not pl.can_act():
		return
	var p: Vector3 = pl.global_position
	if p.z < Layout.ROAD_Z or p.z > Layout.WALK_Z:
		return
	for i in vehicles.size():
		var v: Dictionary = vehicles[i]
		var c: Vector3 = v.body.global_position
		var half: Vector3 = v.half
		# Standing on the roof is riding it; anywhere lower is getting run down.
		if absf(p.x - c.x) < half.x + 0.4 and absf(p.z - c.z) < half.z + 0.4 and p.y < half.y * 2.0 - 0.4:
			var vel := vel_of(i, t)
			if absf(vel.x) < RUN_DOWN_SPEED:
				continue
			_hit_cd = 1.0
			pl.knock(Vector3(vel.x * 1.1, 5.5, 3.0 if p.z > c.z else -3.0))
			g.to_server("srv_run_over", [i])
			return
