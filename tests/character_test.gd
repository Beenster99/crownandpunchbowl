extends SceneTree
## Headless test for the shared rig and every character look.
## Run: godot --headless --path . --script res://tests/character_test.gd

const FIGHTER_STATES := ["IDLE", "ATTACK", "WINDUP", "STAGGER", "DOWN", "CRAWL", "KO", "HELD", "GRABBING", "DODGE"]

var _failures := 0


func _initialize() -> void:
	await process_frame
	_check_farmers_match_game_data()
	_check_every_look_builds()
	_check_crowd_variation()
	_check_state_and_move_mapping()
	_check_lying_down()
	_check_calm_and_guard()
	_check_rich_rig()
	_check_fight_set()
	await _check_head_snap()
	await _check_ragdoll()
	if _failures == 0:
		print("CHARACTERS OK: %d looks, %d keyed animations, %d motion-captured takes" % [CharacterLooks.all_ids().size(),
			CharacterRig.ANIMATIONS.size(), RigMixamo.table().size()])
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	push_error(msg)
	_failures += 1


func _check_farmers_match_game_data() -> void:
	var game_data := root.get_node("GameData")
	var women := 0
	for f in game_data.FARMERS:
		if not CharacterLooks.FARMERS.has(f["id"]):
			_fail("farmer '%s' has no look" % f["id"])
		elif CharacterLooks.farmer(f["id"]).feminine:
			women += 1
	if CharacterLooks.FARMERS.size() != 6 or women != 1:
		_fail("expected 6 farmers with 1 woman, got %d with %d" % [CharacterLooks.FARMERS.size(), women])


func _check_every_look_builds() -> void:
	var heights := {}
	for id in CharacterLooks.all_ids():
		var rig := CharacterRig.new()
		rig.look_id = id
		root.add_child(rig)
		for a in CharacterRig.ANIMATIONS:
			if not rig.anim.has_animation(a):
				_fail("%s: missing animation %s" % [id, a])
		# The keyed set, plus the motion-captured takes (and any name they stand in for).
		var expected := {}
		for a in CharacterRig.ANIMATIONS:
			expected[a] = true
		var mx := RigMixamo.table()
		for a in mx:
			expected[a] = true
			if mx[a].has("replaces"):
				expected[StringName(mx[a]["replaces"])] = true
		if mx.is_empty():
			_fail("no motion-captured clips (assets/animations/mixamo/clips.json)")
		if rig.anim.get_animation_list().size() != expected.size():
			_fail("%s: %d animations, expected %d" % [id, rig.anim.get_animation_list().size(), expected.size()])
		for s in CharacterRig.SOCKETS:
			if rig.get_socket(s) == null:
				_fail("%s: missing socket %s" % [id, s])
		for a in CharacterRig.ANIMATIONS:
			rig.play(a, 0.0)
			rig.anim.advance(5.0)
		rig.play(&"idle", 0.0)
		rig.anim.advance(0.01)
		var h := rig.head_height()
		heights[id] = h
		if h < 1.3 or h > 2.2:
			_fail("%s: head at %.2f m, outside 1.3 to 2.2" % [id, h])
		rig.set_blood(1.0)
		rig.break_nose()
		rig.queue_free()
	# Silhouettes should differ: Tom the giant stands over Barrow the stooped old boy.
	if heights["tom"] - heights["barrow"] < 0.2:
		_fail("Tom should stand well over Barrow (%.2f vs %.2f)" % [heights["tom"], heights["barrow"]])


func _check_crowd_variation() -> void:
	var a := CharacterLooks.punter("local", 7)
	var b := CharacterLooks.punter("local", 7)
	var c := CharacterLooks.punter("local", 8)
	if a.skin != b.skin or a.top_color != b.top_color or a.height != b.height:
		_fail("same punter seed should give the same look")
	var differs := false
	for seed in range(1, 6):
		var d := CharacterLooks.punter("local", seed)
		if d.skin != c.skin or d.top_color != c.top_color or d.hair != c.hair:
			differs = true
	if not differs:
		_fail("different punter seeds should vary the look")


func _check_state_and_move_mapping() -> void:
	for s in FIGHTER_STATES:
		if not CharacterRig.STATE_ANIMS.has(s.to_lower()):
			_fail("no animation for Fighter state %s" % s)
	for move in ["punch", "kick", "headbutt", "swing", "throw", "grab", "drink", "eat", "jab", "cross", "hook",
			"uppercut", "stomp", "counter", "counter_whiff", "knee", "haymaker", "shove", "baton"]:
		if move != "punch" and not CharacterRig.MOVE_ANIMS.has(move):
			_fail("no animation for move %s" % move)
	var rig := CharacterRig.new()
	rig.look_id = "gaz"
	root.add_child(rig)
	rig.play_move("punch")
	var first := rig.current
	rig.play_move("punch")
	if first == rig.current:
		_fail("punch should alternate hands")
	rig.play_state("DOWN")
	rig.anim.advance(1.0)
	if rig.current != &"down":
		_fail("knockdown should chain into down, got %s" % rig.current)
	rig.play_move("kick")
	rig.anim.advance(1.0)
	if rig.current != &"idle":
		_fail("kick should return to idle, got %s" % rig.current)
	rig.set_move_speed(4.0)
	if rig.current != &"walk":
		_fail("moving should walk, got %s" % rig.current)
	rig.queue_free()


## Nobody stands about with their fists up: calm idles until the guard goes up.
func _check_calm_and_guard() -> void:
	var rig := CharacterRig.new()
	rig.look_id = "local"
	rig.look_seed = 4
	root.add_child(rig)
	if not CharacterRig.calm_idles().has(rig.current):
		_fail("a fresh character should stand relaxed, got %s" % rig.current)
	rig.set_talking(true)
	if rig.current != &"idle_chat":
		_fail("chatting should gesture, got %s" % rig.current)
	rig.set_guard(true)
	if not CharacterRig.fight_idles().has(rig.current):
		_fail("guard up should raise the fists, got %s" % rig.current)
	rig.set_move_speed(3.0)
	if rig.current != &"walk":
		_fail("guarded walk expected, got %s" % rig.current)
	rig.set_guard(false)
	if rig.current != &"walk_relaxed":
		_fail("calm walk expected, got %s" % rig.current)
	rig.set_move_speed(0.0)
	rig.set_talking(false)
	if not CharacterRig.calm_idles().has(rig.current):
		_fail("should settle back to a calm idle, got %s" % rig.current)
	rig.queue_free()
	var barman := CharacterRig.new()
	barman.look_id = "barman"
	barman.staff = true
	root.add_child(barman)
	if barman.current != &"idle_polish":
		_fail("bar staff should polish glasses, got %s" % barman.current)
	barman.queue_free()


## The fight rig: every model has the extra bones, strikes publish their timing, a guard
## clenches the fists and a punch reaches forward.
func _check_rich_rig() -> void:
	var rig := CharacterRig.new()
	rig.look_id = "mags"
	root.add_child(rig)
	for b in [&"Spine2", &"Neck", &"Jaw", &"BrowL", &"BrowR", &"ClavicleL", &"ClavicleR", &"Thumb1L", &"Index2R", &"Fingers2L"]:
		if rig.skeleton.find_bone(b) < 0:
			_fail("rig has no %s bone" % b)
	for a in [&"punch_l", &"punch_r", &"hook_l", &"hook_r", &"uppercut_r"]:
		var l := rig.load_time(a)
		var c := rig.contact_time(a)
		if not (l > 0.0 and c > l and c < rig.anim.get_animation(a).length):
			_fail("%s: load %.2f and contact %.2f out of order" % [a, l, c])
	if CharacterRig.MOVE_ANIMS["hook"] != &"hook_r":
		_fail("hook should be the right hook")
	var hand := rig.skeleton.find_bone("HandR")
	var tip := rig.skeleton.find_bone("Index2R")
	var dist := {}
	for a in [&"idle_relaxed", &"idle"]:
		rig.play(a, 0.0)
		rig.anim.seek(0.0, true)
		dist[a] = rig.bone_position(&"Index2R").distance_to(rig.bone_position(&"HandR"))
	if dist[&"idle"] >= dist[&"idle_relaxed"]:
		_fail("the guard should clench the fists")
	rig.play(&"punch_r", 0.0, false)  # the keyed take
	rig.anim.seek(rig.contact_time(&"punch_r"), true)
	var reach := rig.to_local(rig.bone_position(&"HandR")).z
	if reach > -0.45:
		_fail("a cross should reach forward at contact, hand at z %.2f" % reach)
	rig.queue_free()


## The extended fight set: every strike take has its timing in order, body shots and the
## new moves map to their own animations, guards and dodges pick the right take, a kick in
## the balls ends on all fours and a punch snaps the head back on top of the animation.
func _check_fight_set() -> void:
	var rig := CharacterRig.new()
	rig.look_id = "kev"
	root.add_child(rig)
	var strikes: Array = []
	# Every take of every strike, keyed and motion-captured, lands after it loads.
	for base in [&"punch_l", &"punch_r", &"hook_l", &"hook_r", &"uppercut_r", &"kick", &"headbutt", &"stomp", &"clinch_knee"]:
		for take in CharacterRig.takes_of(base):
			if rig.anim.has_animation(take) and not strikes.has(take):
				strikes.append(take)
	strikes.append_array([&"jab_body", &"cross_body", &"uppercut_body", &"groin_kick", &"clinch_knee", &"shoulder_charge", &"body_swing"])
	for a in strikes:
		var l := rig.load_time(a)
		var c := rig.contact_time(a)
		if not (l > 0.0 and c > l and c < rig.anim.get_animation(a).length):
			_fail("%s: load %.2f and contact %.2f out of order" % [a, l, c])
	var moves := {"clinch_knee": &"clinch_knee", "groin_kick": &"groin_kick", "shoulder_charge": &"shoulder_charge",
		"body_swing": &"body_swing"}
	for m in moves:
		rig.play_move(m)
		if rig.current != moves[m]:
			_fail("move %s played %s" % [m, rig.current])
	rig.play_move("jab", &"body")
	if rig.current != &"jab_body":
		_fail("a body jab should play jab_body, got %s" % rig.current)
	for i in 12:
		rig.play_move("hook")
		if not CharacterRig.takes_of(&"hook_r").has(rig.current_take):
			_fail("hook should be a right hook take, got %s" % rig.current)
	# Guards.
	rig.set_guard(true)
	rig.play(&"idle", 0.0)
	rig.set_guard_zone(&"head")
	if rig.current != &"guard_head":
		_fail("LB should raise the head guard, got %s" % rig.current)
	rig.set_guard_zone(&"body")
	if rig.current != &"guard_body":
		_fail("RB should drop to the body guard, got %s" % rig.current)
	rig.set_guard_zone(&"")
	# Letting go of the guard goes back to standing, so walking off animates the legs
	# (it used to stick in "block" and the fighter glided about).
	if not CharacterRig.STANDING.has(rig.current) and not CharacterRig.fight_idles().has(rig.current):
		_fail("dropping the guard should go back to a standing pose, got %s" % rig.current)
	rig.set_move_vector(Vector2(0.0, 3.0))
	rig.set_move_speed(3.0)
	if rig.current != &"walk":
		_fail("walking off after a guard should walk, got %s" % rig.current)
	rig.set_move_speed(0.0)
	# Dodges by direction (the rig faces -Z: +X is its right).
	for pair in [[Vector3.RIGHT, &"dodge_r"], [Vector3.LEFT, &"dodge_l"], [Vector3.BACK, &"dodge_back"], [Vector3.FORWARD, &"dodge_fwd"]]:
		rig.play_dodge(pair[0])
		if rig.current != pair[1]:
			_fail("dodge %s played %s, wanted %s" % [pair[0], rig.current, pair[1]])
	# Footwork.
	rig.play(&"idle", 0.0)
	rig.set_move_vector(Vector2(-2.0, 0.0))
	rig.set_move_speed(2.0)
	if rig.current != &"strafe_l":
		_fail("moving left in the guard should strafe, got %s" % rig.current)
	rig.set_move_vector(Vector2(0.0, -2.0))
	rig.set_move_speed(2.0)
	if rig.current != &"walk_back":
		_fail("backing off should backpedal, got %s" % rig.current)
	rig.set_move_vector(Vector2.ZERO)
	rig.set_move_speed(0.0)
	# Groin: down on all fours, chest low and the knees on the floor.
	rig.play_hit(true, false, Vector3.BACK, &"groin")
	if rig.current != &"groin_down":
		_fail("a kick in the balls should play groin_down, got %s" % rig.current)
	rig.play(&"groin_hold", 0.0)
	rig.anim.seek(0.0, true)
	var chest := rig.bone_position(&"Chest").y
	var knee := rig.bone_position(&"KneeL").y
	if chest > 0.9 or knee > 0.2:
		_fail("on all fours: chest %.2f m and knee %.2f m should be low" % [chest, knee])
	# Body shots fold, uppercuts lift the chin.
	rig.play_hit(true, false, Vector3.BACK, &"body")
	if not rig.current in [&"hit_body", &"hit_body_l", &"hit_body_r"]:
		rig.queue_free()
		_fail("a body shot should fold them, got %s" % rig.current)
		return
	rig.play_hit(true, false, Vector3.BACK, &"head", "uppercut")
	if rig.current != &"hit_uppercut":
		_fail("an uppercut should lift the chin, got %s" % rig.current)
	rig.queue_free()


## The procedural layer: a punch snaps the head away over a few frames, then it settles.
func _check_head_snap() -> void:
	var rig := CharacterRig.new()
	rig.look_id = "tom"
	rig.auto_return_to_idle = false
	root.add_child(rig)
	rig.play(&"block", 0.0)
	for i in 10:
		await process_frame
	# Sockets follow the modified skeleton (get_bone_global_pose shows the animated pose).
	var head := rig.get_socket(&"head")
	var rest := head.global_basis.get_rotation_quaternion()
	rig._reactor.hit(Vector3.BACK, &"head", 2.0)
	var most := 0.0
	for i in 30:
		await process_frame
		most = maxf(most, rest.angle_to(head.global_basis.get_rotation_quaternion()))
	if most < 0.15:
		_fail("a hit should snap the head back, it moved %.2f rad" % most)
	rig.set_head_bob(Vector2(1, 0))
	for i in 80:
		await process_frame
	var chest_x := rig.to_local(rig.get_socket(&"chest").global_position).x
	rig.set_head_bob(Vector2(-1, 0))
	for i in 80:
		await process_frame
	var moved := chest_x - rig.to_local(rig.get_socket(&"chest").global_position).x
	if moved < 0.05:
		_fail("slipping right then left should swing the chest across, moved %.2f m" % moved)
	rig.queue_free()


func _check_lying_down() -> void:
	var rig := CharacterRig.new()
	rig.look_id = "tom"
	root.add_child(rig)
	for a in [&"ko", &"crawl", &"down"]:
		rig.play(a, 0.0)
		rig.anim.advance(1.2)
		var h := rig.bone_position(&"Chest").y
		if h > 0.6:
			_fail("%s: chest still %.2f m off the floor" % [a, h])
	rig.queue_free()


func _check_ragdoll() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	root.add_child(ground)
	var rig := CharacterRig.new()
	rig.look_id = "kev"
	root.add_child(rig)
	await physics_frame
	var start := rig.ragdoll_hips_position()
	rig.play_hit(true, true, Vector3(0, 0, 1))
	rig.play_state("KO")
	if not rig.ragdolling:
		_fail("KO should start the ragdoll")
	for i in 150:
		await physics_frame
	var hips := rig.ragdoll_hips_position()
	if hips.y > 0.45:
		_fail("ragdoll hips still %.2f m up after 2.5 s" % hips.y)
	if hips.z < start.z + 0.1:
		_fail("ragdoll should fall the way it was hit (z %.2f -> %.2f)" % [start.z, hips.z])
	rig.play_state("IDLE")
	if rig.ragdolling or rig.current != &"idle":
		_fail("animation should take back over from the ragdoll")
	rig.queue_free()
	ground.queue_free()
