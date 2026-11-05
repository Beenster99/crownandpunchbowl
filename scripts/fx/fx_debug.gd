class_name FxDebug
extends Node
## Debug-build-only test triggers so the FX can be seen and heard before combat exists.
## Raw F-keys on purpose: these are not game actions and never appear in the keybinds screen.
##
##   F5  punch to the face      F6  heavy kick to the body
##   F7  headbutt + broken nose F8  start crawling (moans, blood trail)
##   F9  knock out              F10 smash a bottle
##   F11 order a pint           F12 police whistle
##
## Hits land on a red dummy that appears in front of the first player.

var _dummy: Node3D
var _crawl := false


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var player := _player()
	if player == null:
		return
	var handled := true
	match k.keycode:
		KEY_F5:
			_hit(player, "punch", 9.0, false, true)
		KEY_F6:
			_hit(player, "kick", 16.0, true, false)
		KEY_F7:
			_hit(player, "headbutt", 18.0, true, true)
			Events.nose_broken.emit(_get_dummy(player))
		KEY_F8:
			_crawl = true
			Events.fighter_knocked_down.emit(_get_dummy(player))
			Events.fighter_crawling.emit(_get_dummy(player))
		KEY_F9:
			_crawl = false
			Events.fighter_knocked_out.emit(_get_dummy(player))
		KEY_F10:
			var bottle := Node3D.new()
			bottle.name = "BrokenBottle"
			get_tree().current_scene.add_child(bottle)
			bottle.global_position = _get_dummy(player).global_position + Vector3.UP * 1.4
			Events.item_broken.emit(bottle)
			bottle.queue_free()
		KEY_F11:
			Events.drink_ordered.emit(player)
		KEY_F12:
			Events.police_called.emit()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _crawl and is_instance_valid(_dummy):
		_dummy.global_position += _dummy.global_basis.z * 0.6 * delta  # crawl away


func _hit(player: Node3D, move: String, damage: float, heavy: bool, to_face: bool) -> void:
	var dummy := _get_dummy(player)
	var dir := (dummy.global_position - player.global_position).normalized()
	Events.hit_landed.emit({
		"attacker": player, "victim": dummy, "move": move, "damage": damage,
		"position": FxDirector.head_position(dummy) if to_face else dummy.global_position + Vector3.UP,
		"direction": dir, "heavy": heavy, "to_face": to_face,
	})


func _player() -> Node3D:
	var players := get_tree().get_nodes_in_group("players")
	return players[0] as Node3D if not players.is_empty() else null


func _get_dummy(player: Node3D) -> Node3D:
	if is_instance_valid(_dummy) and _dummy.is_inside_tree():
		return _dummy
	_dummy = Node3D.new()
	_dummy.name = "FxDummy"
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35  # same size as the placeholder player
	capsule.height = 1.75
	mesh.mesh = capsule
	mesh.position.y = 0.875
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d8c7a0")
	mesh.material_override = mat
	_dummy.add_child(mesh)
	get_tree().current_scene.add_child(_dummy)
	_dummy.global_position = player.global_position - player.global_basis.z * 1.3
	_dummy.look_at(player.global_position, Vector3.UP)
	return _dummy
