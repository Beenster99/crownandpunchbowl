extends Node
## Test cases for Chatter. Loaded by chatter_test.gd once the autoloads exist.

signal finished(failures: int)

var _failures := 0
var _arena: Node3D


func run() -> void:
	GameData.difficulty_index = 1
	var tests := [
		"test_line_pool", "test_murmur", "test_calm_pair_chats", "test_local_just_grunts",
		"test_violence_stops_chatter", "test_no_chatter_while_hot",
	]
	for t in tests:
		_arena = Node3D.new()
		add_child(_arena)
		_floor()
		await call(t)
		_arena.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	if _failures == 0:
		print("Chatter OK: %d tests, %d lines" % [tests.size(), ChatterLines.all_keys().size()])
	finished.emit(_failures)


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(60, 0.2, 60)
	body.add_child(shape)
	body.position.y = -0.1
	_arena.add_child(body)


func _director() -> Director:
	var d := Director.new()
	d.actors = _arena
	d.auto_start = false
	d.rng_seed = 99
	d.initial_punters = 0
	d.reserve_punters = 0
	d.door = Vector3(8, 0, 0)
	d.punter_spots = [Vector3(0, 0, -4)]
	_arena.add_child(d)
	d.start()
	return d


func _chatter(d: Director) -> Chatter:
	var c := d.get_node("Chatter") as Chatter
	c.start_every = Vector2(0.2, 0.3)
	return c


func _player(pos: Vector3) -> Fighter:
	var f := Fighter.new()
	f.team = Fighter.Team.PLAYERS
	f.max_hp = 1000.0
	f.collision_layer = 2
	f.collision_mask = 7
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.position.y = 0.875
	f.add_child(shape)
	f.position = pos
	_arena.add_child(f)
	return f


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


# --- Tests -----------------------------------------------------------------------------

func test_line_pool() -> void:
	var keys := ChatterLines.all_keys()
	_check(keys.size() >= 400, "a big pool of lines (%d)" % keys.size())
	var seen := {}
	for k in keys:
		var t := ChatterLines.text(k)
		_check(t != "", "line %s has text" % k)
		_check(not seen.has(t), "line %s isn't a duplicate" % k)
		seen[t] = true
	for topic in ChatterLines.topics():
		for part in ["open", "reply", "more"]:
			_check(ChatterLines.TOPICS[topic].get(part, []).size() >= 4,
				"%s has at least 4 %s lines" % [topic, part])
	_check(ChatterLines.text("dogs/open/999") == "" and ChatterLines.text("nope") == "",
		"unknown keys give no text")
	_check(ChatterLines.voice_path("dogs/open/3") == "res://assets/audio/voice/chatter/dogs_open_03.ogg",
		"voice file path for a topic line")
	_check(ChatterLines.voice_path("_/interrupt/0").ends_with("shared_interrupt_00.ogg"),
		"voice file path for a shared line")


func test_murmur() -> void:
	var text := ChatterLines.text("tax/open/0")
	var m := ChatterVoice.stream_for("tax/open/0", text, "m")
	var f := ChatterVoice.stream_for("tax/open/0", text, "f")
	_check(m != null and m.data.size() > 0 and f.data != m.data, "murmur for both voices")
	var secs := ChatterVoice.length_of(m)
	_check(secs > 1.5 and secs < 12.0, "murmur roughly as long as the line (%.1fs)" % secs)
	_check(ChatterVoice.stream_for("tax/open/0", text, "m") == m, "murmur is cached")


func test_calm_pair_chats() -> void:
	var d := _director()
	var c := _chatter(d)
	var a := d.spawn(&"second_homer", Vector3(0, 0, 0))
	var b := d.spawn(&"second_homer", Vector3(1.5, 0, 0))
	var said := []
	c.line_said.connect(func(who, k, _t): said.append([who, k]))
	await _wait(1.5)
	_check(c.conversations() == 1, "two calm second-homers start chatting")
	_check(a.chatting_with == b and b.chatting_with == a, "they face each other")
	await _wait(14.0)
	_check(said.size() >= 2, "they exchange lines (%d)" % said.size())
	var speakers := said.map(func(e): return e[0])
	_check(a in speakers and b in speakers, "both of them talk")
	var bubble := (said[0][0] as Node).get_node_or_null("ChatterBubble") as ChatterBubble
	_check(bubble != null, "a speech bubble appears over the speaker")
	_check(a.global_position.distance_to(Vector3(0, 0, 0)) < 1.0, "talkers don't wander off")


func test_local_just_grunts() -> void:
	var d := _director()
	var c := _chatter(d)
	var posh := d.spawn(&"second_homer", Vector3(0, 0, 0))
	var local := d.spawn(&"local", Vector3(1.4, 0, 0))
	var said := []
	c.line_said.connect(func(who, k, _t): said.append([who, k]))
	await _wait(20.0)
	var from_local := said.filter(func(e): return e[0] == local)
	var from_posh := said.filter(func(e): return e[0] == posh)
	_check(not from_posh.is_empty() and not from_local.is_empty(), "second-homer talks at the local")
	for e in from_local:
		_check(String(e[1]).begins_with("_/local/"), "local only grunts back (%s)" % e[1])


func test_violence_stops_chatter() -> void:
	var d := _director()
	var c := _chatter(d)
	var p := _player(Vector3(6, 0, 6))
	var a := d.spawn(&"second_homer", Vector3(0, 0, 0))
	var b := d.spawn(&"second_homer", Vector3(1.5, 0, 0))
	var ended := []
	c.conversation_ended.connect(func(_a, _b, interrupted): ended.append(interrupted))
	await _wait(1.5)
	_check(c.conversations() == 1, "chatting before the fight")
	var victim := d.spawn(&"local", Vector3(5, 0, 6))
	victim.take_hit({"attacker": p, "damage": 4.0, "direction": Vector3.LEFT, "stagger": 0.1})
	await _wait(0.1)
	_check(c.conversations() == 0 and ended == [true], "a punch in the pub ends the chat")
	_check(a.chatting_with == null and b.chatting_with == null, "talkers are freed up")
	_check(not c.is_quiet(), "not quiet after a punch")
	_check(not c.try_start(), "no new chatter straight after a punch")


func test_no_chatter_while_hot() -> void:
	var d := _director()
	var c := _chatter(d)
	d.heat = 0.5
	d.heat_decay = 0.0
	d.spawn(&"second_homer", Vector3(0, 0, 0))
	d.spawn(&"second_homer", Vector3(1.5, 0, 0))
	await _wait(1.0)
	_check(c.conversations() == 0, "nobody chats while the heat is up")
	d.heat = 0.0
	await _wait(1.5)
	_check(c.conversations() == 1, "chatter resumes once it's quiet")
