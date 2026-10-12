extends "res://scenes/world/world_kit.gd"
## Everything inland of the promenade: the avenida, two rows of buildings with a back
## street between them, and the favela stepping up the hill behind.

const ASPHALT := Color(0.16, 0.16, 0.18)
const PAVING := Color(0.66, 0.65, 0.62)
const CONCRETE := Color(0.52, 0.5, 0.47)
const DARK := Color(0.18, 0.19, 0.21)
const STEEL := Color(0.72, 0.73, 0.75)
const BRICK := Color(0.7, 0.4, 0.28)
const CAR_TINTS := [Color(0.85, 0.85, 0.87), Color(0.12, 0.12, 0.14), Color(0.7, 0.1, 0.1), Color(0.15, 0.3, 0.6), Color(0.55, 0.57, 0.6), Color(0.9, 0.75, 0.1)]
const SHOPS := ["PADARIA", "FARMÁCIA", "BOTECO DO ZÉ", "LOTÉRICA", "AÇOUGUE", "SUCOS", "LANCHONETE", "BANCO", "MERCADO", "SORVETERIA", "CHURRASCARIA", "BAR DO PORTUGUÊS", "PASTELARIA", "ÓTICA", "SALÃO", "FERRAGENS", "LAN HOUSE", "PIZZARIA"]
const HOTELS := ["HOTEL ATLÂNTICO", "PALACE", "HOTEL LEME", "RIO SOL", "OTHON"]
const GRAFFITI := ["RIO 40°", "PAZ", "FAVELA VIVE", "SAUDADE", "É NÓIS", "AMOR", "LIBERDADE", "GOL!"]
## Stretches of favela terrace left clear of houses, as [terrace, x from, x to].
const YARDS := [[2, 52.0, 80.0], [4, -62.0, -30.0], [3, -124.0, -116.0], [1, 208.0, 216.0]]

var _rng := RandomNumberGenerator.new()
var _tanks: Array = []
var _dishes: Array = []
var _wheels: Array = []
var _fruit: Array = []
var _fruit_tints: Array = []


func _ready() -> void:
	_rng.seed = 4242
	_init_kit()
	_streets()
	_row_a()
	_row_b()
	_delegacia()
	_favela()
	_far_favela()
	_instances(_cyl(0.8, 0.8, 1.3, 10), _mat(Color(0.15, 0.42, 0.8), 0.5), _tanks)
	_instances(_ball(0.45, 0.25, 8), _mat(Color(0.85, 0.85, 0.85)), _dishes)
	_instances(_cyl(0.32, 0.32, 0.22, 10), _mat(Color(0.06, 0.06, 0.07)), _wheels)
	_instances(_ball(0.12, -1.0, 6), _vertex_mat(), _fruit, _fruit_tints)
	_flush()


func _streets() -> void:
	var long := 1040.0
	_plane(Vector3(0, 0.01, 190), Vector2(long, 240), _mat(CONCRETE))
	_plane(Vector3(0, 0.02, 61), Vector2(long, 18), _mat(ASPHALT))
	_plane(Vector3(0, 0.02, 105), Vector2(long, 12), _mat(ASPHALT.lightened(0.06)))
	_plane(Vector3(0, 0.025, 134), Vector2(long, 6), _mat(Color(0.45, 0.4, 0.34)))
	for cx in Layout.CROSS_X:
		_plane(Vector3(cx, 0.02, 86), Vector2(8, 26), _mat(ASPHALT.lightened(0.03)))
	for sx in Layout.STAIR_X:
		_plane(Vector3(sx, 0.02, 121), Vector2(8, 20), _mat(PAVING.darkened(0.2)))

	# Avenida: lane dashes, edge lines, a planted median and zebra crossings.
	for i in 104:
		var x := -517.0 + i * 10.0
		_box(Vector3(x, 0.04, 56.0), Vector3(3, 0.02, 0.16), Color(0.95, 0.95, 0.95))
		_box(Vector3(x, 0.04, 66.0), Vector3(3, 0.02, 0.16), Color(0.95, 0.95, 0.95))
	for z in [52.6, 69.6]:
		_box(Vector3(0, 0.04, z), Vector3(long, 0.02, 0.14), Color(0.95, 0.9, 0.5))
	var gaps: Array = [-520.0]
	for cx in Layout.CROSS_X:
		gaps.append(cx - 7.0)
		gaps.append(cx + 7.0)
	gaps.append(520.0)
	for k in range(0, gaps.size(), 2):
		var lo: float = gaps[k]
		var hi: float = gaps[k + 1]
		_box(Vector3((lo + hi) * 0.5, 0.1, Layout.MEDIAN_Z), Vector3(hi - lo, 0.2, 1.8), Color(0.72, 0.72, 0.7))
		_box(Vector3((lo + hi) * 0.5, 0.21, Layout.MEDIAN_Z), Vector3(hi - lo - 0.6, 0.02, 1.2), Color(0.2, 0.36, 0.17))
	for cx in Layout.CROSS_X:
		var z := 53.0
		while z < 69.5:
			_box(Vector3(cx, 0.04, z), Vector3(5.0, 0.02, 0.5), Color(0.95, 0.95, 0.95))
			z += 1.0
		for side in [-1.0, 1.0]:
			_signal(Vector3(cx + side * 5.5, 0, 70.5 if side > 0.0 else 52.6))

	# Sidewalk in front of the shops, with lamps and bus shelters.
	_box(Vector3(0, 0.03, 71.5), Vector3(long, 0.06, 3.0), PAVING)
	_box(Vector3(0, 0.07, 70.05), Vector3(long, 0.14, 0.2), Color(0.75, 0.75, 0.75))
	for i in 36:
		var x := -510.0 + i * 29.0
		_box(Vector3(x, 3.5, 70.5), Vector3(0.16, 7.0, 0.16), DARK)
		_box(Vector3(x, 6.9, 69.5), Vector3(0.1, 0.1, 2.0), DARK)
		_glow(Vector3(x, 6.8, 68.7), Vector3(0.5, 0.14, 0.3), Color(1.0, 0.9, 0.65))
	for x in [-180.0, -90.0, 0.0, 90.0, 180.0]:
		_shelter(Vector3(x, 0, 71.3))

	# Back street: parked cars, power lines, bunting, a street market.
	for i in 30:
		var x := -290.0 + i * 20.0 + _rng.randf_range(-3, 3)
		if _near_cross(x, 7.0) or absf(x) < 13.0:
			continue
		if _rng.randf() < 0.55:
			_car(Vector3(x, 0, 109.9), _rng.randf_range(-0.04, 0.04), CAR_TINTS[_rng.randi() % CAR_TINTS.size()])
	var px := -298.0
	var prev := Vector3.ZERO
	while px < 300.0:
		var pole := Vector3(px, 0, 99.5)
		_box(pole + Vector3(0, 4.0, 0), Vector3(0.22, 8.0, 0.22), Color(0.4, 0.33, 0.26))
		_box(pole + Vector3(0, 7.4, 0), Vector3(0.12, 0.12, 1.6), Color(0.4, 0.33, 0.26))
		_box(pole + Vector3(0.3, 6.4, 0), Vector3(0.5, 0.7, 0.5), Color(0.5, 0.52, 0.55))
		if prev != Vector3.ZERO:
			for k in 3:
				var sag := 0.25 + 0.12 * k
				var a := prev + Vector3(0, 7.5 - k * 0.5, -0.6 + k * 0.6)
				var b := pole + Vector3(0, 7.5 - k * 0.5, -0.6 + k * 0.6)
				var mid := (a + b) * 0.5 - Vector3(0, sag, 0)
				_wire(a, mid)
				_wire(mid, b)
		prev = pole
		px += 24.0
	for i in 14:
		var bx := -270.0 + i * 41.0
		if _near_cross(bx, 5.0):
			bx += 9.0
		_bunting(Vector3(bx, 5.2, 99.2), Vector3(bx + _rng.randf_range(-3, 3), 5.2, 110.8))
	for i in 7:
		_stall(Vector3(-104.0 + i * 5.2, 0, 101.3), i)
	for i in 6:
		_stall(Vector3(150.0 + i * 5.2, 0, 101.3), i + 3)


func _near_cross(x: float, r: float) -> bool:
	return absf(x - Layout._nearest(Layout.CROSS_X, x)) < r


func _wire(a: Vector3, b: Vector3) -> void:
	var d := b - a
	_box((a + b) * 0.5, Vector3(d.length(), 0.04, 0.04), Color(0.08, 0.08, 0.08), Vector3(0, atan2(-d.z, d.x), asin(d.y / d.length())))


## Festa junina flags strung across the street.
func _bunting(a: Vector3, b: Vector3) -> void:
	_wire(a, b)
	for k in 10:
		var p := a.lerp(b, (k + 0.5) / 10.0) - Vector3(0, 0.25 + sin(k * PI / 9.0) * 0.1, 0)
		_box(p, Vector3(0.03, 0.4, 0.35), Color.from_hsv(fmod(k * 0.19 + a.x * 0.01, 1.0), 0.8, 0.95), Vector3(0, 0, 0))


func _signal(p: Vector3) -> void:
	_box(p + Vector3(0, 2.0, 0), Vector3(0.14, 4.0, 0.14), DARK)
	_box(p + Vector3(0, 3.6, 0), Vector3(0.3, 0.9, 0.3), Color(0.9, 0.75, 0.1))
	_glow(p + Vector3(0, 3.9, -0.16), Vector3(0.16, 0.16, 0.04), Color(1.0, 0.15, 0.1))
	_glow(p + Vector3(0, 3.6, -0.16), Vector3(0.16, 0.16, 0.04), Color(1.0, 0.7, 0.1))
	_glow(p + Vector3(0, 3.3, -0.16), Vector3(0.16, 0.16, 0.04), Color(0.2, 0.9, 0.3))


func _shelter(p: Vector3) -> void:
	for side in [-1.8, 1.8]:
		_block(p + Vector3(side, 1.25, 0.5), Vector3(0.1, 2.5, 0.1), STEEL)
	_block(p + Vector3(0, 2.55, 0), Vector3(4.4, 0.1, 1.7), Color(0.1, 0.35, 0.7))
	_box(p + Vector3(0, 1.4, 0.55), Vector3(3.6, 1.8, 0.04), Color(0.55, 0.7, 0.8))
	_box(p + Vector3(0, 0.45, 0.2), Vector3(3.0, 0.08, 0.4), STEEL)
	_box(p + Vector3(2.4, 1.5, 0), Vector3(0.08, 3.0, 0.08), STEEL)
	_glow(p + Vector3(2.4, 3.0, 0), Vector3(0.7, 0.5, 0.08), Color(0.1, 0.35, 0.8))
	_sign("ÔNIBUS", p + Vector3(0, 2.9, -0.86), 90, Color.WHITE, PI)


## Parked car: something to vault and hide behind. Faces +x before `yaw`.
func _car(p: Vector3, yaw: float, tint: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var rot := Vector3(0, yaw, 0)
	_box(p + Vector3(0, 0.62, 0), Vector3(4.1, 0.7, 1.8), tint, rot)
	_box(p + b * Vector3(-0.2, 1.22, 0), Vector3(2.2, 0.55, 1.6), tint.darkened(0.1), rot)
	_box(p + b * Vector3(-0.2, 1.22, 0), Vector3(2.24, 0.4, 1.64), Color(0.1, 0.14, 0.18), rot)
	_box(p + b * Vector3(2.06, 0.7, 0), Vector3(0.04, 0.16, 1.5), Color(1.0, 0.95, 0.8), rot)
	_box(p + b * Vector3(-2.06, 0.7, 0), Vector3(0.04, 0.16, 1.5), Color(0.8, 0.1, 0.1), rot)
	_collider(p + Vector3(0, 0.75, 0), Vector3(4.1, 1.5, 1.8), rot)
	for wx in [-1.3, 1.3]:
		for wz in [-0.85, 0.85]:
			_wheels.append(Transform3D(b * Basis(Vector3.RIGHT, PI / 2.0), p + b * Vector3(wx, 0.32, wz)))


## Market stall: a striped awning over crates of fruit.
func _stall(p: Vector3, n: int) -> void:
	var tint := Color.from_hsv(fmod(n * 0.23, 1.0), 0.7, 0.9)
	_block(p + Vector3(0, 0.5, 0), Vector3(3.6, 1.0, 1.4), WOOD)
	for side in [-1.7, 1.7]:
		_box(p + Vector3(side, 1.3, -0.6), Vector3(0.08, 2.6, 0.08), STEEL)
		_box(p + Vector3(side, 1.5, 0.6), Vector3(0.08, 3.0, 0.08), STEEL)
	for k in 6:
		_box(p + Vector3(-1.5 + k * 0.6, 2.85, 0), Vector3(0.6, 0.06, 1.9), tint if k % 2 == 0 else Color(0.97, 0.97, 0.95), Vector3(-0.25, 0, 0))
	for k in 30:
		_fruit.append(Transform3D(Basis(), p + Vector3(-1.5 + (k % 10) * 0.33, 1.12 + (k % 2) * 0.05, -0.4 + (k / 10) * 0.4)))
		_fruit_tints.append([Color(0.95, 0.5, 0.05), Color(0.9, 0.15, 0.1), Color(0.95, 0.85, 0.1), Color(0.3, 0.65, 0.15)][(k / 5 + n) % 4])


# --- buildings ---

func _wall_tint() -> Color:
	var c := Color.from_hsv(_rng.randf(), _rng.randf_range(0.0, 0.22), _rng.randf_range(0.8, 0.97))
	if _rng.randf() < 0.18:
		c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.35, 0.55), _rng.randf_range(0.75, 0.9))
	c.a = _rng.randf()
	return c


## The front row: apartment towers over shops, facing the sea.
func _row_a() -> void:
	var edges: Array = [-520.0]
	for cx in Layout.CROSS_X:
		edges.append(cx - Layout.CROSS_HALF)
		edges.append(cx + Layout.CROSS_HALF)
	edges.append(520.0)
	var escape_side := 0
	for k in range(0, edges.size(), 2):
		var x: float = edges[k]
		var hi: float = edges[k + 1]
		while x < hi - 0.1:
			var w := minf(_rng.randf_range(14.0, 24.0), hi - x)
			if hi - x - w < 12.0:
				w = hi - x
			var low := _rng.randf() < 0.38
			var h := 3.5 * _rng.randi_range(2, 5) if low else _rng.randf_range(24.0, 58.0)
			var tint := _wall_tint()
			var c := Vector3(x + w * 0.5, h * 0.5, 86.0)
			_tower(c, Vector3(w - 0.3, h, 26.0), tint)
			x += w
			if absf(c.x) > Layout.X_LIMIT + 30.0:
				continue
			_collider(c, Vector3(w, h, 26.0))
			var trim := Color(tint.r, tint.g, tint.b).darkened(0.35)
			if not low:
				for f in int((h - 5.0) / 3.5):
					_box(Vector3(c.x, 5.25 + f * 3.5, 72.6), Vector3(w - 3.0, 1.0, 0.8), trim)
			_shopfront(c.x, w, 73.0, -1.0)
			_roof(c.x, w, h, 86.0, 26.0)
			if low:
				escape_side += 1
				_fire_escape(c.x - 3.5, Layout.RUA_Z, h, 1.0)
			elif _rng.randf() < 0.3:
				var title: String = HOTELS[_rng.randi() % HOTELS.size()]
				_glow(Vector3(c.x, h + 2.2, 74.0), Vector3(minf(w - 4.0, title.length() * 1.5), 2.6, 0.2), Color(0.08, 0.1, 0.16))
				_sign(title, Vector3(c.x, h + 2.2, 73.85), 440, Color(1.0, 0.85, 0.3), PI)
			# Service doors, air conditioners and graffiti on the back street side.
			for f in int(h / 3.5) - 1:
				if _rng.randf() < 0.5:
					_box(Vector3(c.x + _rng.randf_range(-w * 0.4, w * 0.4), 4.6 + f * 3.5, 99.25), Vector3(0.9, 0.6, 0.5), Color(0.82, 0.82, 0.8))
			if _rng.randf() < 0.5:
				_graffiti(Vector3(c.x + _rng.randf_range(-3, 3), 1.7, 99.06), 0.0)


## The back row: low buildings with bars and workshops at street level.
func _row_b() -> void:
	var edges: Array = [-520.0]
	for sx in Layout.STAIR_X:
		edges.append(sx - Layout.CROSS_HALF)
		edges.append(sx + Layout.CROSS_HALF)
	edges.append(520.0)
	for k in range(0, edges.size(), 2):
		var x: float = edges[k]
		var hi: float = edges[k + 1]
		while x < hi - 0.1:
			var w := minf(_rng.randf_range(10.0, 18.0), hi - x)
			if hi - x - w < 9.0:
				w = hi - x
			# The delegacia takes the plot in the middle.
			if x < 9.0 and x + w > -9.0:
				if x < -9.0:
					w = -9.0 - x
				else:
					x = 9.0
					continue
			var h := 3.5 * _rng.randi_range(1, 4)
			var tint := _wall_tint()
			var c := Vector3(x + w * 0.5, h * 0.5, 121.0)
			_tower(c, Vector3(w - 0.2, h, 20.0), tint)
			x += w
			if absf(c.x) > Layout.X_LIMIT + 30.0:
				continue
			_collider(c, Vector3(w, h, 20.0))
			_shopfront(c.x, w, 111.0, -1.0)
			_roof(c.x, w, h, 121.0, 20.0)
			if w > 11.0 and _rng.randf() < 0.45:
				_fire_escape(c.x - 3.5, Layout.BLOCK_B_Z, h, -1.0)
			if _rng.randf() < 0.6:
				_graffiti(Vector3(c.x + _rng.randf_range(-2, 2), 1.7, 131.06), 0.0)


## Awning and sign over a ground floor shop. `face` is the z the wall is at, `out` which way it looks.
func _shopfront(x: float, w: float, face: float, out: float) -> void:
	var tint := Color.from_hsv(_rng.randf(), 0.7, 0.85)
	var aw := w - 2.0
	_block(Vector3(x, 3.15, face + out * 1.1), Vector3(aw, 0.14, 2.2), tint)
	var n := int(aw / 1.2)
	for k in n:
		if k % 2 == 0:
			_box(Vector3(x - aw * 0.5 + (k + 0.5) * aw / n, 2.95, face + out * 2.2), Vector3(aw / n, 0.4, 0.05), Color(0.97, 0.97, 0.95))
		else:
			_box(Vector3(x - aw * 0.5 + (k + 0.5) * aw / n, 2.95, face + out * 2.2), Vector3(aw / n, 0.4, 0.05), tint)
	_box(Vector3(x, 3.75, face + out * 0.1), Vector3(minf(aw, 9.0), 0.9, 0.12), tint.darkened(0.55))
	_sign(SHOPS[_rng.randi() % SHOPS.size()], Vector3(x, 3.75, face + out * 0.18), 130, Color(1.0, 0.95, 0.8), PI if out < 0.0 else 0.0)
	# A crate by the door: the first step up to the awning.
	if _rng.randf() < 0.5:
		_block(Vector3(x + aw * 0.5 - 0.8, 0.65, face + out * 0.8), Vector3(1.3, 1.3, 1.3), WOOD)
		_block(Vector3(x + aw * 0.5 - 2.3, 0.35, face + out * 0.8), Vector3(1.2, 0.7, 1.2), WOOD.darkened(0.15))


## Water tanks, a stair hut, aerials and air conditioners on a flat roof.
func _roof(x: float, w: float, h: float, z: float, depth: float) -> void:
	for side in [-1.0, 1.0]:
		_box(Vector3(x, h + 0.2, z + side * (depth * 0.5 - 0.15)), Vector3(w - 0.3, 0.4, 0.3), Color(0.5, 0.5, 0.5))
		_box(Vector3(x + side * (w * 0.5 - 0.3), h + 0.2, z), Vector3(0.3, 0.4, depth - 0.3), Color(0.5, 0.5, 0.5))
	_block(Vector3(x + _rng.randf_range(-1, 1) * (w * 0.5 - 3.0), h + 1.3, z + _rng.randf_range(-6, 6)), Vector3(3.0, 2.6, 3.4), Color(0.8, 0.79, 0.76))
	for k in _rng.randi_range(1, 3):
		var p := Vector3(x + _rng.randf_range(-1, 1) * (w * 0.5 - 2.0), h, z + _rng.randf_range(-1, 1) * (depth * 0.5 - 2.5))
		_block(p + Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 1.8), Color(0.45, 0.45, 0.47))
		_tanks.append(Transform3D(Basis(), p + Vector3(0, 1.65, 0)))
	for k in _rng.randi_range(2, 5):
		var p := Vector3(x + _rng.randf_range(-1, 1) * (w * 0.5 - 1.5), h + 0.4, z + _rng.randf_range(-1, 1) * (depth * 0.5 - 1.5))
		_box(p, Vector3(1.2, 0.8, 0.8), Color(0.8, 0.8, 0.78))
	var a := Vector3(x + _rng.randf_range(-1, 1) * (w * 0.5 - 1.5), h, z + _rng.randf_range(-8, 8))
	_box(a + Vector3(0, 2.5, 0), Vector3(0.08, 5.0, 0.08), STEEL)
	_box(a + Vector3(0, 4.2, 0), Vector3(1.4, 0.05, 0.05), STEEL)
	_box(a + Vector3(0, 3.6, 0), Vector3(1.0, 0.05, 0.05), STEEL)
	if _rng.randf() < 0.6:
		_dishes.append(Transform3D(Basis(Vector3.RIGHT, 0.9), a + Vector3(1.5, 0.9, 0)))
		_box(a + Vector3(1.5, 0.45, 0), Vector3(0.08, 0.9, 0.08), STEEL)


## Zig-zag steel stairs up the wall at z = `face` to a roof `h` high. They start at x0 and
## climb toward +x first; `out` is which way they stick out from the wall.
func _fire_escape(x0: float, face: float, h: float, out: float) -> void:
	var flights := int(roundf(h / 3.5))
	var rust := Color(0.42, 0.24, 0.18)
	var slope := Vector3(7.0, 3.5, 0.0).length()
	for k in flights:
		var even := k % 2 == 0
		var z := face + out * (0.75 if even else 2.25)
		var y := k * 3.5
		_block(Vector3(x0 + 3.5, y + 1.75 - 0.1, z), Vector3(slope, 0.2, 1.4), rust, Vector3(0, 0, 0.4636 if even else -0.4636))
		_box(Vector3(x0 + 3.5, y + 2.75, z + out * 0.7), Vector3(slope, 0.06, 0.06), rust.lightened(0.15), Vector3(0, 0, 0.4636 if even else -0.4636))
		# The landing at the top of each flight spans both lanes.
		var lx := x0 + 7.8 if even else x0 - 0.8
		_block(Vector3(lx, y + 3.4, face + out * 1.5), Vector3(1.6, 0.2, 3.0), rust)
		_box(Vector3(lx + (0.75 if even else -0.75), y + 3.95, face + out * 1.5), Vector3(0.06, 1.0, 3.0), rust.lightened(0.15))
		_box(Vector3(lx, y + 3.95, face + out * 3.0), Vector3(1.6, 1.0, 0.06), rust.lightened(0.15))
	for x in [x0 - 1.5, x0 + 8.5]:
		_box(Vector3(x, h * 0.5, face + out * 2.95), Vector3(0.1, h, 0.1), rust)


func _graffiti(p: Vector3, yaw: float) -> void:
	var c := Color.from_hsv(_rng.randf(), 0.85, 1.0)
	var l := _sign(GRAFFITI[_rng.randi() % GRAFFITI.size()], p, 190, c, yaw)
	l.outline_modulate = Color.from_hsv(_rng.randf(), 0.6, 0.25)
	l.rotation.z = _rng.randf_range(-0.12, 0.12)


## Police station with the lock-up yard behind it. Nobody gets in or out over the walls.
func _delegacia() -> void:
	var c := DB.PRISON_POS
	var grey := Color(0.4, 0.4, 0.42)
	_plane(Vector3(c.x, 0.03, c.z), Vector2(16, 16), _mat(Color(0.55, 0.55, 0.55)))
	_block(Vector3(c.x, 3.5, 112.0), Vector3(18, 7, 2), Color(0.9, 0.9, 0.92))
	_block(Vector3(c.x, 3, 130.0), Vector3(18, 6, 2), grey)
	_block(Vector3(c.x - 8.5, 3, c.z), Vector3(1, 6, 16), grey)
	_block(Vector3(c.x + 8.5, 3, c.z), Vector3(1, 6, 16), grey)
	_collider(Vector3(c.x, 6.4, c.z), Vector3(18, 0.6, 20))
	for k in 17:
		_box(Vector3(c.x - 8.0 + k, 6.05, c.z), Vector3(0.12, 0.12, 16), Color(0.2, 0.2, 0.22))
	for k in 5:
		_box(Vector3(c.x, 6.1, c.z - 8.0 + k * 4.0), Vector3(16, 0.16, 0.16), Color(0.2, 0.2, 0.22))
	# Front: blue band, door, lamp and the patrol cars outside.
	_box(Vector3(c.x, 5.0, 110.95), Vector3(18, 1.2, 0.1), Color(0.1, 0.2, 0.6))
	_box(Vector3(c.x, 1.2, 110.95), Vector3(1.6, 2.4, 0.1), Color(0.15, 0.2, 0.3))
	_glow(Vector3(c.x - 2.0, 3.2, 110.8), Vector3(0.4, 0.4, 0.3), Color(0.2, 0.4, 1.0))
	_glow(Vector3(c.x + 2.0, 3.2, 110.8), Vector3(0.4, 0.4, 0.3), Color(0.2, 0.4, 1.0))
	_sign("DELEGACIA", Vector3(c.x, 5.0, 110.88), 200, Color.WHITE, PI)
	for cx in [-5.5, 5.5]:
		_police_car(Vector3(c.x + cx, 0, 109.8))


func _police_car(p: Vector3) -> void:
	_car(p, 0.0, Color(0.95, 0.95, 0.95))
	_box(p + Vector3(0, 0.62, 0), Vector3(1.4, 0.72, 1.82), Color(0.1, 0.2, 0.6))
	_glow(p + Vector3(-0.2, 1.58, -0.35), Vector3(0.3, 0.14, 0.4), Color(0.9, 0.1, 0.1))
	_glow(p + Vector3(-0.2, 1.58, 0.35), Vector3(0.3, 0.14, 0.4), Color(0.15, 0.3, 1.0))


# --- favela ---

func _house_tint() -> Color:
	var c := BRICK.lerp(Color(0.6, 0.36, 0.26), _rng.randf())
	if _rng.randf() < 0.5:
		c = Color.from_hsv(_rng.randf(), _rng.randf_range(0.3, 0.6), _rng.randf_range(0.8, 0.95))
	c.a = _rng.randf()
	return c


func _in_yard(i: int, x: float, w: float) -> bool:
	for y in YARDS:
		if y[0] == i and x + w * 0.5 > y[1] and x - w * 0.5 < y[2]:
			return true
	return false


## Terraces stepping up the hill, a row of houses on each, stairways between.
func _favela() -> void:
	var earth := Color(0.5, 0.46, 0.42)
	for i in 12:
		var z0 := Layout.FAVELA_Z + i * Layout.TERRACE_D
		var y := (i + 1) * Layout.TERRACE_H
		var deep := Layout.TERRACE_D if i < 11 else 110.0
		_box(Vector3(0, y * 0.5, z0 + deep * 0.5), Vector3(1040, y, deep), earth.darkened(0.04 * (i % 2)))
		if i < Layout.TERRACES:
			_collider(Vector3(0, y * 0.5, z0 + deep * 0.5), Vector3(1040, y, deep))
		# Retaining wall trim.
		_box(Vector3(0, y - 0.1, z0 - 0.06), Vector3(1040, 0.2, 0.14), earth.lightened(0.2))
		_houses(i, z0, y)
		if i < Layout.TERRACES:
			for sx in Layout.STAIR_X:
				_stairs(Vector3(sx, y - Layout.TERRACE_H, z0), i)
	_baile()
	_campinho()
	for v in DB.VENDORS:
		if v.pos.z > Layout.ROAD_Z:
			_vendor_stall(v)


func _houses(i: int, z0: float, y: float) -> void:
	var playable := i < Layout.TERRACES
	var x := -420.0
	var n := 0
	while x < 420.0:
		var w := _rng.randf_range(4.0, 7.5)
		var cx := x + w * 0.5
		var sx := Layout._nearest(Layout.STAIR_X, cx)
		if playable and absf(cx - sx) < 3.0 + w * 0.5:
			x = sx + 3.0
			continue
		if _in_yard(i, cx, w):
			x += w
			continue
		var floors := 1 if _rng.randf() < 0.62 else 2
		var h := Layout.TERRACE_H * floors
		var tint := _house_tint()
		var c := Vector3(cx, y + h * 0.5, z0 + Layout.BECO + 2.5)
		_tower(c, Vector3(w - 0.1, h, 5.0), tint, 1)
		if playable and absf(cx) < Layout.X_LIMIT + 10.0:
			_collider(c, Vector3(w, h, 5.0))
			var top := y + h
			var door := Color.from_hsv(_rng.randf(), 0.6, 0.6)
			_box(Vector3(cx + _rng.randf_range(-1, 1), y + 1.0, z0 + Layout.BECO - 0.02), Vector3(0.9, 2.0, 0.08), door)
			if _rng.randf() < 0.45:
				_tanks.append(Transform3D(Basis.from_scale(Vector3(0.7, 0.8, 0.7)), Vector3(cx + _rng.randf_range(-1, 1), top + 0.52, c.z + 1.2)))
			if _rng.randf() < 0.3:
				_dishes.append(Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(cx + 1.2, top + 0.6, c.z - 1.0)))
			if floors == 1 and _rng.randf() < 0.35:
				# Laje: a sun deck with a low wall and a couple of plastic chairs.
				_box(Vector3(cx, top + 0.3, c.z - 2.4), Vector3(w - 0.3, 0.6, 0.15), Color(tint.r, tint.g, tint.b).lightened(0.2))
				_box(Vector3(cx + 0.8, top + 0.3, c.z), Vector3(0.5, 0.6, 0.5), Color(0.95, 0.95, 0.95))
			elif floors == 2 and _rng.randf() < 0.5:
				_box(Vector3(cx, top + 0.08, c.z - 0.3), Vector3(w + 0.3, 0.08, 5.8), Color(0.55, 0.56, 0.58), Vector3(0.06, 0, 0))
			if n % 3 == 0:
				_washing(Vector3(cx - w * 0.5, y + 2.5, z0 + Layout.BECO), Vector3(cx - w * 0.5 + _rng.randf_range(-0.5, 0.5), y + 2.3, z0 + 0.3))
		x += w + (_rng.randf_range(1.2, 2.2) if _rng.randf() < 0.3 else 0.0)
		n += 1


func _washing(a: Vector3, b: Vector3) -> void:
	_wire(a, b)
	_box(b - Vector3(0, 1.15, 0), Vector3(0.08, 2.3, 0.08), Color(0.4, 0.33, 0.26))
	for k in 4:
		var p := a.lerp(b, (k + 0.6) / 5.0) - Vector3(0, 0.32, 0)
		_box(p, Vector3(0.04, 0.6, 0.45), Color.from_hsv(_rng.randf(), _rng.randf_range(0.2, 0.8), 0.95))


## One flight from the terrace below up to the front edge of terrace i, painted like the
## tiled steps of Lapa.
func _stairs(foot: Vector3, i: int) -> void:
	var run := 4.0
	var rise := Layout.TERRACE_H
	var ang := atan2(rise, run)
	var span := Vector2(run, rise).length()
	_block(foot + Vector3(0, rise * 0.5 - 0.14, -run * 0.5), Vector3(3.0, 0.25, span + 0.3), Color(0.6, 0.58, 0.55), Vector3(-ang, 0, 0))
	var tints := [Color(0.85, 0.15, 0.12), Color(0.98, 0.8, 0.1), Color(0.1, 0.55, 0.25), Color(0.1, 0.3, 0.75)]
	for k in 8:
		var t := (k + 0.5) / 8.0
		_box(foot + Vector3(0, rise * t + 0.02, -run * (1.0 - t)), Vector3(3.0, 0.07, 0.3), tints[(k + i) % 4], Vector3(-ang, 0, 0))
	for side in [-1.6, 1.6]:
		_box(foot + Vector3(side, rise * 0.5 + 0.9, -run * 0.5), Vector3(0.07, 0.07, span), tints[(i + 1) % 4], Vector3(-ang, 0, 0))
		_box(foot + Vector3(side, 0.45, -run), Vector3(0.07, 0.9, 0.07), tints[(i + 1) % 4])
		_box(foot + Vector3(side, rise + 0.45, 0), Vector3(0.07, 0.9, 0.07), tints[(i + 1) % 4])


## A table under a parasol for the people who trade off the promenade.
func _vendor_stall(v: Dictionary) -> void:
	var p: Vector3 = v.pos + Vector3(0, -0.2, 1.6)
	_block(p + Vector3(0, 0.45, 0), Vector3(2.2, 0.9, 0.9), v.color)
	_box(p + Vector3(0, 0.93, 0), Vector3(2.4, 0.06, 1.1), WOOD)
	_box(p + Vector3(0, 1.4, 0.6), Vector3(0.08, 2.8, 0.08), STEEL)
	_box(p + Vector3(0, 2.8, 0), Vector3(2.8, 0.08, 2.0), v.color.lightened(0.3), Vector3(-0.15, 0, 0))
	_sign("%s  [F]" % v.name, p + Vector3(0, 3.5, 0), 80, Color.WHITE, 0.0, true)


## The baile funk yard: a wall of speakers, a DJ table and strings of lights.
func _baile() -> void:
	var c := DB.BAILE_POS
	for side in [-1.0, 1.0]:
		for row in 3:
			for col in 2:
				var p := c + Vector3(side * (10.0 + col * 1.6), 0.75 + row * 1.5, 2.2)
				_block(p, Vector3(1.5, 1.45, 1.2), Color(0.07, 0.07, 0.08))
				_box(p + Vector3(0, 0.2, -0.61), Vector3(0.9, 0.9, 0.04), Color(0.25, 0.25, 0.27))
				_box(p + Vector3(0, -0.45, -0.61), Vector3(0.4, 0.3, 0.04), Color(0.25, 0.25, 0.27))
	_block(c + Vector3(0, 0.55, 2.4), Vector3(4.0, 1.1, 1.0), Color(0.15, 0.1, 0.2))
	_glow(c + Vector3(0, 1.15, 2.4), Vector3(1.6, 0.1, 0.6), Color(0.9, 0.2, 0.8))
	for k in 24:
		var t := k / 23.0
		_glow(c + Vector3(lerpf(-12.0, 12.0, t), 4.2 - sin(t * PI) * 0.7, -2.0), Vector3(0.16, 0.16, 0.16), Color.from_hsv(fmod(k * 0.17, 1.0), 0.7, 1.0))
		_glow(c + Vector3(lerpf(-12.0, 12.0, t), 4.4 - sin(t * PI) * 0.7, 2.6), Vector3(0.16, 0.16, 0.16), Color.from_hsv(fmod(k * 0.13 + 0.4, 1.0), 0.7, 1.0))
	for side in [-12.0, 12.0]:
		_box(c + Vector3(side, 2.2, -2.0), Vector3(0.1, 4.4, 0.1), DARK)
	_sign("BAILE", c + Vector3(0, 5.0, 2.7), 300, Color(1.0, 0.3, 0.85), PI)
	var beat := Sfx.emitter("funk", 5.0, 10.0, 120.0)
	beat.position = c + Vector3(0, 2.5, 2.0)
	add_child(beat)


## A caged concrete five-a-side pitch up the hill.
func _campinho() -> void:
	var c := DB.CAMPINHO_POS
	_box(c + Vector3(0, 0.02, 0.5), Vector3(30, 0.04, 7), Color(0.3, 0.5, 0.36))
	_box(c + Vector3(0, 0.03, 0.5), Vector3(0.12, 0.04, 7), Color(0.95, 0.95, 0.95))
	for side in [-1.0, 1.0]:
		var g := c + Vector3(side * 14.5, 0, 0.5)
		for post in [-1.5, 1.5]:
			_block(g + Vector3(0, 1.0, post), Vector3(0.12, 2.0, 0.12), Color(0.95, 0.95, 0.95))
		_block(g + Vector3(0, 2.0, 0), Vector3(0.12, 0.12, 3.12), Color(0.95, 0.95, 0.95))
	for k in 16:
		_box(c + Vector3(-15.0 + k * 2.0, 1.5, -3.3), Vector3(0.06, 3.0, 0.06), STEEL)
	_box(c + Vector3(0, 3.0, -3.3), Vector3(30, 0.06, 0.06), STEEL)
	_box(c + Vector3(0, 1.5, -3.3), Vector3(30, 0.06, 0.06), STEEL)


## Houses carrying on up the hillside behind the part anyone can reach, thinning with height.
func _far_favela() -> void:
	var z := 236.0
	while z < 330.0:
		var x := -520.0
		while x < 520.0:
			var w := _rng.randf_range(5.0, 9.0)
			var y := maxf(Layout.hill_y(x, z), 36.0)
			# Communities bunch into the folds between hills and leave the peaks green.
			var fold := 0.5 + 0.5 * sin(x * 0.021 + 1.3)
			# Too steep to build on where the slope shoots up.
			if y < 78.0 and Layout.hill_y(x, z + 6.0) - y < 9.0 and _rng.randf() < (0.55 + 0.4 * fold) * (1.0 - (y - 36.0) / 55.0):
				var h := _rng.randf_range(3.0, 6.5)
				_tower(Vector3(x + w * 0.5, y + h * 0.5 - 2.0, z), Vector3(w, h + 4.0, _rng.randf_range(5.0, 7.0)), _house_tint(), 1)
			x += w
		z += _rng.randf_range(5.0, 6.5)
