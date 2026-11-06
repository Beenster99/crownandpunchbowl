extends SceneTree
## Headless test: fighters on different floors can't hit each other (no punching through a
## gallery floor from underneath), and an NPC whose foe is upstairs takes the stairs.
## Run: godot --headless --path . --script res://tests/levels_test.gd

var _failures := 0


func _initialize() -> void:
	await process_frame
	var game_data := root.get_node("GameData")
	root.get_node("Net").start_solo("Tester", 0)
	game_data.start_crawl(0)
	var pub: Dictionary = game_data.PUBS[0]  # Crown and Punchbowl: gallery x -11..1, z -7.5..-4.5, top 2.5
	change_scene_to_file(pub["scene"])
	await _wait_for_scene(pub["scene"])
	var level = current_scene
	for _f in 60:
		await physics_frame
	var dir = level.director
	for n in get_nodes_in_group("npcs"):
		n.queue_free()
	var player = get_nodes_in_group("players")[0]
	player.max_hp = 100000.0
	player.hp = player.max_hp
	player.global_position = Vector3(-4.0, 2.5, -6.0)
	await physics_frame

	# 1. A punter right underneath the player, below the gallery floor.
	var npc = dir.spawn(&"rugby_lad", Vector3(-4.0, 0.0, -5.6))
	await physics_frame
	npc.engage(player)
	var hp0: float = player.hp
	for _f in 240:
		player.global_position = Vector3(-4.0, player.global_position.y, -6.0)
		await physics_frame
	_check(player.hp == hp0, "nobody punches through the gallery floor (hp %.0f -> %.0f)" % [hp0, player.hp])

	# 2. Given time, they come up the stairs and fight on the gallery.
	var got_up := false
	for _f in 60 * 20:
		player.global_position = Vector3(-4.0, player.global_position.y, -6.0)
		await physics_frame
		if npc.global_position.y > 2.0:
			got_up = true
			break
	_check(got_up, "the punter takes the stairs up to the player (y=%.2f at %s)" % [npc.global_position.y, npc.global_position])
	if got_up:
		for _f in 60 * 8:
			await physics_frame
			if player.hp < hp0:
				break
		_check(player.hp < hp0, "upstairs, on the same floor, he lands a blow")

	# 3. The other way round: player downstairs, punter up on the gallery comes down.
	npc.queue_free()
	player.hp = player.max_hp
	player.global_position = Vector3(-6.0, 0.0, -2.0)
	var upper = dir.spawn(&"rugby_lad", Vector3(-6.0, 2.5, -6.0))
	await physics_frame
	upper.engage(player)
	var got_down := false
	for _f in 60 * 20:
		player.global_position = Vector3(-6.0, player.global_position.y, -2.0)
		await physics_frame
		if upper.global_position.y < 0.3 and absf(upper.global_position.x - -6.0) < 2.5:
			got_down = true
			break
	_check(got_down, "a punter on the gallery comes down to a player below (at %s)" % upper.global_position)
	if _failures == 0:
		print("LEVELS OK")
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
	print(("ok   " if ok else "FAIL ") + what)
