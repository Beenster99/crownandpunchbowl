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
	var punch_kb: Dictionary = settings.binds["punch_left"]["kb"].duplicate()
	var swapped: String = settings.set_bind("punch_right", "kb", punch_kb)
	_check(swapped == "punch_left", "binding right punch to left punch's button should swap them")
	_check(settings.binding_equals(settings.binds["punch_right"]["kb"], punch_kb), "right punch takes the new binding")
	_check(settings.binds["punch_left"]["kb"].has("mouse") and settings.binds["punch_left"]["kb"]["mouse"] == MOUSE_BUTTON_RIGHT,
		"left punch gets right punch's old binding")
	settings.reset_binds("kb")
	_check(settings.binds["punch_right"]["kb"]["mouse"] == MOUSE_BUTTON_RIGHT, "reset keyboard binds")

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
	_check(settings.action_label("punch_left", "kb") == "Left mouse", "punch label")
	_check(settings.action_label("block", "pad") == "LB", "block pad label")
	_check(settings.action_label("move_up", "pad") == "Left stick up", "stick label")
	for action in settings.ACTIONS:
		_check(InputMap.has_action(action), "input action exists: " + action)
		_check(InputMap.action_get_events(action).size() == 2, "kb + pad events: " + action)

	# Values, difficulty and section reset.
	settings.set_value("gameplay", "difficulty", 3)
	_check(root.get_node("GameData").difficulty_index == 3, "difficulty setting drives GameData")
	settings.set_value("sound", "music", 0.2)
	settings.reset_section("sound")
	_check(is_equal_approx(settings.get_value("sound", "music"), 0.6), "reset sound section")
	settings.reset_section("gameplay")

	# Main menu builds, settings opens with all four tabs.
	change_scene_to_file("res://scenes/main/main_menu.tscn")
	await process_frame
	await process_frame
	var menu := current_scene
	var s: Control = menu.open_settings()
	await process_frame
	var tabs := s.find_children("*", "TabContainer", true, false)
	_check(tabs.size() == 1 and tabs[0].get_tab_count() == 4, "settings has 4 tabs")
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

	if _failed:
		quit(1)
	else:
		print("UI OK")
		quit(0)
