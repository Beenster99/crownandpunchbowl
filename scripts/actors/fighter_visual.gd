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
	lean = HitLean.new()
	lean.name = "HitLean"
	lean.setup(fighter, rig)
	add_child(lean)
	Events.nose_broken.connect(_on_nose_broken)


func _process(_delta: float) -> void:
	if fighter == null or rig == null:
		return
	var v := fighter.velocity
	var local := fighter.global_basis.inverse() * Vector3(v.x, 0.0, v.z)
	rig.set_move_vector(Vector2(local.x, -local.z))  # facing is -Z
	rig.set_move_speed(Vector2(v.x, v.z).length())
	# Clients see `state` arrive through the state synchroniser, which doesn't fire
	# state_changed; catch those changes here.
	if int(fighter.state) != _last_state:
		_play_state(fighter.state)
	if fighter.max_hp > 0.0:
		rig.set_blood(clampf(1.0 - fighter.hp / fighter.max_hp, 0.0, 1.0) * 1.1 - 0.1)
	rig.set_guard(_wants_guard())
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
	if key == "stagger" and rig.current in [&"hit_front", &"hit_back", &"hit_front_b", &"hit_left", &"hit_right",
			&"hit_uppercut", &"hit_body", &"hit_body_l", &"hit_body_r"]:
		return
	if key == "dodge":
		rig.play_dodge(fighter.velocity)
		return
	rig.play_state(key)


func _on_state_changed(_old: Fighter.State, new_state: Fighter.State) -> void:
	_play_state(new_state)


func _on_move_started(move_id: StringName) -> void:
	# A wind-up long enough to see is played as a visible load-up, held until the hit.
	if fighter.state == Fighter.State.WINDUP and fighter.windup_remaining() >= 0.1:
		rig.play_windup(String(move_id), fighter.windup_remaining())
	else:
		rig.play_move(String(move_id))


func _on_hit_taken(info: Dictionary) -> void:
	if fighter.is_down():
		return
	var from_front := true
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var a := info.get("attacker") as Node3D
	if a != null and is_instance_valid(a):
		var to_a := a.global_position - fighter.global_position
		from_front = fighter.get_facing().dot(to_a) >= 0.0
		if dir.length() < 0.01:
			dir = -to_a.normalized()  # the way the blow pushes them, for a KO ragdoll
	dir.y = 0.0
	var zone := StringName(info.get("zone", "head"))
	if bool(info.get("parried", false)):
		return
	if bool(info.get("blocked", false)):
		rig.play_block_hit(dir, zone)  # knocked back a touch in the cover
		return
	rig.play_hit(from_front, bool(info.get("heavy", false)), dir, zone, String(info.get("move", "")))


func _on_nose_broken(f: Node) -> void:
	if f == fighter:
		rig.break_nose()
