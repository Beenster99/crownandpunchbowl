class_name RigMixamo
## Motion-captured animations from Mixamo, played on every character model.
##
## tools/blender/mixamo_to_rig.py converts each Mixamo FBX into pose data in the rig's own
## convention (per joint, a rotation in the character's axes composed down our chain,
## relative to our rest pose) plus the hips' travel. make() bakes a clip into bone tracks for
## one model with the same rest_local * (M^-1 * q * M) the keyed poses use, so one clip fits
## every build. CLIPS says which clips the game uses, under which animation names.

const DIR := "res://assets/animations/mixamo/"

## Which clips the game uses, under which names, and how they're cut and timed, is in
## DIR/clips.json, written by tools/mixamo_clips.py. Each entry:
##   clip: file name in DIR (no .json). from / to: Mixamo seconds to keep (to < 0: the end).
##   speed: playback rate (up to hit_at, then speed_after, for strikes).
##   loop: loops (the hips' drift over the loop is taken out). root: "keep" the hips' travel
##   or "inplace" (keeps the height only). mirror: left and right swapped.
##   load / contact: seconds into the animation where a strike is loaded and lands.
##   variant_of: one of the random takes of that animation. replaces: plays as that one.
##   pool: "fight_idle", "calm_idle" or "drunk_idle". then: "idle", or the next animation.

## Set by tools to add every converted clip as "mx_<name>" for previewing.
static var preview_all := false
static var _data := {}


## The converted clip, parsed once and shared.
static func clip(clip_name: String) -> Dictionary:
	if _data.has(clip_name):
		return _data[clip_name]
	var path := DIR + clip_name + ".json"
	var d := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
	if d.is_empty():
		push_warning("RigMixamo: no clip '%s'" % path)
	_data[clip_name] = d
	return d


## Every clip name in DIR.
static func all_clips() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


static var _table := {}


## clips.json, parsed once: animation name -> settings.
static func table() -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(DIR + "clips.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR + "clips.json"))
		if parsed is Dictionary:
			for k in parsed:
				_table[StringName(k)] = parsed[k]
	return _table


## The definitions to add to a rig's library: the table, plus every clip when previewing.
static func definitions() -> Dictionary:
	var defs := table().duplicate()
	if preview_all:
		for c in all_clips():
			defs[StringName("mx_" + c)] = {"clip": c}
	return defs


## Bakes one clip into an Animation for this rig's model. Empty if the clip is missing.
static func make(rig: CharacterRig, def: Dictionary) -> Animation:
	var d := clip(String(def["clip"]))
	if d.is_empty():
		return null
	var fps := float(d.get("fps", 30.0))
	var n := int(d["frames"])
	var f0 := clampi(int(round(float(def.get("from", 0.0)) * fps)), 0, n - 1)
	var to := float(def.get("to", -1.0))
	var f1 := n - 1 if to < 0.0 else clampi(int(round(to * fps)), f0 + 1, n - 1)
	var speed := float(def.get("speed", 1.0))
	var after := float(def.get("speed_after", speed))
	var hit_f := float(def.get("hit_at", -1.0)) * fps
	if hit_f < f0:
		hit_f = f1
	var times := PackedFloat32Array()
	times.resize(f1 - f0 + 1)
	for f in range(f0, f1 + 1):
		var before := minf(f, hit_f) - f0
		times[f - f0] = before / fps / speed + maxf(f - hit_f, 0.0) / fps / after
	var mirror := bool(def.get("mirror", false))
	var looping := bool(def.get("loop", false))
	var a := Animation.new()
	a.length = times[f1 - f0]
	a.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var skel := rig.skeleton
	var skel_path := String(rig._model.get_path_to(skel))
	var joints: Dictionary = d["joints"]
	# Some clips start turned away: turn the whole clip so it starts facing forward (-z).
	var h0: Array = joints["Hips"][f0]
	var hq0 := Quaternion(h0[0], -h0[1] if mirror else h0[1], -h0[2] if mirror else h0[2], h0[3]).normalized()
	var fwd := hq0 * Vector3.FORWARD
	fwd.y = 0.0
	var face := Quaternion.IDENTITY
	if fwd.length() > 0.2:
		face = Quaternion(fwd.normalized(), Vector3.FORWARD)
	for joint in joints:
		# Mirrored: the left joint plays the right one's motion, reflected.
		var j := StringName(_swap_side(joint) if mirror else joint)
		if not rig._bone.has(j):
			continue
		var i: int = rig._bone[j]
		var rest_local := skel.get_bone_rest(i).basis.get_rotation_quaternion()
		var m := (rig._rest_global[i] as Transform3D).basis.get_rotation_quaternion()
		var mi := m.inverse()
		var keys: Array = joints[joint]
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, NodePath("%s:%s" % [skel_path, j]))
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
		for f in range(f0, f1 + 1):
			var k: Array = keys[f]
			var q := Quaternion(k[0], -k[1] if mirror else k[1], -k[2] if mirror else k[2], k[3]).normalized()
			if j == &"Hips":
				q = face * q
			a.rotation_track_insert_key(tr, times[f - f0], rest_local * (mi * q * m))
	var hips: int = rig._bone[&"Hips"]
	var pos := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos, NodePath("%s:Hips" % skel_path))
	var rest := skel.get_bone_rest(hips).origin
	var hk: Array = d["hips"]
	var first := _v(hk[f0])
	var drift := _v(hk[f1]) - first
	if mirror:
		first.x = -first.x
		drift.x = -drift.x
	drift.y = 0.0
	var root := String(def.get("root", "keep"))
	for f in range(f0, f1 + 1):
		var o := _v(hk[f])
		if mirror:
			o.x = -o.x
		if root == "inplace":
			o.x = 0.0
			o.z = 0.0
		elif looping:
			o -= drift * ((f - f0) / float(maxi(f1 - f0, 1)))
			o.x -= first.x
			o.z -= first.z
		else:
			# Start where the character stands; travel from there.
			o.x -= first.x
			o.z -= first.z
		a.position_track_insert_key(pos, times[f - f0], rest + (face * o) * rig._scale)
	return a


static func _swap_side(joint: String) -> String:
	if joint.ends_with("L"):
		return joint.left(-1) + "R"
	if joint.ends_with("R"):
		return joint.left(-1) + "L"
	return joint


static func _v(k: Array) -> Vector3:
	return Vector3(k[0], k[1], k[2])
