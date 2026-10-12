extends Node3D
## The sound of people talking: nobody says anything, but everyone has a voice.
##
## Purely local. A few voices follow whoever is talking nearest the listener and string
## synthesized syllables together, each speaker at their own pitch and pace so a table of
## four does not sound like one person. Its own players, so a burst of gunfire never has to
## steal one from a conversation or the other way round.

const VOICES := 6
const REACH := 18.0
const REFRESH := 0.35

var _players: Array[AudioStreamPlayer3D] = []
var _who := PackedInt32Array()
var _next := PackedFloat32Array()
var _said := PackedInt32Array()
var _speakers: Array = []
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_who.resize(VOICES)
	_next.resize(VOICES)
	_said.resize(VOICES)
	_who.fill(-1)
	for k in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 2.5
		p.max_distance = REACH + 8.0
		p.volume_db = -7.0
		p.attenuation_filter_cutoff_hz = 20500.0
		add_child(p)
		_players.append(p)


func tick(delta: float, acts: Node3D) -> void:
	var g = Net.game
	if g == null or g.local_player == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH
		_speakers = acts.speakers_near(g.local_player.global_position, REACH, VOICES)
	for k in VOICES:
		if k >= _speakers.size():
			_who[k] = -1
			continue
		var i: int = _speakers[k][1]
		if _who[k] != i:
			# A new speaker draws breath first.
			_who[k] = i
			_next[k] = _rng.randf_range(0.05, 0.4)
			_said[k] = 0
		_next[k] -= delta
		if _next[k] > 0.0:
			continue
		var s: AudioStream = Sfx.syllable(_rng.randi())
		if s == null:
			continue
		var p := _players[k]
		p.position = _speakers[k][0] + Vector3(0, 1.4, 0)
		p.stream = s
		# Their own voice: fixed per person, with the lilt of a sentence on top.
		var voice := 0.72 + fposmod(i * 0.6180339, 1.0) * 0.75
		p.pitch_scale = voice * _rng.randf_range(0.92, 1.1)
		p.play()
		_said[k] += 1
		var pace := 0.15 + fposmod(i * 0.3819, 1.0) * 0.1
		# A pause for thought every few words.
		_next[k] = pace + (_rng.randf_range(0.25, 0.7) if _said[k] % _rng.randi_range(4, 9) == 0 else 0.0)
