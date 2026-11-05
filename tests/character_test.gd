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
	await _check_ragdoll()
	if _failures == 0:
		print("CHARACTERS OK: %d looks, %d animations" % [CharacterLooks.all_ids().size(), CharacterRig.ANIMATIONS.size()])
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
		if rig.anim.get_animation_list().size() != CharacterRig.ANIMATIONS.size():
			_fail("%s: animation list and ANIMATIONS differ" % id)
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
	if not CharacterRig.CALM_IDLES.has(rig.current):
		_fail("a fresh character should stand relaxed, got %s" % rig.current)
	rig.set_talking(true)
	if rig.current != &"idle_chat":
		_fail("chatting should gesture, got %s" % rig.current)
	rig.set_guard(true)
	if rig.current != &"idle":
		_fail("guard up should raise the fists, got %s" % rig.current)
	rig.set_move_speed(3.0)
	if rig.current != &"walk":
		_fail("guarded walk expected, got %s" % rig.current)
	rig.set_guard(false)
	if rig.current != &"walk_relaxed":
		_fail("calm walk expected, got %s" % rig.current)
	rig.set_move_speed(0.0)
	rig.set_talking(false)
	if not CharacterRig.CALM_IDLES.has(rig.current):
		_fail("should settle back to a calm idle, got %s" % rig.current)
	rig.queue_free()
	var barman := CharacterRig.new()
	barman.look_id = "barman"
	barman.staff = true
	root.add_child(barman)
	if barman.current != &"idle_polish":
		_fail("bar staff should polish glasses, got %s" % barman.current)
	barman.queue_free()


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
