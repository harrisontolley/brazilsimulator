extends RefCounted
## Where things are, for anyone who needs to ask: rooms you can walk into, places to hide,
## cover, seats. The world fills it in as it builds; nothing here is networked, because every
## peer builds the same world.

const Nav := preload("res://scenes/world/nav.gd")

## {name, box: AABB, public: AABB, doors: [[outside, inside]], cops: bool, lit: Node3D}
static var rooms: Array = []
## {pos, kind (DB.HIDE_KINDS key), exit (where you climb back out), room}
static var hides: Array = []
## {box: AABB, mult, crouch: bool}: standing in `box` shortens how far away you can be seen.
static var covers: Array = []
## {pos, yaw, room, table}
static var seats: Array = []
## {pos, yaw, poses, arch, room}: somewhere a person stands, and the things they do there.
static var spots: Array = []
## {kind, pos, prompt, arg, hold, jail}: something to use with F that the world put there.
## jail: 0 for people at large, 1 for inmates, 2 for anyone.
static var uses: Array = []
## {pos, r, depth}: holes dug in the sand. These come and go with the match, so the crowd's
## activity planner owns the list rather than the world.
static var pits: Array = []
## {pos, yaw, idle, arch, opts}: people added to the crowd after everybody else, so that
## putting them there changes nobody who was already in it. Whoever asked for them is the
## one who tells them what to do.
static var stands: Array = []
## {pos (foot of it, against the wall), top (y of the roof), out (the way off the wall)}: rungs
## to climb with forward, up to a roof.
static var ladders: Array = []
## Steel doors in the alleys where a hauled body is handed over for ransom (see becos.gd).
static var cells: Array = []

static var _tables := 0

## The two ends of a doorway are closer together than this, so someone walking through never
## finds themselves between them and unsure which way they were going.
const DOOR_REACH := 1.7


static func clear() -> void:
	rooms.clear()
	hides.clear()
	covers.clear()
	seats.clear()
	spots.clear()
	uses.clear()
	stands.clear()
	ladders.clear()
	cells.clear()
	_tables = 0


static func add_room(room: Dictionary) -> int:
	rooms.append(room)
	# A room is somewhere to go into, not a short cut to the next street.
	Nav.add_cost(room.box, 5.0)
	return rooms.size() - 1


static func add_hide(pos: Vector3, kind: String, exit: Vector3, room := -1) -> int:
	hides.append({"pos": pos, "kind": kind, "exit": exit, "room": room})
	return hides.size() - 1


static func add_cover(box: AABB, mult: float, crouch: bool) -> void:
	covers.append({"box": box, "mult": mult, "crouch": crouch})


static func add_seat(pos: Vector3, yaw: float, room := -1, table := -1) -> int:
	seats.append({"pos": pos, "yaw": yaw, "room": room, "table": table})
	return seats.size() - 1


## `opts` goes straight into the crowd's own description of whoever stands here: `stay`
## (never goes home), `afloat` (nowhere to walk to), `gun` (a Kit.HELD_* carried openly).
static func add_spot(pos: Vector3, yaw: float, poses: Array, arch := "", room := -1, opts := {}) -> void:
	spots.append({"pos": pos, "yaw": yaw, "poses": poses, "arch": arch, "room": room, "opts": opts})


static func add_stand(pos: Vector3, yaw: float, idle: int, arch := "", opts := {}) -> void:
	stands.append({"pos": pos, "yaw": yaw, "idle": idle, "arch": arch, "opts": opts})


static func add_use(kind: StringName, pos: Vector3, prompt: String, arg := 0, hold := 0.0, jail := 0) -> void:
	uses.append({"kind": kind, "pos": pos, "prompt": prompt, "arg": arg, "hold": hold, "jail": jail})


static func add_ladder(pos: Vector3, top: float, out: Vector3) -> int:
	ladders.append({"pos": pos, "top": top, "out": out})
	return ladders.size() - 1


## The ladder whose foot or top p is at, as [index, true if at the top], or [].
static func ladder_near(p: Vector3, r: float) -> Array:
	for i in ladders.size():
		var l: Dictionary = ladders[i]
		var base: Vector3 = l.pos + l.out * 0.45
		if absf(p.x - base.x) < r and absf(p.z - base.z) < r:
			if p.y < 1.4 and p.y > -0.5:
				return [i, false]
			if absf(p.y - l.top) < 0.8:
				return [i, true]
	return []


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
		return door[0] if from.distance_to(door[1]) < DOOR_REACH else door[1]
	var door: Array = _door(b, from)
	if from.distance_to(door[0]) < DOOR_REACH:
		return door[1]
	return street.call(from, door[0])


static func _door(i: int, toward: Vector3) -> Array:
	var best: Array = rooms[i].doors[0]
	for d in rooms[i].doors:
		if d[0].distance_squared_to(toward) < best[0].distance_squared_to(toward):
			best = d
	return best
