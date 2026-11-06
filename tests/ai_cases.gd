extends Node
## Test cases for the AI workstream (scripts/ai). Loaded by ai_test.gd once the autoloads exist.

signal finished(failures: int)

var _failures := 0
var _arena: Node3D


func run() -> void:
	GameData.difficulty_index = 1  # Session Ale: 2 attackers, 2 squaring up per player
	# Hit-stop runs on real time; under --fixed-fps that would slow the whole sim to a crawl.
	var fx := get_node_or_null(^"/root/Fx")
	if fx != null and "hit_stop_time_scale" in fx:
		fx.hit_stop_time_scale = 1.0
	var tests := [
		"test_calm_punters_leave_players_alone", "test_hit_punter_fights_back",
		"test_mates_join_in", "test_attack_tokens_cap", "test_gang_up_rush",
		"test_held_punter_struggles_free", "test_bar_staff", "test_waves_and_cleared",
		"test_police_raid", "test_cooling_off", "test_one_or_two_at_a_time",
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
		print("AI OK: %d tests" % tests.size())
	finished.emit(_failures)


# --- Helpers ---------------------------------------------------------------------------

func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(60, 0.2, 60)
	body.add_child(shape)
	body.position.y = -0.1
	_arena.add_child(body)


func _player(pos: Vector3, hp := 100.0) -> Fighter:
	var f := Fighter.new()
	f.team = Fighter.Team.PLAYERS
	f.max_hp = hp
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


func _director(setup := Callable()) -> Director:
	var d := Director.new()
	d.actors = _arena
	d.auto_start = false
	d.rng_seed = 1234
	d.initial_punters = 0
	d.reserve_punters = 0
	d.door = Vector3(8, 0, 0)
	d.punter_spots = [Vector3(0, 0, -4)]
	if setup.is_valid():
		setup.call(d)
	_arena.add_child(d)
	d.start()
	return d


func _hit(victim: Fighter, attacker: Fighter, dmg := 4.0) -> void:
	var dir := victim.global_position - attacker.global_position
	victim.take_hit({"attacker": attacker, "damage": dmg, "direction": dir, "stagger": 0.1})


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		await get_tree().physics_frame


func _swinging(npcs: Array) -> int:
	var n := 0
	for npc in npcs:
		if npc.state == Fighter.State.WINDUP or npc.state == Fighter.State.ATTACK:
			n += 1
	return n


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


# --- Tests -----------------------------------------------------------------------------

func test_calm_punters_leave_players_alone() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var a := d.spawn(&"rugby_lad", Vector3(0, 0, -1.5))
	var b := d.spawn(&"local", Vector3(1.5, 0, 0))
	await _wait(3.0)
	_check(is_equal_approx(p.hp, p.max_hp), "calm punters never attack (hp %.1f)" % p.hp)
	_check(a.mood == Npc.Mood.CALM and b.mood == Npc.Mood.CALM, "punters stay calm")
	_check(not d.fight_on, "no fight without a hit")
	_check(a.is_in_group(&"npcs") and a.team == Fighter.Team.PUNTERS, "punters join npcs")


func test_hit_punter_fights_back() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0), 1000.0)
	var npc := d.spawn(&"local", Vector3(0, 0, -2.0))
	var tells := []
	var started := []
	var tel_cb := func(a, t, _s): tells.append([a, t])
	var start_cb := func(): started.append(true)
	Events.attack_telegraphed.connect(tel_cb)
	Events.fight_started.connect(start_cb)
	await _wait(0.1)
	_hit(npc, p)
	_check(npc.mood == Npc.Mood.ENGAGED and npc.foe == p, "hit punter engages the attacker")
	_check(started.size() == 1 and d.fight_on, "first hit starts the fight")
	_check(d.heat > 0.0, "hitting raises the heat")
	await _wait(4.0)
	Events.attack_telegraphed.disconnect(tel_cb)
	Events.fight_started.disconnect(start_cb)
	var at_player := tells.filter(func(e): return e[0] == npc and e[1] == p)
	_check(not at_player.is_empty(), "engaged punter throws telegraphed attacks at the player")
	_check(p.hp < p.max_hp, "and some of them land")


func test_mates_join_in() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var victim := d.spawn(&"local", Vector3(0, 0, -2.0))
	var mates: Array[Npc] = []
	for i in 4:
		mates.append(d.spawn(&"rugby_lad", Vector3(-2.0 + i * 1.3, 0, -3.5)))
	var far := d.spawn(&"second_homer", Vector3(0, 0, -20.0))
	await _wait(0.1)
	_hit(victim, p)
	var engaged := mates.filter(func(m): return m.mood == Npc.Mood.ENGAGED and m.foe == p)
	var calm := mates.filter(func(m): return m.mood == Npc.Mood.CALM)
	var room := d.engaged_cap() - 1  # the victim is already squaring up
	_check(engaged.size() == room,
		"only %d mate(s) wade in, the rest watch (%d of 4)" % [room, engaged.size()])
	_check(calm.is_empty(), "every mate nearby at least notices")
	_check(far.mood == Npc.Mood.ALERT, "the rest of the pub turns to watch")


func test_attack_tokens_cap() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0), 100000.0)
	var npcs: Array[Npc] = []
	for i in 6:
		var a := TAU * i / 6.0
		var npc := d.spawn(&"local", Vector3(cos(a), 0, sin(a)) * 2.8)
		npcs.append(npc)
	await _wait(0.1)
	for npc in npcs:
		npc.engage(p)
	# Cold room: one at a time.
	var most := 0
	for i in 240:
		d.heat = 0.0
		most = maxi(most, _swinging(npcs))
		_check(d.tokens_out() <= 1, "at most one token out at heat 0")
		await get_tree().physics_frame
	_check(most == 1, "cold room: punters take turns (max %d at once)" % most)
	# Hot room: up to the difficulty's max_attackers.
	most = 0
	var cap := int(GameData.difficulty()["max_attackers"])
	for i in 360:
		d.heat = 1.0
		most = maxi(most, _swinging(npcs))
		await get_tree().physics_frame
	_check(most >= 2 and most <= cap, "hot room: %d at once (cap %d)" % [most, cap])


func test_gang_up_rush() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0), 100000.0)
	var npcs: Array[Npc] = []
	for i in 4:
		var npc := d.spawn(&"rugby_lad" if i == 0 else &"local",
			Vector3(0, 0, -2.5) if i == 0 else Vector3(-4.0 + i * 2.0, 0, -4.0))
		npc.mood = Npc.Mood.ALERT
		npcs.append(npc)
	await _wait(0.1)
	d.heat = 0.0  # tokens would only allow one attacker
	var crew := d.gang_up(p)
	var most_rushers := int(GameData.difficulty()["max_attackers"])
	_check(crew.size() == most_rushers, "rush is just %d of them (%d)" % [most_rushers, crew.size()])
	_check(crew.all(func(n): return n.mood == Npc.Mood.ENGAGED and n.foe == p and n.rushing > 0.0),
		"crew all go for the same player")
	_check(crew.any(func(n): return n.rush_grab), "a rugby lad is told to grab")
	var most := 0
	var grabbed := false
	for i in 180:
		d.heat = 0.0
		most = maxi(most, _swinging(npcs))
		grabbed = grabbed or p.state == Fighter.State.HELD
		await get_tree().physics_frame
	_check(most >= 1 and grabbed, "one holds while the other lays in (%d swinging)" % most)
	_check(grabbed, "the rugby lad grabs the player for his mates")


func test_held_punter_struggles_free() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"rugby_lad", Vector3(0, 0, -1.0))
	await _wait(0.1)
	p.rotation.y = 0.0
	p.request_grab(npc)
	_check(npc.state == Fighter.State.HELD, "player grabs the punter")
	var freed_at := -1.0
	for i in 240:
		if npc.state != Fighter.State.HELD:
			freed_at = i / 60.0
			break
		await get_tree().physics_frame
	_check(freed_at > 0.0 and freed_at < Moves.HOLD_TIME * p.grip,
		"rugby lad wriggles free before the hold times out (%.2fs)" % freed_at)


func test_bar_staff() -> void:
	var d := _director(func(dd: Director): dd.staff_spots = [Vector3(0, 0, -3)])
	var staff := get_tree().get_first_node_in_group(&"staff") as Npc
	_check(staff != null and staff.team == Fighter.Team.STAFF, "director spawns bar staff")
	_check(not staff.is_in_group(&"npcs"), "staff aren't a knockout target")
	var p := _player(Vector3(0, 0, -1.5))
	var punter := d.spawn(&"local", Vector3(3, 0, -3))
	await _wait(0.1)
	_check(not p.is_hostile_to(staff) and not staff.is_hostile_to(p), "staff are nobody's enemy")
	# Combat stops players hitting staff; even if a stray hit gets through, it changes nothing.
	for i in 5:
		_hit(staff, p, 80.0)
		await _wait(0.2)
	_check(not staff.is_ko(), "staff can't be knocked out")
	_check(not d.fight_on and is_equal_approx(d.heat, 0.0), "a hit on staff never starts a fight")
	_check(punter.mood == Npc.Mood.CALM, "punters ignore it")
	_check(_swinging([staff]) == 0 and staff.foe == null, "staff never fight")


func test_waves_and_cleared() -> void:
	var d := _director(func(dd: Director):
		dd.reserve_punters = 3
		dd.wave_size = Vector2i(2, 2)
		dd.wave_interval = 100.0
		dd.wave_when_standing_below = 1)
	var p := _player(Vector3(0, 0, 0))
	var first := d.spawn(&"second_homer", Vector3(0, 0, -2))
	var arrivals := []
	var cleared := []
	var arr_cb := func(n): arrivals.append(n)
	var clr_cb := func(id): cleared.append(id)
	Events.reinforcements_arrived.connect(arr_cb)
	Events.pub_cleared.connect(clr_cb)
	await _wait(0.1)
	_hit(first, p)
	d.police = Director.Police.NONE  # keep this test about waves
	_check(d.punters_left() == 4, "punters left counts the reserve (%d)" % d.punters_left())
	_hit(first, p, 1000.0)
	_check(first.is_ko(), "first punter out")
	await _wait(5.0)
	_check(arrivals == [2], "a wave of 2 walks in when the room empties (%s)" % [arrivals])
	var newcomers := get_tree().get_nodes_in_group(&"npcs").filter(func(n): return not n.is_ko())
	_check(newcomers.size() == 2, "two newcomers standing")
	_check(newcomers.all(func(n): return n.global_position.distance_to(d.door) < 4.0),
		"newcomers come in by the door")
	for n in newcomers:
		_hit(n, p, 1000.0)
	await _wait(5.0)
	_check(arrivals == [2, 1], "the last of the reserve arrives (%s)" % [arrivals])
	_check(cleared.is_empty(), "not cleared while anyone's left")
	for n in get_tree().get_nodes_in_group(&"npcs"):
		if not n.is_ko():
			_hit(n, p, 1000.0)
	await _wait(0.2)
	_check(cleared.size() == 1 and d.cleared, "pub cleared once everyone's out")
	Events.reinforcements_arrived.disconnect(arr_cb)
	Events.pub_cleared.disconnect(clr_cb)


func test_police_raid() -> void:
	var d := _director(func(dd: Director): dd.police_delay = 0.5)
	var p := _player(Vector3(0, 0, 0), 1000.0)
	var npc := d.spawn(&"local", Vector3(0, 0, -2))
	var calls := []
	var call_cb := func(): calls.append(true)
	Events.police_called.connect(call_cb)
	await _wait(0.1)
	_hit(npc, p)
	d.police = Director.Police.NONE
	d.call_police()
	d.call_police()
	_check(calls.size() == 1, "police are called once")
	await _wait(1.0)
	var cops := get_tree().get_nodes_in_group(&"police")
	_check(cops.size() == d.police_count, "police arrive (%d)" % cops.size())
	var on_job := cops.filter(func(c): return c.is_in_group(&"npcs") and c.foe == p)
	_check(on_job.size() == cops.size() and cops.all(func(c): return c.mood == Npc.Mood.ENGAGED),
		"police come in swinging at the players")
	d.heat = 0.0
	for c in cops:
		c._quiet_t = 100.0
	await _wait(0.2)
	_check(cops.all(func(c): return c.mood == Npc.Mood.ENGAGED), "police never cool off")
	Events.police_called.disconnect(call_cb)


func test_cooling_off() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"local", Vector3(0, 0, -6))
	await _wait(0.1)
	npc.engage(p)
	d.heat = 0.0
	npc._quiet_t = 16.0
	await _wait(0.1)
	_check(npc.mood == Npc.Mood.ALERT, "engaged punter backs off when it's gone quiet")
	npc._quiet_t = 21.0
	await _wait(0.1)
	_check(npc.mood == Npc.Mood.CALM, "and eventually goes back to their pint")
	npc.engage(p)
	d.heat = 0.5
	npc._quiet_t = 16.0
	await _wait(0.1)
	_check(npc.mood == Npc.Mood.ENGAGED, "but stays in while the room is hot")


func test_one_or_two_at_a_time() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0), 100000.0)
	var npcs: Array[Npc] = []
	for i in 6:
		var a := TAU * i / 6.0
		npcs.append(d.spawn(&"local", Vector3(cos(a), 0, sin(a)) * 3.0))
	await _wait(0.1)
	_hit(npcs[0], p)  # start the fight
	for npc in npcs:
		npc.engage(p, true)  # force the whole pub in at once
	var cap := d.engaged_cap()
	await _wait(1.5)
	var engaged := npcs.filter(func(n): return n.mood == Npc.Mood.ENGAGED)
	_check(engaged.size() <= cap, "only %d square up, the rest back off (%d)" % [cap, engaged.size()])
	_check(npcs.filter(func(n): return n.mood == Npc.Mood.ALERT).size() >= 6 - cap,
		"the others spectate")
	# Spectators keep their distance and don't join in by themselves while there's no room.
	var most := 0
	var tells := []
	var tel_cb := func(a, _t, _s): tells.append(a)
	Events.attack_telegraphed.connect(tel_cb)
	for i in 600:
		d.heat = 1.0
		most = maxi(most, _swinging(npcs))
		await get_tree().physics_frame
	Events.attack_telegraphed.disconnect(tel_cb)
	engaged = npcs.filter(func(n): return n.mood == Npc.Mood.ENGAGED)
	_check(engaged.size() <= cap, "still only %d squaring up after 10 s (%d)" % [cap, engaged.size()])
	_check(most <= int(GameData.difficulty()["max_attackers"]), "never more than 2 swinging (%d)" % most)
	var attackers := {}
	for a in tells:
		attackers[a] = true
	_check(attackers.size() <= cap, "only the ones squaring up throw punches (%d)" % attackers.size())
	_check(tells.size() >= 2 and tells.size() <= 10, "a steady pace, not a flurry (%d tells in 10 s)" % tells.size())
