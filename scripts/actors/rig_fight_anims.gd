class_name RigFightAnims
extends RefCounted
## The extended fight set for CharacterRig: variants of every punch, body shots, kicks,
## the clinch knee, shoulder charge and groin kick, head and body guards, parries, slips,
## directional dodges and footwork, and the hit reactions that go with them (body shots
## doubling someone over, a kick in the balls putting them on all fours).
##
## Poses use the same convention as CharacterRig._anim_defs(): Euler degrees in the
## character's own axes (x right, y up, z back). +x swings a limb forward, -x on a knee
## bends it, -x on the spine leans forward, +x on the head tips it back, +y turns left,
## +z on the spine leans left, -z on the left shoulder (+z on the right) lifts the arm out.
## "_hips" moves the hips (in model units), the "_" scalars drive fists, face and heels.
##
## Every strike keeps roughly the load/contact timing of the move it varies, so the
## combat wind-ups (load_time/contact_time) line up whichever variant plays.


static func _w(base: Dictionary, changes: Dictionary) -> Dictionary:
	return CharacterRig._with(base, changes)


## The pose at key `i` of an existing def.
static func _key(defs: Dictionary, anim_name: StringName, i: int) -> Dictionary:
	return defs[anim_name]["keys"][i][1]


## Adds the fight set to `defs`. `guard` is the boxing guard, `pain` the hurt face and
## loose fists, `kneel` the hips offset that puts the knees on the floor.
static func add(defs: Dictionary, guard: Dictionary, pain: Dictionary, kneel: float) -> void:
	_stances(defs, guard)
	_footwork(defs, guard)
	_punch_variants(defs, guard)
	_body_shots(defs, guard)
	_kicks_and_dirty(defs, guard)
	_defence(defs, guard)
	_reactions(defs, guard, pain, kneel)


# --- Stances: everyone squares up a bit differently --------------------------

static func _stances(defs: Dictionary, guard: Dictionary) -> void:
	# The pub brawler: square on, chest out, chin up, fists low and loose, rolling the
	# shoulders. Comes forward like he owns the place.
	var brawl := _w(guard, {&"Hips": Vector3(0, -6, 0), &"Spine": Vector3(2, 4, 0), &"Chest": Vector3(4, 0, 0),
		&"Head": Vector3(4, 2, 0), &"ShoulderL": Vector3(40, 0, 12), &"ElbowL": Vector3(100, 0, 0),
		&"ShoulderR": Vector3(34, 0, -14), &"ElbowR": Vector3(104, 0, 0),
		&"HipL": Vector3(8, 0, -8), &"KneeL": Vector3(-10, 0, 0), &"HipR": Vector3(-4, 0, 8), &"KneeR": Vector3(-8, 0, 0),
		&"_hips": Vector3(0, -0.01, 0), &"_brow": Vector3(1, 0, 0)})
	defs[&"idle_brawler"] = {"length": 1.8, "loop": true, "keys": [
		[0.0, brawl],
		[0.45, _w(brawl, {&"Spine": Vector3(4, 10, -4), &"ShoulderL": Vector3(46, 0, 14), &"ShoulderR": Vector3(30, 0, -10),
			&"_hips": Vector3(0.015, -0.015, 0)})],
		[0.9, _w(brawl, {&"Head": Vector3(8, -4, 0), &"Chest": Vector3(6, 0, 0)})],
		[1.35, _w(brawl, {&"Spine": Vector3(4, -4, 4), &"ShoulderL": Vector3(36, 0, 10), &"ShoulderR": Vector3(40, 0, -16),
			&"_hips": Vector3(-0.015, -0.015, 0)})],
		[1.8, brawl],
	]}
	# The wary one: crouched, weight back, lead hand out open to keep you off, the rear
	# fist by the cheek. Circles and waits.
	var wary := _w(guard, {&"Hips": Vector3(0, -24, 0), &"Spine": Vector3(-14, 12, 0), &"Head": Vector3(-12, 10, 0),
		&"ShoulderL": Vector3(70, 0, 6), &"ElbowL": Vector3(70, 0, 0), &"HandL": Vector3(-24, 0, 0), &"_fistL": Vector3(0.2, 0, 0),
		&"ShoulderR": Vector3(56, 0, -10), &"ElbowR": Vector3(136, 0, 0),
		&"HipL": Vector3(22, 0, -8), &"KneeL": Vector3(-26, 0, 0), &"HipR": Vector3(-14, 0, 8), &"KneeR": Vector3(-30, 0, 0),
		&"_hips": Vector3(0, -0.06, 0.03)})
	defs[&"idle_wary"] = {"length": 1.5, "loop": true, "keys": [
		[0.0, wary],
		[0.4, _w(wary, {&"ShoulderL": Vector3(76, 0, 2), &"ElbowL": Vector3(56, 0, 0), &"_hips": Vector3(0.01, -0.07, 0.025)})],
		[0.75, _w(wary, {&"Spine": Vector3(-16, 16, 0), &"Head": Vector3(-14, 6, 0)})],
		[1.1, _w(wary, {&"ShoulderL": Vector3(66, 0, 10), &"ElbowL": Vector3(84, 0, 0), &"_hips": Vector3(-0.01, -0.065, 0.035)})],
		[1.5, wary],
	]}


# --- Footwork: strafing and backing off in the guard ---------------------------

static func _footwork(defs: Dictionary, guard: Dictionary) -> void:
	# Backing off: the forward walk run in reverse reads as a backpedal.
	var walk: Dictionary = defs[&"walk"]
	var back_keys := []
	var len_w: float = walk["length"]
	var wk: Array = walk["keys"]
	for i in range(wk.size() - 1, -1, -1):
		back_keys.append([len_w - float(wk[i][0]), _w(wk[i][1], {&"Spine": Vector3(-4, 10, 0), &"_hips": Vector3(0, -0.02, 0.02)})])
	defs[&"walk_back"] = {"length": len_w, "loop": true, "keys": back_keys}
	# Side shuffle to the left: the lead foot goes first, the rear foot follows. Feet never cross.
	var wide := _w(guard, {&"HipL": Vector3(16, 0, -18), &"KneeL": Vector3(-22, 0, 0), &"HipR": Vector3(-10, 0, 14),
		&"KneeR": Vector3(-20, 0, 0), &"_hips": Vector3(-0.02, -0.04, 0)})
	var lead_up := _w(guard, {&"HipL": Vector3(22, 0, -22), &"KneeL": Vector3(-40, 0, 0), &"_hips": Vector3(-0.01, -0.02, 0),
		&"Spine": Vector3(-8, 9, 6)})
	var rear_up := _w(guard, {&"HipR": Vector3(-4, 0, 0), &"KneeR": Vector3(-44, 0, 0), &"HipL": Vector3(16, 0, -10),
		&"_hips": Vector3(-0.025, -0.02, 0), &"Spine": Vector3(-8, 9, -4)})
	defs[&"strafe_l"] = {"length": 0.7, "loop": true, "keys": [
		[0.0, guard], [0.17, lead_up], [0.35, wide, "io"], [0.52, rear_up], [0.7, guard, "io"],
	]}
	var wide_r := _w(guard, {&"HipL": Vector3(16, 0, 8), &"KneeL": Vector3(-20, 0, 0), &"HipR": Vector3(-10, 0, 22),
		&"KneeR": Vector3(-22, 0, 0), &"_hips": Vector3(0.02, -0.04, 0)})
	var rear_out := _w(guard, {&"HipR": Vector3(-6, 0, 24), &"KneeR": Vector3(-42, 0, 0), &"_hips": Vector3(0.01, -0.02, 0),
		&"Spine": Vector3(-8, 9, -6)})
	var lead_in := _w(guard, {&"HipL": Vector3(20, 0, 2), &"KneeL": Vector3(-44, 0, 0), &"HipR": Vector3(-10, 0, 12),
		&"_hips": Vector3(0.025, -0.02, 0), &"Spine": Vector3(-8, 9, 4)})
	defs[&"strafe_r"] = {"length": 0.7, "loop": true, "keys": [
		[0.0, guard], [0.17, rear_out], [0.35, wide_r, "io"], [0.52, lead_in], [0.7, guard, "io"],
	]}


# --- Punch variants -----------------------------------------------------------

static func _punch_variants(defs: Dictionary, guard: Dictionary) -> void:
	var jab_load := _key(defs, &"punch_l", 1)
	var jab_hit := _key(defs, &"punch_l", 2)
	# Jab with the head slipped off the centre line, to the right, as it goes out.
	var jab_slip := _w(jab_hit, {&"Spine": Vector3(-14, 2, -10), &"Head": Vector3(-12, 22, -10), &"_hips": Vector3(0.035, -0.04, -0.06),
		&"KneeR": Vector3(-20, 0, 0)})
	defs[&"punch_l_b"] = {"length": 0.4, "load": 0.06, "contact": 0.1, "keys": [
		[0.0, guard], [0.06, jab_load, "io"], [0.1, jab_slip, "snap"],
		[0.16, _w(jab_slip, {&"ShoulderL": Vector3(86, 8, 2), &"ElbowL": Vector3(14, 0, 0)}), "lin"],
		[0.26, _w(guard, {&"ShoulderL": Vector3(68, 4, 4), &"ElbowL": Vector3(92, 0, 0), &"_hips": Vector3(0.02, -0.03, -0.02)}), "out"],
		[0.4, guard],
	]}
	# The double jab: a short range-finder, half back, then the real one. Lands on the second.
	var paw := _w(jab_hit, {&"ShoulderL": Vector3(80, 6, 4), &"ElbowL": Vector3(40, 0, 0), &"Hips": Vector3(0, -20, 0),
		&"_hips": Vector3(0, -0.025, -0.03)})
	defs[&"punch_l_c"] = {"length": 0.5, "load": 0.04, "contact": 0.16, "keys": [
		[0.0, guard], [0.04, paw, "snap"], [0.09, _w(guard, {&"ShoulderL": Vector3(66, 0, 4), &"ElbowL": Vector3(96, 0, 0),
			&"_hips": Vector3(0, -0.025, -0.03)}), "out"],
		[0.16, _w(jab_hit, {&"_hips": Vector3(0, -0.03, -0.1)}), "snap"],
		[0.22, _w(jab_hit, {&"ShoulderL": Vector3(87, 8, 2), &"ElbowL": Vector3(12, 0, 0), &"_hips": Vector3(0, -0.03, -0.1)}), "lin"],
		[0.34, _w(guard, {&"ShoulderL": Vector3(70, 4, 4), &"ElbowL": Vector3(90, 0, 0), &"_hips": Vector3(0, -0.02, -0.05)}), "out"],
		[0.5, guard],
	]}
	# Overhand right: the elbow comes up and the fist loops over the top, the body rolls down
	# behind it. A proper pub right hand.
	var cross_load := _key(defs, &"punch_r", 1)
	var over_load := _w(cross_load, {&"ShoulderR": Vector3(60, 0, -46), &"ElbowR": Vector3(118, 0, 0), &"Spine": Vector3(0, 0, -6)})
	var over_hit := _w(_key(defs, &"punch_r", 2), {&"ShoulderR": Vector3(118, -14, -26), &"ElbowR": Vector3(36, 0, 0),
		&"HandR": Vector3(-20, 0, 0), &"Spine": Vector3(-26, 18, 12), &"Head": Vector3(-14, -14, 0),
		&"KneeL": Vector3(-34, 0, 0), &"_hips": Vector3(-0.01, -0.07, -0.11)})
	defs[&"punch_r_b"] = {"length": 0.52, "load": 0.09, "contact": 0.15, "keys": [
		[0.0, guard], [0.09, over_load, "io"], [0.15, over_hit, "snap"],
		[0.22, _w(over_hit, {&"ShoulderR": Vector3(96, -14, -20), &"ElbowR": Vector3(30, 0, 0), &"Spine": Vector3(-30, 20, 12)}), "out"],
		[0.34, _w(guard, {&"ShoulderR": Vector3(64, 0, -6), &"ElbowR": Vector3(100, 0, 0), &"_hips": Vector3(0, -0.04, -0.05)})],
		[0.52, guard],
	]}
	# Wide looping hooks: arm straighter, more shoulder, the whole body thrown round.
	var hook_hit := _key(defs, &"hook_l", 2)
	var loop_hit := _w(hook_hit, {&"ShoulderL": Vector3(10, -50, -80), &"ElbowL": Vector3(62, 0, 0), &"Hips": Vector3(0, -44, 0),
		&"Spine": Vector3(-14, -26, 6), &"_hips": Vector3(0.02, -0.045, -0.07)})
	defs[&"hook_l_b"] = {"length": 0.58, "load": 0.11, "contact": 0.17, "keys": [
		[0.0, guard], [0.11, _w(_key(defs, &"hook_l", 1), {&"ShoulderL": Vector3(4, -4, -70), &"ElbowL": Vector3(80, 0, 0),
			&"Hips": Vector3(0, 12, 0)}), "io"],
		[0.17, loop_hit, "snap"],
		[0.26, _w(loop_hit, {&"Hips": Vector3(0, -54, 0), &"Spine": Vector3(-14, -34, 6), &"ShoulderL": Vector3(10, -66, -74)}), "out"],
		[0.4, _w(guard, {&"Hips": Vector3(0, -26, 0), &"ShoulderL": Vector3(62, 0, -16), &"ElbowL": Vector3(108, 0, 0)})],
		[0.58, guard],
	]}
	defs[&"hook_r_b"] = CharacterRig._mirror_strike(defs[&"hook_l_b"], guard)
	# Lead uppercut, off the front foot.
	defs[&"uppercut_l"] = CharacterRig._mirror_strike(defs[&"uppercut_r"], guard)
	# A short, chopping uppercut in close: barely any dip, all hips.
	var up_hit := _key(defs, &"uppercut_r", 2)
	var chop := _w(up_hit, {&"ShoulderR": Vector3(84, 0, -8), &"ElbowR": Vector3(110, 0, 0), &"Spine": Vector3(-6, 20, -4),
		&"_hips": Vector3(-0.01, -0.02, -0.05)})
	defs[&"uppercut_r_b"] = {"length": 0.5, "load": 0.1, "contact": 0.16, "keys": [
		[0.0, guard],
		[0.1, _w(guard, {&"Hips": Vector3(0, -24, 0), &"ShoulderR": Vector3(24, 0, -4), &"ElbowR": Vector3(118, 0, 0),
			&"KneeL": Vector3(-28, 0, 0), &"KneeR": Vector3(-28, 0, 0), &"_hips": Vector3(0.01, -0.06, 0.01)}), "io"],
		[0.16, chop, "snap"], [0.23, _w(chop, {&"ShoulderR": Vector3(92, 0, -8)}), "out"],
		[0.36, _w(guard, {&"ShoulderR": Vector3(64, 0, -6), &"ElbowR": Vector3(120, 0, 0)})], [0.5, guard],
	]}
	# A headbutt off a grab of the lapels: hands in, pull, and the forehead goes in.
	var lapels := _w(guard, {&"ShoulderL": Vector3(82, 0, 14), &"ElbowL": Vector3(70, 0, 0), &"ShoulderR": Vector3(82, 0, -14),
		&"ElbowR": Vector3(70, 0, 0), &"_fistL": Vector3(0.9, 0, 0), &"_fistR": Vector3(0.9, 0, 0)})
	var nut := _w(lapels, {&"Spine": Vector3(-30, 0, 0), &"Chest": Vector3(-10, 0, 0), &"Head": Vector3(-30, 0, 0),
		&"ShoulderL": Vector3(60, 0, 14), &"ElbowL": Vector3(110, 0, 0), &"ShoulderR": Vector3(60, 0, -14), &"ElbowR": Vector3(110, 0, 0),
		&"_hips": Vector3(0, -0.03, -0.12), &"_brow": Vector3(1, 0, 0)})
	defs[&"headbutt_b"] = {"length": 0.6, "load": 0.16, "contact": 0.24, "keys": [
		[0.0, guard], [0.08, lapels, "snap"],
		[0.16, _w(lapels, {&"Spine": Vector3(14, 0, 0), &"Head": Vector3(30, 0, 0), &"_hips": Vector3(0, 0, 0.05)}), "io"],
		[0.24, nut, "snap"], [0.34, nut, "lin"], [0.6, guard, "out"],
	]}


# --- Body shots ---------------------------------------------------------------

static func _body_shots(defs: Dictionary, guard: Dictionary) -> void:
	# Level change: the knees do the work so the fist lands at belly height while the eyes
	# stay up. The other hand stays home.
	var dip := {&"KneeL": Vector3(-44, 0, 0), &"KneeR": Vector3(-36, 0, 0), &"HipL": Vector3(30, 0, -8), &"HipR": Vector3(-4, 0, 8)}
	var jab_hit := _key(defs, &"punch_l", 2)
	var bjab := _w(_w(jab_hit, dip), {&"Spine": Vector3(-26, 2, -4), &"Head": Vector3(-2, 18, 0), &"ShoulderL": Vector3(60, 8, 4),
		&"ElbowL": Vector3(10, 0, 0), &"_hips": Vector3(0, -0.12, -0.08)})
	defs[&"jab_body"] = {"length": 0.44, "load": 0.07, "contact": 0.12, "keys": [
		[0.0, guard], [0.07, _w(_w(_key(defs, &"punch_l", 1), dip), {&"_hips": Vector3(0, -0.09, 0.0), &"Spine": Vector3(-16, 12, 0)}), "io"],
		[0.12, bjab, "snap"], [0.18, _w(bjab, {&"ElbowL": Vector3(18, 0, 0)}), "lin"],
		[0.3, _w(guard, {&"ShoulderL": Vector3(64, 4, 4), &"ElbowL": Vector3(96, 0, 0), &"_hips": Vector3(0, -0.06, -0.04)}), "out"],
		[0.44, guard],
	]}
	var cross_hit := _key(defs, &"punch_r", 2)
	var bcross := _w(_w(cross_hit, dip), {&"Spine": Vector3(-28, 16, 6), &"Head": Vector3(-4, -10, 0), &"ShoulderR": Vector3(62, -8, -6),
		&"_hips": Vector3(-0.01, -0.13, -0.1)})
	defs[&"cross_body"] = {"length": 0.5, "load": 0.09, "contact": 0.14, "keys": [
		[0.0, guard], [0.09, _w(_w(_key(defs, &"punch_r", 1), dip), {&"_hips": Vector3(0.01, -0.1, 0.03)}), "io"],
		[0.14, bcross, "snap"], [0.2, _w(bcross, {&"ElbowR": Vector3(16, 0, 0)}), "lin"],
		[0.34, _w(guard, {&"ShoulderR": Vector3(64, 0, -4), &"ElbowR": Vector3(100, 0, 0), &"_hips": Vector3(0, -0.06, -0.04)}), "out"],
		[0.5, guard],
	]}
	# Shovel hook to the liver: elbow low and tight, the fist driven up under the ribs as the
	# lead side dips.
	var hook_hit := _key(defs, &"hook_l", 2)
	var liver := _w(_w(hook_hit, dip), {&"ShoulderL": Vector3(28, -34, -42), &"ElbowL": Vector3(96, 0, 0), &"HandL": Vector3(10, 0, 0),
		&"Spine": Vector3(-24, -18, 12), &"Head": Vector3(-4, 18, 0), &"_hips": Vector3(0.0, -0.12, -0.05)})
	defs[&"hook_l_body"] = {"length": 0.54, "load": 0.1, "contact": 0.16, "keys": [
		[0.0, guard],
		[0.1, _w(_w(_key(defs, &"hook_l", 1), dip), {&"ShoulderL": Vector3(16, -6, -40), &"Spine": Vector3(-18, 14, 14),
			&"_hips": Vector3(-0.03, -0.11, 0)}), "io"],
		[0.16, liver, "snap"],
		[0.24, _w(liver, {&"Hips": Vector3(0, -42, 0), &"ShoulderL": Vector3(32, -46, -38)}), "out"],
		[0.38, _w(guard, {&"Hips": Vector3(0, -22, 0), &"ShoulderL": Vector3(60, 0, -12), &"ElbowL": Vector3(112, 0, 0),
			&"_hips": Vector3(0, -0.06, -0.02)})],
		[0.54, guard],
	]}
	defs[&"hook_r_body"] = CharacterRig._mirror_strike(defs[&"hook_l_body"], guard)
	# Rising uppercut to the solar plexus: same as the head one but the fist stops at the chest.
	var up_hit := _key(defs, &"uppercut_r", 2)
	var bup := _w(_w(up_hit, dip), {&"ShoulderR": Vector3(62, 0, -10), &"ElbowR": Vector3(96, 0, 0), &"Spine": Vector3(-18, 16, -6),
		&"_hips": Vector3(-0.01, -0.09, -0.06)})
	defs[&"uppercut_body"] = {"length": 0.56, "load": 0.12, "contact": 0.18, "keys": [
		[0.0, guard], [0.12, _w(_key(defs, &"uppercut_r", 1), {&"_hips": Vector3(0.02, -0.13, 0.02)}), "io"],
		[0.18, bup, "snap"], [0.26, _w(bup, {&"ShoulderR": Vector3(70, 0, -10)}), "out"],
		[0.4, _w(guard, {&"ShoulderR": Vector3(66, 0, -6), &"ElbowR": Vector3(120, 0, 0), &"_hips": Vector3(0, -0.05, -0.03)})],
		[0.56, guard],
	]}


# --- Kicks, knees, charges and the dirty stuff --------------------------------

static func _kicks_and_dirty(defs: Dictionary, guard: Dictionary) -> void:
	# Lead-leg push kick (a teep): chamber the knee high, lean back and drive the sole out.
	var teep := _w(guard, {&"Hips": Vector3(0, -20, 0), &"Spine": Vector3(20, 6, 0), &"Head": Vector3(-14, 10, 0),
		&"HipL": Vector3(88, 0, -4), &"KneeL": Vector3(-6, 0, 0), &"HipR": Vector3(-6, 0, 6), &"KneeR": Vector3(-16, 0, 0),
		&"ShoulderR": Vector3(40, 0, -26), &"ElbowR": Vector3(110, 0, 0), &"_heelR": Vector3(10, 0, 0), &"_brow": Vector3(1, 0, 0)})
	defs[&"kick_b"] = {"length": 0.6, "load": 0.14, "contact": 0.22, "keys": [
		[0.0, guard],
		[0.14, _w(guard, {&"Spine": Vector3(10, 6, 0), &"HipL": Vector3(80, 0, -4), &"KneeL": Vector3(-112, 0, 0), &"_hips": Vector3(0, 0.01, 0.02)}), "io"],
		[0.22, teep, "snap"], [0.32, teep, "lin"],
		[0.44, _w(guard, {&"HipL": Vector3(50, 0, -4), &"KneeL": Vector3(-80, 0, 0)}), "out"], [0.6, guard],
	]}
	# Rear-leg low kick into the thigh: the hips turn over, the shin swings across, the
	# rear arm whips back to balance it.
	var low_load := _w(guard, {&"Hips": Vector3(0, 4, 0), &"Spine": Vector3(-6, 10, 0), &"HipR": Vector3(10, 0, 26),
		&"KneeR": Vector3(-60, 0, 0), &"HipL": Vector3(14, 0, -6), &"KneeL": Vector3(-24, 0, 0), &"_hips": Vector3(-0.02, -0.03, 0.01)})
	var low_hit := _w(guard, {&"Hips": Vector3(0, 42, 0), &"Spine": Vector3(8, -30, 0), &"Head": Vector3(-8, -16, 0),
		&"HipR": Vector3(44, 0, 38), &"KneeR": Vector3(-14, 0, 0), &"HipL": Vector3(6, 0, -6), &"KneeL": Vector3(-20, 0, 0),
		&"ShoulderR": Vector3(-24, 0, 34), &"ElbowR": Vector3(60, 0, 0), &"ShoulderL": Vector3(70, 0, 10), &"ElbowL": Vector3(120, 0, 0),
		&"_heelL": Vector3(24, 0, 0), &"_hips": Vector3(-0.02, -0.02, -0.03), &"_brow": Vector3(1, 0, 0)})
	defs[&"kick_low"] = {"length": 0.66, "load": 0.14, "contact": 0.22, "keys": [
		[0.0, guard], [0.14, low_load, "io"], [0.22, low_hit, "snap"],
		[0.32, _w(low_hit, {&"Hips": Vector3(0, 52, 0), &"HipR": Vector3(30, 0, 30)}), "out"],
		[0.48, _w(guard, {&"HipR": Vector3(-6, 0, 10), &"KneeR": Vector3(-50, 0, 0)})], [0.66, guard],
	]}
	# Kick in the balls: the lead foot snaps straight up from a low chamber, fast and short.
	var nuts_chamber := _w(guard, {&"HipL": Vector3(52, 0, -2), &"KneeL": Vector3(-100, 0, 0), &"Spine": Vector3(4, 6, 0),
		&"_hips": Vector3(0, 0.0, 0.02)})
	var nuts := _w(guard, {&"HipL": Vector3(62, 0, 0), &"KneeL": Vector3(-28, 0, 0), &"Spine": Vector3(10, 6, 0), &"Head": Vector3(-14, 8, 0),
		&"HipR": Vector3(-8, 0, 6), &"KneeR": Vector3(-14, 0, 0), &"_heelR": Vector3(16, 0, 0),
		&"_hips": Vector3(0, -0.005, -0.03), &"_brow": Vector3(1, 0, 0), &"_jaw": Vector3(0.2, 0, 0)})
	defs[&"groin_kick"] = {"length": 0.5, "load": 0.1, "contact": 0.16, "keys": [
		[0.0, guard], [0.1, nuts_chamber, "io"], [0.16, nuts, "snap"], [0.24, nuts, "lin"],
		[0.36, _w(guard, {&"HipL": Vector3(36, 0, -4), &"KneeL": Vector3(-70, 0, 0)}), "out"], [0.5, guard],
	]}
	# The clinch knee: both hands over the back of his head, drag it down and drive the rear
	# knee up into his face. Fingers open to grip, then clamp.
	var reach := _w(guard, {&"Spine": Vector3(-12, 0, 0), &"ShoulderL": Vector3(86, 0, 14), &"ElbowL": Vector3(26, 0, 0),
		&"ShoulderR": Vector3(86, 0, -14), &"ElbowR": Vector3(26, 0, 0), &"Hips": Vector3(0, -6, 0),
		&"_fistL": Vector3(-0.1, 0, 0), &"_fistR": Vector3(-0.1, 0, 0), &"_hips": Vector3(0, -0.02, -0.06)})
	var clamp := _w(reach, {&"ShoulderL": Vector3(66, 0, 22), &"ElbowL": Vector3(58, 0, 0), &"ShoulderR": Vector3(66, 0, -22),
		&"ElbowR": Vector3(58, 0, 0), &"Spine": Vector3(-6, 0, 0), &"_fistL": Vector3(0.7, 0, 0), &"_fistR": Vector3(0.7, 0, 0),
		&"HipR": Vector3(-20, 0, 6), &"KneeR": Vector3(-30, 0, 0), &"_hips": Vector3(0, -0.04, -0.04), &"_brow": Vector3(1, 0, 0)})
	var drive := _w(clamp, {&"ShoulderL": Vector3(44, 0, 22), &"ElbowL": Vector3(70, 0, 0), &"ShoulderR": Vector3(44, 0, -22),
		&"ElbowR": Vector3(70, 0, 0), &"Spine": Vector3(-16, 0, 0), &"Hips": Vector3(-10, -2, 0), &"Head": Vector3(-16, 0, 0),
		&"HipR": Vector3(122, 0, 2), &"KneeR": Vector3(-130, 0, 0), &"HipL": Vector3(-6, 0, -6), &"KneeL": Vector3(-8, 0, 0),
		&"_heelL": Vector3(26, 0, 0), &"_hips": Vector3(0, 0.03, -0.06), &"_jaw": Vector3(0.15, 0, 0)})
	defs[&"clinch_knee"] = {"length": 0.85, "load": 0.24, "contact": 0.34, "keys": [
		[0.0, guard], [0.12, reach, "snap"], [0.24, clamp, "io"], [0.34, drive, "snap"], [0.44, drive, "lin"],
		[0.6, _w(clamp, {&"HipR": Vector3(20, 0, 6), &"KneeR": Vector3(-60, 0, 0)}), "out"],
		[0.85, guard],
	]}
	# Shoulder charge: drop the level, tuck the head, lead shoulder down and drive off the
	# back foot like a rugby tackle.
	var tuck := _w(guard, {&"Hips": Vector3(-8, -42, 0), &"Spine": Vector3(-30, 24, 10), &"Chest": Vector3(-6, 6, 0), &"Head": Vector3(10, 28, 0),
		&"ShoulderL": Vector3(36, 0, 24), &"ElbowL": Vector3(128, 0, 0), &"ShoulderR": Vector3(40, 0, -8), &"ElbowR": Vector3(120, 0, 0),
		&"HipL": Vector3(38, 0, -8), &"KneeL": Vector3(-50, 0, 0), &"HipR": Vector3(-4, 0, 8), &"KneeR": Vector3(-46, 0, 0),
		&"_hips": Vector3(0, -0.13, 0.03), &"_brow": Vector3(1, 0, 0)})
	var hit := _w(tuck, {&"Hips": Vector3(-16, -48, 0), &"Spine": Vector3(-34, 26, 14), &"Head": Vector3(14, 30, 0),
		&"ShoulderL": Vector3(20, 0, 30), &"ElbowL": Vector3(120, 0, 0),
		&"HipL": Vector3(52, 0, -8), &"KneeL": Vector3(-46, 0, 0), &"HipR": Vector3(-38, 0, 8), &"KneeR": Vector3(-12, 0, 0),
		&"_heelR": Vector3(30, 0, 0), &"_hips": Vector3(0, -0.1, -0.22), &"_jaw": Vector3(0.1, 0, 0)})
	defs[&"shoulder_charge"] = {"length": 0.85, "load": 0.2, "contact": 0.36, "keys": [
		[0.0, guard], [0.2, tuck, "io"], [0.36, hit, "snap"],
		[0.52, _w(hit, {&"_hips": Vector3(0, -0.09, -0.26), &"Spine": Vector3(-26, 22, 12)}), "lin"],
		[0.7, _w(guard, {&"Spine": Vector3(-14, 10, 0), &"_hips": Vector3(0, -0.06, -0.08)}), "out"],
		[0.85, guard],
	]}
	# A punter's swinging body punch: a wide, round arm into the gut.
	var gut := _w(guard, {&"Hips": Vector3(0, 26, 0), &"Spine": Vector3(-20, 20, 0), &"ShoulderR": Vector3(54, -40, -28),
		&"ElbowR": Vector3(54, 0, 0), &"KneeL": Vector3(-32, 0, 0), &"_hips": Vector3(0, -0.06, -0.08), &"_brow": Vector3(1, 0, 0)})
	defs[&"body_swing"] = {"length": 0.7, "load": 0.24, "contact": 0.32, "keys": [
		[0.0, guard],
		[0.24, _w(guard, {&"Hips": Vector3(0, -30, 0), &"Spine": Vector3(-4, -14, 0), &"ShoulderR": Vector3(10, 30, -50),
			&"ElbowR": Vector3(60, 0, 0), &"_hips": Vector3(0, -0.03, 0.05)}), "io"],
		[0.32, gut, "snap"], [0.44, _w(gut, {&"Hips": Vector3(0, 34, 0)}), "out"], [0.7, guard],
	]}


# --- Defence --------------------------------------------------------------------

## The footwork loops a held guard (LB or RB) steps with.
const GUARD_STEPS: Array[StringName] = [&"walk", &"walk_back", &"strafe_l", &"strafe_r"]
## Joints a held guard owns while the legs walk underneath it.
const GUARD_UPPER: Array[StringName] = [&"Spine", &"Chest", &"Head", &"ShoulderL", &"ElbowL", &"HandL",
	&"ShoulderR", &"ElbowR", &"HandR", &"_fistL", &"_fistR", &"_brow"]


## A footwork loop with the arms, chest and head held in `cover` on every key.
static func _guarded_steps(walk: Dictionary, cover: Dictionary) -> Dictionary:
	var out := walk.duplicate(true)
	var keys: Array = []
	for k in walk["keys"]:
		var key: Array = (k as Array).duplicate()
		var pose: Dictionary = (key[1] as Dictionary).duplicate()
		for j in GUARD_UPPER:
			if cover.has(j):
				pose[j] = cover[j]
		key[1] = pose
		keys.append(key)
	out["keys"] = keys
	return out


static func _defence(defs: Dictionary, guard: Dictionary) -> void:
	# Head guard (LB): both gloves up in front of the face, elbows in, chin buried, peeking out between them.
	var high := _w(guard, {&"Hips": Vector3(0, -10, 0), &"Spine": Vector3(-14, 6, 0), &"Head": Vector3(-22, 4, 0),
		&"ShoulderL": Vector3(55, -30, 30), &"ElbowL": Vector3(130, 0, 0), &"HandL": Vector3(-30, 0, 0),
		&"ShoulderR": Vector3(55, 30, -30), &"ElbowR": Vector3(130, 0, 0), &"HandR": Vector3(-30, 0, 0),
		&"KneeL": Vector3(-26, 0, 0), &"KneeR": Vector3(-24, 0, 0), &"_hips": Vector3(0, -0.05, 0), &"_brow": Vector3(0.9, 0, 0)})
	defs[&"guard_head"] = {"length": 1.2, "loop": true, "keys": [
		[0.0, high],
		[0.4, _w(high, {&"Spine": Vector3(-15, 10, 3), &"_hips": Vector3(0.01, -0.06, 0)})],
		[0.8, _w(high, {&"Spine": Vector3(-15, 2, -3), &"_hips": Vector3(-0.01, -0.06, 0)})],
		[1.2, high],
	]}
	# Body guard (RB): elbows tucked in over the ribs, fists up by the chin, hunched
	# and sat down on the legs.
	var low := _w(guard, {&"Hips": Vector3(0, -12, 0), &"Spine": Vector3(-24, 4, 0), &"Chest": Vector3(-6, 0, 0), &"Head": Vector3(-6, 6, 0),
		&"ShoulderL": Vector3(30, -35, 30), &"ElbowL": Vector3(140, 0, 0), &"HandL": Vector3(0, -70, 0),
		&"ShoulderR": Vector3(30, 35, -30), &"ElbowR": Vector3(140, 0, 0), &"HandR": Vector3(0, 70, 0),
		&"HipL": Vector3(24, 0, -8), &"KneeL": Vector3(-36, 0, 0), &"HipR": Vector3(-4, 0, 8), &"KneeR": Vector3(-34, 0, 0),
		&"_hips": Vector3(0, -0.09, 0.01), &"_brow": Vector3(0.9, 0, 0)})
	defs[&"guard_body"] = {"length": 1.2, "loop": true, "keys": [
		[0.0, low],
		[0.6, _w(low, {&"Spine": Vector3(-26, 8, 0), &"_hips": Vector3(0, -0.1, 0.01)})],
		[1.2, low],
	]}
	# Moving with a guard up: the feet keep stepping (forward, back, to the side) under the cover.
	for base in GUARD_STEPS:
		if defs.has(base):
			defs[StringName("guard_head_" + String(base))] = _guarded_steps(defs[base], high)
			defs[StringName("guard_body_" + String(base))] = _guarded_steps(defs[base], low)
	# Taking one on the guard: knocked back a touch, then reset.
	var cover := _key(defs, &"block", 0)
	defs[&"block_hit_head"] = {"length": 0.36, "keys": [
		[0.0, high], [0.05, _w(high, {&"Head": Vector3(-6, -4, 0), &"Spine": Vector3(-4, 2, 0), &"_hips": Vector3(0, -0.05, 0.06),
			&"ElbowL": Vector3(124, 0, 0), &"ElbowR": Vector3(124, 0, 0)}), "snap"],
		[0.18, _w(high, {&"_hips": Vector3(0, -0.06, 0.04)}), "out"], [0.36, high],
	]}
	defs[&"block_hit_body"] = {"length": 0.4, "keys": [
		[0.0, low], [0.05, _w(low, {&"Spine": Vector3(-34, 4, 0), &"_hips": Vector3(0, -0.11, 0.06), &"_jaw": Vector3(0.2, 0, 0)}), "snap"],
		[0.2, _w(low, {&"_hips": Vector3(0, -0.1, 0.04)}), "out"], [0.4, low],
	]}
	defs[&"block_hit"] = {"length": 0.36, "keys": [
		[0.0, cover], [0.05, _w(cover, {&"Spine": Vector3(-6, 4, 0), &"Head": Vector3(-6, 0, 0), &"_hips": Vector3(0, -0.05, 0.06)}), "snap"],
		[0.18, _w(cover, {&"_hips": Vector3(0, -0.06, 0.04)}), "out"], [0.36, cover],
	]}
	# Parries: the lead hand slaps the punch across and down, the body turning with it.
	var slap := _w(guard, {&"Hips": Vector3(0, -26, 0), &"Spine": Vector3(-10, 0, 0), &"Head": Vector3(-10, 14, 0),
		&"ShoulderL": Vector3(64, -34, 0), &"ElbowL": Vector3(70, 0, 0), &"HandL": Vector3(0, 0, -24), &"_fistL": Vector3(0.1, 0, 0),
		&"_hips": Vector3(0.01, -0.03, 0)})
	defs[&"parry_l"] = {"length": 0.34, "keys": [
		[0.0, guard], [0.05, _w(guard, {&"ShoulderL": Vector3(70, 6, 8), &"ElbowL": Vector3(96, 0, 0), &"_fistL": Vector3(0.3, 0, 0)}), "io"],
		[0.1, slap, "snap"], [0.2, _w(slap, {&"ShoulderL": Vector3(54, -30, 0)}), "out"], [0.34, guard],
	]}
	# Rear hand catches it and pushes it down past the hip.
	var catch_r := _w(guard, {&"Hips": Vector3(0, -6, 0), &"Spine": Vector3(-12, 16, 0), &"ShoulderR": Vector3(54, 22, -10),
		&"ElbowR": Vector3(66, 0, 0), &"HandR": Vector3(-20, 0, 0), &"_fistR": Vector3(0.1, 0, 0), &"_hips": Vector3(-0.01, -0.035, 0.02)})
	defs[&"parry_r"] = {"length": 0.36, "keys": [
		[0.0, guard], [0.1, catch_r, "snap"],
		[0.2, _w(catch_r, {&"ShoulderR": Vector3(34, 18, -12), &"ElbowR": Vector3(50, 0, 0)}), "out"], [0.36, guard],
	]}
	# Slips: the head comes off the line, bending at the waist and knees, eyes still on him.
	var slip_l := _w(guard, {&"Spine": Vector3(-14, 12, 20), &"Head": Vector3(-8, 6, -10), &"KneeL": Vector3(-34, 0, 0),
		&"KneeR": Vector3(-26, 0, 0), &"_hips": Vector3(-0.05, -0.06, 0)})
	defs[&"slip_l"] = {"length": 0.42, "keys": [[0.0, guard], [0.1, slip_l, "snap"], [0.24, slip_l, "lin"], [0.42, guard, "out"]]}
	var slip_r := _w(guard, {&"Spine": Vector3(-14, 4, -20), &"Head": Vector3(-8, 8, 10), &"KneeL": Vector3(-26, 0, 0),
		&"KneeR": Vector3(-34, 0, 0), &"_hips": Vector3(0.05, -0.06, 0)})
	defs[&"slip_r"] = {"length": 0.42, "keys": [[0.0, guard], [0.1, slip_r, "snap"], [0.24, slip_r, "lin"], [0.42, guard, "out"]]}
	# Dodges in a direction (the fighter itself slides; this is the body over the feet).
	var side_l := _w(guard, {&"Spine": Vector3(-12, 10, 16), &"Head": Vector3(-6, 6, -10), &"HipL": Vector3(14, 0, -26),
		&"KneeL": Vector3(-36, 0, 0), &"HipR": Vector3(-10, 0, 4), &"KneeR": Vector3(-20, 0, 0), &"_heelR": Vector3(14, 0, 0),
		&"_hips": Vector3(-0.06, -0.07, 0)})
	defs[&"dodge_l"] = {"length": 0.45, "keys": [
		[0.0, guard], [0.1, side_l, "snap"], [0.26, _w(side_l, {&"HipR": Vector3(-10, 0, -8), &"KneeR": Vector3(-36, 0, 0)}), "lin"],
		[0.45, guard, "out"],
	]}
	var side_r := _w(guard, {&"Spine": Vector3(-12, 6, -16), &"Head": Vector3(-6, 8, 10), &"HipR": Vector3(-10, 0, 26),
		&"KneeR": Vector3(-36, 0, 0), &"HipL": Vector3(16, 0, 4), &"KneeL": Vector3(-20, 0, 0), &"_heelL": Vector3(14, 0, 0),
		&"_hips": Vector3(0.06, -0.07, 0)})
	defs[&"dodge_r"] = {"length": 0.45, "keys": [
		[0.0, guard], [0.1, side_r, "snap"], [0.26, _w(side_r, {&"HipL": Vector3(16, 0, 10), &"KneeL": Vector3(-36, 0, 0)}), "lin"],
		[0.45, guard, "out"],
	]}
	var pull := _w(guard, {&"Spine": Vector3(16, 8, 0), &"Head": Vector3(10, 6, 0), &"HipR": Vector3(-30, 0, 6), &"KneeR": Vector3(-34, 0, 0),
		&"HipL": Vector3(8, 0, -6), &"KneeL": Vector3(-10, 0, 0), &"_heelL": Vector3(10, 0, 0), &"_hips": Vector3(0, -0.04, 0.08)})
	defs[&"dodge_back"] = {"length": 0.45, "keys": [[0.0, guard], [0.1, pull, "snap"], [0.26, pull, "lin"], [0.45, guard, "out"]]}
	var dip_in := _w(guard, {&"Spine": Vector3(-34, 10, 0), &"Head": Vector3(14, 6, 0), &"HipL": Vector3(40, 0, -8), &"KneeL": Vector3(-56, 0, 0),
		&"HipR": Vector3(-8, 0, 8), &"KneeR": Vector3(-40, 0, 0), &"_hips": Vector3(0, -0.15, -0.06)})
	defs[&"dodge_fwd"] = {"length": 0.45, "keys": [[0.0, guard], [0.12, dip_in, "snap"], [0.26, dip_in, "lin"], [0.45, guard, "out"]]}


# --- Reactions ------------------------------------------------------------------

static func _reactions(defs: Dictionary, guard: Dictionary, pain: Dictionary, kneel: float) -> void:
	# Winded by a body shot: folds over the fist, hands to the belly, a stumble back.
	var fold := _w(_w(guard, pain), {&"Hips": Vector3(-6, 0, 0), &"Spine": Vector3(-34, 0, 0), &"Chest": Vector3(-12, 0, 0), &"Head": Vector3(18, 0, 0),
		&"ShoulderL": Vector3(30, 0, 22), &"ElbowL": Vector3(104, 0, 0), &"ShoulderR": Vector3(30, 0, -22), &"ElbowR": Vector3(104, 0, 0),
		&"HipL": Vector3(22, 0, -4), &"KneeL": Vector3(-34, 0, 0), &"HipR": Vector3(10, 0, 4), &"KneeR": Vector3(-30, 0, 0),
		&"_hips": Vector3(0, -0.08, 0.07), &"_jaw": Vector3(0.75, 0, 0), &"_brow": Vector3(-1, 0, 0)})
	defs[&"hit_body"] = {"length": 0.8, "keys": [
		[0.0, guard], [0.06, fold, "snap"],
		[0.3, _w(fold, {&"Spine": Vector3(-38, 0, 0), &"HipR": Vector3(-14, 0, 6), &"KneeR": Vector3(-34, 0, 0), &"_hips": Vector3(0, -0.1, 0.12)}), "out"],
		[0.55, _w(guard, {&"Spine": Vector3(-20, 6, 0), &"_hips": Vector3(0, -0.06, 0.08), &"_jaw": Vector3(0.4, 0, 0), &"_brow": Vector3(-0.6, 0, 0)})],
		[0.8, guard],
	]}
	# Liver shot on the left (a right body hook): crumples to that side, elbow clamped down.
	var crumple := _w(_w(guard, pain), {&"Spine": Vector3(-24, -8, 22), &"Chest": Vector3(-6, 0, 8), &"Head": Vector3(10, -10, 0),
		&"ShoulderL": Vector3(14, 0, 16), &"ElbowL": Vector3(110, 0, 0), &"ShoulderR": Vector3(40, 0, 20), &"ElbowR": Vector3(80, 0, 0),
		&"KneeL": Vector3(-42, 0, 0), &"KneeR": Vector3(-24, 0, 0), &"_hips": Vector3(0.03, -0.1, 0.04), &"_jaw": Vector3(0.6, 0, 0)})
	defs[&"hit_body_l"] = {"length": 0.75, "keys": [
		[0.0, guard], [0.06, crumple, "snap"],
		[0.32, _w(crumple, {&"Spine": Vector3(-26, -10, 26), &"_hips": Vector3(0.05, -0.12, 0.06)}), "out"],
		[0.55, _w(guard, {&"Spine": Vector3(-16, 0, 10), &"_hips": Vector3(0.02, -0.06, 0.03)})], [0.75, guard],
	]}
	defs[&"hit_body_r"] = CharacterRig._mirror_strike(defs[&"hit_body_l"], guard)
	# An uppercut on the chin: the head is thrown straight up, up on the toes, arms flung out.
	var lifted := _w(_w(guard, pain), {&"Head": Vector3(58, 0, 0), &"Spine": Vector3(22, 0, 0), &"Chest": Vector3(10, 0, 0),
		&"ShoulderL": Vector3(8, 0, -52), &"ElbowL": Vector3(40, 0, 0), &"ShoulderR": Vector3(8, 0, 52), &"ElbowR": Vector3(40, 0, 0),
		&"KneeL": Vector3(-6, 0, 0), &"KneeR": Vector3(-6, 0, 0), &"_heelL": Vector3(20, 0, 0), &"_heelR": Vector3(20, 0, 0),
		&"_hips": Vector3(0, 0.03, 0.06), &"_fistL": Vector3(0.1, 0, 0), &"_fistR": Vector3(0.1, 0, 0)})
	defs[&"hit_uppercut"] = {"length": 0.75, "keys": [
		[0.0, guard], [0.06, lifted, "snap"],
		[0.24, _w(lifted, {&"Head": Vector3(36, 0, 0), &"HipR": Vector3(-26, 0, 6), &"KneeR": Vector3(-30, 0, 0), &"_heelL": Vector3(0, 0, 0),
			&"_heelR": Vector3(0, 0, 0), &"_hips": Vector3(0, -0.05, 0.14)}), "out"],
		[0.5, _w(guard, {&"Head": Vector3(-4, 0, 0), &"_hips": Vector3(0, -0.05, 0.08), &"_brow": Vector3(-0.5, 0, 0)})],
		[0.75, guard],
	]}
	# A straight one on the nose: the head snaps right back and the jaw goes, then a shake.
	var snapped := _w(_w(guard, pain), {&"Head": Vector3(46, 8, 0), &"Spine": Vector3(10, 4, 0), &"Chest": Vector3(6, 0, 0),
		&"ShoulderL": Vector3(40, 0, -16), &"ElbowL": Vector3(90, 0, 0), &"ShoulderR": Vector3(36, 0, 20), &"ElbowR": Vector3(96, 0, 0),
		&"_hips": Vector3(0, -0.015, 0.06)})
	defs[&"hit_front_b"] = {"length": 0.6, "keys": [
		[0.0, guard], [0.04, snapped, "snap"],
		[0.16, _w(snapped, {&"Head": Vector3(20, -10, 0), &"HipL": Vector3(2, 0, -6), &"KneeL": Vector3(-28, 0, 0), &"_hips": Vector3(0, -0.05, 0.1)}), "out"],
		[0.28, _w(guard, {&"Head": Vector3(-6, 16, 0), &"_brow": Vector3(-0.6, 0, 0), &"_hips": Vector3(0, -0.04, 0.06)})],
		[0.4, _w(guard, {&"Head": Vector3(-8, -6, 0), &"_brow": Vector3(-0.3, 0, 0)})],
		[0.6, guard],
	]}
	# Kicked in the balls: knees snap together, both hands to the crotch, folds, drops to the
	# knees and goes down on all fours, one hand still holding himself.
	var clutch := _w(pain, {&"Hips": Vector3(-8, 0, 0), &"Spine": Vector3(-30, 0, 0), &"Chest": Vector3(-10, 0, 0), &"Head": Vector3(10, 0, 0),
		&"ShoulderL": Vector3(14, 0, 22), &"ElbowL": Vector3(30, 0, 0), &"ShoulderR": Vector3(14, 0, -22), &"ElbowR": Vector3(30, 0, 0),
		&"HipL": Vector3(18, 0, 10), &"KneeL": Vector3(-40, 0, 0), &"HipR": Vector3(18, 0, -10), &"KneeR": Vector3(-40, 0, 0),
		&"_hips": Vector3(0, -0.1, 0.05), &"_jaw": Vector3(0.9, 0, 0), &"_brow": Vector3(-1, 0, 0), &"_heelL": Vector3(10, 0, 0),
		&"_heelR": Vector3(10, 0, 0), &"_fistL": Vector3(0.5, 0, 0), &"_fistR": Vector3(0.5, 0, 0)})
	var knees := _w(clutch, {&"Hips": Vector3(-14, 0, 0), &"Spine": Vector3(-30, 0, 0), &"HipL": Vector3(14, 0, 6), &"KneeL": Vector3(-96, 0, 0),
		&"HipR": Vector3(14, 0, -6), &"KneeR": Vector3(-96, 0, 0), &"FootL": Vector3(-40, 0, 0), &"FootR": Vector3(-40, 0, 0),
		&"_hips": Vector3(0, kneel, 0.04)})
	# On all fours: torso level, thighs upright, the left hand flat on the floor and the right
	# still clutching. Head hanging.
	var fours := {&"Hips": Vector3(-72, 0, 0), &"Spine": Vector3(-10, 0, 0), &"Chest": Vector3(0, 0, 0), &"Head": Vector3(30, 0, 0),
		&"ShoulderL": Vector3(80, 0, -6), &"ElbowL": Vector3(8, 0, 0), &"HandL": Vector3(-60, 0, 0), &"_fistL": Vector3(0, 0, 0),
		&"ShoulderR": Vector3(8, 0, -10), &"ElbowR": Vector3(26, 0, 0), &"_fistR": Vector3(0.5, 0, 0),
		&"HipL": Vector3(76, 0, -4), &"KneeL": Vector3(-92, 0, 0), &"HipR": Vector3(80, 0, 4), &"KneeR": Vector3(-96, 0, 0),
		&"FootL": Vector3(-30, 0, 0), &"FootR": Vector3(-30, 0, 0),
		&"_hips": Vector3(0, kneel + 0.02, 0.06), &"_jaw": Vector3(0.8, 0, 0), &"_brow": Vector3(-1, 0, 0)}
	defs[&"groin_down"] = {"length": 1.3, "keys": [
		[0.0, guard], [0.08, clutch, "snap"],
		[0.35, _w(clutch, {&"Spine": Vector3(-40, 0, 0), &"KneeL": Vector3(-60, 0, 0), &"KneeR": Vector3(-60, 0, 0), &"_hips": Vector3(0, -0.2, 0.05)}), "in"],
		[0.6, knees, "in"],
		[0.75, _w(knees, {&"_hips": Vector3(0, kneel + 0.015, 0.04)}), "out"],
		[1.05, _w(fours, {&"Head": Vector3(10, 0, 0)}), "io"],
		[1.3, fours],
	]}
	defs[&"groin_hold"] = {"length": 2.0, "loop": true, "keys": [
		[0.0, fours],
		[0.6, _w(fours, {&"Hips": Vector3(-68, 0, 0), &"Head": Vector3(14, 0, 0), &"_hips": Vector3(0, kneel + 0.025, 0.09), &"_jaw": Vector3(0.5, 0, 0)})],
		[1.0, _w(fours, {&"Head": Vector3(44, 6, 0), &"_jaw": Vector3(1, 0, 0)})],
		[1.4, _w(fours, {&"Hips": Vector3(-74, 0, 0), &"_hips": Vector3(0, kneel + 0.02, 0.04)})],
		[2.0, fours],
	]}
	# Clinched: his head is dragged down, bent double, hands clawing at the forearms.
	var bent := _w(pain, {&"Hips": Vector3(-14, 0, 0), &"Spine": Vector3(-40, 0, 0), &"Chest": Vector3(-8, 0, 0), &"Head": Vector3(22, 0, 0),
		&"ShoulderL": Vector3(96, 0, 18), &"ElbowL": Vector3(80, 0, 0), &"ShoulderR": Vector3(96, 0, -18), &"ElbowR": Vector3(80, 0, 0),
		&"HipL": Vector3(26, 0, -6), &"KneeL": Vector3(-30, 0, 0), &"HipR": Vector3(16, 0, 6), &"KneeR": Vector3(-26, 0, 0),
		&"_hips": Vector3(0, -0.07, 0.08), &"_fistL": Vector3(0.8, 0, 0), &"_fistR": Vector3(0.8, 0, 0)})
	defs[&"clinched"] = {"length": 0.8, "loop": true, "keys": [
		[0.0, bent], [0.4, _w(bent, {&"Spine": Vector3(-44, 6, 4), &"ShoulderL": Vector3(104, 0, 14), &"_hips": Vector3(0.01, -0.08, 0.06)})], [0.8, bent],
	]}
