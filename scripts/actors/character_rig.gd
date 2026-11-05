@tool
class_name CharacterRig
extends Node3D
## The shared humanoid rig. Every farmer, punter, copper and member of bar staff is a
## rigged, skinned model built in Blender (tools/blender/build_characters.py) on one shared
## armature, recoloured and dressed here from a CharacterLook. The 25 animations are
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
	if anim_name == &"idle" or anim_name == &"walk" or anim_name == &"hold":
		anim.seek(randf() * anim.current_animation_length if not Engine.is_editor_hint() else 0.0, true)


## Plays the animation for a Fighter state, by name: "stagger", "KO", "held"...
func play_state(state_name: String) -> void:
	var key := state_name.to_lower()
	if key == "ko" and ragdoll_on_ko and not Engine.is_editor_hint():
		var dir := _last_hit if _last_hit.length() > 0.01 else global_basis.z
		start_ragdoll(dir.normalized() * ragdoll_impulse + Vector3.UP * ragdoll_impulse * 0.25)
	elif key == "idle":
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


## Plays a hit reaction. Pass the hit's world direction (attacker to victim) so a KO
## that follows throws the ragdoll the right way.
func play_hit(from_front := true, heavy := false, direction := Vector3.ZERO) -> void:
	if direction != Vector3.ZERO:
		_last_hit = direction
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
		play(start_animation, 0.0)
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
	# bone: [radius, cone swing degrees, twist degrees, mass]
	var spec := {
		&"Hips": [0.12 * g, 0.0, 0.0, 12.0], &"Spine": [0.12 * g, 25.0, 15.0, 9.0], &"Chest": [0.14 * g, 25.0, 15.0, 12.0],
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
		if n == "Nose":
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
	var lib := AnimationLibrary.new()
	var defs := _anim_defs()
	for anim_name in defs:
		lib.add_animation(anim_name, _make_animation(defs[anim_name]))
	anim.add_animation_library(&"", lib)
	anim.animation_finished.connect(_on_animation_finished)


func _on_animation_finished(anim_name: StringName) -> void:
	animation_finished.emit(anim_name)
	if ragdolling:
		return
	if CHAINS.has(anim_name):
		play(CHAINS[anim_name], 0.15)
	elif auto_return_to_idle and RETURNS_TO_IDLE.has(anim_name):
		play(&"walk" if _moving else &"idle", 0.15)


## Pose data rotates each joint about the character's own axes (x right, y up, z back),
## composing down the chain. A bone's local pose rotation that gives the same result is
## rest_local * (M^-1 * q * M), where M is the bone's rest orientation in skeleton space.
func _make_animation(def: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = def["length"]
	var looping: bool = def.get("loop", false)
	a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var keys: Array = def["keys"]
	var skel_path := String(_model.get_path_to(skeleton))
	for joint in ANIM_JOINTS:
		var i: int = _bone[joint]
		var rest_local := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		var m := (_rest_global[i] as Transform3D).basis.get_rotation_quaternion()
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("%s:%s" % [skel_path, joint]))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC if looping else Animation.INTERPOLATION_LINEAR)
		for k in keys:
			var pose: Dictionary = k[1]
			var deg: Vector3 = pose.get(joint, Vector3.ZERO)
			var q := Quaternion.from_euler(deg * (PI / 180.0))
			a.rotation_track_insert_key(tr, k[0], rest_local * (m.inverse() * q * m))
	var hips: int = _bone[&"Hips"]
	var pos := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos, NodePath("%s:Hips" % skel_path))
	var rest := skeleton.get_bone_rest(hips).origin
	for k in keys:
		var pose: Dictionary = k[1]
		a.position_track_insert_key(pos, k[0], rest + (pose.get(&"_hips", Vector3.ZERO) as Vector3) * _scale)
	return a


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


