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

var targets: Array[Node3D] = []
var _trauma := 0.0


func _ready() -> void:
	fov = 40.0
	current = true


func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount * float(Settings.get_value("gameplay", "camera_shake")), 0.0, 1.0)


func _process(delta: float) -> void:
	var live := targets.filter(func(t): return is_instance_valid(t))
	if live.is_empty():
		return
	var centre := Vector3.ZERO
	for t in live:
		centre += t.global_position
	centre /= live.size()
	var spread := 0.0
	for t in live:
		spread = maxf(spread, t.global_position.distance_to(centre))
	var dist := clampf(min_distance + spread * 1.2, min_distance, max_distance)
	var pitch := deg_to_rad(pitch_degrees)
	var want := centre + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	global_position = global_position.lerp(want, clampf(follow_speed * delta, 0.0, 1.0))
	look_at(global_position - Vector3(0.0, sin(pitch), cos(pitch)), Vector3.UP)
	if _trauma > 0.0:
		var s := _trauma * _trauma * 0.25
		h_offset = randf_range(-s, s)
		v_offset = randf_range(-s, s)
		_trauma = maxf(_trauma - delta * 1.5, 0.0)
	else:
		h_offset = 0.0
		v_offset = 0.0
