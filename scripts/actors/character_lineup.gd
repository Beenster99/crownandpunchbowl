extends Node3D
## Character line-up: every farmer on the front row, punters, police and bar staff
## behind. Open scenes/actors/character_lineup.tscn and press F6 to look at them.
## Left/Right (or the dodge/punch keys) cycle the animation every character plays.
## B toggles blood. C switches between the game camera and a close-up. K knocks everyone
## out into ragdolls (any animation key stands them back up).

@export var auto_cycle_seconds := 0.0

var rigs: Array[CharacterRig] = []
var _anim_index := 0
var _label: Label
var _cam: Camera3D
var _close := true
var _blood := false
var _timer := 0.0


func _ready() -> void:
	_build_stage()
	var x := -(CharacterLooks.FARMERS.size() - 1) * 0.8
	for id in CharacterLooks.FARMERS:
		_add(CharacterLooks.farmer(id), Vector3(x, 0, 1.4), id.capitalize())
		x += 1.6
	var back := []
	for id in CharacterLooks.PUNTERS:
		back.append(CharacterLooks.punter(id, 1))
	back.append(CharacterLooks.punter("local", 2))
	back.append(CharacterLooks.punter("rugby_lad", 3))
	for id in CharacterLooks.POLICE:
		back.append(CharacterLooks.police(id, 1))
	for id in CharacterLooks.STAFF:
		back.append(CharacterLooks.staff(id, 1))
	x = -(back.size() - 1) * 0.6
	for look in back:
		_add(look, Vector3(x, 0, -1.6), String(look.id).trim_suffix("_1").replace("_", " "))
		x += 1.2
	_label = Label.new()
	_label.position = Vector2(24, 18)
	_label.add_theme_font_size_override("font_size", 26)
	add_child(_label)
	_set_camera()
	_show_anim()


func _process(delta: float) -> void:
	if auto_cycle_seconds > 0.0:
		_timer += delta
		if _timer >= auto_cycle_seconds:
			_timer = 0.0
			_step(1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT, KEY_D:
				_step(1)
			KEY_LEFT, KEY_A:
				_step(-1)
			KEY_B:
				_blood = not _blood
				for r in rigs:
					r.set_blood(1.0 if _blood else 0.0)
			KEY_C:
				_close = not _close
				_set_camera()
			KEY_K:
				knock_out_all()


func play_all(anim_name: StringName) -> void:
	_anim_index = CharacterRig.ANIMATIONS.find(anim_name)
	_show_anim()


## Knocks everyone backwards into ragdolls, each a slightly different way.
func knock_out_all() -> void:
	var i := 0
	for r in rigs:
		var back := r.global_basis.z
		var side := r.global_basis.x * (0.5 if i % 2 == 0 else -0.5)
		r.start_ragdoll((back + side).normalized() * (25.0 + 5.0 * (i % 3)) + Vector3.UP * 8.0)
		i += 1
	_label.text = "ragdoll   (Left/Right: animation, B: blood, C: camera, K: knock out)"


func _step(dir: int) -> void:
	_anim_index = wrapi(_anim_index + dir, 0, CharacterRig.ANIMATIONS.size())
	_show_anim()


func _show_anim() -> void:
	var a := CharacterRig.ANIMATIONS[_anim_index]
	for r in rigs:
		r.auto_return_to_idle = false
		r.play(a, 0.1)
	_label.text = "%s   (Left/Right: animation, B: blood, C: camera, K: knock out)" % a


func _add(look: CharacterLook, pos: Vector3, title: String) -> void:
	var rig := CharacterRig.new()
	rig.look = look
	rig.position = pos
	rig.rotation_degrees.y = 145.0  # three-quarter view towards the camera
	add_child(rig)
	rigs.append(rig)
	var tag := Label3D.new()
	tag.text = title
	tag.font_size = 26
	tag.pixel_size = 0.004
	tag.position = pos + Vector3(0, 0.02, 0.55)
	tag.rotation_degrees.x = -70
	tag.modulate = Color("f2e2b8")
	tag.outline_size = 8
	add_child(tag)


func _set_camera() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.current = true
	if _close:
		_cam.fov = 34.0
		_cam.position = Vector3(0, 2.6, 10.5)
		_cam.rotation_degrees = Vector3(-11, 0, 0)
	else:
		# Same angle as BrawlCamera: 55 degrees down, no yaw.
		_cam.fov = 40.0
		_cam.position = Vector3(0, 12.5, 8.8)
		_cam.rotation_degrees = Vector3(-55, 0, 0)


func _build_stage() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	add_child(ground)  # so ragdolls have something to land on
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(24, 12)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("5a3b22")
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	wall.mesh.size = Vector3(24, 5, 0.2)
	wall.position = Vector3(0, 2.5, -3.5)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("c9b48a")
	wall.material_override = wm
	add_child(wall)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 3.0, 3.0)
	lamp.light_color = Color("ffb35c")
	lamp.light_energy = 1.0
	lamp.omni_range = 12.0
	add_child(lamp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("120b07")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8a6a50")
	env.environment.ambient_light_energy = 0.45
	add_child(env)
