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
##   shoulder charge, LB + B clinch knee. LB + X with the left stick pulled back kicks him in
##   the groin. LB + RB together grabs and holds; while holding, punches are knees, A or Throw
##   hurls them, LB + RB again lets go.
##   A dodges the way the left stick points (back, with the stick centred).
##   Right stick moves the head. A flick slips head shots for a moment, and slipping one
##   right as it lands sets up a counter. Ducking (stick down) and punching goes to the body.
## Punches thrown in rhythm (in the previous punch's recovery, or just after it) build a
## string, and known strings are combos that hit harder (see Moves.COMBOS): jab, body jab,
## kick is "Below the belt", which kicks them in the groin. Hammering the buttons before a
## punch has finished fumbles the string and leaves you off balance, so timing beats mashing.
## Every strike costs stamina (a miss costs double) and it only comes back when you stop
## throwing, so a man who throws everything ends up gassed: soft, slow and with a guard that
## folds. Hold a hook or an uppercut to load a power shot and let go to throw it; a jab in
## the face while you're loading cancels it. Jabs are cheap and drain a guard hard.
##
## Nobody is chased across the room: you walk into range, and a punch only steps in a
## short way. Near an active enemy you take a stance and square up to them.
## L3 (Tab) locks on to the man in front: you stay squared up to him and every punch goes at
## him, whoever else is about. Press it again to let go; D-pad right (R) switches to the next man.
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
## First-person view (local only, set by BrawlCamera): movement is relative to where you look.
var first_person := false
## First person: which way you're looking (radians round Y, 0 = facing -Z like rotation.y).
var view_yaw := 0.0
## First person: mouse turn waiting to be applied (radians), fed by BrawlCamera.
var view_turn := 0.0
## Right stick, x right and y up: where the head is (drives the head-movement visual).
var head_bob := Vector2.ZERO
var _want_block := false
var _want_zone: StringName = Moves.GUARD_HEAD
## After LB + RB (a hold), the guards stay down until both buttons are let go.
var _guards_latched := false
var _prompts: Node = null
## The punch button holding a power shot, or &"".
var _power_button: StringName = &""


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
		var bars := FoeHealthBars.new()
		bars.name = "FoeHealthBars"
		bars.player = self
		add_child(bars)


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
	if lock_target != null and not is_locked():
		lock_target = null  # down, gone or out of range: the lock lets go
		Events.lock_changed.emit(self, null)
	if is_multiplayer_authority():
		_read_input(delta)
	super(delta)


func _read_input(delta: float) -> void:
	if DartsBoard.local_input_locked() or TalkUi.typing:
		# Playing darts (the darts panel has the controls), or typing a line to a punter.
		move_input = Vector3.ZERO
		_set_block(false, _want_zone)
		return
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dodge_dir := Vector3(stick.x, 0.0, stick.y)
	if first_person:
		dodge_dir = _first_person_move(stick, delta)
	else:
		move_input = dodge_dir
		face_override = Vector3.ZERO
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
			request_dodge(dodge_dir)
			_buffered = &""
		return
	if Input.is_action_just_pressed("throw") and state == State.GRABBING:
		request_throw()
		return
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock()
	if Input.is_action_just_pressed("lock_next"):
		next_lock()
	if Input.is_action_just_pressed("headbutt"):
		press(&"headbutt")
	if _power_button != &"" and not Input.is_action_pressed(String(_power_button)):
		release_power()
	for b in Moves.PUNCHES:
		if Input.is_action_just_pressed(String(b)):
			if button(b, lb, rb, head_bob.y < -0.5, true):
				_power_button = b
	_tick_buffer(delta)


## First-person movement. Squared up to a man (locked on or in a stance), you look at him and
## the stick is footwork round him: forward closes in, sideways circles. Walking free, the stick
## steers: forward and back walk, sideways turns (as does the mouse), so stepping back never
## spins you round. Returns the world direction a dodge should go (the full stick, as seen).
func _first_person_move(stick: Vector2, delta: float) -> Vector3:
	var squared := stance_target != null and is_instance_valid(stance_target) \
		and state in [State.IDLE, State.BLOCK, State.WINDUP, State.ATTACK, State.DODGE, State.STAGGER]
	if squared:
		view_yaw = lerp_angle(view_yaw, rotation.y, clampf(10.0 * delta, 0.0, 1.0))
		face_override = Vector3.ZERO
	else:
		view_yaw = wrapf(view_yaw - stick.x * FP_TURN_SPEED * delta - view_turn, -PI, PI)
		face_override = view_forward()
	view_turn = 0.0
	var fwd := view_forward()
	var right := fwd.cross(Vector3.UP)
	var full := right * stick.x - fwd * stick.y
	move_input = full if squared else -fwd * stick.y
	return full


## First person: the flat direction you're looking.
func view_forward() -> Vector3:
	return Vector3(-sin(view_yaw), 0.0, -cos(view_yaw))


## Turn rate (radians a second) of the stick or A/D in first person when not squared up.
const FP_TURN_SPEED := 2.6


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
## to the body. `hold`: the button stays down, so a hook or uppercut loads into a power shot
## until release_power(). Returns true if a held punch went out.
func button(b: StringName, lb := false, rb := false, duck := false, hold := false) -> bool:
	if lb and not rb and b == &"jab" and _stick_back():
		return press(&"groin_kick", hold)  # LB + X with the stick pulled back: below the belt
	if lb and not rb:
		return press(Moves.LB_MOVES[b], hold)
	elif rb or duck:
		return press(Moves.BODY_PUNCHES[b], hold)
	return press(Moves.PUNCHES[b], hold)


## The left stick is pulled back, away from the way we're facing.
func _stick_back() -> bool:
	var m := Vector3(move_input.x, 0.0, move_input.z)
	return m.length() > 0.5 and m.normalized().dot(get_facing()) < -0.5


## Let go of the punch button: a loading power shot goes.
func release_power() -> void:
	_power_button = &""
	if state == State.WINDUP and _hold_power:
		request_unleash()


## Lock on to the man in front, or let go if locked. Candidates are enemies on their feet
## within LOCK_RANGE, the ones fighting you and in front first.
func toggle_lock() -> void:
	if is_locked():
		lock_target = null
	else:
		var foes := lock_candidates()
		lock_target = foes[0] if not foes.is_empty() else null
	Events.lock_changed.emit(self, lock_target)


## Locked on: switch to the next man round from him, clockwise (or lock on if not locked).
func next_lock() -> void:
	if not is_locked():
		toggle_lock()
		return
	var best: Fighter = null
	var best_turn := INF
	var from := lock_target.global_position - global_position
	for f in lock_candidates():
		if f == lock_target:
			continue
		var to := f.global_position - global_position
		# Angle from the current lock round to this man, clockwise seen from above, 0..360.
		var turn := fposmod(rad_to_deg(atan2(from.x * to.z - from.z * to.x, from.x * to.x + from.z * to.z)), 360.0)
		if turn < best_turn:
			best_turn = turn
			best = f
	if best != null:
		lock_target = best
		Events.lock_changed.emit(self, lock_target)


func lock_candidates() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var f := node as Fighter
		if f == null or f == self or not is_hostile_to(f) or f.is_down() or not f.can_be_targeted():
			continue
		if _flat_dist(f) <= Moves.LOCK_RANGE:
			out.append(f)
	var fwd := get_facing()
	var score := func(f: Fighter) -> float:
		var to := f.global_position - global_position
		to.y = 0.0
		var ang := rad_to_deg(fwd.angle_to(to.normalized())) if to.length() > 0.01 else 0.0
		var fighting: bool = f.stance_target == self or ("foe" in f and f.get("foe") == self)
		return to.length() + ang / 45.0 - (2.0 if fighting else 0.0)
	out.sort_custom(func(a: Fighter, b: Fighter) -> bool: return score.call(a) < score.call(b))
	return out


## Right stick: move the head. A flick past the threshold slips (head shots miss for a moment).
func set_head_bob(v: Vector2) -> void:
	var was := head_bob.length()
	head_bob = v.limit_length(1.0)
	if head_bob.length() >= Moves.SLIP_THRESHOLD and was < Moves.SLIP_THRESHOLD:
		request_slip(head_bob)


## A button asking for `move`. It goes now if we're free or in the chain window, is
## buffered if the window is about to open, and otherwise counts as mashing. Returns true if
## it went out now as a held (chargeable) punch.
func press(move: StringName, hold := false) -> bool:
	if _fumble_t > 0.0:
		return false
	if state == State.GRABBING or can_attack():
		hold = hold and state != State.GRABBING and bool(Moves.get_move(move)["chargeable"])
		_perform(move, hold)
		return hold
	if state == State.WINDUP or state == State.ATTACK:
		if _buffered == &"" and _time_to_chain() <= Moves.INPUT_BUFFER:
			_buffered = move
			_buffer_t = Moves.INPUT_BUFFER + 0.05
			return false
		# Too early, or a second press on top of a buffered one: that's mashing.
		_mash += 1
		if _mash >= Moves.MASH_LIMIT:
			_fumble()
	return false


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
func _perform(move: StringName, hold := false) -> void:
	if state == State.GRABBING:
		request_attack(&"knee")
		return
	var aim := move_input
	var tgt := Targeting.pick(self, aim)
	if is_locked():
		# Locked on: it goes at him (and steps in if he's just out of reach), or at nobody.
		tgt = lock_target if _flat_dist(lock_target) <= Moves.LUNGE_RANGE else null
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
		if not is_locked():
			tgt = Targeting.pick(self, aim)
	var bonus := float(combo_row.get("bonus", 1.0))
	var cname := String(combo_row.get("name", ""))
	if not combo_row.is_empty() and combo_row["seq"].size() >= 3 \
			and not Moves.combo_continues(combo_row["seq"]):
		_history.clear()  # a finished string starts afresh
	_mash = 0
	_since_attack = 0.0
	request_attack(move, tgt, bonus, cname, hold)


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
