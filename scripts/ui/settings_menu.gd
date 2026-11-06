class_name SettingsMenu
extends Control
## Settings screen: Gameplay, Sound, Graphics and Keybinds tabs.
## Controls are built from Settings.OPTIONS, so a new setting only needs adding there.
## Keybinds has separate keyboard/mouse and controller columns. Click a binding, then press
## the new key or button. Esc (or clicking elsewhere) cancels. Taken bindings swap.
## Opened from the main menu and the pause menu; emits `closed` when the player backs out.

signal closed()

const TABS := [["gameplay", "Gameplay"], ["sound", "Sound"], ["graphics", "Graphics"], ["talk", "Talk"],
	["keybinds", "Keybinds"]]

var _tabs: TabContainer
var _status: Label
## section -> key -> control, so values can be refreshed after a reset.
var _controls := {}
## action -> device -> Button
var _bind_buttons := {}
var _listening_action := ""
var _listening_device := ""
var _listen_armed := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UiTheme.dimmer())

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = 60
	panel.offset_bottom = -60
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiTheme.label("Settings", "HeaderLabel"))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	for t in TABS:
		var page: Control = _build_keybinds() if t[0] == "keybinds" else _build_section(t[0])
		page.name = t[1]
		_tabs.add_child(page)

	_status = UiTheme.label("", "HintLabel")
	col.add_child(_status)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(UiTheme.button("Reset this tab", _on_reset_tab))
	var back := UiTheme.button("Back", close)
	back.custom_minimum_size.x = 160
	row.add_child(back)

	Settings.changed.connect(_on_settings_changed)
	_tabs.get_tab_bar().grab_focus.call_deferred()


func close() -> void:
	_stop_listening()
	closed.emit()
	queue_free()


# --- Gameplay / Sound / Graphics ---------------------------------------------

func _build_section(section: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	_controls[section] = {}
	if section == "talk":
		# What's installed: the speech tools ship in the speech folder next to the game.
		var status := UiTheme.label(SpeechTools.status(), "HintLabel")
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(status)
		grid.add_child(Control.new())
	for key in Settings.OPTIONS[section]:
		var opt: Dictionary = Settings.OPTIONS[section][key]
		var name_box := VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(UiTheme.label(opt["label"]))
		if opt.has("hint"):
			var hint := UiTheme.label(opt["hint"], "HintLabel")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_box.add_child(hint)
		grid.add_child(name_box)
		var ctl := _make_control(section, key, opt)
		ctl.custom_minimum_size.x = 340
		ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(ctl)
		_controls[section][key] = ctl
	return scroll


func _make_control(section: String, key: String, opt: Dictionary) -> Control:
	var value: Variant = Settings.get_value(section, key)
	match opt["type"]:
		"text":
			var le := LineEdit.new()
			le.secret = bool(opt.get("secret", false))
			le.placeholder_text = String(opt.get("placeholder", ""))
			le.text = String(value)
			le.clear_button_enabled = true
			le.text_changed.connect(func(t: String): Settings.set_value(section, key, t.strip_edges()))
			return le
		"toggle":
			var cb := CheckButton.new()
			cb.button_pressed = bool(value)
			cb.text = "On" if value else "Off"
			cb.toggled.connect(func(on: bool):
				cb.text = "On" if on else "Off"
				Settings.set_value(section, key, on))
			return cb
		"choice":
			var ob := OptionButton.new()
			for item in _choice_items(section, key, opt):
				ob.add_item(item)
			ob.select(_choice_index(section, key, value))
			ob.item_selected.connect(func(i: int):
				var vals := _choice_values(section, key)
				Settings.set_value(section, key, vals[i] if not vals.is_empty() else i))
			return ob
		_:
			var row := HBoxContainer.new()
			var slider := HSlider.new()
			slider.min_value = opt["min"]
			slider.max_value = opt["max"]
			slider.step = opt["step"]
			slider.value = float(value)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var readout := UiTheme.label(_format(opt, float(value)))
			readout.custom_minimum_size.x = 70
			readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(func(v: float):
				readout.text = _format(opt, v)
				Settings.set_value(section, key, v))
			row.add_child(slider)
			row.add_child(readout)
			return row


func _choice_items(section: String, key: String, opt: Dictionary) -> Array:
	if section == "gameplay" and key == "difficulty":
		return GameData.DIFFICULTIES.map(func(d): return d["name"])
	if section == "graphics" and key == "resolution":
		return Settings.resolution_choices().map(func(r): return Settings.resolution_label(r))
	if section == "talk" and key == "mic_device":
		return _mic_devices()
	return opt["items"]


func _mic_devices() -> Array:
	var out: Array = ["Default"]
	for d in AudioServer.get_input_device_list():
		if not out.has(d):
			out.append(d)
	var current := String(Settings.get_value("talk", "mic_device"))
	if not out.has(current):
		out.append(current)
	return out


## The stored values behind a choice's items, or [] when the stored value is the item index.
func _choice_values(section: String, key: String) -> Array:
	if section == "graphics" and key == "resolution":
		return Settings.resolution_choices()
	if section == "talk" and key == "mic_device":
		return _mic_devices()
	return Settings.OPTIONS[section][key].get("values", [])


func _choice_index(section: String, key: String, value: Variant) -> int:
	var vals := _choice_values(section, key)
	if vals.is_empty():
		return int(value)
	for i in vals.size():
		if typeof(vals[i]) == typeof(value) and vals[i] == value:
			return i
		if vals[i] is int and (value is int or value is float) and vals[i] == int(value):
			return i
	return 0


func _format(opt: Dictionary, v: float) -> String:
	if opt.get("percent", false):
		return "%d%%" % roundi(v * 100.0)
	return "%d%s" % [roundi(v), opt.get("suffix", "")] if opt.has("suffix") else str(v)


func _refresh_section(section: String) -> void:
	for key in _controls.get(section, {}):
		var ctl: Control = _controls[section][key]
		var opt: Dictionary = Settings.OPTIONS[section][key]
		var value: Variant = Settings.get_value(section, key)
		if ctl is CheckButton:
			ctl.set_pressed_no_signal(bool(value))
			ctl.text = "On" if value else "Off"
		elif ctl is OptionButton:
			ctl.select(_choice_index(section, key, value))
		elif ctl is LineEdit:
			if ctl.text != String(value):
				ctl.text = String(value)
		else:
			var slider: HSlider = ctl.get_child(0)
			slider.set_value_no_signal(float(value))
			ctl.get_child(1).text = _format(opt, float(value))


# --- Keybinds ----------------------------------------------------------------

func _build_keybinds() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for header in ["Action", "Keyboard & mouse", "Controller"]:
		grid.add_child(UiTheme.label(header, "HeaderLabel"))
	for action in Settings.ACTIONS:
		var name_label := UiTheme.label(Settings.ACTIONS[action][0])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		_bind_buttons[action] = {}
		for device in Settings.DEVICES:
			var b := UiTheme.button("", _start_listening.bind(action, device), 40)
			b.custom_minimum_size.x = 260
			b.name = "%s_%s" % [action, device]
			grid.add_child(b)
			_bind_buttons[action][device] = b
	_refresh_binds()
	return scroll


func _refresh_binds() -> void:
	for action in _bind_buttons:
		for device in _bind_buttons[action]:
			_bind_buttons[action][device].text = Settings.action_label(action, device)


func _start_listening(action: String, device: String) -> void:
	_stop_listening()
	_listening_action = action
	_listening_device = device
	_listen_armed = false
	_bind_buttons[action][device].text = "Press a key or mouse button…" if device == "kb" \
		else "Press a button or move a stick…"
	_status.text = "Esc to cancel."
	# Arm on the next frame so the click or button press that opened this isn't captured.
	await get_tree().process_frame
	_listen_armed = _listening_action == action and _listening_device == device


func _stop_listening() -> void:
	if _listening_action != "":
		_listening_action = ""
		_listen_armed = false
		_refresh_binds()


func _input(event: InputEvent) -> void:
	if _listening_action == "":
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
		return
	if not _listen_armed:
		return
	var is_escape: bool = event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE
	# Esc cancels, except that Pause may be bound to Esc on keyboard.
	if is_escape and not (_listening_action == "pause" and _listening_device == "kb"):
		get_viewport().set_input_as_handled()
		_status.text = ""
		_stop_listening()
		return
	var binding := Settings.binding_from_event(event, _listening_device)
	if binding.is_empty():
		# A mouse click while waiting for a controller button cancels.
		if event is InputEventMouseButton and event.pressed:
			_stop_listening()
			_status.text = ""
		return
	get_viewport().set_input_as_handled()
	var action := _listening_action
	_listening_action = ""
	_listen_armed = false
	var swapped := Settings.set_bind(action, _listening_device, binding)
	_status.text = "" if swapped == "" else "%s was already on %s, so they swapped." % [
		Settings.ACTIONS[swapped][0], Settings.binding_label(binding)]
	_refresh_binds()
	_bind_buttons[action][_listening_device].grab_focus()


func _on_reset_tab() -> void:
	_stop_listening()
	var section: String = TABS[_tabs.current_tab][0]
	if section == "keybinds":
		Settings.reset_binds()
	else:
		Settings.reset_section(section)
	_status.text = "%s reset to defaults." % TABS[_tabs.current_tab][1]


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "keybinds":
		if _listening_action == "":
			_refresh_binds()
	else:
		_refresh_section(section)
