extends Node
## Doing time in the presídio, run by the host. Lives at Game/Prison on every peer.
##
## A sentence is a clock, and nearly everything inside is a way to wind it down or get round
## it: a shift in the workshop, a goal in the yard, a fight won in the ring, a guard who can be
## paid, a spoon and a patient hole under a bunk, a rope over the wall. Start a fight where a
## guard can see it and the clock goes the other way.
##
## The building itself is put up by scenes/world/interiors.gd; the things to use in it reach
## here through the interact system.

const Places := preload("res://scenes/world/places.gd")

## Sentence by wanted level at the moment of arrest.
const SENTENCE := [60.0, 60.0, 100.0, 150.0]
const WORK_CUT := 15.0
const WORK_PAY := 15
const WORK_REST := 8.0
const GOAL_CUT := 8.0
const RING_CUT := 20.0
## What a guard adds for brawling outside the ring.
const FIGHT_ADD := 10.0
const GUARD_SIGHT := 14.0
const BRIBE_BASE := 100
const BRIBE_PER_S := 4
const BAIL_PER_S := 3
const MEAL_REST := 60.0
const MEAL_HEAL := 35.0
## How many goes with the spoon it takes to get under the wall.
const DIG_SESSIONS := 3
const IRON_TIME := 120.0
## The yard: where the ring is, and where the two ways out come up.
const RING := Vector3(21.0, 0, 127.0)
const RING_R := 3.2
const TUNNEL_EXIT := Vector3(-32.0, 0.3, 134.0)
const WALL_EXIT := Vector3(16.0, 0.3, 133.5)

var _rest := {}   # [pid, what] -> match time they can do it again
var _dug := {}    # pid -> sessions dug


func reset() -> void:
	_rest.clear()
	_dug.clear()


## How long someone caught at wanted level `heat` goes down for.
static func sentence(heat: int) -> float:
	return SENTENCE[clampi(heat, 0, 3)]


func _rested(p, what: String, seconds: float) -> bool:
	var key := [p.id, what]
	if MatchState.time < _rest.get(key, 0.0):
		Net.game.send(p.id, "cl_toast", ["Not yet - give it %ds" % ceili(_rest[key] - MatchState.time)])
		return false
	_rest[key] = MatchState.time + seconds
	return true


## Takes `seconds` off a sentence. Running it out is a release like any other.
func srv_cut(p, seconds: float, why: String) -> void:
	if p.st.jail <= 0.0:
		return
	p.st.jail = maxf(p.st.jail - seconds, 0.05)
	Net.game.push_state(p)
	Net.game.send(p.id, "cl_toast", ["%s: %ds off your sentence" % [why, int(seconds)]])


## Out through the front door with nothing owing: time served, a bribe, bail.
func srv_release(p) -> void:
	var g = Net.game
	p.st.jail = 0.0
	p.st.heat = 0
	p.st.fug = false
	# What you came by inside stays inside.
	p.st.inv = {"fists": 1}
	p.st.equipped = "fists"
	p.st.mag = {}
	_dug.erase(p.id)
	g.push_state(p)
	g.srv_teleport(p.id, DB.RELEASE_POS + Vector3(randf_range(-6, 6), 0, 0))


## Over or under the wall: free, but in stripes, and every cop in the city knows it.
func _srv_escape(p, to: Vector3, how: String) -> void:
	var g = Net.game
	p.st.jail = 0.0
	p.st.heat = 2
	p.st.fug = true
	p.wanted_t = 25.0
	_dug.erase(p.id)
	g.push_state(p)
	g.srv_teleport(p.id, to)
	g.bcast("cl_toast", ["%s broke out of prison %s!" % [p.pname, how]])
	g.bcast("cl_sound", ["whistle", to])


# --- things to do, as the interact system calls them ---

func srv_work(p, _a: Dictionary, _arg: int) -> void:
	if not _rested(p, "work", WORK_REST):
		return
	p.st.money += WORK_PAY
	srv_cut(p, WORK_CUT, "A shift done (+R$%d)" % WORK_PAY)


func srv_weights(p, _a: Dictionary, _arg: int) -> void:
	if not _rested(p, "iron", 30.0):
		return
	p.st.drugs["ferro"] = {"phase": "high", "t": IRON_TIME}
	Net.game.push_state(p)
	Net.game.send(p.id, "cl_toast", ["Pumped: you hit harder for a couple of minutes"])


func srv_meal(p, _a: Dictionary, _arg: int) -> void:
	if not _rested(p, "meal", MEAL_REST):
		return
	p.st.hp = minf(100.0, p.st.hp + MEAL_HEAL)
	Net.game.push_state(p)
	Net.game.send(p.id, "cl_toast", ["Rice, beans, and you do not ask about the rest"])


func srv_bribe(p, _a: Dictionary, _arg: int) -> void:
	var price := BRIBE_BASE + int(p.st.jail) * BRIBE_PER_S
	if p.st.money < price:
		Net.game.send(p.id, "cl_toast", ["The guard wants R$%d to look the other way" % price])
		return
	p.st.money -= price
	Net.game.send(p.id, "cl_toast", ["R$%d, and the gate was never locked" % price])
	srv_release(p)


## Someone at the front desk paying to get a friend out.
func srv_bail(p, _a: Dictionary, _arg: int) -> void:
	var g = Net.game
	for pid in g.players:
		var who = g.players[pid]
		if who == p or who.st.jail <= 0.0:
			continue
		var price := 50 + int(who.st.jail) * BAIL_PER_S
		if p.st.money < price:
			g.send(p.id, "cl_toast", ["Bail for %s is R$%d" % [who.pname, price]])
			return
		p.st.money -= price
		g.push_state(p)
		g.send(p.id, "cl_toast", ["Paid R$%d: %s walks" % [price, who.pname]])
		g.send(pid, "cl_toast", ["%s paid your bail" % p.pname])
		srv_release(who)
		return
	g.send(p.id, "cl_toast", ["Nobody of yours is inside"])


func srv_dig(p, _a: Dictionary, _arg: int) -> void:
	var g = Net.game
	if p.st.inv.get("colher", 0) <= 0:
		g.send(p.id, "cl_toast", ["Loose flagstone under the bunk. You would need something to dig with."])
		return
	if not _rested(p, "dig", 6.0):
		return
	_dug[p.id] = _dug.get(p.id, 0) + 1
	g.bcast("cl_sound", ["kick", p.global_position])
	if _dug[p.id] < DIG_SESSIONS:
		g.send(p.id, "cl_toast", ["Digging... %d of %d" % [_dug[p.id], DIG_SESSIONS]])
		return
	_srv_escape(p, TUNNEL_EXIT, "through a tunnel")


func srv_climb(p, _a: Dictionary, _arg: int) -> void:
	if p.st.inv.get("corda", 0) <= 0:
		Net.game.send(p.id, "cl_toast", ["An iron hook high on the wall. With a rope..."])
		return
	_srv_escape(p, WALL_EXIT, "over the wall")


## Dice against the banker: both roll two, high wins, the banker takes ties.
@rpc("any_peer", "call_remote", "reliable")
func srv_dice(amount: int) -> void:
	var g = Net.game
	var p = g.players.get(Net.sender())
	if p == null or p.st.jail <= 0.0 or not [5, 20, 50].has(amount) or p.st.money < amount or not _rested(p, "dice", 0.4):
		return
	var mine := randi_range(1, 6) + randi_range(1, 6)
	var his := randi_range(1, 6) + randi_range(1, 6)
	var won := mine > his
	p.st.money += amount if won else -amount
	g.push_state(p)
	g.send(p.id, "cl_result", ["You rolled %d, the banker %d.   %sR$%d" % [mine, his, "+" if won else "-", amount]], g.casino)


## A jailed player has landed a blow at `at`. In the ring that is sport; anywhere else it is a
## guard's business if one is looking. `out` says the other party went down.
func srv_fight(p, at: Vector3, out: bool) -> void:
	var g = Net.game
	if at.distance_to(RING) < RING_R + 1.0:
		if out:
			srv_cut(p, RING_CUT, "Won in the ring")
		return
	if g.crowd.srv_witness("guarda", p.global_position, GUARD_SIGHT, p.id):
		p.st.jail += FIGHT_ADD
		g.push_state(p)
		g.send(p.id, "cl_toast", ["A guard saw that: %ds on your sentence" % int(FIGHT_ADD)])
