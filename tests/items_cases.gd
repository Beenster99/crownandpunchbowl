extends Node
## Test cases for items, the bar and tipsy. Loaded by items_test.gd once the autoloads exist.

signal finished(failures: int)

var _failures := 0
var _arena: Node3D
var _items: PubItems


func run() -> void:
	GameData.difficulty_index = 1  # Session Ale: multipliers of 1.0
	var tests := [
		"test_pick_up_and_swap", "test_bottle_breaks_into_broken_bottle",
		"test_chair_sweeps_and_breaks", "test_throw_bottle", "test_darts_one_at_a_time",
		"test_thrown_leg_lands", "test_pint_heals_tipsy_and_leaves_glass", "test_food_heals_over_time",
		"test_bar_orders", "test_throws_miss_bar_staff", "test_drop_when_knocked_down",
		"test_poker_never_breaks", "test_handyman_and_seasoned_drinker", "test_prompts_and_highlights",
	]
	for t in tests:
		_arena = Node3D.new()
		add_child(_arena)
		_floor()
		_items = PubItems.install(_arena)
		await call(t)
		_arena.queue_free()
		await get_tree().process_frame
	if _failures == 0:
		print("ITEMS OK: %d tests" % tests.size())
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


func _fighter(team: int, pos: Vector3, face_toward := Vector3.INF) -> Fighter:
	var f := Fighter.new()
	f.team = team
	f.collision_layer = 2 if team == Fighter.Team.PLAYERS else 4
	f.collision_mask = 7
	if team == Fighter.Team.PLAYERS:
		f.add_to_group("players")
	elif team == Fighter.Team.STAFF:
		f.add_to_group("staff")
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


func _hands(f: Fighter) -> Hands:
	var h := Hands.of(f)
	h.read_input = false
	return h


func _wait(seconds: float) -> void:
	var frames := int(ceil(seconds * 60.0))
	for i in frames:
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


func _held_kind(f: Fighter) -> StringName:
	return (f.weapon as PubItem).kind if f.weapon is PubItem else &""


func _count(kind: StringName) -> int:
	var n := 0
	for i in get_tree().get_nodes_in_group(PubItem.GROUP):
		if (i as PubItem).kind == kind and (i as PubItem).mode != PubItem.Mode.GONE:
			n += 1
	return n


# --- Tests -----------------------------------------------------------------------------

func test_pick_up_and_swap() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var bottle := _items.add_item(&"bottle", Vector3(0, 0.8, -0.8))
	var leg := _items.add_item(&"chair_leg", Vector3(0.6, 0, 0))
	await _wait(0.1)
	_check(Hands.of(p) != null, "fighters get Hands")
	_hands(p).request_interact()
	await _wait(0.05)
	_check(p.weapon == leg, "picks up the nearest item (got %s)" % _held_kind(p))
	_check(leg.mode == PubItem.Mode.HELD and leg.holder == p, "item knows it is held")
	_hands(p).request_interact()
	await _wait(0.05)
	_check(p.weapon == bottle, "picking up another swaps")
	_check(leg.is_loose(), "the old one is dropped")
	_hands(p).request_interact()  # nothing in reach but the leg at the feet
	await _wait(0.05)
	_check(p.weapon == leg, "can pick the dropped one back up")


func test_bottle_breaks_into_broken_bottle() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	var bottle := _items.add_item(&"bottle", Vector3(0, 0, -0.3))
	await _wait(0.1)
	bottle.server_give(p)
	await _wait(0.02)
	var broken := []
	Events.item_broken.connect(func(i): broken.append(i))
	p.request_attack(&"jab", e)
	await _wait(0.5)
	_check(is_equal_approx(e.hp, e.max_hp - float(Moves.get_move(&"jab")["damage"]) * 1.5), "bottle jab does 1.5x (hp %.1f)" % e.hp)
	_check(broken.has(bottle), "bottle smashes on the first hit")
	_check(_held_kind(p) == &"broken_bottle", "left holding a broken bottle (got %s)" % _held_kind(p))
	_check(p.weapon is PubItem and (p.weapon as PubItem).sharp, "broken bottle is sharp")


func test_chair_sweeps_and_breaks() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var a := _fighter(Fighter.Team.PUNTERS, Vector3(-0.5, 0, -1.1))
	var b := _fighter(Fighter.Team.PUNTERS, Vector3(0.5, 0, -1.1))
	var chair := _items.add_item(&"chair", Vector3(0, 0, 0.5))
	await _wait(0.1)
	var base_speed := p.move_speed
	chair.server_give(p)
	await _wait(0.05)
	_check(p.move_speed < base_speed, "carrying a chair slows you (%.2f)" % p.move_speed)
	p.request_attack(&"jab")
	await _wait(0.8)
	_check(a.hp < a.max_hp and b.hp < b.max_hp, "chair hits both sides")
	_check(a.is_down() and b.is_down(), "chair knocks them down")
	_check(_held_kind(p) == &"chair_leg", "chair breaks after two hits into a leg (got %s)" % _held_kind(p))
	_check(_count(&"chair_leg") == 2, "and another leg on the floor (got %d)" % _count(&"chair_leg"))
	await _wait(0.05)
	_check(is_equal_approx(p.move_speed, base_speed), "speed back after the chair is gone")


func test_throw_bottle() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0.6, 0, -5))
	var bottle := _items.add_item(&"bottle", Vector3(0, 0, -0.3))
	await _wait(0.1)
	bottle.server_give(p)
	await _wait(0.02)
	var hits := []
	Events.hit_landed.connect(func(info): hits.append(info))
	_hands(p).request_throw_item()
	await _wait(0.05)
	_check(p.weapon == null, "throwing empties your hand")
	_check(bottle.mode == PubItem.Mode.FLYING, "bottle is flying")
	await _wait(0.6)
	_check(e.hp < e.max_hp, "thrown bottle aims at and hits the punter (hp %.1f)" % e.hp)
	_check(not hits.is_empty() and hits[0]["weapon"] == bottle and hits[0]["attacker"] == p,
		"hit info names the thrower and the bottle")
	_check(not is_instance_valid(bottle) or bottle.mode == PubItem.Mode.GONE, "bottle smashes")


func test_darts_one_at_a_time() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -6))
	var darts := _items.add_item(&"darts", Vector3(0, 0, -0.3))
	await _wait(0.1)
	darts.server_give(p)
	await _wait(0.02)
	_check(darts.ammo == 3, "a set of three")
	for i in 3:
		_hands(p).request_throw_item()
		await _wait(0.6)
	_check(is_equal_approx(e.hp, e.max_hp - 18.0), "three darts hit (hp %.1f)" % e.hp)
	_check(p.weapon == null, "out of darts")
	_check(_count(&"darts") == 0, "darts stick in him")


func test_thrown_leg_lands() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var leg := _items.add_item(&"chair_leg", Vector3(0, 0, -0.3))
	await _wait(0.1)
	leg.server_give(p)
	await _wait(0.02)
	_hands(p).request_throw_item()
	await _wait(2.0)
	_check(leg.is_loose(), "a thrown leg that hits nothing lands")
	_check(leg.global_position.z < -6.0 and absf(leg.global_position.y - p.global_position.y) < 0.05,
		"it lands down range on the floor (%s)" % leg.global_position)


func test_pint_heals_tipsy_and_leaves_glass() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	_items.add_item(&"pint", Vector3(0, 0.8, -0.7))
	await _wait(0.1)
	p.hp = 50.0
	var power := p.power
	_hands(p).request_interact()
	await _wait(0.05)
	_check(is_equal_approx(p.hp, 62.0), "pint heals 12 (hp %.1f)" % p.hp)
	_check(p.tipsy > 0.19, "pint makes you tipsy (%.2f)" % p.tipsy)
	_check(p.power > power, "tipsy hits harder")
	_check(_held_kind(p) == &"glass", "left holding the empty glass")
	_check(_count(&"pint") == 0, "pint is gone")
	var t := p.tipsy
	await _wait(1.0)
	_check(p.tipsy < t, "tipsy wears off")


func test_food_heals_over_time() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	_items.add_item(&"food", Vector3(0, 0.8, -0.7))
	await _wait(0.1)
	p.hp = 20.0
	_hands(p).request_interact()
	await _wait(1.0)
	_check(p.hp > 20.0 and p.hp < 40.0, "food heals gradually (hp %.1f)" % p.hp)
	await _wait(6.0)
	_check(is_equal_approx(p.hp, 60.0), "food heals 40 in total (hp %.1f)" % p.hp)


func test_bar_orders() -> void:
	var bar := Bar.new()
	bar.position = Vector3(0, 0, -2)
	_items.add_child(bar)
	var p := _fighter(Fighter.Team.PLAYERS, Vector3(1.0, 0, -1.2), Vector3(1.0, 0, -3))
	await _wait(0.1)
	var drinks := []
	var foods := []
	Events.drink_ordered.connect(func(f): drinks.append(f))
	Events.food_ordered.connect(func(f): foods.append(f))
	_check(_hands(p).interact_hint() == "order", "at the bar the hint is order")
	_hands(p).request_interact()
	await _wait(0.1)
	_check(drinks == [p], "interact at the bar orders a pint")
	_check(_count(&"pint") == 0, "pint takes a moment to pour")
	_hands(p).request_interact()
	await _wait(0.1)
	_check(drinks.size() == 1, "one order at a time")
	await _wait(ItemData.DRINK_SERVE_TIME)
	_check(_count(&"pint") == 1, "pint served on the bar")
	_check(_hands(p).interact_hint() == "drink", "then the hint is drink")
	_hands(p).request_interact()
	await _wait(0.1)
	_check(_count(&"pint") == 0 and p.tipsy > 0.0, "drink it off the bar")
	_hands(p).request_order(&"food")
	await _wait(ItemData.FOOD_SERVE_TIME + 0.1)
	_check(foods == [p] and _count(&"food") == 1, "food ordered and served")
	var far := _fighter(Fighter.Team.PLAYERS, Vector3(0, 0, 3))
	await _wait(0.05)
	_hands(far).request_order(&"pint")
	await _wait(0.05)
	_check(drinks.size() == 1, "can't order from across the room")


func test_throws_miss_bar_staff() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var barman := _fighter(Fighter.Team.STAFF, Vector3(0, 0, -3))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -6))
	var bottle := _items.add_item(&"bottle", Vector3(0, 0, -0.3))
	await _wait(0.1)
	bottle.server_give(p)
	await _wait(0.02)
	_hands(p).request_throw_item()
	await _wait(0.8)
	_check(is_equal_approx(barman.hp, barman.max_hp), "a thrown bottle flies past the barman")
	_check(e.hp < e.max_hp, "and hits the punter behind him (hp %.1f)" % e.hp)

func test_drop_when_knocked_down() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	var poker := _items.add_item(&"poker", Vector3(0, 0, 0.5))
	await _wait(0.1)
	poker.server_give(p)
	await _wait(0.05)
	p.take_hit({"attacker": e, "damage": 5.0, "direction": Vector3.BACK, "knockdown": true})
	await _wait(0.05)
	_check(p.weapon == null and poker.is_loose(), "a knocked-down fighter drops their weapon")


func test_poker_never_breaks() -> void:
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.4))
	e.max_hp = 1000.0
	e.hp = 1000.0
	e.toughness = 50.0
	var poker := _items.add_item(&"poker", Vector3(0, 0, 0.5))
	await _wait(0.1)
	poker.server_give(p)
	await _wait(0.05)
	for i in 6:
		p.request_attack(&"jab", e)
		await _wait(0.5)
	_check(e.hp < 1000.0 - 40.0, "poker lands repeatedly (hp %.1f)" % e.hp)
	_check(p.weapon == poker, "iron poker never breaks")


func test_handyman_and_seasoned_drinker() -> void:
	var kev := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	kev.set_meta("trait", "handyman")
	var e := _fighter(Fighter.Team.PUNTERS, Vector3(0, 0, -1.2))
	e.toughness = 50.0
	var chair := _items.add_item(&"chair", Vector3(0, 0, 0.5))
	await _wait(0.1)
	chair.server_give(kev)
	await _wait(0.05)
	for i in 2:
		kev.request_attack(&"jab", e)
		await _wait(0.8)
	_check(kev.weapon == chair, "chairs last longer in Kev's hands")
	var barrow := _fighter(Fighter.Team.PLAYERS, Vector3(5, 0, 0), Vector3(5, 0, -1))
	barrow.set_meta("trait", "seasoned_drinker")
	_items.add_item(&"pint", Vector3(5, 0.8, -0.7))
	await _wait(0.1)
	barrow.hp = 50.0
	_hands(barrow).request_interact()
	await _wait(0.05)
	_check(is_equal_approx(barrow.hp, 74.0), "ale heals Barrow double (hp %.1f)" % barrow.hp)


func test_prompts_and_highlights() -> void:
	var prompt := _items.get_node(InteractPrompt.NODE_NAME) as InteractPrompt
	var p := _fighter(Fighter.Team.PLAYERS, Vector3.ZERO, Vector3(0, 0, -1))
	var bottle := _items.add_item(&"bottle", Vector3(0, 0.8, -0.8))
	var near := _items.add_item(&"chair_leg", Vector3(2.5, 0, 0))
	var far := _items.add_item(&"poker", Vector3(9, 0, 0))
	await _wait(0.1)
	_check(bottle._highlight == 2, "the item in reach gets the strong outline")
	_check(near._highlight == 1, "items nearby get a faint outline")
	_check(far._highlight == 0, "far items aren't outlined")
	_check(prompt._label.visible and prompt._label.text.ends_with("Pick up bottle"),
		"prompt names the item (%s)" % prompt._label.text)
	_check(prompt._label.text.begins_with("[%s]" % Settings.action_label("interact", "kb")),
		"keyboard prompt shows the keyboard key (%s)" % prompt._label.text)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Input.parse_input_event(pad)
	await _wait(0.05)
	_check(prompt._label.text.begins_with("[%s]" % Settings.action_label("interact", "pad")),
		"after using a controller the prompt shows the button (%s)" % prompt._label.text)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await _wait(0.05)
	_check(prompt._label.text.begins_with("[%s]" % Settings.action_label("interact", "kb")),
		"and back to keyboard")
	bottle.server_give(p)
	await _wait(0.05)
	_check(bottle._highlight == 0, "held items aren't outlined")
	_check(prompt._held_label.visible and "Throw" in prompt._held_label.text, "holding shows the throw key")
	var bar := Bar.new()
	bar.position = Vector3(0, 0, -6)
	_items.add_child(bar)
	p.global_position = Vector3(0, 0, -5.2)
	await _wait(0.05)
	_check("Order a pint" in prompt._label.text and "Order food" in prompt._label.text,
		"at the bar it offers drinks and food (%s)" % prompt._label.text)
	Settings.values["gameplay"]["context_prompts"] = false
	await _wait(0.05)
	_check(not prompt._label.visible and not prompt._held_label.visible, "prompts can be turned off")
	Settings.values["gameplay"]["context_prompts"] = true
