extends SceneTree
## Headless test: punters and police who come in through the door mid-fight land on the
## pub floor in every pub (the door marker is outside, over nothing), and one that falls
## out of the world anyway is put back inside.
## Run: godot --headless --path . --script res://tests/arrivals_test.gd

var _failures := 0


func _initialize() -> void:
	await process_frame
	var game_data := root.get_node("GameData")
	root.get_node("Net").start_solo("Tester", 0)
	game_data.start_crawl(0)
	for pub in game_data.PUBS:
		change_scene_to_file(pub["scene"])
		await _wait_for_scene(pub["scene"])
		var id: String = pub["id"]
		var dir = current_scene.director
		dir.start()  # solo signals "all peers loaded" once; later pubs are started by hand
		for _f in 30:
			await physics_frame
		_check(dir != null and dir.reserve > 0, "%s: director has a reserve" % id)
		if dir == null:
			continue
		var before := {}
		for n in get_nodes_in_group("npcs"):
			before[n] = true
		dir.heat = 0.8
		dir.send_wave(3)
		dir._police_arrive()
		var newbies := get_nodes_in_group("npcs").filter(func(n): return not before.has(n))
		_check(newbies.size() == 5, "%s: 3 punters and 2 police came in (%d)" % [id, newbies.size()])
		for _f in 90:
			await physics_frame
		for n in newbies:
			_check(n.global_position.y > -0.2, "%s: %s stands on the floor (y=%.2f)" % [id, n.name, n.global_position.y])
		# Safety net: drop one through the floor; the director puts it back.
		var lost = newbies[0]
		lost.global_position = Vector3(lost.global_position.x, -20.0, lost.global_position.z)
		for _f in 60:
			await physics_frame
		_check(lost.global_position.y > -0.2, "%s: a punter who fell out of the world is put back (y=%.2f)" % [id, lost.global_position.y])
	if _failures == 0:
		print("ARRIVALS OK")
	quit(1 if _failures > 0 else 0)


func _wait_for_scene(path: String) -> void:
	for _f in 240:
		await process_frame
		if current_scene and current_scene.scene_file_path == path and current_scene.is_node_ready():
			await process_frame
			return


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: ", what)
