extends Node
## Test cases for the Fighter API and core combat rules. Loaded by combat_test.gd once the
## autoloads exist (SceneTree scripts compile before autoloads are registered).

signal finished(failures: int)

var _failures := 0
var _arena: Node3D


func run() -> void:
	GameData.difficulty_index = 1  # Session Ale: multipliers of 1.0
	var tests := [
		"test_jab_hits_and_lunges", "test_held_takes_bonus_damage", "test_counter",
		"test_knockdown_crawl_ko", "test_grab_escape_and_throw", "test_dodge_iframes",
		"test_staff_never_ko", "test_no_friendly_fire", "test_heal_gets_up_from_crawl",
		"test_ground_moves", "test_weapon_hooks", "test_player_punch_chain",
		"test_player_finisher_and_combo", "test_player_kick_stomps", "test_player_input",
		"test_sparring_punter", "test_sandbox_loads", "test_throw_over_railing",
		"test_throw_off_open_edge", "test_throw_away_from_edge", "test_short_drop_no_damage",
	]
	for t in tests:
		print("  ", t)
		_arena = Node3D.new()
		add_child(_arena)
		_floor()
		await call(t)
		_arena.queue_free()
		await get_tree().process_frame
	if _failures == 0:
		print("COMBAT OK: %d tests" % tests.size())
	finished.emit(_failures)


# --- Helpers ---------------------------------------------------------------------------

func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(40, 0.2, 40)
	body.add_child(shape)
	body.position.y = -0.1
	_arena.add_child(body)


func _fighter(team: int, pos: Vector3, face_toward := Vector3.INF, script: GDScript = null) -> Fighter:
	var f: Fighter = script.new() if script != null else Fighter.new()
	f.team = team
	f.collision_layer = 2 if team == Fighter.Team.PLAYERS else 4
	f.collision_mask = 7
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.position.y = 0.875
	f.add_child(shape)
	f.position = pos
	_arena.add_child(f)
	if face_toward != Vector3.INF:
		var d := face_toward - pos
		f.rotation.y = atan2(-d.x, -d.z)
	return f


func _wait(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in frames:
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


# --- Tests -----------------------------------------------------------------------------

func test_jab_hits_and_lunges() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -4))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -3.5))
	await _wait(0.1)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"jab")
	_check(p.state == Fighter.State.WINDUP, "jab starts a windup")
	_check(p.target == e, "freeflow picks the enemy in front")
	await _wait(0.6)
	_check(hits.size() == 1, "jab landed once after lunging (got %d)" % hits.size())
	_check(is_equal_approx(e.hp, e.max_hp - 5.0), "jab did 5 damage (hp %.1f)" % e.hp)
	_check(p.global_position.distance_to(e.global_position) < 2.0, "player lunged to the enemy")


func test_held_takes_bonus_damage() -> void:
	var holder := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var mate := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, -2.6), Vector3(0, 0, 0))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	await _wait(0.1)
	holder.request_grab()
	_check(holder.state == Fighter.State.GRABBING and e.state == Fighter.State.HELD, "grab holds")
	_check(e.held_by == holder and holder.holding == e, "grab links holder and victim")
	await _wait(0.1)
	mate.request_attack(&"cross", e)
	await _wait(0.5)
	_check(is_equal_approx(e.hp, e.max_hp - 7.0 * Moves.HELD_DAMAGE_MULT),
		"held victim takes bonus damage (hp %.1f)" % e.hp)
	_check(e.state == Fighter.State.HELD, "a light hit doesn't free the held victim")
	holder.request_attack(&"jab")  # becomes a knee
	await _wait(0.1)
	_check(e.hp < e.max_hp - 10.5, "holder knees the held victim")


func test_counter() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	var telegraphs := []
	var counters := []
	var tel_cb := func(a, _t, s): telegraphs.append(s)
	var cnt_cb := func(d, a): counters.append([d, a])
	Events.attack_telegraphed.connect(tel_cb)
	Events.attack_countered.connect(cnt_cb)
	e.request_attack(&"swing", p)
	_check(telegraphs.size() == 1, "enemy swing is telegraphed")
	_check(e.is_counterable_by(p), "swing is counterable by its target")
	await _wait(0.1)
	p.request_counter()
	_check(counters.size() == 1, "counter registered")
	_check(e.state == Fighter.State.STAGGER, "countered enemy is staggered")
	await _wait(0.8)
	_check(is_equal_approx(p.hp, p.max_hp), "countered swing never lands")
	_check(e.hp < e.max_hp, "counter hits back")
	Events.attack_telegraphed.disconnect(tel_cb)
	Events.attack_countered.disconnect(cnt_cb)
	# Without a counter the swing lands after the telegraph time.
	await _wait(0.6)
	e.request_attack(&"swing", p)
	await _wait(1.0)
	_check(p.hp < p.max_hp, "uncountered swing lands")


func test_knockdown_crawl_ko() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	await _wait(0.1)
	e.take_hit({"attacker": p, "damage": 10.0, "direction": Vector3.FORWARD, "knockdown": true})
	_check(e.state == Fighter.State.DOWN, "knockdown puts them down")
	await _wait(e.get_up_time + 0.2)
	_check(e.state == Fighter.State.IDLE, "healthy fighter gets up")
	e.hp = e.max_hp * 0.2
	await _wait(0.5)
	e.take_hit({"attacker": p, "damage": 1.0, "direction": Vector3.FORWARD, "knockdown": true})
	await _wait(e.get_up_time + 0.2)
	_check(e.state == Fighter.State.CRAWL, "nearly-out fighter crawls (state %d)" % e.state)
	_check(e.can_be_targeted(), "crawlers can still be targeted")
	e.take_hit({"attacker": p, "damage": 100.0, "direction": Vector3.FORWARD})
	_check(e.state == Fighter.State.KO and e.is_down(), "KO at zero hp")
	_check(not e.can_be_targeted() and e.collision_layer == 0, "KO'd fighter is out of play")


func test_grab_escape_and_throw() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	await _wait(0.1)
	p.request_grab()
	for i in 12:
		e.request_struggle()
	_check(e.state == Fighter.State.STAGGER and p.state == Fighter.State.IDLE, "struggling frees")
	_check(e.held_by == null and p.holding == null, "release clears links")
	await _wait(0.6)
	p.request_grab(e)
	_check(p.state == Fighter.State.GRABBING, "re-grab")
	p.request_throw()
	_check(e.state == Fighter.State.DOWN, "thrown fighter is knocked down")
	_check(p.state == Fighter.State.IDLE, "thrower is free")
	# Hold times out on its own.
	await _wait(e.get_up_time + 0.5)
	p.global_position = e.global_position + Vector3(0, 0, 1.0)
	p.rotation.y = 0.0
	await _wait(0.05)
	p.request_grab(e)
	await _wait(Moves.HOLD_TIME * p.grip + 0.2)
	_check(p.state != Fighter.State.GRABBING, "hold times out")


func test_dodge_iframes() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	await _wait(0.1)
	p.request_dodge(Vector3.RIGHT)
	_check(p.state == Fighter.State.DODGE, "dodge starts")
	_check(not p.can_be_hit(), "dodge has i-frames")
	p.take_hit({"attacker": e, "damage": 10.0, "direction": Vector3.BACK})
	_check(is_equal_approx(p.hp, p.max_hp), "hit during i-frames misses")
	await _wait(0.5)
	_check(p.global_position.x > 1.5, "dodge moves the fighter")
	_check(p.state == Fighter.State.IDLE, "dodge ends")


func test_staff_never_ko() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var s := _fighter(Fighter.Team.STAFF, Vector3(0, 0, -1.0))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, 1.0), Vector3(0, 0, -1))
	await _wait(0.1)
	_check(not p.is_hostile_to(s) and not e.is_hostile_to(s), "staff are nobody's enemy")
	_check(not p.can_hit(s) and not e.can_hit(s), "nobody can hit the staff")
	_check(not s.can_be_grabbed(), "staff can't be grabbed")
	s.take_hit({"attacker": p, "damage": 500.0, "direction": Vector3.FORWARD})
	_check(is_equal_approx(s.hp, s.max_hp) and s.state == Fighter.State.IDLE,
		"take_hit on staff does nothing")
	p.request_attack(&"hook", s)
	await _wait(0.5)
	_check(is_equal_approx(s.hp, s.max_hp), "swinging at the barman passes through him")


func test_no_friendly_fire() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var mate := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, -1.0))
	var police := _fighter(Fighter.Team.POLICE, Vector3(3, 0, 0))
	var punter := _fighter(Fighter.Team.PUNTERS, Vector3(-3, 0, 0))
	await _wait(0.1)
	p.request_attack(&"hook", mate)
	await _wait(0.5)
	_check(is_equal_approx(mate.hp, mate.max_hp), "no friendly fire")
	_check(not police.is_hostile_to(punter), "police and punters are on the same side")
	_check(police.is_hostile_to(p), "police are hostile to players")


func test_heal_gets_up_from_crawl() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0))
	await _wait(0.1)
	p.hp = 10.0
	p.take_hit({"attacker": null, "damage": 1.0, "direction": Vector3.FORWARD, "knockdown": true})
	await _wait(p.get_up_time + 0.2)
	_check(p.state == Fighter.State.CRAWL, "player crawls when nearly out")
	p.heal(50.0)
	_check(p.state == Fighter.State.IDLE and is_equal_approx(p.hp, 59.0), "a pint gets you up")


func test_ground_moves() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	await _wait(0.1)
	e.take_hit({"attacker": p, "damage": 1.0, "direction": Vector3.FORWARD, "knockdown": true})
	var before := e.hp
	p.request_attack(&"jab", e)
	await _wait(0.4)
	_check(is_equal_approx(e.hp, before), "punches miss fighters on the floor")
	p.request_attack(&"stomp")
	_check(p.target == e, "stomp targets the downed fighter")
	await _wait(0.5)
	_check(e.hp < before, "stomp hits the floor")


class FakeChair extends Node:
	var hits := 0
	func modify_move(m: Dictionary) -> Dictionary:
		m["damage"] = float(m["damage"]) * 3.0
		m["sweep"] = true
		m["arc"] = 140.0
		return m
	func on_hit(_info: Dictionary) -> void:
		hits += 1


func test_weapon_hooks() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var a := _fighter(Fighter.Team.PUNTERS, Vector3(-0.4, 0, -0.9))
	var b := _fighter(Fighter.Team.PUNTERS, Vector3(0.4, 0, -0.9))
	await _wait(0.1)
	var chair := FakeChair.new()
	_arena.add_child(chair)
	p.equip(chair)
	p.request_attack(&"jab")
	await _wait(0.5)
	_check(chair.hits == 2, "sweeping weapon hits both (got %d)" % chair.hits)
	_check(is_equal_approx(a.hp, a.max_hp - 15.0), "weapon modifies damage (hp %.1f)" % a.hp)
	_check(p.unequip() == chair and p.weapon == null, "unequip returns the item")


func _player(pos: Vector3, face_toward := Vector3.INF) -> PlayerFighter:
	return _fighter(Fighter.Team.PLAYERS, pos, face_toward, PlayerFighter) as PlayerFighter


func test_player_punch_chain() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1))
	e.toughness = 5.0  # don't fall over mid-test
	await _wait(0.1)
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	for i in 4:
		p._perform(&"punch")
		while not p.can_chain():
			await get_tree().physics_frame
	_check(moves == [&"jab", &"cross", &"hook", &"jab"], "punch chain loops (got %s)" % [moves])
	_check(p.combo == 4, "combo counts hits (got %d)" % p.combo)
	await _wait(0.6 + 0.3)
	p._perform(&"punch")
	_check(moves.back() == &"jab", "chain resets after a pause")


func test_player_finisher_and_combo() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1))
	await _wait(0.1)
	var combos := []
	var cb := func(_pl, c): combos.append(c)
	Events.combo_changed.connect(cb)
	p._set_combo(Moves.FINISHER_COMBO)
	_check(p.finisher_ready(), "finisher ready at the threshold")
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	p._perform(&"punch")
	_check(moves == [Moves.FINISHER_MOVE], "punch becomes the finisher")
	await _wait(0.4)
	_check(e.state == Fighter.State.DOWN, "finisher knocks down")
	_check(not p.finisher_ready(), "finisher is spent")
	e.request_attack(&"shove", p)  # take a hit: combo resets
	await _wait(0.4)
	e.take_hit({"attacker": null, "damage": 0.0, "direction": Vector3.FORWARD})
	p.take_hit({"attacker": e, "damage": 3.0, "direction": Vector3.BACK})
	_check(p.combo == 0, "getting hit resets the combo")
	await _wait(0.1)
	p._set_combo(2)
	await _wait(Moves.COMBO_TIMEOUT + 0.1)
	_check(p.combo == 0, "combo times out")
	_check(combos.size() >= 3, "combo_changed fires")
	Events.combo_changed.disconnect(cb)


func test_player_kick_stomps() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	await _wait(0.1)
	e.take_hit({"attacker": p, "damage": 1.0, "direction": Vector3.FORWARD, "knockdown": true})
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	p._perform(&"kick")
	_check(moves == [&"stomp"], "kick near a downed enemy stomps (got %s)" % [moves])


func test_player_input() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	await _wait(0.1)
	Input.action_press("grab")
	await get_tree().physics_frame
	Input.action_release("grab")
	await _wait(0.05)
	_check(p.state == Fighter.State.GRABBING and e.state == Fighter.State.HELD,
		"grab button holds (state %d)" % p.state)
	Input.action_press("punch")
	await get_tree().physics_frame
	Input.action_release("punch")
	await _wait(0.05)
	_check(e.hp < e.max_hp, "punch while holding knees")
	Input.action_press("throw")
	await get_tree().physics_frame
	Input.action_release("throw")
	await _wait(0.05)
	_check(e.state == Fighter.State.DOWN, "throw button throws")
	Input.action_press("move_right")
	await _wait(0.3)
	Input.action_release("move_right")
	_check(p.global_position.x > 0.5, "stick moves the player")


func test_sparring_punter() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.5), Vector3.INF, SparringPunter) as SparringPunter
	var mate := _fighter(Fighter.Team.PUNTERS, Vector3(1.5, 0, -1.5), Vector3.INF, SparringPunter) as SparringPunter
	var far := _fighter(Fighter.Team.PUNTERS, Vector3(12, 0, 0), Vector3.INF, SparringPunter) as SparringPunter
	await _wait(0.1)
	_check(not e.angry, "punters start calm")
	p.request_attack(&"jab", e)
	await _wait(0.4)
	_check(e.angry and mate.angry, "hitting one angers him and his mate")
	_check(not far.angry, "punters across the room stay calm")
	await _wait(4.0)
	_check(p.hp < p.max_hp, "angry punters fight back")
	# Calm everyone and wait for the player to be back on their feet before grabbing.
	var victim := mate
	e.angry = false
	mate.angry = false
	e.global_position = Vector3(-10, 0, 0)
	var waited := 0.0
	while not (p.can_act() and victim.can_be_grabbed()) and waited < 4.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	p.global_position = victim.global_position + Vector3(0, 0, 1.0)
	p.rotation.y = 0.0
	await _wait(0.05)
	p.request_grab(victim)
	_check(victim.state == Fighter.State.HELD, "can hold a sparring punter")
	await _wait(2.0)
	_check(victim.state == Fighter.State.HELD, "the hold lasts long enough for a mate to get stuck in")
	await _wait(1.5)
	_check(victim.state != Fighter.State.HELD, "held punter struggles free before the grip times out")


func test_sandbox_loads() -> void:
	var sandbox: Node = load("res://scenes/actors/combat_sandbox.tscn").instantiate()
	_arena.add_child(sandbox)
	await _wait(0.5)
	_check(get_tree().get_nodes_in_group("players").size() == 1, "sandbox spawns the player")
	_check(get_tree().get_nodes_in_group("npcs").size() == 4, "sandbox spawns 4 punters")
	Net.leave()


## A 2.5 m gallery over z in [-6, -1], edge facing +Z, optionally railed.
func _gallery(railing: bool, height := 2.5) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(6, 0.3, 5)
	body.add_child(shape)
	body.position = Vector3(0, height - 0.15, -3.5)
	_arena.add_child(body)
	if railing:
		var rail := StaticBody3D.new()
		var rs := CollisionShape3D.new()
		rs.shape = BoxShape3D.new()
		rs.shape.size = Vector3(6, 0.95, 0.1)
		rail.add_child(rs)
		rail.position = Vector3(0, height + 0.475, -1.05)
		_arena.add_child(rail)
	for x in [-1.5, 0.0, 1.5]:
		var m := Marker3D.new()
		m.add_to_group(Ledges.GROUP)
		m.position = Vector3(x, height, -1.3)
		m.set_meta("normal", Vector3(0, 0, 1))
		m.set_meta("drop", height)
		m.set_meta("railing", railing)
		_arena.add_child(m)


func _throw_from_gallery(railing: bool, face := Vector3(0, 0, 1)) -> Array:
	_gallery(railing)
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 2.6, -3.2), Vector3(0, 2.6, -3.2) + face)
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 2.6, -3.2) + face * 0.9)
	await _wait(0.3)
	var events := []
	var cb_off := func(f, _t, r): events.append(["off", f, r])
	var cb_fell := func(f, h): events.append(["fell", f, h])
	Events.fighter_thrown_off_ledge.connect(cb_off)
	Events.fighter_fell.connect(cb_fell)
	p.request_grab(e)
	_check(e.state == Fighter.State.HELD, "grabbed on the gallery")
	await _wait(0.1)
	p.request_throw()
	await _wait(1.5)
	Events.fighter_thrown_off_ledge.disconnect(cb_off)
	Events.fighter_fell.disconnect(cb_fell)
	return [p, e, events]


func test_throw_over_railing() -> void:
	var r: Array = await _throw_from_gallery(true)
	var e: Fighter = r[1]
	var events: Array = r[2]
	_check(e.global_position.y < 0.3, "thrown over the rail to the floor (y %.2f)" % e.global_position.y)
	_check(e.global_position.z > -0.5, "landed beyond the edge (z %.2f)" % e.global_position.z)
	var fall_dmg := (2.5 - Moves.FALL_MIN_HEIGHT) * Moves.FALL_DAMAGE_PER_M
	_check(e.hp <= e.max_hp - 8.0 - fall_dmg + 1.5, "throw plus fall damage (hp %.1f)" % e.hp)
	_check(e.is_down(), "knocked down on landing")
	_check(events.size() >= 2 and events[0][0] == "off" and events[0][2] == true, "thrown-off event, railed")
	_check(events.any(func(ev): return ev[0] == "fell"), "fell event")
	_check(e.collision_mask == 7, "world collision restored after the vault")


func test_throw_off_open_edge() -> void:
	var r: Array = await _throw_from_gallery(false)
	var e: Fighter = r[1]
	var events: Array = r[2]
	_check(e.global_position.y < 0.3, "thrown off the open edge (y %.2f)" % e.global_position.y)
	_check(events.size() >= 1 and events[0][2] == false, "thrown-off event, open edge")
	_check(e.hp < e.max_hp - 8.0, "fall hurts")


func test_throw_away_from_edge() -> void:
	var r: Array = await _throw_from_gallery(true, Vector3(0, 0, -1))
	var e: Fighter = r[1]
	var events: Array = r[2]
	_check(e.global_position.y > 2.0, "throwing away from the edge stays on the gallery")
	_check(events.is_empty(), "no ledge events")


func test_short_drop_no_damage() -> void:
	_gallery(false, 0.6)  # a dais
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0.7, -1.5))
	await _wait(0.2)
	e.move_input = Vector3(0, 0, 1)
	await _wait(1.0)
	e.move_input = Vector3.ZERO
	_check(e.global_position.y < 0.2, "walked off the dais")
	_check(is_equal_approx(e.hp, e.max_hp), "short drops don't hurt")
