extends Node
## Static game data: items, NPC archetypes, vendors, map constants.

const ITEMS := {
	"fists": {"name": "Fists", "type": "weapon", "melee": true, "damage": 12.0, "range": 2.3, "cooldown": 0.45, "spread": 0.0, "intimidation": 1.0, "price": 0},
	"pistol": {"name": "Pistol", "type": "weapon", "melee": false, "damage": 34.0, "range": 60.0, "cooldown": 0.35, "spread": 0.035, "intimidation": 2.5, "price": 400},
	"ammo": {"name": "Ammo x12", "type": "ammo", "amount": 12, "price": 60},
	"cocaine": {"name": "Cocaine", "type": "drug", "key": "drug_1", "duration": 25.0, "comedown": 20.0, "od": 12.0, "price": 150},
	"weed": {"name": "Weed", "type": "drug", "key": "drug_2", "duration": 45.0, "comedown": 0.0, "od": 20.0, "price": 60},
	"meth": {"name": "Meth", "type": "drug", "key": "drug_3", "duration": 40.0, "comedown": 15.0, "od": 20.0, "price": 120},
}
const DRUGS := ["cocaine", "weed", "meth"]
const TOLERANCE_PER_DOSE := 0.45
const TOLERANCE_DECAY := 0.02

## resistance: loudness needed before intimidation builds. fight: chance to turn on you.
## shoot: chance a fighter pulls a gun. gun: chance to hand over a pistol when robbed.
const ARCHETYPES := [
	{"id": "tourist", "weight": 0.5, "money": [30, 120], "resistance": 0.15, "fight": 0.0, "shoot": 0.0, "gun": 0.0, "hp": 40.0, "melee": 0.0, "scale": 1.0, "width": 1.0},
	{"id": "local", "weight": 0.38, "money": [5, 60], "resistance": 0.3, "fight": 0.2, "shoot": 0.0, "gun": 0.0, "hp": 60.0, "melee": 8.0, "scale": 0.97, "width": 0.97},
	{"id": "mafia", "weight": 0.12, "money": [400, 1500], "resistance": 0.65, "fight": 0.7, "shoot": 0.5, "gun": 0.35, "hp": 120.0, "melee": 16.0, "scale": 1.15, "width": 1.45},
]

## Cash an NPC must be carrying to show mid / rich props.
const WEALTH_TIERS := [50, 400]

# Who threw or took a hit, as sent in Game.cl_fx.
const WHO_NONE := 0
const WHO_PLAYER := 1
const WHO_COP := 2
const WHO_NPC := 3

const VENDORS := [
	{"name": "DEALER", "pos": Vector3(-60, 0, 47), "stock": ["cocaine", "weed", "meth"]},
	{"name": "ARMS", "pos": Vector3(80, 0, 47), "stock": ["pistol", "ammo"]},
]

const PRISON_POS := Vector3(0, 0.2, 150)
const RELEASE_POS := Vector3(0, 0.2, 46)
const JAIL_TIME := 30.0
const RESPAWN_TIME := 4.0


## Footprints of the solid beach props, filled in by the world when it builds them.
static var solids: Array[AABB] = []


static func spawn_point() -> Vector3:
	var p := Vector3.ZERO
	for i in 16:
		p = Vector3(randf_range(-270.0, 270.0), 0.2, randf_range(-30.0, 34.0))
		if clear_of_solids(p, 1.0) == p:
			break
	return p


## Moves p sideways out of any solid prop it sits under or inside.
static func clear_of_solids(p: Vector3, margin: float) -> Vector3:
	for s in solids:
		var lo := s.position - Vector3(margin, 0, margin)
		var hi := s.end + Vector3(margin, 0, margin)
		if p.x <= lo.x or p.x >= hi.x or p.z <= lo.z or p.z >= hi.z:
			continue
		var dx := lo.x - p.x if p.x - lo.x < hi.x - p.x else hi.x - p.x
		var dz := lo.z - p.z if p.z - lo.z < hi.z - p.z else hi.z - p.z
		if absf(dx) < absf(dz):
			p.x += dx
		else:
			p.z += dz
	return p


## 0 poor, 1 mid, 2 rich.
static func wealth_tier(cash: int) -> int:
	return 2 if cash >= WEALTH_TIERS[1] else (1 if cash >= WEALTH_TIERS[0] else 0)


## Distance along ray (o, d) to the point nearest c, or -1 if the ray misses a sphere of `radius`.
static func ray_point(o: Vector3, d: Vector3, c: Vector3, radius: float, max_t: float) -> float:
	var t := (c - o).dot(d)
	if t < 0.0 or t > max_t:
		return -1.0
	if (o + d * t).distance_squared_to(c) > radius * radius:
		return -1.0
	return t
