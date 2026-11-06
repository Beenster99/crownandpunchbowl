extends Node
## Darts test cases (see darts_test.gd). Loaded at runtime so the autoloads exist first.

var _failures := 0



signal finished(failures: int)


func run() -> void:
	await get_tree().process_frame
	_test_scoring()
	_test_checkouts()
	_test_501()
	_test_bust_rules()
	_test_legs_and_players()
	_test_sync()
	await _test_in_pub()
	if _failures == 0:
		print("DARTS OK")
	finished.emit(_failures)


func _test_scoring() -> void:
	_eq(DartsRules.score_at(Vector2.ZERO)["label"], "Bull", "centre is the bull")
	_eq(DartsRules.score_at(Vector2.ZERO)["score"], 50, "bull scores 50")
	_eq(DartsRules.score_at(Vector2(0, -10))["score"], 25, "outer bull scores 25")
	_eq(DartsRules.score_at(Vector2(0, -103))["label"], "T20", "straight up in the treble ring is T20")
	_eq(DartsRules.score_at(Vector2(0, -166))["label"], "D20", "straight up in the double ring is D20")
	_eq(DartsRules.score_at(Vector2(0, -60))["label"], "20", "straight up between is single 20")
	_eq(DartsRules.score_at(Vector2(0, -180))["score"], 0, "outside the doubles misses")
	_eq(DartsRules.score_at(Vector2(103, 0))["label"], "T6", "3 o'clock is 6")
	_eq(DartsRules.score_at(Vector2(0, 103))["label"], "T3", "6 o'clock is 3")
	_eq(DartsRules.score_at(Vector2(-103, 0))["label"], "T11", "9 o'clock is 11")
	for n in DartsRules.ORDER:
		for m in [1, 2, 3]:
			var hit := DartsRules.score_at(DartsRules.target_point(n, m))
			_eq(hit["score"], n * m, "target point of %s scores it" % DartsRules.label(n, m))


func _test_checkouts() -> void:
	_eq(DartsRules.checkout(170, 3), ["T20", "T20", "Bull"], "170 is T20 T20 Bull")
	_eq(DartsRules.checkout(40, 1), ["D20"], "40 is D20")
	_eq(DartsRules.checkout(50, 1), ["Bull"], "50 is the bull")
	_eq(DartsRules.checkout(100, 2), ["T20", "D20"], "100 is T20 D20")
	_eq(DartsRules.checkout(169, 3), [], "169 has no checkout")
	_eq(DartsRules.checkout(41, 1), [], "41 can't go out in one dart")
	_check(DartsRules.checkout(41, 2).size() == 2, "41 goes out in two")
	_eq(DartsRules.checkout(1, 3), [], "1 is no checkout with double out")
	_eq(DartsRules.checkout(3, 1, false), ["3"], "straight out 3 is a single 3")
	for r in range(2, 171):
		var route := DartsRules.checkout(r, 3)
		if route.is_empty():
			_check(r in [159, 162, 163, 165, 166, 168, 169], "%d should have a checkout" % r)
			continue
		var total := 0
		for lbl in route:
			total += _label_score(lbl)
		var last: String = route[route.size() - 1]
		_check(total == r and (last.begins_with("D") or last == "Bull"), "%d checkout %s adds up" % [r, route])


func _label_score(lbl: String) -> int:
	if lbl == "Bull":
		return 50
	if lbl.begins_with("T"):
		return 3 * int(lbl.substr(1))
	if lbl.begins_with("D"):
		return 2 * int(lbl.substr(1))
	return int(lbl)


func _t(n: int, m: int) -> Vector2:
	return DartsRules.target_point(n, m)


func _test_501() -> void:
	var g := DartsMatch.new()
	_check(not g.start(), "can't start with nobody")
	_check(g.add_player(10, "Alf"), "Alf chalks up")
	_check(g.add_player(20, "Bert"), "Bert chalks up")
	_check(not g.add_player(10, "Alf"), "can't chalk up twice")
	_check(g.start(), "starts")
	_check(not g.add_player(30, "Cyril"), "no joining mid-game")
	_eq(g.thrower_peer(), 10, "Alf throws first")
	for i in 3:
		g.throw_dart(_t(20, 3))
	_check(g.turn_over, "turn over after three darts")
	_eq(g.players[0]["remaining"], 321, "180 off 501 leaves 321")
	_check(g.throw_dart(_t(20, 3)).is_empty(), "no fourth dart")
	g.end_turn()
	_eq(g.thrower_peer(), 20, "Bert's turn")
	_eq(g.turn.size(), 0, "fresh turn")
	g.throw_dart(_t(1, 1))
	g.throw_dart(Vector2(0, -200))
	g.throw_dart(_t(5, 1))
	_eq(g.players[1]["remaining"], 495, "Bert scores 6 (one miss)")
	_eq(g.players[1]["last"], 6, "last turn recorded")
	_check(absf(g.average(0) - 180.0) < 0.01, "Alf's average is 180")


func _test_bust_rules() -> void:
	var g := DartsMatch.new()
	g.add_player(1, "Solo")
	g.set_options(301, 1, true)
	g.start()
	_eq(g.players[0]["remaining"], 301, "301 game")
	g.players[0]["remaining"] = 40
	g._begin_turn()
	g.throw_dart(_t(10, 1))  # 30
	g.throw_dart(_t(20, 3))  # bust
	_check(g.turn_over and g.note == "BUST", "going below zero busts")
	_eq(g.players[0]["remaining"], 40, "bust puts the score back")
	g.end_turn()
	g.throw_dart(_t(19, 2))  # 38 -> 2
	g.throw_dart(_t(1, 1))   # 1 left -> bust
	_check(g.note == "BUST", "leaving 1 busts with double out")
	g.end_turn()
	g.throw_dart(_t(20, 1))  # 20 -> 20 left
	g.throw_dart(_t(20, 1))  # 0 on a single -> bust
	_check(g.note == "BUST", "finishing on a single busts with double out")
	g.end_turn()
	var res := g.throw_dart(_t(20, 2))
	_check(res["checkout"] and res["match_won"], "D20 wins it")
	g.end_turn()
	_eq(g.phase, DartsMatch.Phase.FINISHED, "match finished")
	_eq(g.winner, 0, "winner recorded")
	g.back_to_lobby()
	_eq(g.phase, DartsMatch.Phase.LOBBY, "back to the lobby")
	_eq(g.players[0]["remaining"], 301, "scores reset")

	var s := DartsMatch.new()
	s.add_player(1, "Solo")
	s.set_options(301, 1, false)
	s.start()
	s.players[0]["remaining"] = 20
	s._begin_turn()
	_check(s.throw_dart(_t(20, 1))["checkout"], "straight out finishes on a single")


func _test_legs_and_players() -> void:
	var g := DartsMatch.new()
	g.add_player(1, "A")
	g.add_player(2, "B")
	g.add_player(3, "C")
	g.set_options(501, 2, true)
	g.start()
	g.players[0]["remaining"] = 50
	g._begin_turn()
	var res := g.throw_dart(_t(25, 2))
	_check(res["leg_won"] and not res["match_won"], "A wins leg one")
	g.end_turn()
	_eq(g.leg, 2, "leg two")
	_eq(g.thrower_peer(), 2, "B throws first in leg two")
	_eq(g.players[0]["remaining"], 501, "scores reset for the leg")
	_eq(g.players[0]["legs"], 1, "A has a leg")
	# B leaves mid-turn: C takes over.
	g.throw_dart(_t(20, 1))
	g.remove_player(2)
	_eq(g.thrower_peer(), 3, "C throws when B leaves on their turn")
	_eq(g.turn.size(), 0, "C starts a fresh turn")
	g.remove_player(1)
	g.remove_player(3)
	_eq(g.phase, DartsMatch.Phase.LOBBY, "empty board goes back to the lobby")
	var full := DartsMatch.new()
	for i in 4:
		full.add_player(i + 1, "P%d" % i)
	_check(not full.add_player(9, "Fifth"), "four players max")


func _test_sync() -> void:
	var g := DartsMatch.new()
	g.add_player(1, "A")
	g.add_player(2, "B")
	g.start()
	g.throw_dart(_t(19, 3))
	var copy := DartsMatch.new()
	copy.from_dict(g.to_dict())
	_eq(copy.to_dict(), g.to_dict(), "to_dict/from_dict round trip")
	copy.throw_dart(_t(19, 3))
	_eq(copy.players[0]["remaining"], 501 - 114, "a synced copy keeps scoring")


func _test_in_pub() -> void:
	DartsBoard.require_pad = false  # headless has no controllers
	get_tree().root.get_node("Net").start_solo("Tester", 0)
	get_tree().root.get_node("GameData").start_crawl(0)
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	get_tree().change_scene_to_file("res://scenes/pubs/crown_and_punchbowl.tscn")
	for _f in 120:
		await get_tree().process_frame
		if get_tree().current_scene and get_tree().current_scene.is_node_ready() and not get_tree().get_nodes_in_group("players").is_empty():
			break
	var boards := get_tree().get_nodes_in_group(DartsBoard.GAMES_GROUP)
	_check(boards.size() == 1, "the pub has a playable board (%d)" % boards.size())
	if boards.is_empty():
		return
	var board: DartsBoard = boards[0]
	var player: Fighter = get_tree().get_nodes_in_group("players")[0]
	_check(DartsBoard.near_oche(player) == null, "not at the oche at the start")
	player.global_position = board.oche_point() + board.facing * 0.3
	await get_tree().physics_frame
	_check(DartsBoard.near_oche(player) == board, "found the oche")
	_check(DartsBoard.handle_local_interact(player), "interact at the oche chalks up")
	_check(board.game.has_player(1), "chalked up")
	_check(DartsBoard.local_input_locked(), "fight controls off while playing")
	board.request_options(301, 1, true)
	board.request_start()
	_eq(board.game.phase, DartsMatch.Phase.PLAYING, "solo practice game started")
	_check(board.is_local_turn(), "our throw")
	var to_board := player.global_position.distance_to(board.oche_point())
	_check(to_board < 0.5, "stepped up to the oche (%.2f m)" % to_board)
	board.request_throw(_t(20, 3))
	_eq(board.game.turn.size(), 1, "dart thrown")
	_eq(board.get_node("Darts").get_child_count(), 1 if Vector2(board.game.turn[0]["x"], board.game.turn[0]["y"]).length() <= DartsRules.R_BOARD else 0, "dart stuck in the 3D board")
	var left: int = board.game.players[0]["remaining"]
	_check(left < 301 or board.game.turn[0]["score"] == 0, "score went down")
	var landed := Vector2(board.game.turn[0]["x"], board.game.turn[0]["y"])
	_check(landed.distance_to(_t(20, 3)) < 60.0, "sober throw lands near the aim (%.0f mm)" % landed.distance_to(_t(20, 3)))
	board.request_throw(_t(20, 3))
	board.request_throw(_t(20, 3))
	_check(board.game.turn_over, "turn over after three")
	await get_tree().create_timer(DartsBoard.TURN_PAUSE + 0.2).timeout
	_check(not board.game.turn_over and board.game.turn.is_empty(), "next turn after the pause")
	_eq(board.get_node("Darts").get_child_count(), 0, "darts pulled out for the next turn")
	get_tree().root.get_node("Events").fight_started.emit()
	_check(not DartsBoard.local_input_locked(), "a fight puts the darts down")
	_check(board.game.has_player(1) and board.game.players[0]["away"], "place kept while away")
	_check(DartsBoard.handle_local_interact(player), "interact again at the oche")
	_check(DartsBoard.local_input_locked(), "back at the darts")
	_check(DartsBoard.handle_local_interact(player), "interact steps away")
	_check(not DartsBoard.local_input_locked(), "stepped away")
	board.request_leave()
	_check(not board.game.has_player(1), "left the game")


func _eq(a: Variant, b: Variant, what: String) -> void:
	_check(a == b, "%s (got %s, want %s)" % [what, a, b])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)
