class_name Fighter
extends CharacterBody3D
## Base class for everyone who brawls: players, punters, police and bar staff.
##
## How to drive a Fighter (players and AI brains do exactly the same thing):
##   - Set `move_input` every physics frame (world-space XZ, length 0..1).
##   - Call the request_* methods for actions: attack, block, grab, release, throw,
##     dodge and struggle. Call them on the fighter's multiplayer authority (the owning
##     peer for players, the host for NPCs). They are forwarded to the host, which
##     validates them and replicates the result to every peer.
##   - Read `state`, `hp`, `target`, `held_by` and `holding`. Listen to the signals below or
##     to the combat signals on `Events`.
##
## Damage only ever happens on the host, through take_hit(). Combat `Events` fire on every
## peer (so FX and HUD work on clients); gameplay listeners must check multiplayer.is_server().
## Difficulty is applied here: punters and police get `enemy_health` on spawn and
## `enemy_damage` on hits against players, and heal() applies `heal_multiplier` for players.
## Don't apply those again elsewhere.
##
## Placeholder visuals: if the scene has a MeshInstance3D called "Body" (and optionally
## "Facing"), it is tinted on hits and laid flat when down. The characters workstream
## replaces this by listening to `state_changed` and `move_started`.

signal state_changed(old_state: State, new_state: State)
## A move began (animation hook). Fires on every peer.
signal move_started(move_id: StringName)
## This fighter was hit. Same keys as Events.hit_landed. Fires on every peer.
signal hit_taken(info: Dictionary)
## One of this fighter's attacks landed. Fires on every peer.
signal hit_dealt(info: Dictionary)
## Entered or left a fighting stance (guard up, facing the foe). Fires on every peer.
signal stance_changed(in_stance: bool)
## Slipped the head (right stick flick) towards `dir` (x: right, y: up). Fires on every peer.
signal slipped(dir: Vector2)
## A power shot started loading (true) or went (false).
signal power_charging(on: bool)

## DOUBLED: kicked in the groin, on all fours holding it. Appended so older values keep
## their numbers on the wire.
enum State { IDLE, ATTACK, WINDUP, STAGGER, DOWN, CRAWL, KO, HELD, GRABBING, DODGE, BLOCK, DOUBLED }
enum Team { PLAYERS, PUNTERS, POLICE, STAFF }

const GROUP := &"fighters"
const GRAVITY := 20.0
const _RELEASE_PLAIN := 0   # victim stumbles free
const _RELEASE_SILENT := 1  # victim's state is set by whatever happens next (hit, throw)

@export var team: Team = Team.PUNTERS
@export var max_hp := 100.0
## Outgoing damage multiplier.
@export var power := 1.0
@export var move_speed := 4.2
## Divides incoming stagger time, poise damage and knockback. Rugby lads are tough.
@export var toughness := 1.0
## How long this fighter's holds last, and how well they keep hold of a strong man.
@export var grip := 1.0
## How hard this fighter is to hold: the chance (over the holder's grip) of shrugging a
## grab off, and how much faster they wriggle free. Rugby lads are a handful.
@export_range(0.0, 1.0) var hold_resist := 0.0
## Chance that a guard raised at the last moment parries (players always do; most punters
## just cover up and take it on the arms).
@export_range(0.0, 1.0) var parry_skill := 1.0
## Below this fraction of max_hp, a fighter who gets knocked down only gets up to crawl.
@export_range(0.0, 1.0) var crawl_fraction := 0.25
## The gas tank (see Moves.STAMINA): strikes spend it, blocks and body shots drain it.
@export var max_stamina := Moves.STAMINA
## False for anyone who must never be KO'd. (Bar staff are untouchable anyway.)
@export var can_be_knocked_out := true
@export var get_up_time := 1.5
## Dress this fighter in a CharacterRig (FighterVisual) instead of the capsule placeholder.
@export var use_rig := true

var hp: float
var stamina: float
var state: State = State.IDLE
## World-space desired movement, set by the controller each physics frame.
var move_input := Vector3.ZERO
## Who this fighter is attacking. Set when a move starts. Controllers may also set it.
var target: Fighter = null
## The fighter holding this one (state HELD), or null.
var held_by: Fighter = null
## The fighter this one is holding (state GRABBING), or null.
var holding: Fighter = null
## Equipped weapon (workstream 5). Duck-typed; see equip().
var weapon: Node = null
## 0..1, set by drinks (workstream 5). Read by traits and the HUD.
var tipsy := 0.0
var nose_broken := false
## Id of the move in progress (WINDUP/ATTACK), or &"".
var current_move: StringName = &""
## In a fighting stance: an exchange happened recently, or (players) an active enemy is
## close. Movement becomes footwork facing `stance_target`. Animations use it to pick a
## relaxed idle or a guard.
var in_stance := false
var stance_target: Fighter = null
## Which guard is up while state is BLOCK: Moves.GUARD_HEAD (LB) or Moves.GUARD_BODY (RB).
var guard_zone: StringName = Moves.GUARD_HEAD
## The last slip's direction (x right, y up), for visuals. Fades with the slip.
var slip_dir := Vector2.ZERO

var _move: Dictionary = {}
var _state_t := 0.0
var _state_len := 0.0
var _windup_left := 0.0
var _lunge_t := 0.0
var _attack_t := 0.0
var _impulse := Vector3.ZERO
var _walk_vel := Vector3.ZERO  ## smoothed footwork velocity (accel/decel)
var _dodge_dir := Vector3.ZERO
var _dodge_cd := 0.0
var _poise := Moves.POISE
var _poise_wait := 0.0
var _invuln := 0.0
var _hold_left := 0.0
var _escape := 0.0
var _knee_cd := 0.0
var _flash := 0.0
var _saved_layer := 0
var _ko_announced := false
var _combat_t := 0.0
var _bonus := 1.0
var _combo_name := ""
var _counter_ready := 0.0
var _lunge_ok := false
var _launch_y := 0.0
var _vault_origin := Vector3.ZERO
var _vault_normal := Vector3.ZERO
var _vault_t := -1.0
var _slip_t := 0.0       # head shots miss while > 0 (counts down from Moves.SLIP_WINDOW)
var _slip_cd := 0.0
var _charge_hit := false  # this shoulder charge has already hit someone
var _stamina_wait := 0.0
var _hold_power := false  # the button is still held: at the end of the windup, it loads
var _charging := false
var _charge_t := 0.0
var _power := 1.0         # damage multiplier of the strike in progress
var _power_frac := 0.0
var _saved_mask := 0
var _airborne := false
var _fall_peak := 0.0
var _impacts: BodyImpacts


func _ready() -> void:
	add_to_group(GROUP)
	if team == Team.PUNTERS or team == Team.POLICE:
		max_hp *= float(GameData.difficulty()["enemy_health"])
	hp = max_hp
	stamina = max_stamina
	_poise = Moves.POISE * toughness
	_saved_layer = collision_layer
	if use_rig:
		FighterVisual.attach(self)
	_impacts = BodyImpacts.attach(self)  # shoves props, goes over the bar (scripts/physics)


# --- Queries --------------------------------------------------------------------------

func is_down() -> bool:
	return state == State.DOWN or state == State.CRAWL or state == State.KO


func is_ko() -> bool:
	return state == State.KO


## Free to start a new action right now.
func can_act() -> bool:
	return state == State.IDLE


## Free to throw an attack: idle, blocking (it drops the guard) or chaining.
func can_attack() -> bool:
	return state == State.IDLE or state == State.BLOCK or can_chain()


## Whether a hit from `from_pos` to `zone` (head, body or groin) would hit this fighter's
## guard. A head guard covers the head; a body guard covers the body and groin.
func is_blocking_from(from_pos: Vector3, zone: StringName = Moves.GUARD_HEAD) -> bool:
	if state != State.BLOCK:
		return false
	if (zone == Moves.GUARD_HEAD) != (guard_zone == Moves.GUARD_HEAD):
		return false
	var to := from_pos - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return true
	return get_facing().angle_to(to.normalized()) <= deg_to_rad(Moves.BLOCK_ARC * 0.5)


## Just parried: the next punch thrown is a counter.
func has_counter_ready() -> bool:
	return _counter_ready > 0.0


## In the recovery of an attack, where the next attack (or a dodge or counter) can chain.
func can_chain() -> bool:
	return state == State.ATTACK and _attack_t >= float(_move.get("active", 0.0))


## Valid for freeflow targeting and AI attention.
func can_be_targeted() -> bool:
	return is_inside_tree() and state != State.KO


## Whether an incoming hit would land right now.
func can_be_hit() -> bool:
	if team == Team.STAFF or state == State.KO or _invuln > 0.0:
		return false
	if state == State.DODGE and _state_t < Moves.DODGE_IFRAMES:
		return false
	return true


func can_be_grabbed() -> bool:
	return state in [State.IDLE, State.ATTACK, State.WINDUP, State.STAGGER, State.BLOCK,
			State.DOUBLED] \
		and held_by == null and holding == null and team != Team.STAFF


## Whether `other` is an enemy for targeting and AI. Bar staff are nobody's enemy.
func is_hostile_to(other: Fighter) -> bool:
	if other == null or other.team == Team.STAFF or team == Team.STAFF:
		return false
	return (team == Team.PLAYERS) != (other.team == Team.PLAYERS)


## Whether an attack from this fighter can physically land on `other`.
## Nobody hits the bar staff: attacks pass straight through them. With friendly fire on
## (GameData.friendly_fire, the host's setting) players' hits land on other players too.
func can_hit(other: Fighter) -> bool:
	if other == null or other == self:
		return false
	return is_hostile_to(other) or is_friendly_fire_on(other)


## Player-on-player hits are allowed by the friendly fire setting. Bar staff never count.
func is_friendly_fire_on(other: Fighter) -> bool:
	return GameData.friendly_fire and other != null and other != self \
		and team == Team.PLAYERS and other.team == Team.PLAYERS


## True while this fighter is winding up a telegraphed attack aimed at `defender`.
func is_counterable_by(defender: Fighter) -> bool:
	if state != State.WINDUP or not bool(_move.get("telegraph", false)):
		return false
	if target != null:
		return target == defender
	var to := defender.global_position - global_position
	to.y = 0.0
	return to.length() < 2.0 and get_facing().angle_to(to.normalized()) < deg_to_rad(60.0)


## Seconds left before a winding-up attack lands (for HUD counter prompts).
func windup_remaining() -> float:
	return _windup_left if state == State.WINDUP else 0.0


## How to defend the attack being wound up, as the action to press: "guard_head" (punches
## to the head: LB), "guard_body" (body shots: RB) or "dodge" (guard breakers: kicks,
## haymakers, shoves, batons). "" when not winding up.
func defend_hint() -> String:
	if state != State.WINDUP:
		return ""
	if bool(_move.get("guard_break", false)):
		return "dodge"
	return "guard_head" if attack_zone() == Moves.GUARD_HEAD else "guard_body"


## Where the move being wound up or thrown will land: &"head", &"body" or &"groin".
func attack_zone() -> StringName:
	return StringName(_move.get("zone", Moves.GUARD_HEAD)) if not _move.is_empty() \
		else Moves.GUARD_HEAD


## Slipping right now: head shots miss.
func is_slipping() -> bool:
	return _slip_t > 0.0


## World position of the head, for FX (blood, sounds) and UI.
func get_head_position() -> Vector3:
	var v := get_node_or_null(FighterVisual.NODE_NAME) as FighterVisual
	if v != null and v.rig != null:
		return v.head_position()
	var head := get_node_or_null("Head") as Node3D
	return head.global_position if head else global_position + Vector3.UP * 1.5


func get_facing() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func stamina_fraction() -> float:
	return clampf(stamina / maxf(max_stamina, 1.0), 0.0, 1.0)


## Running on fumes: soft punches, slow hands and feet, a guard that folds.
func is_gassed() -> bool:
	return stamina < max_stamina * Moves.GASSED


## Stood coiled, loading a power shot.
func is_charging() -> bool:
	return _charging


## How loaded the power shot being charged is (0..1).
func charge_fraction() -> float:
	return clampf(_charge_t / Moves.CHARGE_TIME, 0.0, 1.0) if _charging else 0.0


func hp_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


# --- Requests (call on this fighter's authority) -------------------------------------

## Start a move from Moves.DATA. With no target, soft-lock aiming picks the enemy in front.
## A target further than one short step out of reach isn't chased: the move whiffs.
## `bonus` multiplies damage (combos), up to 2.0; `combo_name` is shown by the HUD.
## While GRABBING, any attack becomes a knee to the held fighter.
## `hold`: the button is held down. A chargeable move (hooks, uppercuts) that's still held
## when its wind-up ends loads into a power shot until request_unleash().
func request_attack(move_id: StringName, target_fighter: Fighter = null, bonus := 1.0,
		combo_name := "", hold := false) -> void:
	_send(&"attack", [move_id, _path(target_fighter), bonus, combo_name, hold])


## Let go of a held punch: throw it now, with however much power it has loaded.
func request_unleash() -> void:
	_send(&"unleash", [])


## Raise (true) or drop (false) a guard: Moves.GUARD_HEAD covers head shots, GUARD_BODY
## body (and groin) shots, from the front, for chip damage. Raising the right one just
## before a punch lands parries it, and the next punch is a counter. Guard breakers
## (kicks, headbutts, haymakers) stagger a blocker: dodge those. Calling it again with the
## other zone while blocking switches guards.
func request_block(on: bool, zone: StringName = Moves.GUARD_HEAD) -> void:
	_send(&"block", [on, zone])


## Flick the head out of the way (right stick). `dir` is x right, y up (down ducks). For a
## moment head shots miss; slipping one just as it lands sets up a counter.
func request_slip(dir: Vector2) -> void:
	_send(&"slip", [dir])


## Grab `victim`, or the nearest enemy in front if null.
func request_grab(victim: Fighter = null) -> void:
	_send(&"grab", [_path(victim)])


func request_release() -> void:
	_send(&"release", [])


## Throw the held fighter in the direction we face.
func request_throw() -> void:
	_send(&"throw", [])


## Dodge in `dir` (world XZ). A zero vector steps backwards.
func request_dodge(dir: Vector3) -> void:
	_send(&"dodge", [dir])


## Call repeatedly while HELD to wriggle free (button mashing, or AI on a timer).
func request_struggle() -> void:
	_send(&"struggle", [])


# --- Host-only API -------------------------------------------------------------------

## Apply a hit. Host only; other peers ignore it. Required keys: attacker (Node or null),
## damage (float), direction (Vector3). Optional: move (String), position (Vector3),
## heavy, to_face, knockdown, ground (bool), stagger, poise, knockback (float), weapon (Node).
## Items and hazards can call this directly (darts, thrown bottles).
func take_hit(info: Dictionary) -> void:
	if not multiplayer.is_server() or not can_be_hit():
		return
	var attacker := info.get("attacker") as Fighter
	var heavy := bool(info.get("heavy", false))
	var dmg := float(info.get("damage", 0.0))
	var zone := StringName(info.get("zone", Moves.GUARD_HEAD))
	var from_pos: Vector3 = attacker.global_position if attacker != null \
		else global_position - (info.get("direction", Vector3.ZERO) as Vector3)
	if zone == Moves.GUARD_HEAD and _slip_t > 0.0 and attacker != null \
			and not bool(info.get("ground", false)) and not bool(info.get("clinch", false)) \
			and _can_slip():
		_server_slipped(info, attacker)
		return
	if is_blocking_from(from_pos, zone) and not bool(info.get("ground", false)):
		if _server_guard(info, attacker):
			return
	if state == State.HELD:
		dmg *= Moves.HELD_DAMAGE_MULT
		info["held"] = true
	elif is_down() and not bool(info.get("ground", false)):
		dmg *= Moves.GROUND_DAMAGE_MULT
	info["damage"] = dmg
	info["victim"] = self
	if not info.has("position"):
		info["position"] = global_position + Vector3.UP * 1.4
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	dir.y = 0.0
	dir = dir.normalized()
	info["direction"] = dir

	var new_hp := hp - dmg
	if zone != Moves.GUARD_HEAD and dmg > 0.0:
		# Body shots take the wind out of you.
		_server_drain(dmg * Moves.BODY_SHOT_DRAIN)
	var poise_hit := float(info.get("poise", 8.0)) / maxf(toughness, 0.1)
	if state == State.STAGGER or state == State.DOUBLED:
		poise_hit *= Moves.STAGGER_POISE_SCALE  # no stun-locking a man to the floor
	_poise -= poise_hit
	_poise_wait = Moves.POISE_REGEN_DELAY
	var tough := maxf(toughness, 0.1)
	var impulse := dir * float(info.get("knockback", 1.0)) / tough
	var broke_nose := bool(info.get("to_face", false)) and dmg >= Moves.NOSE_BREAK_DAMAGE \
		and not nose_broken
	var reaction := State.STAGGER
	var dur := maxf(float(info.get("stagger", 0.3)) / tough, 0.12)
	if new_hp <= 0.0:
		if can_be_knocked_out:
			new_hp = 0.0
			reaction = State.KO
		else:
			new_hp = 1.0
			reaction = State.DOWN
			dur = get_up_time
	elif state == State.CRAWL:
		reaction = State.CRAWL
	elif state == State.DOWN:
		reaction = State.DOWN
		dur = minf(_state_len - _state_t + 0.3, get_up_time)
	elif bool(info.get("knockdown", false)) or _poise <= 0.0:
		reaction = State.DOWN
		dur = get_up_time
		_poise = Moves.POISE * toughness
	elif bool(info.get("doubles", false)) and state != State.HELD:
		reaction = State.DOUBLED
		dur = Moves.DOUBLED_TIME / tough
	elif state == State.DOUBLED:
		reaction = State.DOUBLED  # still curled up holding it
		dur = _state_len - _state_t
	elif state == State.HELD:
		reaction = State.HELD  # flinch in their grip

	# Holds break: a holder who gets hit lets go; a held fighter who goes down is dropped.
	if holding != null:
		_server_release(_RELEASE_PLAIN)
	if held_by != null and reaction != State.HELD:
		held_by._server_release(_RELEASE_SILENT)
	if heavy and attacker != null and reaction == State.STAGGER:
		dur *= 1.25
	_rpc_react.rpc(reaction, dur, new_hp, impulse, _pack(info), broke_nose)


## Slipping can't happen while busy: only on your feet and free to move your head.
func _can_slip() -> bool:
	return state in [State.IDLE, State.BLOCK, State.ATTACK, State.DODGE] \
		or (state == State.WINDUP and not bool(_move.get("telegraph", false)))


## A head shot met a slipping head: it misses. Slipped right as it landed, it's a counter.
func _server_slipped(info: Dictionary, attacker: Fighter) -> void:
	info["victim"] = self
	info["damage"] = 0.0
	info["slipped"] = true
	info["heavy"] = false
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	dir.y = 0.0
	info["direction"] = dir.normalized()
	if not info.has("position"):
		info["position"] = global_position + Vector3.UP * 1.5
	if Moves.SLIP_WINDOW - _slip_t <= Moves.SLIP_COUNTER_WINDOW:
		# Slipped it at the last moment: they're overextended and you're set to counter.
		info["parried"] = true
		_counter_ready = Moves.COUNTER_WINDOW
		attacker._rpc_react.rpc(State.STAGGER, Moves.PARRY_STAGGER * 0.6, attacker.hp,
			attacker.get_facing() * 1.2, {}, false)
		_rpc_parried.rpc(_path(attacker))
	_rpc_react.rpc(state, _state_len - _state_t, hp, Vector3.ZERO, _pack(info), false)


## A hit met our guard. Returns true if the guard dealt with it (parried or blocked);
## false means it broke through and take_hit carries on with it (already adjusted).
func _server_guard(info: Dictionary, attacker: Fighter) -> bool:
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	dir.y = 0.0
	dir = dir.normalized()
	if bool(info.get("guard_break", false)):
		info["guard_broken"] = true
		info["stagger"] = Moves.GUARD_BREAK_STAGGER * maxf(toughness, 0.1)
		info["damage"] = float(info.get("damage", 0.0)) * 0.6
		Events.guard_broken.emit(self, attacker)
		return false
	info["victim"] = self
	info["direction"] = dir
	if not info.has("position"):
		info["position"] = global_position + Vector3.UP * 1.4
	if _state_t <= Moves.PARRY_WINDOW and attacker != null \
			and (parry_skill >= 1.0 or randf() < parry_skill):
		# Parried: no damage, the attacker reels, and our next punch is a counter.
		info["damage"] = 0.0
		info["parried"] = true
		_counter_ready = Moves.COUNTER_WINDOW
		attacker._rpc_react.rpc(State.STAGGER, Moves.PARRY_STAGGER, attacker.hp,
			-dir * 1.5, {}, false)
		_rpc_parried.rpc(_path(attacker))
		_rpc_react.rpc(State.BLOCK, 0.0, hp, Vector3.ZERO, _pack(info), false)
		return true
	var drain := float(info.get("guard_drain", float(info.get("damage", 0.0)) * 1.2))
	if stamina - drain <= 0.0:
		# Nothing left to hold it up with: the guard is smashed apart and they reel, open.
		_server_drain(stamina)
		info["guard_broken"] = true
		info["guard_crushed"] = true
		info["stagger"] = Moves.GUARD_CRUSH_STAGGER * maxf(toughness, 0.1)
		info["damage"] = float(info.get("damage", 0.0)) * 0.6
		Events.guard_broken.emit(self, attacker)
		return false
	_server_drain(drain)
	var chip := float(info.get("damage", 0.0)) * Moves.BLOCK_CHIP
	info["damage"] = chip
	info["blocked"] = true
	info["heavy"] = false
	var new_hp := maxf(hp - chip, 1.0)
	_rpc_react.rpc(State.BLOCK, 0.0, new_hp, dir * 1.2 / maxf(toughness, 0.1), _pack(info), false)
	return true


## Heal. Applies the difficulty's heal_multiplier for players. Host only.
func heal(amount: float) -> void:
	if not multiplayer.is_server() or state == State.KO or amount <= 0.0:
		return
	if team == Team.PLAYERS:
		amount *= float(GameData.difficulty()["heal_multiplier"])
	_rpc_vitals.rpc(minf(hp + amount, max_hp), amount)


## Bring a KO'd fighter back (co-op revive, M2). Host only.
func revive(hp_fraction_after := 0.3) -> void:
	if not multiplayer.is_server() or state != State.KO:
		return
	_rpc_revive.rpc(maxf(1.0, max_hp * hp_fraction_after))


## Equip a weapon on this peer. Workstream 5 calls this on every peer (host decides).
## Optional item methods: on_equipped(fighter), on_unequipped(fighter),
## modify_move(move: Dictionary) -> Dictionary (change damage, reach, sweep, heavy...),
## on_hit(info: Dictionary) (host only; durability and breaking).
func equip(item: Node) -> void:
	if weapon != null:
		unequip()
	weapon = item
	if item != null and item.has_method("on_equipped"):
		item.on_equipped(self)


func unequip() -> Node:
	var w := weapon
	weapon = null
	if w != null and w.has_method("on_unequipped"):
		w.on_unequipped(self)
	return w


# --- Networking plumbing -------------------------------------------------------------

func _send(action: StringName, args: Array) -> void:
	if not is_inside_tree():
		return
	if multiplayer.is_server():
		_server_action(action, args)
	else:
		_rpc_action.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_action(action: StringName, args: Array) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_server_action(action, args)


func _server_action(action: StringName, args: Array) -> void:
	match action:
		&"slip":
			if args.size() > 0 and args[0] is Vector2:
				_server_slip(args[0])
		&"attack":
			var bonus := clampf(float(args[2]), 0.5, 2.0) if args.size() > 2 else 1.0
			var cname := String(args[3]) if args.size() > 3 else ""
			var hold := bool(args[4]) if args.size() > 4 else false
			_server_attack(args[0], _fighter_at(args[1]), bonus, cname, hold)
		&"unleash":
			_server_unleash()
		&"block":
			var zone: StringName = StringName(args[1]) if args.size() > 1 else Moves.GUARD_HEAD
			if zone != Moves.GUARD_BODY:
				zone = Moves.GUARD_HEAD
			_server_block(bool(args[0]), zone)
		&"grab":
			_server_grab(_fighter_at(args[0]))
		&"release":
			if state == State.GRABBING:
				_server_release(_RELEASE_PLAIN)
		&"throw":
			_server_throw()
		&"dodge":
			_server_dodge(args[0])
		&"struggle":
			if state == State.HELD and held_by != null:
				held_by._server_add_escape(Moves.ESCAPE_PER_STRUGGLE)
		&"landed":
			_server_landed(float(args[0]))


func _sender_is_host() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == 1


func _path(n: Node) -> NodePath:
	return n.get_path() if n != null and n.is_inside_tree() else NodePath()


func _fighter_at(p: NodePath) -> Fighter:
	if p.is_empty():
		return null
	return get_node_or_null(p) as Fighter


func _pack(info: Dictionary) -> Dictionary:
	var out := {}
	for k in info:
		var v = info[k]
		out[k] = _path(v) if v is Node else v
	return out


func _unpack(info: Dictionary) -> Dictionary:
	var out := {}
	for k in info:
		var v = info[k]
		out[k] = get_node_or_null(v) if v is NodePath else v
	return out


# --- Host-side action handling ------------------------------------------------------

func _resolve_move(move_id: StringName) -> Dictionary:
	var m := Moves.get_move(move_id)
	if weapon != null and weapon.has_method("modify_move"):
		m = weapon.modify_move(m)
	if bool(m["telegraph"]):
		m["windup"] = float(GameData.difficulty()["telegraph_time"]) * float(m["windup_scale"]) \
			* Moves.ENEMY_WINDUP_SCALE
	return m


func _server_attack(move_id: StringName, tgt: Fighter, bonus := 1.0, combo_name := "",
		hold := false) -> void:
	if not Moves.has(move_id):
		push_warning("Unknown move %s" % move_id)
		return
	if state == State.GRABBING:
		if _knee_cd > 0.0 or holding == null:
			return
		_knee_cd = Moves.KNEE_COOLDOWN
		_rpc_start_move.rpc(&"knee", _path(holding))
		return
	if not can_attack():
		return
	var m := _resolve_move(move_id)
	if tgt == null and (bool(m["lunge"]) or bool(m["charge"])):
		# No stick aim here: only the man in front (passing the facing would count as aiming).
		tgt = Targeting.pick(self, Vector3.ZERO, Moves.LUNGE_RANGE, bool(m["ground"]))
	if _counter_ready > 0.0 and not bool(m["ground"]):
		bonus *= Moves.COUNTER_BONUS
		if combo_name == "":
			combo_name = "Counter"
		_counter_ready = 0.0
	# Too gassed to load one up: it just goes.
	hold = hold and bool(m["chargeable"]) and stamina >= float(m["stamina"]) * 2.0
	_rpc_start_move.rpc(move_id, _path(tgt), bonus, combo_name, hold)


## Throw the power shot being held, if there is one.
func _server_unleash() -> void:
	if state != State.WINDUP or not _hold_power:
		return
	_rpc_unleash.rpc(clampf(_charge_t / Moves.CHARGE_TIME, 0.0, 1.0) if _charging else 0.0)


## Take stamina off (blocks, body shots) and tell everyone. Host only.
func _server_drain(amount: float) -> void:
	if amount <= 0.0:
		return
	_rpc_stamina.rpc(maxf(stamina - amount, 0.0))


func _server_block(on: bool, zone: StringName) -> void:
	if on and (state == State.IDLE or can_chain()):
		_rpc_block.rpc(true, zone)
	elif on and state == State.BLOCK and zone != guard_zone:
		_rpc_block.rpc(true, zone)  # switch guards (the parry timing restarts)
	elif not on and state == State.BLOCK:
		_rpc_block.rpc(false, zone)


func _server_slip(dir: Vector2) -> void:
	if _slip_cd > 0.0 or dir.length() < 0.1 or not _can_slip():
		return
	_rpc_slip.rpc(dir.limit_length(1.0))


func _server_grab(victim: Fighter) -> void:
	if not can_act():
		return
	if victim == null:
		victim = Targeting.grab_candidate(self)
	if victim == null or not can_hit(victim) or not victim.can_be_grabbed():
		return
	if victim.global_position.distance_to(global_position) > Moves.GRAB_RANGE + 0.3:
		return
	# Some men are harder to get hold of. Soften them up first and it's easier.
	var resist := victim.hold_resist / maxf(grip, 0.1)
	if victim.state == State.STAGGER or victim.state == State.DOUBLED:
		resist *= 0.5
	if resist > 0.0 and randf() < resist:
		var away := global_position - victim.global_position
		away.y = 0.0
		_rpc_react.rpc(State.STAGGER, Moves.SHRUG_STAGGER, hp, away.normalized() * 2.5, {}, false)
		Events.grab_shrugged.emit(self, victim)
		return
	_rpc_grab.rpc(_path(victim))


func _server_release(mode: int) -> void:
	if holding == null:
		return
	_rpc_release.rpc(mode)


func _server_throw() -> void:
	if state != State.GRABBING or holding == null:
		return
	var victim := holding
	_server_release(_RELEASE_SILENT)
	var m := Moves.get_move(&"throw")
	var dir := get_facing()
	var knockback := float(m["knockback"])
	# Near a gallery edge and throwing towards it? Over they go.
	var ledge := Ledges.for_throw(get_tree(), victim.global_position, dir)
	if ledge != null:
		dir = Ledges.normal_of(ledge)
		knockback = Moves.LEDGE_THROW_SPEED * maxf(victim.toughness, 0.1)
	victim.take_hit({
		"attacker": self, "move": "throw", "damage": float(m["damage"]) * power,
		"direction": dir, "heavy": true, "knockdown": true,
		"knockback": knockback, "poise": 0.0,
	})
	if ledge != null and victim.state != State.KO:
		var railed := Ledges.has_railing(ledge)
		victim._rpc_over_edge.rpc(ledge.global_position, dir, railed)
		Events.fighter_thrown_off_ledge.emit(victim, self, railed)


func _server_dodge(dir: Vector3) -> void:
	if _dodge_cd > 0.0 or not (can_act() or can_chain() or state == State.WINDUP \
			or state == State.BLOCK):
		return
	_rpc_dodge.rpc(dir)


## The fighter's authority reports a landing; the host turns it into fall damage.
func _server_landed(height: float) -> void:
	if height < Moves.FALL_MIN_HEIGHT or height > Moves.MAX_FALL:
		return
	var dmg := (height - Moves.FALL_MIN_HEIGHT) * Moves.FALL_DAMAGE_PER_M
	_rpc_fell.rpc(height)
	take_hit({
		"attacker": null, "move": "fall", "damage": dmg, "direction": Vector3.ZERO,
		"position": global_position + Vector3.UP * 0.3, "heavy": true, "knockdown": true,
		"ground": true, "knockback": 0.0, "poise": 0.0,
	})


func _server_add_escape(amount: float) -> void:
	var resist := holding.hold_resist if holding != null else 0.0
	_escape += amount * (1.0 + resist * 2.0) / maxf(grip, 0.1)
	if _escape >= 1.0:
		_server_release(_RELEASE_PLAIN)


func _server_resolve_hit() -> void:
	var victims := _find_victims()
	var m := _move
	if state != State.GRABBING and float(m["damage"]) > 0.0 and not bool(m.get("charge", false)):
		_rpc_strike_result.rpc(not victims.is_empty())
	for v in victims:
		var to := v.global_position - global_position
		to.y = 0.0
		var dir := to.normalized() if to.length() > 0.01 else get_facing()
		var side := float(m.get("side", 0.0))
		if side != 0.0:
			# A hook comes round from the side: it knocks the head (and the body) sideways.
			var right := get_facing().cross(Vector3.UP)
			dir = (dir - right * side * 0.9).normalized()
		var zone := StringName(m.get("zone", Moves.GUARD_HEAD))
		var dmg := float(m["damage"]) * power * _bonus * _power
		if team != Team.PLAYERS and v.team == Team.PLAYERS:
			dmg *= float(GameData.difficulty()["enemy_damage"])
		if is_gassed():
			dmg *= Moves.GASSED_DAMAGE
		# Caught him recovering from his own punch (or his miss): a punish.
		var punish := v.state == State.ATTACK and v._attack_t > float(v._move.get("active", 0.0)) \
			and not bool(m["ground"])
		if punish:
			dmg *= Moves.PUNISH_BONUS
		var height := 1.45 if bool(m["to_face"]) else 1.1
		if zone == &"groin":
			height = 0.85
		var info := {
			"attacker": self, "victim": v, "move": String(m["id"]), "damage": dmg,
			"zone": zone, "side": side, "clinch": bool(m["clinch"]), "doubles": bool(m["doubles"]),
			"charge": bool(m["charge"]),
			"position": v.global_position + Vector3.UP * height,
			"direction": dir, "heavy": bool(m["heavy"]), "to_face": bool(m["to_face"]),
			"knockdown": bool(m["knockdown"]), "ground": bool(m["ground"]),
			"stagger": float(m["stagger"]), "poise": float(m["poise"]),
			"knockback": float(m["knockback"]), "weapon": weapon,
			"guard_break": bool(m.get("guard_break", false)),
			"guard_drain": float(m.get("guard_drain", 0.0)) * _power,
		}
		if _power > 1.0:
			info["power"] = _power_frac
			info["stagger"] = float(info["stagger"]) * _power
			info["poise"] = float(info["poise"]) * _power
			info["knockback"] = float(info["knockback"]) * (1.0 + (_power - 1.0) * 0.6)
			if _power_frac >= 0.5:
				info["heavy"] = true
		if punish:
			info["punish"] = true
			info["heavy"] = true
			info["stagger"] = float(info["stagger"]) * 1.3
		# A "clean" connect (FX sprays blood off the face): a counter, a combo ender, or a
		# face shot on someone reeling or held.
		info["clean"] = bool(m["to_face"]) and (_bonus >= 1.3 \
			or v.state == State.STAGGER or v.state == State.HELD)
		if _bonus > 1.0:
			info["stagger"] = float(info["stagger"]) * _bonus
			info["poise"] = float(info["poise"]) * _bonus
			info["combo"] = _combo_name
			if _bonus >= 1.3:
				info["heavy"] = true
		v.take_hit(info)
		if weapon != null and weapon.has_method("on_hit"):
			weapon.on_hit(info)
	if not victims.is_empty() and float(m["self_damage"]) > 0.0:
		_rpc_vitals.rpc(maxf(1.0, hp - float(m["self_damage"])), 0.0)


func _find_victims() -> Array[Fighter]:
	var m := _move
	var out: Array[Fighter] = []
	if float(m["damage"]) <= 0.0:
		return out
	var reach := float(m["reach"])
	if bool(m.get("charge", false)):
		reach = Moves.CHARGE_HIT_RANGE
	if state == State.GRABBING:
		if holding != null:
			out.append(holding)
		return out
	# The man you aimed at only gets hit if he's still there: in reach and in front of you.
	# Step back, slip off to the side or duck round, and it misses.
	if not bool(m["sweep"]) and _valid_victim(target, m) \
			and _flat_dist(target) <= reach + Moves.REACH_SLACK and _in_arc(target, m):
		out.append(target)
		return out
	var fwd := get_facing()
	var half := deg_to_rad(float(m["arc"]) * 0.5)
	var best: Fighter = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(GROUP):
		var f := node as Fighter
		if not _valid_victim(f, m):
			continue
		var to := f.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach or (d > 0.05 and fwd.angle_to(to / d) > half):
			continue
		if bool(m["sweep"]):
			out.append(f)
		elif d < best_d:
			best_d = d
			best = f
	if best != null:
		out.append(best)
	return out


func _in_arc(f: Fighter, m: Dictionary) -> bool:
	var to := f.global_position - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return true
	return get_facing().angle_to(to.normalized()) <= deg_to_rad(float(m["arc"]) * 0.5)


func _valid_victim(f: Fighter, m: Dictionary) -> bool:
	if f == null or f == self or not can_hit(f) or not f.can_be_hit():
		return false
	var on_floor := f.state == State.DOWN or f.state == State.CRAWL
	return on_floor == bool(m["ground"])


func _flat_dist(f: Fighter) -> float:
	var to := f.global_position - global_position
	to.y = 0.0
	return to.length()


# --- Replicated results (run on every peer) ------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _rpc_start_move(move_id: StringName, target_path: NodePath, bonus := 1.0,
		combo_name := "", hold := false) -> void:
	if not _sender_is_host():
		return
	var tgt := _fighter_at(target_path)
	var m := _resolve_move(move_id)
	_spend(float(m["stamina"]))
	if is_gassed():
		m["windup"] = float(m["windup"]) * Moves.GASSED_WINDUP
	_power = 1.0
	_power_frac = 0.0
	if combo_name != "" and m.has("knockdown"):
		for c in Moves.COMBOS:
			if c["name"] == combo_name and bool(c.get("knockdown", false)):
				m["knockdown"] = true
	_bonus = bonus
	_combo_name = combo_name
	_combat_t = Moves.STANCE_HOLD
	if combo_name != "":
		Events.combo_performed.emit(self, combo_name)
	if state == State.GRABBING:  # knee: no state change, resolves at once
		_move = m
		move_started.emit(move_id)
		if multiplayer.is_server():
			_server_resolve_hit()
		return
	_move = m
	current_move = move_id
	target = tgt
	_windup_left = float(m["windup"])
	_lunge_t = 0.0
	_attack_t = 0.0
	_charge_hit = false
	_hold_power = hold
	_charging = false
	_charge_t = 0.0
	# Only step in when the target is a short step out of reach; never chase across the room.
	_lunge_ok = tgt != null and bool(m["lunge"]) \
		and _flat_dist(tgt) - float(m["reach"]) * 0.8 <= Moves.MAX_LUNGE_STEP
	_enter(State.WINDUP, float(m["windup"]))
	current_move = move_id
	target = tgt
	# Emitted once the windup is set, so the visual can pace the wind-up to windup_remaining().
	move_started.emit(move_id)
	if bool(m["telegraph"]):
		Events.attack_telegraphed.emit(self, tgt, _windup_left)


@rpc("any_peer", "call_local", "reliable")
func _rpc_react(new_state: State, duration: float, new_hp: float, impulse: Vector3,
		packed: Dictionary, broke_nose: bool) -> void:
	if not _sender_is_host():
		return
	hp = new_hp
	_impulse += impulse
	if not packed.is_empty():
		var info := _unpack(packed)
		_flash = 1.0
		hit_taken.emit(info)
		Events.hit_landed.emit(info)
		var attacker := info.get("attacker") as Fighter
		if attacker != null:
			attacker.hit_dealt.emit(info)
	if broke_nose:
		nose_broken = true
		Events.nose_broken.emit(self)
	var was := state
	if not packed.is_empty():
		_combat_t = Moves.STANCE_HOLD
	if new_state == was and (was == State.HELD or was == State.CRAWL or was == State.BLOCK \
			or was == State.DOUBLED or was == State.IDLE or was == State.DODGE):
		return
	if new_state == State.DOWN and was == State.DOWN:
		_state_len = _state_t + duration
		return
	_enter(new_state, duration)
	if new_state == State.DOWN:
		Events.fighter_knocked_down.emit(self)


@rpc("any_peer", "call_local", "reliable")
func _rpc_block(on: bool, zone: StringName = Moves.GUARD_HEAD) -> void:
	if not _sender_is_host():
		return
	_combat_t = maxf(_combat_t, 1.0)
	guard_zone = zone
	if on and state == State.BLOCK:
		_state_t = 0.0  # a switched guard is a freshly raised one
		return
	_enter(State.BLOCK if on else State.IDLE, 0.0)


@rpc("any_peer", "call_local", "reliable")
func _rpc_slip(dir: Vector2) -> void:
	if not _sender_is_host():
		return
	_slip_t = Moves.SLIP_WINDOW
	_slip_cd = Moves.SLIP_WINDOW + Moves.SLIP_COOLDOWN
	slip_dir = dir
	_combat_t = maxf(_combat_t, 1.0)
	slipped.emit(dir)


## A strike connected (it stops dead on them) or missed (the weight carries on through
## thin air and you're a beat slower recovering).
@rpc("any_peer", "call_local", "reliable")
func _rpc_strike_result(hit: bool) -> void:
	if not _sender_is_host():
		return
	if hit:
		_impulse = _impulse.limit_length(0.3)
		return
	if state == State.ATTACK:
		_state_len += Moves.WHIFF_RECOVER
	_spend(float(_move.get("stamina", 0.0)) * Moves.WHIFF_STAMINA)
	_impulse += get_facing() * Moves.WHIFF_STUMBLE
	Events.attack_whiffed.emit(self, current_move)


@rpc("any_peer", "call_local", "reliable")
func _rpc_stamina(value: float) -> void:
	if not _sender_is_host():
		return
	stamina = clampf(value, 0.0, max_stamina)
	_stamina_wait = Moves.STAMINA_REGEN_DELAY


## The held punch goes, loaded to `frac` (0 = a normal punch).
@rpc("any_peer", "call_local", "reliable")
func _rpc_unleash(frac: float) -> void:
	if not _sender_is_host():
		return
	var was_charging := _charging
	_hold_power = false
	_charging = false
	if frac >= Moves.POWER_MIN and state == State.WINDUP:
		_power_frac = frac
		_power = lerpf(1.0, Moves.POWER_MAX, frac)
		_spend(float(_move.get("stamina", 0.0)) * Moves.POWER_STAMINA * frac)
		_move["heavy"] = true if frac >= 0.5 else bool(_move["heavy"])
		if frac >= 0.95:
			_move["guard_break"] = true  # everything behind it: no guard holds that
	if was_charging:
		power_charging.emit(false)


## Spend stamina on a strike (runs on every peer, so the bars agree).
func _spend(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(stamina - amount, 0.0)
	_stamina_wait = Moves.STAMINA_REGEN_DELAY


@rpc("any_peer", "call_local", "reliable")
func _rpc_parried(attacker_path: NodePath) -> void:
	if not _sender_is_host():
		return
	_counter_ready = Moves.COUNTER_WINDOW
	var a := _fighter_at(attacker_path)
	Events.attack_countered.emit(self, a)


@rpc("any_peer", "call_local", "reliable")
func _rpc_vitals(new_hp: float, healed: float) -> void:
	if not _sender_is_host():
		return
	hp = new_hp
	if healed > 0.0 and team == Team.PLAYERS:
		Events.player_healed.emit(self, healed)
	if state == State.CRAWL and hp > max_hp * crawl_fraction:
		_enter(State.IDLE, 0.0)
		Events.fighter_got_up.emit(self)


@rpc("any_peer", "call_local", "reliable")
func _rpc_revive(new_hp: float) -> void:
	if not _sender_is_host():
		return
	hp = new_hp
	_enter(State.DOWN, get_up_time)


@rpc("any_peer", "call_local", "reliable")
func _rpc_grab(victim_path: NodePath) -> void:
	if not _sender_is_host():
		return
	var victim := _fighter_at(victim_path)
	if victim == null:
		return
	_enter(State.GRABBING, 0.0)
	holding = victim
	victim.held_by = self
	victim._enter(State.HELD, 0.0)
	_hold_left = Moves.HOLD_TIME * grip
	_escape = 0.0
	_knee_cd = 0.0
	add_collision_exception_with(victim)
	victim.add_collision_exception_with(self)
	Events.grab_started.emit(self, victim)


@rpc("any_peer", "call_local", "reliable")
func _rpc_release(mode: int) -> void:
	if not _sender_is_host():
		return
	var victim := holding
	holding = null
	if state == State.GRABBING:
		_enter(State.IDLE, 0.0)
	if victim == null:
		return
	remove_collision_exception_with(victim)
	victim.remove_collision_exception_with(self)
	if victim.held_by == self:
		victim.held_by = null
	if victim.state == State.HELD:
		if mode == _RELEASE_PLAIN:
			victim._enter(State.STAGGER, 0.35)
			victim._impulse += get_facing() * 2.5
		else:
			victim._enter(State.IDLE, 0.0)
	Events.grab_ended.emit(self, victim)


## Send this fighter over a ledge: they keep their momentum until clear of the edge. With a
## railing, they're lifted and pass through the rail (world collision off) on the way.
@rpc("any_peer", "call_local", "reliable")
func _rpc_over_edge(ledge_pos: Vector3, normal: Vector3, railing: bool) -> void:
	if not _sender_is_host():
		return
	_vault_normal = normal
	_vault_origin = ledge_pos
	_launch_y = Moves.RAIL_VAULT_LIFT if railing else 1.5
	if _vault_t < 0.0:
		_saved_mask = collision_mask
		if railing:
			collision_mask &= ~1
	_vault_t = 0.0


@rpc("any_peer", "call_local", "reliable")
func _rpc_fell(height: float) -> void:
	if not _sender_is_host():
		return
	Events.fighter_fell.emit(self, height)


@rpc("any_peer", "call_local", "reliable")
func _rpc_dodge(dir: Vector3) -> void:
	if not _sender_is_host():
		return
	dir.y = 0.0
	_dodge_dir = dir.normalized() if dir.length() > 0.1 else -get_facing()
	_dodge_cd = Moves.DODGE_TIME + Moves.DODGE_COOLDOWN
	_enter(State.DODGE, Moves.DODGE_TIME)


# --- State machine -------------------------------------------------------------------

func _enter(new_state: State, duration: float) -> void:
	var old := state
	_state_t = 0.0
	_state_len = duration
	if old == new_state:
		return
	state = new_state
	if new_state != State.WINDUP and new_state != State.ATTACK:
		current_move = &""
	if new_state != State.WINDUP:
		# Hit (or let go) while loading a power shot: it's gone.
		_hold_power = false
		if _charging:
			_charging = false
			power_charging.emit(false)
	if old == State.GRABBING and holding != null:
		# Safety net: the host always releases explicitly, but never leave a dangling hold.
		if holding.held_by == self:
			holding.held_by = null
		holding = null
	if old == State.HELD and new_state != State.HELD:
		held_by = null
	if new_state == State.KO:
		collision_layer = 0
		if not _ko_announced:
			_ko_announced = true
			Events.fighter_knocked_out.emit(self)
	elif old == State.KO:
		collision_layer = _saved_layer
		_ko_announced = false
	if new_state == State.CRAWL:
		Events.fighter_crawling.emit(self)
	state_changed.emit(old, new_state)


func _physics_process(delta: float) -> void:
	_tick_state(delta)
	if is_multiplayer_authority():
		_tick_motion(delta)
	_update_placeholder(delta)


func _tick_state(delta: float) -> void:
	_state_t += delta
	_invuln = maxf(_invuln - delta, 0.0)
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_knee_cd = maxf(_knee_cd - delta, 0.0)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_counter_ready = maxf(_counter_ready - delta, 0.0)
	_slip_t = maxf(_slip_t - delta, 0.0)
	_slip_cd = maxf(_slip_cd - delta, 0.0)
	if _slip_t <= 0.0:
		slip_dir = slip_dir.move_toward(Vector2.ZERO, delta * 4.0)
	_combat_t = maxf(_combat_t - delta, 0.0)
	_update_stance()
	_poise_wait -= delta
	if _poise_wait <= 0.0:
		_poise = minf(_poise + Moves.POISE_REGEN * delta, Moves.POISE * toughness)
	_stamina_wait -= delta
	if _stamina_wait <= 0.0 and state != State.WINDUP and state != State.ATTACK:
		var regen := Moves.STAMINA_REGEN
		if state == State.BLOCK:
			regen *= Moves.STAMINA_BLOCK_REGEN
		stamina = minf(stamina + regen * delta, max_stamina)
	match state:
		State.WINDUP:
			_lunge_t += delta
			if not _is_lunging():
				_windup_left -= delta
			if _windup_left <= 0.0 and _hold_power:
				# Still holding the button: coil up and load the power shot.
				if not _charging:
					_charging = true
					_charge_t = 0.0
					power_charging.emit(true)
				_charge_t += delta
				if multiplayer.is_server() and _charge_t >= Moves.CHARGE_TIME + Moves.CHARGE_HOLD:
					_server_unleash()
			elif _windup_left <= 0.0:
				_attack_t = 0.0
				_enter(State.ATTACK, float(_move["active"]) + float(_move["recover"]))
				# Put your weight into it: the strike carries you a little way forward.
				if bool(_move["lunge"]) and not bool(_move["ground"]):
					_impulse += get_facing() * Moves.FOLLOW_THROUGH \
						* (1.4 if bool(_move["heavy"]) else 1.0)
				# A shoulder charge hits whoever it runs into on the way, not here.
				if multiplayer.is_server() and not bool(_move["charge"]):
					_server_resolve_hit()
		State.ATTACK:
			_attack_t += delta
			if bool(_move.get("charge", false)) and not _charge_hit and multiplayer.is_server() \
					and _attack_t <= float(_move["active"]) + 0.05:
				if not _find_victims().is_empty():
					_charge_hit = true
					_server_resolve_hit()
			if _state_t >= _state_len:
				_enter(State.IDLE, 0.0)
		State.STAGGER, State.DODGE:
			if _state_t >= _state_len:
				_enter(State.IDLE, 0.0)
		State.DOWN, State.DOUBLED:
			if _state_t >= _state_len:
				_get_up()
		State.GRABBING:
			if multiplayer.is_server():
				_hold_left -= delta
				if _hold_left <= 0.0 or holding == null or holding.state != State.HELD:
					_server_release(_RELEASE_PLAIN)
		State.HELD:
			if held_by == null or not is_instance_valid(held_by):
				held_by = null
				_enter(State.IDLE, 0.0)


func _update_stance() -> void:
	var tgt: Fighter = null
	var on := _combat_t > 0.0 or state == State.BLOCK
	if not is_down() and state != State.HELD and state != State.GRABBING:
		tgt = _nearest_active_foe()
		if team == Team.PLAYERS and tgt != null:
			on = true
	else:
		on = false
	stance_target = tgt if on else null
	if on != in_stance:
		in_stance = on
		stance_changed.emit(on)


## The enemy within ENGAGE_RANGE who is up for a fight (recently in an exchange, or
## winding up, attacking or blocking) that we're most squared up to: near and in front,
## and sticky, so a punter wandering up at your shoulder doesn't spin you round.
func _nearest_active_foe() -> Fighter:
	var best: Fighter = null
	var best_score := INF
	var fwd := get_facing()
	for node in get_tree().get_nodes_in_group(GROUP):
		var f := node as Fighter
		if f == null or f == self or not is_hostile_to(f) or f.is_down():
			continue
		if f._combat_t <= 0.0 and not (f.state in [State.WINDUP, State.ATTACK, State.BLOCK]):
			continue
		var d := _flat_dist(f)
		if d > Moves.ENGAGE_RANGE:
			continue
		var to := f.global_position - global_position
		to.y = 0.0
		var angle := rad_to_deg(fwd.angle_to(to.normalized())) if to.length() > 0.01 else 0.0
		var score := d + angle / 60.0
		if f == stance_target:
			score -= 1.0
		if f.state == State.WINDUP and f.target == self:
			score -= 0.5  # the one about to hit you
		if score < best_score:
			best_score = score
			best = f
	return best


func _get_up() -> void:
	_poise = Moves.POISE * toughness
	if can_be_knocked_out and hp <= max_hp * crawl_fraction:
		_enter(State.CRAWL, 0.0)
	else:
		_invuln = 0.4
		_enter(State.IDLE, 0.0)
		Events.fighter_got_up.emit(self)


func _is_lunging() -> bool:
	if not _lunge_ok or target == null or not is_instance_valid(target):
		return false
	if _lunge_t >= Moves.MAX_LUNGE_TIME or not target.can_be_targeted():
		return false
	return _flat_dist(target) > float(_move["reach"]) * 0.8


func _tick_motion(delta: float) -> void:
	var v := Vector3.ZERO
	var walking := false
	match state:
		State.IDLE, State.BLOCK:
			var scale := 1.0
			if state == State.BLOCK:
				scale = Moves.BLOCK_MOVE_SCALE
			elif in_stance:
				scale = Moves.STANCE_MOVE_SCALE
			# Weight: footwork speeds up and slows down over a moment instead of snapping.
			if is_gassed():
				scale *= Moves.GASSED_SPEED
			var want := move_input.limit_length(1.0) * move_speed * scale
			var rate := Moves.ACCEL if want.length() > _walk_vel.length() else Moves.DECEL
			_walk_vel = _walk_vel.move_toward(want, rate * delta)
			v = _walk_vel
			walking = true
			if stance_target != null and is_instance_valid(stance_target):
				# Footwork: keep squared up to the foe and move around them.
				var to_foe := stance_target.global_position - global_position
				to_foe.y = 0.0
				_face(to_foe, delta, 10.0)
			else:
				_face(move_input, delta, 12.0)
		State.GRABBING:
			v = move_input.limit_length(1.0) * move_speed * Moves.GRAB_MOVE_SCALE
			_face(move_input, delta, 5.0)
		State.CRAWL:
			v = move_input.limit_length(1.0) * Moves.CRAWL_SPEED
			_face(move_input, delta, 4.0)
		State.WINDUP, State.ATTACK:
			if target != null and is_instance_valid(target) and target.can_be_targeted():
				var to := target.global_position - global_position
				to.y = 0.0
				_face(to, delta, 25.0)
				if state == State.WINDUP and _is_lunging():
					var gap := to.length() - float(_move["reach"]) * 0.75
					v = to.normalized() * minf(Moves.LUNGE_SPEED, gap / maxf(delta, 0.001))
			if state == State.ATTACK and bool(_move.get("charge", false)) \
					and _attack_t <= float(_move["active"]) and not _charge_hit:
				# Shoulder down, driving through: full speed until we hit someone.
				v = get_facing() * Moves.CHARGE_SPEED
		State.DODGE:
			v = _dodge_dir * Moves.DODGE_SPEED * (1.0 - 0.6 * _state_t / maxf(_state_len, 0.01))
		State.HELD:
			if held_by != null and is_instance_valid(held_by):
				var fwd := held_by.get_facing()
				global_position = held_by.global_position + fwd * Moves.HOLD_DISTANCE
				_face(fwd, delta, 30.0)
			velocity = Vector3.ZERO
			_impulse = Vector3.ZERO
			_walk_vel = Vector3.ZERO
			return
	if not walking:
		# Carry a little of the walk into the next move, then let it bleed off.
		_walk_vel = _walk_vel.move_toward(Vector3.ZERO, Moves.DECEL * delta)
		if state == State.WINDUP or state == State.ATTACK:
			v += _walk_vel * 0.5
	v += _impulse
	# A body sailing off a ledge keeps its momentum instead of skidding to a stop.
	var drag := 14.0
	if _vault_t >= 0.0 or not is_on_floor():
		drag = 2.0
	elif state == State.STAGGER:
		drag = Moves.STAGGER_DRAG  # a big hit makes you stumble back, not stop dead
	_impulse = _impulse.move_toward(Vector3.ZERO, drag * delta)
	velocity.x = v.x
	velocity.z = v.z
	if _launch_y > 0.0:
		velocity.y = _launch_y
		_launch_y = 0.0
	else:
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	var asked := velocity
	move_and_slide()
	if _impacts != null:
		_impacts.after_move(delta, asked)
	_tick_vault(delta)
	_track_fall()


func _tick_vault(delta: float) -> void:
	if _vault_t < 0.0:
		return
	_vault_t += delta
	var past := (global_position - _vault_origin).dot(_vault_normal)
	if past > 0.7 or _vault_t > 1.0:
		collision_mask = _saved_mask
		_vault_t = -1.0


## Runs on the authority: report how far we fell when we land.
func _track_fall() -> void:
	if not is_on_floor():
		if not _airborne:
			_airborne = true
			_fall_peak = global_position.y
		_fall_peak = maxf(_fall_peak, global_position.y)
	elif _airborne:
		_airborne = false
		var drop := _fall_peak - global_position.y
		if drop >= Moves.FALL_MIN_HEIGHT:
			_send(&"landed", [drop])


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.1:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(rate * delta, 0.0, 1.0))


# --- Placeholder visuals -------------------------------------------------------------

func _update_placeholder(_delta: float) -> void:
	# Dressed in a CharacterRig: the capsule and its grey "Facing" nose box stay hidden.
	# (Re-showing the nose here was the grey box hovering in front of everyone's face.)
	if get_node_or_null(FighterVisual.NODE_NAME) != null:
		return
	var body := get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var lying := state == State.DOWN or state == State.CRAWL or state == State.KO
	body.rotation.x = -PI * 0.5 if lying else 0.0
	body.position.y = 0.3 if lying else 0.875
	var nose := get_node_or_null("Facing") as Node3D
	if nose != null:
		nose.visible = not lying
	var mat := body.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		body.material_override = mat
		mat.set_meta("base", _team_colour())
	var base: Color = mat.get_meta("base", _team_colour())
	var c := base
	if state == State.KO:
		c = base.darkened(0.6)
	elif state == State.WINDUP and bool(_move.get("telegraph", false)):
		c = base.lerp(Color(1.0, 0.85, 0.1), 0.7)  # the tell: flash yellow
	elif state == State.HELD:
		c = base.lerp(Color(0.6, 0.3, 1.0), 0.4)
	mat.albedo_color = c.lerp(Color(1, 0.1, 0.1), _flash)


func _team_colour() -> Color:
	match team:
		Team.PLAYERS:
			return Color("6f8f4e")
		Team.POLICE:
			return Color("1f2d5c")
		Team.STAFF:
			return Color("d9d2c0")
	return Color("b9824f")
