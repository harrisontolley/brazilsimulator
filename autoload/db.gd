extends Node
## Static game data: items, NPC archetypes, vendors, map constants.

const ITEMS := {
	"fists": {"name": "Fists", "type": "weapon", "melee": true, "damage": 12.0, "range": 2.3, "cooldown": 0.45, "spread": 0.0, "intimidation": 1.0, "price": 0},
	"pistol": {"name": "Pistol", "type": "weapon", "melee": false, "damage": 34.0, "range": 60.0, "cooldown": 0.35, "spread": 0.035, "intimidation": 2.5, "price": 400},
	"ammo": {"name": "Ammo x12", "type": "ammo", "amount": 12, "price": 60},
	"cocaine": {"name": "Cocaine", "type": "drug", "key": "drug_1", "duration": 25.0, "comedown": 20.0, "od": 12.0, "price": 150},
	"weed": {"name": "Weed", "type": "drug", "key": "drug_2", "duration": 45.0, "comedown": 0.0, "od": 20.0, "price": 60},
	"meth": {"name": "Meth", "type": "drug", "key": "drug_3", "duration": 40.0, "comedown": 15.0, "od": 20.0, "price": 120},
	# Eaten on the spot. `buff` ones also leave you tipsy for `duration`.
	"coco": {"name": "Água de coco", "type": "food", "heal": 25.0, "price": 15},
	"espetinho": {"name": "Espetinho", "type": "food", "heal": 40.0, "price": 25},
	"acai": {"name": "Açaí", "type": "food", "heal": 70.0, "price": 40},
	"caipirinha": {"name": "Caipirinha", "type": "food", "heal": 10.0, "buff": true, "duration": 45.0, "comedown": 0.0, "od": 0.0, "price": 25},
	# Taken off the people you rob. Worth nothing until a fence buys it; lost if arrested.
	"phone": {"name": "Celular", "type": "loot", "price": 120},
	"watch": {"name": "Relógio", "type": "loot", "price": 180},
	"camera": {"name": "Câmera", "type": "loot", "price": 220},
	"chain": {"name": "Cordão de ouro", "type": "loot", "price": 450},
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

const FOOD := ["coco", "espetinho", "acai", "caipirinha"]
const LOOT := ["phone", "watch", "camera", "chain"]
## kind: "shop" sells `stock` (at `discount`), "bicho" takes bets, "fence" buys loot.
## `till` shops keep cash that can be taken at gunpoint.
const VENDORS := [
	{"name": "DEALER", "kind": "shop", "pos": Vector3(-60, 0, 47), "stock": ["cocaine", "weed", "meth"], "color": Color(0.2, 0.7, 0.3)},
	{"name": "ARMS", "kind": "shop", "pos": Vector3(80, 0, 47), "stock": ["pistol", "ammo"], "color": Color(0.25, 0.25, 0.3)},
	{"name": "QUIOSQUE 1", "kind": "shop", "till": true, "pos": Vector3(-240, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 2", "kind": "shop", "till": true, "pos": Vector3(-150, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "QUIOSQUE 3", "kind": "shop", "till": true, "pos": Vector3(10, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 4", "kind": "shop", "till": true, "pos": Vector3(170, 0, 47), "stock": FOOD, "color": Color(0.2, 0.55, 0.85)},
	{"name": "QUIOSQUE 5", "kind": "shop", "till": true, "pos": Vector3(250, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(130, 0, 47), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(-70, 0, 107.0), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "BOCA", "kind": "shop", "discount": 0.7, "pos": Vector3(-120, 12.2, 162.5), "stock": ["cocaine", "weed", "meth"], "color": Color(0.2, 0.7, 0.3)},
	{"name": "RECEPTADOR", "kind": "fence", "pos": Vector3(212, 6.2, 146.5), "stock": [], "color": Color(0.5, 0.3, 0.6)},
]

## The 25 animals of the jogo do bicho, in their traditional order.
const BICHOS := ["Avestruz", "Águia", "Burro", "Borboleta", "Cachorro", "Cabra", "Carneiro", "Camelo", "Cobra", "Coelho", "Cavalo", "Elefante", "Galo", "Gato", "Jacaré", "Leão", "Macaco", "Porco", "Pavão", "Peru", "Touro", "Tigre", "Urso", "Veado", "Vaca"]
const BICHO_PAYS := 18
const BICHO_EVERY := 60.0
const BETS := [50, 200, 1000]

const PRISON_POS := Vector3(0, 0.2, 121)
const RELEASE_POS := Vector3(0, 0.2, 105)
const BAILE_POS := Vector3(66, 9, 157)
const CAMPINHO_POS := Vector3(-46, 15, 172.5)
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
