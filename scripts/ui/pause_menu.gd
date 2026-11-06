class_name PauseMenu
extends CanvasLayer
## In-game pause menu: Resume, Settings, Restart pub, Quit to main menu.
## Only freezes the game when no one else is connected. In online co-op the fight carries on
## behind the menu (like most co-op games), so a paused player can still be hit.

signal opened()
signal resumed()

var _root: Control
var _settings: SettingsMenu
var _restart: Button
var _resume: Button


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	_root.add_child(UiTheme.dimmer(0.6))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 380
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiTheme.label("Paused", "HeaderLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var pub := UiTheme.label("%s · %s" % [GameData.current_pub()["name"], GameData.difficulty()["name"]], "HintLabel")
	pub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(pub)
	_resume = UiTheme.button("Resume", resume)
	box.add_child(_resume)
	box.add_child(UiTheme.button("Settings", _open_settings))
	_restart = UiTheme.button("Restart this pub", _on_restart)
	box.add_child(_restart)
	box.add_child(UiTheme.button("Quit to main menu", _on_quit))


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if is_open():
		return
	_root.visible = true
	# The host (or a solo player) restarts the pub for everyone through Net.
	_restart.disabled = not Net.is_host()
	_restart.text = "Restart this pub" if Net.is_host() else "Restart this pub (host only)"
	if _is_alone():
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()
	opened.emit()


func resume() -> void:
	if not is_open():
		return
	if is_instance_valid(_settings):
		_settings.close()
	_root.visible = false
	get_tree().paused = false
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_settings):
			_settings.close()
		elif is_open():
			resume()
		else:
			open()
	elif is_open() and event.is_action_pressed("ui_cancel") and not is_instance_valid(_settings):
		get_viewport().set_input_as_handled()
		resume()


func _is_alone() -> bool:
	return multiplayer.get_peers().is_empty()


func _open_settings() -> void:
	var focus := _root.get_viewport().gui_get_focus_owner()
	_settings = SettingsMenu.new()
	_settings.closed.connect(func():
		if is_instance_valid(focus):
			focus.grab_focus())
	_root.add_child(_settings)


## Goes through Net rather than reloading the scene here: a plain reload left Net thinking the
## pub was already loaded, so nobody was spawned and the pub came back empty.
func _on_restart() -> void:
	if not Net.is_host():
		return
	_root.visible = false
	get_tree().paused = false
	Net.restart_pub()


func _on_quit() -> void:
	get_tree().paused = false
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
