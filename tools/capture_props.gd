extends SceneTree
## Renders every prop in PropLibrary to contact sheets, one per category. Needs a renderer:
## xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_props.gd -- <out_dir> [category...]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://captures"
	var only := args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 1000)
	var cats := {}
	for k in PropLibrary.kinds():
		for n in PropLibrary.variants(k):
			var c: String = PropLibrary.info(n)["category"]
			if only.is_empty() or only.has(c):
				if not cats.has(c):
					cats[c] = []
				cats[c].append(n)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2a2622")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8a8070")
	env.environment.ambient_light_energy = 0.6
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	stage.add_child(sun)
	var fill := OmniLight3D.new()
	fill.light_color = Color("ffc890")
	fill.light_energy = 1.5
	fill.omni_range = 30.0
	stage.add_child(fill)
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.current = true
	for c in cats:
		var holder := Node3D.new()
		stage.add_child(holder)
		var names: Array = cats[c]
		var cols := ceili(sqrt(names.size() * 1.6))
		var cell := 0.0
		for n in names:
			var d := PropLibrary.dims(n)
			cell = maxf(cell, maxf(d.x, d.z) * 1.25 + 0.05)
			cell = maxf(cell, d.y * 0.9)
		var rows := ceili(float(names.size()) / cols)
		for i in names.size():
			var v := PropLibrary.visual(names[i])
			var x := (i % cols - (cols - 1) * 0.5) * cell
			var z := (i / cols - (rows - 1) * 0.5) * cell
			v.position = Vector3(x, 0, z)
			var info := PropLibrary.info(names[i])
			if bool(info.get("pinned", false)):
				v.rotation_degrees.x = -90.0  # lay wall pieces face up
				v.position.y = 0.02
			holder.add_child(v)
			var label := Label3D.new()
			label.text = names[i]
			label.pixel_size = cell * 0.0012
			label.position = Vector3(x, 0.01, z + cell * 0.45)
			label.rotation_degrees.x = -90
			label.modulate = Color("e8e0d0")
			holder.add_child(label)
		var span := maxf(cols, rows) * cell
		cam.look_at_from_position(Vector3(0, span * 0.62, span * 0.5), Vector3(0, 0, 0.05 * span))
		cam.fov = 50.0
		fill.position = Vector3(0, span * 0.6, span * 0.4)
		await process_frame
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/props_%s.png" % [out, c]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		holder.free()
	quit(0)
