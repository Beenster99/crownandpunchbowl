class_name HeadSnap
extends SkeletonModifier3D
## When a punch connects, the head snaps: straight back from a jab or an uppercut, round to
## the side from a hook, and a body shot folds the chest forward over the fist. It's a
## damped spring layered on top of whatever animation is playing (it runs after the
## AnimationPlayer as a skeleton modifier), so every hit looks a little different and the
## head carries on wobbling for a moment after the hit animation has moved on.
## Purely cosmetic and local to each peer. FighterVisual puts one on each rig's skeleton.

const STIFFNESS := 210.0     ## spring pull back to the animated pose
const DAMPING := 15.0        ## how quickly the wobble dies away
const MAX_ANGLE := 0.95      ## radians, the furthest the head can be knocked
const MAX_FOLD := 0.5        ## radians, the furthest a body shot folds the chest

var fighter: Fighter
## The CharacterRig, so the spring can stand down while it's a ragdoll.
var rig: Node3D

var _head := -1
var _neck := -1
var _chest := -1
# Rotation vectors (axis * angle) in the fighter's local space.
var _snap := Vector3.ZERO
var _snap_v := Vector3.ZERO
var _fold := Vector3.ZERO
var _fold_v := Vector3.ZERO


func setup(f: Fighter, r: Node3D) -> void:
	fighter = f
	rig = r


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_head = skel.find_bone("Head")
	_neck = skel.find_bone("Neck")
	for n in ["Spine2", "Chest", "Spine1"]:
		_chest = skel.find_bone(n)
		if _chest >= 0:
			break
	if fighter != null:
		fighter.hit_taken.connect(_on_hit_taken)


## How far the head is knocked right now, in radians.
func snap_angle() -> float:
	return _snap.length()


## Knock the head. `push` is the world direction the blow drives the head; `strength` is in
## radians per second. Hooks push sideways, which also turns the face away.
func knock(push: Vector3, strength: float, body := false) -> void:
	if fighter == null:
		return
	var d := fighter.global_basis.inverse() * push
	d.y = 0.0
	if d.length() < 0.01:
		return
	d = d.normalized()
	if body:
		# A dig to the body: the chest folds over towards the puncher (against the push).
		_fold_v += Vector3.UP.cross(-d) * strength * 0.7
		_snap_v += Vector3.UP.cross(-d) * strength * 0.25  # the chin drops with it
		return
	# The top of the head goes the way it's pushed...
	_snap_v += Vector3.UP.cross(d) * strength
	# ...and a blow from the side twists the face round with it (x is the fighter's right).
	_snap_v += Vector3.UP * (-d.x * strength * 0.9)


func _on_hit_taken(info: Dictionary) -> void:
	if bool(info.get("blocked", false)) or bool(info.get("slipped", false)) \
			or bool(info.get("parried", false)):
		return
	var push: Vector3 = info.get("direction", Vector3.ZERO)
	if push.length() < 0.01:
		return
	var zone := StringName(info.get("zone", &"head"))
	var dmg := float(info.get("damage", 0.0))
	var strength := clampf(7.0 + dmg * 0.7, 7.0, 22.0)
	if bool(info.get("heavy", false)):
		strength *= 1.3
	var move := String(info.get("move", ""))
	if move.contains("uppercut") and zone == &"head":
		# Up through the chin: the head goes back and up, not sideways.
		push = push.normalized() * 1.3
	knock(push, strength, zone != &"head")


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or fighter == null or _head < 0:
		return
	if rig != null and bool(rig.get("ragdolling")):
		_snap = Vector3.ZERO
		_snap_v = Vector3.ZERO
		_fold = Vector3.ZERO
		_fold_v = Vector3.ZERO
		return
	delta = minf(delta, 0.05)
	_snap_v += (-STIFFNESS * _snap - DAMPING * _snap_v) * delta
	_snap += _snap_v * delta
	_fold_v += (-STIFFNESS * 0.7 * _fold - DAMPING * _fold_v) * delta
	_fold += _fold_v * delta
	if _snap.length() > MAX_ANGLE:
		_snap = _snap.normalized() * MAX_ANGLE
	if _fold.length() > MAX_FOLD:
		_fold = _fold.normalized() * MAX_FOLD
	if _snap.length() < 0.001 and _snap_v.length() < 0.01 and _fold.length() < 0.001 \
			and _fold_v.length() < 0.01:
		return
	# Fighter-local rotation vectors into skeleton space.
	var to_skel := skel.global_basis.orthonormalized().inverse() * fighter.global_basis.orthonormalized()
	if _chest >= 0 and _fold.length() > 0.001:
		_rotate_bone(skel, _chest, to_skel * _fold)
	if _neck >= 0:
		_rotate_bone(skel, _neck, to_skel * _snap * 0.4)
		_rotate_bone(skel, _head, to_skel * _snap * 0.6)
	else:
		_rotate_bone(skel, _head, to_skel * _snap)


## Turns a bone about its own origin by a skeleton-space rotation vector.
func _rotate_bone(skel: Skeleton3D, bone: int, rotvec: Vector3) -> void:
	var angle := rotvec.length()
	if angle < 0.0001:
		return
	var g := skel.get_bone_global_pose(bone)
	g.basis = Basis(rotvec / angle, angle) * g.basis
	skel.set_bone_global_pose(bone, g)
