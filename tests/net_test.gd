extends SceneTree
## Two-process co-op test over real ENet on localhost. Run with tests/run_net_test.sh,
## or by hand: one process with `-- host`, another with `-- client`.
## Checks: join + lobby sync, host-picked pub/difficulty, synced start, both players
## spawned on both peers with the right owners, client movement replicated to the host,
## networked combat (a client grabs, knees and throws a host-owned punter, and the host
## sees the hits), pub-to-pub transition, and the host seeing a client drop.

const PORT := 24599
var net: Node
var gd: Node


func _initialize() -> void:
	await process_frame
	net = root.get_node("Net")
	gd = root.get_node("GameData")
	var role := "host" if "host" in OS.get_cmdline_user_args() else "client"
	var ok: bool
	if role == "host":
		ok = await _host()
	else:
		ok = await _client()
	print("NET %s %s" % [role.to_upper(), "OK" if ok else "FAILED"])
	quit(0 if ok else 1)


func _host() -> bool:
	if net.host("Hosty", 0, PORT) != OK:
		return _fail("host: couldn't open port")
	net.set_pub(2)
	net.set_difficulty(3)
	if not await _wait(func(): return net.players.size() == 2, 15.0):
		return _fail("host: client never joined")
	if not await _wait(func(): return net.can_start(), 10.0):
		return _fail("host: client never readied")
	net.start_game()
	if not await _wait(func(): return _players_spawned(2), 10.0):
		return _fail("host: players not spawned")
	var cid: int = net.player_ids()[1]
	var cp := _player(cid)
	if cp.get_multiplayer_authority() != cid or _player(1).get_multiplayer_authority() != 1:
		return _fail("host: wrong authorities")
	if not await _wait(func(): return absf(_player(cid).position.x - 3.0) < 0.05, 10.0):
		return _fail("host: client movement not replicated (x=%s)" % _player(cid).position.x)
	_player(1).position.x = -3.0  # client checks this arrives
	# Networked combat: the client grabs and knees a punter; the host resolves the hits.
	var hits := []
	var events := root.get_node("Events")
	var on_hit := func(info: Dictionary):
		if info.get("attacker") == _player(cid):
			hits.append(info)
	events.hit_landed.connect(on_hit)
	if not await _wait(func(): return hits.size() > 0, 20.0):
		return _fail("host: never saw the client's hit land")
	events.hit_landed.disconnect(on_hit)
	print("NET host saw client hit %s for %.1f" % [hits[0]["victim"].name, float(hits[0].get("damage", 0.0))])
	await create_timer(1.0).timeout
	net.next_pub()
	if not await _wait(func(): return gd.current_pub_index == 3 and _players_spawned(2), 10.0):
		return _fail("host: next pub didn't load with both players")
	if not await _wait(func(): return net.players.size() == 1, 15.0):
		return _fail("host: didn't notice the client leaving")
	await create_timer(0.5).timeout
	if _player(cid) != null:
		return _fail("host: dropped player's node still exists")
	return true


func _client() -> bool:
	await create_timer(0.5).timeout
	if net.join("127.0.0.1", "Clienty", 3, PORT) != OK:
		return _fail("client: couldn't start")
	if not await _wait(func(): return net.players.has(net.local_id()), 10.0):
		return _fail("client: never got into the lobby")
	if gd.current_pub_index != 2 or gd.difficulty_index != 3:
		return _fail("client: lobby settings not synced (%d, %d)" % [gd.current_pub_index, gd.difficulty_index])
	if net.players[net.local_id()]["farmer"] != 3:
		return _fail("client: farmer choice lost")
	net.set_ready(true)
	if not await _wait(func(): return _players_spawned(2), 15.0):
		return _fail("client: players not spawned")
	var me := _player(net.local_id())
	if not me.is_multiplayer_authority():
		return _fail("client: doesn't own its player")
	me.position.x = 3.0
	if not await _wait(func(): return absf(_player(1).position.x + 3.0) < 0.05, 10.0):
		return _fail("client: host movement not replicated")
	if not await _client_fight(me):
		return false
	if not await _wait(func(): return gd.current_pub_index == 3 and _players_spawned(2), 15.0):
		return _fail("client: didn't follow the host to the next pub")
	await create_timer(1.0).timeout
	net.leave()
	await create_timer(1.0).timeout
	return true


## Grab a host-owned punter, knee it and throw it, checking each step replicates back.
func _client_fight(me: Node3D) -> bool:
	if not await _wait(func(): return _punter() != null, 10.0):
		return _fail("client: no punters replicated")
	var npc: Node3D = _punter()
	var hp_before: float = npc.hp
	for attempt in 5:
		var dir: Vector3 = Vector3(1, 0, 0)
		me.global_position = npc.global_position - dir * 0.9
		me.rotation.y = atan2(-dir.x, -dir.z)
		await create_timer(0.3).timeout
		me.request_grab(npc)
		if await _wait(func(): return me.state == me.State.GRABBING, 1.5):
			break
	if me.state != me.State.GRABBING:
		return _fail("client: grab never took (me %s, npc %s)" % [me.State.keys()[me.state], npc.State.keys()[npc.state]])
	if not await _wait(func(): return npc.state == npc.State.HELD, 2.0):
		return _fail("client: punter not shown as held")
	me.request_attack(&"knee")
	if not await _wait(func(): return npc.hp < hp_before, 5.0):
		return _fail("client: knee didn't hurt the punter (hp %s)" % npc.hp)
	me.request_throw()
	if not await _wait(func(): return me.state != me.State.GRABBING, 3.0):
		return _fail("client: throw didn't release the punter")
	print("NET client grabbed, kneed and threw %s (hp %.0f -> %.0f)" % [npc.name, hp_before, npc.hp])
	return true


func _punter() -> Node3D:
	for n in get_nodes_in_group("npcs"):
		if n.is_inside_tree() and not n.is_in_group("staff") and n.state == n.State.IDLE:
			return n
	return null


func _players_spawned(n: int) -> bool:
	if current_scene == null or not current_scene.has_node("Actors") or not current_scene.is_node_ready():
		return false
	var ps := get_nodes_in_group("players").filter(func(p): return p.is_inside_tree() and not p.is_queued_for_deletion())
	return ps.size() == n


func _player(id: int) -> Node3D:
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Actors/P%d" % id)


func _wait(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func _fail(msg: String) -> bool:
	push_error(msg)
	return false
