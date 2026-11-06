class_name PubPhysics
extends Node
## Physics for everything loose in a pub: furniture, glasses, bottles, pictures, barrels,
## pool balls and every PubItem lying about. One per pub, added by PubLevel.
##
## Every prop is a RigidBody3D in the "pub_props" group. The host simulates them all and
## streams the ones that are moving to the other peers about 20 times a second; on clients
## they're frozen (kinematic) and glide to the host's poses. Props sleep until something
## disturbs them, so a quiet pub costs nothing to simulate or sync.
##
## Prop metadata (all optional):
##   fragile: bool  glassware and crockery smash on a hard knock (Events.prop_smashed)
##   pinned: bool   fixed to a wall or shelf (freeze = true) until disturb() knocks it loose
##
## Layers: props sit on LAYER_PROPS (fighters don't snag on them, BodyImpacts shoves them
## instead), plus LAYER_WORLD for big pieces that should block people (tables, barrels).
## Ragdolls (CharacterRig, layer 7) collide with both, so a falling body scatters chairs.

const GROUP := &"pub_props"
const MANAGER_GROUP := &"pub_physics"
const NODE_NAME := "PubPhysics"

const LAYER_WORLD := 1
const LAYER_ITEMS := 8
const LAYER_RAGDOLL := 64
const LAYER_PROPS := 128
## What props collide with: the room, each other and loose items.
const PROP_MASK := LAYER_WORLD | LAYER_ITEMS | LAYER_PROPS

## Pose updates per second sent to clients for props that are moving.
const SYNC_RATE := 20.0
## A change of speed this big in one physics tick smashes glass (m/s). A glass knocked off
## a table lands at about 4 m/s.
const SMASH_DV := 3.2
## Fresh props (spawned, unpinned or dropped) can't smash for this long, so settling
## onto a table or shelf at load never breaks anything.
const SMASH_GRACE := 0.35
## Loose PubItems that smash when knocked hard (full pints too, not just empties).
const SMASHABLE_ITEMS: Array[StringName] = [&"bottle", &"glass", &"pint"]
## Mass in kg of each PubItem kind lying loose. Anything missing weighs 1 kg.
const ITEM_MASS := {
	&"bottle": 0.9, &"broken_bottle": 0.4, &"glass": 0.45, &"pint": 1.0, &"food": 0.8,
	&"plate": 0.5, &"chair": 6.5, &"stool": 4.5, &"chair_leg": 0.6, &"table_leg": 1.2,
	&"pool_cue": 0.55, &"broken_cue": 0.3, &"darts": 0.1, &"poker": 1.5, &"coal_shovel": 2.0,
	&"fire_tongs": 1.2, &"fire_shovel": 1.6,
}
## How quickly clients close the gap to the host's pose (per physics tick).
const CLIENT_FOLLOW := 0.4

var _sync_t := 0.0
var _awake := {}        # host: body -> true while it was moving at the last sync
var _last_v := {}       # host: fragile body -> linear velocity last tick
var _born := {}         # host: body -> ticks since it could start smashing
var _targets := {}      # client: body -> Transform3D from the host


## Create the manager under `level`.
static func install(level: Node) -> PubPhysics:
	var existing := level.get_node_or_null(NODE_NAME) as PubPhysics
	if existing != null:
		return existing
	var p := PubPhysics.new()
	p.name = NODE_NAME
	level.add_child(p)
	return p


static func get_for(n: Node) -> PubPhysics:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group(MANAGER_GROUP) as PubPhysics


## Turn `body` into a pub prop. Call before or after it enters the tree, on every peer, in
## the same order (names must match across peers). `blocks` also puts it on the world
## layer so fighters bump into it instead of wading through.
static func setup_prop(body: RigidBody3D, mass: float, blocks := false, fragile := false,
		pinned := false) -> RigidBody3D:
	body.add_to_group(GROUP)
	body.mass = maxf(mass, 0.05)
	body.collision_layer = LAYER_PROPS | (LAYER_WORLD if blocks else 0)
	body.collision_mask = PROP_MASK
	body.can_sleep = true
	body.sleeping = true
	body.linear_damp = 0.15
	body.angular_damp = 0.6
	if fragile:
		body.set_meta("fragile", true)
	if pinned:
		body.set_meta("pinned", true)
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	if body.physics_material_override == null:
		var pm := PhysicsMaterial.new()
		pm.friction = 0.7
		pm.bounce = 0.05 if not fragile else 0.15
		body.physics_material_override = pm
	return body


## Build a simple prop: a RigidBody3D with one box, cylinder or sphere shape and the
## given visual (any Node3D, centred on the shape) under `parent` at `xform`.
## `shape_size` is Vector3 for a box, Vector2(radius, height) for a cylinder, or a float
## radius for a sphere.
static func make_prop(parent: Node, prop_name: String, xform: Transform3D, shape_size: Variant,
		visual: Node3D, mass: float, blocks := false, fragile := false,
		pinned := false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = prop_name
	var col := CollisionShape3D.new()
	col.shape = shape_for(shape_size)
	body.add_child(col)
	if visual != null:
		body.add_child(visual)
	setup_prop(body, mass, blocks, fragile, pinned)
	parent.add_child(body, true)
	body.global_transform = xform
	return body


static func shape_for(size: Variant) -> Shape3D:
	if size is Vector3:
		var b := BoxShape3D.new()
		b.size = size
		return b
	if size is Vector2:
		var c := CylinderShape3D.new()
		c.radius = (size as Vector2).x
		c.height = (size as Vector2).y
		return c
	var s := SphereShape3D.new()
	s.radius = float(size)
	return s


static func is_prop(n: Node) -> bool:
	return n is RigidBody3D and n.is_in_group(GROUP)


## Host only: knock props near `pos` about. Pinned props within `radius` come loose.
## `impulse` is the push (N·s) given to a 1 kg prop right at `pos`; it falls off with
## distance and is scaled up gently with mass so heavy things still shift a little.
static func disturb(tree: SceneTree, pos: Vector3, radius: float, impulse: Vector3) -> void:
	if tree == null or not tree.root.multiplayer.is_server():
		return
	var mgr := tree.get_first_node_in_group(MANAGER_GROUP) as PubPhysics
	for node in tree.get_nodes_in_group(GROUP):
		var body := node as RigidBody3D
		if body == null or not body.is_inside_tree():
			continue
		var to := body.global_position - pos
		var d := to.length()
		if d > radius:
			continue
		var fall := 1.0 - d / radius
		if bool(body.get_meta("pinned", false)) and body.freeze:
			if body.collision_layer == 0:
				continue  # held or put away by its owner (PubItem)
			body.set_meta("pinned", false)
			body.freeze = false
			if mgr != null:
				mgr._born[body] = 0
		if body.freeze:
			continue
		var away := to
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
		var push := (impulse * 0.6 + away * impulse.length() * 0.4 + Vector3.UP * impulse.length() * 0.25)
		push *= fall * sqrt(clampf(body.mass, 0.2, 40.0))
		body.sleeping = false
		body.apply_impulse(push, Vector3(randf_range(-0.03, 0.03), randf_range(0.0, 0.06), randf_range(-0.03, 0.03)))


## Host only: give one prop a shove (BodyImpacts calls this for fighters it barges into).
static func shove(body: RigidBody3D, impulse: Vector3, offset := Vector3.ZERO) -> void:
	if body == null or not body.is_inside_tree() or not body.multiplayer.is_server():
		return
	if body.freeze:
		if not bool(body.get_meta("pinned", false)) or body.collision_layer == 0:
			return
		body.set_meta("pinned", false)
		body.freeze = false
	body.sleeping = false
	body.apply_impulse(impulse, offset)


func _ready() -> void:
	add_to_group(MANAGER_GROUP)
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().get_nodes_in_group(GROUP):
		_adopt(n)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is RigidBody3D:
		_adopt.call_deferred(n)  # groups and meta are set up just after add_child


## Clients don't simulate props: freeze them and follow the host.
func _adopt(n: Node) -> void:
	if not is_instance_valid(n) or not is_prop(n):
		return
	var body := n as RigidBody3D
	if multiplayer.is_server():
		_born[body] = 0
		return
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_check_smashes()
		_sync_t += delta
		if _sync_t >= 1.0 / SYNC_RATE and multiplayer.has_multiplayer_peer() \
				and not multiplayer.get_peers().is_empty():
			_sync_t = 0.0
			_send_poses()
	else:
		_follow_host()


# --- Smashing (host) --------------------------------------------------------------

func _check_smashes() -> void:
	var gone: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var body := node as RigidBody3D
		if body == null or body.freeze or body.sleeping or not _is_fragile(body):
			_last_v.erase(body)
			continue
		var age: int = _born.get(body, 1000) + 1
		_born[body] = age
		var v := body.linear_velocity
		var last: Vector3 = _last_v.get(body, v)
		_last_v[body] = v
		if age * get_physics_process_delta_time() < SMASH_GRACE:
			continue
		if (v - last).length() >= SMASH_DV:
			gone.append(body)
	for body in gone:
		smash(body)
	for body in _born.keys():
		if not is_instance_valid(body):
			_born.erase(body)
			_last_v.erase(body)


func _is_fragile(body: RigidBody3D) -> bool:
	if bool(body.get_meta("fragile", false)):
		return true
	var item := body.get_parent() as PubItem
	if item == null or not item.is_loose():
		return false
	return item.kind in SMASHABLE_ITEMS


## Host only: break a prop. Loose PubItems break the way items do (pieces, Events.item_broken);
## anything else is removed on every peer and Events.prop_smashed fires.
func smash(body: RigidBody3D) -> void:
	if not multiplayer.is_server() or not is_instance_valid(body):
		return
	var item := body.get_parent() as PubItem
	if item != null:
		if item.is_loose():
			_born[body] = -100000  # don't try again while the break goes through
			item.server_break()
		return
	_rpc_smash.rpc(get_tree().current_scene.get_path_to(body) if get_tree().current_scene else body.get_path())


@rpc("authority", "call_local", "reliable")
func _rpc_smash(path: NodePath) -> void:
	var root: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	var body := root.get_node_or_null(path) as RigidBody3D
	if body == null or not body.is_in_group(GROUP):
		return
	body.remove_from_group(GROUP)
	Events.prop_smashed.emit(body)
	if is_instance_valid(Fx) and Fx.has_method("play"):
		Fx.play("glass_smash", body.global_position)
	body.visible = false
	body.collision_layer = 0
	body.queue_free.call_deferred()


# --- Sync ----------------------------------------------------------------------------

func _send_poses() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var paths := PackedStringArray()
	var data := PackedFloat32Array()
	var still_awake := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		var body := node as RigidBody3D
		if body == null or not body.is_inside_tree():
			continue
		var moving := not body.freeze and not body.sleeping
		if moving:
			still_awake[body] = true
		elif not _awake.has(body):
			continue  # asleep and already settled on every peer
		paths.append(String(root.get_path_to(body)))
		var t := body.global_transform
		var q := t.basis.get_rotation_quaternion()
		data.append_array([t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w])
	_awake = still_awake
	if not paths.is_empty():
		_rpc_poses.rpc(paths, data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_poses(paths: PackedStringArray, data: PackedFloat32Array) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for i in paths.size():
		var body := root.get_node_or_null(NodePath(paths[i])) as RigidBody3D
		if body == null:
			continue
		var o := i * 7
		var q := Quaternion(data[o + 3], data[o + 4], data[o + 5], data[o + 6]).normalized()
		_targets[body] = Transform3D(Basis(q), Vector3(data[o], data[o + 1], data[o + 2]))


func _follow_host() -> void:
	var done: Array = []
	for body in _targets:
		if not is_instance_valid(body):
			done.append(body)
			continue
		var item := body.get_parent() as PubItem
		if item != null and not item.is_loose():
			done.append(body)  # held or flying: the item drives it now
			continue
		var target: Transform3D = _targets[body]
		var cur: Transform3D = body.global_transform
		var next := cur.interpolate_with(target, CLIENT_FOLLOW)
		body.global_transform = next
		if next.origin.distance_squared_to(target.origin) < 0.000001:
			done.append(body)
	for body in done:
		_targets.erase(body)
