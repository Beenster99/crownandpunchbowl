extends Node
## Networking entry point (stub). The networking workstream owns this file.
## Model: host-authoritative ENet. The host simulates NPCs, items and hit
## resolution; each client owns its own player's movement and sends actions as RPCs.
## Solo play uses OfflineMultiplayerPeer so the same code paths run.

signal players_changed()
signal connection_failed()
signal server_disconnected()

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4

## peer_id -> {"name": String, "farmer": int}
var players := {}


func start_solo(player_name: String, farmer: int) -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: {"name": player_name, "farmer": farmer}}
	players_changed.emit()


func host(player_name: String, farmer: int, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": player_name, "farmer": farmer}}
	players_changed.emit()
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	players_changed.emit()


func is_host() -> bool:
	return multiplayer.is_server()
