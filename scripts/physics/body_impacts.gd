class_name BodyImpacts
extends Node
## How a fighter's body meets the pub. Fighter adds one ("Impacts") and calls after_move()
## after every move_and_slide() on the fighter's authority.
##
## - Walking barges chairs, stools, glasses and anything else loose out of the way (they're
##   on PubPhysics.LAYER_PROPS, which fighters don't collide with, so nobody snags on them).
## - A fighter sent flying (knocked down, or carried by a big hit) hits props much harder:
##   tables tip, chairs scatter, glasses go everywhere.
## - Sent flying into something waist high (the bar, a table, a pool table, a railing) at
##   VAULT_SPEED or more, they go over it. Their ragdoll flips over the top.
## - Slammed into a wall, bar back or anything tall, whatever's pinned up nearby (pictures,
##   shelf bottles) comes loose (PubPhysics.disturb).
##
## Props are simulated by the host, so a client-owned player sends its shoves to the host.

const NODE_NAME := "Impacts"
## Rough mass of a fighter (kg) for momentum shared with what they hit.
const FIGHTER_MASS := 80.0
## Knocked-down fighters carried this fast (m/s, flat) go over waist-high obstacles.
## Combat: a shoulder charge or throw meant to send someone over the bar needs at least this
## much knockback (after the victim's toughness).
const VAULT_SPEED := 5.5
## Going this fast into a wall knocks pinned props loose.
const SLAM_SPEED := 3.5
## Obstacles whose top is this far above the feet can be gone over (m).
const VAULT_MIN := 0.3
const VAULT_MAX := 1.35
## How far over the obstacle's top the feet are thrown (m).
const VAULT_CLEAR := 0.4
## Share of the fighter's speed given to what they walk or fly into.
const WALK_PUSH := 0.55
const FLY_PUSH := 1.45
## Fastest a shove sends anything (m/s), so chairs scatter rather than take off.
const MAX_PUSH := 6.5
## Slower than this and nothing gets shoved (people standing at a table don't nudge it).
const MIN_PUSH_SPEED := 0.6
## Above this impulse a fighter counts as flying even if they're still on their feet.
const FLYING_SPEED := 2.5

var fighter: Fighter
var _shape: Shape3D
var _shape_xf := Transform3D.IDENTITY
var _vault_cd := 0.0
var _slam_cd := 0.0
var _pushed := {}


static func attach(f: Fighter) -> BodyImpacts:
	var existing := f.get_node_or_null(NODE_NAME) as BodyImpacts
	if existing != null:
		return existing
	var b := BodyImpacts.new()
	b.name = NODE_NAME
	b.fighter = f
	f.add_child(b)
	return b


func _ready() -> void:
	if fighter == null:
		fighter = get_parent() as Fighter
	for c in fighter.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			_shape = (c as CollisionShape3D).shape
			_shape_xf = (c as CollisionShape3D).transform
			break


## The fighter's speed carried by hits (not footwork), flat.
func knock_speed() -> float:
	var i: Vector3 = fighter._impulse
	return Vector2(i.x, i.z).length()


func is_flying() -> bool:
	return fighter.is_down() or knock_speed() >= FLYING_SPEED


## Call on the fighter's authority right after move_and_slide(). `pre_velocity` is the
## velocity it was asked to move with (move_and_slide changes it on contact).
func after_move(delta: float, pre_velocity: Vector3) -> void:
	if fighter == null or not fighter.is_inside_tree():
		return
	_vault_cd = maxf(_vault_cd - delta, 0.0)
	_slam_cd = maxf(_slam_cd - delta, 0.0)
	_pushed.clear()
	var flat := Vector3(pre_velocity.x, 0.0, pre_velocity.z)
	var speed := flat.length()
	var knock := knock_speed()
	var flying := is_flying()
	for i in fighter.get_slide_collision_count():
		var c := fighter.get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.5:
			continue  # floors and ceilings: standing on a table doesn't push it
		var into := Vector3(-n.x, 0.0, -n.z).normalized()
		var v_into := flat.dot(into)
		if v_into <= 0.05:
			continue
		var other := c.get_collider()
		var point := c.get_position()
		if other is RigidBody3D:
			var rb := other as RigidBody3D
			if flying and knock >= VAULT_SPEED and rb.mass >= 12.0:
				_try_vault(point, into, knock, rb)
			_push(rb, into, v_into, flying, point)
		elif other is PhysicsBody3D or other is CSGShape3D:
			if flying and knock >= VAULT_SPEED and _try_vault(point, into, knock, other as Node):
				continue
			if flying and knock >= SLAM_SPEED:
				_slam(point, into * knock)
	if speed >= MIN_PUSH_SPEED:
		_push_overlaps(flat, speed, flying)


# --- Shoving props ----------------------------------------------------------------------

func _push(body: RigidBody3D, dir: Vector3, v_into: float, flying: bool, point: Vector3) -> void:
	if body == null or _pushed.has(body) or not PubPhysics.is_prop(body):
		return
	if body.freeze and not (flying and bool(body.get_meta("pinned", false))):
		return
	_pushed[body] = true
	var m := body.mass
	var share := FIGHTER_MASS / (FIGHTER_MASS + m)
	var want := minf(v_into * share * (FLY_PUSH if flying else WALK_PUSH), MAX_PUSH)
	var have := body.linear_velocity.dot(dir)
	if want <= have + 0.05:
		return
	var dv := want - have
	var imp := dir * dv * m
	if flying:
		imp += Vector3.UP * dv * m * 0.25  # a body crashing in lifts things, so they tumble
	_send_shove(body, imp, point - body.global_position)


## Props the fighter's capsule is passing through (chairs, stools, glasses on the floor).
func _push_overlaps(flat: Vector3, speed: float, flying: bool) -> void:
	if _shape == null:
		return
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = fighter.global_transform * _shape_xf
	q.collision_mask = PubPhysics.LAYER_PROPS
	q.collide_with_areas = false
	q.exclude = [fighter.get_rid()]
	var space := fighter.get_world_3d().direct_space_state
	var move_dir := flat / speed
	for r in space.intersect_shape(q, 12):
		var body := r.get("collider") as RigidBody3D
		if body == null:
			continue
		var to := body.global_position - fighter.global_position
		to.y = 0.0
		if to.length() > 0.01 and to.normalized().dot(move_dir) < -0.2:
			continue  # it's behind us
		var dir := move_dir
		if to.length() > 0.01:
			dir = (move_dir + to.normalized() * 0.6).normalized()  # kicked aside, not just ahead
		# Hit low, so a chair trips and topples rather than sliding upright.
		_push(body, dir, speed, flying, body.global_position + Vector3.UP * 0.1)


func _send_shove(body: RigidBody3D, impulse: Vector3, offset: Vector3) -> void:
	if multiplayer.is_server():
		PubPhysics.shove(body, impulse, offset)
	else:
		_rpc_shove.rpc_id(1, body.get_path(), impulse, offset)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_shove(path: NodePath, impulse: Vector3, offset: Vector3) -> void:
	if not multiplayer.is_server() or not _from_authority():
		return
	var body := get_node_or_null(path) as RigidBody3D
	if body == null or not PubPhysics.is_prop(body):
		return
	PubPhysics.shove(body, impulse.limit_length(400.0), offset.limit_length(2.0))


# --- Going over things ------------------------------------------------------------------

## A flying body meets something. If its top is waist high, throw them up and over it.
func _try_vault(point: Vector3, into: Vector3, knock: float, obstacle: Node) -> bool:
	if _vault_cd > 0.0 or fighter._vault_t >= 0.0 or fighter._launch_y > 0.0:
		return false
	var feet := fighter.global_position.y
	var probe := point + into * 0.25
	var from := Vector3(probe.x, feet + VAULT_MAX + 0.4, probe.z)
	var q := PhysicsRayQueryParameters3D.create(from, Vector3(probe.x, feet - 0.1, probe.z),
		PubPhysics.LAYER_WORLD)
	q.exclude = [fighter.get_rid()]
	var hit := fighter.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return false
	var top: float = Vector3(hit["position"]).y - feet
	if top < VAULT_MIN or top > VAULT_MAX:
		return false
	_vault_cd = 0.8
	fighter._launch_y = sqrt(2.0 * Fighter.GRAVITY * (top + VAULT_CLEAR))
	# Keep the momentum going over the top rather than skidding to a stop against it.
	fighter._impulse = into * maxf(knock, VAULT_SPEED)
	var path := obstacle.get_path() if obstacle != null and obstacle.is_inside_tree() else NodePath()
	_rpc_flipped.rpc(path, into, fighter._launch_y)
	return true


## Every peer: the body went over something. The ragdoll flips; FX can react.
@rpc("any_peer", "call_local", "reliable")
func _rpc_flipped(obstacle_path: NodePath, dir: Vector3, lift: float) -> void:
	if not _from_authority():
		return
	var obstacle := get_node_or_null(obstacle_path) if not obstacle_path.is_empty() else null
	var visual := fighter.get_node_or_null(FighterVisual.NODE_NAME)
	var driver := visual.get_node_or_null(RagdollDriver.NODE_NAME) as RagdollDriver if visual else null
	if driver != null:
		driver.flip(dir, lift)
	Events.fighter_flipped_over.emit(fighter, obstacle)


func _slam(point: Vector3, impulse: Vector3) -> void:
	if _slam_cd > 0.0:
		return
	_slam_cd = 0.4
	if multiplayer.is_server():
		PubPhysics.disturb(get_tree(), point, 1.8, impulse * 0.5)
	else:
		_rpc_slam.rpc_id(1, point, impulse)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_slam(point: Vector3, impulse: Vector3) -> void:
	if not multiplayer.is_server() or not _from_authority():
		return
	if point.distance_to(fighter.global_position) > 2.5:
		return
	PubPhysics.disturb(get_tree(), point, 1.8, impulse.limit_length(15.0) * 0.5)


func _from_authority() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == fighter.get_multiplayer_authority()
