extends "res://scenes/world/world_kit.gd"
## The alleys: lanes 3.2 m wide cut through the two building rows (Layout.ALLEY_X and
## ALLEY_B_X), and the rooftops they are between.
##
## City builds the buildings with the gaps left in them and tells this who is next to each
## gap. Everything here is dressing, climbing and people: laundry lines and gas bottles,
## ladders up to the lajes, planks across, parties and pigeons on the roofs, old men at
## dominoes, and three bocas run by the facção (soldiers, a lookout and a dealer who sells
## anything). Nothing here is networked: every peer builds the same lanes from fixed seeds.

const Kit := preload("res://scenes/characters/char_kit.gd")
const Places := preload("res://scenes/world/places.gd")

const BRICK := Color(0.66, 0.36, 0.26)
const PLASTER := Color(0.78, 0.74, 0.66)
const RUST := Color(0.42, 0.24, 0.18)
const DARK := Color(0.14, 0.15, 0.17)
const STEEL := Color(0.62, 0.64, 0.67)
const CLOTHES := [Color(0.9, 0.2, 0.2), Color(0.95, 0.85, 0.2), Color(0.2, 0.55, 0.9), Color(0.95, 0.95, 0.95), Color(0.2, 0.75, 0.4), Color(0.9, 0.5, 0.15)]
const TAGS := ["SÓ OS FORTES", "COMUNIDADE", "PROIBIDO PASSAR", "RIO 40°", "PAZ", "SAUDADE", "É NÓIS", "FAVELA VIVE", "AMOR", "SEM LEI", "FÉ"]
## Where the three bocas are: [row band (1 front, 3 back), alley x]. Index is the crew.
const BOCAS := [[3, -180.0], [3, 150.0], [1, 80.0]]
## Roofs this low or lower have a ladder, planks and furniture on them.
const CLIMBABLE := 14.0

## Filled in by City: per band, the buildings it made as [x, width, height].
var plots := {1: [], 3: []}

## Everyone who asks: [{band, x, z0, z1, mouth, vendor, stands: [crowd index], ...}]
static var bocas: Array = []
## Where planks were laid across a lane, for anyone who wants to look at one.
static var planks: Array = []

var _rng := RandomNumberGenerator.new()
var _bricks := 0


## Puts somebody at `at`, or the nearest spot along the lane where nothing is in the way.
## `force` places them regardless, for people the rest of the code counts on being there.
func _stand(at: Vector3, yaw: float, idle: int, arch: String, opts: Dictionary, force := false) -> void:
	if at.y < 0.5:
		var spot := at
		var found := false
		for off in [0.0, 0.6, -0.6, 1.2, -1.2, 1.8, -1.8]:
			var q := at + Vector3(0, 0, off)
			if not Nav.blocked(q):
				spot = q
				found = true
				break
		if not found and not force:
			return
		at = spot
	Places.add_stand(at, yaw, idle, arch, opts)


func _ready() -> void:
	_rng.seed = 5150
	bocas.clear()
	planks.clear()
	_init_kit()
	var lit := 0
	for band in [1, 3]:
		var xs: Array = Layout.ALLEY_X if band == 1 else Layout.ALLEY_B_X
		for cx in xs:
			_alley(band, cx, lit)
			lit += 1
	_cells()
	_parties()
	_flush()


## Z extent of an alley in band `band`.
func _span(band: int) -> Vector2:
	return Vector2(Layout.BLOCK_A_Z, Layout.RUA_Z) if band == 1 else Vector2(Layout.BLOCK_B_Z, Layout.FOOT_Z)


## The roof height of the building that ends at x (its x1) or starts at x (its x0) in `band`,
## or -1.0 when it is not one of ours or is a tower nobody climbs.
func _roof_at(band: int, x: float, east_side: bool) -> float:
	for p in plots[band]:
		var edge: float = p[0] + p[1] * 0.5 if not east_side else p[0] - p[1] * 0.5
		if absf(edge - x) < 0.3:
			return p[2]
	return -1.0


func _alley(band: int, cx: float, index: int) -> void:
	var z := _span(band)
	var length := z.y - z.x
	var zc := (z.x + z.y) * 0.5
	var crew := -1
	for k in BOCAS.size():
		if BOCAS[k][0] == band and BOCAS[k][1] == cx:
			crew = k
	# Floor: darker than the street, with a gutter down the middle that never quite dries.
	_plane(Vector3(cx, 0.035, zc), Vector2(Layout.ALLEY_HALF * 2.0, length), _mat(Color(0.3, 0.29, 0.28)))
	_box(Vector3(cx, 0.045, zc), Vector3(0.3, 0.02, length), Color(0.1, 0.11, 0.12))
	for k in _rng.randi_range(1, 3):
		_box(Vector3(cx + _rng.randf_range(-0.5, 0.5), 0.05, z.x + _rng.randf_range(3.0, length - 3.0)), Vector3(_rng.randf_range(0.6, 1.2), 0.01, _rng.randf_range(0.6, 1.4)), Color(0.07, 0.08, 0.1))

	for side in [-1.0, 1.0]:
		var wall_x: float = cx + side * Layout.ALLEY_HALF
		var into: float = -side
		# Pipes, meters and wall units: nothing the walkway needs.
		for k in 2:
			_box(Vector3(wall_x + into * 0.1, 4.5, z.x + _rng.randf_range(2.0, length - 2.0)), Vector3(0.14, 9.0, 0.14), DARK)
		for k in _rng.randi_range(2, 4):
			var az := z.x + _rng.randf_range(2.0, length - 2.0)
			var ay := _rng.randf_range(3.0, 9.0)
			_box(Vector3(wall_x + into * 0.3, ay, az), Vector3(0.6, 0.5, 0.6), Color(0.85, 0.85, 0.82))
			_box(Vector3(wall_x + into * 0.3, ay - 0.45, az), Vector3(0.05, 0.4, 0.05), Color(0.2, 0.3, 0.4))
		var mz := z.x + _rng.randf_range(2.0, length - 2.0)
		_box(Vector3(wall_x + into * 0.1, 2.6, mz), Vector3(0.3, 0.5, 0.4), Color(0.55, 0.57, 0.58))
		# A single bulb on a bracket, the only light there is after dark.
		var lz := z.x + length * _rng.randf_range(0.3, 0.7)
		_box(Vector3(wall_x + into * 0.2, 4.4, lz), Vector3(0.4, 0.06, 0.06), DARK)
		_glow(Vector3(wall_x + into * 0.45, 4.3, lz), Vector3(0.18, 0.22, 0.18), Color(1.0, 0.85, 0.5))
		# Gas bottles, crates and bins pushed to the sides, never the middle.
		for k in _rng.randi_range(1, 3):
			var pz := z.x + _rng.randf_range(2.5, length - 2.5)
			var px: float = wall_x + into * 0.42
			match _rng.randi() % 4:
				0:
					_block(Vector3(px, 0.3, pz), Vector3(0.56, 0.6, 0.56), Color(0.9, 0.55, 0.12))
				1:
					_block(Vector3(px, 0.35, pz), Vector3(0.7, 0.7, 0.7), WOOD.darkened(0.15))
					if _rng.randf() < 0.5:
						_block(Vector3(px, 0.9, pz), Vector3(0.55, 0.4, 0.55), WOOD)
				2:
					_block(Vector3(px, 0.45, pz), Vector3(0.62, 0.9, 0.62), Color(0.22, 0.4, 0.28))
				_:
					# Bags of rubbish piled up against the wall.
					for b in 3:
						_box(Vector3(px + _rng.randf_range(-0.1, 0.1), 0.2 + b * 0.22, pz + (b - 1) * 0.35), Vector3(0.55, 0.4, 0.4), Color(0.08, 0.08, 0.1))
		if _rng.randf() < 0.6:
			var tag: String = TAGS[_rng.randi() % TAGS.size()]
			var gz := z.x + _rng.randf_range(3.0, length - 3.0)
			_sign(tag, Vector3(wall_x + into * 0.02, _rng.randf_range(1.5, 2.2), gz), 80, Color.from_hsv(_rng.randf(), 0.85, 1.0), -PI / 2.0 * side)

	# Washing lines across, high enough to walk under, with the day's wash on them.
	for k in _rng.randi_range(2, 3):
		var lz := z.x + length * (0.15 + 0.3 * k) + _rng.randf_range(-1.0, 1.0)
		var ly := _rng.randf_range(4.0, 6.0)
		_box(Vector3(cx, ly, lz), Vector3(Layout.ALLEY_HALF * 2.0, 0.025, 0.025), Color(0.85, 0.85, 0.85), Vector3(0, 0, _rng.randf_range(-0.05, 0.05)))
		for c in _rng.randi_range(3, 5):
			_box(Vector3(cx - 1.2 + c * 0.55, ly - 0.35, lz), Vector3(0.45, 0.6, 0.04), CLOTHES[_rng.randi() % CLOTHES.size()])
	# Wires, cut across at the angle somebody's cousin did the installation.
	for k in 3:
		var wz := z.x + _rng.randf_range(2.0, length - 2.0)
		_box(Vector3(cx, _rng.randf_range(6.5, 9.0), wz), Vector3(Layout.ALLEY_HALF * 2.0, 0.03, 0.03), DARK, Vector3(0, _rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.1, 0.1)))

	# A heap of bricks: take one, it makes a good weapon.
	if _rng.randf() < 0.55 or crew >= 0:
		var bz := z.x + _rng.randf_range(4.0, length - 4.0)
		var bx := cx + (1.1 if _rng.randf() < 0.5 else -1.1)
		for b in 6:
			_box(Vector3(bx + _rng.randf_range(-0.3, 0.3), 0.07 + (b / 4) * 0.13, bz + _rng.randf_range(-0.3, 0.3)), Vector3(0.22, 0.12, 0.1), BRICK.darkened(_rng.randf_range(0.0, 0.3)), Vector3(0, _rng.randf() * TAU, 0))
		Places.add_use(&"brick", Vector3(bx, 0.0, bz), "pick up a brick", _bricks)
		_bricks += 1

	if band == 1 and cx == -178.0:
		_junk(cx, z)
	_ladders(band, cx, z)
	if crew >= 0:
		# The crew are the only people in a boca's lane.
		_boca(crew, band, cx, z)
	else:
		_people(band, cx, z, crew, index)


## The ferro-velho: a heap of pans, pipes and tyres against the wall, and the old man who sells it.
func _junk(cx: float, z: Vector2) -> void:
	var at := Vector3(cx + 1.1, 0.0, 90.0)
	_block(Vector3(at.x, 0.4, at.z), Vector3(0.9, 0.8, 1.6), Color(0.38, 0.3, 0.24))
	for k in 5:
		_box(Vector3(at.x - 0.2, 0.9 + k * 0.05, at.z - 0.6 + k * 0.3), Vector3(0.3, 0.04, 0.3), Color(0.1, 0.1, 0.11))
		_box(Vector3(at.x - 0.2, 0.93 + k * 0.05, at.z - 0.6 + k * 0.3 + 0.28), Vector3(0.04, 0.04, 0.3), Color(0.1, 0.1, 0.11))
	for k in 4:
		_box(Vector3(at.x + 0.25, 0.25 + k * 0.12, at.z + 0.6 - k * 0.1), Vector3(0.5, 0.2, 0.5), Color(0.09, 0.09, 0.1))
	_sign("FERRO-VELHO", Vector3(cx + 1.58, 2.3, 90.0), 80, Color(0.95, 0.8, 0.3), -PI / 2.0)
	_stand(Vector3(cx - 0.6, 0.0, 90.0), Kit.face(Vector3(1, 0, 0)), Kit.STAND, "velho", {}, true)


# --- up to the roofs ---

## Rungs up the walls of low buildings on either side, and a plank over when both roofs are level.
func _ladders(band: int, cx: float, z: Vector2) -> void:
	var left := _roof_at(band, cx - Layout.ALLEY_HALF, false)
	var right := _roof_at(band, cx + Layout.ALLEY_HALF, true)
	var mid := (z.x + z.y) * 0.5
	var made := 0
	for side in [[-1.0, left], [1.0, right]]:
		var h: float = side[1]
		if h < 3.0 or h > CLIMBABLE or made >= 1 and _rng.randf() < 0.5:
			continue
		var wall_x: float = cx + side[0] * Layout.ALLEY_HALF
		var out := Vector3(-side[0], 0, 0)
		var lz := mid + _rng.randf_range(-4.0, 4.0)
		for rail in [-0.22, 0.22]:
			_box(Vector3(wall_x + out.x * 0.02, h * 0.5, lz + rail), Vector3(0.05, h, 0.05), STEEL)
		for k in int(h / 0.38):
			_box(Vector3(wall_x + out.x * 0.02, 0.3 + k * 0.38, lz), Vector3(0.05, 0.04, 0.46), STEEL.darkened(0.15))
		Places.add_ladder(Vector3(wall_x, 0.0, lz), h, out)
		made += 1
	if left > 0.0 and absf(left - right) < 0.1 and left <= CLIMBABLE and _rng.randf() < 0.75:
		var pz := mid + _rng.randf_range(-6.0, 6.0)
		_block(Vector3(cx, left + 0.06, pz), Vector3(Layout.ALLEY_HALF * 2.0 + 1.6, 0.12, 0.8), WOOD.darkened(0.2))
		planks.append(Vector3(cx, left + 0.06, pz))
	# Furniture on the roofs either side.
	for roof in [[-1.0, left], [1.0, right]]:
		var h: float = roof[1]
		if h < 3.0 or h > CLIMBABLE:
			continue
		var rx: float = cx + roof[0] * (Layout.ALLEY_HALF + 2.5)
		var rz := z.x + _rng.randf_range(4.0, z.y - z.x - 4.0)
		match _rng.randi() % 3:
			0:
				# Plastic chairs round a table under a faded parasol.
				_box(Vector3(rx, h + 0.7, rz), Vector3(0.9, 0.06, 0.9), Color(0.95, 0.95, 0.95))
				_box(Vector3(rx, h + 0.35, rz), Vector3(0.1, 0.7, 0.1), STEEL)
				for c in 3:
					_box(Vector3(rx + cos(c * 2.1) * 0.9, h + 0.25, rz + sin(c * 2.1) * 0.9), Vector3(0.4, 0.5, 0.4), CLOTHES[_rng.randi() % CLOTHES.size()])
				_box(Vector3(rx, h + 2.3, rz), Vector3(2.2, 0.08, 2.2), CLOTHES[_rng.randi() % CLOTHES.size()])
				_box(Vector3(rx, h + 1.2, rz), Vector3(0.06, 2.4, 0.06), STEEL)
			1:
				# The pigeon coop: a wire box on legs, and the birds that go with it.
				_box(Vector3(rx, h + 0.9, rz), Vector3(1.6, 1.2, 1.0), Color(0.5, 0.42, 0.3))
				_box(Vector3(rx, h + 1.55, rz), Vector3(1.8, 0.1, 1.2), RUST)
				for b in 4:
					_box(Vector3(rx - 0.5 + b * 0.35, h + 1.68, rz + _rng.randf_range(-0.3, 0.3)), Vector3(0.18, 0.14, 0.12), Color(0.7, 0.72, 0.75))
			_:
				# Washing, again: this one is somebody's whole wardrobe.
				for c in 6:
					_box(Vector3(rx - 1.5 + c * 0.6, h + 1.7, rz), Vector3(0.45, 0.7, 0.04), CLOTHES[_rng.randi() % CLOTHES.size()])
				for e in [-1.8, 1.8]:
					_box(Vector3(rx + e, h + 1.0, rz), Vector3(0.05, 2.0, 0.05), STEEL)
				_box(Vector3(rx, h + 2.0, rz), Vector3(3.6, 0.025, 0.025), Color(0.85, 0.85, 0.85))


# --- who lives here ---

## A few people to find in the lane, picked from what goes on in lanes.
func _people(band: int, cx: float, z: Vector2, crew: int, index: int) -> void:
	var n := _rng.randi_range(0, 3)
	for k in n:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var pz := z.x + _rng.randf_range(5.0, z.y - z.x - 5.0)
		var at := Vector3(cx + side * 1.05, 0.0, pz)
		var face := Kit.face(Vector3(-side, 0, 0))
		match _rng.randi() % 8:
			0:
				_stand(at, face, Kit.SMOKE, "local", {})
			1:
				_stand(at, face, Kit.LEAN, "malandro", {})
			2:
				_stand(at, face, Kit.BEG, "local", {})
			3:
				_stand(Vector3(cx, 0.0, pz), PI * 0.5, Kit.SWEEP, "velho", {})
			4:
				# Two on a doorstep arguing about football.
				_stand(at, Kit.face(Vector3(0, 0, 1)), Kit.TALK, "velho", {})
				_stand(at + Vector3(0, 0, 1.0), Kit.face(Vector3(0, 0, -1)), Kit.ARGUE, "velho", {})
			5:
				# Kids at keepy-uppies where the cars cannot get.
				_stand(Vector3(cx - 0.5, 0.0, pz), Kit.face(Vector3(1, 0, 0)), Kit.KEEPUP, "olheiro", {})
				_stand(Vector3(cx + 0.7, 0.0, pz), Kit.face(Vector3(-1, 0, 0)), Kit.CHEER, "olheiro", {})
			6:
				_stand(at, face, Kit.SQUAT, "local", {})
			_:
				_stand(at, face, Kit.PREACH, "local", {})


## A boca: soldiers with rifles, the lookout at the mouth, the dealer in the middle, a
## speaker and a chair to sit on while they wait.
func _boca(crew: int, band: int, cx: float, z: Vector2) -> void:
	var mid := (z.x + z.y) * 0.5
	var mouth_z: float = z.x + 1.5 if band == 3 else z.y - 1.5
	var inner_z: float = z.y - 1.5 if band == 3 else z.x + 1.5
	var vendor: Vector3 = DB.VENDORS[DB.VENDORS.size() - 3 + crew].pos
	var stands: Array = []
	var face_mouth := Kit.face(Vector3(0, 0, mouth_z - mid))
	var first := Places.stands.size()
	# The dealer's table, and what is on it.
	_block(Vector3(cx - 0.9, 0.45, vendor.z), Vector3(0.8, 0.9, 1.4), WOOD.darkened(0.25))
	_box(Vector3(cx - 0.9, 0.93, vendor.z), Vector3(0.9, 0.05, 1.5), WOOD)
	for k in 6:
		_box(Vector3(cx - 0.9 + _rng.randf_range(-0.25, 0.25), 0.99, vendor.z + _rng.randf_range(-0.6, 0.6)), Vector3(0.12, 0.08, 0.12), Color.from_hsv(_rng.randf(), 0.5, 1.0))
	# A speaker as tall as a person, and a glow from a coal grill.
	_block(Vector3(cx + 1.2, 0.7, mid - 4.5), Vector3(0.5, 1.4, 0.5), DARK)
	_box(Vector3(cx + 1.2, 1.15, mid - 4.5 - 0.26), Vector3(0.3, 0.3, 0.02), Color(0.3, 0.3, 0.32))
	_glow(Vector3(cx - 1.2, 0.8, mid + 4.5), Vector3(0.4, 0.04, 0.4), Color(1.0, 0.45, 0.12))
	_block(Vector3(cx - 1.2, 0.35, mid + 4.5), Vector3(0.5, 0.7, 0.5), Color(0.2, 0.2, 0.22))
	# Their name on both walls, and a skull.
	for side in [-1.0, 1.0]:
		_sign("PROIBIDO PASSAR\n☠", Vector3(cx + side * 1.58, 2.4, mid), 110, Color(0.95, 0.15, 0.1), -PI / 2.0 * side)

	# Two soldiers either side of the dealer, rifles in the open.
	_stand(Vector3(cx - 1.0, 0.0, mid - 2.5), face_mouth, Kit.LEAN, "traficante", {"gun": Kit.HELD_RIFLE}, true)
	_stand(Vector3(cx + 1.0, 0.0, mid + 2.5), face_mouth, Kit.STAND, "traficante", {"gun": Kit.HELD_RIFLE}, true)
	_stand(Vector3(cx + 0.9, 0.0, vendor.z), Kit.face(Vector3(-1, 0, 0)), Kit.STAND, "vapor", {}, true)
	# The lookout sits by the mouth with a radio, and a third soldier holds the far end.
	_stand(Vector3(cx - 1.0, 0.0, mouth_z), Kit.face(Vector3(0, 0, mouth_z - mid)), Kit.SQUAT, "olheiro", {}, true)
	_stand(Vector3(cx, 0.0, inner_z), face_mouth, Kit.STAND, "traficante", {"gun": Kit.HELD_RIFLE}, true)
	for k in 5:
		stands.append(first + k)
	bocas.append({"crew": crew, "band": band, "x": cx, "z0": z.x, "z1": z.y, "mouth": Vector3(cx, 0.0, mouth_z),
			"dealer": vendor, "stands": stands, "first": first})


# --- ransom ---

## Two steel doors where a hauled body is taken for ransom.
func _cells() -> void:
	for spec in [[1, 32.0, 90.0, -1.0], [3, 75.0, 125.0, 1.0]]:
		var cx: float = spec[1]
		var cz: float = spec[2]
		var side: float = spec[3]
		var wall_x: float = cx + side * Layout.ALLEY_HALF
		var into: float = -side
		_box(Vector3(wall_x + into * 0.04, 1.1, cz), Vector3(0.08, 2.2, 1.1), Color(0.18, 0.2, 0.24))
		_box(Vector3(wall_x + into * 0.1, 1.0, cz), Vector3(0.06, 0.16, 0.5), Color(0.5, 0.5, 0.52))
		_box(Vector3(wall_x + into * 0.12, 1.15, cz + 0.3), Vector3(0.1, 0.14, 0.1), Color(0.8, 0.65, 0.1))
		_glow(Vector3(wall_x + into * 0.15, 2.5, cz), Vector3(0.14, 0.14, 0.14), Color(1.0, 0.1, 0.05))
		_sign("ENTREGA", Vector3(wall_x + into * 0.02, 2.75, cz), 70, Color(0.9, 0.9, 0.9), -PI / 2.0 * side)
		Places.cells.append({"door": Vector3(wall_x + into * 0.8, 0.0, cz), "face": Vector3(into, 0, 0)})


# --- parties ---

## Two roofs with a laje party going: grill, speakers, bulbs and people dancing.
func _parties() -> void:
	var held := 0
	for band in [1, 3]:
		for p in plots[band]:
			if held >= 3 or p[2] < 3.0 or p[2] > CLIMBABLE or absf(p[0]) > 250.0 or _rng.randf() > 0.12:
				continue
			held += 1
			var x: float = p[0]
			var h: float = p[2]
			var zc := 86.0 if band == 1 else 121.0
			# The grill, a cooler, and a speaker stack with bulbs strung over the lot.
			_box(Vector3(x - 2.0, h + 0.5, zc), Vector3(1.0, 0.8, 0.5), Color(0.2, 0.2, 0.22))
			_glow(Vector3(x - 2.0, h + 0.93, zc), Vector3(0.9, 0.04, 0.4), Color(1.0, 0.45, 0.12))
			_box(Vector3(x + 2.0, h + 0.3, zc + 1.0), Vector3(0.9, 0.6, 0.5), Color(0.2, 0.45, 0.8))
			for e in [-1.0, 1.0]:
				_block(Vector3(x + e * 3.0, h + 0.8, zc - 2.0), Vector3(0.6, 1.6, 0.6), DARK)
			for k in 8:
				_glow(Vector3(x - 3.5 + k, h + 2.6 + sin(k) * 0.12, zc), Vector3(0.14, 0.14, 0.14), Color.from_hsv(float(k) / 8.0, 0.8, 1.0))
			_box(Vector3(x, h + 2.7, zc), Vector3(7.5, 0.02, 0.02), DARK)
			for k in 3:
				_stand(Vector3(x - 1.0 + k * 1.2, h, zc + 1.5 - k % 2), Kit.face(Vector3(0, 0, -1)), Kit.DANCE, "local", {"afloat": true})
