class_name DartsBoard
extends Node3D
## A playable dartboard: 501 or 301 with your mates, online or solo.
##
## `DartsBoard.install(pub)` adds one, named "DartsGame", under every board PubBuilder
## built (board roots are in the "dartboards" group with a "facing" meta). The path is the
## same on every peer, so the RPCs below just work.
##
## How it plays:
## - Walk up to the oche and press interact to chalk up. A darts panel opens with the
##   board, the scores and the game options. Anyone else at the oche can chalk up too, up
##   to four. The first to chalk up (the captain) picks 501 or 301, the legs and double or
##   straight out, then starts.
## - On your turn you step up to the oche. Aim with the move stick, the keys or the mouse;
##   your hand wobbles (more after a few pints). Throw with the throw button, left click,
##   Space or Enter, or X on a pad. Three darts a turn.
## - Interact again steps away from the board (your place is kept). If a fight kicks off
##   everyone at the board steps away. Come back to the oche and press interact to carry on.
##
## Host-authoritative: clients send requests, the host runs a DartsMatch, adds the throw
## scatter, scores the dart and sends the whole match to everyone.

signal state_changed()

const GROUP := &"dartboards"            ## board roots built by PubBuilder.dartboard()
const GAMES_GROUP := &"darts_games"     ## DartsBoard nodes
const NODE_NAME := "DartsGame"
const BOARD_HEIGHT := 1.73              ## bull above the floor
const OCHE_DISTANCE := 2.37             ## regulation, from the board face
const OCHE_RADIUS := 1.6                ## how close to the oche you must be to chalk up
const TURN_PAUSE := 1.8                 ## seconds the finished turn stays up
const MATCH_PAUSE := 7.0                ## seconds the winner is shown before the lobby
## Throw scatter (mm, standard deviation) sober and on top when fully tipsy.
const SCATTER := 9.0
const TIPSY_SCATTER := 26.0
const MAX_AIM := 260.0
const PANEL_SCRIPT := preload("res://scripts/darts/darts_panel.gd")

## The board the local player is playing at (chalked up and not stepped away), or null.
## While set, the local player's fight and item controls are off.
static var local_board: DartsBoard = null
## Darts is played on a controller only. Tests turn this off (headless has no pads).
static var require_pad := true

var game := DartsMatch.new()
## Out from the wall, into the room.
var facing := Vector3.BACK
## The bull, in world space.
var bull := Vector3.ZERO

var _panel: Node = null
var _prompt: Label3D
var _darts_root: Node3D
var _rng := RandomNumberGenerator.new()
var _at_oche := false
var _shown_darts := 0
var _pause_id := 0


## Adds a DartsBoard to every dartboard in `level`. Returns them.
static func install(level: Node) -> Array:
	var out := []
	var roots := level.get_tree().get_nodes_in_group(GROUP)
	for root in roots:
		if not level.is_ancestor_of(root) or root.has_node(NODE_NAME):
			continue
		var b := DartsBoard.new()
		b.name = NODE_NAME
		b.facing = (root.get_meta("facing", Vector3.BACK) as Vector3).normalized()
		root.add_child(b)
		out.append(b)
	return out


## True while the local player is playing darts (their other controls are off).
static func local_input_locked() -> bool:
	return local_board != null and is_instance_valid(local_board) and local_board.is_inside_tree()


## The local player pressed interact. Returns true if darts used it: steps away from the
## board you're playing at, or chalks up at the oche you're stood at.
static func handle_local_interact(f: Fighter) -> bool:
	if local_input_locked():
		local_board.request_away()
		return true
	var b := near_oche(f)
	if b != null:
		if not pad_connected():
			Events.banner.emit("Darts is played on a controller. Plug one in.", 2.5)
		else:
			b.request_join()
		return true
	return false


static func pad_connected() -> bool:
	return not require_pad or not Input.get_connected_joypads().is_empty()


## The board whose oche `f` is stood at, or null.
static func near_oche(f: Fighter) -> DartsBoard:
	if f == null or not f.is_inside_tree() or not f.can_act():
		return null
	for node in f.get_tree().get_nodes_in_group(GAMES_GROUP):
		var b := node as DartsBoard
		if b == null:
			continue
		var to := b.oche_point() - f.global_position
		if absf(to.y) < 1.0 and Vector2(to.x, to.z).length() <= OCHE_RADIUS:
			return b
	return null


func _ready() -> void:
	add_to_group(GAMES_GROUP)
	bull = (get_parent() as Node3D).global_position if get_parent() is Node3D else global_position
	_rng.randomize()
	_darts_root = Node3D.new()
	_darts_root.name = "Darts"
	add_child(_darts_root)
	_darts_root.top_level = true
	_darts_root.global_transform = Transform3D.IDENTITY
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.fixed_size = true
	_prompt.pixel_size = 0.0008
	_prompt.font_size = 30
	_prompt.outline_size = 12
	_prompt.outline_modulate = Color(0, 0, 0, 0.85)
	_prompt.modulate = Color(1.0, 0.93, 0.8)
	_prompt.render_priority = 10
	_prompt.outline_render_priority = 9
	_prompt.visible = false
	_prompt.top_level = true
	add_child(_prompt)
	Events.fight_started.connect(_on_fight_started)
	Events.hit_landed.connect(_on_hit_landed)
	Net.player_dropped.connect(_on_player_dropped)


func _exit_tree() -> void:
	if local_board == self:
		local_board = null


## Where the oche line is, on the floor.
func oche_point() -> Vector3:
	var p := bull + facing * OCHE_DISTANCE
	p.y = bull.y - BOARD_HEIGHT
	return p


## Board mm (x right, y down, as you look at it) to world space on the board face.
func board_to_world(p: Vector2, out_from_face := 0.03) -> Vector3:
	var right := Vector3.UP.cross(facing).normalized()
	return bull + right * p.x * 0.001 - Vector3.UP * p.y * 0.001 + facing * out_from_face


func is_local_turn() -> bool:
	return game.phase == DartsMatch.Phase.PLAYING and not game.turn_over \
		and game.thrower_peer() == multiplayer.get_unique_id() and not _thrower_away()


func _thrower_away() -> bool:
	return bool(game.thrower().get("away", false))


# --- Requests (any peer) ---------------------------------------------------------------

func request_join() -> void:
	_send(&"join", [])


func request_away() -> void:
	_send(&"away", [])


func request_leave() -> void:
	_send(&"leave", [])


func request_start() -> void:
	_send(&"start", [])


func request_options(start_score: int, legs: int, double_out: bool) -> void:
	_send(&"options", [start_score, legs, double_out])


## Throw at `aim` (board mm, including the wobble the player saw).
func request_throw(aim: Vector2) -> void:
	_send(&"throw", [aim])


func _send(action: StringName, args: Array) -> void:
	if not is_inside_tree():
		return
	if multiplayer.is_server():
		_server(multiplayer.get_unique_id(), action, args)
	else:
		_rpc_request.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(action: StringName, args: Array) -> void:
	if not multiplayer.is_server():
		return
	_server(multiplayer.get_remote_sender_id(), action, args)


# --- Host ------------------------------------------------------------------------------

func _server(peer: int, action: StringName, args: Array) -> void:
	match action:
		&"join":
			if game.has_player(peer):
				game.set_away(peer, false)
			elif not game.add_player(peer, _name_of(peer)):
				var why := "The board's full." if game.players.size() >= DartsMatch.MAX_PLAYERS \
					else "There's a game on. Chalk up for the next one."
				_tell(peer, why)
				return
		&"away":
			game.set_away(peer, true)
		&"leave":
			game.remove_player(peer)
		&"start":
			if peer != game.captain_peer() or not game.start():
				return
		&"options":
			if peer != game.captain_peer() or args.size() < 3:
				return
			game.set_options(int(args[0]), int(args[1]), bool(args[2]))
		&"throw":
			if args.is_empty() or not (args[0] is Vector2) or peer != game.thrower_peer() or _thrower_away():
				return
			if not _server_throw(peer, args[0]):
				return
		_:
			return
	_broadcast()


func _server_throw(peer: int, aim: Vector2) -> bool:
	if aim.length() > MAX_AIM:
		aim = aim.normalized() * MAX_AIM
	var sigma := SCATTER + TIPSY_SCATTER * _tipsy_of(peer)
	var landed := aim + Vector2(_rng.randfn(0.0, sigma), _rng.randfn(0.0, sigma))
	var res := game.throw_dart(landed)
	if res.is_empty():
		return false
	if game.turn_over:
		_pause_id += 1
		get_tree().create_timer(TURN_PAUSE).timeout.connect(_host_end_turn.bind(_pause_id))
	return true


func _host_end_turn(id: int) -> void:
	if id != _pause_id or not game.turn_over:
		return
	game.end_turn()
	if game.phase == DartsMatch.Phase.FINISHED:
		_pause_id += 1
		get_tree().create_timer(MATCH_PAUSE).timeout.connect(_host_back_to_lobby.bind(_pause_id))
	_broadcast()


func _host_back_to_lobby(id: int) -> void:
	if id != _pause_id or game.phase != DartsMatch.Phase.FINISHED:
		return
	game.back_to_lobby()
	_broadcast()


func _broadcast() -> void:
	var d := game.to_dict()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_rpc_state.rpc(d)
	_on_state()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(d: Dictionary) -> void:
	game.from_dict(d)
	_on_state()


func _tell(peer: int, text: String) -> void:
	if peer == multiplayer.get_unique_id():
		_rpc_tell(text)
	else:
		_rpc_tell.rpc_id(peer, text)


@rpc("authority", "call_remote", "reliable")
func _rpc_tell(text: String) -> void:
	Events.banner.emit(text, 2.5)


func _name_of(peer: int) -> String:
	return String(Net.players.get(peer, {}).get("name", "Player %d" % peer))


func _fighter_of(peer: int) -> Fighter:
	for node in get_tree().get_nodes_in_group("players"):
		var f := node as Fighter
		if f != null and f.get_multiplayer_authority() == peer:
			return f
	return null


func _tipsy_of(peer: int) -> float:
	var f := _fighter_of(peer)
	return clampf(f.tipsy, 0.0, 1.0) if f != null else 0.0


## It's kicked off: everyone at the board puts their darts down (their places are kept).
func _on_fight_started() -> void:
	if not multiplayer.is_server() or game.players.is_empty():
		return
	for p in game.players:
		game.set_away(int(p["peer"]), true)
	_broadcast()


## Someone at the board got hit: they step away to deal with it.
func _on_hit_landed(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var v := info.get("victim") as Fighter
	if v == null or not v.is_in_group("players"):
		return
	var peer := v.get_multiplayer_authority()
	var i := game.index_of(peer)
	if i >= 0 and not bool(game.players[i]["away"]):
		game.set_away(peer, true)
		_broadcast()


func _on_player_dropped(peer: int, _player_name: String) -> void:
	if multiplayer.is_server() and game.has_player(peer):
		game.remove_player(peer)
		_broadcast()


# --- Every peer ------------------------------------------------------------------------

func _on_state() -> void:
	var me := multiplayer.get_unique_id()
	var i := game.index_of(me)
	var active := i >= 0 and not bool(game.players[i]["away"])
	if active and local_board != self:
		if local_input_locked():
			local_board.request_away()  # playing at another board: leave that one
		local_board = self
		_open_panel()
		_place_local(false)
	elif not active and local_board == self:
		local_board = null
		_close_panel()
	var at_oche := active and game.phase == DartsMatch.Phase.PLAYING and game.thrower_peer() == me
	if at_oche != _at_oche:
		_at_oche = at_oche
		_place_local(at_oche)
	_sync_darts()
	if _panel != null:
		_panel.refresh()
	state_changed.emit()


func _open_panel() -> void:
	if _panel != null or DisplayServer.get_name() == "headless":
		return
	_panel = PANEL_SCRIPT.new()
	_panel.board = self
	get_tree().current_scene.add_child(_panel)


func _close_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


## Moves the local player onto the oche (their throw) or beside it.
func _place_local(on_oche: bool) -> void:
	var f := _fighter_of(multiplayer.get_unique_id())
	if f == null or not f.can_act():
		return
	var right := Vector3.UP.cross(facing).normalized()
	var spot := oche_point() + facing * 0.15
	if not on_oche:
		var i := maxi(game.index_of(multiplayer.get_unique_id()), 0)
		spot = oche_point() + facing * 0.5 + right * (0.9 + 0.6 * (i % 2)) * (1.0 if i < 2 else -1.0)
	spot.y = f.global_position.y
	f.global_position = spot
	f.velocity = Vector3.ZERO
	var dir := (bull - spot)
	dir.y = 0.0
	if dir.length() > 0.01:
		f.rotation.y = atan2(-dir.x, -dir.z)


## Darts stuck in the board: the turn in progress.
func _sync_darts() -> void:
	var n := game.turn.size()
	if n < _shown_darts or n == 0:
		for c in _darts_root.get_children():
			c.queue_free()
		_shown_darts = 0
	while _shown_darts < n:
		var d: Dictionary = game.turn[_shown_darts]
		var p := Vector2(float(d["x"]), float(d["y"]))
		_shown_darts += 1
		if p.length() > DartsRules.R_BOARD:
			_play("wood_hit", bull, -14.0)  # in the cabinet or the wall
			continue
		_make_dart(board_to_world(p, 0.035))
		_play("wood_hit", bull, -18.0)
	if game.note == "MATCH" or game.note == "GAME SHOT" or (game.turn.size() == 3 and _turn_total() == 180):
		if game.turn_over and n > 0 and _darts_root.get_meta("cheered", -1) != game.serial:
			_darts_root.set_meta("cheered", game.serial)
			_play("crowd_roar", bull, 4.0)


func _names() -> String:
	var names := []
	for p in game.players:
		names.append(String(p["name"]))
	return ", ".join(names)


func _turn_total() -> int:
	var t := 0
	for d in game.turn:
		t += int(d["score"])
	return t


func _make_dart(at: Vector3) -> Node3D:
	var dart := Node3D.new()
	_darts_root.add_child(dart)
	dart.global_position = at
	# Stuck in at a slight upward angle, pointing back towards the oche.
	var out := (facing + Vector3.UP * 0.12).normalized()
	dart.look_at(at + out, Vector3.UP if absf(out.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("c9a03a")
	brass.metallic = 0.8
	brass.roughness = 0.35
	var flight_mat := StandardMaterial3D.new()
	flight_mat.albedo_color = Color("b3261e")
	flight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0045
	cyl.bottom_radius = 0.0045
	cyl.height = 0.11
	barrel.mesh = cyl
	barrel.material_override = brass
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0, -0.055)
	dart.add_child(barrel)
	for k in 2:
		var flight := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.03, 0.035)
		flight.mesh = quad
		flight.material_override = flight_mat
		flight.position = Vector3(0, 0, -0.105)
		flight.rotation = Vector3(0, PI * 0.5, PI * 0.5 * k)
		dart.add_child(flight)
	return dart


func _play(cue: String, pos: Vector3, db: float) -> void:
	var fx := get_node_or_null("/root/Fx")
	if fx != null and fx.has_method("play") and SoundBank.has_cue(cue):
		fx.play(cue, pos, db)


func _process(_delta: float) -> void:
	var f := _fighter_of(multiplayer.get_unique_id()) if multiplayer.has_multiplayer_peer() else null
	var show := f != null and not local_input_locked() and near_oche(f) == self
	_prompt.visible = show
	if show:
		var key := "[%s]" % (Settings.action_label("interact", "pad") if Settings.has_method("action_label") else "RT")
		var i := game.index_of(multiplayer.get_unique_id())
		var text := "%s  Play darts" % key
		if i >= 0:
			text = "%s  Back to the darts" % key
		elif game.phase != DartsMatch.Phase.LOBBY:
			text = "Darts: %s on  (%s)" % [game.describe().split("  ·")[0], _names()]
		elif not game.players.is_empty():
			text = "%s  Chalk up for darts  (%s)" % [key, _names()]
		if i < 0 and not pad_connected():
			text = "Darts needs a controller"
		_prompt.text = text
		_prompt.global_position = oche_point() + Vector3.UP * 2.1
