class_name DartsMatch
extends RefCounted
## One game of 501 or 301 at a dartboard: who's chalked up, scores, legs and whose throw
## it is. Pure rules, no networking: DartsBoard runs one on the host and sends
## `to_dict()` to every peer.
##
## Rules (pub darts, the usual ones):
## - Everyone starts on `start_score` and takes turns of three darts.
## - With double_out the last dart must be a double (or the bull). Going below zero,
##   leaving 1, or reaching 0 without a double is a bust: the turn ends and the score goes
##   back to what it was before the turn.
## - The first to zero wins the leg. First to `legs_to_win` legs wins the match. The
##   player who throws first moves round each leg.

enum Phase { LOBBY, PLAYING, FINISHED }

const MAX_PLAYERS := 4
const DARTS_PER_TURN := 3
const START_SCORES := [501, 301]

var phase := Phase.LOBBY
var start_score := 501
var legs_to_win := 1
var double_out := true
## [{peer, name, remaining, legs, away, last, darts, scored}]
## last: what their previous turn scored (-1 = bust, -2 = not thrown yet).
var players: Array = []
## Index into players of whoever is throwing.
var current := 0
var leg_starter := 0
var leg := 1
## Darts of the turn in progress: [{x, y, label, score}]
var turn: Array = []
## The turn is finished (three darts, bust or checkout) and waits for end_turn().
var turn_over := false
## "", "BUST", "GAME SHOT" or "MATCH"
var note := ""
## Index of the match winner once phase is FINISHED.
var winner := -1
## Counts every change, so peers can tell a new state from a repeat.
var serial := 0

var _remaining_at_turn_start := 0
var _leg_won := false


func index_of(peer: int) -> int:
	for i in players.size():
		if int(players[i]["peer"]) == peer:
			return i
	return -1


func has_player(peer: int) -> bool:
	return index_of(peer) >= 0


func thrower() -> Dictionary:
	return players[current] if current >= 0 and current < players.size() else {}


func thrower_peer() -> int:
	return int(thrower().get("peer", 0))


## Captain = first to chalk up. They pick the game and start it.
func captain_peer() -> int:
	return int(players[0]["peer"]) if not players.is_empty() else 0


## Sign up in the lobby. False when full, already in, or a game is on.
func add_player(peer: int, player_name: String) -> bool:
	if phase != Phase.LOBBY or players.size() >= MAX_PLAYERS or has_player(peer):
		return false
	players.append({"peer": peer, "name": player_name, "remaining": start_score, "legs": 0,
		"away": false, "last": -2, "darts": 0, "scored": 0})
	serial += 1
	return true


func remove_player(peer: int) -> void:
	var i := index_of(peer)
	if i < 0:
		return
	players.remove_at(i)
	serial += 1
	if players.is_empty():
		_to_lobby()
		return
	if phase != Phase.PLAYING:
		current = clampi(current, 0, players.size() - 1)
		return
	if leg_starter > i:
		leg_starter -= 1
	leg_starter = leg_starter % players.size()
	if i < current:
		current -= 1
	elif i == current:
		# Their turn goes to the next player, from scratch.
		current = current % players.size()
		_begin_turn()


func set_away(peer: int, away: bool) -> void:
	var i := index_of(peer)
	if i >= 0 and bool(players[i]["away"]) != away:
		players[i]["away"] = away
		serial += 1


## Lobby only. Unknown values are ignored.
func set_options(new_start: int, new_legs: int, new_double_out: bool) -> void:
	if phase != Phase.LOBBY:
		return
	if START_SCORES.has(new_start):
		start_score = new_start
	legs_to_win = clampi(new_legs, 1, 5)
	double_out = new_double_out
	for p in players:
		p["remaining"] = start_score
	serial += 1


func can_start() -> bool:
	return phase == Phase.LOBBY and not players.is_empty()


func start() -> bool:
	if not can_start():
		return false
	phase = Phase.PLAYING
	leg = 1
	leg_starter = 0
	winner = -1
	for p in players:
		p["legs"] = 0
		p["darts"] = 0
		p["scored"] = 0
	_new_leg()
	return true


## The thrower's dart lands at `pos` (board mm). Returns the scored dart plus
## {bust, checkout, leg_won, match_won}, or {} if no dart can be thrown now.
func throw_dart(pos: Vector2) -> Dictionary:
	if phase != Phase.PLAYING or turn_over or players.is_empty():
		return {}
	var hit := DartsRules.score_at(pos)
	var p: Dictionary = players[current]
	var score: int = hit["score"]
	turn.append({"x": pos.x, "y": pos.y, "label": hit["label"], "score": score})
	p["darts"] = int(p["darts"]) + 1
	var left: int = int(p["remaining"]) - score
	var bust: bool = left < 0 or (double_out and (left == 1 or (left == 0 and not hit["double"])))
	var res := hit.duplicate()
	res["bust"] = bust
	res["checkout"] = false
	res["leg_won"] = false
	res["match_won"] = false
	serial += 1
	if bust:
		# A bust turn scores nothing, so take back this turn's earlier darts.
		p["scored"] = int(p["scored"]) - (_turn_total() - score)
		p["remaining"] = _remaining_at_turn_start
		p["last"] = -1
		turn_over = true
		note = "BUST"
		return res
	p["remaining"] = left
	p["scored"] = int(p["scored"]) + score
	if left == 0:
		p["legs"] = int(p["legs"]) + 1
		p["last"] = _turn_total()
		res["checkout"] = true
		res["leg_won"] = true
		turn_over = true
		_leg_won = true
		if int(p["legs"]) >= legs_to_win:
			res["match_won"] = true
			note = "MATCH"
		else:
			note = "GAME SHOT"
		return res
	if turn.size() >= DARTS_PER_TURN:
		p["last"] = _turn_total()
		turn_over = true
	return res


## After the pause that shows the turn: next player, next leg, or the match is over.
func end_turn() -> void:
	if phase != Phase.PLAYING or not turn_over:
		return
	serial += 1
	if _leg_won:
		_leg_won = false
		if note == "MATCH":
			phase = Phase.FINISHED
			winner = current
			turn_over = false
			return
		leg += 1
		leg_starter = (leg_starter + 1) % players.size()
		_new_leg()
		return
	current = (current + 1) % players.size()
	_begin_turn()


## After a finished match: back to the lobby with the same players.
func back_to_lobby() -> void:
	_to_lobby()
	serial += 1


func darts_left() -> int:
	return DARTS_PER_TURN - turn.size()


## Three-dart average for player i.
func average(i: int) -> float:
	var p: Dictionary = players[i]
	var d := int(p["darts"])
	return 0.0 if d == 0 else float(p["scored"]) / d * 3.0


## Checkout route for whoever is throwing, or [].
func suggested_checkout() -> Array:
	if phase != Phase.PLAYING or turn_over or players.is_empty():
		return []
	return DartsRules.checkout(int(thrower()["remaining"]), darts_left(), double_out)


func describe() -> String:
	var legs := "first to %d legs" % legs_to_win if legs_to_win > 1 else "one leg"
	return "%d  ·  %s  ·  %s" % [start_score, "double out" if double_out else "straight out", legs]


func _turn_total() -> int:
	var t := 0
	for d in turn:
		t += int(d["score"])
	return t


func _new_leg() -> void:
	for p in players:
		p["remaining"] = start_score
		p["last"] = -2
	current = leg_starter % players.size()
	_begin_turn()


func _begin_turn() -> void:
	turn = []
	turn_over = false
	note = ""
	_remaining_at_turn_start = int(players[current]["remaining"]) if not players.is_empty() else 0


func _to_lobby() -> void:
	phase = Phase.LOBBY
	current = 0
	leg = 1
	leg_starter = 0
	winner = -1
	turn = []
	turn_over = false
	note = ""
	_leg_won = false
	for p in players:
		p["remaining"] = start_score
		p["legs"] = 0
		p["last"] = -2
		p["darts"] = 0
		p["scored"] = 0


# --- Sync ----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"phase": phase, "start": start_score, "legs_to_win": legs_to_win,
		"double_out": double_out, "players": players.duplicate(true), "current": current,
		"leg_starter": leg_starter, "leg": leg, "turn": turn.duplicate(true),
		"turn_over": turn_over, "note": note, "winner": winner, "serial": serial,
		"rats": _remaining_at_turn_start, "leg_won": _leg_won}


func from_dict(d: Dictionary) -> void:
	phase = int(d.get("phase", Phase.LOBBY)) as Phase
	start_score = int(d.get("start", 501))
	legs_to_win = int(d.get("legs_to_win", 1))
	double_out = bool(d.get("double_out", true))
	players = (d.get("players", []) as Array).duplicate(true)
	current = int(d.get("current", 0))
	leg_starter = int(d.get("leg_starter", 0))
	leg = int(d.get("leg", 1))
	turn = (d.get("turn", []) as Array).duplicate(true)
	turn_over = bool(d.get("turn_over", false))
	note = String(d.get("note", ""))
	winner = int(d.get("winner", -1))
	serial = int(d.get("serial", 0))
	_remaining_at_turn_start = int(d.get("rats", 0))
	_leg_won = bool(d.get("leg_won", false))
