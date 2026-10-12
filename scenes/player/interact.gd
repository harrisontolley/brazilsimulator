extends Node
## Everything the F key does. Lives at Game/Interact on every peer.
##
## A thing to use is a record: {kind, pos, r, prompt, hold, jail, arg, prio}. Fixed ones are
## added once with add() while the world builds, so every peer has the same list and an index
## is enough to name one over the network. Things that come and go (a bike, a drop, a body)
## are offered each tick by providers instead.
##
## Each kind has a `use` that runs on the peer who pressed F (open a panel, or call its own
## RPC) and optionally a `srv` that runs on the host through the one srv_act message, after
## the host has checked the player really is standing there.

const TICK := 0.1
## jail: who may use it.
const FREE := 0
const INSIDE := 1
const ANYONE := 2

var acts: Array = []
## What F would use right now, or {} for nothing in reach.
var current := {}
## 0..1 while a hold-to-use is being held.
var hold_frac := 0.0

var _use := {}
var _srv := {}
var _providers: Array[Callable] = []
var _grid := {}
var _t := 0.0
var _held := 0.0
var _fired := false
var _last := {}  # server: pid -> msec of their last act


## Adds a fixed thing to use and returns its index. `opts` may set hold, jail and prio.
func add(kind: StringName, pos: Vector3, r: float, prompt: String, arg := 0, opts := {}) -> int:
	var id := acts.size()
	acts.append({"id": id, "kind": kind, "pos": pos, "r": r, "prompt": prompt, "arg": arg,
			"hold": opts.get("hold", 0.0), "jail": opts.get("jail", FREE), "prio": opts.get("prio", 0)})
	var cell := Vector2i(floori(pos.x / 8.0), floori(pos.z / 8.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var key := cell + Vector2i(dx, dz)
			if not _grid.has(key):
				_grid[key] = PackedInt32Array()
			_grid[key].append(id)
	return id


## What a kind does: `use.call(act)` on the peer that pressed F, `srv.call(player, act, arg)` on
## the host. Leave `use` empty to go straight to the host.
func on(kind: StringName, use := Callable(), srv := Callable()) -> void:
	if use.is_valid():
		_use[kind] = use
	if srv.is_valid():
		_srv[kind] = srv


## `c.call(player, out)` appends records for things in reach right now. Give them "id": -1.
func provide(c: Callable) -> void:
	_providers.append(c)


## A one-off record for a provider to offer.
static func offer(kind: StringName, pos: Vector3, prompt: String, arg := 0, prio := 0, hold := 0.0) -> Dictionary:
	return {"id": -1, "kind": kind, "pos": pos, "r": 99.0, "prompt": prompt, "arg": arg, "hold": hold, "jail": ANYONE, "prio": prio}


func _process(delta: float) -> void:
	var g = Net.game
	var p = g.local_player
	if p == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		current = _pick(p)
	var usable: bool = not current.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and p.can_act()
	if not usable or not Input.is_action_pressed("interact"):
		_held = 0.0
		_fired = false
	elif not _fired:
		_held += delta
		if _held >= current.hold:
			_fired = true
			_fire(current)
	hold_frac = clampf(_held / current.hold, 0.0, 1.0) if usable and current.hold > 0.0 else 0.0
	g.hud.set_prompt(("Hold F: " if current.get("hold", 0.0) > 0.0 else "F: ") + current.prompt if usable else "", hold_frac)


## Uses whatever is in reach right now, without waiting for a hold.
func press() -> void:
	var p = Net.game.local_player
	if p == null or not p.can_act():
		return
	current = _pick(p)
	if not current.is_empty():
		_fire(current)


func _pick(p) -> Dictionary:
	var at: Vector3 = p.global_position
	var jailed: bool = p.st.jail > 0.0
	var cands: Array = []
	for c in _providers:
		c.call(p, cands)
	for id in _grid.get(Vector2i(floori(at.x / 8.0), floori(at.z / 8.0)), PackedInt32Array()):
		cands.append(acts[id])
	var best := {}
	var best_score := -INF
	for a in cands:
		if a.jail != ANYONE and (a.jail == INSIDE) != jailed:
			continue
		var d: float = at.distance_to(a.pos)
		if d > a.r or absf(at.y - a.pos.y) > 2.5:
			continue
		var score: float = a.prio * 100.0 - d
		if score > best_score:
			best = a
			best_score = score
	return best


func _fire(a: Dictionary) -> void:
	if _use.has(a.kind):
		_use[a.kind].call(a)
	elif a.id >= 0:
		Net.game.to_server("srv_act", [a.id, 0], self)


## A fixed act that needs the host: checked there, then handed to the kind's srv.
@rpc("any_peer", "call_remote", "reliable")
func srv_act(id: int, arg: int) -> void:
	var pid := Net.sender()
	var p = Net.game.players.get(pid)
	if p == null or not p.can_act() or id < 0 or id >= acts.size():
		return
	var now := Time.get_ticks_msec()
	if now - _last.get(pid, 0) < 150:
		return
	_last[pid] = now
	var a: Dictionary = acts[id]
	if a.jail != ANYONE and (a.jail == INSIDE) != (p.st.jail > 0.0):
		return
	if p.global_position.distance_to(a.pos) > a.r + 1.5 or not _srv.has(a.kind):
		return
	_srv[a.kind].call(p, a, arg)
