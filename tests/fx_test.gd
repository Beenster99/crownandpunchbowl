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
	await create_timer(1.2, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "hit-stop never released (time_scale %s)" % Engine.time_scale)
	_check(dummy.get_node_or_null("FxFaceBlood") != null, "no bloody face decal")
	_check(fx.blood.decal_count() > 0, "no floor blood decals")
	var speaking := 0
	for p in fx.get_children():
		if p is AudioStreamPlayer3D and p.playing:
			speaking += 1
	_check(speaking > 0, "nothing is playing")

	events.fighter_knocked_out.emit(dummy)
	_check(not fx.is_crawling(dummy), "KO'd fighter still crawling")
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
	print("FX OK: %d cues, %d sound files, %d blood decals" % [SoundBank.CUES.size(), files, fx.blood.decal_count()])
	quit(0)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failed = true
		push_error("FX FAIL: " + msg)
