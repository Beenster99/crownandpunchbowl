extends SceneTree
## Headless FX test: every sound cue loads, and gameplay events produce blood, bloody
## faces, crawl moaning and a hit-stop that always releases.
## Run: godot --headless --path . --script res://tests/fx_test.gd
## (Only SoundBank is referenced by class here: classes that use autoloads must not be
## compiled before the autoloads exist, so the rest is reached through the `Fx` node.)

var _failed := false


func _initialize() -> void:
	await process_frame
	var fx: Node = root.get_node("Fx")
	var events: Node = root.get_node("Events")
	var settings: Node = root.get_node("Settings")
	settings.values["gameplay"]["blood"] = 1

	# 1. Every cue's files exist and load.
	var files := 0
	for cue in SoundBank.CUES:
		for path in SoundBank.files_for(cue):
			_check(load(path) is AudioStream, "missing sound %s" % path)
			files += 1
		var s := SoundBank.stream(cue) as AudioStreamRandomizer
		_check(s != null and s.streams_count == int(SoundBank.CUES[cue]["count"]), "cue %s incomplete" % cue)

	# 1b. Every bark line and every chatter line has a recording.
	var barks: Script = load("res://scripts/fx/bark_lines.gd")
	var cast: Script = load("res://scripts/fx/voice_cast.gd")
	var bark_files := 0
	for vid in barks.VOICES:
		for cat in barks.VOICES[vid]["lines"]:
			for i in barks.VOICES[vid]["lines"][cat].size():
				var path: String = cast.bark_path(vid, cat, i)
				_check(ResourceLoader.exists(path), "missing bark %s" % path)
				bark_files += 1
	var chatter: Script = load("res://scripts/ai/chatter_lines.gd")
	var posh := Node3D.new()
	posh.set_meta("voice_id", "posh_m1")
	posh.name = "N7"
	var missing_chatter := 0
	for k in chatter.all_keys():
		if cast.chatter_path(k, posh) == "":
			missing_chatter += 1
	_check(missing_chatter == 0, "%d chatter lines have no recording" % missing_chatter)
	posh.free()

	# 2. Fire events at a dummy in the test pub.
	root.get_node("Net").start_solo("FxTest", 0)
	change_scene_to_file("res://scenes/pubs/test_pub.tscn")
	await create_timer(0.5).timeout
	var player := get_nodes_in_group("players")[0] as Node3D
	var dummy := Node3D.new()
	dummy.name = "N1"
	current_scene.add_child(dummy)
	dummy.global_position = player.global_position + Vector3(0, 0, -1.3)

	events.hit_landed.emit({"attacker": player, "victim": dummy, "move": "punch", "damage": 10.0,
		"position": dummy.global_position + Vector3.UP * 1.5, "direction": Vector3.FORWARD,
		"heavy": true, "to_face": true})
	_check(Engine.time_scale < 1.0, "hit-stop did not engage for a local player's heavy hit")
	events.nose_broken.emit(dummy)
	events.fighter_knocked_down.emit(dummy)
	events.fighter_crawling.emit(dummy)
	_check(fx.is_crawling(dummy), "crawler not tracked")
	for i in 10:
		dummy.global_position += Vector3(0.1, 0, 0)
		await process_frame
	# Sample while waiting: short groans can finish before any single check.
	var speaking := 0
	var until := Time.get_ticks_msec() + 1600
	while Time.get_ticks_msec() < until:
		for p in fx.get_children():
			if p is AudioStreamPlayer3D and p.playing:
				speaking += 1
		await process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop never released (time_scale %s)" % Engine.time_scale)
	_check(dummy.get_node_or_null("FxFaceBlood") != null, "no bloody face decal")
	_check(fx.blood.decal_count() > 0, "no floor blood decals")
	_check(speaking > 0, "nothing is playing")

	events.fighter_knocked_out.emit(dummy)
	_check(not fx.is_crawling(dummy), "KO'd fighter still crawling")
	_check(fx.moans_left(dummy) == fx.ko_moans, "KO'd fighter has no moan budget")

	# 2b. Pain sounds stop: a few moans each, then quiet, and nothing once the fight's over.
	var groaner := Node3D.new()
	groaner.name = "N9"
	current_scene.add_child(groaner)
	fx.crawl_moan_every = Vector2(0.05, 0.06)
	events.fighter_crawling.emit(groaner)
	await create_timer(2.0).timeout  # the first moan waits up to 1.2 s
	_check(fx.is_crawling(groaner) and fx.moans_left(groaner) == 0,
		"crawler kept moaning past %d groans (%d left)" % [fx.crawl_moans, fx.moans_left(groaner)])
	var ko2 := Node3D.new()
	ko2.name = "N10"
	current_scene.add_child(ko2)
	events.fighter_knocked_out.emit(ko2)
	events.fighter_crawling.emit(groaner)
	events.pub_cleared.emit("test")
	_check(fx.moans_left(ko2) == 0 and fx.moans_left(groaner) == 0, "moaning carried on after the pub was cleared")
	var groaning := 0
	until = Time.get_ticks_msec() + 600
	while Time.get_ticks_msec() < until:
		for p in fx.get_children():
			if p is AudioStreamPlayer3D and p.playing and String(p.get_meta("cue", "")).begins_with("groan"):
				groaning += 1
		await process_frame
	_check(groaning == 0, "groans still playing after the pub was cleared")
	fx.crawl_moan_every = Vector2(2.2, 4.5)
	var bottle := Node3D.new()
	bottle.name = "Bottle"
	current_scene.add_child(bottle)
	events.item_broken.emit(bottle)
	events.drink_ordered.emit(player)
	events.police_called.emit()

	# Ledge throws and falls (signals come from the combat PR; call the handlers if absent).
	var faller := Node3D.new()
	current_scene.add_child(faller)
	faller.global_position = player.global_position + Vector3(1.5, 0, 0)
	var marks_before: int = fx.blood.decal_count()
	if events.has_signal("fighter_fell"):
		events.emit_signal("fighter_thrown_off_ledge", faller, player, true)
		events.emit_signal("fighter_fell", faller, 3.0)
	else:
		fx._on_thrown_off_ledge(faller, player, true)
		fx._on_fell(faller, 3.0)
	_check(fx.blood.decal_count() > marks_before, "no landing blood after a fall")
	_check(faller.get_node_or_null("FxFaceBlood") != null, "no face blood after a fall")

	# Clean connects throw blood and droplets; blocked and parried hits don't bleed at all.
	var target := Node3D.new()
	target.name = "N2"
	current_scene.add_child(target)
	target.global_position = player.global_position + Vector3(-1.5, 0, -1.0)
	_check(fx.is_clean_hit({"move": "uppercut", "to_face": true}), "uppercut to the face not clean")
	_check(fx.is_clean_hit({"move": "jab", "to_face": true, "clean": true}), "clean flag ignored")
	_check(not fx.is_clean_hit({"move": "jab", "to_face": true}), "plain jab counted as clean")
	var particles_before := _count_particles()
	var marks_clean: int = fx.blood.decal_count()
	events.hit_landed.emit({"attacker": player, "victim": target, "move": "counter", "damage": 12.0,
		"position": target.global_position + Vector3.UP * 1.5, "direction": Vector3.LEFT,
		"heavy": true, "to_face": true, "clean": true})
	_check(_count_particles() >= particles_before + 50, "clean hit didn't spray fine droplets")
	var drops: Node = fx.blood.droplets()
	var landed_before: int = drops.marks_left()
	await create_timer(1.5).timeout
	_check(fx.blood.decal_count() > marks_clean + 20, "clean hit left no fine splats")
	# The blood flew with the punch (LEFT = -x), not straight down or at random.
	var landed: PackedVector3Array = drops.recent_landings(drops.marks_left() - landed_before)
	var mean_x := 0.0
	for at in landed:
		mean_x += at.x
	mean_x /= maxf(landed.size(), 1)
	_check(landed.size() > 20 and mean_x < target.global_position.x - 0.3,
		"blood didn't follow the punch (%d landed, mean x %.2f vs head %.2f)" % [landed.size(), mean_x, target.global_position.x])
	var blocker := Node3D.new()
	current_scene.add_child(blocker)
	var p_before := _count_particles()
	events.hit_landed.emit({"attacker": player, "victim": blocker, "move": "hook", "damage": 2.0,
		"direction": Vector3.LEFT, "heavy": true, "to_face": true, "blocked": true})
	events.hit_landed.emit({"attacker": player, "victim": blocker, "move": "hook", "damage": 0.0,
		"direction": Vector3.LEFT, "to_face": true, "parried": true})
	_check(_count_particles() == p_before, "blocked or parried hit drew blood")
	_check(blocker.get_node_or_null("FxFaceBlood") == null, "blocked hit bloodied the face")
	_check(fx.bark(player, "taunt", 3, true), "player couldn't bark a taunt")
	target.set_meta("voice_id", "posh_m1")
	_check(not fx.bark(target, "hurt", 1), "two spoken lines back to back (barks should be occasional)")

	# 3. Blood off means no new blood.
	settings.values["gameplay"]["blood"] = 0
	var before: int = fx.blood.decal_count()
	var clean := Node3D.new()
	current_scene.add_child(clean)
	events.nose_broken.emit(clean)
	await create_timer(1.0).timeout
	_check(fx.blood.decal_count() == before, "blood spawned with blood setting off")
	_check(clean.get_node_or_null("FxFaceBlood") == null, "face blood with blood setting off")

	# 4. Freed fighters don't break anything.
	dummy.queue_free()
	await create_timer(0.3).timeout
	events.hit_landed.emit({"attacker": null, "victim": null, "move": "kick"})

	await process_frame
	if _failed:
		quit(1)
		return
	print("FX OK: %d cues, %d sound files, %d bark lines, %d blood decals" % [SoundBank.CUES.size(),
		files, bark_files, fx.blood.decal_count()])
	quit(0)


## Blood droplets thrown so far.
func _count_particles() -> int:
	var fx: Node = root.get_node("Fx")
	return fx.blood.droplets().drops_thrown()


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failed = true
		push_error("FX FAIL: " + msg)
