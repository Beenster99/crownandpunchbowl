extends SceneTree
## Renders each pub, dressed, from an overview and a few game-camera angles. Needs a renderer:
## xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_pubs.gd -- <out_dir> [pub_id...]
## The front wall is hidden so the overview can see in. Slow under llvmpipe (~1 fps).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://captures"
	var only := args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	await process_frame
	# Loaded at run time: PubLevel needs the autoloads, which SceneTree scripts compile before.
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	for pub_id in ["crown_and_punchbowl", "king_william", "farmers_dog", "pillock_tickle"]:
		if not only.is_empty() and not only.has(pub_id):
			continue
		var scene: Node3D = load("res://scenes/pubs/%s.tscn" % pub_id).instantiate()
		root.add_child(scene)
		current_scene = scene
		for i in 4:
			await process_frame
		var room: Rect2 = scene.get("room")
		for w in scene.builder.walls_built:
			if w["along_x"] and (w["origin"] as Vector3).z >= room.end.y - 0.1:
				(w["root"] as Node3D).visible = false
		for n in scene.get_tree().get_nodes_in_group("camera_occluders"):
			if n is Node3D and n.name.begins_with("Beam"):
				(n as Node3D).visible = false
		var cam := Camera3D.new()
		scene.add_child(cam)
		cam.current = true
		cam.fov = 45.0
		var c := room.get_center()
		var shots := {
			"overview": [Vector3(c.x, 15.0, room.end.y + 9.0), Vector3(c.x, 0.0, c.y - 1.0)],
			"left": [Vector3(c.x - room.size.x * 0.28, 6.5, c.y + 6.0), Vector3(c.x - room.size.x * 0.28, 0.6, c.y - 2.5)],
			"centre": [Vector3(c.x, 6.5, c.y + 5.5), Vector3(c.x, 0.6, c.y - 3.0)],
			"right": [Vector3(c.x + room.size.x * 0.28, 6.5, c.y + 6.0), Vector3(c.x + room.size.x * 0.28, 0.6, c.y - 2.5)],
		}
		for shot in shots:
			cam.look_at_from_position(shots[shot][0], shots[shot][1])
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [out, pub_id, shot]
			root.get_texture().get_image().save_png(path)
			print("saved ", path)
		print("%s: %d decor props" % [pub_id, scene.get_tree().get_nodes_in_group(&"pub_props").size()])
		scene.queue_free()
		await process_frame
	quit(0)
