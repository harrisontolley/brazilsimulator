extends Node
## Connection lifecycle. Host is a listen-server; gameplay RPCs live on the Game scene.

signal join_failed

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 16
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

## Overridden with --port=N, e.g. to run a second host on one machine.
var PORT := DEFAULT_PORT
var local_name := "Kid"
var game: Node = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			PORT = int(a.trim_prefix("--port="))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(leave)


func host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file(GAME_SCENE)
	return true


func join(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	return true


func leave() -> void:
	game = null
	MatchState.running = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## Peer id of whoever invoked the current RPC; 1 when the host called it directly.
func sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


func _on_connected() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit()
