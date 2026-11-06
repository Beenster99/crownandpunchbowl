class_name BrawlCamera
extends Camera3D
## The recommended camera: fixed-yaw, high three-quarter view with a perspective lens.
## Optional first person (Settings gameplay/camera_view, P, or zoom in past the closest view)
## looks through the local player's eyes; each player picks their own view, online too.
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

## First person: field of view (wider than the overhead lens), how far down you look, and how
## far forward of the head's centre the eyes sit.
const FP_FOV := 74.0
const FP_PITCH := -9.0
const FP_EYE_FORWARD := 0.14
## Mouse turn in first person, radians per pixel.
const FP_MOUSE_TURN := 0.0035

var targets: Array[Node3D] = []
## The local player is seen through their own eyes right now (not just chosen in settings:
## while you're on the floor or held the overhead view comes back). Read by HUD prompts.
static var first_person := false
var _fp_blend := 0.0
var _fp_pos := Vector3.ZERO
var _fp_player: PlayerFighter = null
var _over_pos := Vector3.ZERO
var _over_ready := false
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
	if section == "graphics" and key == "fov" and _fp_blend <= 0.0:
		fov = float(Settings.get_value("graphics", "fov"))


## _input rather than _unhandled_input: the HUD sits over the whole screen, and a mouse wheel
## tick over any of its controls would otherwise be swallowed before it reached the camera.
func _input(event: InputEvent) -> void:
	if _menu_open():
		return
	if InputMap.has_action("camera_view") and event.is_action_pressed("camera_view"):
		set_view(not wants_first_person())
		return
	if wants_first_person():
		# Zooming out of your own eyes goes back to the overhead view.
		if event.is_action_pressed("zoom_out") or _zoom_key(event, KEYS_OUT):
			set_view(false)
		var mm := event as InputEventMouseMotion
		if mm != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and is_instance_valid(_fp_player):
			_fp_player.view_turn += mm.relative.x * FP_MOUSE_TURN
		return
	# Wheel ticks and presses step the zoom; held buttons and keys keep going in _process.
	# Zooming in when already as close as it goes drops into first person (the pad's way in).
	if event.is_action_pressed("zoom_in") or _zoom_key(event, KEYS_IN):
		if zoom <= min_zoom + 0.001 and _hold_t <= 0.25:
			set_view(true)
		else:
			zoom_by(-zoom_step)
	elif event.is_action_pressed("zoom_out") or _zoom_key(event, KEYS_OUT):
		zoom_by(zoom_step)


## The player chose first person (the Camera setting). Saved, so it sticks between fights.
func wants_first_person() -> bool:
	return int(Settings.get_value("gameplay", "camera_view")) == 1


func set_view(fp: bool) -> void:
	Settings.set_value("gameplay", "camera_view", 1 if fp else 0)


## The player this machine controls, or null.
func local_player() -> PlayerFighter:
	for t in targets:
		if not is_instance_valid(t):
			continue  # a player who left: the pub drops them from targets later
		var p := t as PlayerFighter
		if p != null and p.is_inside_tree() and p.is_multiplayer_authority():
			return p
	return null


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
	_update_first_person(0.0, true)
	_place()


func _process(delta: float) -> void:
	if not _menu_open() and not wants_first_person():
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
	_update_first_person(delta)
	_place()
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
	_over_pos = _over_pos.lerp(want, weight) if _over_ready else want
	_over_ready = true


## The overhead view's transform: fixed angle looking down at the framing centre.
func _overhead_transform() -> Transform3D:
	var pitch := deg_to_rad(pitch_degrees)
	var xf := Transform3D(Basis.IDENTITY, _over_pos)
	return xf.looking_at(_over_pos - Vector3(0.0, sin(pitch), cos(pitch)), Vector3.UP)


## First person is on when chosen and the local player is on their feet (on the floor, held
## or knocked out the overhead view comes back so you can see what's happening to you).
func _update_first_person(delta: float, instant := false) -> void:
	var p := local_player()
	if p != _fp_player:
		_set_player(p)
	var on := wants_first_person() and p != null and not p.is_down() \
		and p.state != Fighter.State.HELD and p.state != Fighter.State.DOUBLED
	if on and not first_person:
		p.view_yaw = p.rotation.y
		_fp_pos = _eye_position(p)
	first_person = on
	if p != null:
		p.first_person = on
		var hider := _head_hider(p)
		if hider != null:
			hider.active = _fp_blend > 0.5 or on and instant
	_fp_blend = (1.0 if on else 0.0) if instant else move_toward(_fp_blend, 1.0 if on else 0.0, delta * 4.0)
	if p != null and (on or _fp_blend > 0.0):
		# A little lag on the eyes: hit snaps and footwork move the view without jarring it.
		var eye := _eye_position(p)
		_fp_pos = eye if instant else _fp_pos.lerp(eye, clampf(18.0 * delta, 0.0, 1.0))
	# Mouse look needs the pointer captured, but only while nothing on screen wants it.
	var capture := on and Settings.device == "kb" and not _menu_open() and not TalkUi.typing \
		and not DartsBoard.local_input_locked()
	if capture and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not capture and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_player(p: PlayerFighter) -> void:
	if is_instance_valid(_fp_player):
		_fp_player.first_person = false
		_fp_player.face_override = Vector3.ZERO
		var old := _head_hider(_fp_player)
		if old != null:
			old.active = false
	_fp_player = p


func _eye_position(p: PlayerFighter) -> Vector3:
	return p.get_head_position() + p.get_facing() * FP_EYE_FORWARD


## The local player's FirstPersonHead, made on first use. Null without a rigged skeleton.
func _head_hider(p: PlayerFighter) -> FirstPersonHead:
	var v := p.get_node_or_null(FighterVisual.NODE_NAME) as FighterVisual
	if v == null or v.rig == null or v.rig.skeleton == null:
		return null
	var skel := v.rig.skeleton
	var h := skel.get_node_or_null("FirstPersonHead") as FirstPersonHead
	if h == null:
		h = FirstPersonHead.new()
		h.name = "FirstPersonHead"
		h.active = false
		skel.add_child(h)
	elif h.get_index() != skel.get_child_count() - 1:
		skel.move_child(h, -1)  # stay after the hit reactions and anything else on the skeleton
	return h


func _first_person_transform() -> Transform3D:
	var p := _fp_player
	var yaw := p.view_yaw if p != null and is_instance_valid(p) else 0.0
	var roll := 0.0
	if p != null and is_instance_valid(p):
		roll = -p.head_bob.x * 0.12  # slipping tilts the view a touch
	var b := Basis.from_euler(Vector3(deg_to_rad(FP_PITCH), yaw, roll), EULER_ORDER_YXZ)
	return Transform3D(b, _fp_pos)


func _place() -> void:
	var over := _overhead_transform()
	var setting_fov := float(Settings.get_value("graphics", "fov"))
	if _fp_blend <= 0.0 or _fp_player == null or not is_instance_valid(_fp_player):
		global_transform = over
		fov = setting_fov
		near = 0.05
		return
	var t := ease(_fp_blend, -2.0)
	global_transform = over.interpolate_with(_first_person_transform(), t)
	fov = lerpf(setting_fov, FP_FOV, t)
	near = 0.12


func _exit_tree() -> void:
	first_person = false
	_set_player(null)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
