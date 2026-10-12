extends "res://scenes/world/world_kit.gd"
## Traffic on the avenida. Every vehicle's position is a function of the match clock, so
## all players see the same cars in the same place without a byte sent. The whole road
## stops together for a few seconds in every cycle, which is when to cross.

const LOOP := 1100.0
const CYCLE := 40.0
const GO := 28.0
const BRAKE := 2.0
const HALT := 8.0
const LANE_SPEED := [11.0, 14.5, 14.5, 11.0]
## Paint for body panels: vertex alpha 0 means "use this vehicle's paint".
const P := Color(1, 1, 1, 0)
const GLASS := Color(0.08, 0.11, 0.15)
const TYRE := Color(0.05, 0.05, 0.06)
const LAMP := Color(1.0, 0.95, 0.8, 2.0)
const TAIL := Color(0.9, 0.08, 0.05, 2.0)

## One entry per vehicle: {body, lane, phase, half (half size), damage}.
var vehicles: Array = []

var _kinds: Array = []  # [mesh, size, damage, weight, paints]
var _mat_v: ShaderMaterial
var _hit_cd := 0.0


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
	rng.seed = 5150
	for lane in Layout.LANES.size():
		var x := rng.randf_range(0.0, 20.0)
		while x < LOOP - 16.0:
			var roll := rng.randf()
			var k := 0
			for i in _kinds.size():
				roll -= _kinds[i][3]
				if roll <= 0.0:
					k = i
					break
			# Buses keep to the kerb lanes, bikes filter down the middle.
			if k == 2 and (lane == 1 or lane == 2):
				k = 0
			var kind: Array = _kinds[k]
			var paints: Array = kind[4]
			_spawn(kind, lane, x, paints[rng.randi() % paints.size()])
			x += kind[1].x + rng.randf_range(7.0, 34.0)


func _spawn(kind: Array, lane: int, phase: float, paint: Color) -> void:
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
	if Layout.LANE_DIR[lane] < 0.0:
		body.rotation.y = PI
	add_child(body)
	vehicles.append({"body": body, "lane": lane, "phase": phase, "half": size * 0.5, "damage": kind[2]})


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
	_kinds.append([compose(car), Vector3(4.2, 1.5, 1.85), 35.0, 0.42, car_paints])

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
	_kinds.append([compose(taxi), Vector3(4.4, 1.5, 1.85), 35.0, 0.16, [Color.WHITE]])

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
	_kinds.append([compose(bus), Vector3(11.0, 3.05, 2.5), 60.0, 0.12, [Color(0.1, 0.4, 0.75), Color(0.9, 0.45, 0.05), Color(0.1, 0.55, 0.3), Color(0.8, 0.12, 0.12), Color(0.95, 0.85, 0.2)]])

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
	_kinds.append([compose(kombi), Vector3(4.4, 1.95, 1.8), 40.0, 0.1, [Color(0.25, 0.6, 0.75), Color(0.85, 0.3, 0.2), Color(0.95, 0.75, 0.2), Color(0.3, 0.55, 0.3)]])

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
	_kinds.append([compose(moto), Vector3(2.0, 1.4, 0.7), 20.0, 0.12, [Color(0.1, 0.1, 0.1), Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.7)]])

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
	_kinds.append([compose(truck), Vector3(7.6, 3.0, 2.4), 60.0, 0.04, [Color.WHITE]])

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
	_kinds.append([compose(cop), Vector3(4.2, 1.6, 1.85), 35.0, 0.04, [Color.WHITE]])


## Where vehicle i is at match time t.
func pos_of(i: int, t: float) -> Vector3:
	var v: Dictionary = vehicles[i]
	var lane: int = v.lane
	var x := fposmod(v.phase + Layout.LANE_DIR[lane] * LANE_SPEED[lane] * warp(t), LOOP) - LOOP * 0.5
	return Vector3(x, 0.0, Layout.LANES[lane])


func _physics_process(delta: float) -> void:
	var t := MatchState.time
	for i in vehicles.size():
		vehicles[i].body.global_position = pos_of(i, t)
	_hit_cd -= delta
	var g = Net.game
	if g == null or g.local_player == null or _hit_cd > 0.0:
		return
	var pl = g.local_player
	var f := flow(t)
	if f < 0.25 or not pl.can_act():
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
			var lane: int = v.lane
			_hit_cd = 1.0
			pl.knock(Vector3(Layout.LANE_DIR[lane] * LANE_SPEED[lane] * f * 1.1, 5.5, 3.0 if p.z > c.z else -3.0))
			g.to_server("srv_run_over", [i])
			return
