class_name RigReactor
extends SkeletonModifier3D
## Procedural layer on top of CharacterRig's animations, so a fight doesn't look scripted:
##
## - Head snap: a punch that lands whips the head away from it on a damped spring (back for
##   a straight shot, round to the side for a hook, up for an uppercut) and lets it wobble
##   back, whatever animation is playing underneath.
## - Body flinch: body shots fold the torso the same way.
## - Head movement (right stick): slips left and right, ducks and leans back, bending the
##   spine and the legs together so the feet stay on the floor.
## - Breathing: the chest rises and falls, harder when hurt.
##
## Runs after the AnimationPlayer every frame (it's a SkeletonModifier3D under the
## skeleton) and is switched off while the body is a ragdoll. Purely cosmetic and local.

## Spring for the head and neck.
const HEAD_K := 150.0
const HEAD_C := 13.0
## Spring for the torso.
const BODY_K := 90.0
const BODY_C := 10.0
## The furthest the springs can bend, radians.
const MAX_HEAD := 1.1
const MAX_BODY := 0.7
## How fast the head-bob follows the stick.
const BOB_FOLLOW := 14.0

var rig: CharacterRig
## Breath rate scale, 1 calm, up to 2 when hurt and blowing.
var breath := 1.0

var _head := Vector3.ZERO    # rotation vector, character frame
var _head_v := Vector3.ZERO
var _body := Vector3.ZERO
var _body_v := Vector3.ZERO
var _bob_target := Vector2.ZERO
var _bob := Vector2.ZERO
var _t := 0.0
var _bones := {}
var _leg := 1.0  # hip height at rest, skeleton units


func setup(r: CharacterRig, skel: Skeleton3D) -> void:
	rig = r
	for n in [&"Hips", &"Spine", &"Spine2", &"Chest", &"Neck", &"Head", &"HipL", &"HipR", &"KneeL", &"KneeR", &"FootL", &"FootR"]:
		var i := skel.find_bone(n)
		if i >= 0:
			_bones[n] = i
	if _bones.has(&"Hips"):
		_leg = maxf(skel.get_bone_global_rest(_bones[&"Hips"]).origin.y, 0.1)


## Right stick: x slips (+ right), y ducks (+ down) or leans back (- up). -1..1.
func set_bob(v: Vector2) -> void:
	_bob_target = v.limit_length(1.0)


## A blow landing. `push` is the direction it shoves the victim, in the character's own
## frame (x right, z back). `zone` is head, body or groin. `strength` is about 1 for a jab,
## 2 for a big hook, more for a haymaker.
func hit(push: Vector3, zone: StringName, strength: float, uppercut := false) -> void:
	push.y = 0.0
	if push.length() < 0.01:
		push = Vector3.BACK
	push = push.normalized()
	# Turning about UP x push tips the top of the bone towards push.
	var tip := Vector3.UP.cross(push)
	match zone:
		&"body", &"groin":
			# Folds forward round the fist whichever way it came from, a little to the side.
			_body_v += (Vector3(-1.0, 0, 0) * 0.9 + tip * 0.35) * 5.0 * strength
			_head_v += Vector3(-2.0, 0, 0) * strength
		_:
			_head_v += tip * 9.0 * strength
			# A hook (pushed sideways) twists the head round as well as tipping it.
			_head_v.y += -push.x * 8.0 * strength
			if uppercut:
				_head_v.x += 10.0 * strength
			_body_v += tip * 1.6 * strength


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or rig == null or _bones.size() < 6:
		return
	delta = minf(delta, 0.05)
	_t += delta
	_step(delta)
	var lying := CharacterRig.ON_FLOOR.has(rig.current) or rig.current in [&"groin_down", &"groin_hold", &"get_up"]
	# Head movement: slips bend the spine sideways, the duck folds forward over bent legs.
	var bob := _bob if not lying else Vector2.ZERO
	var spine := Vector3(-0.38 * maxf(bob.y, 0.0) + 0.22 * maxf(-bob.y, 0.0), 0.08 * bob.x, -0.32 * bob.x)
	var drop := (0.12 * maxf(bob.y, 0.0) + 0.03 * absf(bob.x)) * _leg
	var hips_shift := Vector3(0.07 * bob.x, 0.0, 0.05 * maxf(-bob.y, 0.0) - 0.02 * maxf(bob.y, 0.0)) * _leg
	# Breathing.
	var br := sin(_t * 1.7 * breath) * deg_to_rad(1.2 + 1.5 * (breath - 1.0))
	var body := _body + spine * 0.5
	if drop > 0.0001 or hips_shift.length() > 0.0001:
		var hi: int = _bones[&"Hips"]
		skel.set_bone_pose_position(hi, skel.get_bone_pose_position(hi) + hips_shift - Vector3(0, drop, 0))
		_bend_legs(skel, drop)
	_rotate(skel, &"Spine2", body * 0.5 + spine * 0.25)
	_rotate(skel, &"Chest", body * 0.5 + spine * 0.25 + Vector3(-br, 0, 0))
	# The head stays level with the eyes on the man in front while slipping.
	var head := _head
	if not lying:
		head += Vector3(-spine.x * 0.6, 0, -spine.z * 0.6)
	_rotate(skel, &"Neck", head * 0.4)
	_rotate(skel, &"Head", head * 0.6 + Vector3(br * 0.5, 0, 0))


func _step(delta: float) -> void:
	_bob = _bob.lerp(_bob_target, 1.0 - exp(-BOB_FOLLOW * delta))
	var steps := 2
	var h := delta / steps
	for _i in steps:
		_head_v += (-_head * HEAD_K - _head_v * HEAD_C) * h
		_head += _head_v * h
		_body_v += (-_body * BODY_K - _body_v * BODY_C) * h
		_body += _body_v * h
	if _head.length() > MAX_HEAD:
		_head = _head.normalized() * MAX_HEAD
	if _body.length() > MAX_BODY:
		_body = _body.normalized() * MAX_BODY


## Rotates a bone by `rv` (a rotation vector in the character's frame) about its own joint,
## on top of whatever pose it has.
func _rotate(skel: Skeleton3D, bone: StringName, rv: Vector3) -> void:
	if not _bones.has(bone) or rv.length() < 0.0001:
		return
	var i: int = _bones[bone]
	var parent := skel.get_bone_parent(i)
	var pq := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var q := Quaternion(rv.normalized(), rv.length())
	var local := skel.get_bone_pose_rotation(i)
	skel.set_bone_pose_rotation(i, (pq.inverse() * q * pq) * local)


## Lowers the hips by `drop` with the feet staying put: thighs forward, knees back, feet flat.
func _bend_legs(skel: Skeleton3D, drop: float) -> void:
	var a := acos(clampf(1.0 - drop / _leg, -1.0, 1.0))
	for s in ["L", "R"]:
		_rotate(skel, StringName("Hip" + s), Vector3(a, 0, 0))
		_rotate(skel, StringName("Knee" + s), Vector3(-2.0 * a, 0, 0))
		_rotate(skel, StringName("Foot" + s), Vector3(a, 0, 0))
