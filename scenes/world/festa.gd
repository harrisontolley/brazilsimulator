extends "res://scenes/world/world_kit.gd"
## The beach party: a DJ booth and speaker stacks on the sand, people dancing round it, the
## song going round, and whatever the host keeps lying about on the ground nearby.
##
## Like the rest of the world it is built the same on every peer. Only the drugs on the
## ground are the host's to hand out, and those ride the ordinary drop messages.

const Places := preload("res://scenes/world/places.gd")
const Kit := preload("res://scenes/characters/char_kit.gd")

const DANCERS := 30
## How often the host looks at what is left on the ground, and the most it puts back at once.
const RESTOCK_EVERY := 5.0
const RESTOCK_MAX := 3
## How near the booth counts as "at the party" for the drugs on the ground.
const NEAR := 14.0
## How far out the song may drift from the match clock before it is moved back.
const DRIFT := 0.4

var _lights: Array[OmniLight3D] = []
var _beat: AudioStreamPlayer3D
var _sync_t := 0.0
var _restock_t := 3.0


func _ready() -> void:
	_init_kit()
	var c := DB.FESTA_POS
	var dark := Color(0.07, 0.07, 0.08)
	var grey := Color(0.25, 0.25, 0.27)
	# The booth and a speaker stack to each side of it.
	_solid(c + Vector3(0, 0.55, -3.0), Vector3(4.0, 1.1, 1.0), Color(0.15, 0.1, 0.2))
	_glow(c + Vector3(0, 1.15, -3.0), Vector3(1.8, 0.08, 0.6), Color(0.9, 0.2, 0.8))
	_glow(c + Vector3(-1.3, 1.2, -3.0), Vector3(0.5, 0.05, 0.5), Color(0.2, 0.9, 0.9))
	_glow(c + Vector3(1.3, 1.2, -3.0), Vector3(0.5, 0.05, 0.5), Color(0.95, 0.85, 0.2))
	for side in [-1.0, 1.0]:
		for row in 3:
			var p := c + Vector3(side * 5.5, 0.75 + row * 1.5, -3.2)
			_solid(p, Vector3(1.5, 1.45, 1.2), dark)
			_box(p + Vector3(0, 0.2, 0.61), Vector3(0.9, 0.9, 0.04), grey)
			_box(p + Vector3(0, -0.45, 0.61), Vector3(0.4, 0.3, 0.04), grey)
	# A cooler of beer and a drum of fire for the cold end of the evening.
	_solid(c + Vector3(3.2, 0.3, -2.4), Vector3(0.9, 0.6, 0.5), Color(0.2, 0.45, 0.8))
	_box(c + Vector3(3.2, 0.63, -2.4), Vector3(0.95, 0.06, 0.55), Color(0.95, 0.95, 0.95))
	_solid(c + Vector3(-3.4, 0.45, -2.2), Vector3(0.7, 0.9, 0.7), Color(0.3, 0.2, 0.15))
	_glow(c + Vector3(-3.4, 0.95, -2.2), Vector3(0.5, 0.2, 0.5), Color(1.0, 0.45, 0.1))
	# Four poles with strings of bulbs between them and a light hung from each.
	var corners := [Vector3(-9, 0, -7), Vector3(9, 0, -7), Vector3(9, 0, 9), Vector3(-9, 0, 9)]
	for i in corners.size():
		var a: Vector3 = c + corners[i]
		var b: Vector3 = c + corners[(i + 1) % corners.size()]
		_block(a + Vector3(0, 2.4, 0), Vector3(0.14, 4.8, 0.14), dark)
		for k in 12:
			var t := (k + 0.5) / 12.0
			var at := a.lerp(b, t)
			_glow(at + Vector3(0, 4.6 - sin(t * PI) * 0.7, 0), Vector3(0.16, 0.16, 0.16), Color.from_hsv(fmod(i * 0.21 + k * 0.17, 1.0), 0.75, 1.0))
		var l := OmniLight3D.new()
		l.position = a + Vector3(0, 4.4, 0)
		l.omni_range = 16.0
		l.light_energy = 1.5
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
	_sign("FESTA NA PRAIA", c + Vector3(0, 4.3, -3.1), 260, Color(1.0, 0.85, 0.2), 0.0)
	_flush()

	# The song, from the booth. It is held until the stream exists, then sat on the match clock.
	_beat = Sfx.emitter("festa", 6.0, 12.0, 150.0, false)
	_beat.position = c + Vector3(0, 2.5, -3.0)
	add_child(_beat)

	# Who is here. Their own dice, a fixed seed, and a ring round the booth, all facing it.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	_stand(c + Vector3(0, 0, -4.4), Kit.face(Vector3(0, 0, 1)), Kit.DANCE, "local")
	var placed := 0
	var tries := 0
	while placed < DANCERS and tries < DANCERS * 6:
		tries += 1
		var ang := rng.randf() * TAU
		var r := rng.randf_range(3.4, 9.0)
		var at := c + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var roll := rng.randf()
		var pose := Kit.DANCE
		if roll > 0.9:
			pose = Kit.DRINK
		elif roll > 0.82:
			pose = Kit.CLAP
		elif roll > 0.7:
			pose = Kit.CHEER
		var arch := "tourist" if rng.randf() < 0.5 else "local"
		if _stand(at, Kit.face(c - at), pose, arch):
			placed += 1


## One person on the sand at `at`, unless something solid is there.
func _stand(at: Vector3, yaw: float, idle: int, arch: String) -> bool:
	if Nav.blocked(at) or Layout.on_play_area(at, 1.0):
		return false
	Places.add_stand(at, yaw, idle, arch, {"stay": true})
	return true


func _process(delta: float) -> void:
	var t := MatchState.time
	var day := t / maxf(MatchState.duration, 1.0)
	var night := smoothstep(0.7, 1.0, day)
	for i in _lights.size():
		_lights[i].light_color = Color.from_hsv(fposmod(t * 0.2 + i * 0.25, 1.0), 0.7, 1.0)
		_lights[i].light_energy = (1.2 + 2.8 * night) * (0.85 + 0.15 * sin(t * 6.0 + i))
	_sync_song(delta)
	if multiplayer.is_server() and MatchState.running and not MatchState.ended:
		_restock_t -= delta
		if _restock_t <= 0.0:
			_restock_t = RESTOCK_EVERY
			_restock()


## Keeps everyone on the same bar: from the match clock while there is one, free-running
## otherwise (in the lobby the clock stands still and would only make it stutter).
func _sync_song(delta: float) -> void:
	if _beat == null or _beat.stream == null:
		return
	var length := _beat.stream.get_length()
	if length < 0.1:
		if not _beat.playing:
			_beat.play()
		return
	if not _beat.playing:
		_beat.play(fposmod(MatchState.time, length) if MatchState.running else 0.0)
		_sync_t = 2.0
		return
	_sync_t -= delta
	if _sync_t > 0.0 or not MatchState.running:
		return
	_sync_t = 2.0
	var want := fposmod(MatchState.time, length)
	var off := absf(_beat.get_playback_position() - want)
	if minf(off, length - off) > DRIFT:
		_beat.seek(want)


## Host: puts back what has been taken from the ground round the booth.
func _restock() -> void:
	var g = Net.game
	if g == null:
		return
	var have := 0
	for id in g.drops:
		var d: Dictionary = g.drops[id]
		if d.money != 0 or d.pos.distance_to(DB.FESTA_POS) > NEAR:
			continue
		for item in d.items:
			if item in DB.FESTA_LOOT:
				have += 1
				break
	var made := 0
	while have < DB.FESTA_STOCK and made < RESTOCK_MAX:
		var item: String = DB.FESTA_LOOT[randi() % DB.FESTA_LOOT.size()]
		var a := randf() * TAU
		var r := randf_range(2.5, 10.0)
		var p := DB.FESTA_POS + Vector3(cos(a) * r, 0.2, sin(a) * r)
		g.srv_add_drop(DB.clear_of_solids(p, 0.8), 0, {item: 1})
		have += 1
		made += 1
