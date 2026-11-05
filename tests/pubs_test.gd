extends SceneTree
## Headless test for the four pubs: each one loads, builds its markers, spawns the
## player, fades the wall in front of a player standing by it, and the pub flow
## goes calm -> fight -> cleared -> next pub, finishing the crawl after four.
## Run: godot --headless --path . --script res://tests/pubs_test.gd

var _failures := 0


func _initialize() -> void:
	await process_frame
	var game_data := root.get_node("GameData")
	var events := root.get_node("Events")
	root.get_node("Net").start_solo("Tester", 0)
	game_data.start_crawl(0)
	var cleared := []
	events.pub_cleared.connect(func(id): cleared.append(id))

	for i in game_data.PUBS.size():
		var pub: Dictionary = game_data.PUBS[game_data.current_pub_index]
		if i == 0:
			change_scene_to_file(pub["scene"])
		await _wait_for_scene(pub["scene"])
		var level = current_scene
		_check(level.pub_id == pub["id"], "%s: pub_id matches GameData" % pub["id"])
		for kind in ["PlayerSpawns", "PunterSpots", "StaffSpots", "DoorSpawns", "PoliceSpawns", "PropSpawns", "Ledges"]:
			_check(level.get_markers(kind).size() > 0, "%s: has %s" % [pub["id"], kind])
		_check(level.get_bar_zones().size() > 0, "%s: has a bar zone" % pub["id"])
		var players := get_nodes_in_group("players")
		_check(players.size() == 1, "%s: one player spawned" % pub["id"])
		_check(get_nodes_in_group("camera_occluders").size() > 4, "%s: has camera occluders" % pub["id"])
		await _check_fading(level, players[0], pub["id"])
		await _check_stairs(level, players[0], pub["id"])

		# Flow: arriving -> calm -> fight -> cleared.
		await create_timer(level.arrival_time + 0.2).timeout
		_check(level.phase == level.Phase.CALM, "%s: settles to CALM" % pub["id"])
		events.fight_started.emit()
		_check(level.phase == level.Phase.FIGHT, "%s: fight starts" % pub["id"])
		level.clear_delay = 0.2
		level.pub_cleared()
		_check(level.phase == level.Phase.CLEARED, "%s: cleared" % pub["id"])
		if i < game_data.PUBS.size() - 1:
			await create_timer(0.4).timeout

	_check(cleared.size() == 4, "all four pubs cleared (%d)" % cleared.size())
	_check(game_data.crawl_finished(), "crawl finished")
	await create_timer(0.5).timeout
	_check(current_scene != null and current_scene.scene_file_path.ends_with("main_menu.tscn"), "back to the menu after the crawl")
	if _failures == 0:
		print("PUBS OK")
	quit(1 if _failures > 0 else 0)


func _wait_for_scene(path: String) -> void:
	for _f in 120:
		await process_frame
		if current_scene and current_scene.scene_file_path == path and current_scene.is_node_ready():
			await process_frame
			return
	_check(false, "scene %s loaded" % path)


## Stand the player against the front wall and check something in front of them fades,
## then move them to the middle of the room and check it comes back.
func _check_fading(level, player: Node3D, id: String) -> void:
	var room: Rect2 = level.room
	var mid_x := room.get_center().x
	player.global_position = Vector3(mid_x + 0.5, 0, room.end.y - 0.6)
	level.camera.snap()
	for _f in 40:
		await process_frame
	var faded: Array = level.fader._occluders.keys().filter(func(n): return level.fader.is_faded(n) and String(n.name).begins_with("Wall"))
	_check(faded.size() > 0, "%s: the front wall fades when the player stands by it" % id)
	player.global_position = Vector3(mid_x + 0.5, 0, room.get_center().y)
	level.camera.snap()
	for _f in 60:
		await process_frame
	var still: Array = level.fader._occluders.keys().filter(func(n): return level.fader.is_faded(n) and String(n.name).begins_with("Wall"))
	_check(still.is_empty(), "%s: walls are solid when the player is mid-room (%d faded)" % [id, still.size()])


## Walk the player up every flight of stairs and check they reach the top.
func _check_stairs(level, player: Node3D, id: String) -> void:
	var flights: Array = level.builder.stairs_built
	_check(flights.size() > 0, "%s: has stairs to an upper level" % id)
	var actions := {Vector3.FORWARD: "move_up", Vector3.BACK: "move_down", Vector3.LEFT: "move_left", Vector3.RIGHT: "move_right"}
	for f in flights:
		var dir: Vector3 = f["dir"]
		var top: Vector3 = f["top"]
		var action: String = actions[dir]
		player.global_position = f["base"] - dir * 0.6 + Vector3(0, 0.05, 0)
		player.velocity = Vector3.ZERO
		Input.action_press(action)
		var reached := false
		for _f in 240:
			await physics_frame
			if player.global_position.y > top.y - 0.15 and (player.global_position - f["base"]).dot(dir) > (top - f["base"]).dot(dir) - 0.2:
				reached = true
				break
		Input.action_release(action)
		_check(reached, "%s: can walk up stairs to %.1f m (got to %.2f)" % [id, top.y, player.global_position.y])
		# Standing still at the top, they should stay up there.
		for _f in 30:
			await physics_frame
		_check(player.global_position.y > top.y - 0.15, "%s: stays on the upper level" % id)
	# Find an unrailed high edge and walk off it: you should land on the floor below.
	var actions_by_normal := {Vector3.BACK: "move_down", Vector3.FORWARD: "move_up", Vector3.LEFT: "move_left", Vector3.RIGHT: "move_right"}
	for ledge in level.get_markers("Ledges"):
		if ledge.get_meta("railing") or float(ledge.get_meta("drop")) < 1.5:
			continue
		var n: Vector3 = ledge.get_meta("normal")
		player.global_position = ledge.global_position - n * 0.6 + Vector3(0, 0.05, 0)
		player.velocity = Vector3.ZERO
		Input.action_press(actions_by_normal[n])
		for _f in 90:
			await physics_frame
		Input.action_release(actions_by_normal[n])
		_check(player.global_position.y < 0.3, "%s: walking off an open edge drops you to the floor (y %.2f)" % [id, player.global_position.y])
		break
	player.global_position = level.get_markers("PlayerSpawns")[0].global_position


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		_failures += 1
		push_error("FAIL " + what)
		print("  FAIL ", what)
