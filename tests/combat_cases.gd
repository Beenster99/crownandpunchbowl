extends Node
## Test cases for the Fighter API and core combat rules. Loaded by combat_test.gd once the
## autoloads exist (SceneTree scripts compile before autoloads are registered).

signal finished(failures: int)

var _failures := 0
var _arena: Node3D


func run() -> void:
	GameData.difficulty_index = 1  # Session Ale: multipliers of 1.0
	# Hit-stop runs on real time, and --fixed-fps runs frames much faster than real time,
	# so a hit-stop would slow whole tests down. Combat timing is what's under test here.
	var fx := get_node_or_null("/root/Fx")
	if fx != null and "hit_stop_time_scale" in fx:
		fx.hit_stop_time_scale = 1.0
	var tests := [
		"test_jab_hits_and_lunges", "test_no_snapping_to_far_enemies", "test_held_takes_bonus_damage",
		"test_counter", "test_guard_breakers", "test_stance", "test_defend_prompt_text",
		"test_knockdown_crawl_ko", "test_grab_escape_and_throw", "test_dodge_iframes",
		"test_staff_never_ko", "test_no_friendly_fire", "test_friendly_fire_setting", "test_heal_gets_up_from_crawl",
		"test_ground_moves", "test_weapon_hooks", "test_player_punch_chain",
		"test_player_combos_and_mashing", "test_player_kick_stomps", "test_player_input",
		"test_sparring_punter", "test_sandbox_loads", "test_throw_over_railing",
		"test_throw_off_open_edge", "test_throw_away_from_edge", "test_short_drop_no_damage",
		"test_enemy_windup_is_readable", "test_windup_pose_holds", "test_hit_lean",
		"test_footwork_has_weight", "test_head_and_body_guards", "test_slip",
		"test_groin_kick_combo", "test_shoulder_charge", "test_clinch_knee", "test_hold_resistance",
		"test_hook_knocks_head_sideways", "test_one_punch_doesnt_drop_a_fresh_man",
		"test_punches_can_miss", "test_no_stick_punch_goes_straight", "test_foe_health_bar",
		"test_stamina", "test_jabs_crush_a_guard", "test_body_shots_sap_stamina", "test_power_shot",
		"test_punish_a_miss", "test_player_holds_for_power", "test_clean_shot_into_the_gap",
		"test_perfect_parry", "test_lock_on", "test_set_up_into_the_gap",
		"test_rocked_and_finished", "test_winded_by_body_shots",
	]
	# COMBAT_ONLY=test_a,test_b runs just those.
	var only := OS.get_environment("COMBAT_ONLY")
	if only != "":
		tests = tests.filter(func(t): return t in only.split(","))
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
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.7))
	await _wait(0.1)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"jab")
	_check(p.state == Fighter.State.WINDUP, "jab starts a windup")
	_check(p.target == e, "soft lock picks the enemy in front")
	await _wait(0.6)
	_check(hits.size() == 1, "jab steps in a little and lands (got %d)" % hits.size())
	_check(is_equal_approx(e.hp, e.max_hp - 5.0), "jab did 5 damage (hp %.1f)" % e.hp)


func test_no_snapping_to_far_enemies() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -4))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -3.4))
	await _wait(0.1)
	var start := p.global_position
	p.request_attack(&"jab")
	await _wait(0.6)
	_check(p.global_position.distance_to(start) < 0.3,
		"no lunge across the room (moved %.2f m)" % p.global_position.distance_to(start))
	_check(is_equal_approx(e.hp, e.max_hp), "the punch whiffs: walk in first")
	var far := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -5.0))
	p.request_attack(&"jab")
	_check(p.target != far, "soft lock doesn't reach across the room")


func test_held_takes_bonus_damage() -> void:
	var holder := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var mate := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, -2.4), Vector3(0, 0, 0))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	await _wait(0.1)
	holder.request_grab()
	_check(holder.state == Fighter.State.GRABBING and e.state == Fighter.State.HELD, "grab holds")
	_check(e.held_by == holder and holder.holding == e, "grab links holder and victim")
	await _wait(0.1)
	mate.request_attack(&"cross", e)
	await _wait(0.5)
	_check(is_equal_approx(e.hp, e.max_hp - 9.0 * Moves.HELD_DAMAGE_MULT),
		"held victim takes bonus damage (hp %.1f)" % e.hp)
	_check(e.state == Fighter.State.HELD, "a light hit doesn't free the held victim")
	holder.request_attack(&"jab")  # becomes a knee
	await _wait(0.1)
	_check(e.hp < e.max_hp - 9.0 * Moves.HELD_DAMAGE_MULT - 1.0, "holder knees the held victim")


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
	# Guard up early: the punch is blocked for chip damage.
	p.request_block(true)
	_check(p.state == Fighter.State.BLOCK, "block raises the guard")
	e.request_attack(&"swing", p)
	_check(telegraphs.size() == 1, "enemy swing is telegraphed")
	_check(e.defend_hint() == "guard_head", "a swing is prompted as a head guard")
	await _until_free(e)
	_check(is_equal_approx(p.hp, p.max_hp - 8.0 * Moves.BLOCK_CHIP), "blocked for chip damage (hp %.2f)" % p.hp)
	_check(p.state == Fighter.State.BLOCK, "the guard holds")
	_check(counters.is_empty(), "an early block isn't a parry")
	p.request_block(false)
	_check(p.state == Fighter.State.IDLE, "guard down")
	# Raise it just as the punch lands: a parry, and the next punch is a counter.
	var before := p.hp
	e.request_attack(&"swing", p)
	await _wait(e.windup_remaining() - 0.08)
	p.request_block(true)
	await _wait(0.2)
	_check(is_equal_approx(p.hp, before), "parried punch does nothing (hp %.2f)" % p.hp)
	_check(counters.size() == 1, "parry registered")
	_check(e.state == Fighter.State.STAGGER, "parried enemy reels")
	_check(p.has_counter_ready(), "counter ready after a parry")
	p.request_attack(&"cross", e)
	await _wait(0.4)
	_check(is_equal_approx(e.hp, e.max_hp - 9.0 * Moves.COUNTER_BONUS),
		"counter hits harder (hp %.1f)" % e.hp)
	Events.attack_telegraphed.disconnect(tel_cb)
	Events.attack_countered.disconnect(cnt_cb)
	# Without a guard the swing lands.
	await _until_free(e)
	before = p.hp
	e.request_attack(&"swing", p)
	await _wait(e.windup_remaining() + 0.2)
	_check(p.hp < before, "unguarded swing lands")


func test_guard_breakers() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	var broken := []
	var cb := func(d, _a): broken.append(d)
	Events.guard_broken.connect(cb)
	p.request_block(true)
	e.request_attack(&"haymaker", p)
	_check(e.defend_hint() == "dodge", "a haymaker is prompted as dodge")
	await _wait(e.windup_remaining() + 0.2)
	_check(broken.size() == 1, "haymaker breaks the guard")
	_check(p.hp < p.max_hp - 5.0, "guard break hurts (hp %.1f)" % p.hp)
	Events.guard_broken.disconnect(cb)
	await _until_free(e)
	await _until_free(p)
	# Dodging it works.
	var before := p.hp
	p.request_block(false)
	e.request_attack(&"haymaker", p)
	await _wait(e.windup_remaining() - 0.1)
	p.request_dodge(Vector3.RIGHT)
	await _wait(0.5)
	_check(is_equal_approx(p.hp, before), "dodged the haymaker")
	# A block only covers the front.
	await _wait(1.0)
	p.request_block(true)
	_check(p.is_blocking_from(p.global_position + p.get_facing()), "a block covers the front")
	_check(not p.is_blocking_from(p.global_position - p.get_facing()), "a block doesn't cover your back")


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
	GameData.friendly_fire = false
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


func test_friendly_fire_setting() -> void:
	GameData.friendly_fire = true
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var mate := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, -1.0))
	var s := _fighter(Fighter.Team.STAFF, Vector3(1.0, 0, 0))
	var a := _fighter(Fighter.Team.PUNTERS, Vector3(-3, 0, 0))
	var b := _fighter(Fighter.Team.PUNTERS, Vector3(-3, 0, -1))
	await _wait(0.1)
	_check(p.can_hit(mate) and mate.can_hit(p), "friendly fire on: players can hit each other")
	_check(not p.is_hostile_to(mate), "a mate still isn't an enemy for the AI")
	_check(not p.can_hit(s), "friendly fire still never reaches the bar staff")
	_check(not a.can_hit(b), "punters still don't hit each other")
	_check(Targeting.pick(p, Vector3(0, 0, -1)) == mate, "aiming at a mate picks them when nobody else is about")
	p.request_attack(&"hook", mate)
	await _wait(0.6)
	_check(mate.hp < mate.max_hp, "friendly fire on: the hook lands on a mate (hp %.1f)" % mate.hp)
	# With an enemy just as close, grabbing goes for the enemy.
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0.4, 0, -1.0))
	await _wait(0.6)
	p.rotation.y = 0.0
	_check(Targeting.grab_candidate(p) == e, "grab prefers the enemy over a mate")
	GameData.friendly_fire = false
	_check(not p.can_hit(mate), "friendly fire off again")


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


func _tap(p: PlayerFighter, b: StringName, lb := false, rb := false) -> void:
	p.button(b, lb, rb)
	await get_tree().physics_frame


## Waits until `f` is free to act again (its attack or stagger is over).
func _until_free(f: Fighter) -> void:
	var n := 0
	while f.state != Fighter.State.IDLE and f.state != Fighter.State.BLOCK and n < 300:
		await get_tree().physics_frame
		n += 1


func _until_chain(p: PlayerFighter) -> void:
	var n := 0
	while not p.can_chain() and n < 120:
		await get_tree().physics_frame
		n += 1


func test_player_punch_chain() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1))
	e.toughness = 5.0  # don't fall over mid-test
	await _wait(0.1)
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	await _tap(p, &"jab")
	await _wait(0.8)
	await _tap(p, &"hook")
	await _wait(0.8)
	await _tap(p, &"uppercut")
	await _wait(0.8)
	await _tap(p, &"jab", false, true)
	await _wait(0.8)
	await _tap(p, &"hook", false, true)
	await _wait(0.8)
	p.press(&"headbutt")
	await _wait(0.8)
	_check(moves == [&"jab", &"hook", &"uppercut", &"body_jab", &"body_hook", &"headbutt"],
		"X/B/Y punch, RB sends them to the body, R3 headbutts (got %s)" % [moves])
	_check(p.combo == 6, "combo counts hits (got %d)" % p.combo)
	moves.clear()
	p.button(&"jab", false, false, true)
	await _wait(0.8)
	_check(moves == [&"body_jab"], "ducking (right stick down) and punching goes to the body (%s)" % [moves])
	moves.clear()
	await _tap(p, &"jab", true)
	await _wait(1.0)
	await _tap(p, &"hook", true)
	await _wait(1.0)
	await _tap(p, &"uppercut", true)
	await _wait(1.2)
	_check(moves == [&"kick", &"clinch_knee", &"shoulder_charge"],
		"LB + X/B/Y: kick, clinch knee, shoulder charge (got %s)" % [moves])


func test_player_combos_and_mashing() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1))
	e.toughness = 5.0
	e.max_hp = 500.0
	e.hp = 500.0
	await _wait(0.1)
	var combos := []
	var cb := func(_f, n): combos.append(n)
	Events.combo_performed.connect(cb)
	# In rhythm: jab, jab, hook, uppercut.
	await _tap(p, &"jab")
	await _until_chain(p)
	await _tap(p, &"jab")
	await _until_chain(p)
	await _tap(p, &"hook")
	await _until_chain(p)
	await _tap(p, &"uppercut")
	await _wait(0.9)
	_check(combos == ["Double jab, hook", "The Full English"],
		"rhythm strings are combos (got %s)" % [combos])
	# He's too tough to reel, so the finishers don't go in clean: half the combo bonus.
	var half := Moves.COMBO_UNCLEAN_SHARE
	var expected := 500.0 - 5.0 - 5.0 - 11.0 * (1.0 + 0.3 * half) - 14.0 * (1.0 + 0.7 * half)
	_check(absf(e.hp - expected) < 0.01, "combos hit harder (hp %.2f, want %.2f)" % [e.hp, expected])
	# Out of rhythm: no combo.
	combos.clear()
	await _wait(2.5)
	await _tap(p, &"jab")
	await _wait(1.4)
	await _tap(p, &"hook")
	await _wait(0.8)
	_check(combos.is_empty(), "a slow jab, hook isn't a combo")
	# Mashing during a punch fumbles: the extra presses are lost.
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	await _wait(1.0)
	await _tap(p, &"hook")
	for i in 4:
		await _tap(p, &"jab")
	_check(p._fumble_t > 0.0 and p._history.is_empty(), "mashing fumbles the string")
	await _wait(0.9)
	_check(moves == [&"hook"], "mashed presses are dropped (got %s)" % [moves])
	Events.combo_performed.disconnect(cb)
	# Combo counter resets when you're hit, and times out.
	p._set_combo(3)
	p.take_hit({"attacker": e, "damage": 3.0, "direction": Vector3.BACK})
	_check(p.combo == 0, "getting hit resets the combo")
	await _wait(0.6)
	p._set_combo(2)
	await _wait(Moves.COMBO_TIMEOUT + 0.1)
	_check(p.combo == 0, "combo times out")


func test_stance() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -2.5), Vector3(0, 0, 0))
	await _wait(0.2)
	_check(not p.in_stance, "no stance near a calm punter")
	e.request_attack(&"shove", p)
	await _wait(0.05)
	_check(p.in_stance and p.stance_target == e, "an attacking punter puts you in a stance")
	await _wait(1.0)
	Input.action_press("move_right")
	await _wait(0.5)
	Input.action_release("move_right")
	var to := e.global_position - p.global_position
	to.y = 0.0
	_check(p.get_facing().angle_to(to.normalized()) < deg_to_rad(25.0), "footwork keeps you facing the foe")
	_check(p.global_position.x > 0.5, "you can still move round them")
	await _wait(Moves.STANCE_HOLD + 0.5)
	_check(not p.in_stance, "stance relaxes when the exchange is over")


func test_defend_prompt_text() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	var prompts: Node = load("res://scripts/combat/defend_prompts.gd").new()
	prompts.player = p
	p.add_child(prompts)
	await _wait(0.1)
	prompts.device = "kb"
	var kb: String = prompts.prompt_text("guard_head")
	_check(kb.ends_with("BLOCK HIGH") and kb.contains(Settings.action_label("guard_head", "kb")),
		"kb head guard prompt: " + kb)
	_check(prompts.prompt_text("guard_body").ends_with("BLOCK LOW"), "body guard prompt")
	if not Settings.has_method("prompt"):
		prompts.device = "pad"
		_check(prompts.prompt_text("dodge") == "%s  DODGE" % Settings.action_label("dodge", "pad"),
			"pad dodge prompt: " + prompts.prompt_text("dodge"))
	e.request_attack(&"haymaker", p)
	await _wait(0.05)
	var label := p.get_children().filter(func(c): return c is Label3D)
	_check(label.size() == 1 and (label[0] as Label3D).text.ends_with("DODGE"),
		"one prompt under the player")
	_check(label.size() == 1 and (label[0] as Label3D).font_size <= 24, "and it's small")
	_check(e.get_children().filter(func(c): return c is Label3D).is_empty(), "nothing over the attacker")


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
	Input.action_press("guard_head")
	Input.action_press("guard_body")
	await get_tree().physics_frame
	Input.action_release("guard_head")
	Input.action_release("guard_body")
	await _wait(0.05)
	_check(p.state == Fighter.State.GRABBING and e.state == Fighter.State.HELD,
		"LB + RB holds (state %d)" % p.state)
	Input.action_press("jab")
	await get_tree().physics_frame
	Input.action_release("jab")
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
	Input.action_press("guard_head")
	await _wait(0.05)
	_check(p.state == Fighter.State.BLOCK and p.guard_zone == Moves.GUARD_HEAD,
		"holding LB raises the head guard")
	Input.action_release("guard_head")
	await _wait(0.05)
	_check(p.state == Fighter.State.IDLE, "letting go drops it")
	Input.action_press("guard_body")
	await _wait(0.05)
	_check(p.state == Fighter.State.BLOCK and p.guard_zone == Moves.GUARD_BODY,
		"holding RB raises the body guard")
	Input.action_release("guard_body")
	await _wait(0.05)
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	Input.action_press("hook")
	await _wait(0.05)
	Input.action_release("hook")
	await _wait(0.05)
	_check(moves == [&"hook"], "B throws a hook (got %s)" % [moves])
	await _until_free(p)
	moves.clear()
	Input.action_press("uppercut")
	await get_tree().physics_frame
	Input.action_release("uppercut")
	await _wait(0.05)
	_check(moves == [&"uppercut"], "the uppercut button throws an uppercut (got %s)" % [moves])


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


func test_enemy_windup_is_readable() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	e.request_attack(&"swing", p)
	var tt := float(GameData.difficulty()["telegraph_time"])
	_check(is_equal_approx(e.windup_remaining(), tt * Moves.ENEMY_WINDUP_SCALE),
		"enemy tells are stretched (%.2f)" % e.windup_remaining())
	e.request_attack(&"haymaker", p)  # ignored: already winding up
	_check(e.current_move == &"swing", "can't restart a wind-up")
	await _until_free(e)
	e.request_attack(&"haymaker", p)
	_check(e.windup_remaining() > tt * Moves.ENEMY_WINDUP_SCALE * 1.4,
		"a haymaker is lined up for longer than a swing")


func test_windup_pose_holds() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	var vis := FighterVisual.attach(e)
	await _wait(0.1)
	var rig := vis.rig
	e.request_attack(&"swing", p)
	await _wait(e.windup_remaining() * 0.85)
	_check(e.state == Fighter.State.WINDUP, "still lining it up")
	_check(rig.anim.speed_scale == 0.0, "the loaded pose holds until the punch comes")
	var lead := rig.current
	await _wait(e.windup_remaining() + 0.05)
	_check(e.state == Fighter.State.ATTACK, "then it lands")
	_check(rig.anim.speed_scale == 1.0 and rig.current == lead, "and the strike is thrown (%s)" % rig.current)
	_check(vis.lean.lean_angle() > 0.01 or e.velocity.length() > 0.1, "the body goes into the punch")


func test_hit_lean() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1), Vector3(0, 0, 0))
	e.toughness = 5.0
	var vis := FighterVisual.attach(e)
	await _wait(0.1)
	p.request_attack(&"hook", e)
	var peak := 0.0
	for i in 30:
		await get_tree().physics_frame
		await get_tree().process_frame
		peak = maxf(peak, vis.lean.lean_angle())
	_check(peak > 0.1, "a hook rocks the victim (%.2f rad)" % peak)
	# The rig is pushed away from the attacker: its head goes back along -Z (towards +Z world).
	await _wait(1.5)
	_check(vis.lean.lean_angle() < 0.01, "and they settle back up (%.3f)" % vis.lean.lean_angle())
	_check(vis.rig.transform.is_equal_approx(Transform3D.IDENTITY), "rig back at rest")


func test_footwork_has_weight() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0))
	await _wait(0.1)
	p.move_input = Vector3(1, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(p.velocity.length() < p.move_speed * 0.6, "you don't hit full speed at once (%.2f)" % p.velocity.length())
	await _wait(0.6)
	_check(is_equal_approx(p.velocity.length(), p.move_speed), "then you're up to speed")
	p.move_input = Vector3.ZERO
	await get_tree().physics_frame
	_check(p.velocity.length() > 0.5, "and you slow down over a moment")
	await _wait(0.6)
	_check(p.velocity.length() < 0.01, "then stop")


# --- Head and body, slips, the shoulder-button moves -----------------------------------

func test_head_and_body_guards() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	# A body guard doesn't cover the head.
	e.request_block(true, Moves.GUARD_BODY)
	await _wait(0.4)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and not bool(hits[0].get("blocked", false)) \
		and hits[0]["zone"] == &"head", "a jab gets over a body guard")
	# But it does stop a body shot. (The jab knocked the guard down: put it back up.)
	await _until_free(e)
	e.request_block(true, Moves.GUARD_BODY)
	await _wait(0.4)
	hits.clear()
	p.request_attack(&"body_hook", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("blocked", false)), "a body guard stops a body hook")
	# Switch to the head guard: now body shots get in under it.
	e.request_block(true, Moves.GUARD_HEAD)
	_check(e.state == Fighter.State.BLOCK and e.guard_zone == Moves.GUARD_HEAD, "guards switch")
	await _wait(0.4)
	hits.clear()
	p.request_attack(&"body_jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and not bool(hits[0].get("blocked", false)) \
		and hits[0]["zone"] == &"body", "a body jab gets under a head guard")
	await _until_free(e)
	e.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.4)
	hits.clear()
	p.request_attack(&"jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("blocked", false)), "a head guard stops a jab")
	# Enemy body shots ask for the body guard.
	e.request_block(false)
	await _wait(0.1)
	e.request_attack(&"body_swing", p)
	_check(e.defend_hint() == "guard_body", "a punter's body shot is prompted as a low block")


func test_slip() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	var counters := []
	var cb := func(d, _a): counters.append(d)
	Events.attack_countered.connect(cb)
	# Slip early: it misses, but there's no counter.
	e.request_attack(&"swing", p)
	await _wait(e.windup_remaining() - Moves.SLIP_WINDOW + 0.08)
	p.request_slip(Vector2(1, 0))
	_check(p.is_slipping(), "a flick of the right stick slips")
	await _until_free(e)
	_check(is_equal_approx(p.hp, p.max_hp), "a slipped swing misses (hp %.1f)" % p.hp)
	_check(counters.is_empty(), "an early slip isn't a counter")
	# Slip right as it lands: a counter.
	await _wait(0.6)
	e.request_attack(&"swing", p)
	await _wait(e.windup_remaining() - 0.1)
	p.request_slip(Vector2(-1, 0))
	await _wait(0.2)
	_check(is_equal_approx(p.hp, p.max_hp), "a late slip misses too")
	_check(counters.size() == 1 and p.has_counter_ready(), "slipping it late sets up a counter")
	Events.attack_countered.disconnect(cb)
	# Body shots can't be slipped.
	await _until_free(e)
	await _wait(0.6)
	e.request_attack(&"body_swing", p)
	await _wait(e.windup_remaining() - 0.1)
	p.request_slip(Vector2(0, 1))
	await _wait(0.2)
	_check(p.hp < p.max_hp, "a body shot still lands on a slipping man")


func test_groin_kick_combo() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	await _wait(0.1)
	var combos := []
	var cb := func(_f, n): combos.append(n)
	Events.combo_performed.connect(cb)
	var moves := []
	p.move_started.connect(func(m): moves.append(m))
	await _tap(p, &"jab")
	await _until_chain(p)
	await _tap(p, &"jab", false, true)
	await _until_chain(p)
	await _tap(p, &"jab", true)
	await _wait(0.5)
	Events.combo_performed.disconnect(cb)
	_check(moves == [&"jab", &"body_jab", &"groin_kick"], "jab, body jab, kick goes low (got %s)" % [moves])
	_check(combos.has("Below the belt"), "and it's a combo (got %s)" % [combos])
	_check(e.state == Fighter.State.DOUBLED, "they go down on all fours holding it (state %d)" % e.state)
	# Or straight off: LB + X with the stick pulled back.
	await _wait(Moves.DOUBLED_TIME + 1.0)
	moves.clear()
	p.move_input = Vector3(0, 0, 1)  # facing -z: pulling back
	await _tap(p, &"jab", true)
	p.move_input = Vector3.ZERO
	await _wait(0.6)
	_check(moves == [&"groin_kick"], "LB + X, stick back, is the groin kick (got %s)" % [moves])
	_check(not e.is_down() and e.can_be_grabbed(), "doubled over, they can still be hit and held")
	await _wait(Moves.DOUBLED_TIME + 0.3)
	_check(e.state == Fighter.State.IDLE, "and get back up after a while (state %d)" % e.state)


func test_shoulder_charge() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -2.6))
	await _wait(0.1)
	var start_e := e.global_position
	p.request_block(false)
	e.request_block(true)
	await _wait(0.1)
	p.request_attack(&"shoulder_charge", e)
	await _wait(0.9)
	_check(e.state == Fighter.State.DOWN, "a shoulder charge runs them over, guard or not (state %d)" % e.state)
	_check(e.global_position.distance_to(start_e) > 1.0,
		"and sends them flying (%.2f m)" % e.global_position.distance_to(start_e))
	_check(p.global_position.z < -0.8, "the charger drives forward (z %.2f)" % p.global_position.z)


func test_clinch_knee() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0), Vector3(0, 0, 0))
	await _wait(0.1)
	e.request_block(true)
	await _wait(0.4)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"clinch_knee", e)
	await _wait(0.5)
	_check(hits.size() == 1 and bool(hits[0]["clinch"]) and not bool(hits[0].get("blocked", false)),
		"the clinch knee drags the guard down and lands")
	_check(e.hp < e.max_hp - 10.0, "and it hurts (hp %.1f)" % e.hp)


func test_hold_resistance() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var easy := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	await _wait(0.1)
	p.request_grab(easy)
	_check(easy.state == Fighter.State.HELD, "a soft lad is easy to hold")
	p.request_release()
	await _wait(0.8)
	easy.global_position = Vector3(20, 0, 0)
	var hard := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.0))
	hard.hold_resist = 1.0
	await _wait(0.1)
	var shrugs := []
	var cb := func(_h, v): shrugs.append(v)
	Events.grab_shrugged.connect(cb)
	p.request_grab(hard)
	Events.grab_shrugged.disconnect(cb)
	_check(hard.state != Fighter.State.HELD and shrugs.size() == 1, "a strong man shrugs the grab off")
	_check(p.state == Fighter.State.STAGGER, "and the would-be holder stumbles")
	# A resisting man also wriggles free faster.
	var a := _fighter(Fighter.Team.PLAYERS, Vector3(5, 0, 0), Vector3(5, 0, -1))
	var b := _fighter(Fighter.Team.PUNTERS, Vector3(5, 0, -1.0))
	await _wait(0.1)
	a.request_grab(b)
	b.hold_resist = 0.5
	var n := 0
	while b.state == Fighter.State.HELD and n < 50:
		b.request_struggle()
		n += 1
	_check(n < int(1.0 / Moves.ESCAPE_PER_STRUGGLE), "resist speeds up the escape (%d struggles)" % n)


func test_hook_knocks_head_sideways() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1), Vector3(0, 0, 0))
	e.toughness = 5.0
	var vis := FighterVisual.attach(e)
	await _wait(0.1)
	var hits := []
	e.hit_taken.connect(func(info): hits.append(info))
	p.request_attack(&"jab", e)
	await _until_free(p)
	var jab_dir: Vector3 = hits[0]["direction"]
	_check(absf(jab_dir.x) < 0.1, "a jab pushes straight back (%s)" % jab_dir)
	p.request_attack(&"hook", e)
	var peak := 0.0
	for i in 30:
		await get_tree().physics_frame
		await get_tree().process_frame
		if vis.snap != null:
			peak = maxf(peak, vis.snap.snap_angle())
	var hook_dir: Vector3 = hits[1]["direction"]
	# The player faces -Z, so their right is +X; a right hook knocks the head to -X.
	_check(hook_dir.x < -0.4, "a right hook knocks the head sideways (%s)" % hook_dir)
	if vis.snap == null:
		return  # the characters' RigReactor does the head snap (tested there)
	_check(peak > 0.15, "the head snaps on the hit (%.2f rad)" % peak)
	await _wait(1.5)
	_check(vis.snap.snap_angle() < 0.02, "then settles (%.3f)" % vis.snap.snap_angle())


func test_one_punch_doesnt_drop_a_fresh_man() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.1), Vector3(0, 0, 0))
	await _wait(0.1)
	p.request_attack(&"uppercut", e)
	await _until_free(p)
	_check(e.state != Fighter.State.DOWN, "a fresh man stays up after an uppercut (state %d)" % e.state)
	p.request_attack(&"headbutt", e)
	await _until_free(p)
	_check(e.state != Fighter.State.DOWN, "and after a headbutt")
	# A sustained beating does put him down.
	var downed := false
	for i in 8:
		p.request_attack(&"hook", e)
		await _until_free(p)
		if e.state == Fighter.State.DOWN:
			downed = true
			break
	_check(downed, "a good beating still drops him")


func test_punches_can_miss() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.25), Vector3(0, 0, 0))
	await _wait(0.1)
	var whiffs := []
	var cb := func(a, _m): whiffs.append(a)
	Events.attack_whiffed.connect(cb)
	p.request_attack(&"hook", e)
	# He steps back out of it while it's being thrown.
	e.global_position = Vector3(0, 0, -2.6)
	await _until_free(p)
	Events.attack_whiffed.disconnect(cb)
	_check(is_equal_approx(e.hp, e.max_hp), "a punch at a man who stepped away misses (hp %.1f)" % e.hp)
	_check(whiffs == [p], "and it's a whiff (%s)" % [whiffs])


func test_no_stick_punch_goes_straight() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var side := _fighter(Fighter.Team.PUNTERS, Vector3(-1.0, 0, -0.5))
	await _wait(0.1)
	p.move_input = Vector3.ZERO
	_check(Targeting.pick(p, Vector3.ZERO) == null, "no stick: a man at your shoulder isn't picked")
	var start := p.rotation.y
	p.button(&"jab")
	await _until_free(p)
	_check(absf(angle_difference(start, p.rotation.y)) < 0.05,
		"a jab with the stick centred goes straight (%.2f rad)" % angle_difference(start, p.rotation.y))
	var ahead := _fighter(Fighter.Team.PUNTERS, Vector3(0.3, 0, -1.4))
	await _wait(0.1)
	_check(Targeting.pick(p, Vector3.ZERO) == ahead, "the man in front is")
	# Squared up to the man in front, a second one arriving at your shoulder doesn't spin you.
	ahead.request_attack(&"shove", p)
	await _wait(0.3)
	_check(p.stance_target == ahead, "squared up to the man in front")
	side.request_attack(&"shove", p)
	await _wait(0.1)
	_check(p.stance_target == ahead, "and you stay on him when another starts at your side")


func test_foe_health_bar() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.5), Vector3(0, 0, 0))
	var bars := FoeHealthBars.new()
	bars.player = p
	p.add_child(bars)
	await _wait(0.1)
	_check(bars.bar_for(e) == null, "no bar on a punter you're not fighting")
	e.request_attack(&"swing", p)
	await _wait(0.6)
	_check(bars.bar_for(e) != null and bars.bar_for(e).get_parent() == e, "a bar under the man you're fighting")
	_check(bars.bar_for(e) != null and bars.bar_for(e).position.y < 0.2, "on the floor, under him")


func test_stamina() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	_check(is_equal_approx(p.stamina, p.max_stamina), "fighters start with a full tank")
	p.request_attack(&"jab", e)
	_check(is_equal_approx(p.stamina, p.max_stamina - 6.0), "a jab costs 6 (%.1f)" % p.stamina)
	await _until_free(p)
	# A miss costs double.
	var before := p.stamina
	e.global_position = Vector3(0, 0, -4.0)
	p.request_attack(&"hook", e)
	await _until_free(p)
	_check(p.stamina <= before - 26.0 + 0.5, "a missed hook costs double (%.1f -> %.1f)" % [before, p.stamina])
	# It comes back once you stop throwing.
	var low := p.stamina
	await _wait(1.5)
	_check(p.stamina > low + 10.0, "stamina comes back with a breather (%.1f -> %.1f)" % [low, p.stamina])
	# Gassed: soft punches.
	e.global_position = Vector3(0, 0, -1.2)
	await _until_free(e)
	p.stamina = 5.0
	_check(p.is_gassed(), "under a quarter is gassed")
	var hp := e.hp
	p.request_attack(&"jab", e)
	await _until_free(p)
	_check(is_equal_approx(hp - e.hp, 5.0 * Moves.GASSED_DAMAGE),
		"a gassed jab hits soft (%.2f)" % (hp - e.hp))


func test_jabs_crush_a_guard() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	e.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.4)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("blocked", false)), "the jab hits the guard")
	_check(e.stamina < e.max_stamina - 12.0, "and drains it more than it cost (%.1f)" % e.stamina)
	# Run his tank down: the next one smashes the guard apart.
	e.stamina = 5.0
	hits.clear()
	p.request_attack(&"jab", e)
	await _wait(0.25)
	_check(hits.size() == 1 and bool(hits[0].get("guard_crushed", false)) \
		and not bool(hits[0].get("blocked", false)), "an empty guard is crushed")
	_check(e.state == Fighter.State.STAGGER, "and he reels, open (%s)" % Fighter.State.keys()[e.state])


func test_body_shots_sap_stamina() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	p.request_attack(&"body_hook", e)
	await _until_free(p)
	_check(e.stamina <= e.max_stamina - 8.0 * Moves.BODY_SHOT_DRAIN + 0.5,
		"a body hook takes the wind out of him (%.1f)" % e.stamina)


func test_power_shot() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	e.max_hp = 500.0
	e.hp = 500.0
	await _wait(0.1)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	# A quick tap is a normal hook.
	p.request_attack(&"hook", e, 1.0, "", true)
	p.request_unleash()
	await _until_free(p)
	_check(hits.size() == 1 and is_equal_approx(float(hits[0]["damage"]), 11.0),
		"a tapped hook is a normal hook (%s)" % [hits[0]["damage"] if hits else "none"])
	await _until_free(e)
	await _wait(1.0)
	# Held: it loads, the fighter stays coiled, and let go at full it lands at full power
	# and goes through a guard.
	e.request_block(true, Moves.GUARD_HEAD)
	hits.clear()
	p.request_attack(&"hook", e, 1.0, "", true)
	await _wait(0.6)
	_check(p.state == Fighter.State.WINDUP and p.is_charging(), "holding it loads a power shot")
	await _wait(0.55)
	_check(p.charge_fraction() >= 0.99, "fully loaded (%.2f)" % p.charge_fraction())
	p.request_unleash()
	await _until_free(p)
	_check(hits.size() == 1 and not bool(hits[0].get("blocked", false)) \
		and float(hits[0].get("power", 0.0)) >= 0.95, "full power goes through the guard")
	if hits.size() == 1:
		_check(float(hits[0]["damage"]) > 11.0 * 0.6 * 1.5,
			"and hits much harder (%.1f)" % float(hits[0]["damage"]))
	# Held too long, it goes on its own.
	await _until_free(e)
	await _wait(1.0)
	hits.clear()
	p.request_attack(&"uppercut", e, 1.0, "", true)
	await _wait(Moves.CHARGE_TIME + Moves.CHARGE_HOLD + 0.6)
	_check(hits.size() == 1, "a power shot held too long goes by itself")
	# A jab in the face while loading cancels it.
	await _until_free(e)
	await _until_free(p)
	await _wait(1.0)
	hits.clear()
	p.request_attack(&"hook", e, 1.0, "", true)
	await _wait(0.5)
	e.request_attack(&"jab", p)
	await _wait(0.3)
	_check(not p.is_charging() and p.state != Fighter.State.WINDUP and p.state != Fighter.State.ATTACK,
		"a jab while loading knocks the power shot out of him (%s)" % Fighter.State.keys()[p.state])
	await _wait(0.6)
	_check(hits.is_empty(), "and it never lands")


func test_punish_a_miss() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	# He swings at thin air (we're stood off to the side of it).
	p.global_position = Vector3(3.0, 0, 0)
	e.request_attack(&"hook")
	await _wait(0.1)
	while e.state == Fighter.State.WINDUP:
		await get_tree().physics_frame
	await _wait(0.12)
	_check(e.state == Fighter.State.ATTACK, "he's recovering from the miss")
	p.global_position = Vector3(0, 0, 0)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	var hp := e.hp
	p.request_attack(&"jab", e)
	await _wait(0.2)
	_check(hits.size() == 1 and bool(hits[0].get("punish", false)), "catching him recovering is a punish")
	_check(is_equal_approx(hp - e.hp, 5.0 * Moves.PUNISH_BONUS), "and hits harder (%.2f)" % (hp - e.hp))


func test_player_holds_for_power() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	await _wait(0.1)
	_check(p.button(&"hook", false, false, false, true), "a held hook button loads a power shot")
	await _wait(0.6)
	_check(p.is_charging(), "and the fighter is coiled")
	p.release_power()
	await _wait(0.1)
	_check(p.state == Fighter.State.ATTACK, "letting go throws it")
	await _until_free(p)
	_check(not p.button(&"jab", false, false, false, true), "jabs don't load: they're quick")


func test_clean_shot_into_the_gap() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	var bars := FoeHealthBars.new()
	bars.player = p
	p.add_child(bars)
	await _wait(0.1)
	_check(e.open_zone() == &"", "a man just stood there shows nothing")
	e.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.4)
	_check(e.open_zone() == Moves.GUARD_BODY, "covering up high leaves the body open")
	p.stance_target = e
	await _wait(0.1)
	var bar := bars.bar_for(e)
	var word := bar.get_node_or_null("Opening") as Label3D if bar != null else null
	_check(word != null and word.text == "BODY OPEN", "the bar says where he's open (%s)" % [word.text if word else "none"])
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	var hp := e.hp
	p.request_attack(&"body_jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("opening", false)) and not bool(hits[0].get("blocked", false)),
		"a body shot under a high guard is a clean shot")
	_check(is_equal_approx(hp - e.hp, 4.0 * Moves.CLEAN_BONUS), "and hits harder (%.2f)" % (hp - e.hp))
	# The same shot into the guard is just blocked.
	await _until_free(e)
	e.request_block(true, Moves.GUARD_BODY)
	await _wait(0.4)
	hits.clear()
	p.request_attack(&"body_jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("blocked", false)) and not bool(hits[0].get("opening", false)),
		"into the guard it's blocked")


func test_perfect_parry() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	await _wait(0.1)
	var taken := []
	p.hit_taken.connect(func(info): taken.append(info))
	e.request_attack(&"swing", p)
	while e.state == Fighter.State.WINDUP and e.windup_remaining() > 0.05:
		await get_tree().physics_frame
	p.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.3)
	_check(taken.size() == 1 and bool(taken[0].get("parried", false)) and bool(taken[0].get("perfect", false)),
		"a guard raised at the last moment is a perfect parry")
	# Raised early it still blocks, but it's no read.
	await _until_free(e)
	await _wait(1.2)
	p.request_block(false)
	await _wait(0.1)
	taken.clear()
	p.request_block(true, Moves.GUARD_HEAD)
	e.request_attack(&"swing", p)
	await _until_free(e)
	_check(taken.size() == 1 and not bool(taken[0].get("perfect", false)), "an early guard isn't a perfect read")


func test_lock_on() -> void:
	var p := _player(Vector3(0, 0, 0), Vector3(0, 0, -1))
	var a := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	var b := _fighter(Fighter.Team.PUNTERS, Vector3(1.0, 0, -0.9), Vector3(0, 0, 0))
	a.toughness = 5.0
	b.toughness = 5.0
	await _wait(0.1)
	p.toggle_lock()
	_check(p.lock_target == a and p.is_locked(), "lock on picks the man in front")
	p.next_lock()
	_check(p.lock_target == b, "switch to the next man")
	p.next_lock()
	_check(p.lock_target == a, "and round again")
	p.next_lock()
	# Locked on to the one at the side, a punch goes at him, not the one in front.
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	await _wait(0.3)
	p.button(&"jab")
	await _until_free(p)
	_check(hits.size() == 1 and hits[0]["victim"] == b, "locked on, the punch goes at him")
	_check(p.stance_target == b, "and you stay squared up to him")
	p.toggle_lock()
	_check(p.lock_target == null, "lock on again lets go")
	# The lock lets go when he's down.
	p.toggle_lock()
	var locked := p.lock_target
	locked.take_hit({"attacker": p, "damage": 1.0, "direction": Vector3(0, 0, -1), "knockdown": true})
	await _wait(0.1)
	_check(p.lock_target == null, "the lock lets go of a man on the floor")


## Jabs upstairs bring his hands up; the body shot that follows into the gap is a set-up.
func test_set_up_into_the_gap() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.toughness = 5.0
	e.parry_skill = 0.0
	await _wait(0.1)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	# A body shot into the gap with nothing before it: clean, but not a set-up.
	e.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.4)
	p.request_attack(&"body_jab", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("opening", false)) and not bool(hits[0].get("setup", false)),
		"a lone clean shot isn't a set-up")
	await _wait(Moves.SETUP_WINDOW + 0.2)
	# Jab at the high guard, then go downstairs.
	await _until_free(e)
	e.request_block(true, Moves.GUARD_HEAD)
	await _wait(0.4)
	hits.clear()
	p.request_attack(&"jab", e)
	await _until_free(p)
	var hp := e.hp
	p.request_attack(&"body_jab", e)
	await _until_free(p)
	_check(hits.size() == 2 and bool(hits[0].get("blocked", false)), "the jab is blocked (%d hits)" % hits.size())
	var last: Dictionary = hits.back() if not hits.is_empty() else {}
	_check(bool(last.get("setup", false)) and String(last.get("setup_name", "")) == "Upstairs, downstairs",
		"the body shot after it is a set-up (%s)" % [last.get("setup_name", "none")])
	_check(is_equal_approx(hp - e.hp, 4.0 * Moves.CLEAN_BONUS * Moves.SETUP_BONUS),
		"and pays off (%.2f)" % (hp - e.hp))


## Enough to the head in a spell rocks him: slow guard, wobbly legs, and a heavy shot drops him.
func test_rocked_and_finished() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.max_hp = 100.0
	e.hp = 100.0
	e.parry_skill = 0.0
	await _wait(0.1)
	var rocked := []
	var cb := func(f): rocked.append(f)
	Events.fighter_rocked.connect(cb)
	for i in 3:
		e.take_hit({"attacker": p, "damage": 11.0, "zone": Moves.GUARD_HEAD, "poise": 0.0,
			"stagger": 0.1, "direction": Vector3(0, 0, -1)})
		await _wait(0.15)
	Events.fighter_rocked.disconnect(cb)
	_check(e.is_rocked() and rocked == [e], "33 to the head of a 100 hp man rocks him")
	_check(e.open_zone() == &"all", "a rocked man is open")
	await _until_free(e)
	e.request_block(true, Moves.GUARD_HEAD)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not e.is_blocking_from(p.global_position, Moves.GUARD_HEAD), "his hands are slow coming up")
	e.request_block(false)
	var hits := []
	p.hit_dealt.connect(func(info): hits.append(info))
	p.request_attack(&"hook", e)
	await _until_free(p)
	_check(hits.size() == 1 and bool(hits[0].get("finish", false)), "a hook on a rocked man finishes him")
	_check(e.state == Fighter.State.DOWN, "and puts him down (%s)" % Fighter.State.keys()[e.state])
	await _wait(e.get_up_time + 0.5)
	_check(not e.is_rocked(), "the count clears his head")


## Body shots wind him: stamina knocked out, slow to get it back, slow on his feet.
func test_winded_by_body_shots() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 0), Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2), Vector3(0, 0, 0))
	e.max_hp = 100.0
	e.hp = 100.0
	await _wait(0.1)
	var before := e.stamina
	for i in 3:
		e.take_hit({"attacker": p, "damage": 10.0, "zone": Moves.GUARD_BODY, "poise": 0.0,
			"stagger": 0.1, "direction": Vector3(0, 0, -1)})
		await _wait(0.15)
	_check(e.is_winded() and not e.is_rocked(), "30 to the body winds him")
	_check(e.stamina < before - e.max_stamina * Moves.WINDED_DRAIN, "and knocks the wind out (%.1f)" % e.stamina)
	var low := e.stamina
	await _wait(2.0)
	_check(e.stamina - low < Moves.STAMINA_REGEN * 2.0 * 0.6, "he's slow getting it back (%.1f)" % (e.stamina - low))
	await _wait(Moves.WINDED_TIME)
	_check(not e.is_winded(), "until he gets his breath")
