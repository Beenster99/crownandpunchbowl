class_name Npc
extends Fighter
## An AI-driven Fighter: punters, police and bar staff. The brain runs on the host only and
## drives the Fighter exactly like a player does: move_input every frame, request_attack()
## with a telegraphed move, request_struggle() while held.
##
## Moods:
##   CALM     having a quiet pint. Mills about near `home`. Never attacks.
##   ALERT    a fight is on. Faces the action and keeps its distance. May join in as the
##            heat rises (bravery x heat).
##   ENGAGED  has a grudge against `foe`. Circles at a distance and only steps in to attack
##            when the Director grants it an attack token (or during a gang-up rush).
## A punter only gets ENGAGED when it is hit, a mate nearby is hit (bravery roll), a rush
## pulls it in, or it walks in on a hot fight. With no blows traded for a while and the heat
## low, it cools back down to ALERT and then CALM, so the players set the pace.

enum Mood { CALM, ALERT, ENGAGED }

## Row in NpcTypes.DATA. Set before the node enters the tree.
@export var kind: StringName = &"local"
## Where a calm NPC hangs about (a table, the bar). Staff stay here.
@export var home := Vector3.ZERO

var mood: Mood = Mood.CALM
## Who an ENGAGED NPC is after.
var foe: Fighter = null
## Seconds left in a gang-up rush. Rushing NPCs attack without waiting for a token.
var rushing := 0.0
## Set by the Director during a rush: try to grab `foe` so mates can lay into them.
var rush_grab := false
## The Director that hands out attack tokens. Found by group if not set.
var director: Node = null

var _type: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _has_token := false
var _token_used := false  # the token's attack has started
var _token_t := 0.0       # seconds holding a token without swinging
var _attack_cd := 0.0
var _struggle_t := 0.0
var _quiet_t := 0.0       # seconds since this NPC last traded blows
var _strafe := 1.0
var _strafe_t := 0.0
var _wander_t := 0.0
var _wander_to := Vector3.INF
var _engage_roll_t := 0.0
var _look_at: Vector3 = Vector3.INF


func _ready() -> void:
	_type = NpcTypes.get_type(kind)
	match kind:
		&"staff":
			team = Team.STAFF
			can_be_knocked_out = false
			add_to_group(&"staff")
		&"police":
			team = Team.POLICE
			add_to_group(&"police")
			add_to_group(&"npcs")
		_:
			team = Team.PUNTERS
			add_to_group(&"npcs")
	max_hp = float(_type["max_hp"])
	power = float(_type["power"])
	move_speed = float(_type["move_speed"])
	toughness = float(_type["toughness"])
	grip = float(_type["grip"])
	crawl_fraction = float(_type["crawl_fraction"])
	_rng.seed = hash(String(name)) ^ hash(kind)
	_strafe = 1.0 if _rng.randf() < 0.5 else -1.0
	_attack_cd = _rng.randf_range(0.3, 1.0)
	_tint(_type["colour"])
	super()
	if bool(_type["always_engaged"]):
		mood = Mood.ENGAGED
	hit_taken.connect(_on_hit_taken)
	hit_dealt.connect(func(_info: Dictionary) -> void: _quiet_t = 0.0)


func type_value(key: String) -> Variant:
	return _type.get(key)


# --- Mood changes (host) ---------------------------------------------------------------

## Pick a fight with `who`. Ignored for staff.
func engage(who: Fighter) -> void:
	if team == Team.STAFF or who == null or not is_hostile_to(who):
		return
	mood = Mood.ENGAGED
	foe = who
	_quiet_t = 0.0


## Notice the fight without joining in.
func alert() -> void:
	if team == Team.STAFF or mood != Mood.CALM:
		return
	mood = Mood.ALERT
	_quiet_t = 0.0


func calm_down() -> void:
	if bool(_type.get("always_engaged", false)):
		return
	_drop_token()
	mood = Mood.CALM
	foe = null
	rushing = 0.0
	rush_grab = false


func has_token() -> bool:
	return _has_token


func _on_hit_taken(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_quiet_t = 0.0
	var attacker := info.get("attacker") as Fighter
	if attacker != null and is_hostile_to(attacker):
		# Whoever hit you is now your problem, unless you're busy with someone else.
		if mood != Mood.ENGAGED or foe == null or not foe.can_be_targeted() \
				or _rng.randf() < 0.6:
			engage(attacker)


# --- Brain ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_look_at = Vector3.INF
	if multiplayer.is_server():
		_think(delta)
	super(delta)
	if _look_at != Vector3.INF and state == State.IDLE:
		_turn_toward(_look_at - global_position, delta, 10.0)


func _think(delta: float) -> void:
	_attack_cd -= delta
	_quiet_t += delta
	rushing = maxf(rushing - delta, 0.0)
	if rushing <= 0.0:
		rush_grab = false
	if _has_token:
		_token_t += delta
		var swinging := state == State.WINDUP or state == State.ATTACK
		if (_token_used and not swinging) or (not _token_used and state != State.IDLE) \
				or mood != Mood.ENGAGED or _token_t > 4.0:
			_drop_token()
	move_input = Vector3.ZERO
	match state:
		State.HELD:
			_struggle_t -= delta
			if _struggle_t <= 0.0:
				_struggle_t = float(_type["struggle_interval"]) * _rng.randf_range(0.8, 1.2)
				request_struggle()
			return
		State.CRAWL:
			_crawl_away()
			return
		State.GRABBING:
			_hold_for_mates()
			return
		State.IDLE:
			pass
		_:
			return
	if team == Team.STAFF:
		_think_staff()
		return
	match mood:
		Mood.CALM:
			_think_calm(delta)
		Mood.ALERT:
			_think_alert(delta)
		Mood.ENGAGED:
			_think_engaged(delta)


func _think_staff() -> void:
	var to := home - global_position
	to.y = 0.0
	if to.length() > 0.4:
		move_input = to.normalized() * 0.6
	var p := _nearest_player(12.0)
	if p != null:
		_look_at = p.global_position


func _think_calm(delta: float) -> void:
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = _rng.randf_range(4.0, 9.0)
		var a := _rng.randf() * TAU
		_wander_to = home + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.0, 1.0)
	if _wander_to != Vector3.INF:
		var to := _wander_to - global_position
		to.y = 0.0
		if to.length() > 0.3:
			move_input = to.normalized() * 0.35
		else:
			_wander_to = Vector3.INF
	move_input += _separation() * 0.5


func _think_alert(delta: float) -> void:
	var p := _nearest_player(30.0)
	if p == null:
		return
	var heat := _heat()
	if _quiet_t > 20.0 and heat < 0.1:
		calm_down()
		return
	_look_at = p.global_position
	var to := p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var keep := float(_type["watch_distance"])
	if d < keep - 0.5:
		move_input = -to.normalized() * 0.6  # back off
	move_input += _separation()
	move_input = move_input.limit_length(1.0)
	# The hotter it gets, the more likely onlookers wade in.
	_engage_roll_t -= delta
	if _engage_roll_t <= 0.0:
		_engage_roll_t = 2.0
		if heat > 0.35 and _rng.randf() < float(_type["bravery"]) * heat * 0.3:
			engage(p)


func _think_engaged(delta: float) -> void:
	if foe == null or not is_instance_valid(foe) or not foe.can_be_targeted() \
			or (foe.is_down() and _nearest_player(30.0, true) != null):
		foe = _nearest_player(30.0, true)
		if foe == null:
			foe = _nearest_player(30.0)
		if foe == null:
			mood = Mood.ALERT
			return
	# Cool off when nobody's traded blows for a while and the room has calmed down.
	if not bool(_type["always_engaged"]) and rushing <= 0.0 and _quiet_t > 15.0 \
			and _heat() < 0.2:
		_drop_token()
		mood = Mood.ALERT
		foe = null
		return
	_look_at = foe.global_position
	var to := foe.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else get_facing()
	var wants_in := _attack_cd <= 0.0 and not foe.is_down()
	if wants_in and not _has_token:
		_has_token = _request_token()
		_token_used = false
		_token_t = 0.0
	if wants_in and _has_token:
		if d > 1.8:
			move_input = (dir + _separation() * 0.3).limit_length(1.0)
			return
		if rush_grab and foe.can_be_grabbed():
			rush_grab = false
			request_grab(foe)
			if state == State.GRABBING:
				_drop_token()
				return
		var move: StringName = NpcTypes.pick_weighted(_type["moves"], _rng)
		request_attack(move, foe)
		if state == State.WINDUP:
			_token_used = true
		else:
			_drop_token()
		var aggression := maxf(float(_type["aggression"]), 0.1)
		_attack_cd = _rng.randf_range(1.0, 2.2) / aggression
		if rushing > 0.0:
			_attack_cd *= 0.5
		return
	# Waiting for a turn: circle on a ring round the foe, strafing, keeping apart from mates.
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = _rng.randf_range(1.5, 3.5)
		if _rng.randf() < 0.4:
			_strafe = -_strafe
	var ring := float(_type["circle_distance"])
	var radial := clampf(d - ring, -1.0, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe
	move_input = (dir * radial * 0.8 + tangent * 0.35 + _separation()).limit_length(0.7)


## Holding a player for mates: stand still and knee them now and then.
func _hold_for_mates() -> void:
	if holding != null:
		_look_at = holding.global_position
		if _attack_cd <= 0.0:
			_attack_cd = _rng.randf_range(0.8, 1.4)
			request_attack(&"shove")  # becomes a knee while grabbing


func _crawl_away() -> void:
	var p := _nearest_player(6.0)
	if p == null:
		return
	var away := global_position - p.global_position
	away.y = 0.0
	if away.length() > 0.01:
		move_input = away.normalized()


# --- Helpers ---------------------------------------------------------------------------

func _find_director() -> Node:
	if director == null or not is_instance_valid(director):
		director = get_tree().get_first_node_in_group(&"director") if is_inside_tree() else null
	return director


func _heat() -> float:
	var d := _find_director()
	return float(d.heat) if d != null else 0.5


func _request_token() -> bool:
	var d := _find_director()
	if d == null:
		return true
	return d.request_token(self)


func _drop_token() -> void:
	if not _has_token:
		return
	_has_token = false
	_token_used = false
	var d := _find_director()
	if d != null:
		d.release_token(self)


func _nearest_player(max_dist: float, standing_only := false) -> Fighter:
	var best: Fighter = null
	var best_d := max_dist
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f.team != Team.PLAYERS or not f.can_be_targeted():
			continue
		if standing_only and f.is_down():
			continue
		var d := f.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = f
	return best


## Push away from other fighters standing too close, so crowds spread into a ring.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == self or f.is_ko() or f.team == Team.PLAYERS:
			continue
		var away := global_position - f.global_position
		away.y = 0.0
		var d := away.length()
		if d < 1.2 and d > 0.001:
			push += away / d * (1.2 - d)
	return push


func _turn_toward(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.1:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(rate * delta, 0.0, 1.0))


func _tint(colour: Color) -> void:
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var mat := StandardMaterial3D.new()
	mat.set_meta("base", colour)
	mat.albedo_color = colour
	body.material_override = mat
