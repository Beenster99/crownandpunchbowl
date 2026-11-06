class_name PlayerFighter
extends Fighter
## Player-controlled fighter: a boxing pad layout on top of Fighter.
##
## Controller (keyboard in brackets):
##   X jab (LMB), B hook (RMB), Y uppercut (F). R3 headbutt (Q).
##   LB head guard (Shift), RB body guard (Ctrl). Hold one, then raise it just as a punch
##   lands to parry, and your next punch is a counter. Head guard only stops head shots,
##   body guard only body shots, so read where it's going.
##   RB + a punch throws it to the body. LB + X kick (stomps a man on the floor), LB + Y
##   shoulder charge, LB + B clinch knee. LB + RB together grabs and holds; while holding,
##   punches are knees, A or Throw hurls them, LB + RB again lets go.
##   A dodges the way the left stick points (back, with the stick centred).
##   Right stick moves the head. A flick slips head shots for a moment, and slipping one
##   right as it lands sets up a counter. Ducking (stick down) and punching goes to the body.
## Punches thrown in rhythm (in the previous punch's recovery, or just after it) build a
## string, and known strings are combos that hit harder (see Moves.COMBOS): jab, body jab,
## kick is "Below the belt", which kicks them in the groin. Hammering the buttons before a
## punch has finished fumbles the string and leaves you off balance, so timing beats mashing.
##
## Nobody is chased across the room: you walk into range, and a punch only steps in a
## short way. Near an active enemy you take a stance and square up to them.
## Mash any button while held to struggle.

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
## Right stick, x right and y up: where the head is (drives the head-movement visual).
var head_bob := Vector2.ZERO
var _want_block := false
var _want_zone: StringName = Moves.GUARD_HEAD
## After LB + RB (a hold), the guards stay down until both buttons are let go.
var _guards_latched := false
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
	set_head_bob(Input.get_vector("bob_left", "bob_right", "bob_down", "bob_up"))

	var buttons := ["jab", "hook", "uppercut", "headbutt", "dodge", "guard_head", "guard_body"]
	if state == State.HELD:
		for a in buttons:
			if Input.is_action_just_pressed(a):
				request_struggle()
		return
	if state == State.DOUBLED:
		return  # on all fours, holding it: nothing to do but wait

	# A tap shorter than a physics frame still counts as held for that frame.
	var lb_now := Input.is_action_just_pressed("guard_head")
	var rb_now := Input.is_action_just_pressed("guard_body")
	var lb := Input.is_action_pressed("guard_head") or lb_now
	var rb := Input.is_action_pressed("guard_body") or rb_now
	if guards(lb, rb, lb_now, rb_now):
		return
	if Input.is_action_just_pressed("dodge"):
		if state == State.GRABBING:
			request_throw()
		else:
			request_dodge(move_input)
			_buffered = &""
		return
	if Input.is_action_just_pressed("throw") and state == State.GRABBING:
		request_throw()
		return
	if Input.is_action_just_pressed("headbutt"):
		press(&"headbutt")
	for b in Moves.PUNCHES:
		if Input.is_action_just_pressed(String(b)):
			button(b, lb, rb, head_bob.y < -0.5)
	_tick_buffer(delta)


# --- Input steps (public so tests and bots can drive them without real input) ----------

## The shoulder buttons. One held is a guard (LB head, RB body). Both together grabs and
## holds the man in front (or lets go of the one you're holding). Returns true if it grabbed
## or let go this frame.
func guards(lb: bool, rb: bool, lb_now := false, rb_now := false) -> bool:
	if _guards_latched:
		if not lb and not rb:
			_guards_latched = false
		_set_block(false, _want_zone)
		return false
	if lb and rb and (lb_now or rb_now):
		_guards_latched = true
		_set_block(false, _want_zone)
		if state == State.GRABBING:
			request_release()
		else:
			request_grab(Targeting.grab_candidate(self))
		return true
	if state == State.GRABBING:
		return false
	if lb != rb:
		_set_block(true, Moves.GUARD_HEAD if lb else Moves.GUARD_BODY)
	else:
		_set_block(false, _want_zone)
	return false


## A punch button (`b` is &"jab", &"hook" or &"uppercut") with the shoulder buttons held as
## they are: LB turns it into kick / clinch knee / shoulder charge, RB (or ducking) sends it
## to the body.
func button(b: StringName, lb := false, rb := false, duck := false) -> void:
	if lb and not rb:
		press(Moves.LB_MOVES[b])
	elif rb or duck:
		press(Moves.BODY_PUNCHES[b])
	else:
		press(Moves.PUNCHES[b])


## Right stick: move the head. A flick past the threshold slips (head shots miss for a moment).
func set_head_bob(v: Vector2) -> void:
	var was := head_bob.length()
	head_bob = v.limit_length(1.0)
	if head_bob.length() >= Moves.SLIP_THRESHOLD and was < Moves.SLIP_THRESHOLD:
		request_slip(head_bob)


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


func _set_block(on: bool, zone: StringName = Moves.GUARD_HEAD) -> void:
	if on == _want_block and (not on or zone == _want_zone):
		# Re-raise the guard once an attack or stagger ends while the button is still held.
		if on and state == State.IDLE:
			request_block(true, zone)
		return
	_want_block = on
	_want_zone = zone
	request_block(on, zone)


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
	if combo_row.has("becomes"):
		move = combo_row["becomes"]  # e.g. the kick at the end of "Below the belt" goes low
		tgt = Targeting.pick(self, aim)
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
	if bool(info.get("blocked", false)) or bool(info.get("parried", false)) \
			or bool(info.get("slipped", false)):
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
