@tool
class_name CharacterRig
extends Node3D
## The shared humanoid rig. Every farmer, punter, copper and member of bar staff is
## this rig with a different CharacterLook. It builds a chunky low-poly body out of
## primitives, plus the full placeholder animation set.
##
## Gameplay code only talks to the API below (play_state, play_move, set_move_speed,
## get_socket, set_blood, break_nose). When real art arrives, a skinned glTF with the
## same animation names and sockets replaces the primitives without touching gameplay.
## See docs/CHARACTERS.md.
##
## Facing is -Z, the same as the placeholder player. The rig's origin is between the feet.

signal animation_finished(anim_name: StringName)

## Every animation in the set. Real art must provide all of these names.
const ANIMATIONS: Array[StringName] = [
	&"idle", &"walk", &"punch_l", &"punch_r", &"kick", &"headbutt", &"windup", &"swing",
	&"throw", &"grab", &"hold", &"held_struggle", &"hit_front", &"hit_back", &"stagger",
	&"knockdown", &"down", &"get_up", &"crawl", &"ko", &"drink", &"eat", &"dodge",
	&"cheer", &"taunt",
]

## Fighter state name (lower case, as in Fighter.State) -> animation.
const STATE_ANIMS := {
	"idle": &"idle", "attack": &"punch_r", "windup": &"windup", "stagger": &"stagger",
	"down": &"knockdown", "crawl": &"crawl", "ko": &"ko", "held": &"held_struggle",
	"grabbing": &"grab", "dodge": &"dodge",
}

## Move names (as in Events.hit_landed "move") -> animation. "punch" alternates hands.
const MOVE_ANIMS := {
	"punch_l": &"punch_l", "punch_r": &"punch_r", "kick": &"kick", "headbutt": &"headbutt",
	"swing": &"swing", "throw": &"throw", "grab": &"grab", "drink": &"drink", "eat": &"eat",
	"cheer": &"cheer", "taunt": &"taunt",
	# Move ids from scripts/combat/moves.gd. Placeholders reuse the nearest animation.
	"jab": &"punch_l", "cross": &"punch_r", "hook": &"punch_r", "uppercut": &"punch_r",
	"haymaker": &"punch_r", "counter": &"punch_r", "counter_whiff": &"dodge", "shove": &"punch_l",
	"knee": &"kick", "stomp": &"kick", "baton": &"swing",
}

## One-shots that hand over to another animation when they finish.
const CHAINS := {&"knockdown": &"down", &"grab": &"hold"}
## One-shots that go back to idle (or walk) when they finish.
const RETURNS_TO_IDLE: Array[StringName] = [
	&"punch_l", &"punch_r", &"kick", &"headbutt", &"swing", &"throw", &"hit_front",
	&"hit_back", &"stagger", &"get_up", &"drink", &"eat", &"dodge", &"cheer", &"taunt",
]
## Lying on the floor. Drunken sway is switched off for these.
const ON_FLOOR: Array[StringName] = [&"knockdown", &"down", &"crawl", &"ko"]

## Attachment points for weapons, pints and held enemies.
const SOCKETS: Array[StringName] = [&"hand_r", &"hand_l", &"head", &"chest", &"hold_point"]

const ANIM_JOINTS: Array[StringName] = [
	&"Hips", &"Spine", &"Chest", &"Head", &"ShoulderL", &"ElbowL", &"ShoulderR", &"ElbowR",
	&"HipL", &"KneeL", &"HipR", &"KneeR",
]

## Which look to build. Leave empty and set look_id instead to pick from CharacterLooks.
@export var look: CharacterLook:
	set(value):
		look = value
		if is_inside_tree():
			rebuild()
## Id from CharacterLooks (a farmer id, punter type, "constable", "barman"...).
@export var look_id := "":
	set(value):
		look_id = value
		if is_inside_tree() and value != "":
			look = CharacterLooks.by_id(value, look_seed)
## Seed for crowd variation. Use something every peer agrees on, like the NPC number.
@export var look_seed := 0
@export var auto_return_to_idle := true
## Plays this animation on start. In the editor it previews the pose.
@export var start_animation: StringName = &"idle"

var anim: AnimationPlayer
var current: StringName = &""

var _body: Node3D
var _joints := {}
var _sockets := {}
var _mats := {}
var _leg := 0.0
var _lie := 0.0
var _time := 0.0
var _moving := false
var _next_punch_left := false
var _blood := 0.0
var _blood_nodes: Array[Node3D] = []
var _nose: Node3D


func _ready() -> void:
	if look == null and look_id != "":
		look = CharacterLooks.by_id(look_id, look_seed)
	else:
		rebuild()


func _process(delta: float) -> void:
	if _body == null or look == null:
		return
	_time += delta
	var w := 0.0 if ON_FLOOR.has(current) else look.sway
	_body.rotation.z = sin(_time * 1.3) * 0.07 * w
	_body.rotation.x = sin(_time * 0.85 + 1.0) * 0.04 * w


# --- Public API ------------------------------------------------------------

## Plays an animation by name with a short blend.
func play(anim_name: StringName, blend := 0.1) -> void:
	if anim == null or not anim.has_animation(anim_name):
		push_warning("CharacterRig: no animation '%s'" % anim_name)
		return
	current = anim_name
	anim.speed_scale = 1.0
	anim.play(anim_name, blend)
	if anim_name == &"idle" or anim_name == &"walk" or anim_name == &"hold":
		anim.seek(randf() * anim.current_animation_length if not Engine.is_editor_hint() else 0.0, true)


## Plays the animation for a Fighter state, by name: "stagger", "KO", "held"...
func play_state(state_name: String) -> void:
	var key := state_name.to_lower()
	if key == "idle":
		play(&"walk" if _moving else &"idle")
	elif STATE_ANIMS.has(key):
		play(STATE_ANIMS[key])
	else:
		push_warning("CharacterRig: no animation for state '%s'" % state_name)


## Plays an attack or action by move name. "punch" alternates left and right.
func play_move(move: String) -> void:
	if move == "punch":
		play(&"punch_l" if _next_punch_left else &"punch_r", 0.05)
		_next_punch_left = not _next_punch_left
	elif MOVE_ANIMS.has(move):
		play(MOVE_ANIMS[move], 0.05)
	else:
		push_warning("CharacterRig: no animation for move '%s'" % move)


## Plays a hit reaction. `from_front` is true when the hit came from in front.
func play_hit(from_front := true, heavy := false) -> void:
	if heavy:
		play(&"stagger", 0.05)
	else:
		play(&"hit_front" if from_front else &"hit_back", 0.03)


## Call every frame with horizontal speed in m/s. Switches between idle and walk.
func set_move_speed(speed: float) -> void:
	_moving = speed > 0.2
	if current == &"idle" and _moving:
		play(&"walk", 0.15)
	elif current == &"walk" and not _moving:
		play(&"idle", 0.2)
	if current == &"walk":
		anim.speed_scale = clampf(speed / 2.6, 0.6, 2.2)


## A node to attach weapons, glasses or a held enemy to: hand_r, hand_l, head, chest, hold_point.
func get_socket(socket: StringName) -> Node3D:
	return _sockets.get(socket)


## 0 is clean. Higher levels show a nosebleed, a bloody face and blood down the front.
## Cosmetic only. The gore workstream decides when to call it (for example from hp).
func set_blood(level: float) -> void:
	_blood = clampf(level, 0.0, 1.0)
	var thresholds := [0.2, 0.45, 0.65, 0.85]
	for i in _blood_nodes.size():
		_blood_nodes[i].visible = _blood >= thresholds[i]


## Knocks the nose sideways. Hook this to Events.nose_broken.
func break_nose() -> void:
	if _nose:
		_nose.rotation_degrees = Vector3(0, 0, 22)
		_nose.position.x += 0.012
	set_blood(maxf(_blood, 0.45))


## The head's height in world units for this look, standing. Handy for UI and camera.
func head_height() -> float:
	return (_sockets[&"head"] as Node3D).global_position.y - global_position.y if _sockets.has(&"head") else 1.7


# --- Building --------------------------------------------------------------

func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_joints.clear()
	_sockets.clear()
	_mats.clear()
	_blood_nodes.clear()
	_nose = null
	if look == null:
		return
	_build_body()
	_build_animations()
	set_blood(_blood)
	if start_animation != &"" and anim.has_animation(start_animation):
		play(start_animation, 0.0)
		anim.advance(0.0)


func _build_body() -> void:
	var L := look
	var t := L.limb_thickness
	var thigh := 0.44 * L.leg_length
	var shin := 0.42 * L.leg_length
	var foot_h := 0.08
	_leg = thigh + shin + foot_h
	var torso_w := 0.4 * L.girth * (0.92 if L.feminine else 1.0)
	var torso_d := 0.25 * L.girth
	var hip_w := torso_w * (1.06 if L.feminine else 0.95)
	var shoulder_x := 0.17 * L.shoulders + 0.06 * L.girth
	var upper := 0.3 * L.arm_length
	var fore := 0.27 * L.arm_length
	var head_r := 0.13 * L.head_size
	_lie = 0.15 * L.girth + 0.04 * L.belly - _leg

	var sleeve := L.top_color
	var torso_col := L.top_color
	var legs_col := L.trousers_color
	if L.over == CharacterLook.Over.OVERALLS:
		legs_col = L.over_color

	_body = Node3D.new()
	_body.name = "Body"
	_body.scale = Vector3.ONE * L.height
	add_child(_body)

	# Spine and chest.
	var hips := _joint(&"Hips", _body, Vector3(0, _leg, 0))
	var spine := _joint(&"Spine", hips, Vector3(0, 0.02, 0))
	var hunch := _joint(&"Hunch", spine, Vector3(0, 0.18, 0))
	hunch.rotation_degrees.x = -L.stoop
	var chest := _joint(&"Chest", hunch, Vector3.ZERO)
	var neck := _joint(&"Neck", chest, Vector3(0, 0.38, 0))
	var head := _joint(&"Head", neck, Vector3(0, 0.06, 0))

	_box(hips, Vector3(hip_w, 0.2, torso_d * 0.95), Vector3(0, -0.03, 0), legs_col)
	_box(spine, Vector3(torso_w * 0.98, 0.22, torso_d), Vector3(0, 0.08, 0), torso_col)
	_box(chest, Vector3(torso_w * 1.04, 0.36, torso_d * 1.04), Vector3(0, 0.19, 0), torso_col)
	# Shoulder yoke so broad builds read from above.
	_box(chest, Vector3(shoulder_x * 2.0 + 0.06 * t, 0.12, torso_d * 0.95), Vector3(0, 0.32, 0), torso_col)
	if L.belly > 0.15:
		var outer := L.over_color if L.over in [CharacterLook.Over.OVERALLS, CharacterLook.Over.HI_VIS, CharacterLook.Over.APRON] else torso_col
		var b := _sphere(spine, 0.5, Vector3(0, 0.1, -torso_d * 0.12 - 0.05 * L.belly), outer)
		b.scale = Vector3(torso_w * 0.92, 0.3 + 0.06 * L.belly, torso_d * 0.75 + 0.14 * L.belly)
	_cyl(neck, 0.055 * t + 0.02 * L.girth, 0.1, Vector3(0, 0.02, 0), L.skin)

	_build_head(head, head_r)
	_build_clothes(spine, chest, hips, torso_w, torso_d, hip_w, shoulder_x)

	# Arms.
	var rolled := L.sleeves_rolled
	for side in [-1.0, 1.0]:
		var s := "L" if side < 0 else "R"
		var shoulder := _joint(StringName("Shoulder" + s), chest, Vector3(shoulder_x * side, 0.31, 0))
		var elbow := _joint(StringName("Elbow" + s), shoulder, Vector3(0, -upper, 0))
		_capsule(shoulder, 0.07 * t, upper + 0.1, Vector3(0, -upper * 0.5, 0), sleeve)
		_capsule(elbow, 0.06 * t, fore + 0.06, Vector3(0, -fore * 0.5, 0), L.skin if rolled else sleeve)
		if rolled:
			_cyl(elbow, 0.072 * t, 0.07, Vector3(0, -0.02, 0), sleeve)
		var hs := L.hand_size
		_box(elbow, Vector3(0.1, 0.11, 0.09) * hs * (0.85 + 0.15 * t), Vector3(0, -fore - 0.04 * hs, -0.005), L.skin)
		var hand := _joint(StringName("Hand" + s), elbow, Vector3(0, -fore - 0.05 * hs, 0))
		_sockets[StringName("hand_" + s.to_lower())] = hand
		if L.top == CharacterLook.Top.RUGBY_SHIRT:
			_cyl(shoulder, 0.074 * t, 0.05, Vector3(0, -upper * 0.55, 0), L.top_trim)
		if L.top == CharacterLook.Top.POLICE and L.hat == CharacterLook.Hat.POLICE_CAP:
			# Sergeant's stripes.
			for i in 3:
				_box(shoulder, Vector3(0.02, 0.012, 0.1), Vector3(0.072 * t * side, -0.1 - i * 0.025, 0), L.top_trim)

	# Legs.
	for side in [-1.0, 1.0]:
		var s := "L" if side < 0 else "R"
		var hip := _joint(StringName("Hip" + s), hips, Vector3(hip_w * 0.27 * side, -0.04, 0))
		var knee := _joint(StringName("Knee" + s), hip, Vector3(0, -thigh, 0))
		_capsule(hip, 0.09 * t * (0.9 + 0.1 * L.girth), thigh + 0.12, Vector3(0, -thigh * 0.5, 0), legs_col)
		var shin_col := legs_col
		if L.wellies:
			shin_col = L.boots_color
		elif L.shorts:
			shin_col = L.skin
		_capsule(knee, 0.075 * t, shin + 0.08, Vector3(0, -shin * 0.5, 0), shin_col)
		if L.shorts:
			_cyl(knee, 0.08 * t, 0.1, Vector3(0, -shin + 0.04, 0), Color("6a6a60"))  # walking socks
		_box(knee, Vector3(0.13, 0.09, 0.27) * (0.9 + 0.1 * t), Vector3(0, -shin - 0.035, -0.05), L.boots_color)

	_sockets[&"head"] = head
	_sockets[&"chest"] = chest
	var hold := Node3D.new()
	hold.name = "HoldPoint"
	hold.position = Vector3(0, 0.0, -torso_d - 0.32)
	chest.add_child(hold)
	_sockets[&"hold_point"] = hold


func _build_head(head: Node3D, r: float) -> void:
	var L := look
	var c := r * 1.05  # head centre height above the neck joint
	var skull := _sphere(head, r, Vector3(0, c, 0), L.skin)
	skull.scale = Vector3(1.0, 1.1, 1.05)
	# Brow ridge, ears, eyes, mouth.
	var brow_col := L.skin.darkened(0.08)
	_box(head, Vector3(r * 1.5, r * (0.18 + 0.2 * L.brow), r * (0.3 + 0.4 * L.brow) * (0.7 if L.feminine else 1.0)),
		Vector3(0, c + r * 0.38, -r * 0.82), brow_col)
	var bald_brows := L.hair_color if L.hair != CharacterLook.Hair.BALD else L.beard_color
	for side in [-1.0, 1.0]:
		_box(head, Vector3(r * 0.45, r * 0.1, r * 0.12), Vector3(r * 0.38 * side, c + r * (0.5 + 0.1 * L.brow), -r * (0.93 + 0.2 * L.brow)), bald_brows.darkened(0.2))
		_box(head, Vector3(r * 0.16, r * 0.14, r * 0.06), Vector3(r * 0.36 * side, c + r * 0.25, -r * 0.98), Color("161210"))
		_box(head, Vector3(r * 0.16, r * 0.38, r * 0.3), Vector3(r * 1.0 * side, c + r * 0.05, 0.0), L.skin.darkened(0.05))
		_sphere(head, r * 0.22, Vector3(r * 0.55 * side, c - r * 0.1, -r * 0.82), L.flush.lerp(L.skin, 0.5))
	_nose = Node3D.new()
	_nose.name = "Nose"
	_nose.position = Vector3(0, c + r * 0.05, -r * 1.02)
	head.add_child(_nose)
	var ns := L.nose_size
	_box(_nose, Vector3(r * 0.32, r * 0.42, r * 0.36) * ns, Vector3(0, 0, -r * 0.1 * ns), L.flush)
	if L.beard != CharacterLook.Beard.FULL:
		var lips := Color("a8474a") if L.feminine else Color("5a2a24")
		_box(head, Vector3(r * 0.55, r * (0.12 if L.feminine else 0.08), r * 0.1), Vector3(0, c - r * 0.42, -r * 0.94), lips)

	_build_hair(head, r, c)
	if L.feminine and L.hair in [CharacterLook.Hair.BUN, CharacterLook.Hair.PONYTAIL]:
		for side in [-1.0, 1.0]:
			_box(head, Vector3(r * 0.3, r * 0.9, r * 0.35), Vector3(r * 0.9 * side, c + r * 0.05, -r * 0.45), L.hair_color)
	_build_beard(head, r, c)

	if L.glasses:
		var frame := Color("1a1a1a")
		for side in [-1.0, 1.0]:
			_box(head, Vector3(r * 0.4, r * 0.3, r * 0.04), Vector3(r * 0.38 * side, c + r * 0.25, -r * 1.06), frame).transparency = 0.35
		_box(head, Vector3(r * 0.3, r * 0.05, r * 0.04), Vector3(0, c + r * 0.3, -r * 1.06), frame)

	_build_hat(head, r, c)

	# Blood, hidden until set_blood() asks for it.
	var blood := Color("8a0d0d")
	var drip := _box(_nose, Vector3(r * 0.2, r * 0.5, r * 0.06), Vector3(0, -r * 0.4, -r * 0.18), blood)
	var face := _box(head, Vector3(r * 1.0, r * 0.55, r * 0.08), Vector3(0, c - r * 0.35, -r * 1.0), blood)
	var cheek := _box(head, Vector3(r * 0.35, r * 0.5, r * 0.08), Vector3(r * 0.55, c + r * 0.15, -r * 0.88), blood.darkened(0.15))
	var shirt := _box(_joints[&"Chest"], Vector3(0.18, 0.22, 0.03) * look.girth, Vector3(0.0, 0.22, -0.13 * look.girth - 0.01), blood)
	_blood_nodes.assign([drip, face, shirt, cheek])


func _build_hair(head: Node3D, r: float, c: float) -> void:
	var L := look
	var col := L.hair_color
	match L.hair:
		CharacterLook.Hair.BALD:
			# Horseshoe round the back for the old boys.
			_box(head, Vector3(r * 1.7, r * 0.45, r * 0.5), Vector3(0, c + r * 0.05, r * 0.8), col)
		CharacterLook.Hair.SHAVED:
			_cap(head, r * 1.03, Vector3(0, c + r * 0.05, r * 0.04), 20.0, L.skin.lerp(col, 0.45))
		CharacterLook.Hair.SHORT, CharacterLook.Hair.SIDE_PARTING:
			_cap(head, r * 1.07, Vector3(0, c + r * 0.08, r * 0.05), 22.0, col)
			_box(head, Vector3(r * 1.6, r * 0.7, r * 0.5), Vector3(0, c + r * 0.15, r * 0.75), col)
			if L.hair == CharacterLook.Hair.SIDE_PARTING:
				var sweep := _box(head, Vector3(r * 1.2, r * 0.3, r * 0.6), Vector3(r * 0.2, c + r * 0.82, -r * 0.55), col)
				sweep.rotation_degrees.z = -12
		CharacterLook.Hair.MOP:
			var mop := _cap(head, r * 1.18, Vector3(0, c + r * 0.05, r * 0.02), 14.0, col)
			mop.scale.y = 0.95
			_box(head, Vector3(r * 1.7, r * 0.35, r * 0.4), Vector3(0, c + r * 0.62, -r * 0.82), col)
			_box(head, Vector3(r * 2.1, r * 0.9, r * 0.9), Vector3(0, c - r * 0.05, r * 0.55), col)
		CharacterLook.Hair.COMB_OVER:
			_box(head, Vector3(r * 2.05, r * 0.5, r * 0.9), Vector3(0, c + r * 0.05, r * 0.45), col)
			for i in 3:
				var strand := _box(head, Vector3(r * 1.9, r * 0.06, r * 0.12), Vector3(0, c + r * (1.05 - i * 0.04), r * (-0.3 + i * 0.3)), col)
				strand.rotation_degrees.z = 8
		CharacterLook.Hair.BUN:
			_cap(head, r * 1.07, Vector3(0, c + r * 0.06, r * 0.05), 22.0, col)
			_box(head, Vector3(r * 2.0, r * 0.8, r * 0.7), Vector3(0, c + r * 0.05, r * 0.65), col)
			_sphere(head, r * 0.42, Vector3(0, c + r * 0.85, r * 0.85), col)
		CharacterLook.Hair.PONYTAIL:
			_cap(head, r * 1.07, Vector3(0, c + r * 0.06, r * 0.05), 22.0, col)
			_box(head, Vector3(r * 2.0, r * 0.8, r * 0.7), Vector3(0, c + r * 0.05, r * 0.65), col)
			var tail := _capsule(head, r * 0.22, r * 1.6, Vector3(0, c - r * 0.2, r * 1.15), col)
			tail.rotation_degrees.x = 25
		CharacterLook.Hair.FLOPPY:
			_cap(head, r * 1.12, Vector3(0, c + r * 0.1, r * 0.04), 18.0, col)
			var fringe := _box(head, Vector3(r * 1.3, r * 0.5, r * 0.35), Vector3(-r * 0.3, c + r * 0.6, -r * 0.85), col)
			fringe.rotation_degrees.z = 18
			_box(head, Vector3(r * 2.0, r * 0.8, r * 0.7), Vector3(0, c, r * 0.65), col)


func _build_beard(head: Node3D, r: float, c: float) -> void:
	var L := look
	var col := L.beard_color
	match L.beard:
		CharacterLook.Beard.STUBBLE:
			_box(head, Vector3(r * 1.7, r * 0.75, r * 1.3), Vector3(0, c - r * 0.45, -r * 0.32), L.skin.lerp(col, 0.4))
		CharacterLook.Beard.FULL:
			_box(head, Vector3(r * 1.9, r * 0.95, r * 1.35), Vector3(0, c - r * 0.45, -r * 0.35), col)
			_box(head, Vector3(r * 1.1, r * 0.6, r * 0.6), Vector3(0, c - r * 1.0, -r * 0.65), col)
			_box(head, Vector3(r * 0.9, r * 0.18, r * 0.25), Vector3(0, c - r * 0.18, -r * 1.0), col)
		CharacterLook.Beard.GOATEE:
			_box(head, Vector3(r * 0.55, r * 0.7, r * 0.35), Vector3(0, c - r * 0.7, -r * 0.82), col)
			_box(head, Vector3(r * 0.8, r * 0.12, r * 0.2), Vector3(0, c - r * 0.28, -r * 1.0), col)
		CharacterLook.Beard.MUTTON_CHOPS:
			for side in [-1.0, 1.0]:
				_box(head, Vector3(r * 0.5, r * 1.0, r * 0.95), Vector3(r * 0.78 * side, c - r * 0.25, -r * 0.25), col)
			_box(head, Vector3(r * 1.1, r * 0.2, r * 0.25), Vector3(0, c - r * 0.25, -r * 1.0), col)
		CharacterLook.Beard.MOUSTACHE:
			_box(head, Vector3(r * 1.0, r * 0.2, r * 0.25), Vector3(0, c - r * 0.25, -r * 1.0), col)


func _build_hat(head: Node3D, r: float, c: float) -> void:
	var L := look
	var col := L.hat_color
	match L.hat:
		CharacterLook.Hat.FLAT_CAP:
			var crown := _sphere(head, r * 1.15, Vector3(0, c + r * 0.72, -r * 0.05), col)
			crown.scale = Vector3(1.0, 0.42, 1.08)
			crown.rotation_degrees.x = -10
			_box(head, Vector3(r * 1.5, r * 0.08, r * 0.6), Vector3(0, c + r * 0.55, -r * 1.05), col.darkened(0.15)).rotation_degrees.x = 10
		CharacterLook.Hat.BEANIE, CharacterLook.Hat.BOBBLE_HAT:
			var b := _cap(head, r * 1.16, Vector3(0, c + r * 0.3, r * 0.02), 12.0, col)
			b.scale.y = 1.25
			_cyl(head, r * 1.17, r * 0.35, Vector3(0, c + r * 0.4, r * 0.0), col.darkened(0.15)).rotation_degrees.x = 12
			if L.hat == CharacterLook.Hat.BOBBLE_HAT:
				_sphere(head, r * 0.35, Vector3(0, c + r * 1.75, r * 0.1), Color("f2efe6"))
		CharacterLook.Hat.TRILBY:
			var tilt := Node3D.new()
			tilt.position = Vector3(0, c + r * 0.62, 0)
			tilt.rotation_degrees = Vector3(-6, 0, 9)
			head.add_child(tilt)
			_cyl(tilt, r * 1.75, r * 0.07, Vector3.ZERO, col)
			_cyl(tilt, r * 0.95, r * 0.75, Vector3(0, r * 0.38, 0), col, r * 0.8)
			_cyl(tilt, r * 0.97, r * 0.18, Vector3(0, r * 0.12, 0), Color("2a1a14"))
		CharacterLook.Hat.BASEBALL_CAP:
			_cap(head, r * 1.12, Vector3(0, c + r * 0.15, r * 0.03), 8.0, col)
			_box(head, Vector3(r * 1.2, r * 0.07, r * 0.85), Vector3(0, c + r * 0.55, -r * 1.25), col.darkened(0.1))
		CharacterLook.Hat.POLICE_HELMET:
			var dome := _sphere(head, r * 1.15, Vector3(0, c + r * 0.85, r * 0.05), col)
			dome.scale = Vector3(1.0, 1.55, 1.12)
			_cyl(head, r * 1.25, r * 0.08, Vector3(0, c + r * 0.45, 0), col)
			_box(head, Vector3(r * 0.35, r * 0.45, r * 0.06), Vector3(0, c + r * 0.95, -r * 1.25), Color("c8ccd4"))
			_sphere(head, r * 0.18, Vector3(0, c + r * 2.55, r * 0.05), Color("c8ccd4"))
		CharacterLook.Hat.POLICE_CAP:
			_cyl(head, r * 1.3, r * 0.32, Vector3(0, c + r * 0.85, -r * 0.05), col, r * 1.08)
			_cyl(head, r * 1.11, r * 0.16, Vector3(0, c + r * 0.62, -r * 0.03), Color("e8e8e8"))
			_box(head, Vector3(r * 1.1, r * 0.06, r * 0.55), Vector3(0, c + r * 0.52, -r * 1.12), Color("0b0b0b")).rotation_degrees.x = 15
			_box(head, Vector3(r * 0.3, r * 0.3, r * 0.05), Vector3(0, c + r * 0.85, -r * 1.33), Color("c8ccd4"))
		CharacterLook.Hat.HEADSCARF:
			_cap(head, r * 1.12, Vector3(0, c + r * 0.12, r * 0.04), 18.0, col)
			var knot := _box(head, Vector3(r * 0.4, r * 0.3, r * 0.3), Vector3(0, c - r * 0.6, -r * 0.7), col)
			knot.rotation_degrees.z = 45


func _build_clothes(spine: Node3D, chest: Node3D, hips: Node3D, tw: float, td: float, hw: float, shx: float) -> void:
	var L := look
	var front := -td * 0.52 - 0.012  # just proud of the chest front
	match L.top:
		CharacterLook.Top.SHIRT:
			_collar(chest, td, L.top_color.lightened(0.1))
			# A check pattern in the trim colour.
			for i in [-1.0, 1.0]:
				_box(chest, Vector3(0.025, 0.34, 0.01), Vector3(tw * 0.25 * i, 0.19, front), L.top_trim).transparency = 0.45
				_box(chest, Vector3(tw * 1.02, 0.025, 0.01), Vector3(0, 0.19 + 0.08 * i, front), L.top_trim).transparency = 0.45
		CharacterLook.Top.JUMPER:
			_collar(chest, td, L.top_trim)
			_box(spine, Vector3(tw * 1.02, 0.06, td * 1.04), Vector3(0, 0.0, 0), L.top_color.darkened(0.15))
		CharacterLook.Top.BOILER_SUIT:
			_collar(chest, td, L.top_trim)
			_box(chest, Vector3(0.02, 0.36, 0.01), Vector3(0, 0.19, front), Color("b8b8b8"))
			_box(spine, Vector3(0.02, 0.22, 0.01), Vector3(0, 0.08, front), Color("b8b8b8"))
			_box(chest, Vector3(0.1, 0.08, 0.01), Vector3(tw * 0.25, 0.25, front), L.top_trim)
		CharacterLook.Top.WAX_JACKET:
			_box(chest, Vector3(tw * 1.12, 0.38, td * 1.12), Vector3(0, 0.19, 0), L.top_color)
			_box(spine, Vector3(tw * 1.1, 0.3, td * 1.12), Vector3(0, 0.03, 0), L.top_color)
			_collar(chest, td * 1.1, L.top_trim)
			for i in [-1.0, 1.0]:
				_box(spine, Vector3(0.11, 0.09, 0.02), Vector3(tw * 0.3 * i, 0.02, -td * 0.58), L.top_color.darkened(0.2))
		CharacterLook.Top.FLEECE, CharacterLook.Top.CAGOULE:
			_collar(chest, td, L.top_color.darkened(0.12), 0.09)
			_box(chest, Vector3(0.018, 0.34, 0.01), Vector3(0, 0.19, front), L.top_trim)
			if L.top == CharacterLook.Top.CAGOULE:
				_box(chest, Vector3(tw * 0.9, 0.1, td * 0.5), Vector3(0, 0.37, td * 0.45), L.top_color.darkened(0.1))
		CharacterLook.Top.RUGBY_SHIRT:
			for y in [0.06, 0.2, 0.32]:
				_box(chest, Vector3(tw * 1.06, 0.05, td * 1.06), Vector3(0, y, 0), L.top_trim)
			_box(spine, Vector3(tw * 1.0, 0.05, td * 1.02), Vector3(0, 0.1, 0), L.top_trim)
			_collar(chest, td, Color("f2efe6"), 0.08)
		CharacterLook.Top.POLICE:
			_collar(chest, td, L.top_color.lightened(0.1))
			for i in [-1.0, 1.0]:
				_box(chest, Vector3(0.12, 0.02, 0.1), Vector3(shx * 0.8 * i, 0.39, 0), L.top_color.lightened(0.15))
		CharacterLook.Top.BAR_SHIRT:
			_collar(chest, td, L.top_color.lightened(0.05))
			_box(chest, Vector3(0.1, 0.04, 0.03), Vector3(0, 0.34, front - 0.01), L.top_trim)
		CharacterLook.Top.HOODIE:
			_box(chest, Vector3(tw * 0.75, 0.14, 0.12), Vector3(0, 0.36, td * 0.55), L.top_color)
			_box(spine, Vector3(tw * 0.6, 0.12, 0.02), Vector3(0, 0.07, front), L.top_trim)
			for i in [-1.0, 1.0]:
				_box(chest, Vector3(0.012, 0.12, 0.012), Vector3(0.04 * i, 0.3, front), Color("e8e8e8"))

	match L.over:
		CharacterLook.Over.GILET:
			_open_shell(chest, tw * 1.1, 0.38, td * 1.14, 0.19, L.over_color)
			_open_shell(spine, tw * 1.08, 0.24, td * 1.12, 0.06, L.over_color)
			for y in [0.08, 0.2, 0.32]:
				_box(chest, Vector3(tw * 1.12, 0.008, td * 1.16), Vector3(0, y, 0), L.over_color.darkened(0.25))
			_collar(chest, td * 1.1, L.over_color, 0.07)
		CharacterLook.Over.WAISTCOAT:
			_open_shell(chest, tw * 1.08, 0.3, td * 1.1, 0.15, L.over_color)
			_open_shell(spine, tw * 1.06, 0.22, td * 1.1, 0.07, L.over_color)
			for y in [0.06, 0.13, 0.2]:
				_box(chest, Vector3(0.025, 0.025, 0.02), Vector3(tw * 0.12, y, -td * 0.57), Color("c9a24a"))
		CharacterLook.Over.OVERALLS:
			_box(spine, Vector3(tw * 1.04, 0.24, td * 1.06), Vector3(0, 0.07, 0), L.over_color)
			_box(chest, Vector3(tw * 0.7, 0.22, 0.03), Vector3(0, 0.1, front - 0.005), L.over_color)
			_box(chest, Vector3(0.12, 0.08, 0.01), Vector3(0, 0.12, front - 0.02), L.over_color.darkened(0.15))
			for i in [-1.0, 1.0]:
				_box(chest, Vector3(0.05, 0.03, td * 1.1), Vector3(tw * 0.28 * i, 0.38, 0), L.over_color)
				_box(chest, Vector3(0.05, 0.24, 0.02), Vector3(tw * 0.28 * i, 0.26, front), L.over_color)
				_box(chest, Vector3(0.05, 0.36, 0.02), Vector3(tw * 0.28 * i, 0.2, td * 0.53), L.over_color)
				_box(chest, Vector3(0.03, 0.03, 0.02), Vector3(tw * 0.28 * i, 0.2, front - 0.01), Color("c9c9c9"))
		CharacterLook.Over.HI_VIS:
			_box(chest, Vector3(tw * 1.1, 0.34, td * 1.12), Vector3(0, 0.17, 0), L.over_color)
			_box(spine, Vector3(tw * 1.08, 0.22, td * 1.1), Vector3(0, 0.07, 0), L.over_color)
			for y in [0.06, 0.24]:
				_box(chest, Vector3(tw * 1.12, 0.03, td * 1.14), Vector3(0, y, 0), Color("b9bcc4"))
			_box(chest, Vector3(0.22, 0.05, 0.01), Vector3(0, 0.3, -td * 0.57 - 0.01), Color("1a1d24"))  # POLICE panel
		CharacterLook.Over.APRON:
			_box(chest, Vector3(tw * 0.75, 0.24, 0.02), Vector3(0, 0.1, front), L.over_color)
			_box(spine, Vector3(tw * 0.8, 0.24, 0.02), Vector3(0, 0.08, front), L.over_color)
			_box(hips, Vector3(hw * 0.95, 0.3, 0.02), Vector3(0, -0.18, -td * 0.52), L.over_color)
			_box(spine, Vector3(tw * 1.0, 0.03, td * 1.04), Vector3(0, -0.02, 0), L.over_color)
		CharacterLook.Over.BRACES:
			for i in [-1.0, 1.0]:
				_box(chest, Vector3(0.035, 0.42, 0.012), Vector3(tw * 0.25 * i, 0.17, front - 0.004), L.over_color)
				_box(chest, Vector3(0.035, 0.42, 0.012), Vector3(tw * 0.22 * i, 0.17, td * 0.54), L.over_color)
				_box(spine, Vector3(0.035, 0.22, 0.012), Vector3(tw * 0.25 * i, 0.06, -td * 0.52 - 0.04 * L.belly - 0.006), L.over_color)

	if L.tool_belt:
		_box(hips, Vector3(hw * 1.08, 0.06, td * 1.08), Vector3(0, 0.05, 0), Color("6b4a2a"))
		for i in [-1.0, 1.0]:
			_box(hips, Vector3(0.1, 0.13, 0.09), Vector3(hw * 0.5 * i, -0.04, -td * 0.15), Color("5a3a1e"))
		var hammer := _box(hips, Vector3(0.03, 0.22, 0.03), Vector3(hw * 0.6, -0.12, 0.05), Color("8a6a3a"))
		hammer.rotation_degrees.z = 8
		_box(hips, Vector3(0.1, 0.035, 0.04), Vector3(hw * 0.61, -0.005, 0.05), Color("5a5a5a"))
	if L.neckerchief:
		var n := _box(chest, Vector3(0.16, 0.12, 0.04), Vector3(0, 0.36, -td * 0.5 - 0.02), L.neckerchief_color)
		n.rotation_degrees.z = 45
		_cyl(chest, 0.085 * L.girth, 0.05, Vector3(0, 0.4, 0), L.neckerchief_color)


func _collar(chest: Node3D, td: float, col: Color, h := 0.05) -> void:
	_box(chest, Vector3(0.22 * look.girth, h, td * 0.75), Vector3(0, 0.38 + h * 0.4, 0), col)


## A jacket shell over the torso with a gap down the front.
func _open_shell(parent: Node3D, w: float, h: float, d: float, y: float, col: Color) -> void:
	var gap := 0.08
	_box(parent, Vector3(w, h, d * 0.55), Vector3(0, y, d * 0.22), col)
	for i in [-1.0, 1.0]:
		_box(parent, Vector3((w - gap) * 0.5, h, d * 0.5), Vector3((w + gap) * 0.25 * i, y, -d * 0.25), col)


# --- Animation -------------------------------------------------------------

func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	anim.root_node = anim.get_path_to(_body)
	var lib := AnimationLibrary.new()
	var defs := _anim_defs()
	for anim_name in defs:
		lib.add_animation(anim_name, _make_animation(defs[anim_name]))
	anim.add_animation_library(&"", lib)
	anim.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(anim_name)
	if CHAINS.has(anim_name):
		play(CHAINS[anim_name], 0.15)
	elif auto_return_to_idle and RETURNS_TO_IDLE.has(anim_name):
		play(&"walk" if _moving else &"idle", 0.15)


func _make_animation(def: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = def["length"]
	a.loop_mode = Animation.LOOP_LINEAR if def.get("loop", false) else Animation.LOOP_NONE
	var keys: Array = def["keys"]
	for joint in ANIM_JOINTS:
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, _body.get_path_to(_joints[joint]))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC if def.get("loop", false) else Animation.INTERPOLATION_LINEAR)
		for k in keys:
			var pose: Dictionary = k[1]
			var deg: Vector3 = pose.get(joint, Vector3.ZERO)
			a.rotation_track_insert_key(tr, k[0], Quaternion.from_euler(deg * (PI / 180.0)))
	var pos := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos, _body.get_path_to(_joints[&"Hips"]))
	var rest: Vector3 = (_joints[&"Hips"] as Node3D).position
	for k in keys:
		var pose: Dictionary = k[1]
		a.position_track_insert_key(pos, k[0], rest + (pose.get(&"_hips", Vector3.ZERO) as Vector3))
	return a


## Swaps left and right, so right-handed poses can be reused for the left.
static func _mirror(pose: Dictionary) -> Dictionary:
	var out := {}
	for key in pose:
		var v: Vector3 = pose[key]
		var k := String(key)
		if k.ends_with("L"):
			k = k.substr(0, k.length() - 1) + "R"
		elif k.ends_with("R"):
			k = k.substr(0, k.length() - 1) + "L"
		out[StringName(k)] = Vector3(v.x, -v.y, -v.z) if k != "_hips" else Vector3(-v.x, v.y, v.z)
	return out


static func _with(base: Dictionary, changes: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(changes, true)
	return out


## Every animation as keyed poses. Each pose maps a joint to Euler degrees (x, y, z).
## +x swings a limb forward, -x on a knee bends it, -x on the spine leans forward.
## "_hips" offsets the hips from their standing position.
func _anim_defs() -> Dictionary:
	var lie := _lie
	var guard := {
		&"Spine": Vector3(-6, 0, 0),
		&"ShoulderL": Vector3(48, 0, -14), &"ElbowL": Vector3(112, 0, 0),
		&"ShoulderR": Vector3(40, 0, 14), &"ElbowR": Vector3(118, 0, 0),
		&"HipL": Vector3(8, 0, -5), &"KneeL": Vector3(-14, 0, 0), &"HipR": Vector3(-6, 0, 5), &"KneeR": Vector3(-10, 0, 0),
	}
	var relaxed := {
		&"ShoulderL": Vector3(6, 0, -7), &"ElbowL": Vector3(18, 0, 0), &"ShoulderR": Vector3(6, 0, 7), &"ElbowR": Vector3(18, 0, 0),
	}
	var punch_r_hit := _with(guard, {
		&"Spine": Vector3(-12, 24, 0), &"Chest": Vector3(0, 8, 0), &"ShoulderR": Vector3(88, 0, -6), &"ElbowR": Vector3(6, 0, 0),
		&"ShoulderL": Vector3(42, 0, -16), &"ElbowL": Vector3(122, 0, 0), &"KneeL": Vector3(-22, 0, 0), &"_hips": Vector3(0, -0.03, -0.07),
	})
	var punch_r_load := _with(guard, {&"Spine": Vector3(-4, -16, 0), &"ShoulderR": Vector3(28, 0, 22), &"ElbowR": Vector3(128, 0, 0)})
	var on_back := {
		&"Hips": Vector3(90, 0, 0), &"_hips": Vector3(0, lie, 0.42),
		&"ShoulderL": Vector3(12, 0, -58), &"ElbowL": Vector3(40, 0, 0), &"ShoulderR": Vector3(8, 0, 52), &"ElbowR": Vector3(30, 0, 0),
		&"HipL": Vector3(12, 0, -10), &"KneeL": Vector3(-30, 0, 0), &"HipR": Vector3(2, 0, 8), &"KneeR": Vector3(-6, 0, 0),
		&"Head": Vector3(0, 28, 0),
	}
	var crawl_a := {
		&"Hips": Vector3(-80, -5, 0), &"_hips": Vector3(0, lie + 0.03, 0.15), &"Spine": Vector3(14, 0, 0), &"Chest": Vector3(10, 0, 0),
		&"Head": Vector3(40, 0, 0),
		&"ShoulderR": Vector3(155, 0, 12), &"ElbowR": Vector3(25, 0, 0), &"ShoulderL": Vector3(100, 0, -12), &"ElbowL": Vector3(75, 0, 0),
		&"HipL": Vector3(-4, 0, -12), &"KneeL": Vector3(-40, 0, 0), &"HipR": Vector3(-2, 0, 8), &"KneeR": Vector3(-8, 0, 0),
	}
	var crawl_b := _mirror(crawl_a)
	crawl_b[&"_hips"] = Vector3(0, lie + 0.03, 0.15)
	var hold_a := {
		&"Spine": Vector3(-8, 0, 0), &"ShoulderL": Vector3(78, 0, 26), &"ElbowL": Vector3(78, 0, 0),
		&"ShoulderR": Vector3(78, 0, -26), &"ElbowR": Vector3(78, 0, 0),
		&"HipL": Vector3(14, 0, -6), &"KneeL": Vector3(-22, 0, 0), &"HipR": Vector3(-12, 0, 6), &"KneeR": Vector3(-16, 0, 0),
	}
	var held_a := {
		&"Spine": Vector3(10, 16, 6), &"Head": Vector3(18, 25, 0),
		&"ShoulderL": Vector3(-16, 0, -10), &"ElbowL": Vector3(35, 0, 0), &"ShoulderR": Vector3(-12, 0, 12), &"ElbowR": Vector3(45, 0, 0),
		&"HipL": Vector3(25, 0, 0), &"KneeL": Vector3(-55, 0, 0), &"HipR": Vector3(-8, 0, 0), &"KneeR": Vector3(-10, 0, 0),
		&"_hips": Vector3(0, 0.04, 0),
	}

	var defs := {}
	defs[&"idle"] = {"length": 2.0, "loop": true, "keys": [
		[0.0, guard],
		[1.0, _with(guard, {&"Chest": Vector3(-4, 0, 0), &"Spine": Vector3(-7, 3, 0), &"_hips": Vector3(0, -0.018, 0), &"ElbowL": Vector3(105, 0, 0)})],
		[2.0, guard],
	]}
	var step := _with(guard, {&"Spine": Vector3(-9, 7, 0), &"HipL": Vector3(28, 0, -3), &"KneeL": Vector3(-8, 0, 0),
		&"HipR": Vector3(-26, 0, 3), &"KneeR": Vector3(-30, 0, 0), &"ShoulderL": Vector3(38, 0, -14), &"ShoulderR": Vector3(52, 0, 14)})
	var passing := _with(guard, {&"HipL": Vector3(4, 0, -3), &"KneeL": Vector3(-10, 0, 0), &"HipR": Vector3(6, 0, 3),
		&"KneeR": Vector3(-60, 0, 0), &"_hips": Vector3(0, 0.03, 0)})
	defs[&"walk"] = {"length": 0.8, "loop": true, "keys": [
		[0.0, step], [0.2, passing], [0.4, _mirror(step)], [0.6, _mirror(passing)], [0.8, step],
	]}
	defs[&"punch_r"] = {"length": 0.42, "keys": [
		[0.0, guard], [0.08, punch_r_load], [0.16, punch_r_hit], [0.26, punch_r_hit], [0.42, guard],
	]}
	defs[&"punch_l"] = {"length": 0.42, "keys": [
		[0.0, guard], [0.08, _mirror(punch_r_load)], [0.16, _mirror(punch_r_hit)], [0.26, _mirror(punch_r_hit)], [0.42, guard],
	]}
	var kick_out := _with(guard, {&"Spine": Vector3(18, 0, 0), &"HipR": Vector3(85, 0, 0), &"KneeR": Vector3(-4, 0, 0),
		&"KneeL": Vector3(-14, 0, 0), &"HipL": Vector3(-4, 0, -5), &"ShoulderL": Vector3(30, 0, -32), &"ElbowL": Vector3(70, 0, 0)})
	defs[&"kick"] = {"length": 0.6, "keys": [
		[0.0, guard],
		[0.12, _with(guard, {&"Spine": Vector3(10, 0, 0), &"HipR": Vector3(72, 0, 0), &"KneeR": Vector3(-100, 0, 0), &"_hips": Vector3(0, 0.02, 0)})],
		[0.22, kick_out], [0.36, kick_out], [0.6, guard],
	]}
	var butt := _with(guard, {&"Spine": Vector3(-32, 0, 0), &"Chest": Vector3(-10, 0, 0), &"Head": Vector3(-25, 0, 0),
		&"ShoulderL": Vector3(62, 0, 28), &"ElbowL": Vector3(85, 0, 0), &"ShoulderR": Vector3(62, 0, -28), &"ElbowR": Vector3(85, 0, 0),
		&"_hips": Vector3(0, -0.04, -0.13)})
	defs[&"headbutt"] = {"length": 0.55, "keys": [
		[0.0, guard],
		[0.16, _with(guard, {&"Spine": Vector3(16, 0, 0), &"Head": Vector3(22, 0, 0), &"_hips": Vector3(0, 0, 0.05)})],
		[0.25, butt], [0.34, butt], [0.55, guard],
	]}
	var cocked := _with(guard, {&"Spine": Vector3(8, -30, 0), &"Head": Vector3(0, 22, 0), &"ShoulderR": Vector3(-35, 0, 58),
		&"ElbowR": Vector3(112, 0, 0), &"ShoulderL": Vector3(62, 0, -10), &"ElbowL": Vector3(55, 0, 0), &"HipR": Vector3(-14, 0, 6)})
	defs[&"windup"] = {"length": 0.5, "keys": [
		[0.0, guard], [0.3, cocked],
		[0.5, _with(cocked, {&"Spine": Vector3(10, -34, 0), &"ShoulderR": Vector3(-40, 0, 62)})],
	]}
	var overhead := _with(guard, {&"Spine": Vector3(14, 0, 0), &"ShoulderL": Vector3(165, 0, 8), &"ElbowL": Vector3(40, 0, 0),
		&"ShoulderR": Vector3(165, 0, -8), &"ElbowR": Vector3(40, 0, 0)})
	var smash := _with(guard, {&"Spine": Vector3(-26, 0, 0), &"ShoulderL": Vector3(52, 0, 10), &"ElbowL": Vector3(10, 0, 0),
		&"ShoulderR": Vector3(52, 0, -10), &"ElbowR": Vector3(10, 0, 0), &"KneeL": Vector3(-26, 0, 0), &"_hips": Vector3(0, -0.06, -0.05)})
	defs[&"swing"] = {"length": 0.7, "keys": [[0.0, guard], [0.22, overhead], [0.33, smash], [0.46, smash], [0.7, guard]]}
	defs[&"throw"] = {"length": 0.6, "keys": [
		[0.0, guard],
		[0.18, _with(guard, {&"Spine": Vector3(10, -26, 0), &"ShoulderR": Vector3(-55, 0, 32), &"ElbowR": Vector3(70, 0, 0)})],
		[0.3, _with(guard, {&"Spine": Vector3(-16, 22, 0), &"ShoulderR": Vector3(125, 0, 0), &"ElbowR": Vector3(10, 0, 0), &"_hips": Vector3(0, 0, -0.05)})],
		[0.6, guard],
	]}
	defs[&"grab"] = {"length": 0.4, "keys": [
		[0.0, guard],
		[0.15, _with(hold_a, {&"Spine": Vector3(-16, 0, 0), &"ShoulderL": Vector3(88, 0, 18), &"ElbowL": Vector3(18, 0, 0),
			&"ShoulderR": Vector3(88, 0, -18), &"ElbowR": Vector3(18, 0, 0), &"_hips": Vector3(0, -0.04, -0.1)})],
		[0.4, hold_a],
	]}
	defs[&"hold"] = {"length": 1.2, "loop": true, "keys": [
		[0.0, hold_a], [0.6, _with(hold_a, {&"Spine": Vector3(-9, 7, 4), &"_hips": Vector3(0, -0.015, 0)})], [1.2, hold_a],
	]}
	defs[&"held_struggle"] = {"length": 0.9, "loop": true, "keys": [
		[0.0, held_a], [0.45, _mirror(held_a)], [0.9, held_a],
	]}
	defs[&"hit_front"] = {"length": 0.35, "keys": [
		[0.0, guard],
		[0.06, _with(guard, {&"Head": Vector3(35, 12, 0), &"Spine": Vector3(20, 0, 0), &"Chest": Vector3(10, 0, 0), &"_hips": Vector3(0, 0, 0.08),
			&"ShoulderL": Vector3(22, 0, -26), &"ElbowL": Vector3(60, 0, 0), &"ShoulderR": Vector3(22, 0, 26), &"ElbowR": Vector3(60, 0, 0)})],
		[0.35, guard],
	]}
	defs[&"hit_back"] = {"length": 0.35, "keys": [
		[0.0, guard],
		[0.06, _with(guard, {&"Head": Vector3(-22, 0, 0), &"Spine": Vector3(-26, 0, 0), &"_hips": Vector3(0, 0, -0.08),
			&"ShoulderL": Vector3(-20, 0, -20), &"ShoulderR": Vector3(-20, 0, 20)})],
		[0.35, guard],
	]}
	defs[&"stagger"] = {"length": 0.9, "keys": [
		[0.0, guard],
		[0.15, {&"Spine": Vector3(25, 10, 8), &"Head": Vector3(30, 0, 0), &"ShoulderL": Vector3(40, 0, -62), &"ElbowL": Vector3(20, 0, 0),
			&"ShoulderR": Vector3(-10, 0, 70), &"ElbowR": Vector3(30, 0, 0), &"HipL": Vector3(28, 0, 0), &"KneeL": Vector3(-40, 0, 0),
			&"_hips": Vector3(0, -0.05, 0.1)}],
		[0.45, {&"Spine": Vector3(15, -10, -8), &"Head": Vector3(18, -10, 0), &"ShoulderL": Vector3(10, 0, -40), &"ShoulderR": Vector3(30, 0, 45),
			&"HipR": Vector3(-24, 0, 0), &"KneeR": Vector3(-22, 0, 0), &"KneeL": Vector3(-30, 0, 0), &"_hips": Vector3(0, -0.08, 0.12)}],
		[0.9, guard],
	]}
	defs[&"knockdown"] = {"length": 0.7, "keys": [
		[0.0, guard],
		[0.15, {&"Hips": Vector3(25, 0, 0), &"Head": Vector3(32, 0, 0), &"ShoulderL": Vector3(120, 0, -40), &"ShoulderR": Vector3(120, 0, 40),
			&"KneeL": Vector3(-40, 0, 0), &"KneeR": Vector3(-45, 0, 0), &"_hips": Vector3(0, -0.12, 0.1)}],
		[0.4, _with(on_back, {&"Hips": Vector3(75, 0, 0), &"_hips": Vector3(0, lie + 0.1, 0.35), &"HipL": Vector3(45, 0, 0), &"HipR": Vector3(35, 0, 0)})],
		[0.55, _with(on_back, {&"Head": Vector3(-20, 10, 0)})],
		[0.62, _with(on_back, {&"_hips": Vector3(0, lie + 0.03, 0.42), &"Hips": Vector3(86, 0, 0)})],
		[0.7, on_back],
	]}
	defs[&"down"] = {"length": 2.4, "loop": true, "keys": [
		[0.0, on_back],
		[1.2, _with(on_back, {&"Head": Vector3(-14, 12, 0), &"Chest": Vector3(-5, 0, 0), &"ShoulderL": Vector3(25, 0, -45), &"KneeL": Vector3(-45, 0, 0)})],
		[2.4, on_back],
	]}
	defs[&"get_up"] = {"length": 0.9, "keys": [
		[0.0, on_back],
		[0.3, _with(on_back, {&"Spine": Vector3(-70, 0, 0), &"Head": Vector3(-10, 0, 0), &"HipL": Vector3(60, 0, 0), &"KneeL": Vector3(-100, 0, 0),
			&"ShoulderL": Vector3(-20, 0, -20), &"ShoulderR": Vector3(-20, 0, 20)})],
		[0.6, {&"Spine": Vector3(-30, 0, 0), &"HipL": Vector3(85, 0, 0), &"KneeL": Vector3(-125, 0, 0), &"HipR": Vector3(75, 0, 0), &"KneeR": Vector3(-120, 0, 0),
			&"ShoulderL": Vector3(40, 0, -10), &"ShoulderR": Vector3(40, 0, 10), &"_hips": Vector3(0, -0.36, 0.12)}],
		[0.9, guard],
	]}
	defs[&"crawl"] = {"length": 1.4, "loop": true, "keys": [[0.0, crawl_a], [0.7, crawl_b], [1.4, crawl_a]]}
	var limp := _with(on_back, {&"ShoulderL": Vector3(140, 0, -50), &"ElbowL": Vector3(20, 0, 0), &"ShoulderR": Vector3(30, 0, 72),
		&"ElbowR": Vector3(10, 0, 0), &"Head": Vector3(0, -62, 0), &"HipL": Vector3(25, 0, -16), &"KneeL": Vector3(-52, 0, 0), &"HipR": Vector3(0, 0, 12),
		&"KneeR": Vector3(0, 0, 0)})
	defs[&"ko"] = {"length": 1.0, "keys": [
		[0.0, guard],
		[0.12, _with(guard, {&"Head": Vector3(42, 0, 0), &"Spine": Vector3(18, 0, 0), &"ShoulderL": Vector3(20, 0, -20), &"ShoulderR": Vector3(20, 0, 20),
			&"ElbowL": Vector3(20, 0, 0), &"ElbowR": Vector3(20, 0, 0)})],
		[0.35, {&"Hips": Vector3(45, 0, 0), &"Head": Vector3(30, 0, 0), &"ShoulderL": Vector3(60, 0, -30), &"ShoulderR": Vector3(60, 0, 30),
			&"KneeL": Vector3(-60, 0, 0), &"KneeR": Vector3(-50, 0, 0), &"_hips": Vector3(0, lie * 0.5, 0.22)}],
		[0.6, _with(limp, {&"Hips": Vector3(92, 0, 0), &"_hips": Vector3(0, lie, 0.5), &"Head": Vector3(0, -20, 0)})],
		[0.7, _with(limp, {&"Hips": Vector3(84, 0, 0), &"_hips": Vector3(0, lie + 0.04, 0.5)})],
		[1.0, _with(limp, {&"_hips": Vector3(0, lie, 0.5)})],
	]}
	var sup := _with(relaxed, {&"ShoulderR": Vector3(105, 0, -26), &"ElbowR": Vector3(138, 0, 0)})
	defs[&"drink"] = {"length": 1.6, "keys": [
		[0.0, guard], [0.35, sup],
		[0.6, _with(sup, {&"Head": Vector3(32, 0, 0), &"Spine": Vector3(12, 0, 0), &"ShoulderR": Vector3(132, 0, -22), &"ElbowR": Vector3(122, 0, 0)})],
		[1.1, _with(sup, {&"Head": Vector3(36, 0, 0), &"Spine": Vector3(14, 0, 0), &"ShoulderR": Vector3(138, 0, -20), &"ElbowR": Vector3(118, 0, 0)})],
		[1.35, _with(relaxed, {&"ShoulderR": Vector3(40, 0, 0), &"ElbowR": Vector3(90, 0, 0), &"Head": Vector3(-6, 0, 0)})],
		[1.6, relaxed],
	]}
	var bite := _with(relaxed, {&"ShoulderR": Vector3(96, 0, -26), &"ElbowR": Vector3(142, 0, 0), &"Head": Vector3(-10, 0, 0), &"Spine": Vector3(-6, 0, 0)})
	var chew := _with(relaxed, {&"ShoulderR": Vector3(55, 0, -12), &"ElbowR": Vector3(100, 0, 0), &"Head": Vector3(4, 0, 0), &"Spine": Vector3(-4, 0, 0)})
	defs[&"eat"] = {"length": 1.6, "keys": [
		[0.0, guard], [0.3, bite], [0.55, chew], [0.75, _with(chew, {&"Head": Vector3(-4, 0, 0)})], [0.95, bite],
		[1.25, chew], [1.6, relaxed],
	]}
	var duck := _with(guard, {&"Spine": Vector3(-26, 0, 20), &"HipL": Vector3(32, 0, -8), &"KneeL": Vector3(-55, 0, 0),
		&"HipR": Vector3(28, 0, 8), &"KneeR": Vector3(-50, 0, 0), &"_hips": Vector3(0, -0.2, 0)})
	defs[&"dodge"] = {"length": 0.45, "keys": [
		[0.0, guard], [0.12, duck], [0.28, _with(duck, {&"Spine": Vector3(-22, 0, -16), &"_hips": Vector3(0, -0.18, 0)})], [0.45, guard],
	]}
	var arms_up := {&"ShoulderL": Vector3(165, 0, -26), &"ElbowL": Vector3(20, 0, 0), &"ShoulderR": Vector3(165, 0, 26),
		&"ElbowR": Vector3(20, 0, 0), &"Head": Vector3(25, 0, 0), &"Spine": Vector3(10, 0, 0)}
	defs[&"cheer"] = {"length": 1.2, "keys": [
		[0.0, guard], [0.25, arms_up],
		[0.5, _with(arms_up, {&"ShoulderR": Vector3(140, 0, 32), &"ElbowR": Vector3(70, 0, 0), &"_hips": Vector3(0, 0.04, 0)})],
		[0.75, arms_up], [1.2, guard],
	]}
	var beckon := _with(relaxed, {&"Spine": Vector3(10, 0, 0), &"Chest": Vector3(8, 0, 0), &"Head": Vector3(-8, 0, 0),
		&"ShoulderR": Vector3(68, 0, 4), &"ElbowR": Vector3(25, 0, 0), &"ShoulderL": Vector3(10, 0, -30), &"ElbowL": Vector3(10, 0, 0)})
	defs[&"taunt"] = {"length": 1.4, "keys": [
		[0.0, guard], [0.25, beckon], [0.45, _with(beckon, {&"ElbowR": Vector3(95, 0, 0)})], [0.65, beckon],
		[0.85, _with(beckon, {&"ElbowR": Vector3(95, 0, 0)})], [1.05, beckon], [1.4, guard],
	]}
	return defs


# --- Primitives ------------------------------------------------------------

func _joint(joint_name: StringName, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = joint_name
	j.position = pos
	parent.add_child(j)
	_joints[joint_name] = j
	return j


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, pos, color)


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 10
	m.rings = 6
	return _mesh(parent, m, pos, color)


## A hemisphere tipped back so it sits on the crown of the head (hair, hats).
func _cap(parent: Node3D, radius: float, pos: Vector3, tilt: float, color: Color) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius
	m.is_hemisphere = true
	m.radial_segments = 10
	m.rings = 4
	var mi := _mesh(parent, m, pos, color)
	mi.rotation_degrees.x = tilt
	return mi


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 8
	m.rings = 2
	return _mesh(parent, m, pos, color)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, top := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top < 0.0 else top
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	return _mesh(parent, m, pos, color)
