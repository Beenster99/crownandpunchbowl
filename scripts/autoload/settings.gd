extends Node
## Player settings: Gameplay, Sound, Graphics and Keybinds, saved to user://settings.cfg.
## The menus workstream builds the UI on top of this; other systems read values via
## Settings.get_value() and listen to `changed`.
##
## Input action names below are a contract: gameplay code must only use these names.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"gameplay": {"difficulty": 1, "camera_shake": 1.0, "blood": 1, "counter_prompts": true, "subtitles": true},
	"sound": {"master": 0.9, "music": 0.6, "sfx": 1.0, "voice": 1.0},
	"graphics": {"window_mode": 0, "vsync": true, "max_fps": 0, "render_scale": 1.0, "shadows": true},
}

## Audio buses every sound must route through (created at startup if missing).
const BUSES := ["Music", "SFX", "Voice"]

## action -> [label, keyboard/mouse default, controller default]
## Binding format: {"key": KEY_*} | {"mouse": MOUSE_BUTTON_*} | {"joy": JOY_BUTTON_*} | {"axis": JOY_AXIS_*, "dir": ±1}
const ACTIONS := {
	"move_up": ["Move up", {"key": KEY_W}, {"axis": JOY_AXIS_LEFT_Y, "dir": -1}],
	"move_down": ["Move down", {"key": KEY_S}, {"axis": JOY_AXIS_LEFT_Y, "dir": 1}],
	"move_left": ["Move left", {"key": KEY_A}, {"axis": JOY_AXIS_LEFT_X, "dir": -1}],
	"move_right": ["Move right", {"key": KEY_D}, {"axis": JOY_AXIS_LEFT_X, "dir": 1}],
	"punch": ["Punch", {"mouse": MOUSE_BUTTON_LEFT}, {"joy": JOY_BUTTON_X}],
	"kick": ["Kick", {"mouse": MOUSE_BUTTON_RIGHT}, {"joy": JOY_BUTTON_B}],
	"headbutt": ["Headbutt", {"key": KEY_Q}, {"joy": JOY_BUTTON_Y}],
	"counter": ["Counter", {"key": KEY_F}, {"joy": JOY_BUTTON_RIGHT_SHOULDER}],
	"grab": ["Grab / hold", {"key": KEY_R}, {"joy": JOY_BUTTON_LEFT_SHOULDER}],
	"dodge": ["Dodge", {"key": KEY_SPACE}, {"joy": JOY_BUTTON_A}],
	"interact": ["Pick up / order drink", {"key": KEY_E}, {"axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1}],
	"order_food": ["Order food", {"key": KEY_C}, {"axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1}],
	"throw": ["Throw held item", {"key": KEY_T}, {"joy": JOY_BUTTON_DPAD_UP}],
	"pause": ["Pause", {"key": KEY_ESCAPE}, {"joy": JOY_BUTTON_START}],
}

var values := {}
## action -> {"kb": binding, "pad": binding}
var binds := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	apply_all()


func get_value(section: String, key: String) -> Variant:
	return values[section][key]


func set_value(section: String, key: String, value: Variant) -> void:
	values[section][key] = value
	_apply(section, key)
	save_settings()
	changed.emit(section, key)


func set_bind(action: String, device: String, binding: Dictionary) -> void:
	binds[action][device] = binding
	_apply_binds()
	save_settings()
	changed.emit("keybinds", action)


func reset_binds() -> void:
	_default_binds()
	_apply_binds()
	save_settings()
	changed.emit("keybinds", "")


func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	_default_binds()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in values:
		for key in values[section]:
			values[section][key] = cfg.get_value(section, key, values[section][key])
	for action in binds:
		for device in ["kb", "pad"]:
			var b: Variant = cfg.get_value("keybinds", "%s.%s" % [action, device], null)
			if b is Dictionary:
				binds[action][device] = b


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in values:
		for key in values[section]:
			cfg.set_value(section, key, values[section][key])
	for action in binds:
		for device in binds[action]:
			cfg.set_value("keybinds", "%s.%s" % [action, device], binds[action][device])
	cfg.save(PATH)


func apply_all() -> void:
	for section in values:
		for key in values[section]:
			_apply(section, key)
	_apply_binds()


func make_event(binding: Dictionary) -> InputEvent:
	if binding.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = binding["key"]
		return k
	if binding.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = binding["mouse"]
		return m
	if binding.has("joy"):
		var j := InputEventJoypadButton.new()
		j.button_index = binding["joy"]
		j.device = -1
		return j
	if binding.has("axis"):
		var a := InputEventJoypadMotion.new()
		a.axis = binding["axis"]
		a.axis_value = float(binding["dir"])
		a.device = -1
		return a
	return null


func _default_binds() -> void:
	binds.clear()
	for action in ACTIONS:
		binds[action] = {"kb": ACTIONS[action][1].duplicate(), "pad": ACTIONS[action][2].duplicate()}


func _apply_binds() -> void:
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		InputMap.action_erase_events(action)
		for device in binds[action]:
			var ev := make_event(binds[action][device])
			if ev:
				InputMap.action_add_event(action, ev)


func _ensure_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _apply(section: String, key: String) -> void:
	var v: Variant = values[section][key]
	match [section, key]:
		["sound", _]:
			var bus := AudioServer.get_bus_index("Master" if key == "master" else key.capitalize())
			if bus != -1:
				AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(float(v), 0.0001)))
		["graphics", "window_mode"]:
			var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			DisplayServer.window_set_mode(modes[clampi(int(v), 0, 2)])
		["graphics", "vsync"]:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		["graphics", "max_fps"]:
			Engine.max_fps = int(v)
		["graphics", "render_scale"]:
			get_tree().root.scaling_3d_scale = float(v)
		["gameplay", "difficulty"]:
			GameData.difficulty_index = int(v)
		# graphics/shadows, gameplay/blood etc. are read by the systems that use them.
