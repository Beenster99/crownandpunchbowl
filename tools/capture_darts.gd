extends SceneTree
## Screenshot of the darts screen mid-game (not a test). Run under a display:
## xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --script res://tools/capture_darts.gd -- out.png


func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://darts.png"
	root.get_node("Net").start_solo("Beenster", 0)
	root.get_node("GameData").start_crawl(0)
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	change_scene_to_file("res://scenes/pubs/crown_and_punchbowl.tscn")
	for _f in 200:
		await process_frame
		if current_scene and current_scene.is_node_ready() and not get_nodes_in_group("players").is_empty():
			break
	var board = get_nodes_in_group("darts_games")[0]
	var player = get_nodes_in_group("players")[0]
	player.global_position = board.oche_point() + board.facing * 0.3
	await physics_frame
	board.handle_local_interact(player)
	board.game.add_player(2, "Dave")
	board.game.add_player(3, "Big Sue")
	board.request_start()
	# Play a few turns so the scoreboard has numbers.
	var aims := [[20, 3], [20, 3], [19, 3]]
	for turn in 6:
		for a in aims:
			board.game.throw_dart(load("res://scripts/darts/darts_rules.gd").target_point(a[0], a[1]) + Vector2(randf_range(-8, 8), randf_range(-8, 8)))
		board.game.end_turn()
	board._broadcast()
	board.request_throw(load("res://scripts/darts/darts_rules.gd").target_point(20, 3))
	board.request_throw(load("res://scripts/darts/darts_rules.gd").target_point(20, 1))
	for _f in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
