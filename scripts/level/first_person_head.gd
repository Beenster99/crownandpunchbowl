class_name FirstPersonHead
extends SkeletonModifier3D
## Shrinks your own head to nothing while the first-person camera sits inside it, so you see
## the pub (and your own fists and guard) instead of the inside of your skull. Added last
## under the local player's skeleton, so it runs after the animation and the hit reactions.
## Only on the local machine: everyone else still sees your head.

var bone := -1


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	if bone < 0:
		bone = skel.find_bone("Head")
		if bone < 0:
			return
	skel.set_bone_pose_scale(bone, Vector3.ONE * 0.001)
