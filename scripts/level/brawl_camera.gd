class_name BrawlCamera
extends Camera3D
## The recommended camera: fixed-yaw, high three-quarter view with a perspective lens.
## It frames every player (so co-op fights stay on one screen) and pulls back as they
## spread out. Movement input is camera-relative, so "up" always means "up the screen".
## The camera workstream tunes these numbers; see docs/DESIGN.md.

@export var pitch_degrees := 55.0
@export var min_distance := 11.0
@export var max_distance := 20.0
@export var follow_speed := 5.0
## Player zoom range, as a multiple of the framing distance (the zoom_in / zoom_out actions).
@export var min_zoom := 0.4
@export var max_zoom := 1.5
@export var zoom_step := 0.08
## Fixed keyboard zoom keys on top of the rebindable mouse wheel: = / + zooms in, - zooms out.
const KEYS_IN := [KEY_EQUAL, KEY_KP_ADD]
const KEYS_OUT := [KEY_MINUS, KEY_KP_SUBTRACT]
## Default framing for a new player: fairly close in on the fight.
const DEFAULT_ZOOM := 0.7
## Floor area (x, z, width, depth) the framing centre is kept inside. Zero size = no limit.
@export var bounds := Rect2()

var targets: Array[Node3D] = []
## 1.0 = the full framing distance. Below 1 is closer. Saved with the settings
## (profile/camera_zoom), so it carries across pubs and sessions.
static var zoom := DEFAULT_ZOOM
var _trauma := 0.0
var _zoom_smooth := 1.0
var _hold_t := 0.0


func _ready() -> void:
	fov = float(Settings.get_value("graphics", "fov"))
	current = true
	zoom = clampf(float(Settings.get_value("profile", "camera_zoom")), min_zoom, max_zoom)
	_zoom_smooth = zoom
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "fov":
		fov = float(Settings.get_value("graphics", "fov"))


## _input rather than _unhandled_input: the HUD sits over the whole screen, and a mouse wheel
## tick over any of its controls would otherwise be swallowed before it reached the camera.
func _input(event: InputEvent) -> void:
	if _menu_open():
		return
	# Wheel ticks and presses step the zoom; held buttons and keys keep going in _process.
	if event.is_action_pressed("zoom_in") or _zoom_key(event, KEYS_IN):
		zoom_by(-zoom_step)
	elif event.is_action_pressed("zoom_out") or _zoom_key(event, KEYS_OUT):
		zoom_by(zoom_step)


func _zoom_key(event: InputEvent, keys: Array) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.physical_keycode in keys


## A pause or settings screen has the focus, so the wheel and D-pad belong to it.
func _menu_open() -> bool:
	return get_tree().paused or get_viewport().gui_get_focus_owner() != null


func zoom_by(amount: float) -> void:
	zoom = clampf(zoom + amount, min_zoom, max_zoom)


func _held(action: String, keys: Array) -> bool:
	# The mouse wheel has no "held", so only buttons and keys count here.
	if InputMap.has_action(action) and Input.is_action_pressed(action):
		return true
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")), 0.0, 1.0)


## Jump straight to the framing position (e.g. on level load) instead of easing in.
func snap() -> void:
	_zoom_smooth = zoom
	_frame(1.0)


func _process(delta: float) -> void:
	if not _menu_open():
		# Held: after a short delay the zoom keeps sliding (D-pad, or the keyboard keys).
		var dir := 0.0
		if _held("zoom_in", KEYS_IN):
			dir -= 1.0
		if _held("zoom_out", KEYS_OUT):
			dir += 1.0
		_hold_t = _hold_t + delta if dir != 0.0 else 0.0
		if _hold_t > 0.25:
			zoom_by(dir * delta * 0.8)
		elif _hold_t == 0.0 and not is_equal_approx(float(Settings.get_value("profile", "camera_zoom")), zoom):
			Settings.set_value("profile", "camera_zoom", zoom)  # saved once the zoom settles
	_zoom_smooth = lerpf(_zoom_smooth, zoom, clampf(8.0 * delta, 0.0, 1.0))
	_frame(clampf(follow_speed * delta, 0.0, 1.0))
	if _trauma > 0.0:
		var s := _trauma * _trauma * 0.25
		h_offset = randf_range(-s, s)
		v_offset = randf_range(-s, s)
		_trauma = maxf(_trauma - delta * 1.5, 0.0)
	else:
		h_offset = 0.0
		v_offset = 0.0


func _frame(weight: float) -> void:
	var live := targets.filter(func(t): return is_instance_valid(t) and t.is_inside_tree())
	if live.is_empty():
		return
	var centre := Vector3.ZERO
	for t in live:
		centre += t.global_position
	centre /= live.size()
	if bounds.has_area():
		centre.x = clampf(centre.x, bounds.position.x, bounds.end.x)
		centre.z = clampf(centre.z, bounds.position.y, bounds.end.y)
	var spread := 0.0
	for t in live:
		spread = maxf(spread, t.global_position.distance_to(centre))
	var dist := clampf(min_distance + spread * 1.2, min_distance, max_distance) * _zoom_smooth
	var pitch := deg_to_rad(pitch_degrees)
	var want := centre + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	global_position = global_position.lerp(want, weight)
	look_at(global_position - Vector3(0.0, sin(pitch), cos(pitch)), Vector3.UP)
