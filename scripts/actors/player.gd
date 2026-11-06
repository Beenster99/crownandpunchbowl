class_name PlayerFighter
extends Fighter
## Player-controlled fighter: boxing-style controls on top of Fighter.
##
## Left and right punches are separate buttons. Tap for a quick punch (left jab, right
## hook), hold for a heavy one (left cross, right uppercut). The uppercut also has its own
## button. Both punches together is a headbutt.
## Punches thrown in rhythm (in the previous punch's recovery, or just after it) build a
## string, and known strings are combos that hit harder (see Moves.COMBOS). Hammering the
## buttons before a punch has finished fumbles the string and leaves you off balance, so
## timing beats mashing.
##
## Hold Block to keep your guard up against punches. Raising it just as a punch arrives
## parries it, and your next punch is a counter. Kicks, headbutts and haymakers break a
## guard, so dodge those. The prompt over an attacker says which to press.
##
## Nobody is chased across the room: you walk into range, and a punch only steps in a
## short way. Near an active enemy you take a stance and square up to them.
## Kick stomps a downed enemy. Grab holds an enemy for your mates; punch while holding to
## knee, Throw to hurl them, Grab again to let go. Mash any button while held to struggle.

## Current combo (hits landed without a long gap or being hit). HUD reads Events.combo_changed.
var combo := 0
var farmer: Dictionary = {}

## Moves thrown in the current rhythm string, oldest first.
var _history: Array[StringName] = []
var _since_attack := 99.0
var _combo_t := 0.0
var _buffered: StringName = &""
var _buffer_t := 0.0
var _mash := 0
var _fumble_t := 0.0
## Per hand: seconds the button has been held, or -1 when not pending.
var _held := {&"left": -1.0, &"right": -1.0}
var _want_block := false
var _prompts: Node = null


func _ready() -> void:
	team = Team.PLAYERS
	_apply_farmer()
	super()
	hit_dealt.connect(_on_hit_dealt)
	hit_taken.connect(_on_hit_taken)
	if is_multiplayer_authority() and DisplayServer.get_name() != "headless":
		_prompts = load("res://scripts/combat/defend_prompts.gd").new()
		_prompts.player = self
		add_child(_prompts)


## Farmer stats from the lobby choice (Net.players[peer]["farmer"]).
func _apply_farmer() -> void:
	var peer := get_multiplayer_authority()
	if not Net.players.has(peer):
		return
	var idx := int(Net.players[peer].get("farmer", 0))
	if idx < 0 or idx >= GameData.FARMERS.size():
		return
	farmer = GameData.FARMERS[idx]
	max_hp = float(farmer["max_hp"])
	power = float(farmer["power"])
	move_speed = float(farmer["speed"])
	grip = float(farmer["grip"])


func _physics_process(delta: float) -> void:
	_tick_combo(delta)
	if is_multiplayer_authority():
		_read_input(delta)
	super(delta)


func _read_input(delta: float) -> void:
	if DartsBoard.local_input_locked():
		# Playing darts: the darts panel has the controls.
		move_input = Vector3.ZERO
		_set_block(false)
		return
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_input = Vector3(stick.x, 0.0, stick.y)

	if state == State.HELD:
		for a in ["punch_left", "punch_right", "uppercut", "kick", "headbutt", "grab", "dodge"]:
			if Input.is_action_just_pressed(a):
				request_struggle()
		return

	_set_block(Input.is_action_pressed("block"))
	if Input.is_action_just_pressed("dodge"):
		request_dodge(move_input)
		_buffered = &""
		return
	if Input.is_action_just_pressed("grab"):
		if state == State.GRABBING:
			request_release()
		else:
			request_grab(Targeting.grab_candidate(self))
		return
	if Input.is_action_just_pressed("throw") and state == State.GRABBING:
		request_throw()
		return

	if Input.is_action_just_pressed("kick"):
		press(&"kick")
	if Input.is_action_just_pressed("headbutt"):
		press(&"headbutt")
	if Input.is_action_just_pressed("uppercut"):
		press(&"uppercut")
	for hand in [&"left", &"right"]:
		var action := "punch_" + String(hand)
		if Input.is_action_just_pressed(action):
			hand_down(hand)
		elif Input.is_action_just_released(action):
			hand_up(hand)
	tick_hands(delta)
	_tick_buffer(delta)


# --- Input steps (public so tests and bots can drive them without real input) ----------

func hand_down(hand: StringName) -> void:
	var other := &"right" if hand == &"left" else &"left"
	var other_t: float = _held[other]
	if other_t >= 0.0 and other_t <= Moves.BOTH_HANDS_WINDOW:
		# Both punch buttons together: a headbutt.
		_held[other] = -1.0
		_held[hand] = -1.0
		press(&"headbutt")
		return
	_held[hand] = 0.0


func hand_up(hand: StringName) -> void:
	var t: float = _held[hand]
	if t < 0.0:
		return
	_held[hand] = -1.0
	press(Moves.LEFT_TAP if hand == &"left" else Moves.RIGHT_TAP)


func tick_hands(delta: float) -> void:
	for hand in [&"left", &"right"]:
		var t: float = _held[hand]
		if t < 0.0:
			continue
		t += delta
		_held[hand] = t
		if t >= Moves.PUNCH_HOLD_TIME:
			_held[hand] = -1.0
			press(Moves.LEFT_HOLD if hand == &"left" else Moves.RIGHT_HOLD)


## A button asking for `move`. It goes now if we're free or in the chain window, is
## buffered if the window is about to open, and otherwise counts as mashing.
func press(move: StringName) -> void:
	if _fumble_t > 0.0:
		return
	if state == State.GRABBING or can_attack():
		_perform(move)
		return
	if state == State.WINDUP or state == State.ATTACK:
		if _buffered == &"" and _time_to_chain() <= Moves.INPUT_BUFFER:
			_buffered = move
			_buffer_t = Moves.INPUT_BUFFER + 0.05
			return
		# Too early, or a second press on top of a buffered one: that's mashing.
		_mash += 1
		if _mash >= Moves.MASH_LIMIT:
			_fumble()


func _set_block(on: bool) -> void:
	if on == _want_block:
		# Re-raise the guard once an attack or stagger ends while the button is still held.
		if on and state == State.IDLE:
			request_block(true)
		return
	_want_block = on
	request_block(on)


func _time_to_chain() -> float:
	if state == State.WINDUP:
		return windup_remaining() + float(_move.get("active", 0.0))
	if state == State.ATTACK:
		return maxf(float(_move.get("active", 0.0)) - _attack_t, 0.0)
	return 0.0


func _tick_buffer(delta: float) -> void:
	_fumble_t = maxf(_fumble_t - delta, 0.0)
	if _buffered == &"":
		return
	_buffer_t -= delta
	if state == State.GRABBING or can_attack():
		var m := _buffered
		_buffered = &""
		_perform(m)
	elif _buffer_t <= 0.0:
		_buffered = &""


func _fumble() -> void:
	_mash = 0
	_history.clear()
	_buffered = &""
	_fumble_t = Moves.FUMBLE_TIME
	_set_combo(0)


## Turn a move into a target and a combo, then ask the host.
func _perform(move: StringName) -> void:
	if state == State.GRABBING:
		request_attack(&"knee")
		return
	var aim := move_input
	var tgt := Targeting.pick(self, aim)
	if move == &"kick" and tgt == null:
		var floored := Targeting.pick(self, aim, Moves.LUNGE_RANGE * 0.6, true)
		if floored != null:
			move = &"stomp"
			tgt = floored
	var in_rhythm := can_chain() or _since_attack <= Moves.RHYTHM_GRACE
	if not in_rhythm:
		_history.clear()
	_history.append(move)
	if _history.size() > 6:
		_history.remove_at(0)
	var combo_row := Moves.match_combo(_history)
	var bonus := float(combo_row.get("bonus", 1.0))
	var cname := String(combo_row.get("name", ""))
	if not combo_row.is_empty() and combo_row["seq"].size() >= 3 \
			and not Moves.combo_continues(combo_row["seq"]):
		_history.clear()  # a finished string starts afresh
	_mash = 0
	_since_attack = 0.0
	request_attack(move, tgt, bonus, cname)


func _tick_combo(delta: float) -> void:
	if state == State.ATTACK or state == State.WINDUP:
		_since_attack = 0.0
	else:
		_since_attack += delta
	if combo > 0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_set_combo(0)


func _on_hit_dealt(info: Dictionary) -> void:
	if bool(info.get("blocked", false)) or bool(info.get("parried", false)):
		return
	_combo_t = Moves.COMBO_TIMEOUT
	_set_combo(combo + 1)


func _on_hit_taken(info: Dictionary) -> void:
	if float(info.get("damage", 0.0)) > 0.0 and not bool(info.get("blocked", false)):
		_set_combo(0)


func _set_combo(value: int) -> void:
	if value == combo:
		return
	combo = value
	Events.combo_changed.emit(self, combo)
