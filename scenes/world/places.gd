extends RefCounted
## Where things are, for anyone who needs to ask: rooms you can walk into, places to hide,
## cover, seats. The world fills it in as it builds; nothing here is networked, because every
## peer builds the same world.

## {name, box: AABB, public: AABB, doors: [[outside, inside]], cops: bool, lit: Node3D}
static var rooms: Array = []
## {pos, kind (DB.HIDE_KINDS key), exit (where you climb back out), room}
static var hides: Array = []
## {box: AABB, mult, crouch: bool}: standing in `box` shortens how far away you can be seen.
static var covers: Array = []
## {pos, yaw, room, table}
static var seats: Array = []
## {pos, r, depth}: holes dug in the sand. These come and go with the match, so the crowd's
## activity planner owns the list rather than the world.
static var pits: Array = []

static var _tables := 0


static func clear() -> void:
	rooms.clear()
	hides.clear()
	covers.clear()
	seats.clear()
	_tables = 0


static func add_room(room: Dictionary) -> int:
	rooms.append(room)
	return rooms.size() - 1


static func add_hide(pos: Vector3, kind: String, exit: Vector3, room := -1) -> int:
	hides.append({"pos": pos, "kind": kind, "exit": exit, "room": room})
	return hides.size() - 1


static func add_cover(box: AABB, mult: float, crouch: bool) -> void:
	covers.append({"box": box, "mult": mult, "crouch": crouch})


static func add_seat(pos: Vector3, yaw: float, room := -1, table := -1) -> int:
	seats.append({"pos": pos, "yaw": yaw, "room": room, "table": table})
	return seats.size() - 1


## A fresh id to group the seats round one table.
static func new_table() -> int:
	_tables += 1
	return _tables


## Index of the pit whose mouth p is over, or -1.
static func pit_at(p: Vector3) -> int:
	if p.z > 40.0 or p.y > 0.6:
		return -1
	for i in pits.size():
		var c: Vector3 = pits[i].pos
		var dx := p.x - c.x
		var dz := p.z - c.z
		var r: float = pits[i].r * 0.8
		if dx * dx + dz * dz < r * r:
			return i
	return -1


## How far below the sand someone at p is standing.
static func depth_at(p: Vector3) -> float:
	var i := pit_at(p)
	return pits[i].depth if i >= 0 else 0.0


## Index of the room p is inside, or -1 out of doors.
static func room_at(p: Vector3) -> int:
	for i in rooms.size():
		if rooms[i].box.has_point(p):
			return i
	return -1


## How much of a watcher's range survives the cover at p: 1 in the open, less in the bushes.
static func cover_at(p: Vector3, crouched: bool) -> float:
	var m := 1.0
	for c in covers:
		if (crouched or not c.crouch) and c.box.has_point(p):
			m = minf(m, c.mult)
	return m


## The nearest hiding place within r of p, or -1.
static func hide_near(p: Vector3, r: float) -> int:
	var best := -1
	var best_d := r * r
	for i in hides.size():
		var d: float = hides[i].pos.distance_squared_to(p)
		if d < best_d:
			best = i
			best_d = d
	return best


## Whether someone on foot at street level may stand at p inside room i.
static func in_public(i: int, p: Vector3) -> bool:
	return i >= 0 and rooms[i].public.has_point(Vector3(p.x, rooms[i].public.position.y + 0.1, p.z))


## Next point to walk to on the way from `from` to `to` when either end is indoors: out by
## the door, round by the street, in by the door. Returns `to` when there is nothing in the way.
static func route(from: Vector3, to: Vector3, street: Callable) -> Vector3:
	var a := room_at(from)
	var b := room_at(to)
	if a == b:
		return to if a >= 0 else street.call(from, to)
	if a >= 0:
		# Leave by whichever door is nearest to where we are going.
		var door: Array = _door(a, to)
		return door[0] if from.distance_to(door[1]) < 0.8 else door[1]
	var door: Array = _door(b, from)
	if from.distance_to(door[0]) < 0.8:
		return door[1]
	return street.call(from, door[0])


static func _door(i: int, toward: Vector3) -> Array:
	var best: Array = rooms[i].doors[0]
	for d in rooms[i].doors:
		if d[0].distance_squared_to(toward) < best[0].distance_squared_to(toward):
			best = d
	return best
