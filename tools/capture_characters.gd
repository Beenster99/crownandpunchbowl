extends SceneTree
## Renders the character line-up to PNGs for docs and reviews. Needs a real renderer:
## xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_characters.gd -- <out_dir>

const SHOTS := [
	["idle", 0.6, true, false],
	["punch_r", 0.18, true, false],
	["headbutt", 0.27, true, false],
	["crawl", 0.9, true, true],
	["ko", 1.0, false, true],
	["hold", 0.3, true, false],
	["drink", 0.8, true, false],
	["kick", 0.3, true, false],
	["ragdoll", 2.5, true, true],
	["ragdoll", 0.0, false, true],
	["idle", 0.6, false, false],
	["idle_relaxed", 1.2, true, false],
	["idle_pint", 3.2, true, false],
	["idle_chat", 0.9, true, false],
	["idle_polish", 0.5, true, false],
	["walk_relaxed", 0.3, true, false],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://captures"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	var scene: Node = load("res://scenes/actors/character_lineup.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for shot in SHOTS:
		scene._close = shot[2]
		scene._set_camera()
		for r in scene.rigs:
			r.set_blood(1.0 if shot[3] else 0.0)
		if shot[0] == "ragdoll":
			if shot[1] > 0.0:
				scene.knock_out_all()
				for i in int(shot[1] * 60.0):
					await physics_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var rimg := root.get_texture().get_image()
			var rpath := "%s/ragdoll_%s.png" % [out, "close" if shot[2] else "game"]
			rimg.save_png(rpath)
			print("saved ", rpath)
			continue
		scene.play_all(StringName(shot[0]))
		# Seek rather than wait, so the pose is the same however fast frames run.
		for r in scene.rigs:
			r.anim.stop()
			r.anim.play(StringName(shot[0]), 0.0)
			r.anim.seek(shot[1], true)
			r.anim.pause()  # big first-frame deltas would otherwise run one-shots to the end
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [out, shot[0], "close" if shot[2] else "game"]
		img.save_png(path)
		print("saved ", path)
	quit(0)
