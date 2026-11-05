class_name CoopRules
extends Node
## Co-op rules that sit on top of combat: downed mates, reviving, wipes, and moving
## the group on when a pub is cleared. Add one to every pub scene. Host-authoritative:
## clients only report whether they're holding the revive button.
##
## Reviving: stand next to a downed mate and hold `interact` for `revive_time` seconds.
## Downed means Fighter.is_down() (DOWN, CRAWL or KO). The host calls
## Fighter.revive(fraction) if the fighter has it, else heal(max_hp * fraction).
## If every player is down at once the pub restarts; if the pub is cleared the
## group moves on to the next one.

## Emitted on every peer while someone is being picked up. progress is 0..1, and
## -1 when the reviver lets go. The HUD can draw a ring over `downed`.
signal revive_progress(downed: Node3D, reviver: Node3D, progress: float)
signal player_revived(downed: Node3D, reviver: Node3D)

@export var revive_radius := 1.6
@export var revive_time := 3.0
## Fraction of max_hp a revived player gets back.
@export var revive_hp_fraction := 0.35
@export var wipe_restart_delay := 4.0
@export var next_pub_delay := 6.0

## Host: peer_id -> holding interact.
var _holding := {}
## Host: downed player name -> seconds of revive accumulated.
var _progress := {}
var _local_holding := false
var _flow_pending := false


func _ready() -> void:
	add_to_group("coop_rules")
	Events.pub_cleared.connect(_on_pub_cleared)
	Net.player_dropped.connect(_on_player_dropped)


func _on_player_dropped(peer_id: int, _player_name: String) -> void:
	_holding.erase(peer_id)


func _process(_delta: float) -> void:
	var holding := Input.is_action_pressed("interact")
	if holding == _local_holding:
		return
	_local_holding = holding
	if multiplayer.is_server():
		_holding[1] = holding
	else:
		_set_holding.rpc_id(1, holding)


@rpc("any_peer", "reliable")
func _set_holding(holding: bool) -> void:
	if multiplayer.is_server():
		_holding[multiplayer.get_remote_sender_id()] = holding


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _flow_pending:
		return
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return
	var any_standing := false
	for p in players:
		if not is_downed(p):
			any_standing = true
			continue
		_tick_revive(p, players, delta)
	if not any_standing:
		_on_wipe()


static func is_downed(p: Node) -> bool:
	return p.has_method("is_down") and p.is_down()


func _tick_revive(downed: Node3D, players: Array, delta: float) -> void:
	var reviver: Node3D = null
	for p in players:
		if p == downed or is_downed(p):
			continue
		if not _holding.get(p.get_multiplayer_authority(), false):
			continue
		if p.global_position.distance_to(downed.global_position) <= revive_radius:
			reviver = p
			break
	var key := downed.name
	if reviver == null:
		if _progress.has(key):
			_progress.erase(key)
			_sync_progress.rpc(downed.get_path(), NodePath(), -1.0)
		return
	_progress[key] = _progress.get(key, 0.0) + delta
	var t: float = clampf(_progress[key] / revive_time, 0.0, 1.0)
	_sync_progress.rpc(downed.get_path(), reviver.get_path(), t)
	if t >= 1.0:
		_progress.erase(key)
		_revive(downed)
		_announce_revive.rpc(downed.get_path(), reviver.get_path())


func _revive(p: Node) -> void:
	if p.has_method("revive"):
		p.revive(revive_hp_fraction)
	elif p.has_method("heal") and "max_hp" in p:
		p.heal(float(p.get("max_hp")) * revive_hp_fraction)


@rpc("authority", "call_local", "unreliable_ordered")
func _sync_progress(downed_path: NodePath, reviver_path: NodePath, t: float) -> void:
	var downed := get_node_or_null(downed_path) as Node3D
	if downed:
		revive_progress.emit(downed, get_node_or_null(reviver_path) as Node3D, t)


@rpc("authority", "call_local", "reliable")
func _announce_revive(downed_path: NodePath, reviver_path: NodePath) -> void:
	var downed := get_node_or_null(downed_path) as Node3D
	var reviver := get_node_or_null(reviver_path) as Node3D
	if downed:
		player_revived.emit(downed, reviver)


func _on_wipe() -> void:
	_flow_pending = true
	_announce_wipe.rpc()
	await get_tree().create_timer(wipe_restart_delay).timeout
	Net.restart_pub()


@rpc("authority", "call_local", "reliable")
func _announce_wipe() -> void:
	Events.all_players_down.emit()
	Events.banner.emit("Thrown out! Back in you go…", wipe_restart_delay)


func _on_pub_cleared(_pub_id: String) -> void:
	if not multiplayer.is_server() or _flow_pending:
		return
	_flow_pending = true
	var next: Dictionary = GameData.PUBS[(GameData.current_pub_index + 1) % GameData.PUBS.size()]
	_announce_next.rpc(next["name"])
	await get_tree().create_timer(next_pub_delay).timeout
	Net.next_pub()


@rpc("authority", "call_local", "reliable")
func _announce_next(pub_name: String) -> void:
	Events.banner.emit("Pub cleared! On to %s." % pub_name, next_pub_delay)
