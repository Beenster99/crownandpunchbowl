extends SceneTree
## Headless test of the first-person camera: switching in and out (setting, P, zooming past
## the closest view), the view sitting in the local player's head with the head hidden,
## movement relative to the view, and the overhead view coming back when you're on the floor.
## Run: godot --headless --path . --script res://tests/first_person_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		push_error("FAIL: " + what)
		print("FAIL: " + what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	await process_frame
	var settings := root.get_node("Settings")
	var net := root.get_node("Net")
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	settings.set_value("gameplay", "camera_view", 0)
	net.start_solo("Eyes", 0)
	net.start_game()
	await create_timer(1.0).timeout
	var cam = current_scene.get_node_or_null("BrawlCamera")
	var players := get_nodes_in_group("players")
	_check(cam != null and players.size() == 1, "pub with camera and a player")
	if cam == null or players.is_empty():
		quit(1)
		return
	var p = players[0]
	var cam_script = load("res://scripts/level/brawl_camera.gd")
	await _frames(5)
	_check(not cam_script.first_person and not p.first_person, "starts overhead")
	var over_y: float = cam.global_position.y

	# Zooming in past the closest overhead view drops into first person.
	cam.zoom = cam.min_zoom
	var wheel_in := InputEventMouseButton.new()
	wheel_in.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_in.pressed = true
	cam._input(wheel_in)
	_check(int(settings.get_value("gameplay", "camera_view")) == 1, "zoom in at the limit picks first person")
	await create_timer(0.6).timeout
	_check(cam_script.first_person and p.first_person, "first person is on")
	var head: Vector3 = p.get_head_position()
	_check(cam.global_position.distance_to(head) < 0.3, "camera sits in the head (%.2f m away, cam y %.2f was %.2f)" \
		% [cam.global_position.distance_to(head), cam.global_position.y, over_y])
	_check(absf(cam.fov - cam.FP_FOV) < 0.5, "first-person lens")
	var look: Vector3 = -cam.global_basis.z
	_check(Vector2(look.x, look.z).normalized().dot(Vector2(p.get_facing().x, p.get_facing().z)) > 0.95,
		"looking the way the player faces")
	var hider = cam._head_hider(p)
	_check(hider == null or hider.active, "own head hidden from the inside")

	# Walking free: forward walks the way you look, sideways turns.
	p.stance_target = null
	p.view_yaw = 0.0
	p._first_person_move(Vector2(0, -1), 0.1)
	_check(p.move_input.distance_to(Vector3(0, 0, -1)) < 0.01, "stick up walks forward (%s)" % p.move_input)
	var dodge: Vector3 = p._first_person_move(Vector2(1, 0), 0.1)
	_check(p.view_yaw < 0.0 and p.move_input.length() < 0.01, "stick right turns right without stepping")
	_check(dodge.x > 0.5 or dodge.z != 0.0, "a dodge still goes sideways")
	p.view_turn = 0.5
	var y0: float = p.view_yaw
	p._first_person_move(Vector2.ZERO, 0.016)
	_check(is_equal_approx(p.view_yaw, y0 - 0.5), "mouse turn applies")
	_check(p.face_override.length() > 0.9, "free: you face where you look")

	# Squared up: you look at him and the stick circles.
	p.view_yaw = 0.0
	p.rotation.y = 0.0
	p.stance_target = p  # any fighter will do for the maths; only its presence matters here
	p._first_person_move(Vector2(1, 0), 0.016)
	_check(p.move_input.distance_to(Vector3(1, 0, 0)) < 0.01, "squared up: stick right steps right (%s)" % p.move_input)
	_check(p.face_override == Vector3.ZERO, "squared up: stance does the facing")
	p.stance_target = null

	# Overhead comes back while you're on the floor.
	p.take_hit({"attacker": null, "damage": 1.0, "direction": Vector3.FORWARD, "knockdown": true,
		"knockback": 0.0, "poise": 999.0})
	await _frames(3)
	if p.is_down():
		_check(not cam_script.first_person, "on the floor: overhead view")

	# P toggles, zoom out leaves.
	settings.set_value("gameplay", "camera_view", 1)
	var wheel_out := InputEventMouseButton.new()
	wheel_out.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_out.pressed = true
	cam._input(wheel_out)
	_check(int(settings.get_value("gameplay", "camera_view")) == 0, "zoom out leaves first person")
	var pkey := InputEventKey.new()
	pkey.physical_keycode = KEY_P
	pkey.pressed = true
	cam._input(pkey)
	_check(int(settings.get_value("gameplay", "camera_view")) == 1, "P switches to first person")
	cam._input(pkey)
	_check(int(settings.get_value("gameplay", "camera_view")) == 0, "P switches back")

	if _failed:
		quit(1)
	else:
		print("FIRST PERSON OK")
		quit(0)
