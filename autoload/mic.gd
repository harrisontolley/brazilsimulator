extends Node
## Microphone capture: loudness for robbery, raw PCM relay for proximity voice.

const VOICE_RANGE := 40.0
const DECIMATE := 3
const VOICE_GATE := 0.06
const MAX_PACKET := 8000

## Smoothed 0..1 loudness. Hold fake_shout (V) to simulate shouting without a mic.
var loudness := 0.0
var available := false

var _capture: AudioEffectCapture
var _player: AudioStreamPlayer
var _raw := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Mic")
	AudioServer.set_bus_mute(idx, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(idx, _capture)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Mic"
	add_child(_player)
	_player.play()
	available = true


func _process(delta: float) -> void:
	var frames := PackedVector2Array()
	if available:
		var n := _capture.get_frames_available()
		if n > 0:
			frames = _capture.get_buffer(n)
			var sum := 0.0
			for f in frames:
				sum += f.x * f.x
			var db := linear_to_db(maxf(sqrt(sum / n), 0.00001))
			_raw = clampf(inverse_lerp(-42.0, -8.0, db), 0.0, 1.0)
	var target := _raw
	if Input.is_action_pressed("fake_shout"):
		target = maxf(target, 0.9)
	loudness = lerpf(loudness, target, minf(1.0, (18.0 if target > loudness else 5.0) * delta))
	if Net.game != null and frames.size() > 0 and _raw > VOICE_GATE:
		_send_voice(frames)


func _send_voice(frames: PackedVector2Array) -> void:
	var n := mini(frames.size() / DECIMATE, MAX_PACKET / 2)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var f := frames[i * DECIMATE]
		data.encode_s16(i * 2, int(clampf((f.x + f.y) * 0.5, -1.0, 1.0) * 32767.0))
	var rate := int(AudioServer.get_mix_rate()) / DECIMATE
	if multiplayer.is_server():
		_relay(1, rate, data)
	else:
		srv_voice.rpc_id(1, rate, data)


@rpc("any_peer", "call_remote", "unreliable")
func srv_voice(rate: int, data: PackedByteArray) -> void:
	if data.size() <= MAX_PACKET:
		_relay(multiplayer.get_remote_sender_id(), rate, data)


func _relay(from: int, rate: int, data: PackedByteArray) -> void:
	var g = Net.game
	if g == null:
		return
	var src = g.players.get(from)
	if src == null:
		return
	for pid in g.ready_peers:
		if pid == from:
			continue
		var p = g.players.get(pid)
		if p == null or p.global_position.distance_to(src.global_position) > VOICE_RANGE:
			continue
		if pid == 1:
			cl_voice(from, rate, data)
		else:
			cl_voice.rpc_id(pid, from, rate, data)


@rpc("authority", "call_remote", "unreliable")
func cl_voice(from: int, rate: int, data: PackedByteArray) -> void:
	var g = Net.game
	if g == null:
		return
	var p = g.players.get(from)
	if p != null:
		p.voice_push(rate, data)
