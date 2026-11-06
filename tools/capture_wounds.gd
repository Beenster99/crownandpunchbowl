extends SceneTree
## Renders faces taking a beating: fresh, after a few punches, and after a lot, plus a
## body shot. Needs a real renderer:
## xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --script res://tools/capture_wounds.gd -- <out_dir>

const LOOKS := [["local", 3], ["rugby_lad", 5], ["rambler", 2], ["local", 8]]
## Rounds of punishment: [spot, hit strength, repeats].
const ROUNDS := [
	[],
	[[&"eye_l", 1.0, 2], [&"lip", 0.9, 1], [&"cheek_r", 1.0, 1]],
	[[&"eye_l", 1.1, 3], [&"brow_l", 1.2, 3], [&"lip", 1.0, 3], [&"cheek_r", 1.2, 3], [&"nose", 1.0, 2]],
	[[&"eye_r", 1.3, 4], [&"brow_r", 1.4, 3], [&"jaw_l", 1.2, 3], [&"chin", 1.0, 2], [&"forehead", 1.6, 1]],
]

var _rigs: Array = []
var _wounds: Array = []
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://captures"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2a2522")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8a7c70")
	env.environment.ambient_light_energy = 0.7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.4
	key.light_color = Color("ffe2c0")
	key.shadow_enabled = true
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.4
	world.add_child(fill)
	var rig_script: Script = load("res://scripts/actors/character_rig.gd")
	var looks_script: Script = load("res://scripts/actors/character_looks.gd")
	var wounds_script: Script = load("res://scripts/fx/wounds.gd")
	for n in LOOKS.size():
		var holder := Node3D.new()
		holder.name = "N%d" % (n + 1)
		holder.position = Vector3((n - (LOOKS.size() - 1) * 0.5) * 0.5, 0, 0)
		holder.rotation_degrees.y = 180.0  # face the camera (+Z)
		world.add_child(holder)
		var rig: Node3D = rig_script.new()
		rig.look = looks_script.punter(LOOKS[n][0], LOOKS[n][1])
		rig.start_animation = &"idle_relaxed"
		holder.add_child(rig)
		_rigs.append(rig)
		_wounds.append(wounds_script.attach(holder, rig))
	_cam = Camera3D.new()
	_cam.fov = 30
	world.add_child(_cam)
	await process_frame
	for r in _rigs:
		r.anim.pause()
	for round_i in ROUNDS.size():
		for w in _wounds:
			for hit in ROUNDS[round_i]:
				for k in int(hit[2]):
					w.apply_hit(w.spot_index(hit[0]), float(hit[1]))
		# Let the bruises colour up a bit before the later shots.
		for w in _wounds:
			for i in w.age.size():
				if w.age[i] > 0.0:
					w.age[i] += 8.0 * round_i
		await _shot("%s/faces_%d.png" % [out, round_i], 1.62, 2.1)
		await _shot("%s/face_close_%d.png" % [out, round_i], 1.66, 0.75, 1)
	# Body shots on a bare chest aren't common (shirts), but rugby lads go topless.
	quit(0)


func _shot(path: String, y: float, dist: float, only := -1) -> void:
	var x := 0.0
	if only >= 0:
		x = (_rigs[only] as Node3D).global_position.x
	_cam.position = Vector3(x, y, dist)
	_cam.look_at(Vector3(x, y - 0.02, 0))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
