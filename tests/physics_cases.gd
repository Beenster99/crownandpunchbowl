extends Node
## Cases for tests/physics_test.gd (loaded after the autoloads so class names resolve).

signal finished(failures: int)

const PUB := "res://scenes/pubs/crown_and_punchbowl.tscn"

var _failures := 0
var _level: Node
var _player: Fighter


func run() -> void:
	Net.start_solo("Tester", 0)
	GameData.start_crawl(0)
	Fx.hit_stop_time_scale = 1.0  # hit-stop runs on real time; --fixed-fps outruns it
	load("res://scripts/level/pub_level.gd").crowd_enabled = false
	get_tree().change_scene_to_file(PUB)
	for _f in 240:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.is_node_ready() \
				and not get_tree().get_nodes_in_group("players").is_empty():
			break
	_level = get_tree().current_scene
	_player = get_tree().get_nodes_in_group("players")[0] as Fighter
	await _frames(30)

	await _test_props_exist()
	await _test_glass_smashes()
	await _test_walking_shoves_chair()
	await _test_flung_into_table()
	await _test_over_the_bar()
	await _test_slam_shakes_shelves()
	await _test_ragdoll_down_and_up()

	if _failures == 0:
		print("PHYSICS OK")
	finished.emit(_failures)


func _test_props_exist() -> void:
	var props := get_tree().get_nodes_in_group(PubPhysics.GROUP)
	_check(props.size() > 60, "pub has lots of physics props (%d)" % props.size())
	_check(PubPhysics.get_for(_level) != null, "pub has a PubPhysics manager")
	var tables := 0
	var shelf := 0
	for p in props:
		if p.get_parent() != null and String(p.get_parent().name).begins_with("Table"):
			tables += 1
		if String(p.name).begins_with("ShelfBottle"):
			shelf += 1
	_check(tables > 0, "tables are rigid bodies (%d)" % tables)
	_check(shelf > 10, "back bar bottles are pinned props (%d)" % shelf)
	var items := get_tree().get_nodes_in_group(PubItem.GROUP)
	var with_body := 0
	for i in items:
		if (i as PubItem).body != null:
			with_body += 1
	_check(with_body == items.size() and items.size() > 0, "every loose item has a body (%d/%d)" % [with_body, items.size()])


func _test_glass_smashes() -> void:
	var mgr := PubItems.get_for(_level)
	var glass := mgr.server_spawn(&"glass", Vector3(-3.0, 2.2, 2.0))
	await _frames(2)
	glass.body.global_position = Vector3(-3.0, 2.2, 2.0)
	glass.body.sleeping = false
	await _frames(90)
	_check(not is_instance_valid(glass) or glass.mode == PubItem.Mode.GONE, "a dropped glass smashes on the floor")


func _test_walking_shoves_chair() -> void:
	var chair := _nearest_item(&"chair", _player.global_position)
	if chair == null:
		_check(false, "found a chair")
		return
	var start := chair.global_position
	var dir := Vector3(1, 0, 0)
	_place(_player, start - dir * 1.4)
	Input.action_press("move_right")  # the player reads its stick every frame
	for _f in 60:
		await get_tree().physics_frame
	Input.action_release("move_right")
	await _frames(20)
	_check(chair.global_position.distance_to(start) > 0.15, "walking into a chair shoves it (%.2f m)" % chair.global_position.distance_to(start))


func _test_flung_into_table() -> void:
	var table := _nearest_table(Vector3(-4, 0, 2))
	if table == null:
		_check(false, "found a table")
		return
	var start := table.global_position
	var dir := Vector3(0, 0, -1)
	_place(_player, start - dir * 1.5 + Vector3(0.0, 0, 0))
	_knock(_player, dir, 5.0)
	await _frames(70)
	_check(table.global_position.distance_to(start) > 0.2 or table.global_basis.y.dot(Vector3.UP) < 0.95,
		"a body knocked into a table moves it (%.2f m)" % table.global_position.distance_to(start))
	await _wait_up(_player)


func _test_over_the_bar() -> void:
	# Crown and Punchbowl: bar counter from x 2.5..10, z -5.8..-5.0; staff side is -z.
	_place(_player, Vector3(5.0, 0, -4.2))
	await _frames(5)
	var flipped := []
	var cb := func(f, _o): flipped.append(f)
	Events.fighter_flipped_over.connect(cb)
	_knock(_player, Vector3(0, 0, -1), 9.0)
	await _frames(90)
	Events.fighter_flipped_over.disconnect(cb)
	_check(flipped.has(_player), "knocked into the bar: flipped over it")
	_check(_player.global_position.z < -5.9, "ends up behind the bar (z %.2f)" % _player.global_position.z)
	_check(_player.global_position.y > -0.2, "still on the floor, not through it (y %.2f)" % _player.global_position.y)
	await _wait_up(_player)


func _test_slam_shakes_shelves() -> void:
	var bottles: Array[RigidBody3D] = []
	for p in get_tree().get_nodes_in_group(PubPhysics.GROUP):
		if String(p.name).begins_with("ShelfBottle"):
			bottles.append(p)
	var before := {}
	for b in bottles:
		before[b] = b.global_position
	PubPhysics.disturb(get_tree(), Vector3(6.2, 1.2, -6.9), 1.8, Vector3(0, 0, -5))
	await _frames(60)
	var moved := 0
	for b in bottles:
		if not is_instance_valid(b) or b.global_position.distance_to(before[b]) > 0.1:
			moved += 1
	_check(moved >= 3, "a slam into the back bar knocks shelf bottles loose (%d)" % moved)


func _test_ragdoll_down_and_up() -> void:
	_place(_player, Vector3(-2.0, 0, 3.0))
	await _frames(10)
	var visual := _player.get_node(FighterVisual.NODE_NAME) as FighterVisual
	_knock(_player, Vector3(1, 0, 0), 4.0)
	await _frames(20)
	_check(_player.state == Fighter.State.DOWN, "knocked down")
	_check(visual.rig.ragdolling, "a knockdown goes ragdoll")
	await _frames(40)
	var hips := visual.rig.ragdoll_bone(&"Hips")
	var gap := Vector2(hips.global_position.x - _player.global_position.x, hips.global_position.z - _player.global_position.z).length()
	_check(gap < 1.2, "the ragdoll stays with the fighter (%.2f m)" % gap)
	await _wait_up(_player)
	await _frames(45)
	_check(not visual.rig.ragdolling, "back on their feet: the ragdoll has ended")
	_check(_player.state == Fighter.State.IDLE, "got up")


# --- Helpers ---------------------------------------------------------------------------

func _knock(f: Fighter, dir: Vector3, speed: float) -> void:
	f.take_hit({
		"attacker": null, "move": "test", "damage": 1.0, "direction": dir, "heavy": true,
		"knockdown": true, "knockback": speed * maxf(f.toughness, 0.1), "poise": 0.0,
	})


func _place(f: Fighter, pos: Vector3) -> void:
	f.global_position = pos
	f.velocity = Vector3.ZERO
	f._impulse = Vector3.ZERO
	f.move_input = Vector3.ZERO


func _wait_up(f: Fighter) -> void:
	for _f in 300:
		if not f.is_down():
			break
		await get_tree().physics_frame
	await _frames(40)  # past the get-up invulnerability


func _nearest_item(kind: StringName, pos: Vector3) -> PubItem:
	var best: PubItem = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(PubItem.GROUP):
		var i := n as PubItem
		if i.kind == kind and i.is_loose() and i.global_position.y < 0.3:
			var d := i.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = i
	return best


func _nearest_table(pos: Vector3) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(PubPhysics.GROUP):
		if n.get_parent() != null and String(n.get_parent().name).begins_with("Table"):
			var d := (n as Node3D).global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = n
	return best


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok  ", what)
	else:
		_failures += 1
		print("  FAIL ", what)
