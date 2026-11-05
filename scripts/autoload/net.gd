extends Node
## Networking entry point: solo, host and join, the lobby, starting the night and
## moving pub to pub. Owned by the networking workstream (see docs/NETWORKING.md).
##
## Model: host-authoritative ENet. The host simulates NPCs, items, hit resolution and
## pub flow. Each client owns its own player's movement and sends actions as RPCs.
## Solo uses OfflineMultiplayerPeer so the same code paths run.
##
## Typical flow:
##   Net.host(name, farmer) / Net.join(address, name, farmer)
##   Net.set_farmer(i), Net.set_ready(true)            # any peer
##   Net.set_pub(i), Net.set_difficulty(i)             # host only
##   Net.start_game()                                  # host only, when can_start()
##   level _ready(): connect Net.all_peers_loaded, then call Net.level_ready()
##   Net.next_pub() / Net.restart_pub()                # host only

## The player list or a player's farmer/ready flag changed.
signal players_changed()
## The host changed the pub or the difficulty.
signal lobby_settings_changed()
## Client: we reached the host and it accepted us into the lobby.
signal joined_lobby()
## Client: could not reach the host, or the host turned us away (see last_error).
signal connection_failed()
## Client: the host went away. Net has already returned to the main menu.
signal server_disconnected()
## A player left mid-session. Emitted on every peer.
signal player_dropped(peer_id: int, player_name: String)
## Host: host_info changed (addresses found, router port opened or not).
signal host_info_changed()
## Every peer is loading a pub. Emitted on every peer just before the scene changes.
signal pub_loading(pub_index: int)
## Host only: every connected peer has loaded the current pub, so it is safe to spawn.
signal all_peers_loaded()

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
## Bump when the lobby or spawn RPCs change so old builds can't join new hosts.
const PROTOCOL_VERSION := 1
const MENU_SCENE := "res://scenes/main/main_menu.tscn"
## Every node a MultiplayerSpawner creates joins this group (players, NPCs, items),
## so the host can despawn them cleanly before a pub change.
const SPAWNED_GROUP := "net_spawned"
## Seconds a join waits for the host before giving up with a useful message.
const JOIN_TIMEOUT := 10.0

## peer_id -> {"name": String, "farmer": int, "ready": bool}
var players := {}
## True from start_game() until leave(). Joining is refused while true.
var in_game := false
## Human-readable reason for the last failure (rejected, lost host…), for menus to show.
var last_error := ""

## Host only: what to tell mates so they can join. Keys:
##   port, lan (Array of home-network IPs), vpn (Tailscale/ZeroTier/Radmin IPs),
##   public_ip ("" until known), upnp ("off" | "trying" | "open" | "failed"), upnp_error,
##   router_ip (the router's own internet address from UPnP), cgnat (bool: the provider
##   shares the public address, so only a VPN will work for internet play).
var host_info := {}
## Set false to skip UPnP and the public address lookup (tests, LAN parties).
var use_upnp := true

var _local_name := "Farmer"
var _join_attempt := 0
var _join_target := ""
var _join_port := DEFAULT_PORT
var _port_opener: PortOpener
var _local_farmer := 0
## Host only: peers that have finished loading the current pub.
var _loaded := {}
var _all_loaded_sent := false


func _ready() -> void:
	_port_opener = PortOpener.new()
	_port_opener.name = "PortOpener"
	_port_opener.finished.connect(_on_port_opened)
	add_child(_port_opener)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Session lifecycle ----------------------------------------------------------

func start_solo(player_name: String, farmer: int) -> void:
	_reset()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: _make_player(player_name, farmer, true)}
	players_changed.emit()


func host(player_name: String, farmer: int, port := DEFAULT_PORT) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		last_error = ("Couldn't open port %d. Is another copy of the game already hosting? " +
			"Try a different port. (%s)") % [port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: _make_player(player_name, farmer, true)}
	players_changed.emit()
	_start_host_info(port)
	return OK


## `address` may include a port ("81.2.3.4:24566"), which then wins over `port`.
func join(address: String, player_name: String, farmer: int, port := DEFAULT_PORT) -> Error:
	_reset()
	_local_name = player_name
	_local_farmer = farmer
	var target := NetAddress.parse(address, port)
	if target.is_empty():
		last_error = "That address doesn't look right. Type the host's address, like 81.2.3.4 or 81.2.3.4:%d." % DEFAULT_PORT
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(target[0], target[1])
	if err != OK:
		last_error = "Couldn't find %s. Check the address. (%s)" % [target[0], error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	_join_target = "%s:%d" % target
	_join_port = target[1]
	_join_attempt += 1
	var attempt := _join_attempt
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(_on_join_timeout.bind(attempt, target[0]))
	return OK


func _on_join_timeout(attempt: int, address: String) -> void:
	if attempt != _join_attempt or players.has(local_id()) or not is_online():
		return
	last_error = join_failure_message(address)
	leave()
	connection_failed.emit()


## What to tell a player whose join got no answer, based on the address they typed.
func join_failure_message(address: String) -> String:
	var msg := "No answer from %s after %d seconds. " % [_join_target, int(JOIN_TIMEOUT)]
	if NetAddress.is_loopback(address):
		return msg + "127.0.0.1 means this computer. Type the address shown in the host's lobby instead."
	if NetAddress.is_private(address):
		return msg + ("That's a home-network address, so it only works on the same Wi-Fi or network " +
			"as the host. Over the internet, use the host's internet address. Also check the host " +
			"allowed the game through Windows Firewall.")
	return msg + ("Check the address and port match the host's lobby, that the host's lobby says " +
		"the router port is open (or they forwarded UDP %d), and that Windows Firewall allowed " +
		"the game on their PC. If the host's lobby warns about a shared internet address, use a " +
		"VPN like Tailscale instead.") % _join_port


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	_loaded.clear()
	_join_attempt += 1  # cancels any pending join timeout
	if _port_opener:
		_port_opener.close()
	host_info = {}
	players_changed.emit()


func is_host() -> bool:
	return multiplayer.is_server()


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func local_id() -> int:
	return multiplayer.get_unique_id()


## Peer ids in a stable order (host first). Use for spawn slots and HUD order.
func player_ids() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


# --- Lobby ------------------------------------------------------------------------

func set_farmer(farmer: int) -> void:
	_request_update({"farmer": clampi(farmer, 0, GameData.FARMERS.size() - 1)})


func set_ready(is_ready: bool) -> void:
	_request_update({"ready": is_ready})


func set_player_name(player_name: String) -> void:
	_request_update({"name": player_name})


func set_pub(index: int) -> void:
	if not is_host():
		return
	GameData.current_pub_index = clampi(index, 0, GameData.PUBS.size() - 1)
	_broadcast_lobby()


func set_difficulty(index: int) -> void:
	if not is_host():
		return
	GameData.difficulty_index = clampi(index, 0, GameData.DIFFICULTIES.size() - 1)
	_broadcast_lobby()


## Host: everyone (except the host, who starts it) has pressed ready.
func can_start() -> bool:
	if not is_host() or in_game:
		return false
	for id in players:
		if id != 1 and not players[id]["ready"]:
			return false
	return true


func start_game() -> void:
	if not can_start():
		return
	_load_pub.rpc(GameData.current_pub_index, GameData.difficulty_index)


# --- Pub flow ---------------------------------------------------------------------

## Host: everyone moves to the next pub together.
func next_pub() -> void:
	if not is_host():
		return
	await _despawn_replicated()
	_load_pub.rpc((GameData.current_pub_index + 1) % GameData.PUBS.size(), GameData.difficulty_index)


## Host: everyone reloads the current pub (after a wipe).
func restart_pub() -> void:
	if not is_host():
		return
	await _despawn_replicated()
	_load_pub.rpc(GameData.current_pub_index, GameData.difficulty_index)


## Called by a pub scene at the end of its _ready(). The host emits all_peers_loaded
## once every connected peer has called it, so spawns never race a client's scene load.
## Host: frees everything a MultiplayerSpawner replicated (group SPAWNED_GROUP) and lets
## the despawns reach clients before the scene changes. Otherwise the despawns arrive
## after the clients have already freed the old pub, and every one logs an error.
func _despawn_replicated() -> void:
	var nodes := get_tree().get_nodes_in_group(SPAWNED_GROUP)
	if nodes.is_empty():
		return
	for n in nodes:
		n.queue_free()
	for i in 3:
		await get_tree().process_frame


func level_ready() -> void:
	if is_host():
		_mark_loaded(1)
	else:
		_client_loaded.rpc_id(1)


@rpc("authority", "call_local", "reliable")
func _load_pub(pub_index: int, difficulty_index: int) -> void:
	in_game = true
	GameData.current_pub_index = pub_index
	GameData.difficulty_index = difficulty_index
	_loaded.clear()
	_all_loaded_sent = false
	pub_loading.emit(pub_index)
	get_tree().change_scene_to_file(GameData.current_pub()["scene"])


@rpc("any_peer", "reliable")
func _client_loaded() -> void:
	if is_host():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	_loaded[peer_id] = true
	_check_all_loaded()


func _check_all_loaded() -> void:
	if _all_loaded_sent:
		return
	for id in players:
		if not _loaded.has(id):
			return
	_all_loaded_sent = true
	all_peers_loaded.emit()


# --- Lobby RPCs -------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _register(protocol: int, player_name: String, farmer: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL_VERSION:
		reason = "Different game version from the host."
	elif in_game:
		reason = "The fight has already started."
	elif players.size() >= MAX_PLAYERS:
		reason = "The pub's full (%d players max)." % MAX_PLAYERS
	if reason != "":
		_rejected.rpc_id(id, reason)
		# Give the rejection a moment to arrive before dropping the peer.
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer and multiplayer.has_multiplayer_peer():
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	players[id] = _make_player(player_name, farmer, false)
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	last_error = reason
	leave()
	connection_failed.emit()


@rpc("any_peer", "reliable")
func _request_update_rpc(changes: Dictionary) -> void:
	if is_host():
		_apply_update(multiplayer.get_remote_sender_id(), changes)


func _request_update(changes: Dictionary) -> void:
	if is_host():
		_apply_update(1, changes)
	elif is_online():
		_request_update_rpc.rpc_id(1, changes)


func _apply_update(id: int, changes: Dictionary) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	if changes.get("farmer") is int:
		p["farmer"] = clampi(changes["farmer"], 0, GameData.FARMERS.size() - 1)
	if changes.get("ready") is bool and not in_game:
		p["ready"] = changes["ready"]
	if changes.get("name") is String:
		p["name"] = _clean_name(changes["name"])
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	players_changed.emit()
	lobby_settings_changed.emit()
	if is_online():
		_sync_lobby.rpc(players, GameData.current_pub_index, GameData.difficulty_index)


@rpc("authority", "reliable")
func _sync_lobby(new_players: Dictionary, pub_index: int, difficulty_index: int) -> void:
	var first := players.is_empty()
	players = new_players
	GameData.current_pub_index = pub_index
	GameData.difficulty_index = difficulty_index
	players_changed.emit()
	lobby_settings_changed.emit()
	if first and players.has(local_id()):
		joined_lobby.emit()


# --- Connection events ------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass  # Clients register themselves with _register; nothing to do until then.


func _on_connected_to_server() -> void:
	_register.rpc_id(1, PROTOCOL_VERSION, _local_name, _local_farmer)


func _on_connection_failed() -> void:
	last_error = join_failure_message(_join_target.rsplit(":", true, 1)[0])
	leave()
	connection_failed.emit()


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	var player_name: String = players[id]["name"]
	players.erase(id)
	_loaded.erase(id)
	_announce_drop.rpc(id, player_name)
	_broadcast_lobby()
	if in_game:
		_check_all_loaded()


@rpc("authority", "call_local", "reliable")
func _announce_drop(id: int, player_name: String) -> void:
	player_dropped.emit(id, player_name)
	Events.banner.emit("%s has gone home." % player_name, 3.0)


func _on_server_disconnected() -> void:
	last_error = "Lost connection to the host."
	leave()
	server_disconnected.emit()
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Host addresses and router port ------------------------------------------------

func _start_host_info(port: int) -> void:
	host_info = {
		"port": port, "lan": NetAddress.lan_addresses(), "vpn": NetAddress.vpn_addresses(),
		"public_ip": "", "upnp": "trying" if use_upnp else "off", "upnp_error": "",
		"router_ip": "", "cgnat": false,
	}
	host_info_changed.emit()
	if not use_upnp:
		return
	_port_opener.open(port)
	_port_opener.fetch_public_ip(_on_public_ip)


func _on_port_opened(result: Dictionary) -> void:
	if host_info.is_empty():
		return
	host_info["upnp"] = "open" if result["ok"] else "failed"
	host_info["upnp_error"] = result["error"]
	host_info["router_ip"] = result["external_ip"]
	_update_cgnat()


func _on_public_ip(ip: String) -> void:
	if host_info.is_empty():
		return
	host_info["public_ip"] = ip
	_update_cgnat()


## The router's internet address being private/shared, or not matching the address the
## outside world sees, means the provider puts several customers behind one address
## (carrier-grade NAT). Port opening can't help then; a VPN can.
func _update_cgnat() -> void:
	var router: String = host_info["router_ip"]
	var public: String = host_info["public_ip"]
	host_info["cgnat"] = router != "" and (NetAddress.is_private(router) or NetAddress.is_cgnat(router)
		or (public != "" and NetAddress.is_ipv4(public) and router != public))
	host_info_changed.emit()


## The address mates should type to join over the internet ("" if unknown).
func internet_address() -> String:
	var ip: String = host_info.get("public_ip", "")
	if ip == "":
		ip = host_info.get("router_ip", "")
	if ip == "" or NetAddress.is_private(ip):
		return ""
	var port: int = host_info.get("port", DEFAULT_PORT)
	return ip if port == DEFAULT_PORT else "%s:%d" % [ip, port]



# --- Helpers ----------------------------------------------------------------------

func _reset() -> void:
	leave()
	last_error = ""
	_all_loaded_sent = false


func _make_player(player_name: String, farmer: int, is_ready: bool) -> Dictionary:
	return {
		"name": _clean_name(player_name),
		"farmer": clampi(farmer, 0, GameData.FARMERS.size() - 1),
		"ready": is_ready,
	}


func _clean_name(player_name: String) -> String:
	var n := player_name.strip_edges().left(20)
	return n if n != "" else "Farmer"
