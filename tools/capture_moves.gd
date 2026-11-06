extends SceneTree
## Renders one character through a move, frame by frame, as a contact sheet, so you can
## judge a punch's wind-up, contact and recovery. Needs a real renderer:
## xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_moves.gd -- <out.png> [look] [view] anim[@t1,t2,...] ...
##   view: side (default), front, top, three, close (head and fists) or hand (right hand)
##   e.g. -- /tmp/cross.png tom side punch_r@0,0.04,0.08,0.11,0.13,0.19,0.3,0.46

const CELL := Vector2i(360, 420)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://moves.png"
	var look := args[1] if args.size() > 1 else "tom"
	var view := args[2] if args.size() > 2 else "side"
	var shots: Array = []
	for a in args.slice(3):
		var parts := String(a).split("@")
		var times := [0.0]
		if parts.size() > 1:
			times = Array(parts[1].split(",")).map(func(x): return float(x))
		for t in times:
			shots.append([StringName(parts[0]), t])
	if shots.is_empty():
		shots = [[&"idle", 0.0]]
	var vp := SubViewport.new()
	vp.size = CELL
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("d9b98a")
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.7)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("6b4426")
	floor.material_override = fm
	world.add_child(floor)
	var rig := CharacterRig.new()
	rig.look_id = look
	rig.ragdoll_on_ko = false
	world.add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.current = true
	await process_frame
	match view:
		"front":
			cam.position = Vector3(0, 1.1, -4.6)
			cam.look_at(Vector3(0, 1.0, 0))
		"top":
			cam.position = Vector3(0, 5.5, 0.01)
			cam.look_at(Vector3(0, 0, 0))
		"close":
			cam.fov = 17.0
			cam.position = Vector3(-1.8, 1.75, -3.6)
			cam.look_at(Vector3(0, 1.5, -0.2))
		"three":
			cam.position = Vector3(-3.0, 1.6, -3.4)
			cam.look_at(Vector3(0, 1.0, 0))
		_:
			cam.position = Vector3(-4.6, 1.1, 0)  # the character's left side, facing -Z
			cam.look_at(Vector3(0, 1.0, 0))
	var cols := mini(shots.size(), 6)
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var shot: Array = shots[i]
		rig.anim.stop()
		rig.anim.play(shot[0], 0.0)
		rig.anim.seek(shot[1], true)
		rig.anim.pause()
		await process_frame
		if view == "hand":
			# Close on the right hand, wherever the pose puts it.
			var hp := rig.get_socket(&"hand_r").global_position
			cam.fov = 14.0
			cam.position = hp + Vector3(1.4, 0.5, -1.2)
			cam.look_at(hp)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
	sheet.save_png(out)
	print("saved ", out)
	quit(0)
