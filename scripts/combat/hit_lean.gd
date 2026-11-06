class_name HitLean
extends Node
## Physical hit reactions layered on top of the animations, so a fight reads as bodies
## trading weight rather than clips swapping. Every hit kicks a damped spring that tips
## the whole rig away from the blow and shoves it back a touch; it wobbles and settles
## over about half a second. Throwing a punch leans the body into it. FighterVisual adds
## one of these for each fighter's rig. Purely cosmetic and local to each peer.

const STIFFNESS := 120.0     ## spring pull back to upright
const DAMPING := 12.0        ## how fast the wobble dies away
const MAX_ANGLE := 0.4       ## radians, the furthest a hit can tip the body
const MAX_OFFSET := 0.18     ## metres, the furthest the body is shoved off its feet
const OFFSET_PER_KICK := 0.1 ## shove speed per unit of tip speed

var fighter: Fighter
## The node that gets tipped (the rig). Its transform when the lean is at rest is kept.
var target: Node3D

var _rest := Transform3D.IDENTITY
var _ang := Vector3.ZERO      # rotation vector (axis * angle) in the fighter's local space
var _ang_v := Vector3.ZERO
var _off := Vector3.ZERO
var _off_v := Vector3.ZERO


func setup(f: Fighter, t: Node3D) -> void:
	fighter = f
	target = t


func _ready() -> void:
	if fighter == null or target == null:
		return
	_rest = target.transform
	fighter.hit_taken.connect(_on_hit_taken)
	fighter.state_changed.connect(_on_state_changed)


## How far the body is tipped right now, in radians.
func lean_angle() -> float:
	return _ang.length()


## Tips the body towards world direction `dir` with `strength` (radians per second).
func kick(dir: Vector3, strength: float) -> void:
	if fighter == null or not _can_lean():
		return
	var d := fighter.global_basis.inverse() * dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	d = d.normalized()
	# Turning about UP x d swings the top of the body towards d.
	_ang_v += Vector3.UP.cross(d) * strength
	_off_v += d * strength * OFFSET_PER_KICK


func _on_hit_taken(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var a: Variant = info.get("attacker")
	if dir.length() < 0.01 and a is Node3D and is_instance_valid(a):
		dir = fighter.global_position - (a as Node3D).global_position
	if dir.length() < 0.01:
		return
	var strength := minf(1.5 + float(info.get("damage", 0.0)) * 0.2, 6.0)
	if bool(info.get("heavy", false)):
		strength *= 1.4
	if bool(info.get("parried", false)):
		strength *= 0.25
	elif bool(info.get("blocked", false)):
		strength *= 0.5
	kick(dir, strength)


func _on_state_changed(_old: Fighter.State, new_state: Fighter.State) -> void:
	if new_state == Fighter.State.ATTACK:
		# Put the shoulder into it.
		kick(fighter.get_facing(), 2.2 if bool(fighter._move.get("heavy", false)) else 1.4)
	elif not _can_lean():
		_reset()


func _can_lean() -> bool:
	if fighter.is_down() or fighter.state == Fighter.State.HELD:
		return false
	return not bool(target.get("ragdolling")) if "ragdolling" in target else true


func _reset() -> void:
	_ang = Vector3.ZERO
	_ang_v = Vector3.ZERO
	_off = Vector3.ZERO
	_off_v = Vector3.ZERO
	if target != null:
		target.transform = _rest


func _process(delta: float) -> void:
	if fighter == null or target == null:
		return
	if not _can_lean():
		if _ang != Vector3.ZERO or _off != Vector3.ZERO:
			_reset()
		return
	if _ang == Vector3.ZERO and _ang_v == Vector3.ZERO and _off == Vector3.ZERO \
			and _off_v == Vector3.ZERO:
		return
	delta = minf(delta, 0.05)
	_ang_v += (-STIFFNESS * _ang - DAMPING * _ang_v) * delta
	_ang += _ang_v * delta
	_off_v += (-STIFFNESS * _off - DAMPING * _off_v) * delta
	_off += _off_v * delta
	if _ang.length() > MAX_ANGLE:
		_ang = _ang.normalized() * MAX_ANGLE
	if _off.length() > MAX_OFFSET:
		_off = _off.normalized() * MAX_OFFSET
	if _ang.length() < 0.0005 and _ang_v.length() < 0.005 and _off.length() < 0.0005 \
			and _off_v.length() < 0.005:
		_reset()
		return
	var angle := _ang.length()
	var b := Basis(_ang / angle, angle) if angle > 0.0 else Basis.IDENTITY
	target.transform = Transform3D(b * _rest.basis, _rest.origin + _off)
