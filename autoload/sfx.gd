extends Node
## Every sound in the game, synthesized at startup: there are no audio files.
##
## One-shots go through play(). Looping music and machines are emitters the scene owns.
## The four ambient beds (surf, crowd, traffic, rain) are mixed here from where the local
## player is standing.

const Layout := preload("res://scenes/world/layout.gd")

const RATE := 16000
const VOICES := 32
## How many different syllables people mumble in.
const BABBLE := 7

## 0..1, set by whoever knows it is raining.
var rain := 0.0

var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _beds := {}
var _rng := RandomNumberGenerator.new()
var _task := -1
var _horn_t := 0.0
var _muffled := false
var _low: AudioEffectLowPassFilter


func _ready() -> void:
	_rng.seed = 77
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 7.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 20500.0
		add_child(p)
		_pool.append(p)
	for bed in ["surf", "crowd", "traffic", "rain", "deep"]:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_beds[bed] = p
	# Synthesis takes a second or two; do it off the main thread while the menu is up.
	_task = WorkerThreadPool.add_task(_build)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


## One of the BABBLE syllables, or null until they have been made.
func syllable(k: int) -> AudioStream:
	return _streams.get("babble%d" % (k % BABBLE))


## Plays a one-shot at a place in the world.
func play(sound: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	var s = _streams.get(sound)
	if s == null:
		return
	# The next voice with nothing to say; failing that, whoever has been at it longest.
	var p := _pool[_next]
	for k in VOICES:
		var q := _pool[(_next + k) % VOICES]
		if not q.playing:
			p = q
			_next = (_next + k) % VOICES
			break
	_next = (_next + 1) % VOICES
	p.stream = s
	p.position = at
	p.volume_db = db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


## The stream called `sound` for a caller with a player of its own, or null if there is no
## such thing (or not yet).
func stream(sound: String) -> AudioStream:
	return _streams.get(sound)


## A looping source for the caller to add to the scene and move about. It starts itself
## once the sound exists.
func emitter(sound: String, db := 0.0, unit := 8.0, reach := 90.0, autoplay := true) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = unit
	p.max_distance = reach
	p.volume_db = db
	p.attenuation_filter_cutoff_hz = 20500.0
	p.set_meta("sound", sound)
	if not autoplay:
		p.set_meta("held", true)
	p.tree_entered.connect(_start.bind(p), CONNECT_DEFERRED)
	return p


func _start(p: AudioStreamPlayer3D) -> void:
	while not _streams.has(p.get_meta("sound")):
		await get_tree().create_timer(0.3).timeout
		if not is_instance_valid(p):
			return
	if p.is_inside_tree():
		p.stream = _streams[p.get_meta("sound")]
		if not p.has_meta("held"):
			p.play()


func _process(delta: float) -> void:
	var g = Net.game
	var levels := {"surf": 0.0, "crowd": 0.0, "traffic": 0.0, "rain": 0.0, "deep": 0.0}
	if g != null and g.local_player != null:
		var at: Vector3 = g.local_player.global_position
		# Loudest where the waves break; out at sea it is a wash, up in the city a murmur.
		var off: float = at.z - Layout.SHORE_Z
		levels.surf = (clampf(1.0 - off / 110.0, 0.05, 1.0) if off > 0.0 else clampf(1.0 + off / 160.0, 0.4, 1.0)) * 0.55
		levels.crowd = clampf(g.crowd.near.size() / 30.0, 0.0, 1.0) * 0.5
		var flow: float = g.traffic.flow(MatchState.time)
		levels.traffic = clampf(1.0 - absf(at.z - 61.0) / 55.0, 0.0, 1.0) * clampf(1.0 - at.y / 60.0, 0.2, 1.0) * (0.25 + 0.5 * flow)
		levels.rain = rain * 0.7
		# A stopped road is a road full of horns.
		_horn_t -= delta
		if flow < 0.2 and _horn_t <= 0.0 and absf(at.z - 61.0) < 70.0:
			_horn_t = _rng.randf_range(0.25, 1.1)
			var v: Dictionary = g.traffic.vehicles[_rng.randi() % g.traffic.vehicles.size()]
			var vp: Vector3 = v.body.global_position
			if absf(vp.x - at.x) < 90.0:
				play("horn", vp + Vector3(0, 1, 0), -4.0, _rng.randf_range(0.8, 1.25))
	_muffle(Layout.cam_under)
	if Layout.cam_under:
		levels.deep = 0.9
	for bed in _beds:
		var p: AudioStreamPlayer = _beds[bed]
		var want: float = levels[bed]
		var now := db_to_linear(p.volume_db)
		var v := lerpf(now, want, minf(1.0, 2.5 * delta))
		p.volume_db = linear_to_db(maxf(v, 0.0001))
		if v > 0.002 and not p.playing and _streams.has(bed):
			p.stream = _streams[bed]
			p.play()
		elif v <= 0.002 and p.playing:
			p.stop()


## Under water everything loses its top end. (The bed that plays down there is already dull.)
func _muffle(on: bool) -> void:
	if on == _muffled:
		return
	_muffled = on
	if _low == null:
		_low = AudioEffectLowPassFilter.new()
		_low.cutoff_hz = 520.0
		_low.resonance = 0.7
		AudioServer.add_bus_effect(0, _low)
	AudioServer.set_bus_effect_enabled(0, AudioServer.get_bus_effect_count(0) - 1, on)


# --- synthesis (runs on a worker thread) ---

func _build() -> void:
	var made := {}
	made["surf"] = _wav(_surf(), true)
	made["crowd"] = _wav(_murmur(), true)
	made["traffic"] = _wav(_hum(), true)
	made["rain"] = _wav(_rain(), true)
	made["samba"] = _wav(_samba(), true)
	made["funk"] = _wav(_funk(), true)
	made["siren"] = _wav(_siren(), true)
	made["engine"] = _wav(_engine(), true)
	made["heli"] = _wav(_heli(), true)
	made["shot"] = _wav(_shot(), false)
	made["punch"] = _wav(_punch(), false)
	made["horn"] = _wav(_horn(), false)
	made["whistle"] = _wav(_whistle(), false)
	made["cheer"] = _wav(_cheer(), false)
	made["cash"] = _wav(_cash(), false)
	made["kick"] = _wav(_thump(120.0, 0.12), false)
	made["firework"] = _wav(_firework(), false)
	made["crash"] = _wav(_crash(), false)
	made["thunder"] = _wav(_thunder(), false)
	made["headshot"] = _wav(_headshot(), false)
	made["ko"] = _wav(_ko(), false)
	made["dry"] = _wav(_dry(), false)
	made["reload"] = _wav(_reload(), false)
	made["giggle"] = _wav(_giggle(), false)
	made["sniff"] = _wav(_sniff(), false)
	made["retch"] = _wav(_retch(), false)
	made["heartbeat"] = _wav(_heartbeat(), false)
	for k in 4:
		made["scream%d" % k] = _wav(_scream(k), false)
	made["grunt"] = _wav(_voice(0.22, [150.0, 120.0, 95.0], [620.0, 1050.0], 0.35, 5), false)
	made["die"] = _wav(_voice(0.7, [210.0, 170.0, 110.0, 80.0], [560.0, 980.0], 0.3, 6), false)
	made["shout"] = _wav(_voice(0.4, [230.0, 300.0, 240.0], [640.0, 1900.0], 0.15, 7), false)
	# Dogs: a yap, a woof and a boom, by size, and the rest of what they have to say.
	made["bark0"] = _wav(_bark([820.0, 1050.0, 600.0], 0.09, 10), false)
	made["bark1"] = _wav(_bark([380.0, 470.0, 260.0], 0.13, 11), false)
	made["bark2"] = _wav(_bark([190.0, 240.0, 130.0], 0.17, 12), false)
	made["growl"] = _wav(_growl(), false)
	made["yelp"] = _wav(_voice(0.24, [700.0, 1250.0, 1100.0, 600.0], [1100.0, 2300.0], 0.12, 13), false)
	made["whine"] = _wav(_voice(0.65, [820.0, 980.0, 900.0, 700.0], [900.0, 2500.0], 0.05, 14), false)
	made["bite"] = _wav(_bite(), false)
	# Each gun its own voice.
	made["revolver"] = _wav(_gun(0.55, 110.0, 40.0, 0.07, 0.16, 0.9), false)
	made["smg"] = _wav(_gun(0.25, 210.0, 90.0, 0.03, 0.07, 1.0), false)
	made["rifle"] = _wav(_gun(0.5, 170.0, 55.0, 0.045, 0.14, 0.85), false)
	made["shotgun"] = _wav(_gun(0.8, 95.0, 32.0, 0.1, 0.22, 0.45), false)
	made["sniper"] = _wav(_sniper(), false)
	made["launch"] = _wav(_launch(), false)
	made["rocket"] = _wav(_rocket(), true)
	made["boom"] = _wav(_boom(), false)
	made["clink"] = _wav(_clink(), false)
	made["smash"] = _wav(_smash(), false)
	made["fire"] = _wav(_fire(), true)
	made["throw"] = _wav(_throw(), false)
	# The sea: going in, pulling through it, coming up for air, and the two-stroke of a jet ski.
	made["splash"] = _wav(_splash(0.9, 0.22, 21), false)
	made["plop"] = _wav(_splash(0.28, 0.07, 22), false)
	made["gasp"] = _wav(_gasp(), false)
	made["bubbles"] = _wav(_bubbles(), false)
	made["deep"] = _wav(_deep(), true)
	made["ski"] = _wav(_ski(), true)
	made["tick"] = _wav(_tick(1500.0), false)
	made["tick_kill"] = _wav(_tick(900.0), false)
	made["bell"] = _wav(_bell(), false)
	made["roll"] = _wav(_roll(), true)
	for k in BABBLE:
		made["babble%d" % k] = _wav(_syllable(k), false)
	# What people dance to when they bring their own: two bars each, at the tempo of the feet.
	made["em_passinho"] = _wav(_tune(126.0, [0, 6, 8, 16, 22, 24, 27], [4, 12, 20, 28, 30], 2,
			{0: 45, 6: 45, 8: 48, 14: 43, 16: 45, 22: 45, 24: 50, 28: 48},
			{0: 69, 3: 72, 6: 76, 8: 74, 11: 72, 14: 69, 16: 69, 19: 72, 22: 76, 24: 79, 26: 76, 28: 74, 30: 72}), true)
	made["em_fio"] = _wav(_tune(120.0, [0, 4, 8, 12, 16, 20, 24, 28], [4, 12, 20, 28], 2,
			{0: 48, 8: 43, 16: 45, 24: 41},
			{0: 72, 2: 76, 4: 79, 6: 76, 8: 71, 10: 74, 12: 79, 14: 74, 16: 72, 18: 76, 20: 81, 22: 76, 24: 72, 26: 77, 28: 81, 30: 77}), true)
	made["em_toma"] = _wav(_tune(140.0, [0, 8, 16, 24, 28], [4, 12, 20, 26, 30], 4,
			{0: 43, 8: 43, 16: 38, 24: 43},
			{0: 79, 4: 79, 8: 76, 12: 81, 16: 79, 24: 76}), true)
	made["em_cossaco"] = _wav(_tune(150.0, [0, 8, 16, 24], [4, 12, 20, 28], 4,
			{0: 45, 4: 52, 8: 45, 12: 52, 16: 40, 20: 52, 24: 40, 28: 52},
			{0: 69, 2: 71, 4: 72, 6: 74, 8: 76, 12: 76, 16: 77, 18: 76, 20: 74, 22: 72, 24: 71, 28: 68}), true)
	made["em_trenzinho"] = _wav(_tune(116.0, [0, 4, 8, 12, 16, 20, 24, 28], [12, 28], 2,
			{0: 48, 4: 52, 8: 55, 12: 60, 16: 50, 20: 53, 24: 55, 28: 62},
			{0: 72, 4: 72, 8: 76, 12: 79, 13: 79, 16: 74, 20: 74, 24: 77, 28: 81, 29: 81}), true)
	made["clap"] = _wav(_clap(), false)
	made["pou"] = _wav(_pou(), false)
	made["whoosh"] = _wav(_whoosh(), false)
	_adopt.call_deferred(made)


func _adopt(made: Dictionary) -> void:
	_streams = made


func _wav(f: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var peak := 0.001
	for v in f:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(f.size() * 2)
	var k := 30000.0 / maxf(peak, 1.0)
	for i in f.size():
		bytes.encode_s16(i * 2, int(f[i] * k))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = f.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(int(seconds * RATE))
	return f


## Adds a decaying sine, optionally sliding in pitch, starting `at` seconds in.
func _tone(f: PackedFloat32Array, at: float, hz: float, hz_end: float, decay: float, amp: float) -> void:
	var start := int(at * RATE)
	var n := mini(int(decay * 6.0 * RATE), f.size() - start)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(hz, hz_end, minf(1.0, t / (decay * 3.0))) / RATE
		f[start + i] += sin(ph) * exp(-t / decay) * amp


## Adds a burst of noise, low-passed by `soft` (1 = white), starting `at` seconds in.
func _hiss(f: PackedFloat32Array, rng: RandomNumberGenerator, at: float, decay: float, amp: float, soft := 1.0) -> void:
	var start := int(at * RATE)
	var n := mini(int(decay * 6.0 * RATE), f.size() - start)
	var y := 0.0
	for i in n:
		y += soft * (rng.randf_range(-1.0, 1.0) - y)
		f[start + i] += y * exp(-float(i) / RATE / decay) * amp


## Water thrown up and falling back: a slap, then spray that takes `tail` seconds to settle.
func _splash(seconds: float, tail: float, seed_value: int) -> PackedFloat32Array:
	var f := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_tone(f, 0.0, 95.0, 45.0, 0.05, 0.9)
	_hiss(f, rng, 0.0, 0.03, 1.0, 0.5)
	_hiss(f, rng, 0.02, tail, 0.8, 0.28)
	_hiss(f, rng, 0.05, tail * 0.6, 0.35, 0.8)
	# Drops coming back down.
	for k in int(seconds * 22.0):
		var at := 0.08 + rng.randf() * maxf(seconds - 0.2, 0.05)
		_tone(f, at, rng.randf_range(900.0, 2600.0), rng.randf_range(1400.0, 3200.0), 0.006, 0.12 * (1.0 - at / seconds))
	return f


## Breaking the surface with empty lungs.
func _gasp() -> PackedFloat32Array:
	var f := _buf(0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lo := 0.0
	var hi := 0.0
	for i in f.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lo += 0.32 * (x - lo)
		hi += 0.06 * (x - hi)
		# The breath in, rising, with a catch of voice in it.
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.3, 0.55, t))
		f[i] = ((lo - hi) * 0.9 + sin(TAU * lerpf(260.0, 420.0, t / 0.5) * t) * 0.12) * env
	return f


func _bubbles() -> PackedFloat32Array:
	var f := _buf(0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 24
	for k in 16:
		var hz := rng.randf_range(260.0, 900.0)
		_tone(f, rng.randf() * 0.55, hz, hz * 1.7, 0.014, rng.randf_range(0.2, 0.6))
	return f


## What the sea sounds like from inside it: a low press on the ears, slowly breathing.
func _deep() -> PackedFloat32Array:
	var f := _buf(4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 25
	var y := 0.0
	var z := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.012 * (rng.randf_range(-1.0, 1.0) - y)
		z += 0.2 * (y - z)
		f[i] = z * (0.7 + 0.3 * sin(TAU * t / 4.0)) + sin(TAU * 48.0 * t) * 0.01 * (0.5 + 0.5 * sin(TAU * t / 2.0))
	return f


## A jet ski: a small engine at full shout with water going through it.
func _ski() -> PackedFloat32Array:
	var f := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 26
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.3 * (rng.randf_range(-1.0, 1.0) - y)
		var buzz := 0.0
		for h in range(1, 6):
			buzz += sin(TAU * 92.0 * h * t + sin(TAU * 31.0 * t) * 0.6) / h
		f[i] = buzz * 0.5 * (0.75 + 0.25 * sin(TAU * 46.0 * t)) + y * 0.35
	return f


func _surf() -> PackedFloat32Array:
	var f := _buf(4.0)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.09 * (rng.randf_range(-1.0, 1.0) - y)
		var swell := 0.5 + 0.5 * sin(TAU * t / 4.0)
		f[i] = y * (0.25 + 0.75 * swell * swell)
	return f


func _murmur() -> PackedFloat32Array:
	var f := _buf(3.0)
	var rng := RandomNumberGenerator.new()
	var a := 0.0
	var b := 0.0
	for i in f.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		a += 0.16 * (x - a)
		b += 0.03 * (x - b)
		f[i] = (a - b) * (0.6 + 0.2 * sin(TAU * t / 1.5) + 0.2 * sin(TAU * t + 1.0))
	return f


func _hum() -> PackedFloat32Array:
	var f := _buf(2.0)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.035 * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * 2.0 + sin(TAU * 55.0 * t) * 0.12 + sin(TAU * 82.0 * t) * 0.06
	return f


func _rain() -> PackedFloat32Array:
	var f := _buf(2.0)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var x := rng.randf_range(-1.0, 1.0)
		y += 0.35 * (x - y)
		f[i] = (x - y) * 0.6 + y * 0.3
	return f


## One bar of batucada: surdo, caixa, tamborim and agogô.
func _samba() -> PackedFloat32Array:
	var step := 0.15
	var f := _buf(step * 16.0)
	var rng := RandomNumberGenerator.new()
	var caixa := [1.0, 0.4, 0.4, 0.8, 0.4, 0.4, 0.9, 0.4, 0.5, 0.4, 0.9, 0.4, 1.0, 0.4, 0.6, 0.5]
	for s in 16:
		var at := s * step
		_hiss(f, rng, at, 0.02, 0.22 * caixa[s])
		if s == 4 or s == 12:
			_tone(f, at, 82.0, 62.0, 0.11, 0.9)
		elif s == 0 or s == 8:
			_tone(f, at, 70.0, 60.0, 0.035, 0.5)
		if s in [0, 2, 3, 5, 7, 8, 10, 12, 13, 15]:
			_tone(f, at, 1900.0, 1700.0, 0.012, 0.22)
		if s in [0, 6, 10]:
			_tone(f, at, 880.0, 880.0, 0.05, 0.2)
		if s in [3, 8, 13]:
			_tone(f, at, 660.0, 660.0, 0.05, 0.2)
	return f


## Two bars of a tune in sixteenths: which steps the kick and the clap fall on, how often the
## shaker ticks, and the notes (step -> MIDI number) of a bass and of a plucked lead over it.
func _tune(bpm: float, kick: Array, clap: Array, shake: int, bass: Dictionary, lead: Dictionary) -> PackedFloat32Array:
	var step := 60.0 / bpm / 4.0
	var f := _buf(step * 32.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(bpm)
	for s in 32:
		var at := s * step
		if s in kick:
			_tone(f, at, 110.0, 46.0, 0.055, 1.0)
		if s in clap:
			_hiss(f, rng, at, 0.028, 0.5, 0.7)
			_hiss(f, rng, at + 0.012, 0.02, 0.3, 0.9)
		if s % shake == 0:
			_hiss(f, rng, at, 0.012, 0.12 if s % 4 == 0 else 0.07)
		if bass.has(s):
			var hz := 440.0 * pow(2.0, (bass[s] - 69) / 12.0)
			_tone(f, at, hz, hz, 0.11, 0.55)
			_tone(f, at, hz * 2.0, hz * 2.0, 0.05, 0.16)
		if lead.has(s):
			var hz := 440.0 * pow(2.0, (lead[s] - 69) / 12.0)
			_tone(f, at, hz, hz, 0.075, 0.3)
			_tone(f, at, hz * 2.0, hz * 2.0, 0.04, 0.11)
			_tone(f, at, hz * 3.0, hz * 3.0, 0.025, 0.05)
	return f


## Two palms meeting: not one crack but three, a few thousandths apart.
func _clap() -> PackedFloat32Array:
	var f := _buf(0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for k in 3:
		_hiss(f, rng, k * 0.007, 0.006 + k * 0.007, 0.5, 0.75)
	_tone(f, 0.0, 1100.0, 900.0, 0.01, 0.25)
	return f


## A gun as done by somebody's mouth.
func _pou() -> PackedFloat32Array:
	var f := _voice(0.34, [520.0, 300.0, 170.0, 120.0], [700.0, 1100.0], 0.25, 41)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	_hiss(f, rng, 0.0, 0.012, 0.9, 0.5)
	_tone(f, 0.0, 190.0, 70.0, 0.05, 0.8)
	return f


## A leg going through the air with intent.
func _whoosh() -> PackedFloat32Array:
	var f := _buf(0.32)
	var rng := RandomNumberGenerator.new()
	rng.seed = 43
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE / 0.32
		var e := sin(PI * t)
		y += lerpf(0.05, 0.5, e) * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * e * e
	return f


## One bar of tamborzão, the baile funk beat.
func _funk() -> PackedFloat32Array:
	var step := 60.0 / 130.0 / 4.0
	var f := _buf(step * 16.0)
	var rng := RandomNumberGenerator.new()
	for s in 16:
		var at := s * step
		if s in [0, 6, 8]:
			_tone(f, at, 95.0, 42.0, 0.07, 1.0)
		if s in [3, 7, 11, 13]:
			_hiss(f, rng, at, 0.03, 0.45, 0.6)
		if s in [2, 5, 10, 14, 15]:
			_tone(f, at, 230.0, 200.0, 0.03, 0.4)
	return f


func _siren() -> PackedFloat32Array:
	var f := _buf(1.2)
	for i in f.size():
		var t := float(i) / RATE
		var hz := 650.0 if t < 0.6 else 870.0
		f[i] = sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 3.0 * t) * 0.18
	return f


func _engine() -> PackedFloat32Array:
	var f := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.2 * (rng.randf_range(-1.0, 1.0) - y)
		var saw := fposmod(t * 90.0, 1.0) * 2.0 - 1.0
		f[i] = saw * 0.5 + sin(TAU * 45.0 * t) * 0.4 + y * 0.2
	return f


func _heli() -> PackedFloat32Array:
	var f := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.06 * (rng.randf_range(-1.0, 1.0) - y)
		var chop := pow(0.5 + 0.5 * sin(TAU * 11.0 * t), 3.0)
		f[i] = y * (0.3 + chop * 1.5) + sin(TAU * 44.0 * t) * 0.1
	return f


func _shot() -> PackedFloat32Array:
	var f := _buf(0.45)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.05, 1.0)
	_hiss(f, rng, 0.0, 0.12, 0.5, 0.15)
	_tone(f, 0.0, 150.0, 55.0, 0.05, 0.8)
	return f


## A voice holding one open vowel while its pitch runs through `pitch` (Hz, evenly spaced over
## the length). `rough` is how much the throat tears at it.
func _voice(seconds: float, pitch: Array, vowel: Array, rough: float, seed_value: int) -> PackedFloat32Array:
	var f := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + seed_value
	var n := f.size()
	var ph := 0.0
	var wobble := 0.0
	var breath := 0.0
	for i in n:
		var u := float(i) / n
		var at := u * (pitch.size() - 1)
		var k := mini(int(at), pitch.size() - 2)
		var f0: float = lerpf(pitch[k], pitch[k + 1], at - k)
		wobble += 0.02 * (rng.randf_range(-1.0, 1.0) - wobble)
		ph += TAU * f0 * (1.0 + wobble * rough * 6.0 + 0.012 * sin(u * seconds * 38.0)) / RATE
		var v := 0.0
		for h in range(1, mini(12, int(7000.0 / f0)) + 1):
			var hz := f0 * h
			var w := 1.0 / (1.0 + pow((hz - vowel[0]) / 170.0, 2.0)) + 0.8 / (1.0 + pow((hz - vowel[1]) / 240.0, 2.0)) + 0.5 / (1.0 + pow((hz - 3000.0) / 400.0, 2.0)) + 0.04
			v += sin(ph * h) * w
		breath += 0.5 * (rng.randf_range(-1.0, 1.0) - breath)
		var env := minf(1.0, u * 18.0) * minf(1.0, (1.0 - u) * 5.0)
		f[i] = (v * (1.0 + rough * breath * 1.5) + breath * rough * 2.0) * env
	return f


## A gunshot: the crack, the thump under it that slides from `hz` to `hz_end`, and a tail of
## `tail` seconds. `soft` below 1 takes the top off the crack.
func _gun(seconds: float, hz: float, hz_end: float, thump: float, tail: float, soft: float) -> PackedFloat32Array:
	var f := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hz * 7.0)
	_hiss(f, rng, 0.0, 0.012, 1.0, soft)
	_hiss(f, rng, 0.0, tail, 0.45, 0.2)
	_tone(f, 0.0, hz, hz_end, thump, 0.9)
	return f


## A crack that takes the air apart, and then the valley answering.
func _sniper() -> PackedFloat32Array:
	var f := _buf(1.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	_hiss(f, rng, 0.0, 0.006, 1.2, 1.0)
	_hiss(f, rng, 0.0, 0.3, 0.5, 0.25)
	_tone(f, 0.0, 240.0, 45.0, 0.06, 1.0)
	_hiss(f, rng, 0.28, 0.25, 0.16, 0.08)
	_hiss(f, rng, 0.6, 0.3, 0.09, 0.05)
	return f


## A cough and a rising roar as the motor lights.
func _launch() -> PackedFloat32Array:
	var f := _buf(0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 32
	_hiss(f, rng, 0.0, 0.04, 1.0, 0.5)
	_tone(f, 0.0, 90.0, 40.0, 0.09, 0.9)
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.25 * (rng.randf_range(-1.0, 1.0) - y)
		f[i] += y * minf(1.0, t * 14.0) * exp(-t * 3.0) * 0.8
	return f


## The motor of a rocket going past, to loop while it flies.
func _rocket() -> PackedFloat32Array:
	var f := _buf(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += 0.3 * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * (0.75 + 0.25 * sin(TAU * 46.0 * t)) + sin(TAU * 92.0 * t) * 0.12
	return f


## The big one: a crack, a slam you feel in the chest, and rubble coming down after it.
func _boom() -> PackedFloat32Array:
	var f := _buf(2.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	_hiss(f, rng, 0.0, 0.02, 1.0, 0.9)
	_tone(f, 0.0, 85.0, 24.0, 0.22, 1.3)
	_tone(f, 0.02, 48.0, 20.0, 0.35, 0.9)
	_hiss(f, rng, 0.0, 0.45, 0.7, 0.12)
	_hiss(f, rng, 0.35, 0.5, 0.25, 0.05)
	for k in 9:
		_hiss(f, rng, 0.5 + rng.randf() * 1.2, 0.03, 0.12, 0.4)
	return f


## Metal off concrete.
func _clink() -> PackedFloat32Array:
	var f := _buf(0.2)
	_tone(f, 0.0, 2600.0, 2400.0, 0.03, 0.6)
	_tone(f, 0.0, 3900.0, 3700.0, 0.02, 0.4)
	_tone(f, 0.0, 700.0, 500.0, 0.012, 0.5)
	return f


## A bottle going, and what was in it catching.
func _smash() -> PackedFloat32Array:
	var f := _buf(0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	_hiss(f, rng, 0.0, 0.03, 1.0, 1.0)
	for k in 8:
		_tone(f, rng.randf() * 0.12, rng.randf_range(2500.0, 6000.0), rng.randf_range(2200.0, 5000.0), 0.03, 0.3)
	_hiss(f, rng, 0.06, 0.25, 0.6, 0.1)
	_tone(f, 0.06, 70.0, 40.0, 0.12, 0.6)
	return f


## Flames, to loop: a low rush with the crackle on top.
func _fire() -> PackedFloat32Array:
	var f := _buf(1.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var y := 0.0
	for i in f.size():
		y += 0.06 * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * 3.0
	for k in 40:
		_hiss(f, rng, rng.randf() * 1.4, 0.004, rng.randf_range(0.1, 0.5), 1.0)
	return f


## An arm coming over.
func _throw() -> PackedFloat32Array:
	var f := _buf(0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var y := 0.0
	for i in f.size():
		var u := float(i) / f.size()
		y += (0.05 + u * 0.3) * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * sin(u * PI)
	return f


## The small sound of having hit something: for the shooter's ears only.
func _tick(hz: float) -> PackedFloat32Array:
	var f := _buf(0.09)
	_tone(f, 0.0, hz, hz * 0.8, 0.012, 0.8)
	_tone(f, 0.0, hz * 2.0, hz * 1.9, 0.006, 0.4)
	return f


## A croupier's bell: struck once and left to ring.
func _bell() -> PackedFloat32Array:
	var f := _buf(1.4)
	_tone(f, 0.0, 1180.0, 1180.0, 0.22, 0.7)
	_tone(f, 0.0, 2390.0, 2390.0, 0.12, 0.35)
	_tone(f, 0.0, 3560.0, 3560.0, 0.06, 0.2)
	_tone(f, 0.0, 400.0, 300.0, 0.01, 0.5)
	return f


## A ball running round a wooden track, to loop: a hollow rumble with the grain in it.
func _roll() -> PackedFloat32Array:
	var f := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var lo := 0.0
	var mid := 0.0
	for i in f.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		lo += 0.03 * (x - lo)
		mid += 0.3 * (x - mid)
		f[i] = lo * 3.0 + (mid - lo) * 0.25 * (0.6 + 0.4 * sin(TAU * 12.0 * t)) + sin(TAU * 96.0 * t) * 0.05
	return f


## One bark: a rough shout with a hard front edge, as long as the dog is big.
func _bark(pitch: Array, seconds: float, seed_value: int) -> PackedFloat32Array:
	var f := _voice(seconds, pitch, [pitch[0] * 1.9, pitch[0] * 3.6], 0.9, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := _buf(seconds + 0.08)
	for i in f.size():
		out[i] = f[i] * exp(-float(i) / RATE / (seconds * 0.55)) * 0.2
	_hiss(out, rng, 0.0, 0.02, 0.5, 0.5)
	return out


## Deep in the throat, rattling.
func _growl() -> PackedFloat32Array:
	var f := _voice(0.9, [88.0, 82.0, 92.0, 80.0], [420.0, 900.0], 1.0, 15)
	for i in f.size():
		var t := float(i) / RATE
		f[i] *= 0.55 + 0.45 * sin(TAU * 27.0 * t)
	return f


## Teeth meeting.
func _bite() -> PackedFloat32Array:
	var f := _buf(0.18)
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	_hiss(f, rng, 0.0, 0.012, 1.0, 0.6)
	_tone(f, 0.0, 900.0, 300.0, 0.015, 0.6)
	_tone(f, 0.01, 180.0, 90.0, 0.03, 0.7)
	return f


## Four people's screams: high or low, short or long, one that breaks in the middle.
func _scream(k: int) -> PackedFloat32Array:
	match k:
		0:
			return _voice(0.95, [520.0, 760.0, 800.0, 740.0, 520.0], [950.0, 1650.0], 0.3, 0)
		1:
			return _voice(1.3, [430.0, 640.0, 610.0, 660.0, 600.0, 380.0], [880.0, 1500.0], 0.45, 1)
		2:
			return _voice(0.6, [300.0, 430.0, 400.0, 250.0], [780.0, 1300.0], 0.55, 2)
	return _voice(1.1, [600.0, 900.0, 940.0, 620.0, 880.0, 560.0], [1000.0, 1900.0], 0.25, 3)


## One syllable of nothing in particular: a voiced buzz shaped by two vowel resonances, some
## with a consonant on the front. Strung together at random they pass for talk at a distance.
func _syllable(k: int) -> PackedFloat32Array:
	var f := _buf(0.2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + k
	var f0 := 165.0 + k * 9.0
	var vowels := [[700.0, 1150.0], [320.0, 2300.0], [480.0, 900.0], [600.0, 1700.0], [380.0, 760.0], [820.0, 1400.0], [450.0, 2000.0]]
	var v: Array = vowels[k % vowels.size()]
	var n := f.size()
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := float(i) / n
		ph += TAU * f0 * (1.0 + 0.06 * sin(u * PI) - 0.04 * u) / RATE
		# A buzz rich in harmonics, each weighted by how near it falls to a resonance.
		var s := 0.0
		for h in range(1, 14):
			var hz := f0 * h
			var w := 1.0 / (1.0 + pow((hz - v[0]) / 130.0, 2.0)) + 0.7 / (1.0 + pow((hz - v[1]) / 180.0, 2.0)) + 0.06
			s += sin(ph * h) * w / h
		f[i] = s * sin(u * PI) * exp(-t * 2.0)
	if k % 3 != 0:
		_hiss(f, rng, 0.0, 0.008, 0.25, 0.7)
	return f


## A wet crack with a ring to it: the sound of having got the head.
func _headshot() -> PackedFloat32Array:
	var f := _buf(0.4)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.012, 1.0)
	_tone(f, 0.0, 420.0, 180.0, 0.03, 0.9)
	_tone(f, 0.01, 2100.0, 1900.0, 0.07, 0.35)
	return f


## Lights out: a deep thud and a falling whistle.
func _ko() -> PackedFloat32Array:
	var f := _buf(0.7)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.03, 0.8, 0.2)
	_tone(f, 0.0, 90.0, 45.0, 0.06, 1.0)
	_tone(f, 0.05, 1400.0, 500.0, 0.14, 0.3)
	return f


## Hammer on an empty chamber.
func _dry() -> PackedFloat32Array:
	var f := _buf(0.12)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.004, 0.9)
	_tone(f, 0.0, 2400.0, 2000.0, 0.008, 0.5)
	return f


## Magazine out, magazine in, slide forward.
func _reload() -> PackedFloat32Array:
	var f := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	for at in [0.0, 0.45, 0.8]:
		_hiss(f, rng, at, 0.012, 0.8, 0.6)
		_tone(f, at, 900.0, 500.0, 0.015, 0.5)
	_tone(f, 0.8, 300.0, 200.0, 0.03, 0.6)
	return f


## Lança-perfume: a run of helium ha-ha-has, climbing.
func _giggle() -> PackedFloat32Array:
	var f := _buf(1.3)
	for k in 9:
		var hz := 620.0 + k * 45.0 + (k % 2) * 80.0
		_tone(f, k * 0.12, hz, hz * 0.8, 0.025, 0.7)
		_tone(f, k * 0.12, hz * 2.0, hz * 1.6, 0.02, 0.25)
	return f


## A long pull up one nostril.
func _sniff() -> PackedFloat32Array:
	var f := _buf(0.6)
	var rng := RandomNumberGenerator.new()
	var y := 0.0
	for i in f.size():
		var t := float(i) / RATE
		y += (0.15 + 0.6 * t) * (rng.randf_range(-1.0, 1.0) - y)
		f[i] = y * minf(1.0, t / 0.05) * exp(-maxf(0.0, t - 0.35) * 14.0)
	return f


## Stomach on its way up.
func _retch() -> PackedFloat32Array:
	var f := _buf(1.0)
	var rng := RandomNumberGenerator.new()
	_tone(f, 0.0, 180.0, 90.0, 0.09, 0.9)
	_tone(f, 0.02, 360.0, 150.0, 0.07, 0.4)
	_hiss(f, rng, 0.25, 0.1, 0.9, 0.12)
	_hiss(f, rng, 0.3, 0.05, 0.5, 0.5)
	return f


## Two thumps, the way a chest sounds from the inside.
func _heartbeat() -> PackedFloat32Array:
	var f := _buf(0.6)
	_tone(f, 0.0, 70.0, 45.0, 0.04, 1.0)
	_tone(f, 0.18, 60.0, 40.0, 0.05, 0.8)
	return f


func _punch() -> PackedFloat32Array:
	var f := _buf(0.2)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.02, 0.7, 0.3)
	_tone(f, 0.0, 110.0, 60.0, 0.03, 1.0)
	return f


func _thump(hz: float, seconds: float) -> PackedFloat32Array:
	var f := _buf(seconds)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.006, 0.4)
	_tone(f, 0.0, hz, hz * 0.6, seconds / 5.0, 1.0)
	return f


func _horn() -> PackedFloat32Array:
	var f := _buf(0.5)
	for i in f.size():
		var t := float(i) / RATE
		var e := minf(1.0, t / 0.02) * minf(1.0, (0.5 - t) / 0.05)
		var a := sin(TAU * 370.0 * t) + sin(TAU * 1110.0 * t) * 0.35
		var b := sin(TAU * 466.0 * t) + sin(TAU * 1398.0 * t) * 0.35
		f[i] = (a + b) * e * 0.4
	return f


func _whistle() -> PackedFloat32Array:
	var f := _buf(0.55)
	var rng := RandomNumberGenerator.new()
	var ph := 0.0
	for i in f.size():
		var t := float(i) / RATE
		ph += TAU * (2700.0 + sin(TAU * 32.0 * t) * 180.0) / RATE
		var e := minf(1.0, t / 0.01) * minf(1.0, (0.55 - t) / 0.06)
		f[i] = (sin(ph) * 0.8 + rng.randf_range(-0.1, 0.1)) * e
	return f


func _cheer() -> PackedFloat32Array:
	var f := _buf(2.4)
	var rng := RandomNumberGenerator.new()
	var a := 0.0
	var b := 0.0
	for i in f.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		a += 0.25 * (x - a)
		b += 0.04 * (x - b)
		var e := minf(1.0, t / 0.25) * exp(-maxf(0.0, t - 0.6) * 1.6)
		f[i] = (a - b) * e * (0.8 + 0.2 * sin(TAU * 7.0 * t))
	return f


func _cash() -> PackedFloat32Array:
	var f := _buf(0.4)
	_tone(f, 0.0, 1320.0, 1320.0, 0.05, 0.6)
	_tone(f, 0.07, 1760.0, 1760.0, 0.06, 0.6)
	return f


func _firework() -> PackedFloat32Array:
	var f := _buf(1.6)
	var rng := RandomNumberGenerator.new()
	_tone(f, 0.0, 500.0, 1900.0, 0.12, 0.15)
	_hiss(f, rng, 0.42, 0.22, 1.0, 0.12)
	_tone(f, 0.42, 90.0, 40.0, 0.12, 0.9)
	for k in 30:
		_hiss(f, rng, 0.55 + rng.randf() * 0.8, 0.004, 0.25)
	return f


func _crash() -> PackedFloat32Array:
	var f := _buf(0.7)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.09, 1.0, 0.5)
	for hz in [420.0, 610.0, 890.0, 1340.0]:
		_tone(f, 0.0, hz, hz * 0.97, 0.08, 0.25)
	_tone(f, 0.0, 80.0, 45.0, 0.06, 0.8)
	return f


func _thunder() -> PackedFloat32Array:
	var f := _buf(2.5)
	var rng := RandomNumberGenerator.new()
	_hiss(f, rng, 0.0, 0.5, 1.0, 0.03)
	_hiss(f, rng, 0.15, 0.3, 0.6, 0.06)
	_hiss(f, rng, 0.6, 0.4, 0.5, 0.02)
	return f
