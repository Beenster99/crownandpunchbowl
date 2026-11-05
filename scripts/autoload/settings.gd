extends Node
## Player settings: Gameplay, Sound, Graphics and Keybinds, saved to user://settings.cfg.
## The settings screen (scripts/ui/settings_menu.gd) builds its controls from DEFAULTS and
## OPTIONS. Other systems read values via Settings.get_value() and listen to `changed`.
## Keys are stable: add new ones rather than renaming.
##
## Input action names below are a contract: gameplay code must only use these names.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"gameplay": {"difficulty": 1, "camera_shake": 1.0, "blood": 1, "counter_prompts": true,
		"subtitles": true, "context_prompts": true, "vibration": true},
	"sound": {"master": 0.9, "music": 0.6, "sfx": 1.0, "voice": 1.0, "mute_unfocused": false},
	"graphics": {"window_mode": 0, "vsync": true, "max_fps": 0, "render_scale": 1.0, "shadows": true,
		"msaa": 1, "ui_scale": 1.0},
	## Remembered front-end choices, not shown on the settings screen.
	"profile": {"name": "Farmer", "farmer": 0, "pub": 0},
}

## How each setting is shown on the settings screen. Keys missing here are not shown.
## {"label", "type": "slider"|"toggle"|"choice", "min", "max", "step", "percent", "items", "hint"}
const OPTIONS := {
	"gameplay": {
		"difficulty": {"label": "Default difficulty", "type": "choice", "items": [],
			"hint": "Used when you host or play solo. The host's choice applies in co-op."},
		"camera_shake": {"label": "Camera shake", "type": "slider", "min": 0.0, "max": 1.5,
			"step": 0.05, "percent": true},
		"blood": {"label": "Blood", "type": "choice", "items": ["Off", "Normal", "Buckets"]},
		"counter_prompts": {"label": "Counter prompts", "type": "toggle",
			"hint": "Show a marker over punters about to swing at you."},
		"context_prompts": {"label": "Button prompts", "type": "toggle",
			"hint": "Show prompts like \"E: Order pint\" near the bar and items."},
		"subtitles": {"label": "Subtitles for shouts", "type": "toggle"},
		"vibration": {"label": "Controller vibration", "type": "toggle"},
	},
	"sound": {
		"master": {"label": "Master volume", "type": "slider", "min": 0.0, "max": 1.0, "step": 0.01, "percent": true},
		"music": {"label": "Music", "type": "slider", "min": 0.0, "max": 1.0, "step": 0.01, "percent": true},
		"sfx": {"label": "Effects (punches, glass, furniture)", "type": "slider", "min": 0.0, "max": 1.0,
			"step": 0.01, "percent": true},
		"voice": {"label": "Voices (oofs, groans, shouting)", "type": "slider", "min": 0.0, "max": 1.0,
			"step": 0.01, "percent": true},
		"mute_unfocused": {"label": "Mute when the window loses focus", "type": "toggle"},
	},
	"graphics": {
		"window_mode": {"label": "Window mode", "type": "choice",
			"items": ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]},
		"vsync": {"label": "V-Sync", "type": "toggle"},
		"max_fps": {"label": "Frame rate cap", "type": "choice", "items": ["Unlimited", "30", "60", "120", "144", "240"],
			"values": [0, 30, 60, 120, 144, 240]},
		"render_scale": {"label": "3D render scale", "type": "slider", "min": 0.5, "max": 1.0, "step": 0.05,
			"percent": true, "hint": "Lower it if the game runs slowly. Menus stay sharp."},
		"msaa": {"label": "Anti-aliasing", "type": "choice", "items": ["Off", "2x MSAA", "4x MSAA", "8x MSAA"]},
		"shadows": {"label": "Shadows", "type": "toggle"},
		"ui_scale": {"label": "Interface size", "type": "slider", "min": 0.75, "max": 1.5, "step": 0.05,
			"percent": true},
	},
}

const DEVICES := ["kb", "pad"]

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
var _save_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	apply_all()


func get_value(section: String, key: String) -> Variant:
	return values[section][key]


func set_value(section: String, key: String, value: Variant) -> void:
	if values[section][key] == value:
		return
	values[section][key] = value
	_apply(section, key)
	_queue_save()
	changed.emit(section, key)


## Restores one section ("gameplay", "sound", "graphics") to its defaults.
func reset_section(section: String) -> void:
	for key in DEFAULTS[section]:
		set_value(section, key, DEFAULTS[section][key])


## Binds `binding` to `action` on `device` ("kb" or "pad"). If another action already uses
## that binding on the same device, the two swap, so nothing is left unbound.
## Returns the name of the action that was swapped, or "".
func set_bind(action: String, device: String, binding: Dictionary) -> String:
	var swapped := ""
	var old: Dictionary = binds[action][device]
	for other in binds:
		if other != action and binding_equals(binds[other][device], binding):
			binds[other][device] = old.duplicate()
			swapped = other
	binds[action][device] = binding.duplicate()
	_apply_binds()
	_queue_save()
	changed.emit("keybinds", action)
	return swapped


func reset_binds(device := "") -> void:
	for action in ACTIONS:
		if device == "" or device == "kb":
			binds[action]["kb"] = ACTIONS[action][1].duplicate()
		if device == "" or device == "pad":
			binds[action]["pad"] = ACTIONS[action][2].duplicate()
	_apply_binds()
	_queue_save()
	changed.emit("keybinds", "")


func binding_equals(a: Dictionary, b: Dictionary) -> bool:
	for k in ["key", "mouse", "joy", "axis", "dir"]:
		if a.has(k) != b.has(k) or (a.has(k) and int(a[k]) != int(b[k])):
			return false
	return true


## Turns a raw input event into a binding for `device`, or {} if it doesn't belong there.
## Keyboard/mouse accepts keys and mouse buttons; controller accepts buttons and axes pushed
## past half way.
func binding_from_event(event: InputEvent, device: String) -> Dictionary:
	if device == "kb":
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			return {"key": code} if code != KEY_NONE else {}
		if event is InputEventMouseButton and event.pressed:
			return {"mouse": event.button_index}
	elif device == "pad":
		if event is InputEventJoypadButton and event.pressed:
			return {"joy": event.button_index}
		if event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
			return {"axis": event.axis, "dir": 1 if event.axis_value > 0.0 else -1}
	return {}


## Short text for a binding, e.g. "E", "Left mouse", "RB", "Left stick up".
func binding_label(binding: Dictionary) -> String:
	if binding.has("key"):
		var code: int = binding["key"]
		# Show the key for the player's layout (e.g. AZERTY) where the display server knows it.
		var mapped: int = KEY_NONE if DisplayServer.get_name() == "headless" \
			else DisplayServer.keyboard_get_keycode_from_physical(code)
		var text := OS.get_keycode_string(mapped if mapped != KEY_NONE else code)
		return text if text != "" else "Key %d" % code
	if binding.has("mouse"):
		var mouse_names := {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse",
			MOUSE_BUTTON_MIDDLE: "Middle mouse", MOUSE_BUTTON_WHEEL_UP: "Wheel up",
			MOUSE_BUTTON_WHEEL_DOWN: "Wheel down", MOUSE_BUTTON_XBUTTON1: "Mouse 4",
			MOUSE_BUTTON_XBUTTON2: "Mouse 5"}
		return mouse_names.get(binding["mouse"], "Mouse %d" % binding["mouse"])
	if binding.has("joy"):
		var joy_names := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Back",
			JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_LEFT_STICK: "L3",
			JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
			JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"}
		return joy_names.get(binding["joy"], "Button %d" % binding["joy"])
	if binding.has("axis"):
		var neg: bool = int(binding.get("dir", 1)) < 0
		match int(binding["axis"]):
			JOY_AXIS_LEFT_X: return "Left stick left" if neg else "Left stick right"
			JOY_AXIS_LEFT_Y: return "Left stick up" if neg else "Left stick down"
			JOY_AXIS_RIGHT_X: return "Right stick left" if neg else "Right stick right"
			JOY_AXIS_RIGHT_Y: return "Right stick up" if neg else "Right stick down"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Axis %d%s" % [binding["axis"], "-" if neg else "+"]
	return "Unbound"


## Label for whatever `action` is bound to on `device`, for prompts like "E: Order pint".
func action_label(action: String, device := "kb") -> String:
	if not binds.has(action):
		return "?"
	return binding_label(binds[action][device])


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


func _queue_save() -> void:
	# Sliders change many times a second; write the file once per frame at most.
	if not _save_queued:
		_save_queued = true
		save_settings.call_deferred()


func save_settings() -> void:
	_save_queued = false
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


func _notification(what: int) -> void:
	if values.is_empty():
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and values["sound"]["mute_unfocused"]:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, false)


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
		["sound", "mute_unfocused"]:
			if not v:
				AudioServer.set_bus_mute(0, false)
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
		["graphics", "msaa"]:
			var levels := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
			get_tree().root.msaa_3d = levels[clampi(int(v), 0, 3)]
		["graphics", "ui_scale"]:
			get_tree().root.content_scale_factor = float(v)
		["gameplay", "difficulty"]:
			GameData.difficulty_index = clampi(int(v), 0, GameData.DIFFICULTIES.size() - 1)
		# graphics/shadows, gameplay/blood etc. are read by the systems that use them.
