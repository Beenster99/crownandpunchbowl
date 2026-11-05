class_name PlayerFighter
extends Fighter
## Player-controlled fighter: freeflow controls on top of Fighter.
##
## Punch walks a jab → cross → hook chain while you keep hitting in rhythm, and turns into
## a finisher once the combo counter is high enough. Every attack lunges to the enemy you
## push the stick towards (or the one in front). Kick stomps a downed enemy when there's no
## one standing to kick. Grab holds an enemy for your mates; punch while holding to knee,
## Throw to hurl them, Grab again to let go. Mash any button while held to struggle free.

## Seconds an early button press is remembered, so mashing in rhythm chains cleanly.
@export var input_buffer := 0.3
## Seconds after an attack ends that the next punch still continues the chain.
@export var chain_grace := 0.45

## Current combo (hits landed without a long gap or being hit). HUD reads Events.combo_changed.
var combo := 0
var farmer: Dictionary = {}

var _chain_i := 0
var _since_attack := 99.0
var _combo_t := 0.0
var _last_finisher_at := 0
var _buffered: StringName = &""
var _buffer_t := 0.0


func _ready() -> void:
	team = Team.PLAYERS
	_apply_farmer()
	super()
	hit_dealt.connect(_on_hit_dealt)
	hit_taken.connect(_on_hit_taken)


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


func finisher_ready() -> bool:
	return combo >= Moves.FINISHER_COMBO and combo - _last_finisher_at >= Moves.FINISHER_COMBO


func _physics_process(delta: float) -> void:
	_tick_combo(delta)
	if is_multiplayer_authority():
		_read_input(delta)
	super(delta)


func _read_input(delta: float) -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_input = Vector3(stick.x, 0.0, stick.y)

	if state == State.HELD:
		for a in ["punch", "kick", "headbutt", "grab", "dodge"]:
			if Input.is_action_just_pressed(a):
				request_struggle()
		return

	if Input.is_action_just_pressed("counter"):
		request_counter()
		_buffered = &""
		return
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

	for a in ["punch", "kick", "headbutt"]:
		if Input.is_action_just_pressed(a):
			_buffered = StringName(a)
			_buffer_t = input_buffer
	if _buffered != &"":
		_buffer_t -= delta
		if state == State.GRABBING or can_act() or can_chain():
			_perform(_buffered)
			_buffered = &""
		elif _buffer_t <= 0.0:
			_buffered = &""


## Turn a button into a move and a target, then ask the host.
func _perform(button: StringName) -> void:
	if state == State.GRABBING:
		request_attack(&"knee")
		return
	var aim := move_input
	var move: StringName
	match button:
		&"punch":
			var chaining := can_chain() or _since_attack <= chain_grace
			_chain_i = (_chain_i + 1) % Moves.PUNCH_CHAIN.size() if chaining else 0
			move = Moves.PUNCH_CHAIN[_chain_i]
			if finisher_ready():
				move = Moves.FINISHER_MOVE
				_last_finisher_at = combo
				_chain_i = -1
		&"kick":
			move = &"kick"
		&"headbutt":
			move = &"headbutt"
	var tgt := Targeting.pick(self, aim)
	if tgt == null and button == &"kick":
		var floored := Targeting.pick(self, aim, Moves.LUNGE_RANGE * 0.5, true)
		if floored != null:
			move = &"stomp"
			tgt = floored
	_since_attack = 0.0
	request_attack(move, tgt)


func _tick_combo(delta: float) -> void:
	if state == State.ATTACK or state == State.WINDUP:
		_since_attack = 0.0
	else:
		_since_attack += delta
	if combo > 0:
		_combo_t -= delta
		if _combo_t <= 0.0:
			_set_combo(0)


func _on_hit_dealt(_info: Dictionary) -> void:
	_combo_t = Moves.COMBO_TIMEOUT
	_set_combo(combo + 1)


func _on_hit_taken(info: Dictionary) -> void:
	if float(info.get("damage", 0.0)) > 0.0:
		_set_combo(0)


func _set_combo(value: int) -> void:
	if value == combo:
		return
	combo = value
	if combo == 0:
		_last_finisher_at = 0
	Events.combo_changed.emit(self, combo)
