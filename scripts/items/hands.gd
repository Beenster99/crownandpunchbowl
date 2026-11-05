class_name Hands
extends Node
## A Fighter's hands: pick up, swing (through Fighter.equip), throw and drop items, drink
## and eat, and order at the bar. Also owns the tipsy effect. PubItems adds one, named
## "Hands", to every Fighter in a pub.
##
## Players: reads the `interact`, `throw` and `order_food` actions on the owning peer.
## AI: call the request_* methods on the host, the same way it calls Fighter requests.
##
##   interact      pick up / drink / eat the nearest loose item; else order a pint if at
##                 the bar; else drop what you're holding
##   throw         throw the held item (throwing a grabbed person stays with the combat
##                 controller, so this does nothing while GRABBING)
##   order_food    order food at the bar
##
## Tipsy (Fighter.tipsy, 0..1): each pint adds to it and it wears off slowly. While tipsy
## you hit harder and feel less (power and toughness up), walk slower and sway about.

const NODE_NAME := "Hands"

## Read the local player's input. Off for NPCs (they aren't in "players").
@export var read_input := true

var fighter: Fighter

var _hot_left := 0.0        # food hp still to heal (host)
var _hot_ticks := 0
var _hot_t := 0.0
var _power_mult := 1.0      # multipliers currently applied to the fighter's stats
var _tough_mult := 1.0
var _speed_mult := 1.0
var _sway_t := 0.0


static func of(f: Node) -> Hands:
	return f.get_node_or_null(NODE_NAME) as Hands if f != null else null


func _ready() -> void:
	fighter = get_parent() as Fighter
	if fighter == null:
		push_warning("Hands must be a child of a Fighter")
		set_physics_process(false)
		return
	fighter.state_changed.connect(_on_state_changed)


# --- Queries ---------------------------------------------------------------------------

func held_item() -> PubItem:
	return fighter.weapon as PubItem


func at_bar() -> Bar:
	return Bar.nearest(fighter, fighter.global_position)


## What interact would do right now, for HUD prompts: "pick_up", "drink", "eat",
## "order", "drop" or "".
func interact_hint() -> String:
	return String(interact_target()["hint"])


## What interact would act on right now: {"hint": String, "node": PubItem, Bar or null}.
## Same priority as the host uses: nearest item, then the bar, then dropping.
func interact_target() -> Dictionary:
	var item := PubItems.nearest_item(fighter, fighter.global_position)
	if item != null:
		var hint := "pick_up"
		if item.is_consumable():
			hint = "eat" if item.kind == &"food" else "drink"
		return {"hint": hint, "node": item}
	var bar := at_bar()
	if bar != null:
		return {"hint": "order", "node": bar}
	if held_item() != null:
		return {"hint": "drop", "node": held_item()}
	return {"hint": "", "node": null}


# --- Requests (call on the fighter's authority) ---------------------------------------

func request_interact() -> void:
	_send(&"interact", [])


func request_throw_item() -> void:
	_send(&"throw", [])


func request_drop() -> void:
	_send(&"drop", [])


## kind: &"pint" or &"food"
func request_order(kind: StringName) -> void:
	_send(&"order", [kind])


func _send(action: StringName, args: Array) -> void:
	if not is_inside_tree():
		return
	if multiplayer.is_server():
		_server_action(action, args)
	else:
		_rpc_action.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_action(action: StringName, args: Array) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != fighter.get_multiplayer_authority():
		return
	_server_action(action, args)


# --- Host side -------------------------------------------------------------------------

func _server_action(action: StringName, args: Array) -> void:
	match action:
		&"interact":
			_server_interact()
		&"throw":
			var item := held_item()
			if item != null and (fighter.can_act() or fighter.can_chain()):
				item.server_throw()
		&"drop":
			var item := held_item()
			if item != null:
				item.server_drop()
		&"order":
			var kind: StringName = args[0] if args.size() > 0 else &"pint"
			if kind != &"pint" and kind != &"food":
				return
			var bar := at_bar()
			if bar != null and fighter.can_act():
				bar.server_order(fighter, kind)


func _server_interact() -> void:
	if not fighter.can_act():
		return
	var item := PubItems.nearest_item(fighter, fighter.global_position)
	if item != null:
		if item.is_consumable():
			_server_consume(item)
		elif item.is_weapon():
			item.server_give(fighter)
		return
	var bar := at_bar()
	if bar != null:
		bar.server_order(fighter, &"pint")
		return
	if held_item() != null:
		held_item().server_drop()


func _server_consume(item: PubItem) -> void:
	var k := item.data()
	var leaves: StringName = k.get("leaves", &"")
	var pos := item.global_position
	item.server_consume()
	var heal := float(k.get("heal", 0.0))
	if item.kind == &"pint" and ItemData.trait_of(fighter) == "seasoned_drinker":
		heal *= ItemData.SEASONED_DRINKER_HEAL
	if heal > 0.0:
		fighter.heal(heal)
	var hot := float(k.get("heal_over_time", 0.0))
	if hot > 0.0:
		_hot_left += hot
		_hot_ticks = ItemData.HEAL_TICKS
		_hot_t = 0.0
	var tipsy := float(k.get("tipsy", 0.0))
	if tipsy > 0.0:
		_rpc_tipsy.rpc(minf(fighter.tipsy + tipsy, 1.0))
	if leaves != &"" and fighter.weapon == null:
		var mgr := PubItems.get_for(self)
		if mgr != null:
			var empty := mgr.server_spawn(leaves, pos)
			if empty != null:
				empty.server_give(fighter)


@rpc("any_peer", "call_local", "reliable")
func _rpc_tipsy(value: float) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s == 0 or s == 1:
		fighter.tipsy = clampf(value, 0.0, 1.0)


## Down, held or out: you drop what you're holding.
func _on_state_changed(_old: Fighter.State, new_state: Fighter.State) -> void:
	if not multiplayer.is_server():
		return
	if new_state in [Fighter.State.DOWN, Fighter.State.CRAWL, Fighter.State.KO, Fighter.State.HELD]:
		var item := held_item()
		if item != null:
			item.server_drop.call_deferred()  # let the fighter finish changing state
		if new_state == Fighter.State.KO:
			_hot_left = 0.0


# --- Every frame -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if fighter.tipsy > 0.0:
		fighter.tipsy = maxf(fighter.tipsy - ItemData.TIPSY_DECAY * delta, 0.0)
	_apply_mods()
	if multiplayer.is_server():
		_tick_food(delta)
	if fighter.is_multiplayer_authority():
		_sway(delta)
		if read_input and fighter.is_in_group("players"):
			_read_input()


func _read_input() -> void:
	if Input.is_action_just_pressed("interact"):
		request_interact()
	if Input.is_action_just_pressed("order_food"):
		request_order(&"food")
	if Input.is_action_just_pressed("throw") and fighter.state != Fighter.State.GRABBING:
		request_throw_item()


func _tick_food(delta: float) -> void:
	if _hot_ticks <= 0 or fighter.is_ko():
		return
	_hot_t += delta
	if _hot_t < ItemData.HEAL_TICK_TIME:
		return
	_hot_t = 0.0
	var amount := _hot_left / _hot_ticks
	_hot_left -= amount
	_hot_ticks -= 1
	fighter.heal(amount)


## Applies tipsy and the carried weapon's speed to the fighter's stats. Uses the change in
## multiplier, so other systems can still set the base stats.
func _apply_mods() -> void:
	var t := fighter.tipsy
	var power_bonus := ItemData.DRUNKEN_MASTER_POWER \
		if ItemData.trait_of(fighter) == "drunken_master" else ItemData.TIPSY_POWER
	var p := 1.0 + power_bonus * t
	var tough := 1.0 + ItemData.TIPSY_TOUGHNESS * t
	var speed := 1.0 - ItemData.TIPSY_SLOW * t
	var item := held_item()
	if item != null:
		speed *= float(item.data().get("speed_mult", 1.0))
	fighter.power *= p / _power_mult
	fighter.toughness *= tough / _tough_mult
	fighter.move_speed *= speed / _speed_mult
	_power_mult = p
	_tough_mult = tough
	_speed_mult = speed


## A tipsy fighter wanders a bit off their line. Runs on the fighter's owner, which moves it.
func _sway(delta: float) -> void:
	var t := fighter.tipsy
	var body := fighter.get_node_or_null("Body") as Node3D
	if t < 0.05 or fighter.state != Fighter.State.IDLE:
		if body != null:
			body.rotation.z = 0.0
		return
	_sway_t += delta
	var side := fighter.get_facing().cross(Vector3.UP)
	var push := side * sin(_sway_t * 1.7) + fighter.get_facing() * 0.35 * sin(_sway_t * 1.1)
	fighter.move_and_collide(push * ItemData.TIPSY_SWAY * t * delta)
	if body != null:
		body.rotation.z = sin(_sway_t * 1.7) * 0.12 * t
