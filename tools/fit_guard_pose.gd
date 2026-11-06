extends SceneTree
## Fits the guard poses on a real character model: finds the shoulder, elbow and wrist angles
## that put the knuckles by the cheek and brow and keep the elbows down in front of (not
## inside) the chest. Prints the angles to paste into the guard poses (CharacterRig._anim_defs,
## RigFightAnims._defence and _stances). Run it on several looks and average the results:
##   godot --headless --path . --script tools/fit_guard_pose.gd -- gaz idle,guard_head,guard_body
var rig
var sk: Skeleton3D
var rest_local := {}
var mg := {}

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	rig = load("res://scripts/actors/character_rig.gd").new()
	rig.look = CharacterLooks.farmer(args[0])
	root.add_child(rig)
	for k in 3: await process_frame
	rig.anim.stop()
	rig.anim.active = false
	sk = rig.skeleton
	for j in CharacterRig.ANIM_JOINTS:
		var i := sk.find_bone(j)
		if i >= 0:
			rest_local[j] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
			mg[j] = sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
	var defs: Dictionary = rig._anim_defs()
	var spec := {
		# anim: [knuckle offset from brow centre L, R], [elbow offset from own shoulder (inward, down) L, R]
		"idle": [Vector3(-0.06, -0.01, -0.18), Vector3(0.075, -0.03, -0.08), Vector2(0.07, 0.17), Vector2(0.06, 0.18)],
		"guard_head": [Vector3(-0.065, 0.0, -0.07), Vector3(0.065, 0.0, -0.07), Vector2(0.09, 0.15), Vector2(0.09, 0.15)],
		"idle_brawler": [Vector3(-0.06, -0.01, -0.18), Vector3(0.075, -0.03, -0.08), Vector2(0.07, 0.17), Vector2(0.06, 0.18)],
		"idle_wary": [Vector3(-0.06, -0.01, -0.18), Vector3(0.075, -0.03, -0.08), Vector2(0.07, 0.17), Vector2(0.06, 0.18)],
		"guard_body": [Vector3(-0.07, -0.08, -0.07), Vector3(0.07, -0.08, -0.07), Vector2(0.05, 0.22), Vector2(0.05, 0.22)],
	}
	for a in args[1].split(","):
		var pose: Dictionary = defs[StringName(a)]["keys"][0][1]
		var sp: Array = spec[a]
		var out := "%s:" % a
		for side in ["L", "R"]:
			var si := 0 if side == "L" else 1
			var res := _fit(pose, side, sp[si], sp[2 + si])
			pose = res[0]
			out += "  %s S%s E%s H%s err %.3f" % [side, _v(pose[StringName("Shoulder" + side)]),
				_v(pose[StringName("Elbow" + side)]), _v(pose[StringName("Hand" + side)]), res[1]]
		print(out)
		_report(pose)
	quit()

func _v(v: Vector3) -> String:
	return "(%d, %d, %d)" % [roundi(v.x), roundi(v.y), roundi(v.z)]

func _apply(pose: Dictionary) -> void:
	var p := CharacterRig._expand(pose)
	for j in rest_local:
		var q := Quaternion.from_euler((p.get(j, Vector3.ZERO) as Vector3) * (PI / 180.0))
		var m: Quaternion = mg[j]
		sk.set_bone_pose_rotation(sk.find_bone(j), rest_local[j] * (m.inverse() * q * m))

func _pos(n: String) -> Vector3:
	return sk.get_bone_global_pose(sk.find_bone(n)).origin * rig._model.scale

func _cost(pose: Dictionary, side: String, kt: Vector3, et: Vector2) -> float:
	_apply(pose)
	var brow := (_pos("BrowL") + _pos("BrowR")) * 0.5
	var k := _pos("Index1" + side) - brow
	var sh := _pos("Shoulder" + side)
	var e := _pos("Elbow" + side)
	var chest := _pos("Chest")
	var inward := (e.x - sh.x) * (1.0 if side == "L" else -1.0)
	var c := (k - kt).length_squared() * 10.0
	c += (inward - et.x) * (inward - et.x) * 3.0 + ((sh.y - e.y) - et.y) * ((sh.y - e.y) - et.y) * 3.0
	var clear := e.z - (chest.z - 0.14)
	if clear > 0.0:
		c += clear * clear * 20.0
	# Fist upright: the knuckles straight above the wrist, not tipped.
	var w := _pos("Hand" + side)
	var up := (_pos("Index1" + side) - w).normalized()
	c += (1.0 - up.y) * 0.01
	return c

func _fit(pose: Dictionary, side: String, kt: Vector3, et: Vector2) -> Array:
	var keys := [StringName("Shoulder" + side), StringName("Elbow" + side), StringName("Hand" + side)]
	var best := pose.duplicate()
	var best_c := _cost(best, side, kt, et)
	var step := 16.0
	while step >= 0.5:
		var improved := true
		while improved:
			improved = false
			for k in keys:
				for axis in 3:
					if k == keys[1] and axis != 0:
						continue
					if k == keys[2] and axis == 1:
						continue
					for d in [-step, step]:
						var t := best.duplicate()
						var v: Vector3 = t.get(k, Vector3.ZERO)
						v[axis] += d
						if k == keys[1]:
							v.x = clampf(v.x, 0.0, 150.0)
						t[k] = v
						var c := _cost(t, side, kt, et)
						if c < best_c - 1e-7:
							best_c = c
							best = t
							improved = true
		step *= 0.5
	return [best, best_c]

func _report(pose: Dictionary) -> void:
	_apply(pose)
	var brow := (_pos("BrowL") + _pos("BrowR")) * 0.5
	var s := "   "
	for n in ["Index1L", "Index1R", "ElbowL", "ElbowR", "ShoulderL", "ShoulderR", "Chest"]:
		var p := _pos(n) - brow
		s += " %s(%.2f,%.2f,%.2f)" % [n, p.x, p.y, p.z]
	print(s)
