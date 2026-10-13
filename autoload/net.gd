extends Node
## Connection lifecycle. Host is a listen-server; gameplay RPCs live on the Game scene.
##
## Joining is a handshake on this node first, and only a matching build gets as far as
## loading the game scene: RPCs are matched by index, so two different builds would not fail
## loudly, they would call the wrong functions. The host also tries to open its own port on
## the router (UPnP) so a friend across the internet can get in without any router fiddling.

signal join_failed(reason: String)
## The router port mapping finished (or failed); read upnp_state and public_ip.
signal upnp_changed

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 16
const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
## How long a join may take, to reach the host and then to be let in.
const CONNECT_TIMEOUT := 10.0

## Overridden with --port=N, e.g. to run a second host on one machine.
var PORT := DEFAULT_PORT
var local_name := "Kid"
var game: Node = null
## Both ends must report the same one. Bump `application/config/version` when RPCs change.
## --version-override=X pretends to be another build, for testing the rejection.
var version := ""
## Shown on the menu after a match ends or a join fails.
var last_error := ""
## Peers that passed the version check; the game ignores everyone else.
var verified := {}

## "idle" (not tried), "working", "open", "natted" (router itself is behind another NAT),
## or "failed".
var upnp_state := "idle"
var public_ip := ""

var _upnp: UPNP
var _upnp_thread: Thread
var _mapped := false
var _mapped_ip := ""
var _mapped_ok := false
var _awaiting_welcome := false


func _ready() -> void:
	version = str(ProjectSettings.get_setting("application/config/version", "dev"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			PORT = int(a.trim_prefix("--port="))
		elif a.begins_with("--version-override="):
			version = a.trim_prefix("--version-override=")
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	multiplayer.peer_connected.connect(_tune)
	multiplayer.peer_disconnected.connect(func(pid: int): verified.erase(pid))


func _exit_tree() -> void:
	_stop_upnp()


func host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS - 1) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	verified.clear()
	last_error = ""
	_start_upnp()
	get_tree().change_scene_to_file(GAME_SCENE)
	return true


## `address` is an IP or name, optionally with :port. False if it could not even be tried;
## otherwise the result is the scene changing, or join_failed.
func join(address: String) -> bool:
	var ip := address.strip_edges()
	var port := PORT
	if ip.count(":") == 1:
		var parts := ip.split(":")
		ip = parts[0].strip_edges()
		var p := parts[1].strip_edges()
		if not p.is_valid_int() or int(p) < 1 or int(p) > 65535:
			last_error = "That port is not a number between 1 and 65535."
			return false
		port = int(p)
	if ip == "":
		last_error = "Type the host's address first."
		return false
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		last_error = "Could not use that address."
		return false
	multiplayer.multiplayer_peer = peer
	_awaiting_welcome = true
	# Nobody answering is not an error ENet reports quickly, so do not wait for it to.
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func():
		if _awaiting_welcome and multiplayer.multiplayer_peer == peer:
			_fail("Could not reach the host. Check the address, and that the host's firewall or router lets UDP port %d in." % port))
	return true


func leave() -> void:
	game = null
	_awaiting_welcome = false
	verified.clear()
	MatchState.running = false
	_stop_upnp()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## Peer id of whoever invoked the current RPC; 1 when the host called it directly.
func sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else 1


## Round trip to a peer, in seconds; 0 for yourself or when it cannot be told.
func rtt(pid: int) -> float:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or pid == multiplayer.get_unique_id():
		return 0.0
	var pp := peer.get_peer(pid)
	if pp == null:
		return 0.0
	return pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0


# --- the handshake ---

@rpc("any_peer", "call_remote", "reliable")
func srv_hello(their_version: String) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if their_version != version:
		cl_rejected.rpc_id(pid, "Different builds: the host has %s and you have %s. Get the same download." % [version, their_version])
		# Give the reason time to get out before the link goes.
		get_tree().create_timer(0.5).timeout.connect(func():
			var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if peer != null and multiplayer.is_server() and multiplayer.get_peers().has(pid):
				peer.disconnect_peer(pid))
		return
	verified[pid] = true
	print("[net] peer %d joined (%s)" % [pid, their_version])
	cl_welcome.rpc_id(pid)


@rpc("authority", "call_remote", "reliable")
func cl_welcome() -> void:
	if _awaiting_welcome:
		_awaiting_welcome = false
		get_tree().change_scene_to_file(GAME_SCENE)


@rpc("authority", "call_remote", "reliable")
func cl_rejected(reason: String) -> void:
	_fail(reason)


func _on_connected() -> void:
	_tune(1)
	srv_hello.rpc_id(1, version)
	# Connected is not the same as let in: the host may be a different build.
	var peer := multiplayer.multiplayer_peer
	get_tree().create_timer(CONNECT_TIMEOUT).timeout.connect(func():
		if _awaiting_welcome and multiplayer.multiplayer_peer == peer:
			_fail("The host did not answer. It may be a different build."))


func _on_failed() -> void:
	_fail("Could not reach the host. Check the address, and that the host's firewall or router lets UDP port %d in." % PORT)


func _on_server_gone() -> void:
	last_error = "The host left the game."
	print("[net] ", last_error)
	leave()


func _fail(reason: String) -> void:
	_awaiting_welcome = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	last_error = reason
	print("[net] join failed: ", reason)
	join_failed.emit(reason)


## A friend who drops off should be noticed in seconds, not the half minute ENet allows.
func _tune(pid: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	var pp := peer.get_peer(pid)
	if pp != null:
		pp.set_timeout(32, 4000, 10000)


# --- addresses to give a friend ---

## What a friend could type, best first: [{"label", "addr"}].
func join_addresses() -> Array:
	var out: Array = []
	if upnp_state == "open":
		out.append({"label": "Over the internet", "addr": _with_port(public_ip)})
	for a in local_addresses():
		out.append({"label": "Tailscale" if a.tailscale else "Same Wi-Fi or LAN", "addr": _with_port(a.ip)})
	return out


## This machine's IPv4 addresses worth offering: [{"ip", "tailscale"}], real networks first.
func local_addresses() -> Array:
	var plain: Array = []
	var tail: Array = []
	for ip in IP.get_local_addresses():
		var parts: PackedStringArray = ip.split(".")
		if parts.size() != 4 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		var second := int(parts[1])
		if int(parts[0]) == 100 and second >= 64 and second <= 127:
			tail.append({"ip": ip, "tailscale": true})
		else:
			plain.append({"ip": ip, "tailscale": false})
	return plain + tail


## One line for the host about whether the router let a friend in.
func upnp_text() -> String:
	match upnp_state:
		"working":
			return "Asking the router to let a friend in..."
		"open":
			return "Router opened port %d for you. Friends outside can join with the first address." % PORT
		"natted":
			return "Your internet provider shares one address between homes, so no port can be opened. Both of you use Tailscale (see the README)."
		"failed":
			return "The router would not open UDP port %d by itself. Forward it by hand, or both use Tailscale (see the README). The same Wi-Fi works as it is." % PORT
	return ""


func _with_port(ip: String) -> String:
	return ip if PORT == DEFAULT_PORT else "%s:%d" % [ip, PORT]


# --- UPnP ---

func _start_upnp() -> void:
	upnp_state = "idle"
	public_ip = ""
	var args := OS.get_cmdline_user_args()
	# Test runs are headless and many; they should not be punching holes in the router.
	var skip: bool = args.has("--no-upnp") or (DisplayServer.get_name() == "headless" and not args.has("--upnp"))
	if skip:
		return
	upnp_state = "working"
	_mapped = false
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(PORT))


## On a thread: discovery waits on the network for seconds.
func _upnp_work(port: int) -> void:
	var u := UPNP.new()
	_mapped_ip = ""
	_mapped_ok = false
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS:
		var gw := u.get_gateway()
		if gw != null and gw.is_valid_gateway():
			# Some routers refuse an open-ended lease, so ask again for a long one.
			var r := u.add_port_mapping(port, port, "Brazil Simulator", "UDP", 0)
			if r != UPNP.UPNP_RESULT_SUCCESS:
				r = u.add_port_mapping(port, port, "Brazil Simulator", "UDP", 14400)
			if r == UPNP.UPNP_RESULT_SUCCESS:
				_upnp = u
				_mapped = true
				_mapped_ok = true
				_mapped_ip = u.query_external_address()
	_upnp_finished.call_deferred()


func _upnp_finished() -> void:
	if _upnp_thread == null or not _upnp_thread.is_started():
		return
	_upnp_thread.wait_to_finish()
	if not _mapped_ok:
		upnp_state = "failed"
	elif _mapped_ip == "" or _is_private(_mapped_ip):
		upnp_state = "natted"
	else:
		upnp_state = "open"
		public_ip = _mapped_ip
	print("[net] upnp: ", upnp_state, " ", public_ip)
	upnp_changed.emit()


func _stop_upnp() -> void:
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	if _mapped and _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
	_mapped = false
	_upnp = null
	upnp_state = "idle"
	public_ip = ""


## Addresses a router reports as its own when something upstream is also translating.
func _is_private(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return true
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) or (a == 100 and b >= 64 and b <= 127)
