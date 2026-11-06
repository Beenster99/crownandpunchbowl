extends SceneTree
## Screenshots of the first-person view squared up to a punter (not a test). Run under a display:
## xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --script res://tools/capture_first_person.gd -- out_prefix


func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://fp"
	root.get_node("Settings").set_value("gameplay", "camera_view", 1)
	root.get_node("Net").start_solo("Beenster", 0)
	root.get_node("GameData").start_crawl(0)
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	change_scene_to_file("res://scenes/pubs/crown_and_punchbowl.tscn")
	for _f in 300:
		await process_frame
		if current_scene and current_scene.is_node_ready() and not get_nodes_in_group("players").is_empty():
			break
	var player = get_nodes_in_group("players")[0]
	var sp = load("res://scenes/actors/sparring_punter.tscn").instantiate()
	player.get_parent().add_child(sp)
	sp.global_position = player.global_position + player.get_facing() * 1.5
	sp.look_at(player.global_position, Vector3.UP)
	sp.rotate_y(PI)
	sp.rotation.y = player.rotation.y + PI
	for _f in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "_idle.png")
	player.toggle_lock()
	player._set_block(true, &"guard_head")
	for _f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "_guard.png")
	player._set_block(false, &"guard_head")
	player.press(&"jab")
	for shot in 3:
		for _f in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "_jab%d.png" % shot)
	root.get_node("Settings").set_value("gameplay", "camera_view", 0)  # don't leave it on for the next run
	root.get_node("Settings").save_settings()
	print("saved ", out)
	quit()
