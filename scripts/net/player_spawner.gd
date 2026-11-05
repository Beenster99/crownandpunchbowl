class_name PlayerSpawner
extends MultiplayerSpawner
## Spawns one player per connected peer, named P<peer_id> and owned by that peer.
## The host spawns once Net.all_peers_loaded fires; MultiplayerSpawner replicates the
## spawn (and despawn when someone drops) to every client. Works the same in solo.
##
## Usage in a pub scene's _ready():
##   var spawner := PlayerSpawner.new()
##   spawner.spawn_points = [...]          # Vector3 per slot, host first
##   add_child(spawner)
##   spawner.setup($Actors)
##   spawner.player_spawned.connect(...)   # e.g. add to camera targets
##   Net.level_ready()

## Emitted on every peer when a player node enters the tree.
signal player_spawned(player: Node3D)

@export var player_scene: PackedScene = preload("res://scenes/actors/player.tscn")
## One position per slot. Slots follow Net.player_ids() order.
@export var spawn_points: Array[Vector3] = [
	Vector3(-1.5, 0, 4.5), Vector3(-0.5, 0, 4.5), Vector3(0.5, 0, 4.5), Vector3(1.5, 0, 4.5)]


func _init() -> void:
	name = "PlayerSpawner"
	spawn_function = _spawn_player


## Points the spawner at the node players are parented to and hooks up Net.
## Call after the spawner is in the tree.
func setup(actors: Node) -> void:
	spawn_path = get_path_to(actors)
	Net.all_peers_loaded.connect(_spawn_all)
	Net.player_dropped.connect(_on_player_dropped)


## Returns the player node for a peer, or null.
func get_player(peer_id: int) -> Node3D:
	return get_node_or_null(spawn_path).get_node_or_null("P%d" % peer_id) as Node3D


func _spawn_all() -> void:
	if not multiplayer.is_server():
		return
	var ids := Net.player_ids()
	for slot in ids.size():
		var id: int = ids[slot]
		if get_player(id) == null:
			spawn({"peer": id, "farmer": int(Net.players[id]["farmer"]), "slot": slot})


func _spawn_player(data: Variant) -> Node:
	var peer: int = data["peer"]
	var player := player_scene.instantiate() as Node3D
	player.name = "P%d" % peer
	player.position = spawn_points[int(data["slot"]) % spawn_points.size()]
	if "farmer_index" in player:
		player.set("farmer_index", int(data["farmer"]))
	player.add_to_group(Net.SPAWNED_GROUP)
	NetSync.attach(player, peer)
	player.tree_entered.connect(func(): player_spawned.emit(player), CONNECT_ONE_SHOT)
	return player


func _on_player_dropped(peer_id: int, _player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var p := get_player(peer_id)
	if p:
		p.queue_free()  # MultiplayerSpawner despawns it on the clients.
