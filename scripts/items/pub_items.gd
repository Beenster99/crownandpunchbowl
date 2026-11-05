class_name PubItems
extends Node3D
## One per pub. Owns every PubItem in the pub, spawns new ones with deterministic names
## (I<n>) on every peer, and gives each Fighter a Hands node so it can pick things up,
## throw them and order at the bar.
##
## Setup in a pub scene's _ready() (every peer):
##   var items := PubItems.install(self)       # under $Items if the pub has one
##   items.add_item(&"bottle", Vector3(...))   # starting props, same order on every peer
## Bars are Bar nodes (scripts/items/bar.gd); place them anywhere in the pub.

const NODE_NAME := "PubItems"
const MANAGER_GROUP := &"item_manager"

var _next_id := 0


## Create the manager under `pub` (or its "Items" child) and hook up Hands for fighters.
static func install(pub: Node) -> PubItems:
	var mgr := PubItems.new()
	mgr.name = NODE_NAME
	var parent: Node = pub.get_node_or_null("Items")
	(parent if parent != null else pub).add_child(mgr)
	return mgr


## The pub's item manager, or null.
static func get_for(n: Node) -> PubItems:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group(MANAGER_GROUP) as PubItems


## Nearest loose item a fighter at `pos` can reach, or null. `filter` takes a PubItem.
static func nearest_item(n: Node, pos: Vector3, max_range := ItemData.PICKUP_RANGE,
		filter := Callable()) -> PubItem:
	var best: PubItem = null
	var best_d := INF
	for node in n.get_tree().get_nodes_in_group(PubItem.GROUP):
		var item := node as PubItem
		if item == null or not item.is_loose():
			continue
		if filter.is_valid() and not filter.call(item):
			continue
		var to := item.global_position - pos
		if to.y > ItemData.PICKUP_HEIGHT or to.y < -0.6:
			continue
		to.y = 0.0
		var d := to.length()
		if d <= max_range and d < best_d:
			best_d = d
			best = item
	return best


func _ready() -> void:
	add_to_group(MANAGER_GROUP)
	get_tree().node_added.connect(_on_node_added)
	for f in get_tree().get_nodes_in_group(Fighter.GROUP):
		_give_hands(f)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Place a starting prop. Call on every peer in the same order (the pub's _ready does).
func add_item(kind: StringName, pos: Vector3, yaw := 0.0) -> PubItem:
	var item := _make(kind, "I%d" % _next_id, pos, -1)
	item.rotation.y = yaw
	_next_id += 1
	return item


## Host only: spawn an item on every peer. Returns the host's copy.
func server_spawn(kind: StringName, pos: Vector3, ammo := -1) -> PubItem:
	if not multiplayer.is_server() or not ItemData.has(kind):
		return null
	var item_name := "I%d" % _next_id
	_next_id += 1
	_rpc_spawn.rpc(kind, item_name, pos, ammo)
	return get_node_or_null(item_name) as PubItem


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn(kind: StringName, item_name: String, pos: Vector3, ammo: int) -> void:
	var s := multiplayer.get_remote_sender_id()
	if s != 0 and s != 1:
		return
	if get_node_or_null(item_name) == null:
		_make(kind, item_name, pos, ammo)


func _make(kind: StringName, item_name: String, pos: Vector3, ammo: int) -> PubItem:
	var item := PubItem.new()
	item.kind = kind
	item.ammo = ammo
	item.name = item_name
	item.position = pos
	add_child(item)
	return item


func _on_node_added(n: Node) -> void:
	if n is Fighter:
		_give_hands.call_deferred(n)


func _give_hands(f: Node) -> void:
	if not is_instance_valid(f) or not f.is_inside_tree() or f.has_node(Hands.NODE_NAME):
		return
	var h := Hands.new()
	h.name = Hands.NODE_NAME
	f.add_child(h)


## Props and a bar for the greybox test pub (scripts/level/test_pub.gd). The pubs
## workstream places its own in each real pub.
func furnish_test_pub(room: Vector2) -> void:
	var bar := Bar.new()
	bar.name = "Bar"
	bar.position = Vector3(0.0, 0.0, -room.y * 0.5 + 1.6)
	bar.length = 7.0
	bar.depth = 0.8
	bar.top_height = 1.1
	add_child(bar)
	var top := 0.8  # table top
	var props := [
		[&"pint", Vector3(-4.2, top, -0.2)], [&"bottle", Vector3(-3.8, top, 0.2)],
		[&"food", Vector3(4.0, top, 0.0)], [&"glass", Vector3(4.3, top, 0.3)],
		[&"bottle", Vector3(-4.0, top, 3.0)], [&"pint", Vector3(3.8, top, 3.2)],
		[&"bottle", Vector3(-2.0, 1.1, -room.y * 0.5 + 1.5)],
		[&"chair", Vector3(-5.2, 0.0, 0.0)], [&"chair", Vector3(5.2, 0.0, 0.0)],
		[&"chair", Vector3(-5.2, 0.0, 3.0)], [&"stool", Vector3(-1.5, 0.0, -room.y * 0.5 + 2.6)],
		[&"stool", Vector3(1.5, 0.0, -room.y * 0.5 + 2.6)],
		[&"pool_cue", Vector3(6.8, 0.0, -2.5)], [&"darts", Vector3(-7.2, 0.0, -2.0)],
		[&"poker", Vector3(7.2, 0.0, 4.5)], [&"coal_shovel", Vector3(7.0, 0.0, 5.0)],
		[&"table_leg", Vector3(0.0, 0.0, 2.0)], [&"chair_leg", Vector3(-1.0, 0.0, 1.0)],
	]
	for p in props:
		add_item(p[0], p[1])
