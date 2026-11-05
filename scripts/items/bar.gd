class_name Bar
extends Node3D
## A bar counter you can order at. Place it in a pub with its origin on the floor at the
## middle of the counter. The counter runs along local X; customers stand on the local +Z
## side. Orders are served onto the counter top in front of whoever ordered, so anyone
## can grab them (a mate, or a thirsty punter).
##
## A pint is quick and small: a little health and a bit tipsy. Food takes the microwave
## a while, then heals a lot over a few seconds. Nobody hits the bar staff, so the bar
## always serves.

const GROUP := &"bar"

@export var length := 7.0
@export var depth := 0.8
@export var top_height := 1.1

## Pending orders (host): [{fighter, kind, left}]
var _orders: Array[Dictionary] = []
var _cooldown := {}  # fighter -> seconds


## The bar that `pos` is close enough to order at, or null.
static func nearest(n: Node, pos: Vector3) -> Bar:
	var best: Bar = null
	var best_d := INF
	for node in n.get_tree().get_nodes_in_group(GROUP):
		var bar := node as Bar
		if bar == null:
			continue
		var d := bar.distance_to_front(pos)
		if d <= ItemData.BAR_RANGE and d < best_d:
			best_d = d
			best = bar
	return best


func _ready() -> void:
	add_to_group(GROUP)


## Flat distance from `pos` to the customer side of the counter. INF behind the bar.
func distance_to_front(pos: Vector3) -> float:
	var local := to_local(pos)
	if local.z < depth * 0.5 - 0.1:
		return INF
	var dx := maxf(absf(local.x) - length * 0.5, 0.0)
	var dz := local.z - depth * 0.5
	return Vector2(dx, dz).length()


## Where an order for someone standing at `pos` goes on the counter.
func serve_point(pos: Vector3) -> Vector3:
	var local := to_local(pos)
	var half := length * 0.5 - 0.2
	return to_global(Vector3(clampf(local.x, -half, half), top_height, depth * 0.5 - 0.15))


func has_order(f: Fighter) -> bool:
	for o in _orders:
		if o["fighter"] == f:
			return true
	return false


## Host only. Returns true if the order was taken.
func server_order(f: Fighter, kind: StringName) -> bool:
	if not multiplayer.is_server() or f == null or not ItemData.is_consumable(kind):
		return false
	if distance_to_front(f.global_position) > ItemData.BAR_RANGE:
		return false
	if has_order(f) or float(_cooldown.get(f, 0.0)) > 0.0:
		return false
	var wait := ItemData.FOOD_SERVE_TIME if kind == &"food" else ItemData.DRINK_SERVE_TIME
	_orders.append({"fighter": f, "kind": kind, "left": wait})
	_cooldown[f] = ItemData.ORDER_COOLDOWN
	_rpc_ordered.rpc(f.get_path(), kind)
	return true


@rpc("any_peer", "call_local", "reliable")
func _rpc_ordered(fighter_path: NodePath, kind: StringName) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	var f := get_node_or_null(fighter_path)
	if f == null:
		return
	if kind == &"food":
		Events.food_ordered.emit(f)
	else:
		Events.drink_ordered.emit(f)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for f in _cooldown.keys():
		_cooldown[f] = float(_cooldown[f]) - delta
		if _cooldown[f] <= 0.0 or not is_instance_valid(f):
			_cooldown.erase(f)
	if _orders.is_empty():
		return
	var done: Array[Dictionary] = []
	for o in _orders:
		o["left"] = float(o["left"]) - delta
		if o["left"] <= 0.0:
			done.append(o)
	for o in done:
		_orders.erase(o)
		var f = o["fighter"]
		if not is_instance_valid(f):
			continue
		var mgr := PubItems.get_for(self)
		if mgr != null:
			mgr.server_spawn(o["kind"], serve_point((f as Fighter).global_position))
