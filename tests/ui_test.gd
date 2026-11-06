extends SceneTree
## Headless UI test: settings storage and rebinding, menu screens, pause menu and HUD.
## Run: godot --headless --path . --script res://tests/ui_test.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		push_error("FAIL: " + what)


func _initialize() -> void:
	await process_frame
	var settings := root.get_node("Settings")
	var events := root.get_node("Events")

	# Rebinding swaps a clash rather than leaving an action unbound.
	settings.reset_binds()
	var punch_kb: Dictionary = settings.binds["jab"]["kb"].duplicate()
	var swapped: String = settings.set_bind("hook", "kb", punch_kb)
	_check(swapped == "jab", "binding hook to jab's button should swap them")
	_check(settings.binding_equals(settings.binds["hook"]["kb"], punch_kb), "right punch takes the new binding")
	_check(settings.binds["jab"]["kb"].has("mouse") and settings.binds["jab"]["kb"]["mouse"] == MOUSE_BUTTON_RIGHT,
		"left punch gets right punch's old binding")
	settings.reset_binds("kb")
	_check(settings.binds["hook"]["kb"]["mouse"] == MOUSE_BUTTON_RIGHT, "reset keyboard binds")

	# Event conversion respects the device column.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	_check(settings.binding_from_event(key, "kb") == {"key": KEY_G}, "key event -> kb binding")
	_check(settings.binding_from_event(key, "pad").is_empty(), "key event ignored for controller")
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_TRIGGER_LEFT
	axis.axis_value = 0.9
	_check(settings.binding_from_event(axis, "pad") == {"axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1}, "trigger -> pad")
	_check(settings.action_label("jab", "kb") == "Left mouse", "punch label")
	_check(settings.action_label("guard_head", "pad") == "LB", "head guard pad label")
	_check(settings.action_label("move_up", "pad") == "Left stick up", "stick label")
	for action in settings.ACTIONS:
		_check(InputMap.has_action(action), "input action exists: " + action)
		# Typing a line is keyboard only: a pad has nothing to type with.
		var want := 1 if action == "say_line" else 2
		_check(InputMap.action_get_events(action).size() == want, "kb + pad events: " + action)

	# Values, difficulty and section reset.
	settings.set_value("gameplay", "difficulty", 3)
	_check(root.get_node("GameData").difficulty_index == 3, "difficulty setting drives GameData")
	settings.set_value("sound", "music", 0.2)
	settings.reset_section("sound")
	_check(is_equal_approx(settings.get_value("sound", "music"), 0.6), "reset sound section")
	settings.reset_section("gameplay")

	# Device detection drives prompts.
	settings.set_device("kb")
	var got_device := [""]
	settings.device_changed.connect(func(d): got_device[0] = d)
	var pad_press := InputEventJoypadButton.new()
	pad_press.button_index = JOY_BUTTON_A
	pad_press.pressed = true
	settings._input(pad_press)
	_check(settings.device == "pad" and got_device[0] == "pad", "pad press switches device")
	_check(settings.prompt("dodge") == "A", "pad prompt for dodge")
	var prompt = load("res://scripts/ui/button_prompt.gd").make("dodge", "Dodge")  # loaded late: needs autoloads
	root.add_child(prompt)
	_check(prompt._cap_label.text == "A", "ButtonPrompt shows pad label")
	settings._input(key)
	_check(settings.device == "kb", "key press switches back")
	_check(prompt._cap_label.text == "Space", "ButtonPrompt follows device")
	prompt.queue_free()

	# Zoom actions exist and don't clash with throw on the pad.
	_check(InputMap.has_action("zoom_in") and InputMap.has_action("zoom_out"), "zoom actions")
	_check(not settings.binding_equals(settings.binds["throw"]["pad"], settings.binds["zoom_in"]["pad"]),
		"throw and zoom in differ on pad")
	var cam = load("res://scripts/level/brawl_camera.gd").new()
	root.add_child(cam)
	_check(is_equal_approx(cam.zoom, clampf(settings.get_value("profile", "camera_zoom"), cam.min_zoom, cam.max_zoom)),
		"camera starts at the saved zoom")
	var z0: float = cam.zoom
	var plus := InputEventKey.new()
	plus.physical_keycode = KEY_EQUAL
	plus.pressed = true
	cam._input(plus)
	_check(cam.zoom < z0, "+ key zooms in")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	cam._input(wheel)
	cam._input(wheel)
	_check(cam.zoom > z0, "mouse wheel zooms out")
	_check(load("res://scripts/level/brawl_camera.gd").DEFAULT_ZOOM < 1.0, "default view is zoomed in")
	cam.zoom = z0
	cam.queue_free()
	# Friendly fire is a gameplay setting; solo counts as host, so it applies straight away.
	settings.set_value("gameplay", "friendly_fire", true)
	_check(root.get_node("GameData").friendly_fire, "friendly fire setting reaches GameData")
	settings.set_value("gameplay", "friendly_fire", false)
	_check(not root.get_node("GameData").friendly_fire, "friendly fire off")

	# Graphics presets set the detail options; touching one detail flips to Custom.
	settings.set_value("graphics", "quality", 0)
	_check(settings.get_value("graphics", "shadow_quality") == 0 and not settings.get_value("graphics", "bloom"),
		"low preset applied")
	_check(settings.get_value("graphics", "quality") == 0, "preset stays Low after applying")
	settings.set_value("graphics", "bloom", true)
	_check(settings.get_value("graphics", "quality") == settings.CUSTOM_QUALITY, "detail change -> Custom")
	settings.set_value("graphics", "quality", 2)
	_check(settings.get_value("graphics", "ambient_occlusion") == true, "high preset applied")
	_check(settings.resolution_choices()[0] == "auto", "resolution choices start with native")
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.fog_enabled = true
	root.add_child(we)
	await process_frame
	settings.set_value("graphics", "fog", false)
	_check(not we.environment.fog_enabled, "fog setting reaches live environments")
	settings.set_value("graphics", "fog", true)
	_check(we.environment.fog_enabled, "fog restored")
	we.queue_free()
	settings.reset_section("graphics")

	# Main menu builds, settings opens with all five tabs.
	change_scene_to_file("res://scenes/main/main_menu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	var s: Control = menu.open_settings()
	await process_frame
	var tabs := s.find_children("*", "TabContainer", true, false)
	_check(tabs.size() == 1 and tabs[0].get_tab_count() == 5, "settings has 5 tabs (with Talk)")
	_check(s.find_children("pause_pad", "Button", true, false).size() == 1, "keybind button per device")
	s.close()
	_check(menu.find_children("*", "FarmerCard", true, false).size() == 6, "six farmer cards")
	print(menu.difficulty_summary(root.get_node("GameData").DIFFICULTIES[0]))

	# Start solo from the menu, then check HUD and pause.
	menu._on_start()
	await create_timer(0.5).timeout
	var ui := current_scene.find_children("*", "GameUi", true, false)
	_check(ui.size() == 1, "pub has GameUi")
	if ui.size() == 1:
		var hud = ui[0].hud
		_check(hud._panels.size() == 1, "one player panel")
		events.banner.emit("Test banner", 0.5)
		_check(hud._banner.text == "Test banner", "banner shows")
		ui[0].pause_menu.open()
		_check(paused, "solo pause freezes the tree")
		ui[0].pause_menu.resume()
		_check(not paused, "resume unfreezes")
		# Restart this pub: a fresh pub with the player spawned again, not an empty room.
		var old_scene := current_scene
		ui[0].pause_menu.open()
		_check(not ui[0].pause_menu._restart.disabled, "solo player can restart")
		ui[0].pause_menu._on_restart()
		var restarted := false
		for i in 600:
			await process_frame
			if current_scene != null and current_scene != old_scene \
					and current_scene.find_children("*", "PlayerFighter", true, false).size() == 1:
				restarted = true
				break
		_check(restarted, "restart reloads the pub with the player in it")
		_check(not paused, "restart leaves the game unpaused")

	if _failed:
		quit(1)
	else:
		print("UI OK")
		quit(0)
