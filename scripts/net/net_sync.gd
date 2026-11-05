class_name NetSync
extends RefCounted
## Builds MultiplayerSynchronizers for actors in code, so actor scenes don't need
## hand-made replication configs and every actor syncs the same way.
##
## Two synchronizers per actor:
##   "MoveSync"  authority = the actor's owner (a player's peer, or the host for NPCs):
##               position, rotation, velocity.
##   "StateSync" authority = the host: hp, state and any extra host-resolved properties.
## Properties the node doesn't have are skipped, so this works on the placeholder
## player today and picks up Fighter.hp/state once the combat workstream adds them.
## Call attach() in a spawn function so it runs identically on every peer.

const MOVE_PROPS: Array[String] = ["position", "rotation", "velocity"]
const STATE_PROPS: Array[String] = ["hp", "max_hp", "state", "team"]


static func attach(actor: Node, owner_peer: int, extra_state: Array[String] = []) -> void:
	actor.set_multiplayer_authority(owner_peer)
	_add_sync(actor, "MoveSync", MOVE_PROPS, owner_peer, true)
	var state_props: Array[String] = STATE_PROPS.duplicate()
	state_props.append_array(extra_state)
	_add_sync(actor, "StateSync", state_props, 1, false)


static func _add_sync(actor: Node, sync_name: String, props: Array[String], authority: int,
		always: bool) -> void:
	var config := SceneReplicationConfig.new()
	for prop in props:
		if not prop in actor:
			continue
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		# Spawn values come from the spawner (the host), so only host-owned props use them.
		config.property_set_spawn(path, authority == 1)
		config.property_set_replication_mode(path,
			SceneReplicationConfig.REPLICATION_MODE_ALWAYS if always
			else SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	if config.get_properties().is_empty():
		return
	var sync := MultiplayerSynchronizer.new()
	sync.name = sync_name
	sync.root_path = NodePath("..")
	sync.replication_config = config
	sync.set_multiplayer_authority(authority)
	actor.add_child(sync)
