extends Node
## Static game data: items, NPC archetypes, vendors, map constants.

const ITEMS := {
	# Weapons. `held` is the Kit.HELD_* shown in the hand. `ko`: a blow to the head can knock
	# someone out. Guns carry `mag` rounds, take `reload` seconds to refill, kick the view up by
	# `recoil`, and a shot to the head kills outright `head_kill` of the time.
	"fists": {"name": "Fists", "type": "weapon", "melee": true, "damage": 12.0, "range": 2.3, "cooldown": 0.45, "spread": 0.0, "intimidation": 1.0, "price": 0, "held": 0, "ko": true},
	"estoque": {"name": "Estoque", "type": "weapon", "melee": true, "damage": 22.0, "range": 2.0, "cooldown": 0.5, "spread": 0.0, "intimidation": 1.6, "price": 80, "held": 1},
	"knife": {"name": "Faca", "type": "weapon", "melee": true, "damage": 28.0, "range": 2.1, "cooldown": 0.5, "spread": 0.0, "intimidation": 1.8, "price": 150, "held": 1},
	"pistol": {"name": "Pistol", "type": "weapon", "melee": false, "damage": 34.0, "range": 60.0, "cooldown": 0.35, "spread": 0.035, "intimidation": 2.5, "price": 400, "held": 2, "mag": 12, "reload": 1.4, "recoil": 0.03, "head_kill": 0.85},
	"revolver": {"name": "Três-oitão", "type": "weapon", "melee": false, "damage": 55.0, "range": 70.0, "cooldown": 0.6, "spread": 0.02, "intimidation": 2.8, "price": 900, "held": 3, "mag": 6, "reload": 2.2, "recoil": 0.065, "head_kill": 1.0},
	"smg": {"name": "Submetralhadora", "type": "weapon", "melee": false, "damage": 16.0, "range": 45.0, "cooldown": 0.09, "spread": 0.06, "intimidation": 3.0, "price": 1500, "held": 4, "mag": 30, "reload": 2.0, "recoil": 0.016, "head_kill": 0.45},
	"ammo": {"name": "Ammo x12", "type": "ammo", "amount": 12, "price": 60},
	# Drugs. `fx` is what each phase does to the body: multipliers on speed, melee damage dealt,
	# damage `taken`, mic loudness, jump height, gravity (`grav`), gun `recoil`, how fast heat
	# cools (`cool`) and how far off a cop picks you out (`seen`); `shake` and `sway` are added
	# to the camera. `screen` is [tint, blur] and `trip` is [hue speed, saturation, wobble].
	# An overdose lasts `od` seconds, costs `od_dmg` hp every half second, puts you on the floor
	# for `od_floor` as it starts, and ends in `od_end` (see Game._srv_od_end). `legal` ones are
	# nothing a cop at a checkpoint cares about.
	"cocaine": {"name": "Cocaine", "type": "drug", "duration": 25.0, "comedown": 20.0, "od": 12.0, "price": 150,
		"fx": {"high": {"speed": 1.6, "melee": 2.0}, "down": {"speed": 0.45, "melee": 0.6}, "od": {"speed": 0.8, "shake": 0.02}},
		"screen": {"high": [Color(1, 1, 1, 0.06), 0.0], "down": [Color(0.2, 0.2, 0.3, 0.3), 0.0], "od": [Color(0.9, 0.0, 0.0, 0.3), 0.0]},
		"od_dmg": 3.0, "od_end": "hospital", "sound": "sniff"},
	"weed": {"name": "Weed", "type": "drug", "duration": 45.0, "comedown": 0.0, "od": 20.0, "price": 60,
		"fx": {"high": {"speed": 0.75, "taken": 0.5}, "od": {"speed": 0.6, "mic": 0.5}},
		"screen": {"high": [Color(0.2, 0.7, 0.2, 0.1), 0.8], "od": [Color(0.1, 0.5, 0.1, 0.3), 3.0]},
		"od_end": "ko", "od_ko": 5.0},
	"meth": {"name": "Meth", "type": "drug", "duration": 40.0, "comedown": 15.0, "od": 20.0, "price": 120,
		"fx": {"down": {"shake": 0.012}, "od": {"shake": 0.04}},
		"screen": {"od": [Color(0.5, 0.3, 0.9, 0.2), 0.0]},
		"od_dmg": 1.5},
	"lanca": {"name": "Lança-perfume", "type": "drug", "duration": 10.0, "comedown": 0.0, "od": 6.0, "price": 40,
		"fx": {"high": {"jump": 1.8, "grav": 0.45}},
		"screen": {"high": [Color(1.0, 0.9, 0.4, 0.08), 0.5], "od": [Color(0, 0, 0, 0.75), 2.0]},
		"od_floor": 6.0, "od_end": "robbed", "sound": "giggle"},
	"bala": {"name": "Bala", "type": "drug", "duration": 40.0, "comedown": 15.0, "od": 25.0, "price": 90,
		"fx": {"high": {"melee": 0.5}, "down": {"speed": 0.8}, "od": {"speed": 0.8}},
		"screen": {"high": [Color(1.0, 0.4, 0.8, 0.06), 0.0], "down": [Color(0.2, 0.2, 0.3, 0.2), 0.0], "od": [Color(1.0, 0.3, 0.0, 0.25), 0.0]},
		"trip": {"high": [0.0, 1.7, 0.0], "od": [0.0, 2.2, 0.4]},
		"od_dmg": 2.0, "od_end": "hospital"},
	"doce": {"name": "Doce", "type": "drug", "duration": 45.0, "comedown": 0.0, "od": 25.0, "price": 110,
		"fx": {},
		"trip": {"high": [0.25, 1.4, 0.6], "od": [0.9, 1.6, 1.0]},
		"od_end": "random"},
	"ayahuasca": {"name": "Ayahuasca", "type": "drug", "duration": 20.0, "comedown": 0.0, "od": 15.0, "price": 130,
		"fx": {},
		"screen": {"high": [Color(0.4, 0.2, 0.7, 0.12), 0.0], "od": [Color(0.4, 0.5, 0.1, 0.25), 1.0]},
		"trip": {"high": [0.0, 1.3, 0.3], "od": [0.0, 0.7, 0.8]},
		"sound": "retch"},
	"bomba": {"name": "Bomba", "type": "drug", "duration": 35.0, "comedown": 15.0, "od": 15.0, "price": 200,
		"fx": {"high": {"melee": 2.5}, "down": {"melee": 0.7, "speed": 0.85}, "od": {"melee": 2.5, "speed": 1.2, "shake": 0.02}},
		"screen": {"high": [Color(1.0, 0.3, 0.1, 0.05), 0.0], "od": [Color(0.9, 0.0, 0.0, 0.3), 0.0]},
		"od_dmg": 4.0},
	"rivotril": {"name": "Rivotril", "type": "drug", "duration": 40.0, "comedown": 0.0, "od": 10.0, "price": 70, "legal": true,
		"fx": {"high": {"cool": 2.5, "seen": 0.7, "recoil": 0.5}},
		"screen": {"high": [Color(0.3, 0.5, 0.9, 0.08), 0.3], "od": [Color(0, 0, 0, 0.85), 2.0]},
		"od_floor": 10.0},
	"ketamine": {"name": "Ketamine", "type": "drug", "duration": 30.0, "comedown": 10.0, "od": 12.0, "price": 100,
		"fx": {"high": {"taken": 0.3, "speed": 0.6, "sway": 0.1}, "down": {"sway": 0.05}, "od": {"sway": 0.15}},
		"screen": {"high": [Color(0.6, 0.6, 0.7, 0.1), 0.6], "od": [Color(0.7, 0.7, 0.8, 0.3), 2.5]},
		"od_floor": 12.0, "od_end": "robbed"},
	"guarana": {"name": "Guaraná em pó", "type": "drug", "duration": 30.0, "comedown": 0.0, "od": 15.0, "price": 20, "legal": true,
		"fx": {"high": {"speed": 1.25, "jump": 1.2}, "od": {"speed": 1.5, "shake": 0.03}},
		"screen": {"od": [Color(1.0, 0.8, 0.0, 0.15), 0.0]},
		"od_end": "ko", "od_ko": 3.0},
	# Eaten on the spot. `buff` ones also leave you tipsy for `duration`.
	"coco": {"name": "Água de coco", "type": "food", "heal": 25.0, "price": 15},
	"espetinho": {"name": "Espetinho", "type": "food", "heal": 40.0, "price": 25},
	"acai": {"name": "Açaí", "type": "food", "heal": 70.0, "price": 40},
	"caipirinha": {"name": "Caipirinha", "type": "food", "heal": 10.0, "buff": true, "duration": 45.0, "comedown": 0.0, "od": 0.0, "price": 25,
		"fx": {"high": {"taken": 0.85, "sway": 0.07}}},
	# Contraband: what a spoon and a rope are for is between you and the wall.
	"colher": {"name": "Colher", "type": "tool", "price": 40},
	"corda": {"name": "Corda", "type": "tool", "price": 90},
	# Not for sale: an hour on the weights.
	"ferro": {"name": "Ferro", "type": "buff", "comedown": 0.0, "fx": {"high": {"melee": 1.3}}},
	"curativo": {"name": "Curativo", "type": "food", "heal": 60.0, "price": 35},
	"cerveja": {"name": "Cerveja", "type": "food", "heal": 8.0, "buff": true, "duration": 30.0, "comedown": 0.0, "od": 0.0, "price": 12,
		"fx": {"high": {"taken": 0.9, "sway": 0.05}}},
	# Taken off the people you rob. Worth nothing until a fence buys it; lost if arrested.
	"phone": {"name": "Celular", "type": "loot", "price": 120},
	"watch": {"name": "Relógio", "type": "loot", "price": 180},
	"camera": {"name": "Câmera", "type": "loot", "price": 220},
	"chain": {"name": "Cordão de ouro", "type": "loot", "price": 450},
}
## In the order they sit along the hotbar.
const DRUGS := ["cocaine", "weed", "meth", "lanca", "bala", "doce", "ayahuasca", "bomba", "rivotril", "ketamine", "guarana"]
## What a drink is: anything here leaves you tipsy.
const DRINKS := ["caipirinha", "cerveja"]
## The bed in the back of the chemist's where an overdose wakes up, and what it costs.
const HOSPITAL_POS := Vector3(103.8, 0.2, 93.0)
const HOSPITAL_BILL := 300
## How much of their cash someone who passes out in the street wakes up without.
const OD_ROBBED := 0.3
## Where a bad trip may leave you: a rooftop on the avenue, or up to the waist in the sea.
const WAKE_SPOTS := [Vector3(60.0, 0.2, 86.0), Vector3(-40.0, 0.2, -44.0)]
## What the two weapon keys cycle through.
const MELEE := ["fists", "knife", "estoque"]
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
	{"id": "preso", "weight": 0.0, "money": [0, 40], "resistance": 0.5, "fight": 0.75, "shoot": 0.0, "gun": 0.0, "hp": 70.0, "melee": 10.0, "scale": 1.0, "width": 1.05},
	{"id": "guarda", "weight": 0.0, "money": [40, 120], "resistance": 0.95, "fight": 1.0, "shoot": 0.0, "gun": 0.0, "hp": 140.0, "melee": 18.0, "scale": 1.1, "width": 1.2},
	{"id": "seguranca", "weight": 0.0, "money": [100, 300], "resistance": 0.9, "fight": 1.0, "shoot": 0.7, "gun": 0.5, "hp": 130.0, "melee": 18.0, "scale": 1.12, "width": 1.3},
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
const WHO_DOG := 4

const FOOD := ["coco", "espetinho", "acai", "caipirinha", "guarana"]
const LOOT := ["phone", "watch", "camera", "chain"]
## kind: "shop" sells `stock` (at `discount`), "bicho" takes bets, "fence" buys loot.
## `till` shops keep cash that can be taken at gunpoint.
const VENDORS := [
	{"name": "DEALER", "kind": "shop", "pos": Vector3(-60, 0, 47), "stock": ["cocaine", "weed", "meth", "lanca", "bala", "doce", "ketamine"], "color": Color(0.2, 0.7, 0.3)},
	{"name": "ARMS", "kind": "shop", "pos": Vector3(80, 0, 47), "stock": ["knife", "pistol", "revolver", "smg", "ammo"], "color": Color(0.25, 0.25, 0.3)},
	{"name": "QUIOSQUE 1", "kind": "shop", "till": true, "pos": Vector3(-240, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 2", "kind": "shop", "till": true, "pos": Vector3(-150, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "QUIOSQUE 3", "kind": "shop", "till": true, "pos": Vector3(10, 0, 47), "stock": FOOD, "color": Color(0.9, 0.3, 0.2)},
	{"name": "QUIOSQUE 4", "kind": "shop", "till": true, "pos": Vector3(170, 0, 47), "stock": FOOD, "color": Color(0.2, 0.55, 0.85)},
	{"name": "QUIOSQUE 5", "kind": "shop", "till": true, "pos": Vector3(250, 0, 47), "stock": FOOD, "color": Color(0.95, 0.6, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(130, 0, 47), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "JOGO DO BICHO", "kind": "bicho", "pos": Vector3(-70, 0, 107.0), "stock": [], "color": Color(0.85, 0.75, 0.1)},
	{"name": "BOCA", "kind": "shop", "discount": 0.7, "pos": BOCA_POS, "stock": ["cocaine", "weed", "meth", "lanca", "bala", "doce", "ketamine", "ayahuasca"], "color": Color(0.2, 0.7, 0.3)},
	{"name": "RECEPTADOR", "kind": "fence", "pos": Vector3(212, 6.2, 146.5), "stock": [], "color": Color(0.5, 0.3, 0.6)},
	# Behind a counter indoors (see scenes/world/interiors.gd for the rooms).
	{"name": "BOTECO DO ZÉ", "kind": "shop", "indoor": true, "till": true, "pos": Vector3(-123.2, 0, 79.5), "stock": ["cerveja", "caipirinha", "espetinho"], "color": Color(0.75, 0.12, 0.1)},
	{"name": "MERCADINHO", "kind": "shop", "indoor": true, "till": true, "pos": Vector3(52, 0, 75.1), "stock": ["coco", "acai", "guarana", "ammo"], "color": Color(0.1, 0.45, 0.75)},
	{"name": "FARMÁCIA", "kind": "shop", "indoor": true, "till": true, "pos": Vector3(107, 0, 80.9), "stock": ["curativo", "rivotril", "bomba"], "color": Color(0.1, 0.6, 0.3)},
	{"name": "BAR DO PORTUGUÊS", "kind": "shop", "indoor": true, "till": true, "pos": Vector3(103.8, 0, 117.5), "stock": ["cerveja", "caipirinha", "espetinho"], "color": Color(0.1, 0.4, 0.2)},
	{"name": "CONTRABANDO", "kind": "shop", "indoor": true, "jail": true, "pos": Vector3(-6, 0, 127.4), "stock": ["estoque", "colher", "corda", "cocaine", "weed", "rivotril"], "color": Color(0.3, 0.3, 0.3)},
	{"name": "BICHO DO BINGO", "kind": "bicho", "indoor": true, "pos": Vector3(-14, 0, 89.4), "stock": [], "color": Color(0.85, 0.6, 0.1)},
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
## A clean shirt: nobody is looking for someone dressed like that.
const CLOTHES_PRICE := 50
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
