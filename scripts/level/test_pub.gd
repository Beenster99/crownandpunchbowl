extends Node3D
## Greybox sandbox pub used by every workstream until the real pubs exist.
## Builds a floor, walls and a bar in code, spawns local players and points the
## BrawlCamera at them. The pubs workstream replaces this with authored scenes.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const ROOM := Vector2(16.0, 12.0)


func _ready() -> void:
	_build_room()
	var cam := BrawlCamera.new()
	add_child(cam)
	var i := 0
	for peer_id in Net.players:
		var p := PLAYER_SCENE.instantiate()
		p.name = "P%d" % peer_id
		p.set_multiplayer_authority(peer_id)
		p.position = Vector3(-1.5 + i * 1.0, 0.0, ROOM.y * 0.5 - 1.5)
		$Actors.add_child(p)
		cam.targets.append(p)
		i += 1
	Events.banner.emit("%s — %s" % [GameData.current_pub()["name"], GameData.current_pub()["era"]], 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _build_room() -> void:
	_box(Vector3(ROOM.x, 0.2, ROOM.y), Vector3(0, -0.1, 0), Color("5a3b22"))  # floor
	_box(Vector3(ROOM.x, 3.0, 0.3), Vector3(0, 1.5, -ROOM.y * 0.5), Color("c9b48a"))  # back wall
	_box(Vector3(0.3, 3.0, ROOM.y), Vector3(-ROOM.x * 0.5, 1.5, 0), Color("c9b48a"))
	_box(Vector3(0.3, 3.0, ROOM.y), Vector3(ROOM.x * 0.5, 1.5, 0), Color("c9b48a"))
	_box(Vector3(7.0, 1.1, 0.8), Vector3(0, 0.55, -ROOM.y * 0.5 + 1.6), Color("3b2314"))  # bar
	for t in [Vector3(-4, 0.4, 0), Vector3(4, 0.4, 0), Vector3(-4, 0.4, 3), Vector3(4, 0.4, 3)]:
		_box(Vector3(1.2, 0.8, 1.2), t, Color("4a2d18"))  # tables
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.4
	sun.shadow_enabled = bool(Settings.get_value("graphics", "shadows"))
	add_child(sun)
	for x in [-4.0, 4.0]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 2.6, 0)
		lamp.light_color = Color("ffb35c")
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		add_child(lamp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("120b07")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("6b4a30")
	env.environment.ambient_light_energy = 0.6
	add_child(env)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	$World.add_child(body)
