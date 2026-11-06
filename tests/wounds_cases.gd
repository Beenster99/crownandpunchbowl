extends Node
## Test cases for Wounds and WoundSkin. Loaded by wounds_test.gd once the autoloads exist.

signal finished(failures: int)

var _failures := 0
var _arena: Node3D


func run() -> void:
	GameData.difficulty_index = 1
	var fx := get_node_or_null("/root/Fx")
	if fx != null and "hit_stop_time_scale" in fx:
		fx.hit_stop_time_scale = 1.0
	var tests := [
		"test_punch_marks_the_face", "test_repeats_build_up", "test_cuts_open", "test_side_of_the_hook",
		"test_body_and_groin", "test_guarded_hits_leave_no_mark", "test_staff_stay_clean",
		"test_broken_nose", "test_skin_shows_marks",
	]
	for t in tests:
		print("  ", t)
		_arena = Node3D.new()
		add_child(_arena)
		_floor()
		await call(t)
		_arena.queue_free()
		await get_tree().process_frame
	if _failures == 0:
		print("WOUNDS OK: %d tests" % tests.size())
	finished.emit(_failures)


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(40, 0.2, 40)
	body.add_child(shape)
	body.position.y = -0.1
	_arena.add_child(body)


func _fighter(team: int, pos: Vector3, face_toward := Vector3.INF) -> Fighter:
	var f := Fighter.new()
	f.team = team
	f.collision_layer = 2 if team == Fighter.Team.PLAYERS else 4
	f.collision_mask = 7
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.position.y = 0.875
	f.add_child(shape)
	f.position = pos
	_arena.add_child(f)
	if face_toward != Vector3.INF:
		var d := face_toward - pos
		f.rotation.y = atan2(-d.x, -d.z)
	return f


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


func _wounds(f: Node) -> Wounds:
	return f.get_node_or_null(Wounds.NODE_NAME) as Wounds


func _face_spots() -> Array:
	return Wounds.SPOTS.filter(func(s): return s["region"] == &"face").map(func(s): return s["id"])


# --- Tests -----------------------------------------------------------------------------

func test_punch_marks_the_face() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -4))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.7))
	await _wait(0.1)
	var w := _wounds(e)
	_check(w != null, "every fighter with a character gets Wounds")
	if w == null:
		return
	_check(not w.is_marked(), "a fresh punter is unmarked")
	p.request_attack(&"jab")
	await _wait(0.6)
	_check(e.hp < e.max_hp, "the jab landed")
	_check(w.is_marked(), "a jab to the face leaves a mark")
	_check(w.worst() in _face_spots(), "a jab marks the face, not the body (%s)" % w.worst())


func test_repeats_build_up() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))
	await _wait(0.05)
	var w := _wounds(e)
	var eye := Wounds.spot_index(&"eye_l")
	var steps: Array[float] = []
	var last := 0.0
	for i in 5:
		w.apply_hit(eye, 1.0)
		steps.append(w.swell[eye] - last)
		last = w.swell[eye]
	_check(w.hits_on(&"eye_l") == 5, "hits are counted per spot")
	_check(steps[4] > steps[0] * 3.0, "swelling comes up faster with every repeat (%s)" % [steps])
	_check(w.bruise_of(&"eye_l") > 0.8, "five shots blacken the eye (%.2f)" % w.bruise_of(&"eye_l"))
	_check(w.bruise_of(&"cheek_l") > 0.0 and w.bruise_of(&"cheek_l") < w.bruise_of(&"eye_l"),
		"a black eye spreads a little to the cheek")
	_check(w.bruise_of(&"eye_r") == 0.0, "the other eye is untouched")
	_check(w.cut_of(&"eye_l") == 0.0, "eyes bruise and close, they don't split")


func test_cuts_open() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))
	await _wait(0.05)
	var w := _wounds(e)
	var brow := Wounds.spot_index(&"brow_r")
	w.apply_hit(brow, 1.0)
	w.apply_hit(brow, 1.0)
	_check(w.cut_of(&"brow_r") == 0.0, "two ordinary shots bruise the brow but don't split it")
	w.apply_hit(brow, 1.0)
	_check(w.cut_of(&"brow_r") > 0.0, "a third shot on the same brow splits it")
	var opened := w.cut_of(&"brow_r")
	w.apply_hit(brow, 1.0)
	_check(w.cut_of(&"brow_r") > opened, "a cut gets worse if they keep hitting it")
	var lip := Wounds.spot_index(&"lip")
	w.apply_hit(lip, w.strength({"damage": 14.0, "heavy": true, "clean": true}))
	_check(w.cut_of(&"lip") > 0.0, "one big clean shot splits a lip")


func test_side_of_the_hook() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))  # faces -Z
	await _wait(0.05)
	var w := _wounds(e)
	var lefts := 0
	var rights := 0
	for i in 30:
		# Knocked towards their right (+X): it came in on their left.
		var id := String(Wounds.SPOTS[w.pick_spot({"move": "hook", "zone": &"head", "direction": Vector3(0.8, 0, -0.6)})]["id"])
		lefts += int(id.ends_with("_l"))
		var id2 := String(Wounds.SPOTS[w.pick_spot({"move": "hook", "zone": &"head", "direction": Vector3(-0.8, 0, -0.6)})]["id"])
		rights += int(id2.ends_with("_r"))
	_check(lefts == 30 and rights == 30, "hooks mark the side they land on (%d, %d of 30)" % [lefts, rights])
	var ups := {}
	for i in 30:
		ups[Wounds.SPOTS[w.pick_spot({"move": "uppercut", "zone": &"head", "direction": Vector3.FORWARD})]["id"]] = true
	for id in ups:
		_check(id in [&"chin", &"lip", &"nose"], "uppercuts land on the chin, lips or nose (%s)" % id)


func test_body_and_groin() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))
	await _wait(0.05)
	var w := _wounds(e)
	for i in 20:
		var s := w.pick_spot({"move": "body_hook", "zone": &"body", "direction": Vector3(0.8, 0, -0.6)})
		_check(Wounds.SPOTS[s]["region"] == &"body", "body shots mark the body")
	var r := w.pick_spot({"move": "body_hook", "zone": &"body", "direction": Vector3(-0.9, 0, -0.3)})
	_check(Wounds.SPOTS[r]["id"] in [&"ribs_r", &"gut"], "a body hook digs into the ribs on its side")
	_check(w.pick_spot({"move": "groin_kick", "zone": &"groin"}) == -1, "groin shots don't show")
	var kicked := _fighter(Fighter.Team.PUNTERS, Vector3(3, 0, 0))
	await _wait(0.05)
	kicked.take_hit({"attacker": null, "damage": 8.0, "move": "groin_kick", "zone": &"groin",
		"direction": Vector3.FORWARD})
	_check(not _wounds(kicked).is_marked(), "a kick in the groin leaves no visible mark")


func test_guarded_hits_leave_no_mark() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -4))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	e.parry_skill = 0.0
	e.request_block(true)
	await _wait(0.5)  # past the parry window
	p.request_attack(&"jab")
	await _wait(0.6)
	_check(e.hp < e.max_hp, "the jab chipped the guard")
	_check(not _wounds(e).is_marked(), "a punch on the gloves leaves no mark")


func test_staff_stay_clean() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var s := _fighter(Fighter.Team.STAFF, Vector3(0, 0, -1.0))
	await _wait(0.1)
	s.take_hit({"attacker": p, "damage": 50.0, "move": "cross", "zone": &"head", "direction": Vector3.FORWARD})
	p.request_attack(&"cross", s)
	await _wait(0.6)
	var w := _wounds(s)
	_check(w == null or not w.is_marked(), "nobody can mark the bar staff")


func test_broken_nose() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))
	await _wait(0.05)
	Events.nose_broken.emit(e)
	var w := _wounds(e)
	_check(w.swell_of(&"nose") >= 0.69 and w.cut_of(&"nose") > 0.0, "a broken nose swells up and bleeds")
	_check(w.bruise_of(&"eye_l") > 0.0 and w.bruise_of(&"eye_r") > 0.0, "a broken nose blackens both eyes")


func test_skin_shows_marks() -> void:
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 0))
	await _wait(0.1)
	var w := _wounds(e)
	_check(w.skin != null, "the character gets a WoundSkin")
	if w.skin == null:
		return
	var body := w.skin._body
	_check(body != null, "the skin finds the Body mesh")
	if body == null:
		return
	var fmt := (body.mesh as ArrayMesh).surface_get_format(0)
	_check(fmt & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "the body carries rest positions in CUSTOM0")
	_check(body.skin != null, "the patched body is still skinned")
	_check(not w.skin.is_showing(), "no overlay before the first hit")
	w.apply_hit(Wounds.spot_index(&"eye_l"), 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(w.skin.is_showing(), "the overlay goes on once marked")
	# The spots sit where they should on the face.
	var sk: Skeleton3D = w.skin.rig.skeleton
	var eyes := sk.get_node_or_null("Eyes") as MeshInstance3D
	if eyes != null:
		var c := eyes.mesh.get_aabb().get_center()
		var el := w.skin.spot_position(&"eye_l")
		var er := w.skin.spot_position(&"eye_r")
		_check(el.x < 0.0 and er.x > 0.0, "the left eye spot is on the left (%s, %s)" % [el, er])
		_check(absf(el.y - c.y) < 0.03 and absf(er.y - c.y) < 0.03, "eye spots are level with the eyes")
		var lip := w.skin.spot_position(&"lip")
		var chin := w.skin.spot_position(&"chin")
		_check(lip.y < c.y - 0.04 and chin.y < lip.y, "lip below the eyes, chin below the lip")
		_check(w.skin.spot_position(&"nose").z < el.z, "the nose sticks out past the eyes")
