class_name PubItem
extends Node3D
## Anything in a pub that can be picked up: weapons (bottles, chairs, cues, darts, pokers...)
## and consumables (pints, food). Numbers live in ItemData.KINDS; this node only holds the
## kind and what has happened to it.
##
## Items never change parent, so their node paths stay the same on every peer. A held item
## just follows its holder's hand. The host decides everything (pick-ups, throws, hits,
## breaks) and replicates the result with the _rpc_* methods below.
##
## As a weapon it implements the Fighter weapon hooks: on_equipped, on_unequipped,
## modify_move and on_hit. Gore and audio can read `kind` and `sharp` from a hit's "weapon".
##
## Place one in a pub scene with an exported `kind`, or spawn at runtime with
## PubItems.server_spawn(). Players use them through the Hands node on each Fighter.

enum Mode { LOOSE, HELD, FLYING, GONE }

const GROUP := &"items"
const HIGHLIGHT_COLOR := Color(1.0, 0.82, 0.45)

@export var kind: StringName = &"bottle"
## Which model to show (a PropLibrary variant name). Empty picks one from the start position.
@export var variant := ""
## Darts in the set. -1 takes the kind's default.
@export var ammo := -1

var mode: Mode = Mode.LOOSE
## Fighter holding this, while HELD.
var holder: Fighter = null
## Fighter who threw this, while FLYING.
var thrower: Fighter = null
## Hits left before it breaks. Negative never breaks.
var durability := 1.0
var sharp := false

var _velocity := Vector3.ZERO
var _flight_t := 0.0
var _travelled := 0.0
var _ground_y := 0.0
var _break_pending := false
var _mesh: MeshInstance3D
var _model_centre := Vector3.ZERO  # centre of a PropLibrary model's bounds (zero for primitives)
var _outline: StandardMaterial3D
var _highlight := 0


func _ready() -> void:
	add_to_group(GROUP)
	var k := ItemData.get_kind(kind)
	durability = float(k.get("durability", -1))
	sharp = bool(k.get("sharp", false))
	if ammo < 0:
		ammo = int(k.get("ammo", 1))
	_build_mesh(k)


# --- Queries --------------------------------------------------------------------------

func data() -> Dictionary:
	return ItemData.get_kind(kind)


func is_weapon() -> bool:
	return ItemData.is_weapon(kind)


func is_consumable() -> bool:
	return ItemData.is_consumable(kind)


func is_loose() -> bool:
	return mode == Mode.LOOSE


func display_name() -> String:
	return String(data().get("name", kind))


# --- Fighter weapon hooks ------------------------------------------------------------

func on_equipped(f: Fighter) -> void:
	holder = f
	mode = Mode.HELD
	_follow_holder()


## Called by Fighter.unequip(). If nobody told us where to go first, drop at their feet.
func on_unequipped(f: Fighter) -> void:
	if mode == Mode.HELD:
		mode = Mode.LOOSE
		_lie_at(_feet_of(f))
	holder = null


## Weapons change the bare-knuckle swing moves (see ItemData.SWING_MOVES).
func modify_move(m: Dictionary) -> Dictionary:
	if not ItemData.SWING_MOVES.has(StringName(m.get("id", &""))):
		return m
	var k := data()
	m["damage"] = float(m["damage"]) * float(k.get("damage_mult", 1.0))
	m["reach"] = float(m["reach"]) + float(k.get("reach_add", 0.0))
	if k.has("arc"):
		m["arc"] = float(k["arc"])
	m["sweep"] = bool(m["sweep"]) or bool(k.get("sweep", false))
	m["windup"] = float(m["windup"]) + float(k.get("windup_add", 0.0))
	m["recover"] = float(m["recover"]) + float(k.get("recover_add", 0.0))
	m["poise"] = float(m["poise"]) * float(k.get("poise_mult", 1.0))
	m["knockback"] = float(m["knockback"]) * float(k.get("knockback_mult", 1.0))
	m["stagger"] = float(m["stagger"]) * float(k.get("stagger_mult", 1.0))
	for flag in ["heavy", "to_face", "knockdown"]:
		if bool(k.get(flag, false)):
			m[flag] = true
	m["weapon_kind"] = kind
	return m


## Host only: each landed swing wears the weapon down.
func on_hit(_info: Dictionary) -> void:
	if not multiplayer.is_server() or durability < 0.0 or _break_pending:
		return
	durability -= _wear(holder)
	if durability <= 0.0:
		_break_pending = true
		server_break.call_deferred()  # not mid-way through the attacker's hit loop


# --- Host API ------------------------------------------------------------------------

## Put this item in `f`'s hand, dropping whatever they held.
func server_give(f: Fighter) -> void:
	if not multiplayer.is_server() or f == null or mode == Mode.GONE:
		return
	if f.weapon is PubItem and f.weapon != self:
		(f.weapon as PubItem).server_drop()
	_rpc_give.rpc(f.get_path())


func server_drop() -> void:
	if not multiplayer.is_server() or mode != Mode.HELD:
		return
	_rpc_land.rpc(_feet_of(holder))


## Throw from the holder's hand at the enemy they're facing (or straight ahead).
## Darts send one dart at a time.
func server_throw() -> void:
	if not multiplayer.is_server() or mode != Mode.HELD or holder == null:
		return
	var f := holder
	var k := data()
	var start := f.global_position + f.get_facing() * 0.5 + Vector3.UP * ItemData.THROW_HEIGHT
	var aim := Targeting.pick(f, f.move_input, ItemData.THROW_AIM_RANGE)
	var dir := f.get_facing()
	if aim != null:
		dir = aim.global_position - f.global_position
		dir.y = 0.0
		dir = dir.normalized()
	var vel := dir * float(k.get("throw_speed", 12.0))
	if ammo > 1:
		var mgr := PubItems.get_for(self)
		if mgr == null:
			return
		_rpc_ammo.rpc(ammo - 1)
		var one := mgr.server_spawn(kind, start, 1)
		one._rpc_throw.rpc(f.get_path(), start, vel)
		return
	_rpc_throw.rpc(f.get_path(), start, vel)


## Smash it. Leaves its breaks_into pieces: the first in the holder's hand.
func server_break() -> void:
	if not multiplayer.is_server() or mode == Mode.GONE:
		return
	var f := holder if mode == Mode.HELD else null
	var where := global_position if f == null else _feet_of(f)
	where.y = _ground_y if mode == Mode.FLYING else where.y
	var pieces: Array = data().get("breaks_into", [])
	_rpc_gone.rpc(true)
	var mgr := PubItems.get_for(self)
	if mgr == null:
		return
	for i in pieces.size():
		var offset := Vector3(0.35 * i, 0.0, 0.25 * (i % 2))
		var piece := mgr.server_spawn(pieces[i], where + offset)
		if i == 0 and f != null and f.weapon == null and not f.is_down():
			piece.server_give(f)


## Drink or eat it. The caller (Hands) applies the effects.
func server_consume() -> void:
	if multiplayer.is_server() and mode == Mode.LOOSE:
		_rpc_gone.rpc(false)


# --- Replicated results ---------------------------------------------------------------

func _sender_is_host() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == 1


@rpc("any_peer", "call_local", "reliable")
func _rpc_give(fighter_path: NodePath) -> void:
	if not _sender_is_host():
		return
	var f := get_node_or_null(fighter_path) as Fighter
	if f == null or mode == Mode.GONE:
		return
	if holder != null and holder != f and holder.weapon == self:
		mode = Mode.LOOSE
		holder.unequip()
	mode = Mode.HELD
	_velocity = Vector3.ZERO
	f.equip(self)
	Events.item_picked_up.emit(f, self)


@rpc("any_peer", "call_local", "reliable")
func _rpc_land(pos: Vector3) -> void:
	if not _sender_is_host():
		return
	var f := holder
	mode = Mode.LOOSE
	holder = null
	thrower = null
	_velocity = Vector3.ZERO
	if f != null and f.weapon == self:
		f.unequip()
	_lie_at(pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_throw(thrower_path: NodePath, start: Vector3, vel: Vector3) -> void:
	if not _sender_is_host():
		return
	var f := get_node_or_null(thrower_path) as Fighter
	if holder != null and holder.weapon == self:
		mode = Mode.FLYING
		holder.unequip()
	holder = null
	mode = Mode.FLYING
	thrower = f
	global_position = start
	_velocity = vel
	_flight_t = 0.0
	_travelled = 0.0
	_ground_y = f.global_position.y if f != null else start.y - ItemData.THROW_HEIGHT
	basis = Basis.looking_at(vel.normalized() if vel.length() > 0.01 else Vector3.FORWARD)


@rpc("any_peer", "call_local", "reliable")
func _rpc_gone(broke: bool) -> void:
	if not _sender_is_host() or mode == Mode.GONE:
		return
	var f := holder
	mode = Mode.GONE
	holder = null
	if f != null and f.weapon == self:
		f.unequip()
	remove_from_group(GROUP)
	visible = false
	if broke:
		Events.item_broken.emit(self)
	queue_free.call_deferred()


@rpc("any_peer", "call_local", "reliable")
func _rpc_ammo(n: int) -> void:
	if _sender_is_host():
		ammo = n


# --- Simulation -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if mode == Mode.HELD:
		_follow_holder()
	elif _highlight == 2:
		_pulse_highlight()


func _physics_process(delta: float) -> void:
	if mode == Mode.HELD:
		_follow_holder()
	elif mode == Mode.FLYING:
		_fly(delta)


## Flight runs on every peer from the same start; only the host decides what it hits.
func _fly(delta: float) -> void:
	var k := data()
	_flight_t += delta
	if _travelled > float(k.get("throw_range", 8.0)):
		_velocity.y -= ItemData.GRAVITY * delta
	var from := global_position
	var to := from + _velocity * delta
	_travelled += Vector2(to.x - from.x, to.z - from.z).length()
	if _mesh != null:
		_mesh.rotate_x(-delta * 14.0)
		_mesh.position = -(_mesh.basis * _model_centre)  # spin models round their middle
	if not multiplayer.is_server():
		to.y = maxf(to.y, _ground_y)
		global_position = to
		return
	# Walls stop it dead; then it falls.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and Vector3(hit["normal"]).y > 0.5:
		_ground_y = Vector3(hit["position"]).y  # came down on a floor or table top
		global_position = hit["position"]
		_land_from_flight()
		return
	if not hit.is_empty():
		to = hit["position"] - _velocity.normalized() * 0.05
		_velocity = Vector3(0.0, minf(_velocity.y, 0.0), 0.0)
		if bool(k.get("fragile", false)):
			global_position = to
			server_break()
			return
	global_position = to
	var victim := _flight_victim()
	if victim != null:
		_hit_in_flight(victim)
		return
	if to.y <= _ground_y + 0.02 or _flight_t > ItemData.MAX_FLIGHT_TIME:
		_land_from_flight()


func _flight_victim() -> Fighter:
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == thrower or not f.can_be_hit() or f.is_down():
			continue
		if f.team == Fighter.Team.STAFF:  # nobody hits the bar staff, not even by accident
			continue
		if thrower != null and is_instance_valid(thrower) and not thrower.can_hit(f):
			continue
		var to := f.global_position - global_position
		var h := -to.y
		to.y = 0.0
		if to.length() <= ItemData.THROW_HIT_RADIUS and h > 0.1 and h < 2.0:
			return f
	return null


func _hit_in_flight(victim: Fighter) -> void:
	var k := data()
	var src: Fighter = thrower if thrower != null and is_instance_valid(thrower) else null
	var dmg := float(k.get("throw_damage", 6.0)) * (src.power if src != null else 1.0)
	if src != null and src.team != Fighter.Team.PLAYERS and victim.team == Fighter.Team.PLAYERS:
		dmg *= float(GameData.difficulty()["enemy_damage"])
	var knockdown := bool(k.get("throw_knockdown", false))
	var dir := Vector3(_velocity.x, 0.0, _velocity.z).normalized()
	victim.take_hit({
		"attacker": src, "move": "throw_%s" % kind, "damage": dmg, "direction": dir,
		"position": global_position, "heavy": dmg >= 10.0,
		"to_face": global_position.y - victim.global_position.y > 1.25,
		"knockdown": knockdown, "stagger": 0.45, "poise": dmg * 1.5,
		"knockback": 5.0 if knockdown else 2.0, "weapon": self, "thrown": true,
	})
	if kind == &"darts":
		_rpc_gone.rpc(false)  # it's stuck in them
		return
	if bool(k.get("fragile", false)):
		server_break()
		return
	if durability >= 0.0:
		durability -= 1.0
		if durability <= 0.0:
			server_break()
			return
	_rpc_land.rpc(Vector3(global_position.x, victim.global_position.y, global_position.z) - dir * 0.3)


func _land_from_flight() -> void:
	if bool(data().get("fragile", false)):
		server_break()
		return
	_rpc_land.rpc(Vector3(global_position.x, _ground_y, global_position.z))


# --- Placement and looks --------------------------------------------------------------

func _wear(f: Fighter) -> float:
	return 1.0 / ItemData.HANDYMAN_DURABILITY if ItemData.trait_of(f) == "handyman" else 1.0


func _feet_of(f: Fighter) -> Vector3:
	if f == null or not is_instance_valid(f):
		return global_position
	return f.global_position + f.get_facing() * 0.45


func _lie_at(pos: Vector3) -> void:
	global_position = pos
	if bool(data().get("two_handed", false)):
		basis = Basis()
	else:
		basis = Basis(Vector3.FORWARD, PI * 0.5)  # long things lie on their side
	if _mesh != null:
		_mesh.rotation = Vector3.ZERO
		_mesh.position = -_model_centre


func _follow_holder() -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var local: Transform3D
	if bool(data().get("two_handed", false)):
		local = Transform3D(Basis(), Vector3(0.0, 1.0, -0.55))
	else:
		# In the rig's right hand when the holder has one (characters workstream).
		var visual := holder.get_node_or_null("Visual")
		var hand: Node3D = visual.hand_socket() if visual != null and visual.has_method("hand_socket") else null
		if hand != null:
			global_transform = Transform3D(hand.global_basis.orthonormalized(), hand.global_position)
			return
		local = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-70.0)), Vector3(0.32, 1.0, -0.2))
	global_transform = holder.global_transform * local


## Subtle outline so players can see what they can grab. 0 off, 1 nearby, 2 in reach
## (pulses). Cosmetic and local: InteractPrompt sets it for the local player.
func set_highlight(level: int) -> void:
	if _mesh == null or level == _highlight:
		return
	if _mesh.material_override == null:
		_set_model_highlight(level)
		return
	_highlight = level
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if level <= 0 or mode != Mode.LOOSE:
		mat.next_pass = null
		mat.emission_enabled = false
		_highlight = 0
		return
	mat.emission_enabled = true  # a warm glint on the item itself
	mat.emission = HIGHLIGHT_COLOR
	mat.emission_energy_multiplier = 0.12 if level == 1 else 0.4
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline.grow = true
		_outline.render_priority = 1
	_outline.grow_amount = 0.012 if level == 1 else 0.03
	_outline.albedo_color = HIGHLIGHT_COLOR * Color(1, 1, 1, 0.22 if level == 1 else 0.85)
	mat.next_pass = _outline


## Models (PropLibrary) share their materials, so the glint and outline go in an overlay.
func _set_model_highlight(level: int) -> void:
	_highlight = level
	if level <= 0 or mode != Mode.LOOSE:
		_mesh.material_overlay = null
		_highlight = 0
		return
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline.grow = true
		_outline.render_priority = 1
	_outline.grow_amount = 0.012 if level == 1 else 0.03
	_outline.albedo_color = HIGHLIGHT_COLOR * Color(1, 1, 1, 0.22 if level == 1 else 0.85)
	var glint := StandardMaterial3D.new()
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glint.albedo_color = HIGHLIGHT_COLOR * Color(1, 1, 1, 0.08 if level == 1 else 0.22)
	glint.next_pass = _outline
	_mesh.material_overlay = glint


func _pulse_highlight() -> void:
	if _highlight == 2 and _outline != null:
		var t := Time.get_ticks_msec() / 1000.0
		_outline.albedo_color.a = 0.55 + 0.35 * sin(t * 5.0)


func _build_mesh(k: Dictionary) -> void:
	# A proper model when there is one (PropLibrary), picked from the kind's variants by
	# where the item starts, so every peer shows the same look.
	var look: Variant = variant if variant != "" else position
	var model := PropLibrary.visual(String(kind), look) if PropLibrary.has(String(kind)) else null
	if model != null:
		var h := model.mesh.get_aabb()
		_mesh = model
		_mesh.name = "Mesh"
		_model_centre = h.get_center()
		_mesh.position = -_model_centre
		var model_pivot := Node3D.new()
		model_pivot.name = "Pivot"
		model_pivot.position = _model_centre
		add_child(model_pivot)
		model_pivot.add_child(_mesh)
		return
	var spec: Array = k.get("mesh", ["box", Vector3(0.1, 0.1, 0.1), Color.MAGENTA])
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	var height := 0.1
	var color: Color = spec[spec.size() - 1]
	if spec[0] == "cyl":
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(spec[1])
		cyl.bottom_radius = float(spec[1])
		cyl.height = float(spec[2])
		height = cyl.height
		_mesh.mesh = cyl
	else:
		var box := BoxMesh.new()
		box.size = spec[1]
		height = box.size.y
		_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = mat
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position.y = height * 0.5
	add_child(pivot)
	pivot.add_child(_mesh)
