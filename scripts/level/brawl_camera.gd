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
@export var min_zoom := 0.65
@export var max_zoom := 1.35
@export var zoom_step := 0.08
## Floor area (x, z, width, depth) the framing centre is kept inside. Zero size = no limit.
@export var bounds := Rect2()

var targets: Array[Node3D] = []
## 1.0 = default framing. Below 1 is closer. Kept across pubs for the session.
static var zoom := 1.0
var _trauma := 0.0
var _zoom_smooth := 1.0


func _ready() -> void:
	fov = float(Settings.get_value("graphics", "fov"))
	current = true
	_zoom_smooth = zoom
	Settings.changed.connect(_on_settings_changed)


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "fov":
		fov = float(Settings.get_value("graphics", "fov"))


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel ticks and button presses step the zoom; held pad buttons keep going in _process.
	if event.is_action_pressed("zoom_in"):
		zoom_by(-zoom_step)
	elif event.is_action_pressed("zoom_out"):
		zoom_by(zoom_step)


func zoom_by(amount: float) -> void:
	zoom = clampf(zoom + amount, min_zoom, max_zoom)


func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")), 0.0, 1.0)


## Jump straight to the framing position (e.g. on level load) instead of easing in.
func snap() -> void:
	_zoom_smooth = zoom
	_frame(1.0)


func _process(delta: float) -> void:
	for a in [["zoom_in", -1.0], ["zoom_out", 1.0]]:
		if InputMap.has_action(a[0]) and Input.is_action_pressed(a[0]) and Settings.device == "pad":
			zoom_by(a[1] * delta * 0.6)
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
