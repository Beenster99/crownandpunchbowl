extends SceneTree
## Contact sheets of every converted Mixamo clip on one character, to review the retarget
## and pick clips. Needs a real renderer:
## xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_mixamo.gd -- <out_dir> [look] [clip ...]
## One PNG per clip: six frames spread over the clip, from the character's front-left.

const CELL := Vector2i(240, 300)
const FRAMES := 6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://mixamo"
	var look := args[1] if args.size() > 1 else "tom"
	DirAccess.make_dir_recursive_absolute(out_dir)
	RigMixamo.preview_all = true
	var clips: Array = args.slice(2) if args.size() > 2 else RigMixamo.all_clips()
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
	pm.size = Vector2(8, 8)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("6b4426")
	floor.material_override = fm
	world.add_child(floor)
	var rig := CharacterRig.new()
	rig.look_id = look
	rig.ragdoll_on_ko = false
	rig.auto_return_to_idle = false
	world.add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.current = true
	await process_frame
	cam.position = Vector3(-3.0, 1.7, -3.6)
	cam.look_at(Vector3(0, 0.8, 0))
	for c in clips:
		var anim_name := StringName("mx_" + String(c))
		if not rig.anim.has_animation(anim_name):
			print("missing ", anim_name)
			continue
		var length := rig.anim.get_animation(anim_name).length
		var sheet := Image.create(CELL.x * FRAMES, CELL.y, false, Image.FORMAT_RGBA8)
		for i in FRAMES:
			rig.anim.stop()
			rig.anim.play(anim_name, 0.0)
			rig.anim.seek(length * i / float(FRAMES - 1), true)
			rig.anim.pause()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
		sheet.save_png(out_dir.path_join(String(c) + ".png"))
	print("saved ", clips.size(), " sheets to ", out_dir)
	quit(0)
