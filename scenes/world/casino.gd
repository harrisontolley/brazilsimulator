extends Node
## The games at the BINGO ATLÂNTICO, run by the host. Lives at Game/Casino on every peer.
##
## Every bet is one message up and one result back to the player who made it. The house
## keeps a float that wins and losses move, which is what sits in the safe for anyone with a
## gun and no sense. An illegal house does not ring the police: it has its own men.

const Places := preload("res://scenes/world/places.gd")

const STAKES := [10, 50, 200, 1000]
const FLOAT := 8000
## Reel symbols, how often each comes up, and what three of a kind pay (times the stake).
const SYMBOLS := ["CEREJA", "LIMÃO", "SINO", "BAR", "SETE", "DIAMANTE"]
const WEIGHTS := [0.3, 0.25, 0.2, 0.15, 0.08, 0.02]
const TRIPLE := [5, 10, 20, 40, 150, 1000]
const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]
## Roulette bets: what they are called and what they return on a win, stake included.
const BETS := [["VERMELHO", 2], ["PRETO", 2], ["PAR", 2], ["ÍMPAR", 2], ["1-18", 2], ["19-36", 2], ["DÚZIA", 3], ["NÚMERO", 36]]
const SAFE_COOLDOWN := 180.0
const BAN_TIME := 120.0

var bank := FLOAT

var _hands := {}    # pid -> {bet, mine: [cards], house: [cards]}
var _banned := {}   # pid -> match time they are let back in
var _last := {}     # pid -> msec of their last bet
var _safe_ok := 0.0


func reset() -> void:
	bank = FLOAT
	_hands.clear()
	_banned.clear()
	_safe_ok = 0.0


## The player placing a bet, if they are in the hall, allowed, and good for `amount`.
func _punter(amount: int):
	var pid := Net.sender()
	var p = Net.game.players.get(pid)
	if p == null or not p.at_large() or not STAKES.has(amount) or p.st.money < amount:
		return null
	var room := Places.room_at(p.global_position)
	if room < 0 or Places.rooms[room].kind != "cassino":
		return null
	if MatchState.time < _banned.get(pid, 0.0):
		_tell(p, "You are barred. Come back when they have forgotten your face.")
		return null
	var now := Time.get_ticks_msec()
	if now - _last.get(pid, 0) < 400:
		return null
	_last[pid] = now
	return p


func _settle(p, stake: int, back: int, text: String) -> void:
	p.st.money += back - stake
	bank += stake - back
	Net.game.push_state(p)
	_tell(p, text + ("   +R$%d" % (back - stake) if back > stake else ("   -R$%d" % (stake - back) if back < stake else "   stake back")))
	if back > stake:
		Net.game.send(p.id, "cl_sound", ["cash", p.global_position])


func _tell(p, text: String) -> void:
	Net.game.send(p.id, "cl_result", [text], self)


@rpc("authority", "call_remote", "reliable")
func cl_result(text: String) -> void:
	Net.game.hud.game_result(text)


# --- caça-níquel ---

func _reel() -> int:
	var roll := randf()
	for k in WEIGHTS.size():
		roll -= WEIGHTS[k]
		if roll <= 0.0:
			return k
	return 0


## What a spin returns for a stake of 1: three of a kind, or cherries from the left.
static func slot_pays(r: Array) -> float:
	if r[0] == r[1] and r[1] == r[2]:
		return TRIPLE[r[0]]
	if r[0] == 0:
		return 2.0 if r[1] == 0 else 0.5
	return 0.0


@rpc("any_peer", "call_remote", "reliable")
func srv_slot(amount: int) -> void:
	var p = _punter(amount)
	if p == null:
		return
	var r := [_reel(), _reel(), _reel()]
	_settle(p, amount, int(amount * slot_pays(r)), "%s | %s | %s" % [SYMBOLS[r[0]], SYMBOLS[r[1]], SYMBOLS[r[2]]])


# --- roleta ---

@rpc("any_peer", "call_remote", "reliable")
func srv_roulette(kind: int, n: int, amount: int) -> void:
	if kind < 0 or kind >= BETS.size():
		return
	var p = _punter(amount)
	if p == null:
		return
	var roll := randi_range(0, 36)
	_settle(p, amount, amount * BETS[kind][1] if wins(kind, clampi(n, 0, 36 if kind == 7 else 2), roll) else 0, "%d %s" % [roll, colour(roll)])


## Does a bet of `kind` (on dozen or number n, for the two that take one) win when `roll` comes up?
static func wins(kind: int, n: int, roll: int) -> bool:
	var red := REDS.has(roll)
	match kind:
		0: return red
		1: return roll > 0 and not red
		2: return roll > 0 and roll % 2 == 0
		3: return roll % 2 == 1
		4: return roll >= 1 and roll <= 18
		5: return roll >= 19
		6: return roll > 0 and (roll - 1) / 12 == n
		7: return roll == n
	return false


static func colour(roll: int) -> String:
	return "verde" if roll == 0 else ("vermelho" if REDS.has(roll) else "preto")


# --- vinte-e-um ---

func _card() -> int:
	return randi_range(1, 13)


static func hand_value(cards: Array) -> int:
	var total := 0
	var aces := 0
	for c in cards:
		if c == 1:
			aces += 1
			total += 11
		else:
			total += mini(c, 10)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


static func hand_text(cards: Array) -> String:
	var names := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	var out: Array = []
	for c in cards:
		out.append(names[c])
	return " ".join(out)


## `action`: 0 deal (with a stake), 1 hit, 2 stand, 3 double.
@rpc("any_peer", "call_remote", "reliable")
func srv_bj(action: int, amount: int) -> void:
	var pid := Net.sender()
	if action == 0:
		var pl = _punter(amount)
		if pl == null or _hands.has(pid):
			return
		var dealt := {"bet": amount, "mine": [_card(), _card()], "house": [_card(), _card()]}
		pl.st.money -= amount
		bank += amount
		Net.game.push_state(pl)
		if hand_value(dealt.mine) == 21:
			_bj_end(pl, dealt, int(amount * 2.5), "VINTE-E-UM!")
			return
		_hands[pid] = dealt
		_tell(pl, "You: %s (%d)    House shows: %s" % [hand_text(dealt.mine), hand_value(dealt.mine), hand_text([dealt.house[0]])])
		return
	var p = Net.game.players.get(pid)
	var h = _hands.get(pid)
	if p == null or h == null:
		return
	if action == 3:
		if p.st.money < h.bet or h.mine.size() != 2:
			_tell(p, "Cannot double now.")
			return
		p.st.money -= h.bet
		bank += h.bet
		h.bet *= 2
	if action == 1 or action == 3:
		h.mine.append(_card())
		if hand_value(h.mine) > 21:
			_hands.erase(pid)
			_bj_end(p, h, 0, "Bust.")
			return
		if action == 1:
			_tell(p, "You: %s (%d)    House shows: %s" % [hand_text(h.mine), hand_value(h.mine), hand_text([h.house[0]])])
			return
	# Standing: the house draws to seventeen.
	_hands.erase(pid)
	while hand_value(h.house) < 17:
		h.house.append(_card())
	var mine := hand_value(h.mine)
	var house := hand_value(h.house)
	if house > 21 or mine > house:
		_bj_end(p, h, h.bet * 2, "You win.")
	elif mine == house:
		_bj_end(p, h, h.bet, "Push.")
	else:
		_bj_end(p, h, 0, "House wins.")


func _bj_end(p, h: Dictionary, back: int, text: String) -> void:
	p.st.money += back
	bank -= back
	Net.game.push_state(p)
	_tell(p, "%s   You: %s (%d)   House: %s (%d)%s" % [text, hand_text(h.mine), hand_value(h.mine), hand_text(h.house), hand_value(h.house), "   +R$%d" % (back - h.bet) if back > h.bet else ""])
	if back > h.bet:
		Net.game.send(p.id, "cl_sound", ["cash", p.global_position])


# --- the safe ---

## Called by the interact system once a player has stood at the safe long enough.
func srv_safe(p, _act: Dictionary, _arg: int) -> void:
	var g = Net.game
	if not DB.is_gun(p.st.equipped):
		g.send(p.id, "cl_toast", ["The cashier laughs at you. Come back with a gun."])
		return
	if MatchState.time < _safe_ok:
		g.send(p.id, "cl_toast", ["The safe is empty - somebody got here first"])
		return
	_safe_ok = MatchState.time + SAFE_COOLDOWN
	# (A good night for the punters can leave the float in the red; the safe is then just empty.)
	var take: int = clampi(int(bank * 0.6), 0, 4000)
	bank -= take
	p.st.money += take
	_banned[p.id] = MatchState.time + BAN_TIME
	g.push_state(p)
	g.send(p.id, "cl_toast", ["Cleaned out the safe: R$%d.  The house wants it back." % take])
	g.bcast("cl_sound", ["cash", p.global_position])
	Crime.report_noise(p.global_position, 60.0, p.id)
	Crime.report_crime(p.global_position, p.id, 2)
	g.crowd.srv_alarm("seguranca", p.global_position, 70.0, p.id)
