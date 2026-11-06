extends SceneTree
## Renders a body being knocked over the bar at the Crown and Punchbowl as a 2x2 contact
## sheet, to eyeball the ragdoll and props. Needs a real renderer and a fixed step:
## xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 30 \
##   --script res://tools/capture_physics.gd -- <out.png>

const TIMES := [0.12, 0.3, 0.55, 1.3]
const CELL := Vector2i(800, 450)


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://physics.png"
	await process_frame
	var net := root.get_node("Net")
	net.start_solo("Tester", 0)
	root.get_node("GameData").start_crawl(0)
	root.get_node("Fx").hit_stop_time_scale = 1.0
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	change_scene_to_file("res://scenes/pubs/crown_and_punchbowl.tscn")
	for _f in 400:
		await process_frame
		if current_scene != null and current_scene.is_node_ready() and not get_nodes_in_group("players").is_empty():
			break
	var p: Node3D = get_nodes_in_group("players")[0]
	for _f in 20:
		await physics_frame
	var cam := Camera3D.new()
	cam.fov = 50.0
	current_scene.add_child(cam)
	cam.global_position = Vector3(1.2, 2.3, -1.6)
	cam.look_at(Vector3(5.4, 0.7, -5.6))
	cam.current = true
	# Something to scatter on the way: a pair of loose chairs and glasses on the counter.
	var items = current_scene.get("items")
	items.server_spawn(&"chair", Vector3(5.6, 0, -4.4))
	items.server_spawn(&"glass", Vector3(5.2, 1.12, -5.3))
	items.server_spawn(&"pint", Vector3(5.7, 1.12, -5.4))
	p.global_position = Vector3(5.4, 0, -3.4)
	p.rotation.y = 0.0
	for _f in 10:
		await physics_frame
	p.take_hit({"attacker": null, "move": "test", "damage": 1.0, "direction": Vector3(0, 0, -1),
		"heavy": true, "knockdown": true, "knockback": 9.5 * float(p.get("toughness")), "poise": 0.0})
	var sheet := Image.create(CELL.x * 2, CELL.y * 2, false, Image.FORMAT_RGBA8)
	var t := 0.0
	for i in TIMES.size():
		while t < TIMES[i]:
			await physics_frame
			t += 1.0 / 30.0
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % 2) * CELL.x, (i / 2) * CELL.y))
	sheet.save_png(out)
	print("saved ", out)
	quit()
