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
##            when the Director grants it an attack token (or during a gang-up rush). After
##            an exchange (throwing a punch, or eating one) it backs off to get its breath
##            and its guard back before coming again, and it reads punches being lined up
##            at it: covering up high or low (not always the right one), or stepping back
##            out of a kick. Fights go in waves, like a real scrap, not toe to toe.
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
## Set by Chatter while this NPC is in a conversation: stand still and face them.
var chatting_with: Node3D = null

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
var _recover_t := 0.0     # backing off after an exchange
var _guard_t := 0.0       # seconds left covering up
var _read_windup := false # already reacted to the foe's current wind-up
## Talked down (Npc.hear_words): seconds left where it won't volunteer to rejoin the fight.
var _settled_t := 0.0
var _pleas := 0.0         # recent attempts to talk this NPC down; each one works less
var _hits_from := {}      # player instance id -> hits taken from them tonight
var _last_hit_from := {}  # player instance id -> Time (s) of their last hit
var _face_t := 0.0        # seconds left facing whoever spoke to us
var _heard_from: Node3D = null


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
	hold_resist = float(_type.get("hold_resist", 0.0))
	parry_skill = float(_type.get("parry", 0.0))
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

## Pick a fight with `who`. Ignored for staff. Unless `forced` (they hit us), the Director
## may say that player already has enough on, and we just watch instead.
func engage(who: Fighter, forced := false) -> void:
	if team == Team.STAFF or who == null or not is_hostile_to(who):
		return
	if not forced and _settled_t > 0.0 and not bool(_type.get("always_engaged", false)):
		alert()
		return
	if forced:
		_settled_t = 0.0
	if not forced and foe != who and not bool(_type.get("always_engaged", false)):
		var d := _find_director()
		if d != null and not d.has_room(who):
			alert()
			return
	mood = Mood.ENGAGED
	foe = who
	chatting_with = null
	_quiet_t = 0.0


## Notice the fight without joining in.
func alert() -> void:
	if team == Team.STAFF or mood != Mood.CALM:
		return
	mood = Mood.ALERT
	chatting_with = null
	_quiet_t = 0.0


## Step back out of the fight and spectate (the Director does this to keep it 1-2 at a time).
func back_off() -> void:
	if bool(_type.get("always_engaged", false)) or mood != Mood.ENGAGED:
		return
	_drop_token()
	mood = Mood.ALERT
	foe = null
	rushing = 0.0
	rush_grab = false
	_quiet_t = 0.0


## How much this NPC is in the thick of it (higher stays in when the Director trims).
func engagement_score() -> float:
	var s := -_quiet_t
	if bool(_type.get("always_engaged", false)):
		s += 1000.0
	if rushing > 0.0:
		s += 100.0
	if _has_token:
		s += 50.0
	if foe != null and is_instance_valid(foe):
		s -= global_position.distance_to(foe.global_position) * 0.5
	return s


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
	if float(info.get("damage", 0.0)) > 0.0 and not bool(info.get("blocked", false)) \
			and mood == Mood.ENGAGED and _rng.randf() < 0.6:
		# Rocked: back off and get the guard up before coming again.
		_recover_t = maxf(_recover_t, _rng.randf_range(0.7, 1.5))
		_drop_token()
	var attacker := info.get("attacker") as Fighter
	if attacker != null and attacker.team == Team.PLAYERS:
		var id := attacker.get_instance_id()
		_hits_from[id] = int(_hits_from.get(id, 0)) + 1
		_last_hit_from[id] = Time.get_ticks_msec() / 1000.0
	if attacker != null and is_hostile_to(attacker):
		# Whoever hit you is now your problem, unless you're busy with someone else.
		if mood != Mood.ENGAGED or foe == null or not foe.can_be_targeted() \
				or _rng.randf() < 0.6:
			engage(attacker, true)


# --- Being talked to (host) ------------------------------------------------------------

## Hits `who` has landed on us tonight.
func hits_from(who: Node) -> int:
	return int(_hits_from.get(who.get_instance_id(), 0)) if who != null else 0


## Seconds since `who` last hit us (INF if never).
func since_hit_by(who: Node) -> float:
	if who == null or not _last_hit_from.has(who.get_instance_id()):
		return INF
	return Time.get_ticks_msec() / 1000.0 - float(_last_hit_from[who.get_instance_id()])


func is_settled() -> bool:
	return _settled_t > 0.0


## A player said something to us. `heard` is TalkIntent.classify(). Changes our mood and
## returns what it did (a TalkLines outcome): calmed, unconvinced, riled, fuming, cowed,
## chat or shrug. Staff and police listen but are never talked down.
func hear_words(who: Fighter, heard: Dictionary) -> String:
	if who == null or is_down():
		return "shrug"
	_heard_from = who
	_face_t = 4.0
	var intent := String(heard.get("intent", "none"))
	var strength := float(heard.get("strength", 0.0))
	if team == Team.STAFF:
		match intent:
			"provoke": return "riled"
			"calm": return "calmed" if hits_from(who) == 0 else "unconvinced"
			"chat": return "chat"
		return "shrug"
	match intent:
		"calm":
			return _try_placate(who, strength, bool(heard.get("apology", false)))
		"provoke":
			return _get_provoked(who, strength, bool(heard.get("loud", false)))
		"chat":
			if mood == Mood.CALM:
				return "chat"
			return "shrug"  # small talk in the middle of a scrap: "You what?"
	return "shrug"


## Chance that a calming word works right now, 0..1.
func placate_chance(who: Fighter, strength: float, apology: bool) -> float:
	if bool(_type.get("always_engaged", false)):
		return 0.0  # the Old Bill aren't talked out of an arrest
	var c := 0.25 + strength * 0.65
	c *= 1.15 - float(_type.get("aggression", 1.0)) * 0.3
	c /= 1.0 + 0.3 * hits_from(who)  # each punch you've landed makes them less forgiving
	if apology and since_hit_by(who) < 4.0:
		c *= 1.25  # "it was an accident" is believable straight after a stray one
	var d := _find_director()
	if d != null and float(d.heat) > 0.7:
		c *= 0.7
	c *= pow(0.75, _pleas)  # the fifth "calm down" in a row doesn't land
	return clampf(c, 0.03, 0.92)


func _try_placate(who: Fighter, strength: float, apology: bool) -> String:
	var chance := placate_chance(who, strength, apology)
	_pleas += 1.0
	if _rng.randf() >= chance:
		return "unconvinced"
	settle(who)
	return "calmed"


## Talked down: stop fighting `who` (if we were), and don't volunteer to rejoin for a while.
## Being hit again still sets us off.
func settle(who: Node = null) -> void:
	if bool(_type.get("always_engaged", false)) or team == Team.STAFF:
		return
	_settled_t = _rng.randf_range(20.0, 35.0)
	if mood == Mood.ENGAGED and (who == null or foe == who or foe == null):
		back_off()
	var d := _find_director()
	if d != null:
		d.heat = maxf(float(d.heat) - 0.08, 0.0)
		if float(d.heat) < 0.35 and mood == Mood.ALERT:
			calm_down()


func _get_provoked(who: Fighter, strength: float, loud: bool) -> String:
	_settled_t = 0.0
	var bravery := float(_type.get("bravery", 0.5))
	var d := _find_director()
	if d != null and loud:
		d.heat = minf(float(d.heat) + 0.04, 1.0)
	if mood == Mood.ENGAGED and foe == who:
		# Already at it: come in sooner.
		_attack_cd = minf(_attack_cd, 0.3)
		_recover_t = 0.0
		return "fuming"
	if bravery < 0.35 and _rng.randf() > bravery + strength * 0.3:
		alert()
		return "cowed"
	var chance := clampf(bravery * 0.6 + strength * 0.5, 0.1, 0.95)
	if mood == Mood.CALM:
		chance *= 0.6  # a quiet drinker usually just turns round first
	if _rng.randf() < chance:
		engage(who)
		if mood == Mood.ENGAGED and foe == who:
			return "riled"
	alert()
	return "riled" if strength > 0.5 else "unconvinced"


## Claude's verdict on what the words did (PunterMind effects). Returns a TalkLines outcome.
func apply_talk_effect(who: Fighter, effect: String) -> String:
	if who == null:
		return "shrug"
	_heard_from = who
	_face_t = 4.0
	if team == Team.STAFF:
		return "chat"
	match effect:
		"calm_down":
			if bool(_type.get("always_engaged", false)):
				return "unconvinced"
			_pleas += 1.0
			settle(who)
			return "calmed"
		"stay_wary":
			if mood == Mood.ENGAGED and foe == who and not bool(_type.get("always_engaged", false)):
				back_off()
			else:
				alert()
			return "unconvinced"
		"square_up":
			return _get_provoked(who, 0.9, false)
		"attack":
			_settled_t = 0.0
			engage(who)
			if mood == Mood.ENGAGED and foe == who:
				_attack_cd = 0.0
				_recover_t = 0.0
				return "fuming"
			alert()
			return "riled"
		"cower":
			alert()
			return "cowed"
	return "chat" if mood == Mood.CALM else "shrug"


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
	_settled_t = maxf(_settled_t - delta, 0.0)
	_pleas = maxf(_pleas - delta / 12.0, 0.0)
	_face_t = maxf(_face_t - delta, 0.0)
	_recover_t = maxf(_recover_t - delta, 0.0)
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
		State.BLOCK:
			_guard_t -= delta
			if _guard_t <= 0.0 or mood != Mood.ENGAGED or team == Team.STAFF:
				request_block(false)
				return
			if foe != null and is_instance_valid(foe):
				_look_at = foe.global_position
				_back_off(foe, 0.5)  # covered up, shuffling back
			return
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
	if _face_t > 0.0 and is_instance_valid(_heard_from):
		# Someone's talking to us: stop and look at them.
		_look_at = _heard_from.global_position
		move_input = _separation() * 0.5
		return
	if chatting_with != null and is_instance_valid(chatting_with):
		# In a conversation: hold still, face them, stay out of their personal space.
		_look_at = chatting_with.global_position
		_wander_to = Vector3.INF
		move_input = _separation() * 0.5
		return
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
	if _face_t > 0.0 and is_instance_valid(_heard_from) and _heard_from is Fighter:
		p = _heard_from as Fighter
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
		if heat > 0.45 and _settled_t <= 0.0 \
				and _rng.randf() < float(_type["bravery"]) * heat * 0.15:
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
	if _read_foe():
		return
	var to := foe.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else get_facing()
	if _recover_t > 0.0 and rushing <= 0.0:
		_back_off(foe, 0.7)
		return
	var wants_in := _attack_cd <= 0.0 and not foe.is_down()
	if wants_in and not _has_token:
		_has_token = _request_token()
		_token_used = false
		_token_t = 0.0
	if wants_in and _has_token:
		if d > 1.8:
			# Step in deliberately rather than charging, so the player sees who's coming.
			move_input = (dir + _separation() * 0.3).limit_length(0.8)
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
		_attack_cd = _rng.randf_range(1.8, 3.2) / aggression
		# Then step back out (once the swing's done) rather than stand there trading.
		_recover_t = _rng.randf_range(1.2, 2.0) / sqrt(aggression)
		if rushing > 0.0:
			_attack_cd *= 0.6
		return
	# Waiting for a turn: size them up. Circle slowly on a ring round the foe, sometimes
	# just stand and stare, keeping apart from mates.
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = _rng.randf_range(1.5, 3.5)
		var roll := _rng.randf()
		if roll < 0.3:
			_strafe = 0.0  # hold ground and glare
		elif roll < 0.6 or _strafe == 0.0:
			_strafe = -1.0 if _rng.randf() < 0.5 else 1.0
	var ring := float(_type["circle_distance"]) + 0.4
	var radial := clampf(d - ring, -1.0, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe
	move_input = (dir * radial * 0.6 + tangent * 0.25 + _separation()).limit_length(0.5)


## The foe is lining something up at us. Once per wind-up, maybe read it: cover the right
## spot (or the wrong one), or step back out of a guard breaker. True if we reacted.
func _read_foe() -> bool:
	if foe.state != State.WINDUP or foe.target != self:
		_read_windup = false
		return false
	if _read_windup:
		return false
	_read_windup = true
	if _rng.randf() >= float(_type.get("defence", 0.0)):
		return false  # didn't see it coming
	_drop_token()
	var away := global_position - foe.global_position
	away.y = 0.0
	if foe.defend_hint() == "dodge" or _rng.randf() < 0.2:
		request_dodge(away.normalized())
		return true
	var zone := Moves.GUARD_BODY if foe.attack_zone() != Moves.GUARD_HEAD else Moves.GUARD_HEAD
	if _rng.randf() >= float(_type.get("guard_skill", 0.5)):
		zone = Moves.GUARD_HEAD if zone == Moves.GUARD_BODY else Moves.GUARD_BODY  # guessed wrong
	request_block(true, zone)
	_guard_t = foe.windup_remaining() + _rng.randf_range(0.5, 1.1)
	return true


## Back away from `who` out past the circling ring, drifting sideways, at `speed` (0..1).
func _back_off(who: Fighter, speed: float) -> void:
	var to := who.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / d if d > 0.01 else get_facing()
	var ring := float(_type["circle_distance"]) + 0.6
	var radial := clampf(d - ring, -1.0, 0.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe
	move_input = (dir * radial + tangent * 0.3 + _separation()).limit_length(speed)


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
