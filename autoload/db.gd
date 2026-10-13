extends Node
## Static game data: items, NPC archetypes, vendors, map constants.

const Layout := preload("res://scenes/world/layout.gd")

const ITEMS := {
	# Weapons. `held` is the Kit.HELD_* shown in the hand. `ko`: a blow to the head can knock
	# someone out. Guns carry `mag` rounds, take `reload` seconds to refill, kick the view up by
	# `recoil`, and a shot to the head kills outright `head_kill` of the time. `auto` ones keep
	# firing while the trigger is held. `pellets` leave the barrel together; `pierce` is how
	# many bodies a round goes on through; a `scope` steadies it when aimed and `hip` is how
	# wild it is when not. `feed` is the item its rounds come from, where that is not "ammo".
	# `kind` "rocket" flies and bursts over `blast` metres; "thrown" leaves the hand, and the
	# thing itself is the ammunition: `fuse` seconds, or flames for `burn` seconds where it lands.
	# `sound` is what it sounds like, `muzzle` where the barrel ends in the first-person view.
	# A melee one with `ko` lays people out: `ko_head` / `ko_body` is how often a blow there does
	# (a head blow defaults to KO_CHANCE, a body blow to never), `ko_time` how long a player stays
	# down and `ko_npc` how long anybody else does.
	"fists": {"name": "Fists", "type": "weapon", "melee": true, "damage": 12.0, "range": 2.3, "cooldown": 0.45, "spread": 0.0, "intimidation": 1.0, "price": 0, "held": 0, "ko": true},
	"estoque": {"name": "Estoque", "type": "weapon", "melee": true, "damage": 22.0, "range": 2.0, "cooldown": 0.5, "spread": 0.0, "intimidation": 1.6, "price": 80, "held": 1},
	"knife": {"name": "Faca", "type": "weapon", "melee": true, "damage": 28.0, "range": 2.1, "cooldown": 0.5, "spread": 0.0, "intimidation": 1.8, "price": 150, "held": 1},
	"pistol": {"name": "Pistol", "type": "weapon", "melee": false, "damage": 34.0, "range": 60.0, "cooldown": 0.22, "spread": 0.035, "intimidation": 2.5, "price": 400, "held": 2, "mag": 12, "reload": 1.4, "recoil": 0.03, "head_kill": 0.85},
	"revolver": {"name": "Três-oitão", "type": "weapon", "melee": false, "damage": 55.0, "range": 70.0, "cooldown": 0.5, "spread": 0.02, "intimidation": 2.8, "price": 900, "held": 3, "mag": 6, "reload": 2.2, "recoil": 0.065, "head_kill": 1.0, "sound": "revolver"},
	"smg": {"name": "Submetralhadora", "type": "weapon", "melee": false, "damage": 16.0, "range": 45.0, "cooldown": 0.09, "spread": 0.06, "intimidation": 3.0, "price": 1500, "held": 4, "mag": 30, "reload": 2.0, "recoil": 0.016, "head_kill": 0.45, "auto": true, "sound": "smg"},
	"taco": {"name": "Taco", "type": "weapon", "melee": true, "damage": 32.0, "range": 2.8, "cooldown": 0.7, "spread": 0.0, "intimidation": 2.0, "price": 120, "held": 11, "shove": 7.0, "ko": true, "ko_head": 0.6, "ko_body": 0.2, "ko_time": 30.0, "ko_npc": 45.0, "sound": "thwack"},
	"porrete": {"name": "Porrete", "type": "weapon", "melee": true, "damage": 18.0, "range": 2.5, "cooldown": 0.65, "spread": 0.0, "intimidation": 2.2, "price": 90, "held": 12, "ko": true, "ko_head": 0.8, "ko_body": 0.35, "ko_time": 30.0, "ko_npc": 45.0, "sound": "thwack"},
	"frigideira": {"name": "Frigideira", "type": "weapon", "melee": true, "damage": 10.0, "range": 2.2, "cooldown": 0.6, "spread": 0.0, "intimidation": 1.4, "price": 60, "held": 13, "ko": true, "ko_head": 0.95, "ko_body": 0.5, "ko_time": 30.0, "ko_npc": 45.0, "sound": "bong"},
	"tijolo": {"name": "Tijolo", "type": "weapon", "melee": true, "damage": 16.0, "range": 1.9, "cooldown": 0.55, "spread": 0.0, "intimidation": 1.5, "price": 15, "held": 14, "ko": true, "ko_head": 0.7, "ko_body": 0.25, "ko_time": 30.0, "ko_npc": 45.0, "sound": "crack"},
	"shotgun": {"name": "Escopeta", "type": "weapon", "melee": false, "damage": 14.0, "pellets": 9, "range": 34.0, "cooldown": 0.95, "spread": 0.085, "intimidation": 3.2, "price": 1800, "held": 5, "mag": 5, "reload": 2.6, "recoil": 0.11, "head_kill": 0.2, "feed": "shells", "sound": "shotgun", "muzzle": Vector3(0.2, -0.13, -1.25)},
	"fuzil": {"name": "Fuzil", "type": "weapon", "melee": false, "damage": 30.0, "range": 120.0, "cooldown": 0.105, "spread": 0.026, "intimidation": 3.5, "price": 3200, "held": 6, "mag": 30, "reload": 2.4, "recoil": 0.024, "head_kill": 0.7, "auto": true, "sound": "rifle", "muzzle": Vector3(0.2, -0.13, -1.3)},
	"sniper": {"name": "Sniper", "type": "weapon", "melee": false, "damage": 160.0, "range": 420.0, "cooldown": 1.5, "spread": 0.0015, "hip": 0.09, "intimidation": 3.5, "price": 4500, "held": 7, "mag": 5, "reload": 3.0, "recoil": 0.13, "head_kill": 1.0, "feed": "rounds", "scope": 9.0, "pierce": 1, "sound": "sniper", "muzzle": Vector3(0.2, -0.13, -1.5)},
	"rpg": {"name": "Lança-rojão", "type": "weapon", "melee": false, "kind": "rocket", "damage": 230.0, "blast": 7.5, "range": 300.0, "cooldown": 1.2, "spread": 0.006, "intimidation": 4.0, "price": 6000, "held": 8, "mag": 1, "reload": 2.8, "recoil": 0.16, "head_kill": 0.0, "feed": "rocket", "sound": "launch", "muzzle": Vector3(0.24, -0.02, -1.1)},
	"grenade": {"name": "Granada", "type": "weapon", "melee": false, "kind": "thrown", "damage": 190.0, "blast": 7.0, "fuse": 2.6, "range": 40.0, "cooldown": 0.9, "spread": 0.0, "intimidation": 3.0, "price": 350, "held": 9, "stack": true},
	"molotov": {"name": "Molotov", "type": "weapon", "melee": false, "kind": "thrown", "damage": 13.0, "blast": 3.6, "burn": 7.0, "range": 40.0, "cooldown": 0.9, "spread": 0.0, "intimidation": 3.0, "price": 200, "held": 10, "stack": true},
	"ammo": {"name": "Ammo x12", "type": "ammo", "amount": 12, "price": 60},
	"shells": {"name": "Cartuchos x8", "type": "ammo", "amount": 8, "price": 90},
	"rounds": {"name": "Sniper rounds x5", "type": "ammo", "amount": 5, "price": 220},
	"rocket": {"name": "Rojão", "type": "ammo", "amount": 1, "price": 700},
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
## How long anyone can hold a breath, and what running out of it costs each second after.
const BREATH := 25.0
const DROWN_DMG := 12.0
## Where a bad trip may leave you: a rooftop on the avenue, or up to the waist in the sea.
const WAKE_SPOTS := [Vector3(60.0, 0.2, 86.0), Vector3(-40.0, 0.2, -49.0)]
## What the two weapon keys cycle through.
const MELEE := ["fists", "knife", "estoque", "taco", "porrete", "frigideira", "tijolo"]
const GUNS := ["pistol", "revolver", "smg", "shotgun", "fuzil"]
const HEAVY := ["sniper", "rpg"]
const THROWN := ["grenade", "molotov"]
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
	# The yacht: the girls on deck, and the men whose money it is.
	{"id": "socialite", "weight": 0.0, "money": [80, 400], "resistance": 0.1, "fight": 0.0, "shoot": 0.0, "gun": 0.0, "hp": 40.0, "melee": 0.0, "scale": 0.97, "width": 0.86, "build": 1},
	{"id": "magnata", "weight": 0.0, "money": [2500, 6000], "resistance": 0.35, "fight": 0.0, "shoot": 0.0, "gun": 0.0, "hp": 60.0, "melee": 0.0, "scale": 1.02, "width": 1.42, "build": 2},
	{"id": "traficante", "weight": 0.0, "money": [250, 900], "resistance": 0.6, "fight": 0.9, "shoot": 0.85, "gun": 0.6, "hp": 100.0, "melee": 14.0, "scale": 1.05, "width": 1.15},
	# The alleys: a boca's lookout kid, its dealer, and the old men who have seen everything.
	{"id": "olheiro", "weight": 0.0, "money": [5, 40], "resistance": 0.2, "fight": 0.1, "shoot": 0.0, "gun": 0.0, "hp": 35.0, "melee": 4.0, "scale": 0.78, "width": 0.85},
	{"id": "vapor", "weight": 0.0, "money": [300, 900], "resistance": 0.55, "fight": 0.6, "shoot": 0.4, "gun": 0.4, "hp": 75.0, "melee": 12.0, "scale": 1.0, "width": 1.0},
	{"id": "velho", "weight": 0.0, "money": [5, 50], "resistance": 0.2, "fight": 0.05, "shoot": 0.0, "gun": 0.0, "hp": 40.0, "melee": 3.0, "scale": 0.94, "width": 0.96},
]

## Cash an NPC must be carrying to show mid / rich props.
const WEALTH_TIERS := [50, 400]

# Who threw or took a hit, as sent in Game.cl_fx.
const WHO_NONE := 0
const WHO_PLAYER := 1
const WHO_COP := 2
const WHO_NPC := 3
const WHO_DOG := 4
const WHO_SEACOP := 5

const FOOD := ["coco", "espetinho", "acai", "caipirinha", "guarana"]
const LOOT := ["phone", "watch", "camera", "chain"]
## kind: "shop" sells `stock` (at `discount`), "bicho" takes bets, "fence" buys loot.
## `till` shops keep cash that can be taken at gunpoint.
const VENDORS := [
	{"name": "DEALER", "kind": "shop", "pos": Vector3(-60, 0, 47), "stock": ["cocaine", "weed", "meth", "lanca", "bala", "doce", "ketamine"], "color": Color(0.2, 0.7, 0.3)},
	{"name": "ARMS", "kind": "shop", "pos": Vector3(80, 0, 47), "stock": ["knife", "taco", "porrete", "pistol", "revolver", "smg", "shotgun", "fuzil", "sniper", "rpg", "grenade", "molotov", "ammo", "shells", "rounds", "rocket"], "color": Color(0.25, 0.25, 0.3)},
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
	# An old man in an alley who sells whatever you can hit somebody with.
	{"name": "FERRO-VELHO", "kind": "shop", "stall": false, "pos": Vector3(-178, 0, 90.0), "stock": ["porrete", "frigideira", "tijolo", "taco", "knife"], "color": Color(0.5, 0.4, 0.3)},
	# The facção's three bocas, in the alleys (see scenes/world/becos.gd): they sell everything,
	# at black market prices, for as long as their crew has no quarrel with you.
	{"name": "BOCA DA FACÇÃO", "kind": "shop", "crew": 0, "stall": false, "discount": 1.2, "pos": Vector3(-180, 0, 121.0), "stock": DRUGS + DRINKS, "color": Color(0.2, 0.7, 0.3)},
	{"name": "BOCA DA FACÇÃO", "kind": "shop", "crew": 1, "stall": false, "discount": 1.2, "pos": Vector3(150, 0, 121.0), "stock": DRUGS + DRINKS, "color": Color(0.2, 0.7, 0.3)},
	{"name": "BOCA DA FACÇÃO", "kind": "shop", "crew": 2, "stall": false, "discount": 1.2, "pos": Vector3(80, 0, 86.0), "stock": DRUGS + DRINKS, "color": Color(0.2, 0.7, 0.3)},
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


## How often a blow from `w` to `zone` lays somebody out.
func ko_chance(w: Dictionary, zone: int) -> float:
	if not w.get("ko", false):
		return 0.0
	if zone == ZONE_HEAD:
		return w.get("ko_head", KO_CHANCE)
	return w.get("ko_body", 0.0)
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
		if clear_of_solids(p, 1.0) == p and not Layout.on_wheel(p, 2.0):
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


## Something with a magazine to empty and refill.
static func is_gun(item: String) -> bool:
	return ITEMS.has(item) and ITEMS[item].has("mag")


## What kind of weapon `item` is: "melee", "shot" (a bullet that is there the instant it is
## fired), "rocket" or "thrown".
static func kind_of(item: String) -> String:
	var w: Dictionary = ITEMS[item]
	return "melee" if w.melee else w.get("kind", "shot")


## The item a gun's rounds are bought as.
static func feed_of(item: String) -> String:
	return ITEMS[item].get("feed", "ammo")


## How many rounds for `item` the player with state `st` has that are not in the gun.
static func spare(st: Dictionary, item: String) -> int:
	var feed := feed_of(item)
	return st.ammo if feed == "ammo" else st.inv.get(feed, 0)


## Takes n of them.
static func take_spare(st: Dictionary, item: String, n: int) -> void:
	var feed := feed_of(item)
	if feed == "ammo":
		st.ammo -= n
	else:
		st.inv[feed] = st.inv.get(feed, 0) - n
		if st.inv[feed] <= 0:
			st.inv.erase(feed)


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
