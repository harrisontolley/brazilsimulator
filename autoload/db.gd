extends Node
## Static game data: items, NPC archetypes, vendors, map constants.

const ITEMS := {
	# Weapons. `held` is the Kit.HELD_* shown in the hand. `ko`: a blow to the head can knock
	# someone out. Guns carry `mag` rounds, take `reload` seconds to refill, kick the view up by
	# `recoil`, and a shot to the head kills outright `head_kill` of the time.
	"fists": {"name": "Fists", "type": "weapon", "melee": true, "damage": 12.0, "range": 2.3, "cooldown": 0.45, "spread": 0.0, "intimidation": 1.0, "price": 0, "held": 0, "ko": true},
	"knife": {"name": "Faca", "type": "weapon", "melee": true, "damage": 28.0, "range": 2.1, "cooldown": 0.5, "spread": 0.0, "intimidation": 1.8, "price": 150, "held": 1},
	"pistol": {"name": "Pistol", "type": "weapon", "melee": false, "damage": 34.0, "range": 60.0, "cooldown": 0.35, "spread": 0.035, "intimidation": 2.5, "price": 400, "held": 2, "mag": 12, "reload": 1.4, "recoil": 0.03, "head_kill": 0.85},
	"revolver": {"name": "Três-oitão", "type": "weapon", "melee": false, "damage": 55.0, "range": 70.0, "cooldown": 0.6, "spread": 0.02, "intimidation": 2.8, "price": 900, "held": 3, "mag": 6, "reload": 2.2, "recoil": 0.065, "head_kill": 1.0},
	"smg": {"name": "Submetralhadora", "type": "weapon", "melee": false, "damage": 16.0, "range": 45.0, "cooldown": 0.09, "spread": 0.06, "intimidation": 3.0, "price": 1500, "held": 4, "mag": 30, "reload": 2.0, "recoil": 0.016, "head_kill": 0.45},
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
## What the two weapon keys cycle through.
const MELEE := ["fists", "knife"]
const GUNS := ["pistol", "revolver", "smg"]
## A head shot that does not kill outright still does this much more.
const HEAD_MULT := 2.5
# What came of a hit, as sent in Game.cl_fx.
const FX_HEAD := 1
const FX_KILL := 2
const FX_KO := 4
const TOLERANCE_PER_DOSE := 0.45
const TOLERANCE_DECAY := 0.02

## resistance: loudness needed before intimidation builds. fight: chance to turn on you.
## shoot: chance a fighter pulls a gun. gun: chance to hand over a pistol when robbed.
const ARCHETYPES := [
	{"id": "tourist", "weight": 0.5, "money": [30, 120], "resistance": 0.15, "fight": 0.0, "shoot": 0.0, "gun": 0.0, "hp": 40.0, "melee": 0.0, "scale": 1.0, "width": 1.0},
	{"id": "local", "weight": 0.38, "money": [5, 60], "resistance": 0.3, "fight": 0.2, "shoot": 0.0, "gun": 0.0, "hp": 60.0, "melee": 8.0, "scale": 0.97, "width": 0.97},
	{"id": "mafia", "weight": 0.12, "money": [400, 1500], "resistance": 0.65, "fight": 0.7, "shoot": 0.5, "gun": 0.35, "hp": 120.0, "melee": 16.0, "scale": 1.15, "width": 1.45},
	# Never rolled: these are placed where they belong.
	{"id": "vendor", "weight": 0.0, "money": [60, 220], "resistance": 0.25, "fight": 0.1, "shoot": 0.0, "gun": 0.0, "hp": 50.0, "melee": 8.0, "scale": 1.0, "width": 1.0},
	{"id": "malandro", "weight": 0.0, "money": [80, 300], "resistance": 0.55, "fight": 0.95, "shoot": 0.15, "gun": 0.3, "hp": 90.0, "melee": 13.0, "scale": 1.02, "width": 1.1},
	{"id": "traficante", "weight": 0.0, "money": [250, 900], "resistance": 0.6, "fight": 0.9, "shoot": 0.85, "gun": 0.6, "hp": 100.0, "melee": 14.0, "scale": 1.05, "width": 1.15},
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
	{"name": "ARMS", "kind": "shop", "pos": Vector3(80, 0, 47), "stock": ["knife", "pistol", "revolver", "smg", "ammo"], "color": Color(0.25, 0.25, 0.3)},
	{"name": "QUIOSQUE 1", "kind": "shop", "till": true, "pos": Vector3(-240, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 2", "kind": "shop", "till": true, "pos": Vector3(-150, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "QUIOSQUE 3", "kind": "shop", "till": true, "pos": Vector3(10, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 4", "kind": "shop", "till": true, "pos": Vector3(170, 0, 47), "stock": FOOD, "color": Color(0.2, 0.55, 0.85)},
	{"name": "QUIOSQUE 5", "kind": "shop", "till": true, "pos": Vector3(250, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(130, 0, 47), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(-70, 0, 107.0), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "BOCA", "kind": "shop", "discount": 0.7, "pos": BOCA_POS, "stock": ["cocaine", "weed", "meth"], "color": Color(0.2, 0.7, 0.3)},
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
const BOCA_POS := Vector3(-120, 12.2, 162.5)
## Samba circles on the promenade.
const RODAS := [Vector3(40, 0, 45.5), Vector3(-195, 0, 45.5), Vector3(215, 0, 45.5)]
const CAMPINHO_POS := Vector3(-46, 15, 172.5)
const JAIL_TIME := 30.0
## Where a hit landed.
const ZONE_BODY := 0
const ZONE_HEAD := 1
## A bare fist to the head puts someone out cold this often, and for how long.
const KO_CHANCE := 0.45
const KO_NPC := 25.0
const KO_COP := 12.0
const KO_PLAYER := 3.5
const KO_IMMUNE := 8.0
## Places to hide: how likely a cop searching right beside one is to look inside it.
const HIDE_KINDS := {
	"cacamba": {"name": "the dumpster", "find": 0.25},
	"carro": {"name": "under the car", "find": 0.1},
	"quiosque": {"name": "behind the counter", "find": 0.2},
	"barraca": {"name": "the beach tent", "find": 0.2},
	"barco": {"name": "under the boat", "find": 0.15},
	"armario": {"name": "the cupboard", "find": 0.1},
	"portal": {"name": "the doorway", "find": 0.35},
}
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


static func is_gun(item: String) -> bool:
	return GUNS.has(item)


## Distance along ray (o, d) at which it passes nearest the segment a-b, or -1 if it never
## comes within `radius` of it. A capsule test for a body that is not a ball.
static func ray_segment(o: Vector3, d: Vector3, a: Vector3, b: Vector3, radius: float, max_t: float) -> float:
	var ab := b - a
	var ao := o - a
	var dd := ab.dot(d)
	var len2 := ab.length_squared()
	var denom := len2 - dd * dd
	# s: how far along the body the nearest point is.
	var s := 0.5
	if denom > 0.0001:
		s = clampf((ab.dot(ao) - dd * d.dot(ao)) / denom, 0.0, 1.0)
	return ray_point(o, d, a + ab * s, radius, max_t)


## Distance along ray (o, d) to the point nearest c, or -1 if the ray misses a sphere of `radius`.
static func ray_point(o: Vector3, d: Vector3, c: Vector3, radius: float, max_t: float) -> float:
	var t := (c - o).dot(d)
	if t < 0.0 or t > max_t:
		return -1.0
	if (o + d * t).distance_squared_to(c) > radius * radius:
		return -1.0
	return t
