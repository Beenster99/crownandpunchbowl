@tool
class_name CharacterRig
extends Node3D
## The shared humanoid rig. Every farmer, punter, copper and member of bar staff is a
## rigged, skinned model built in Blender (tools/blender/build_characters.py) on one shared
## armature, recoloured and dressed here from a CharacterLook. The animations are
## generated from pose data at load time and retargeted onto each model's skeleton, and
## knockouts can hand over to a physics ragdoll.
##
## Gameplay code only talks to the API below (play_state, play_move, set_move_speed,
## get_socket, set_blood, break_nose, start_ragdoll). See docs/CHARACTERS.md.
##
## Facing is -Z, the same as the placeholder player. The rig's origin is between the feet.

signal animation_finished(anim_name: StringName)

## Every animation in the set. Real art must provide all of these names.
const ANIMATIONS: Array[StringName] = [
	&"idle", &"walk", &"punch_l", &"punch_r", &"kick", &"headbutt", &"windup", &"swing",
	&"throw", &"grab", &"hold", &"held_struggle", &"hit_front", &"hit_back", &"stagger",
	&"knockdown", &"down", &"get_up", &"crawl", &"ko", &"drink", &"eat", &"dodge",
	&"cheer", &"taunt", &"block", &"hook_l", &"hook_r", &"uppercut_r", &"hit_left", &"hit_right",
	# Calm, before anyone kicks off: relaxed stances, a pint, chatting, staff polishing.
	&"idle_relaxed", &"idle_pint", &"idle_chat", &"idle_polish", &"walk_relaxed",
]

## The calm idles a character picks from (by seed). Staff polish glasses instead.
const CALM_IDLES: Array[StringName] = [&"idle_relaxed", &"idle_pint", &"idle_relaxed"]
## Standing loops that guard/talk changes switch between.
const STANDING: Array[StringName] = [&"idle", &"walk", &"idle_relaxed", &"idle_pint", &"idle_chat", &"idle_polish", &"walk_relaxed"]

## Fighter state name (lower case, as in Fighter.State) -> animation.
const STATE_ANIMS := {
	"idle": &"idle", "attack": &"punch_r", "windup": &"windup", "stagger": &"stagger",
	"down": &"knockdown", "crawl": &"crawl", "ko": &"ko", "held": &"held_struggle",
	"grabbing": &"grab", "dodge": &"dodge", "block": &"block",
}

## Move names (as in Events.hit_landed "move") -> animation. "punch" alternates hands.
const MOVE_ANIMS := {
	"punch_l": &"punch_l", "punch_r": &"punch_r", "kick": &"kick", "headbutt": &"headbutt",
	"swing": &"swing", "throw": &"throw", "grab": &"grab", "drink": &"drink", "eat": &"eat",
	"cheer": &"cheer", "taunt": &"taunt",
	# Move ids from scripts/combat/moves.gd. Placeholders reuse the nearest animation.
	"jab": &"punch_l", "cross": &"punch_r", "hook": &"hook_r", "uppercut": &"uppercut_r",
	"hook_l": &"hook_l", "hook_r": &"hook_r", "uppercut_r": &"uppercut_r",
	"haymaker": &"punch_r", "counter": &"punch_r", "counter_whiff": &"dodge", "shove": &"punch_l",
	"knee": &"kick", "stomp": &"kick", "baton": &"swing",
}

## One-shots that hand over to another animation when they finish.
const CHAINS := {&"knockdown": &"down", &"grab": &"hold"}
## One-shots that go back to idle (or walk) when they finish.
const RETURNS_TO_IDLE: Array[StringName] = [
	&"punch_l", &"punch_r", &"kick", &"headbutt", &"swing", &"throw", &"hit_front",
	&"hit_back", &"stagger", &"get_up", &"drink", &"eat", &"dodge", &"cheer", &"taunt",
	&"hook_l", &"hook_r", &"uppercut_r", &"hit_left", &"hit_right",
]
## Lying on the floor. Drunken sway is switched off for these.
const ON_FLOOR: Array[StringName] = [&"knockdown", &"down", &"crawl", &"ko"]

## Attachment points for weapons, pints and held enemies.
const SOCKETS: Array[StringName] = [&"hand_r", &"hand_l", &"head", &"chest", &"hold_point"]

## Every animated bone. Fingers, collarbones, feet, jaw and brows are mostly filled in
## by _expand() from the body pose and a few scalars.
const ANIM_JOINTS: Array[StringName] = [
	&"Hips", &"Spine", &"Spine2", &"Chest", &"Neck", &"Head", &"Jaw", &"BrowL", &"BrowR",
	&"ClavicleL", &"ShoulderL", &"ElbowL", &"HandL", &"Thumb1L", &"Thumb2L", &"Index1L", &"Index2L", &"Fingers1L", &"Fingers2L",
	&"ClavicleR", &"ShoulderR", &"ElbowR", &"HandR", &"Thumb1R", &"Thumb2R", &"Index1R", &"Index2R", &"Fingers1R", &"Fingers2R",
	&"HipL", &"KneeL", &"FootL", &"HipR", &"KneeR", &"FootR",
]
## Follow-through: seconds each joint trails the pose. The hips lead and the chest, head,
## jaw and fingers follow, so a punch starts in the legs and a blow rolls up into the head.
const OVERLAP := {
	&"Spine2": 0.015, &"Chest": 0.03, &"Neck": 0.04, &"Head": 0.06, &"Jaw": 0.08, &"BrowL": 0.05, &"BrowR": 0.05,
	&"ClavicleL": 0.02, &"ClavicleR": 0.02, &"HandL": 0.02, &"HandR": 0.02,
	&"Thumb1L": 0.03, &"Thumb2L": 0.04, &"Index1L": 0.03, &"Index2L": 0.04, &"Fingers1L": 0.03, &"Fingers2L": 0.04,
	&"Thumb1R": 0.03, &"Thumb2R": 0.04, &"Index1R": 0.03, &"Index2R": 0.04, &"Fingers1R": 0.03, &"Fingers2R": 0.04,
}
## Animations are baked from the keyed poses at this rate.
const BAKE_FPS := 30.0

const MODEL_DIR := "res://assets/models/characters/"
## Physics layer 7 ("ragdoll"): ragdolls hit the world but not players, NPCs or each other.
const RAGDOLL_LAYER := 1 << 6
const RAGDOLL_MASK := 1

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
## KO hands over to the ragdoll instead of the ko animation.
@export var ragdoll_on_ko := true
## How hard a KO punch throws the body, in N·s per unit of hit direction.
@export var ragdoll_impulse := 30.0

## Fists up. Off while the pub is calm: idles and walking are relaxed until a fight is on.
## FighterVisual raises it when the fighter or someone near them gets stuck in.
var guard := false
## Chatting with someone: gestures instead of the calm idle.
var talking := false
## Bar staff: polish a glass instead of the calm idles.
var staff := false

var anim: AnimationPlayer
var skeleton: Skeleton3D
var current: StringName = &""
var ragdolling := false

var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _sockets := {}
var _bone := {}
var _rest_global := {}
var _scale := 1.0
var _lie := 0.0
var _time := 0.0
var _moving := false
var _next_punch_left := false
var _blood := 0.0
var _blood_nodes: Array[Node3D] = []
var _last_hit := Vector3.ZERO
var _sim: PhysicalBoneSimulator3D
var _physical := {}
var _model_path := ""
var _timing := {}  # anim name -> Vector2(load, contact)

static var _lib_cache := {}


func _ready() -> void:
	if look == null and look_id != "":
		look = CharacterLooks.by_id(look_id, look_seed)
	else:
		rebuild()


func _process(delta: float) -> void:
	if _model == null or look == null:
		return
	_time += delta
	var w := 0.0 if ON_FLOOR.has(current) or ragdolling else look.sway
	_model.rotation.z = sin(_time * 1.3) * 0.07 * w
	_model.rotation.x = sin(_time * 0.85 + 1.0) * 0.04 * w


# --- Public API ------------------------------------------------------------

## Plays an animation by name with a short blend.
func play(anim_name: StringName, blend := 0.1) -> void:
	if anim == null or not anim.has_animation(anim_name):
		push_warning("CharacterRig: no animation '%s'" % anim_name)
		return
	if ragdolling:
		stop_ragdoll()
	current = anim_name
	anim.speed_scale = 1.0
	anim.play(anim_name, blend)
	if STANDING.has(anim_name) or anim_name == &"hold":
		anim.seek(randf() * anim.current_animation_length if not Engine.is_editor_hint() else 0.0, true)


## Plays the animation for a Fighter state, by name: "stagger", "KO", "held"...
func play_state(state_name: String) -> void:
	var key := state_name.to_lower()
	if key == "ko" and ragdoll_on_ko and not Engine.is_editor_hint():
		var dir := _last_hit if _last_hit.length() > 0.01 else global_basis.z
		start_ragdoll(dir.normalized() * ragdoll_impulse + Vector3.UP * ragdoll_impulse * 0.25)
	elif key == "idle":
		play(_standing_anim())
	elif STATE_ANIMS.has(key):
		play(STATE_ANIMS[key])
	else:
		push_warning("CharacterRig: no animation for state '%s'" % state_name)


## Plays an attack or action by move name. "punch" alternates left and right.
func play_move(move: String) -> void:
	guard = true
	if move == "punch":
		play(&"punch_l" if _next_punch_left else &"punch_r", 0.05)
		_next_punch_left = not _next_punch_left
	elif MOVE_ANIMS.has(move):
		play(MOVE_ANIMS[move], 0.05)
	else:
		push_warning("CharacterRig: no animation for move '%s'" % move)


## Plays a hit reaction. Pass the hit's world direction (attacker to victim) so a KO
## that follows throws the ragdoll the right way.
func play_hit(from_front := true, heavy := false, direction := Vector3.ZERO) -> void:
	guard = true
	if direction != Vector3.ZERO:
		_last_hit = direction
	if heavy:
		play(&"stagger", 0.04)
		return
	if not from_front:
		play(&"hit_back", 0.03)
		return
	# From the front: a blow coming across (a hook) whips the head round to that side.
	var side := 0.0
	if direction.length() > 0.01 and is_inside_tree():
		side = global_basis.x.normalized().dot(direction.normalized())
	if side > 0.45:
		play(&"hit_left", 0.03)  # pushed to our right: struck on the left
	elif side < -0.45:
		play(&"hit_right", 0.03)
	else:
		play(&"hit_front", 0.03)


## Call every frame with horizontal speed in m/s. Switches between idle and walk.
func set_move_speed(speed: float) -> void:
	_moving = speed > 0.2
	_refresh_standing(0.15)
	if current == &"walk" or current == &"walk_relaxed":
		anim.speed_scale = clampf(speed / (2.6 if current == &"walk" else 2.0), 0.6, 2.2)


## Fists up (a fight is on) or relaxed (calm pub). Blends over if standing or walking.
func set_guard(up: bool) -> void:
	if up == guard:
		return
	guard = up
	_refresh_standing(0.35)


## Chatting: gestures while standing calm.
func set_talking(on: bool) -> void:
	if on == talking:
		return
	talking = on
	_refresh_standing(0.4)


## The idle or walk that fits right now.
func _standing_anim() -> StringName:
	if _moving:
		return &"walk" if guard else &"walk_relaxed"
	if guard:
		return &"idle"
	if talking:
		return &"idle_chat"
	if staff:
		return &"idle_polish"
	return CALM_IDLES[absi(look_seed) % CALM_IDLES.size()]


func _refresh_standing(blend: float) -> void:
	if anim == null or not STANDING.has(current):
		return
	var want := _standing_anim()
	if want != current:
		play(want, blend)


## When a strike's wind-up ends (the coiled, loaded pose), in seconds. 0 if it has none.
func load_time(anim_name: StringName) -> float:
	return (_timing.get(anim_name, Vector2.ZERO) as Vector2).x


## When a strike's blow lands, in seconds from its start. 0 if it isn't a strike.
func contact_time(anim_name: StringName) -> float:
	return (_timing.get(anim_name, Vector2.ZERO) as Vector2).y


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
	if skeleton and _bone.has(&"Nose"):
		var i: int = _bone[&"Nose"]
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion() * Quaternion(Vector3.FORWARD, 0.45))
	set_blood(maxf(_blood, 0.45))


## The head's height in world units for this look, standing. Handy for UI and camera.
func head_height() -> float:
	if skeleton == null:
		return 1.7
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_bone[&"Head"])).origin.y - global_position.y


## Goes limp and hands the body to physics. impulse is in world space, applied to the chest.
## The ragdoll is cosmetic: every peer runs its own, gameplay keeps using the fighter's body.
func start_ragdoll(impulse := Vector3.ZERO) -> void:
	if _sim == null:
		return
	anim.pause()
	ragdolling = true
	current = &"ko"
	_sim.active = true
	_sim.influence = 1.0
	_sim.physical_bones_start_simulation()
	if impulse != Vector3.ZERO:
		var chest: PhysicalBone3D = _physical.get(&"Chest")
		var head: PhysicalBone3D = _physical.get(&"Head")
		if chest:
			chest.apply_central_impulse(impulse * 0.7)
		if head:
			head.apply_central_impulse(impulse * 0.3)


## Ends the ragdoll and goes back to animation (call play() or play_state() next).
func stop_ragdoll() -> void:
	if _sim == null or not ragdolling:
		return
	_sim.physical_bones_stop_simulation()
	_sim.active = false
	ragdolling = false
	skeleton.reset_bone_poses()


## A bone's current position in world space (up to date even before sockets refresh).
func bone_position(bone: StringName) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_bone[bone])).origin


## Where the ragdoll's hips ended up, in world space. Move the fighter here before get_up.
func ragdoll_hips_position() -> Vector3:
	var pb: PhysicalBone3D = _physical.get(&"Hips")
	if ragdolling and pb:
		return pb.global_position
	return bone_position(&"Hips")


# --- Building --------------------------------------------------------------

func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_meshes.clear()
	_sockets.clear()
	_bone.clear()
	_rest_global.clear()
	_blood_nodes.clear()
	_physical.clear()
	_sim = null
	ragdolling = false
	skeleton = null
	if look == null:
		return
	var path := MODEL_DIR + (look.model if look.model != "" else look.id) + ".glb"
	if not ResourceLoader.exists(path):
		push_error("CharacterRig: missing model %s (run tools/blender/build_characters.py)" % path)
		return
	_model_path = path
	_model = (load(path) as PackedScene).instantiate()
	_model.name = "Model"
	var s := look.height / maxf(look.model_height, 0.01)
	var g := look.girth / maxf(look.model_girth, 0.01)
	_model.scale = Vector3(s * sqrt(g), s, s * sqrt(g))
	add_child(_model)
	skeleton = _find_skeleton(_model)
	for i in skeleton.get_bone_count():
		_bone[StringName(skeleton.get_bone_name(i))] = i
		_rest_global[i] = skeleton.get_bone_global_rest(i)
	_scale = look.model_height
	var hips_rest: Vector3 = (_rest_global[_bone[&"Hips"]] as Transform3D).origin
	_lie = ((0.15 * look.girth + 0.04 * look.belly) * look.model_height - hips_rest.y) / _scale
	_dress()
	_build_sockets()
	_build_animations()
	if not Engine.is_editor_hint():
		_build_ragdoll()
	set_blood(_blood)
	if start_animation != &"" and anim.has_animation(start_animation):
		# The default "idle" means "standing about": relaxed unless the guard is up.
		play(_standing_anim() if start_animation == &"idle" else start_animation, 0.0)
		anim.advance(0.0)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


## Shows the pieces this look wears and recolours every surface from the look.
func _dress() -> void:
	var L := look
	var colours := {
		&"skin": L.skin, &"flush": L.flush, &"lips": L.flush.lerp(Color("a8474a"), 0.6) if L.feminine else L.skin.lerp(Color("6a3028"), 0.45),
		&"eye_white": Color("f2ede2"), &"eye_dark": Color("1a1412"), &"hair": L.hair_color, &"beard": L.beard_color,
		&"stubble": L.skin.lerp(L.beard_color, 0.45), &"brow": (L.hair_color if L.hair != CharacterLook.Hair.BALD else L.beard_color).darkened(0.15),
		&"top": L.top_color, &"trim": L.top_trim, &"over": L.over_color, &"trousers": L.trousers_color,
		&"boots": L.boots_color, &"hat": L.hat_color, &"neckerchief": L.neckerchief_color, &"metal": Color("c8ccd4"),
		&"leather": Color("6b4a2a"), &"dark": Color("161616"), &"white": Color("ececec"), &"socks": Color("6a6a60"),
		&"blood": Color("7a0b0b"), &"hivis_band": Color("b9bcc4"),
	}
	var mats := {}
	var wanted := {
		"Hair_": CharacterLook.Hair.find_key(L.hair), "Beard_": CharacterLook.Beard.find_key(L.beard),
		"Hat_": CharacterLook.Hat.find_key(L.hat), "Top_": CharacterLook.Top.find_key(L.top),
	}
	var blood := {}
	for mi in _all_meshes(_model):
		var n := String(mi.name)
		var show := true
		for prefix in wanted:
			if n.begins_with(prefix):
				show = n == prefix + String(wanted[prefix])
		if n.begins_with("Blood_"):
			blood[n] = mi
		mi.visible = show
		_meshes.append(mi)
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var key := StringName(src.resource_name if src else "top")
			if not mats.has(key):
				mats[key] = _material(key, colours.get(key, Color.MAGENTA))
			mi.set_surface_override_material(i, mats[key])
	for n in ["Blood_Nose", "Blood_Face", "Blood_Shirt", "Blood_Cheek"]:
		if blood.has(n):
			_blood_nodes.append(blood[n])


func _material(key: StringName, colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.82
	match key:
		&"eye_white", &"eye_dark":
			m.roughness = 0.25
		&"metal":
			m.metallic = 0.8
			m.roughness = 0.35
		&"blood":
			m.roughness = 0.3
		&"skin", &"flush", &"lips":
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.6
		&"top":
			if look.top == CharacterLook.Top.SHIRT:
				m.albedo_color = Color.WHITE
				m.albedo_texture = _check_texture(look.top_color, look.top_trim)
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 5.0
	return m


## A tattersall check for shirts, mapped triplanar so the models need no UVs.
static func _check_texture(base: Color, line: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var c := base
			var on_x := x % 16 < 3
			var on_y := y % 16 < 3
			if on_x and on_y:
				c = base.lerp(line, 0.8)
			elif on_x or on_y:
				c = base.lerp(line, 0.45)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _all_meshes(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_all_meshes(c, out)
	return out


func _build_sockets() -> void:
	for pair in [[&"hand_r", &"HandR"], [&"hand_l", &"HandL"], [&"head", &"Head"], [&"chest", &"Chest"]]:
		var ba := BoneAttachment3D.new()
		ba.name = "Socket_" + String(pair[0])
		ba.bone_name = pair[1]
		skeleton.add_child(ba)
		_sockets[pair[0]] = ba
	# Where a held enemy goes: in front of the chest.
	var chest_rest: Transform3D = _rest_global[_bone[&"Chest"]]
	var hold := Node3D.new()
	hold.name = "HoldPoint"
	var want := Transform3D(Basis(), chest_rest.origin + Vector3(0, 0.1, -(0.25 * look.model_girth + 0.32)) * _scale)
	hold.transform = chest_rest.affine_inverse() * want
	(_sockets[&"chest"] as Node3D).add_child(hold)
	_sockets[&"hold_point"] = hold


# --- Ragdoll ---------------------------------------------------------------

func _build_ragdoll() -> void:
	_sim = PhysicalBoneSimulator3D.new()
	_sim.name = "Ragdoll"
	_sim.active = false
	skeleton.add_child(_sim)
	var t := look.limb_thickness * _scale
	var g := look.girth * _scale
	# bone: [radius, cone swing degrees, twist degrees, mass]. Spine2, the collarbones, hands,
	# fingers and face bones have no body of their own: they ride along with their parents.
	var spec := {
		&"Hips": [0.12 * g, 0.0, 0.0, 12.0], &"Spine": [0.12 * g, 25.0, 15.0, 9.0],
		&"Chest": [0.14 * g, 25.0, 15.0, 12.0],
		&"Head": [0.15 * look.head_size * _scale, 40.0, 40.0, 5.0],
		&"ShoulderL": [0.065 * t, 80.0, 30.0, 2.5], &"ShoulderR": [0.065 * t, 80.0, 30.0, 2.5],
		&"ElbowL": [0.055 * t, 70.0, 10.0, 1.8], &"ElbowR": [0.055 * t, 70.0, 10.0, 1.8],
		&"HipL": [0.085 * t, 60.0, 20.0, 7.0], &"HipR": [0.085 * t, 60.0, 20.0, 7.0],
		&"KneeL": [0.07 * t, 60.0, 5.0, 4.0], &"KneeR": [0.07 * t, 60.0, 5.0, 4.0],
	}
	for bone_name in spec:
		var i: int = _bone[bone_name]
		var length := _bone_length(i)
		var radius: float = spec[bone_name][0]
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + String(bone_name)
		pb.bone_name = bone_name
		pb.collision_layer = RAGDOLL_LAYER
		pb.collision_mask = RAGDOLL_MASK
		pb.mass = spec[bone_name][3]
		pb.friction = 0.8
		pb.linear_damp = 0.4
		pb.angular_damp = 2.5
		# The body sits halfway along the bone; the joint sits at the bone's root.
		pb.body_offset = Transform3D(Basis(), Vector3(0, length * 0.5, 0))
		pb.joint_offset = Transform3D(Basis(), Vector3(0, -length * 0.5, 0))
		if bone_name != &"Hips":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(length + radius * 0.5, radius * 2.0)
		col.shape = cap
		pb.add_child(col)
		_sim.add_child(pb)
		if bone_name != &"Hips":
			pb.set("joint_constraints/swing_span", spec[bone_name][1])
			pb.set("joint_constraints/twist_span", spec[bone_name][2])
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		_physical[bone_name] = pb


func _bone_length(i: int) -> float:
	var kids := skeleton.get_bone_children(i)
	var best := 0.0
	for k in kids:
		var n := skeleton.get_bone_name(k)
		if n in ["Nose", "Jaw", "BrowL", "BrowR", "ClavicleL", "ClavicleR"] or n.begins_with("Thumb") \
				or n.begins_with("Index") or n.begins_with("Fingers"):
			continue
		best = maxf(best, skeleton.get_bone_rest(k).origin.length())
	if best > 0.0:
		return best
	match skeleton.get_bone_name(i):
		"Head":
			return 0.3 * look.head_size * _scale
		_:
			return 0.12 * _scale


# --- Animation -------------------------------------------------------------

func _build_animations() -> void:
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	add_child(anim)
	anim.root_node = anim.get_path_to(_model)
	# Baking is the slow part, and every character built from the same model and build gets
	# the same result, so a crowd shares one library per model.
	var key := "%s|%.2f|%.3f" % [_model_path, _lie, _scale]
	if not _lib_cache.has(key) or Engine.is_editor_hint():
		var lib := AnimationLibrary.new()
		var defs := _anim_defs()
		var timing := {}
		for anim_name in defs:
			lib.add_animation(anim_name, _make_animation(defs[anim_name]))
			timing[anim_name] = Vector2(float(defs[anim_name].get("load", 0.0)), float(defs[anim_name].get("contact", 0.0)))
		_lib_cache[key] = [lib, timing]
	anim.add_animation_library(&"", _lib_cache[key][0])
	_timing = _lib_cache[key][1]
	anim.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(anim_name)
	if ragdolling:
		return
	if CHAINS.has(anim_name):
		play(CHAINS[anim_name], 0.15)
	elif auto_return_to_idle and RETURNS_TO_IDLE.has(anim_name):
		play(_standing_anim(), 0.15)


## Pose data rotates each joint about the character's own axes (x right, y up, z back),
## composing down the chain. A bone's local pose rotation that gives the same result is
## rest_local * (M^-1 * q * M), where M is the bone's rest orientation in skeleton space.
##
## Poses are keyed, then baked at BAKE_FPS. Between keys the motion follows a spline
## through the neighbouring keys (no dead stop at every key), with an optional ease on the
## way into a key: "io" settles into it (loads, holds), "snap" accelerates into it (the
## impact), "out" decelerates (recoveries), "lin" is even. Joints further from the hips lag
## a little behind (OVERLAP), so hips lead, then the chest, then the head: the motion flows
## through the body instead of every joint moving at once.
func _make_animation(def: Dictionary) -> Animation:
	var a := Animation.new()
	var length: float = def["length"]
	a.length = length
	var looping: bool = def.get("loop", false)
	a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var keys: Array = def["keys"]
	var times: Array[float] = []
	var eases: Array[String] = []
	var poses: Array[Dictionary] = []
	for k in keys:
		times.append(float(k[0]))
		eases.append(String(k[2]) if k.size() > 2 else "")
		poses.append(_expand(k[1]))
	var skel_path := String(_model.get_path_to(skeleton))
	var samples := maxi(2, int(ceil(length * BAKE_FPS)) + 1)
	for joint in ANIM_JOINTS:
		if not _bone.has(joint):
			continue
		var i: int = _bone[joint]
		var rest_local := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		var m := (_rest_global[i] as Transform3D).basis.get_rotation_quaternion()
		var mi := m.inverse()
		var qs: Array[Quaternion] = []
		for p in poses:
			qs.append(Quaternion.from_euler((p.get(joint, Vector3.ZERO) as Vector3) * (PI / 180.0)))
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("%s:%s" % [skel_path, joint]))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		var lag: float = OVERLAP.get(joint, 0.0)
		for s in samples:
			var t := minf(length * s / float(samples - 1), length)
			var q := _sample_rot(qs, times, eases, t - lag, length, looping)
			a.rotation_track_insert_key(tr, t, rest_local * (mi * q * m))
	var hips: int = _bone[&"Hips"]
	var pos := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos, NodePath("%s:Hips" % skel_path))
	var rest := skeleton.get_bone_rest(hips).origin
	var offs: Array[Vector3] = []
	for p in poses:
		offs.append(p.get(&"_hips", Vector3.ZERO))
	for s in samples:
		var t := minf(length * s / float(samples - 1), length)
		a.position_track_insert_key(pos, t, rest + _sample_vec(offs, times, eases, t, length, looping) * _scale)
	return a


## Where in the key list time t falls: [index of the key before, weight to the next].
func _segment(times: Array[float], eases: Array[String], t: float, length: float, looping: bool) -> Array:
	var n := times.size()
	if looping:
		t = fposmod(t, length)
	else:
		t = clampf(t, 0.0, length)
	var k := 0
	while k < n - 2 and t > times[k + 1]:
		k += 1
	var span := maxf(times[k + 1] - times[k], 0.0001)
	var u := clampf((t - times[k]) / span, 0.0, 1.0)
	match eases[k + 1]:
		"io":
			u = u * u * (3.0 - 2.0 * u)
		"snap":
			u = u * u * u
		"in":
			u = u * u
		"out":
			u = 1.0 - (1.0 - u) * (1.0 - u)
	return [k, u]


func _neighbours(n: int, k: int, looping: bool) -> Array[int]:
	# Keys k-1, k, k+1, k+2. Loops repeat their first key as the last, so skip it when wrapping.
	var pre := k - 1
	var post := k + 2
	if looping:
		if pre < 0:
			pre = n - 2
		if post > n - 1:
			post = 1
	else:
		pre = maxi(pre, 0)
		post = mini(post, n - 1)
	return [pre, k, k + 1, post]


func _sample_rot(qs: Array[Quaternion], times: Array[float], eases: Array[String], t: float, length: float, looping: bool) -> Quaternion:
	var seg := _segment(times, eases, t, length, looping)
	var nb := _neighbours(qs.size(), seg[0], looping)
	var a := qs[nb[1]]
	var b := qs[nb[2]]
	if eases[nb[2]] == "lin":
		return a.slerp(b, seg[1])
	return a.spherical_cubic_interpolate(b, qs[nb[0]], qs[nb[3]], seg[1])


func _sample_vec(vs: Array[Vector3], times: Array[float], eases: Array[String], t: float, length: float, looping: bool) -> Vector3:
	var seg := _segment(times, eases, t, length, looping)
	var nb := _neighbours(vs.size(), seg[0], looping)
	if eases[nb[2]] == "lin":
		return vs[nb[1]].lerp(vs[nb[2]], seg[1])
	return vs[nb[1]].cubic_interpolate(vs[nb[2]], vs[nb[0]], vs[nb[3]], seg[1])


## Fills in the joints a pose leaves to the rig: the spine bend shared over two bones, the
## head turn shared with the neck, collarbones that follow the arms (a punch reaches with the
## shoulder), fingers from "_fistL"/"_fistR" (0 open, 1 clenched), the jaw from "_jaw",
## brows from "_brow" (+1 scowl, -1 wince) and feet kept flat on the floor unless "_heelL"/
## "_heelR" lifts the heel (the pivot on a cross).
static func _expand(pose: Dictionary) -> Dictionary:
	var p := pose.duplicate()
	if not p.has(&"Spine2"):
		var sp: Vector3 = p.get(&"Spine", Vector3.ZERO)
		p[&"Spine"] = sp * 0.5
		p[&"Spine2"] = sp * 0.5
	if not p.has(&"Neck"):
		var hd: Vector3 = p.get(&"Head", Vector3.ZERO)
		p[&"Neck"] = hd * 0.35
		p[&"Head"] = hd * 0.65
	for s in ["L", "R"]:
		var side := -1.0 if s == "L" else 1.0
		var sh: Vector3 = p.get(StringName("Shoulder" + s), Vector3.ZERO)
		if not p.has(StringName("Clavicle" + s)):
			var reach := clampf((sh.x - 40.0) * 0.2, -4.0, 12.0)
			var lift := clampf((sh.x - 100.0) * 0.15, 0.0, 10.0) + clampf((sh.z * side - 40.0) * 0.2, 0.0, 10.0)
			p[StringName("Clavicle" + s)] = Vector3(0, reach * side, lift * side)
		var f: float = (p.get(StringName("_fist" + s), Vector3(0.25, 0, 0)) as Vector3).x
		var c := -side  # curl towards the palm
		for bone in [["Index1", 80.0], ["Index2", 95.0], ["Fingers1", 88.0], ["Fingers2", 100.0]]:
			var key := StringName(bone[0] + s)
			if not p.has(key):
				p[key] = Vector3(0, 0, bone[1] * f * c)
		if not p.has(StringName("Thumb1" + s)):
			# Fold the thumb across the front of the curled fingers.
			# (Fitted so the tip lands over the middle of the curled fingers.)
			p[StringName("Thumb1" + s)] = Vector3(-40.0 * f, 90.0 * f * c, -40.0 * f * c)
			p[StringName("Thumb2" + s)] = Vector3(-24.0 * f, 54.0 * f * c, -24.0 * f * c)
		var foot := StringName("Foot" + s)
		if not p.has(foot):
			var hips_x: float = (p.get(&"Hips", Vector3.ZERO) as Vector3).x
			if absf(hips_x) < 30.0:
				var leg: float = hips_x + (p.get(StringName("Hip" + s), Vector3.ZERO) as Vector3).x \
					+ (p.get(StringName("Knee" + s), Vector3.ZERO) as Vector3).x
				var heel: float = (p.get(StringName("_heel" + s), Vector3.ZERO) as Vector3).x
				p[foot] = Vector3(clampf(-leg, -45.0, 45.0) - heel, 0, 0)
	var jaw: float = (p.get(&"_jaw", Vector3.ZERO) as Vector3).x
	if not p.has(&"Jaw"):
		p[&"Jaw"] = Vector3(-16.0 * jaw, 0, 0)
	var brow: float = (p.get(&"_brow", Vector3.ZERO) as Vector3).x
	if not p.has(&"BrowL"):
		p[&"BrowL"] = Vector3(0, 0, -12.0 * brow)
		p[&"BrowR"] = Vector3(0, 0, 12.0 * brow)
	return p


static func _mirror(pose: Dictionary) -> Dictionary:
	var out := {}
	for key in pose:
		var v: Vector3 = pose[key]
		var k := String(key)
		if k.ends_with("L"):
			k = k.substr(0, k.length() - 1) + "R"
		elif k.ends_with("R"):
			k = k.substr(0, k.length() - 1) + "L"
		if k == "_hips":
			out[StringName(k)] = Vector3(-v.x, v.y, v.z)
		elif k.begins_with("_"):
			out[StringName(k)] = v  # scalars: fists, heels, jaw, brows
		else:
			out[StringName(k)] = Vector3(v.x, -v.y, -v.z)
	return out


static func _with(base: Dictionary, changes: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(changes, true)
	return out


## Every animation as keyed poses. Each pose maps a joint to Euler degrees (x, y, z).
## +x swings a limb forward, -x on a knee bends it, -x on the spine leans forward, +x on the
## head tips it back. -y on the hips turns the body to its right. "_hips" offsets the hips
## from their standing position. "_fistL"/"_fistR", "_jaw", "_brow" and "_heelL"/"_heelR"
## are the scalars _expand() turns into fingers, face and feet.
## A strike def's "load" is the end of its wind-up (the coiled pose) and "contact" the
## moment the blow lands; play_windup()/release_strike() and load_time() use them.
func _anim_defs() -> Dictionary:
	var lie := _lie
	var fists := {&"_fistL": Vector3(1, 0, 0), &"_fistR": Vector3(1, 0, 0)}
	# Boxing guard: bladed with the left side forward, chin tucked behind the fists, knees soft.
	var guard := _with(fists, {
		&"Hips": Vector3(0, -16, 0), &"Spine": Vector3(-8, 9, 0), &"Head": Vector3(-8, 6, 0),
		&"ShoulderL": Vector3(58, 0, 4), &"ElbowL": Vector3(124, 0, 0), &"HandL": Vector3(-10, 0, 0),
		&"ShoulderR": Vector3(52, 0, -6), &"ElbowR": Vector3(132, 0, 0), &"HandR": Vector3(-10, 0, 0),
		&"HipL": Vector3(16, 0, -6), &"KneeL": Vector3(-18, 0, 0), &"HipR": Vector3(-10, 0, 6), &"KneeR": Vector3(-16, 0, 0),
		&"_hips": Vector3(0, -0.02, 0), &"_brow": Vector3(0.6, 0, 0),
	})
	var relaxed := {
		&"ShoulderL": Vector3(6, 0, -7), &"ElbowL": Vector3(18, 0, 0), &"ShoulderR": Vector3(6, 0, 7), &"ElbowR": Vector3(18, 0, 0),
		&"_fistL": Vector3(0.3, 0, 0), &"_fistR": Vector3(0.3, 0, 0),
	}
	var on_back := {
		&"Hips": Vector3(90, 0, 0), &"_hips": Vector3(0, lie, 0.42),
		&"ShoulderL": Vector3(12, 0, -58), &"ElbowL": Vector3(40, 0, 0), &"ShoulderR": Vector3(8, 0, 52), &"ElbowR": Vector3(30, 0, 0),
		&"HipL": Vector3(12, 0, -10), &"KneeL": Vector3(-30, 0, 0), &"HipR": Vector3(2, 0, 8), &"KneeR": Vector3(-6, 0, 0),
		&"Head": Vector3(0, 28, 0), &"_jaw": Vector3(0.35, 0, 0), &"_brow": Vector3(-0.5, 0, 0),
		&"_fistL": Vector3(0.4, 0, 0), &"_fistR": Vector3(0.3, 0, 0),
	}
	var crawl_a := {
		&"Hips": Vector3(-80, -5, 0), &"_hips": Vector3(0, lie + 0.03, 0.15), &"Spine": Vector3(14, 0, 0), &"Chest": Vector3(10, 0, 0),
		&"Head": Vector3(40, 0, 0), &"_jaw": Vector3(0.4, 0, 0), &"_brow": Vector3(-0.7, 0, 0),
		&"ShoulderR": Vector3(155, 0, 12), &"ElbowR": Vector3(25, 0, 0), &"ShoulderL": Vector3(100, 0, -12), &"ElbowL": Vector3(75, 0, 0),
		&"HipL": Vector3(-4, 0, -12), &"KneeL": Vector3(-40, 0, 0), &"HipR": Vector3(-2, 0, 8), &"KneeR": Vector3(-8, 0, 0),
		&"_fistL": Vector3(0.1, 0, 0), &"_fistR": Vector3(0.6, 0, 0),
	}
	var crawl_b := _mirror(crawl_a)
	crawl_b[&"_hips"] = Vector3(0, lie + 0.03, 0.15)
	var hold_a := {
		&"Spine": Vector3(-8, 0, 0), &"ShoulderL": Vector3(78, 0, 26), &"ElbowL": Vector3(78, 0, 0),
		&"ShoulderR": Vector3(78, 0, -26), &"ElbowR": Vector3(78, 0, 0),
		&"HipL": Vector3(14, 0, -6), &"KneeL": Vector3(-22, 0, 0), &"HipR": Vector3(-12, 0, 6), &"KneeR": Vector3(-16, 0, 0),
		&"_fistL": Vector3(0.75, 0, 0), &"_fistR": Vector3(0.75, 0, 0), &"_brow": Vector3(0.8, 0, 0), &"_jaw": Vector3(0.15, 0, 0),
	}
	var held_a := {
		&"Spine": Vector3(10, 16, 6), &"Head": Vector3(18, 25, 0),
		&"ShoulderL": Vector3(-16, 0, -10), &"ElbowL": Vector3(35, 0, 0), &"ShoulderR": Vector3(-12, 0, 12), &"ElbowR": Vector3(45, 0, 0),
		&"HipL": Vector3(25, 0, 0), &"KneeL": Vector3(-55, 0, 0), &"HipR": Vector3(-8, 0, 0), &"KneeR": Vector3(-10, 0, 0),
		&"_hips": Vector3(0, 0.04, 0), &"_fistL": Vector3(0.9, 0, 0), &"_fistR": Vector3(0.1, 0, 0),
		&"_jaw": Vector3(0.5, 0, 0), &"_brow": Vector3(-0.8, 0, 0),
	}

	var defs := {}
	_calm_defs(defs, relaxed)

	# --- Stance and footwork ------------------------------------------------
	# On the balls of the feet: a small bounce, hands circling, eyes on the man in front.
	defs[&"idle"] = {"length": 1.2, "loop": true, "keys": [
		[0.0, guard],
		[0.3, _with(guard, {&"_hips": Vector3(0.008, -0.035, 0), &"KneeL": Vector3(-24, 0, 0), &"KneeR": Vector3(-22, 0, 0),
			&"ShoulderL": Vector3(54, 0, 6), &"ElbowL": Vector3(120, 0, 0), &"Spine": Vector3(-10, 11, 0)})],
		[0.6, _with(guard, {&"_hips": Vector3(0, -0.015, 0), &"ShoulderR": Vector3(56, 0, -4)})],
		[0.9, _with(guard, {&"_hips": Vector3(-0.008, -0.035, 0), &"KneeL": Vector3(-24, 0, 0), &"KneeR": Vector3(-22, 0, 0),
			&"ShoulderR": Vector3(50, 0, -8), &"ElbowR": Vector3(128, 0, 0), &"Spine": Vector3(-9, 7, 0), &"Head": Vector3(-9, 9, 0)})],
		[1.2, guard],
	]}
	var step := _with(guard, {&"Spine": Vector3(-10, 14, 0), &"HipL": Vector3(32, 0, -6), &"KneeL": Vector3(-12, 0, 0),
		&"HipR": Vector3(-24, 0, 6), &"KneeR": Vector3(-30, 0, 0), &"_heelR": Vector3(15, 0, 0)})
	var passing := _with(guard, {&"HipL": Vector3(10, 0, -6), &"KneeL": Vector3(-14, 0, 0), &"HipR": Vector3(8, 0, 6),
		&"KneeR": Vector3(-58, 0, 0), &"_hips": Vector3(0, 0.0, 0)})
	var step_b := _with(guard, {&"Spine": Vector3(-10, 4, 0), &"HipL": Vector3(-14, 0, -6), &"KneeL": Vector3(-30, 0, 0),
		&"HipR": Vector3(24, 0, 6), &"KneeR": Vector3(-12, 0, 0), &"_heelL": Vector3(15, 0, 0)})
	var passing_b := _with(guard, {&"HipL": Vector3(6, 0, -6), &"KneeL": Vector3(-56, 0, 0), &"HipR": Vector3(4, 0, 6),
		&"KneeR": Vector3(-16, 0, 0)})
	defs[&"walk"] = {"length": 0.8, "loop": true, "keys": [
		[0.0, step], [0.2, passing], [0.4, step_b], [0.6, passing_b], [0.8, step],
	]}

	# --- Punches -------------------------------------------------------------
	# Each one: a small, readable load (weight and shoulder go back, the punching side coils),
	# a snap into contact led by the hips, a beat at full extension, then a recovery that
	# settles back into the guard. The other hand stays home, guarding the chin.

	# Jab (lead hand): fast. A dip of the lead shoulder, a half step in, straight out and back.
	var jab_load := _with(guard, {&"Hips": Vector3(0, -12, 0), &"Spine": Vector3(-6, 12, 0), &"ShoulderL": Vector3(48, 0, 8),
		&"ElbowL": Vector3(134, 0, 0), &"_hips": Vector3(0, -0.03, 0.015), &"KneeL": Vector3(-22, 0, 0)})
	var jab_hit := _with(guard, {&"Hips": Vector3(0, -26, 0), &"Spine": Vector3(-12, 0, 0), &"Chest": Vector3(0, -6, 0),
		&"Head": Vector3(-12, 18, 0), &"ShoulderL": Vector3(90, 8, 2), &"ElbowL": Vector3(4, 0, 0), &"HandL": Vector3(0, 0, 0),
		&"HipL": Vector3(26, 0, -6), &"KneeL": Vector3(-20, 0, 0), &"HipR": Vector3(-16, 0, 6), &"KneeR": Vector3(-10, 0, 0),
		&"_hips": Vector3(0, -0.025, -0.07), &"_heelR": Vector3(10, 0, 0), &"_brow": Vector3(0.9, 0, 0)})
	defs[&"punch_l"] = {"length": 0.38, "load": 0.06, "contact": 0.1, "keys": [
		[0.0, guard], [0.06, jab_load, "io"], [0.1, jab_hit, "snap"],
		[0.15, _with(jab_hit, {&"ShoulderL": Vector3(87, 8, 2), &"ElbowL": Vector3(12, 0, 0)}), "lin"],
		[0.24, _with(guard, {&"ShoulderL": Vector3(70, 4, 4), &"ElbowL": Vector3(90, 0, 0), &"_hips": Vector3(0, -0.02, -0.03)}), "out"],
		[0.38, guard],
	]}
	# Cross (rear hand): the power shot. Sit back on the rear leg, then drive the rear hip
	# through, pivot on the rear toe and turn the shoulders over.
	var cross_load := _with(guard, {&"Hips": Vector3(0, -30, 0), &"Spine": Vector3(-4, 4, 0), &"Head": Vector3(-6, 14, 0),
		&"ShoulderR": Vector3(44, 0, -14), &"ElbowR": Vector3(138, 0, 0), &"HipR": Vector3(-14, 0, 6), &"KneeR": Vector3(-26, 0, 0),
		&"_hips": Vector3(0.01, -0.035, 0.045), &"_brow": Vector3(0.9, 0, 0)})
	var cross_hit := _with(guard, {&"Hips": Vector3(0, 18, 0), &"Spine": Vector3(-16, 14, 0), &"Chest": Vector3(0, 10, 0),
		&"Head": Vector3(-14, -10, 0), &"ShoulderR": Vector3(90, -8, -6), &"ElbowR": Vector3(4, 0, 0), &"HandR": Vector3(0, 0, 0),
		&"ShoulderL": Vector3(62, 0, 12), &"ElbowL": Vector3(136, 0, 0),
		&"HipL": Vector3(22, 0, -6), &"KneeL": Vector3(-26, 0, 0), &"HipR": Vector3(-24, 0, 6), &"KneeR": Vector3(-8, 0, 0),
		&"_hips": Vector3(-0.01, -0.04, -0.1), &"_heelR": Vector3(30, 0, 0), &"_brow": Vector3(1, 0, 0), &"_jaw": Vector3(0.1, 0, 0)})
	defs[&"punch_r"] = {"length": 0.46, "load": 0.08, "contact": 0.13, "keys": [
		[0.0, guard], [0.08, cross_load, "io"], [0.13, cross_hit, "snap"],
		[0.19, _with(cross_hit, {&"ShoulderR": Vector3(87, -8, -6), &"ElbowR": Vector3(12, 0, 0)}), "lin"],
		[0.3, _with(guard, {&"Hips": Vector3(0, 0, 0), &"ShoulderR": Vector3(66, 0, -4), &"ElbowR": Vector3(96, 0, 0),
			&"_hips": Vector3(0, -0.03, -0.04)}), "out"],
		[0.46, guard],
	]}
	# Lead hook: weight onto the lead leg, the arm bent at 90 degrees, then the hips and the
	# lead foot turn the whole body through, so the fist sweeps across at head height.
	# The hooking arm: upper arm out level with the shoulder, the forearm bent back across the
	# front at 90 degrees. (Shoulder y swings that L shape round; z lifts it level.)
	var hook_load := _with(guard, {&"Hips": Vector3(0, 6, 0), &"Spine": Vector3(-8, 16, -6), &"Head": Vector3(-10, -6, 0),
		&"ShoulderL": Vector3(0, -12, -66), &"ElbowL": Vector3(100, 0, 0), &"HandL": Vector3(0, 0, 0),
		&"KneeL": Vector3(-28, 0, 0), &"_hips": Vector3(-0.025, -0.045, 0), &"_brow": Vector3(1, 0, 0)})
	var hook_hit := _with(guard, {&"Hips": Vector3(0, -34, 0), &"Spine": Vector3(-12, -20, 4), &"Chest": Vector3(0, -10, 0),
		&"Head": Vector3(-12, 18, 0), &"ShoulderL": Vector3(0, -42, -86), &"ElbowL": Vector3(94, 0, 0), &"HandL": Vector3(0, 0, 0),
		&"ShoulderR": Vector3(56, 0, -2), &"ElbowR": Vector3(136, 0, 0),
		&"KneeL": Vector3(-20, 0, 0), &"KneeR": Vector3(-22, 0, 0), &"_heelL": Vector3(18, 0, 0),
		&"_hips": Vector3(0.015, -0.04, -0.05), &"_brow": Vector3(1, 0, 0), &"_jaw": Vector3(0.1, 0, 0)})
	defs[&"hook_l"] = {"length": 0.52, "load": 0.1, "contact": 0.16, "keys": [
		[0.0, guard], [0.1, hook_load, "io"], [0.16, hook_hit, "snap"],
		[0.23, _with(hook_hit, {&"Hips": Vector3(0, -42, 0), &"Spine": Vector3(-12, -28, 4), &"ShoulderL": Vector3(0, -58, -80)}), "out"],
		[0.36, _with(guard, {&"Hips": Vector3(0, -24, 0), &"ShoulderL": Vector3(66, 0, -16), &"ElbowL": Vector3(110, 0, 0)})],
		[0.52, guard],
	]}
	# Rear hook: the same, off the back foot, with a bigger turn.
	defs[&"hook_r"] = _mirror_strike(defs[&"hook_l"], guard)
	# Rear uppercut: dip, drop the rear shoulder with the fist low by the ribs, then drive up
	# through the legs and turn the hip so the fist rises through the chin.
	var upper_load := _with(guard, {&"Hips": Vector3(0, -26, 0), &"Spine": Vector3(-20, -6, 10), &"Head": Vector3(-14, 10, 0),
		&"ShoulderR": Vector3(16, 0, -6), &"ElbowR": Vector3(112, 0, 0), &"HandR": Vector3(20, 0, 0),
		&"HipL": Vector3(24, 0, -6), &"KneeL": Vector3(-40, 0, 0), &"HipR": Vector3(4, 0, 6), &"KneeR": Vector3(-38, 0, 0),
		&"_hips": Vector3(0.02, -0.1, 0.02), &"_brow": Vector3(1, 0, 0)})
	var upper_hit := _with(guard, {&"Hips": Vector3(0, 16, 0), &"Spine": Vector3(4, 16, -6), &"Chest": Vector3(6, 6, 0),
		&"Head": Vector3(2, -6, 0), &"ShoulderR": Vector3(100, 0, -12), &"ElbowR": Vector3(92, 0, 0), &"HandR": Vector3(-10, 0, 0),
		&"ShoulderL": Vector3(60, 0, 12), &"ElbowL": Vector3(136, 0, 0),
		&"HipL": Vector3(14, 0, -6), &"KneeL": Vector3(-10, 0, 0), &"HipR": Vector3(-10, 0, 6), &"KneeR": Vector3(-6, 0, 0),
		&"_hips": Vector3(-0.01, 0.015, -0.05), &"_heelR": Vector3(34, 0, 0), &"_brow": Vector3(1, 0, 0), &"_jaw": Vector3(0.15, 0, 0)})
	defs[&"uppercut_r"] = {"length": 0.6, "load": 0.13, "contact": 0.19, "keys": [
		[0.0, guard], [0.13, upper_load, "io"], [0.19, upper_hit, "snap"],
		[0.27, _with(upper_hit, {&"ShoulderR": Vector3(110, 0, -10), &"ElbowR": Vector3(90, 0, 0), &"_hips": Vector3(-0.01, 0.02, -0.06)}), "out"],
		[0.42, _with(guard, {&"ShoulderR": Vector3(70, 0, -6), &"ElbowR": Vector3(120, 0, 0), &"_hips": Vector3(0, -0.03, -0.03)})],
		[0.6, guard],
	]}
	# The big telegraphed haymaker: a long, obvious chamber. The rear arm swings right back,
	# the body coils away and leans back, the lead hand reaches out to measure. Holds there.
	var cocked := _with(guard, {&"Hips": Vector3(0, -38, 0), &"Spine": Vector3(8, -22, 6), &"Chest": Vector3(4, -8, 0),
		&"Head": Vector3(-4, 40, 0), &"ShoulderR": Vector3(-38, 0, 62), &"ElbowR": Vector3(108, 0, 0), &"HandR": Vector3(-20, 0, 0),
		&"ShoulderL": Vector3(70, 0, -12), &"ElbowL": Vector3(40, 0, 0), &"_fistL": Vector3(0.1, 0, 0),
		&"HipL": Vector3(22, 0, -8), &"KneeL": Vector3(-10, 0, 0), &"HipR": Vector3(-18, 0, 6), &"KneeR": Vector3(-30, 0, 0),
		&"_hips": Vector3(0.02, -0.04, 0.07), &"_brow": Vector3(1, 0, 0), &"_jaw": Vector3(0.25, 0, 0)})
	defs[&"windup"] = {"length": 0.55, "load": 0.55, "keys": [
		[0.0, guard],
		[0.18, _with(guard, {&"Hips": Vector3(0, -24, 0), &"ShoulderR": Vector3(10, 0, 40), &"ElbowR": Vector3(118, 0, 0),
			&"_hips": Vector3(0.01, -0.035, 0.035)}), "io"],
		[0.42, cocked, "out"],
		[0.55, _with(cocked, {&"Spine": Vector3(10, -26, 6), &"ShoulderR": Vector3(-44, 0, 66), &"_hips": Vector3(0.02, -0.045, 0.08)}), "io"],
	]}
	# Block: forearms up in front of the face, chin tucked, braced.
	var cover := _with(guard, {&"Hips": Vector3(0, -8, 0), &"Spine": Vector3(-16, 4, 0), &"Head": Vector3(-16, 0, 0),
		&"ShoulderL": Vector3(72, 0, 22), &"ElbowL": Vector3(138, 0, 0), &"HandL": Vector3(-20, 0, 0),
		&"ShoulderR": Vector3(72, 0, -22), &"ElbowR": Vector3(138, 0, 0), &"HandR": Vector3(-20, 0, 0),
		&"KneeL": Vector3(-26, 0, 0), &"KneeR": Vector3(-24, 0, 0), &"_hips": Vector3(0, -0.05, 0), &"_brow": Vector3(0.9, 0, 0)})
	defs[&"block"] = {"length": 1.0, "loop": true, "keys": [
		[0.0, cover], [0.5, _with(cover, {&"Spine": Vector3(-17, 7, 0), &"_hips": Vector3(0, -0.06, 0)})], [1.0, cover],
	]}

	# --- Other attacks -------------------------------------------------------
	var kick_out := _with(guard, {&"Hips": Vector3(0, -10, 0), &"Spine": Vector3(18, 0, 0), &"HipR": Vector3(85, 0, 0), &"KneeR": Vector3(-4, 0, 0),
		&"KneeL": Vector3(-14, 0, 0), &"HipL": Vector3(-4, 0, -5), &"ShoulderL": Vector3(30, 0, -32), &"ElbowL": Vector3(70, 0, 0),
		&"_heelL": Vector3(14, 0, 0), &"_brow": Vector3(1, 0, 0)})
	defs[&"kick"] = {"length": 0.62, "load": 0.14, "contact": 0.22, "keys": [
		[0.0, guard],
		[0.14, _with(guard, {&"Spine": Vector3(10, 0, 0), &"HipR": Vector3(72, 0, 0), &"KneeR": Vector3(-105, 0, 0), &"_hips": Vector3(0, 0.02, 0)}), "io"],
		[0.22, kick_out, "snap"], [0.34, kick_out, "lin"],
		[0.46, _with(guard, {&"HipR": Vector3(40, 0, 0), &"KneeR": Vector3(-80, 0, 0)}), "out"], [0.62, guard],
	]}
	var butt := _with(guard, {&"Spine": Vector3(-32, 0, 0), &"Chest": Vector3(-10, 0, 0), &"Head": Vector3(-25, 0, 0),
		&"ShoulderL": Vector3(62, 0, 28), &"ElbowL": Vector3(85, 0, 0), &"ShoulderR": Vector3(62, 0, -28), &"ElbowR": Vector3(85, 0, 0),
		&"_fistL": Vector3(0.4, 0, 0), &"_fistR": Vector3(0.4, 0, 0), &"_hips": Vector3(0, -0.04, -0.13), &"_brow": Vector3(1, 0, 0)})
	defs[&"headbutt"] = {"length": 0.56, "load": 0.16, "contact": 0.24, "keys": [
		[0.0, guard],
		[0.16, _with(guard, {&"Spine": Vector3(16, 0, 0), &"Head": Vector3(26, 0, 0), &"_hips": Vector3(0, 0, 0.06)}), "io"],
		[0.24, butt, "snap"], [0.33, butt, "lin"], [0.56, guard, "out"],
	]}
	var overhead := _with(guard, {&"Spine": Vector3(14, 0, 0), &"ShoulderL": Vector3(165, 0, 8), &"ElbowL": Vector3(40, 0, 0),
		&"ShoulderR": Vector3(165, 0, -8), &"ElbowR": Vector3(40, 0, 0), &"_hips": Vector3(0, 0.01, 0.04)})
	var smash := _with(guard, {&"Spine": Vector3(-26, 0, 0), &"ShoulderL": Vector3(52, 0, 10), &"ElbowL": Vector3(10, 0, 0),
		&"ShoulderR": Vector3(52, 0, -10), &"ElbowR": Vector3(10, 0, 0), &"KneeL": Vector3(-26, 0, 0), &"_hips": Vector3(0, -0.06, -0.05)})
	defs[&"swing"] = {"length": 0.72, "load": 0.22, "contact": 0.32, "keys": [
		[0.0, guard], [0.22, overhead, "io"], [0.32, smash, "snap"], [0.46, smash, "lin"], [0.72, guard, "out"]]}
	defs[&"throw"] = {"length": 0.6, "load": 0.18, "contact": 0.3, "keys": [
		[0.0, guard],
		[0.18, _with(guard, {&"Spine": Vector3(10, -26, 0), &"ShoulderR": Vector3(-55, 0, 32), &"ElbowR": Vector3(70, 0, 0)}), "io"],
		[0.3, _with(guard, {&"Spine": Vector3(-16, 22, 0), &"ShoulderR": Vector3(125, 0, 0), &"ElbowR": Vector3(10, 0, 0),
			&"_fistR": Vector3(0, 0, 0), &"_hips": Vector3(0, 0, -0.05)}), "snap"],
		[0.6, guard, "out"],
	]}
	defs[&"grab"] = {"length": 0.4, "keys": [
		[0.0, guard],
		[0.15, _with(hold_a, {&"Spine": Vector3(-16, 0, 0), &"ShoulderL": Vector3(88, 0, 18), &"ElbowL": Vector3(18, 0, 0),
			&"ShoulderR": Vector3(88, 0, -18), &"ElbowR": Vector3(18, 0, 0), &"_hips": Vector3(0, -0.04, -0.1),
			&"_fistL": Vector3(-0.1, 0, 0), &"_fistR": Vector3(-0.1, 0, 0)}), "snap"],
		[0.4, hold_a, "io"],
	]}
	defs[&"hold"] = {"length": 1.2, "loop": true, "keys": [
		[0.0, hold_a], [0.6, _with(hold_a, {&"Spine": Vector3(-9, 7, 4), &"_hips": Vector3(0, -0.015, 0)})], [1.2, hold_a],
	]}
	defs[&"held_struggle"] = {"length": 0.9, "loop": true, "keys": [
		[0.0, held_a], [0.45, _mirror(held_a)], [0.9, held_a],
	]}

	# --- Taking hits ---------------------------------------------------------
	# The head takes it first and the body follows (OVERLAP does the follow-through): a snap
	# away from the blow, a stagger step to catch the weight, the jaw slack and the brows up,
	# then a bob back up into the guard.
	var pain := {&"_jaw": Vector3(0.55, 0, 0), &"_brow": Vector3(-0.9, 0, 0), &"_fistL": Vector3(0.6, 0, 0), &"_fistR": Vector3(0.6, 0, 0)}
	var rock_back := _with(_with(guard, pain), {&"Head": Vector3(40, -14, 0), &"Spine": Vector3(18, 0, 0), &"Chest": Vector3(10, 0, 0),
		&"ShoulderL": Vector3(26, 0, -30), &"ElbowL": Vector3(64, 0, 0), &"ShoulderR": Vector3(20, 0, 32), &"ElbowR": Vector3(70, 0, 0),
		&"HipL": Vector3(4, 0, -6), &"KneeL": Vector3(-10, 0, 0), &"_hips": Vector3(0, -0.01, 0.08)})
	defs[&"hit_front"] = {"length": 0.5, "keys": [
		[0.0, guard], [0.05, rock_back, "snap"],
		[0.16, _with(rock_back, {&"Head": Vector3(26, -8, 0), &"HipR": Vector3(-24, 0, 6), &"KneeR": Vector3(-26, 0, 0),
			&"_hips": Vector3(0, -0.04, 0.13)}), "out"],
		[0.3, _with(guard, {&"Spine": Vector3(-14, 6, 0), &"Head": Vector3(-14, 4, 0), &"_hips": Vector3(0, -0.04, 0.06),
			&"_brow": Vector3(-0.3, 0, 0)})],
		[0.5, guard],
	]}
	var jolt := _with(_with(guard, pain), {&"Head": Vector3(-22, 0, 0), &"Spine": Vector3(-26, 0, 0), &"_hips": Vector3(0, -0.02, -0.08),
		&"ShoulderL": Vector3(-20, 0, -20), &"ElbowL": Vector3(40, 0, 0), &"ShoulderR": Vector3(-20, 0, 20), &"ElbowR": Vector3(40, 0, 0)})
	defs[&"hit_back"] = {"length": 0.5, "keys": [
		[0.0, guard], [0.05, jolt, "snap"],
		[0.18, _with(jolt, {&"HipL": Vector3(28, 0, -6), &"KneeL": Vector3(-30, 0, 0), &"_hips": Vector3(0, -0.05, -0.14)}), "out"],
		[0.5, guard],
	]}
	# Struck on the left (a right hook): the head whips round to the right, the body leans
	# away and the right foot steps out to catch the weight.
	var whip := _with(_with(guard, pain), {&"Head": Vector3(10, -48, -26), &"Spine": Vector3(4, -18, -14), &"Chest": Vector3(0, -8, -8),
		&"ShoulderL": Vector3(30, 0, -48), &"ElbowL": Vector3(70, 0, 0), &"ShoulderR": Vector3(38, 0, 18), &"ElbowR": Vector3(96, 0, 0),
		&"_hips": Vector3(0.05, -0.02, 0.02)})
	defs[&"hit_left"] = {"length": 0.55, "keys": [
		[0.0, guard], [0.05, whip, "snap"],
		[0.18, _with(whip, {&"Head": Vector3(6, -34, -18), &"HipR": Vector3(2, 0, 20), &"KneeR": Vector3(-28, 0, 0),
			&"_hips": Vector3(0.08, -0.05, 0.03)}), "out"],
		[0.34, _with(guard, {&"Head": Vector3(-10, -6, 0), &"_hips": Vector3(0.03, -0.04, 0), &"_brow": Vector3(-0.3, 0, 0)})],
		[0.55, guard],
	]}
	defs[&"hit_right"] = _mirror_strike(defs[&"hit_left"], guard)
	# A heavy one: knocked back off balance, arms windmilling, a few steps to stay up.
	defs[&"stagger"] = {"length": 1.0, "keys": [
		[0.0, guard],
		[0.08, _with(pain, {&"Head": Vector3(46, 10, 0), &"Spine": Vector3(26, 8, 8), &"Chest": Vector3(10, 0, 0),
			&"ShoulderL": Vector3(40, 0, -66), &"ElbowL": Vector3(20, 0, 0), &"ShoulderR": Vector3(-10, 0, 70), &"ElbowR": Vector3(30, 0, 0),
			&"_fistL": Vector3(0.1, 0, 0), &"_fistR": Vector3(0.1, 0, 0), &"_hips": Vector3(0, -0.02, 0.1)}), "snap"],
		[0.28, _with(pain, {&"Head": Vector3(28, -6, 0), &"Spine": Vector3(22, 10, 8), &"ShoulderL": Vector3(60, 0, -50),
			&"ShoulderR": Vector3(10, 0, 62), &"ElbowR": Vector3(40, 0, 0), &"HipL": Vector3(30, 0, 0), &"KneeL": Vector3(-44, 0, 0),
			&"HipR": Vector3(-24, 0, 4), &"_hips": Vector3(0, -0.07, 0.2), &"_fistL": Vector3(0.1, 0, 0), &"_fistR": Vector3(0.2, 0, 0)}), "out"],
		[0.5, _with(pain, {&"Spine": Vector3(14, -10, -8), &"Head": Vector3(18, -12, 0), &"ShoulderL": Vector3(14, 0, -40),
			&"ShoulderR": Vector3(34, 0, 46), &"HipR": Vector3(-26, 0, 0), &"KneeR": Vector3(-28, 0, 0), &"KneeL": Vector3(-30, 0, 0),
			&"_hips": Vector3(0, -0.09, 0.26)})],
		[0.72, _with(guard, {&"Spine": Vector3(-2, 4, 0), &"Head": Vector3(6, 0, 0), &"_hips": Vector3(0, -0.06, 0.24),
			&"KneeL": Vector3(-30, 0, 0), &"KneeR": Vector3(-28, 0, 0), &"_brow": Vector3(-0.4, 0, 0)})],
		[1.0, guard],
	]}
	defs[&"knockdown"] = {"length": 0.7, "keys": [
		[0.0, guard],
		[0.15, _with(pain, {&"Hips": Vector3(25, 0, 0), &"Head": Vector3(32, 0, 0), &"ShoulderL": Vector3(120, 0, -40), &"ShoulderR": Vector3(120, 0, 40),
			&"KneeL": Vector3(-40, 0, 0), &"KneeR": Vector3(-45, 0, 0), &"_hips": Vector3(0, -0.12, 0.1),
			&"_fistL": Vector3(0, 0, 0), &"_fistR": Vector3(0, 0, 0)}), "snap"],
		[0.4, _with(on_back, {&"Hips": Vector3(75, 0, 0), &"_hips": Vector3(0, lie + 0.1, 0.35), &"HipL": Vector3(45, 0, 0), &"HipR": Vector3(35, 0, 0)}), "in"],
		[0.55, _with(on_back, {&"Head": Vector3(-20, 10, 0)}), "lin"],
		[0.62, _with(on_back, {&"_hips": Vector3(0, lie + 0.03, 0.42), &"Hips": Vector3(86, 0, 0)}), "out"],
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
		[0.9, guard, "out"],
	]}
	defs[&"crawl"] = {"length": 1.4, "loop": true, "keys": [[0.0, crawl_a], [0.7, crawl_b], [1.4, crawl_a]]}
	var limp := _with(on_back, {&"ShoulderL": Vector3(140, 0, -50), &"ElbowL": Vector3(20, 0, 0), &"ShoulderR": Vector3(30, 0, 72),
		&"ElbowR": Vector3(10, 0, 0), &"Head": Vector3(0, -62, 0), &"HipL": Vector3(25, 0, -16), &"KneeL": Vector3(-52, 0, 0), &"HipR": Vector3(0, 0, 12),
		&"KneeR": Vector3(0, 0, 0), &"_jaw": Vector3(0.6, 0, 0), &"_brow": Vector3(-0.3, 0, 0), &"_fistL": Vector3(0.2, 0, 0), &"_fistR": Vector3(0.2, 0, 0)})
	defs[&"ko"] = {"length": 1.0, "keys": [
		[0.0, guard],
		[0.12, _with(_with(guard, pain), {&"Head": Vector3(42, 0, 0), &"Spine": Vector3(18, 0, 0), &"ShoulderL": Vector3(20, 0, -20), &"ShoulderR": Vector3(20, 0, 20),
			&"ElbowL": Vector3(20, 0, 0), &"ElbowR": Vector3(20, 0, 0), &"_fistL": Vector3(0.1, 0, 0), &"_fistR": Vector3(0.1, 0, 0)}), "snap"],
		[0.35, _with(limp, {&"Hips": Vector3(45, 0, 0), &"Head": Vector3(30, 0, 0), &"ShoulderL": Vector3(60, 0, -30), &"ShoulderR": Vector3(60, 0, 30),
			&"KneeL": Vector3(-60, 0, 0), &"KneeR": Vector3(-50, 0, 0), &"_hips": Vector3(0, lie * 0.5, 0.22)}), "in"],
		[0.6, _with(limp, {&"Hips": Vector3(92, 0, 0), &"_hips": Vector3(0, lie, 0.5), &"Head": Vector3(0, -20, 0)}), "in"],
		[0.7, _with(limp, {&"Hips": Vector3(84, 0, 0), &"_hips": Vector3(0, lie + 0.04, 0.5)}), "out"],
		[1.0, _with(limp, {&"_hips": Vector3(0, lie, 0.5)})],
	]}

	# --- Pub business --------------------------------------------------------
	var sup := _with(relaxed, {&"ShoulderR": Vector3(105, 0, -26), &"ElbowR": Vector3(138, 0, 0), &"_fistR": Vector3(0.6, 0, 0)})
	defs[&"drink"] = {"length": 1.6, "keys": [
		[0.0, guard], [0.35, sup, "io"],
		[0.6, _with(sup, {&"Head": Vector3(32, 0, 0), &"Spine": Vector3(12, 0, 0), &"ShoulderR": Vector3(132, 0, -22), &"ElbowR": Vector3(122, 0, 0)})],
		[1.1, _with(sup, {&"Head": Vector3(36, 0, 0), &"Spine": Vector3(14, 0, 0), &"ShoulderR": Vector3(138, 0, -20), &"ElbowR": Vector3(118, 0, 0)})],
		[1.35, _with(relaxed, {&"ShoulderR": Vector3(40, 0, 0), &"ElbowR": Vector3(90, 0, 0), &"Head": Vector3(-6, 0, 0), &"_fistR": Vector3(0.6, 0, 0)})],
		[1.6, relaxed],
	]}
	var bite := _with(relaxed, {&"ShoulderR": Vector3(96, 0, -26), &"ElbowR": Vector3(142, 0, 0), &"Head": Vector3(-10, 0, 0), &"Spine": Vector3(-6, 0, 0),
		&"_fistR": Vector3(0.55, 0, 0), &"_jaw": Vector3(0.6, 0, 0)})
	var chew := _with(relaxed, {&"ShoulderR": Vector3(55, 0, -12), &"ElbowR": Vector3(100, 0, 0), &"Head": Vector3(4, 0, 0), &"Spine": Vector3(-4, 0, 0),
		&"_fistR": Vector3(0.55, 0, 0)})
	defs[&"eat"] = {"length": 1.6, "keys": [
		[0.0, guard], [0.3, bite], [0.55, chew], [0.65, _with(chew, {&"_jaw": Vector3(0.3, 0, 0)})], [0.75, _with(chew, {&"Head": Vector3(-4, 0, 0)})],
		[0.95, bite], [1.1, _with(chew, {&"_jaw": Vector3(0.3, 0, 0)})], [1.25, chew], [1.6, relaxed],
	]}
	var duck := _with(guard, {&"Spine": Vector3(-26, 0, 20), &"HipL": Vector3(32, 0, -8), &"KneeL": Vector3(-55, 0, 0),
		&"HipR": Vector3(28, 0, 8), &"KneeR": Vector3(-50, 0, 0), &"_hips": Vector3(0, -0.2, 0)})
	defs[&"dodge"] = {"length": 0.45, "keys": [
		[0.0, guard], [0.12, duck, "snap"], [0.28, _with(duck, {&"Spine": Vector3(-22, 0, -16), &"_hips": Vector3(0, -0.18, 0)})], [0.45, guard, "out"],
	]}
	var arms_up := {&"ShoulderL": Vector3(165, 0, -26), &"ElbowL": Vector3(20, 0, 0), &"ShoulderR": Vector3(165, 0, 26),
		&"ElbowR": Vector3(20, 0, 0), &"Head": Vector3(25, 0, 0), &"Spine": Vector3(10, 0, 0),
		&"_fistL": Vector3(1, 0, 0), &"_fistR": Vector3(1, 0, 0), &"_jaw": Vector3(1, 0, 0), &"_brow": Vector3(-0.4, 0, 0)}
	defs[&"cheer"] = {"length": 1.2, "keys": [
		[0.0, guard], [0.25, arms_up, "snap"],
		[0.5, _with(arms_up, {&"ShoulderR": Vector3(140, 0, 32), &"ElbowR": Vector3(70, 0, 0), &"_hips": Vector3(0, 0.04, 0), &"_jaw": Vector3(0.6, 0, 0)})],
		[0.75, arms_up], [1.2, guard],
	]}
	var beckon := _with(relaxed, {&"Spine": Vector3(10, 0, 0), &"Chest": Vector3(8, 0, 0), &"Head": Vector3(-8, 0, 0),
		&"ShoulderR": Vector3(68, 0, 4), &"ElbowR": Vector3(25, 0, 0), &"ShoulderL": Vector3(10, 0, -30), &"ElbowL": Vector3(10, 0, 0),
		&"_fistR": Vector3(-0.1, 0, 0), &"_fistL": Vector3(0.8, 0, 0), &"_brow": Vector3(0.8, 0, 0), &"_jaw": Vector3(0.2, 0, 0)})
	var curl := _with(beckon, {&"ElbowR": Vector3(95, 0, 0), &"_fistR": Vector3(0.8, 0, 0)})
	defs[&"taunt"] = {"length": 1.4, "keys": [
		[0.0, guard], [0.25, beckon], [0.45, curl], [0.65, beckon], [0.85, curl], [1.05, beckon], [1.4, guard],
	]}
	return defs


## The same move off the other hand. Mirroring a whole pose would also mirror the stance
## (right foot forward), so mirror only how each key differs from the guard and add that
## to the real guard: a rear hook from the normal stance, turning the right way.
static func _mirror_strike(def: Dictionary, guard: Dictionary) -> Dictionary:
	var out := def.duplicate()
	var keys := []
	for k in def["keys"]:
		var pose: Dictionary = k[1]
		var delta := {}
		for j in pose:
			delta[j] = (pose[j] as Vector3) - (guard.get(j, Vector3.ZERO) as Vector3)
		for j in guard:
			if not pose.has(j):
				delta[j] = -(guard[j] as Vector3)
		var md := _mirror(delta)
		var res := guard.duplicate()
		for j in md:
			res[j] = (guard.get(j, Vector3.ZERO) as Vector3) + (md[j] as Vector3)
		var nk: Array = [k[0], res]
		if k.size() > 2:
			nk.append(k[2])
		keys.append(nk)
	out["keys"] = keys
	return out




## The calm set: how people stand about in a pub before it kicks off.
func _calm_defs(defs: Dictionary, relaxed: Dictionary) -> void:
	var stand := _with(relaxed, {&"Spine": Vector3(3, 0, 0), &"HipL": Vector3(2, 0, -3), &"HipR": Vector3(-2, 0, 3),
		&"KneeL": Vector3(-4, 0, 0), &"KneeR": Vector3(-2, 0, 0)})
	# Hands in pockets, weight shifting from foot to foot, glancing about.
	var pockets := _with(stand, {&"ShoulderL": Vector3(-6, 0, -9), &"ElbowL": Vector3(32, 0, 0),
		&"ShoulderR": Vector3(-6, 0, 9), &"ElbowR": Vector3(32, 0, 0)})
	defs[&"idle_relaxed"] = {"length": 4.0, "loop": true, "keys": [
		[0.0, _with(pockets, {&"_hips": Vector3(0.02, 0, 0), &"Spine": Vector3(3, 0, -2), &"KneeR": Vector3(-10, 0, 0)})],
		[1.3, _with(pockets, {&"_hips": Vector3(0.01, -0.004, 0), &"Head": Vector3(0, 18, 0), &"KneeR": Vector3(-8, 0, 0)})],
		[2.0, _with(pockets, {&"_hips": Vector3(-0.02, 0, 0), &"Spine": Vector3(3, 0, 2), &"KneeL": Vector3(-10, 0, 0)})],
		[3.2, _with(pockets, {&"_hips": Vector3(-0.01, -0.004, 0), &"Head": Vector3(-4, -14, 0), &"KneeL": Vector3(-8, 0, 0)})],
		[4.0, _with(pockets, {&"_hips": Vector3(0.02, 0, 0), &"Spine": Vector3(3, 0, -2), &"KneeR": Vector3(-10, 0, 0)})],
	]}
	# Pint held at the belly, the odd sip.
	var hold_pint := _with(stand, {&"ShoulderR": Vector3(22, 0, -8), &"ElbowR": Vector3(92, 0, 0)})
	var sip := _with(hold_pint, {&"ShoulderR": Vector3(100, 0, -26), &"ElbowR": Vector3(136, 0, 0),
		&"Head": Vector3(22, 0, 0), &"Spine": Vector3(8, 0, 0)})
	defs[&"idle_pint"] = {"length": 5.0, "loop": true, "keys": [
		[0.0, hold_pint], [1.5, _with(hold_pint, {&"Head": Vector3(0, 15, 0), &"_hips": Vector3(0.015, 0, 0)})],
		[2.6, hold_pint], [3.1, sip], [3.7, sip], [4.3, hold_pint], [5.0, hold_pint],
	]}
	# Chatting: one hand talking, nods, the other hand on a pint.
	var chat := _with(stand, {&"ShoulderL": Vector3(22, 0, -6), &"ElbowL": Vector3(92, 0, 0)})
	defs[&"idle_chat"] = {"length": 3.0, "loop": true, "keys": [
		[0.0, _with(chat, {&"ShoulderR": Vector3(30, 0, 10), &"ElbowR": Vector3(72, 0, 0)})],
		[0.6, _with(chat, {&"ShoulderR": Vector3(48, 0, 22), &"ElbowR": Vector3(48, 0, 0), &"Head": Vector3(-6, 12, 0)})],
		[1.2, _with(chat, {&"ShoulderR": Vector3(26, 0, 6), &"ElbowR": Vector3(88, 0, 0), &"Head": Vector3(6, -4, 0)})],
		[1.9, _with(chat, {&"ShoulderR": Vector3(12, 0, 8), &"ElbowR": Vector3(30, 0, 0), &"Head": Vector3(-8, 0, 0), &"Spine": Vector3(6, 0, 0)})],
		[2.5, _with(chat, {&"ShoulderR": Vector3(40, 0, 18), &"ElbowR": Vector3(60, 0, 0), &"Head": Vector3(4, 8, 0)})],
		[3.0, _with(chat, {&"ShoulderR": Vector3(30, 0, 10), &"ElbowR": Vector3(72, 0, 0)})],
	]}
	# Bar staff polishing a glass that is already clean.
	var polish := _with(stand, {&"Head": Vector3(-14, 0, 0), &"ShoulderL": Vector3(32, 0, 14), &"ElbowL": Vector3(72, 0, 0),
		&"ShoulderR": Vector3(36, 0, -14), &"ElbowR": Vector3(70, 0, 0)})
	defs[&"idle_polish"] = {"length": 1.6, "loop": true, "keys": [
		[0.0, polish], [0.4, _with(polish, {&"ShoulderR": Vector3(42, 0, -6), &"ElbowR": Vector3(60, 0, 0)})],
		[0.8, _with(polish, {&"ShoulderR": Vector3(36, 0, -22), &"ElbowR": Vector3(80, 0, 0)})],
		[1.2, _with(polish, {&"ShoulderR": Vector3(30, 0, -12), &"ElbowR": Vector3(74, 0, 0)})], [1.6, polish],
	]}
	# Strolling, arms swinging loose.
	var step := _with(relaxed, {&"Spine": Vector3(-2, 6, 0), &"HipL": Vector3(24, 0, -3), &"KneeL": Vector3(-6, 0, 0),
		&"HipR": Vector3(-22, 0, 3), &"KneeR": Vector3(-26, 0, 0), &"ShoulderL": Vector3(-16, 0, -6),
		&"ElbowL": Vector3(14, 0, 0), &"ShoulderR": Vector3(18, 0, 6), &"ElbowR": Vector3(24, 0, 0)})
	var passing := _with(relaxed, {&"HipL": Vector3(4, 0, -3), &"KneeL": Vector3(-8, 0, 0), &"HipR": Vector3(6, 0, 3),
		&"KneeR": Vector3(-52, 0, 0), &"_hips": Vector3(0, 0.025, 0)})
	defs[&"walk_relaxed"] = {"length": 0.9, "loop": true, "keys": [
		[0.0, step], [0.225, passing], [0.45, _mirror(step)], [0.675, _mirror(passing)], [0.9, step],
	]}
