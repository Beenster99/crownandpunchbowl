class_name FighterVisual
extends Node3D
## Puts a CharacterRig on a Fighter and drives it from the Fighter's signals, replacing
## the capsule placeholder. Runs on every peer: it only reads replicated state (state,
## velocity, hp) and the combat signals that already fire everywhere, so nothing extra
## is synced.
##
## Players get their farmer's look. NPCs get a look from their kind, seeded by the number
## in their node name (N12 -> 12) so every peer builds the same person.
##
## Usage: FighterVisual.attach(fighter). Fighter does this itself in _ready().

const NODE_NAME := "Visual"

var fighter: Fighter
var rig: CharacterRig
var lean: HitLean
## Snaps the head back (or round, from a hook) when a punch lands. Null without a skeleton.
var snap: HeadSnap
var _last_state := -1


static func attach(f: Fighter) -> FighterVisual:
	if f.has_node(NODE_NAME):
		return f.get_node(NODE_NAME)
	var v := FighterVisual.new()
	v.name = NODE_NAME
	v.fighter = f
	f.add_child(v)
	return v


static func look_for(f: Fighter) -> CharacterLook:
	if "farmer" in f and f.get("farmer") is Dictionary and not (f.get("farmer") as Dictionary).is_empty():
		return CharacterLooks.farmer(String(f.get("farmer")["id"]))
	var seed := String(f.name).trim_prefix("N").to_int()
	var kind := String(f.get("kind")) if "kind" in f else ""
	match kind:
		"staff":
			return CharacterLooks.staff("barwoman" if seed % 3 == 0 else "barman", seed)
		"police":
			return CharacterLooks.police("sergeant" if seed % 4 == 0 else "constable", seed)
		"second_homer":
			return CharacterLooks.punter("second_homer_gilet" if seed % 2 == 0 else "second_homer_chinos", seed)
		"local", "rugby_lad", "rambler":
			return CharacterLooks.punter(kind, seed)
	match f.team:
		Fighter.Team.PLAYERS:
			return CharacterLooks.farmer(String(GameData.FARMERS[0]["id"]))
		Fighter.Team.POLICE:
			return CharacterLooks.police("constable", seed)
		Fighter.Team.STAFF:
			return CharacterLooks.staff("barman", seed)
	return CharacterLooks.punter("local", seed)


func _ready() -> void:
	if fighter == null:
		fighter = get_parent() as Fighter
	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.look = look_for(fighter)
	rig.look_seed = String(fighter.name).trim_prefix("N").to_int()
	# Before add_child, so the rig starts in the right idle.
	rig.staff = fighter.team == Fighter.Team.STAFF or String(fighter.get("kind") if "kind" in fighter else "") == "staff"
	add_child(rig)
	var body := fighter.get_node_or_null("Body") as Node3D
	if body:
		body.visible = false  # kept: hands.gd and npc.gd still read it
	var facing := fighter.get_node_or_null("Facing")
	if facing:
		facing.queue_free()  # the grey placeholder nose; it floated in front of the face
	fighter.state_changed.connect(_on_state_changed)
	fighter.move_started.connect(_on_move_started)
	fighter.hit_taken.connect(_on_hit_taken)
	fighter.slipped.connect(_on_slipped)
	lean = HitLean.new()
	lean.name = "HitLean"
	lean.setup(fighter, rig)
	add_child(lean)
	# The characters' RigReactor snaps the head itself once it lands; don't double it.
	if rig.skeleton != null and not ResourceLoader.exists("res://scripts/actors/rig_reactor.gd"):
		snap = HeadSnap.new()
		snap.name = "HeadSnap"
		snap.setup(fighter, rig)
		rig.skeleton.add_child(snap)
	Events.nose_broken.connect(_on_nose_broken)
	Events.attack_countered.connect(_on_countered)


func _process(_delta: float) -> void:
	if fighter == null or rig == null:
		return
	var v := fighter.velocity
	rig.set_move_speed(Vector2(v.x, v.z).length())
	# Clients see `state` arrive through the state synchroniser, which doesn't fire
	# state_changed; catch those changes here.
	if int(fighter.state) != _last_state:
		_play_state(fighter.state)
	if fighter.max_hp > 0.0:
		rig.set_blood(clampf(1.0 - fighter.hp / fighter.max_hp, 0.0, 1.0) * 1.1 - 0.1)
	rig.set_guard(_wants_guard())
	# Which guard is up (LB head, RB body), and where the head is (right stick, or a slip).
	if rig.has_method("set_guard_zone"):
		var zone: StringName = fighter.guard_zone if fighter.state == Fighter.State.BLOCK else &""
		rig.call("set_guard_zone", zone)
	if rig.has_method("set_head_bob"):
		var bob: Vector2 = fighter.slip_dir
		if "head_bob" in fighter and fighter.is_multiplayer_authority():
			bob = fighter.get("head_bob")
		# The rig's y is +down (duck); ours is +up.
		rig.call("set_head_bob", Vector2(bob.x, -bob.y) if _can_bob() else Vector2.ZERO)
	var partner: Variant = fighter.get("chatting_with") if "chatting_with" in fighter else null
	rig.set_talking(partner != null and is_instance_valid(partner))


## Calm people stand relaxed (hands down, pint, chatting); the fists only come up when
## there's trouble: the fighter is in a fighting stance (Fighter.in_stance, which every
## peer works out from the combat RPCs), or an NPC's AI mood is past CALM. Staff never
## square up.
func _wants_guard() -> bool:
	if rig.staff:
		return false
	if bool(fighter.get("in_stance")):
		return true
	return "mood" in fighter and int(fighter.get("mood")) != 0  # Npc.Mood.CALM



func _can_bob() -> bool:
	return not fighter.is_down() and fighter.state != Fighter.State.HELD \
		and fighter.state != Fighter.State.DOUBLED


func head_position() -> Vector3:
	var head := rig.get_socket(&"head") if rig else null
	return head.global_position if head else global_position + Vector3.UP * 1.5


func hand_socket() -> Node3D:
	return rig.get_socket(&"hand_r") if rig else null


func _play_state(s: int) -> void:
	_last_state = s
	var key := String(Fighter.State.keys()[s]).to_lower()
	# Attacks are animated from move_started, which knows which move it is. A punch being
	# lined up holds its loaded pose until the strike comes out.
	if key == "attack":
		rig.release_strike()
		return
	if key == "windup":
		return
	if key == "stagger" and rig.current in [&"hit_front", &"hit_back", &"hit_left", &"hit_right"]:
		return
	if key == "doubled":
		# Kicked in the groin: down on all fours, holding it.
		if rig.has_method("play_hit") and rig.get_method_argument_count(&"play_hit") >= 4:
			rig.call("play_hit", true, true, Vector3.ZERO, &"groin")
		else:
			rig.play_state("stagger")
		return
	if key == "dodge" and rig.has_method("play_dodge"):
		rig.call("play_dodge", fighter.velocity if fighter.velocity.length() > 0.5 \
			else -fighter.get_facing())
		return
	rig.play_state(key)


func _on_state_changed(_old: Fighter.State, new_state: Fighter.State) -> void:
	_play_state(new_state)


## Body shots are the same punches thrown low: "body_hook" plays "hook" at the body.
static func split_move(move_id: StringName) -> Array:
	var m := String(move_id)
	if m.begins_with("body_"):
		return [m.trim_prefix("body_"), &"body"]
	return [m, &"head"]


## Stand-ins for new moves on a rig that doesn't have their animations yet.
const MOVE_FALLBACKS := {"body_jab": "jab", "body_hook": "hook", "body_uppercut": "uppercut",
	"body_swing": "swing", "groin_kick": "kick", "clinch_knee": "kick",
	"shoulder_charge": "headbutt"}


func _on_move_started(move_id: StringName) -> void:
	var parts := split_move(move_id)
	var zoned := rig.get_method_argument_count(&"play_move") >= 2
	var move: String = parts[0] if zoned else String(move_id)
	if not CharacterRig.MOVE_ANIMS.has(move) and MOVE_FALLBACKS.has(move) and not zoned:
		move = MOVE_FALLBACKS[move]
	# A wind-up long enough to see is played as a visible load-up, held until the hit.
	if fighter.state == Fighter.State.WINDUP and fighter.windup_remaining() >= 0.1:
		rig.play_windup(move, fighter.windup_remaining())
	elif zoned:
		rig.call("play_move", move, parts[1])
	else:
		rig.play_move(move)


func _on_hit_taken(info: Dictionary) -> void:
	if bool(info.get("slipped", false)):
		return  # slipped it: the head was already moving out of the way
	if fighter.is_down() or bool(info.get("blocked", false)) or bool(info.get("parried", false)):
		return  # a hit taken on the guard keeps the block pose
	if fighter.state == Fighter.State.DOUBLED:
		return  # curled up on the floor; the groin animation holds
	if bool(info.get("clinch", false)) and rig.has_method("play_clinched"):
		rig.call("play_clinched")
		return
	var from_front := true
	var dir := Vector3.ZERO
	var a := info.get("attacker") as Node3D
	if a != null and is_instance_valid(a):
		var to_a := a.global_position - fighter.global_position
		from_front = fighter.get_facing().dot(to_a) >= 0.0
		dir = -to_a.normalized()  # the way the blow pushes them, for a KO ragdoll
	# Hooks come in from the side, so their push (info "direction") knocks the head sideways;
	# straight shots snap it back. Body shots fold the body instead.
	var push: Vector3 = info.get("direction", Vector3.ZERO)
	if push.length() > 0.01:
		dir = push.normalized()
	var zone := StringName(info.get("zone", &"head"))
	if rig.get_method_argument_count(&"play_hit") >= 4:
		rig.call("play_hit", from_front, bool(info.get("heavy", false)), dir, zone)
	else:
		rig.play_hit(from_front, bool(info.get("heavy", false)), dir)


func _on_slipped(dir: Vector2) -> void:
	if rig != null and rig.has_method("set_head_bob") and not fighter.is_multiplayer_authority():
		rig.call("set_head_bob", Vector2(dir.x, -dir.y))


func _on_countered(defender: Node, _attacker: Node) -> void:
	if defender == fighter and rig != null and rig.has_method("play_parry"):
		rig.call("play_parry")


func _on_nose_broken(f: Node) -> void:
	if f == fighter:
		rig.break_nose()
