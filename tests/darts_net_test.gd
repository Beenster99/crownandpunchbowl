extends SceneTree
## Two-process darts test over real ENet on localhost. Run with tests/run_darts_net_test.sh.
## The host and a client chalk up at the same pub board, the host (captain) picks 301 and
## starts, both throw a turn, and each sees the other's darts and scores. Then the client
## leaves the game and the host sees the board go back to one player.

const PORT := 24598
var net: Node
var gd: Node


func _initialize() -> void:
	await process_frame
	net = root.get_node("Net")
	gd = root.get_node("GameData")
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	load("res://scripts/darts/darts_board.gd").require_pad = false  # no controllers headless
	var role := "host" if "host" in OS.get_cmdline_user_args() else "client"
	var ok: bool
	if role == "host":
		ok = await _host()
	else:
		ok = await _client()
	print("DARTSNET %s %s" % [role.to_upper(), "OK" if ok else "FAILED"])
	quit(0 if ok else 1)


func _host() -> bool:
	if net.host("Hosty", 0, PORT) != OK:
		return _fail("host: couldn't open port")
	net.set_pub(0)
	if not await _wait(func(): return net.players.size() == 2 and net.can_start(), 15.0):
		return _fail("host: client never joined and readied")
	net.start_game()
	if not await _wait(func(): return _board() != null and _players_spawned(2), 15.0):
		return _fail("host: pub didn't load")
	var board = _board()
	var cid: int = net.player_ids()[1]
	board.request_join()
	if not await _wait(func(): return board.game.players.size() == 2, 10.0):
		return _fail("host: client never chalked up")
	board.request_options(301, 1, true)
	board.request_start()
	if not board.is_local_turn():
		return _fail("host: captain should throw first")
	for i in 3:
		board.request_throw(_target(20, 3))
	print("DARTSNET host threw %s" % _labels(board))
	if not await _wait(func(): return board.game.thrower_peer() == cid and not board.game.turn_over, 5.0):
		return _fail("host: turn didn't pass to the client")
	if not await _wait(func(): return board.game.turn_over, 15.0):
		return _fail("host: client never threw three darts")
	var client_left: int = board.game.players[1]["remaining"]
	print("DARTSNET host saw client throw %s, on %d" % [_labels(board), client_left])
	if client_left >= 301 and board.game.note != "BUST":
		return _fail("host: client's darts didn't score")
	if not await _wait(func(): return board.game.players.size() == 1, 15.0):
		return _fail("host: client never left the game")
	if not await _wait(func(): return net.players.size() == 1, 15.0):
		return _fail("host: didn't see the client go")
	return true


func _client() -> bool:
	await create_timer(0.5).timeout
	if net.join("127.0.0.1", "Clienty", 1, PORT) != OK:
		return _fail("client: couldn't start")
	if not await _wait(func(): return net.players.has(net.local_id()), 10.0):
		return _fail("client: never got into the lobby")
	net.set_ready(true)
	if not await _wait(func(): return _board() != null and _players_spawned(2), 15.0):
		return _fail("client: pub didn't load")
	var board = _board()
	if not await _wait(func(): return board.game.players.size() == 1, 10.0):
		return _fail("client: host never chalked up")
	# Walk up to the oche and press interact, like a player would.
	var me = current_scene.get_node("Actors/P%d" % net.local_id())
	me.global_position = board.oche_point() + board.facing * 0.3
	await physics_frame
	if not board.handle_local_interact(me):
		return _fail("client: interact at the oche did nothing")
	if not await _wait(func(): return board.game.phase == 1 and board.game.start_score == 301, 10.0):
		return _fail("client: never saw the 301 game start")
	if not await _wait(func(): return board.game.turn_over and board.game.turn.size() > 0, 10.0):
		return _fail("client: never saw the host's darts")
	print("DARTSNET client saw host throw %s" % _labels(board))
	if not await _wait(func(): return board.is_local_turn(), 10.0):
		return _fail("client: our turn never came")
	if me.global_position.distance_to(board.oche_point()) > 0.5:
		return _fail("client: didn't step up to the oche")
	for i in 3:
		var n: int = board.game.turn.size()
		board.request_throw(_target(19, 3))
		if not await _wait(func(): return board.game.turn.size() == n + 1 or board.game.turn_over, 5.0):
			return _fail("client: dart %d never landed" % (i + 1))
		if board.game.turn_over:
			break
	print("DARTSNET client threw %s" % _labels(board))
	await create_timer(0.5).timeout
	board.request_leave()
	if not await _wait(func(): return not board.game.has_player(net.local_id()), 5.0):
		return _fail("client: couldn't leave the game")
	if board.local_input_locked():
		return _fail("client: controls still locked after leaving")
	net.leave()
	await create_timer(1.0).timeout
	return true


func _board():
	if current_scene == null or not current_scene.is_node_ready():
		return null
	var boards := get_nodes_in_group("darts_games")
	return boards[0] if not boards.is_empty() else null


func _target(n: int, m: int) -> Vector2:
	return load("res://scripts/darts/darts_rules.gd").target_point(n, m)


func _labels(board) -> String:
	var out := []
	for d in board.game.turn:
		out.append(String(d["label"]))
	return " ".join(out)


func _players_spawned(n: int) -> bool:
	var ps := get_nodes_in_group("players").filter(func(p): return p.is_inside_tree() and not p.is_queued_for_deletion())
	return ps.size() == n


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
