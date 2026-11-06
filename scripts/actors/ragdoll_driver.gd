class_name RagdollDriver
extends Node
## Hands a fighter's rig to physics whenever they go down, not just on a KO, so falls,
## throws, trips over the bar and tumbles off a gallery are physics rather than one canned
## clip. FighterVisual adds one per rig and asks it first about every state change.
##
## - Knocked down or out: the rig goes limp with the fighter's own momentum plus a kick from
##   the blow (at the head for face shots, the chest otherwise).
## - While limp, the hips are tethered to the fighter's capsule by a soft spring, so the
##   body ends up where gameplay thinks it is on every peer (each peer runs its own ragdoll).
## - Hits taken on the floor shove the limp body about.
## - Getting up blends from the ragdoll back into the get-up animation instead of popping.
##
## - Knocked out: once the body has come to rest it's pinned where it lies (it never
##   twitches or flies off again), and a punter then slowly fades away. Players stay put
##   for a revive.
## - Every bone's speed is capped, so a bad contact can't fling limbs across the room.
##
## Purely cosmetic and local to each peer, like the rest of the visual.

const NODE_NAME := "RagdollDriver"
## Seconds to blend from the ragdoll back to animation on getting up.
const BLEND_OUT := 0.45
## Push (N·s) a knockdown gives the body on top of the fighter's own momentum.
const BLOW_BASE := 9.0
const BLOW_PER_KNOCKBACK := 3.5
## Tether: spring (1/s²) and damping (1/s) pulling the hips to the capsule, and the slack
## (m) inside which the body is left to lie however it fell.
const TETHER_K := 45.0
const TETHER_C := 11.0
const TETHER_SLACK := 0.3
## Further than this from the capsule and the ragdoll is reset onto it.
const TETHER_SNAP := 3.5
## Caps on any bone's speed while limp (m/s and rad/s).
const MAX_SPEED := 9.0
const MAX_SPIN := 14.0
## A KO'd body moving slower than this (m/s, fastest bone) for SETTLE_TIME is at rest.
const SETTLE_SPEED := 0.35
const SETTLE_TIME := 0.4
## KO'd bodies are pinned after this long even if something keeps nudging them.
const SETTLE_MAX := 3.0
## A KO'd punter waits this long after settling, then fades out over FADE_TIME.
const FADE_DELAY := 2.5
const FADE_TIME := 2.5

var fighter: Fighter
var rig: CharacterRig
var _blow := Vector3.ZERO
var _blow_at_head := false
var _ko_t := -1.0       # seconds knocked out (and limp), or -1
var _still_t := 0.0
var _settled := false
var _fade: Tween
var _faded := false


func setup(f: Fighter, r: CharacterRig) -> void:
	fighter = f
	rig = r


func _ready() -> void:
	if fighter != null:
		fighter.hit_taken.connect(_on_hit_taken)


## FighterVisual calls this before playing the animation for a state (lower-case name).
## Returns true when the ragdoll has handled it and no animation should be played.
func on_state(key: String) -> bool:
	if rig == null or rig.skeleton == null:
		return false
	if key == "ko":
		if not rig.ragdolling:
			_go_limp()
		if _ko_t < 0.0:
			_ko_t = 0.0
		return true
	_end_ko()  # revived, or anything else: back to normal
	if key == "down":
		if not rig.ragdolling:
			_go_limp()
		return true
	if rig.ragdolling:
		rig.stop_ragdoll(BLEND_OUT)
		if key == "idle":
			rig.play(&"get_up", 0.0)  # goes back to idle by itself when it's done
			return true
	return false


## The body went over something (BodyImpacts): send the legs up and over, head first.
func flip(dir: Vector3, lift: float) -> void:
	if rig == null:
		return
	if not rig.ragdolling:
		_go_limp()
	var fwd := Vector3(dir.x, 0.0, dir.z).normalized()
	var speed := maxf(Vector2(fighter.velocity.x, fighter.velocity.z).length(), BodyImpacts.VAULT_SPEED)
	for pb in rig.ragdoll_bones():
		var bn := String(pb.bone_name)
		var v := fwd * speed * 0.9 + Vector3.UP * lift * 0.45
		if bn.begins_with("Knee") or (bn.begins_with("Hip") and bn != "Hips"):
			v += Vector3.UP * 2.2 + fwd * 1.0   # legs come up and over
		elif bn == "Head" or bn == "Chest":
			v += Vector3.DOWN * 1.2 - fwd * 0.4  # head and shoulders go down the far side
		pb.linear_velocity = v


func _on_hit_taken(info: Dictionary) -> void:
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	dir.y = 0.0
	var kb := float(info.get("knockback", 1.0)) / maxf(fighter.toughness, 0.1)
	_blow = dir.normalized() * (BLOW_BASE + kb * BLOW_PER_KNOCKBACK) if dir.length() > 0.01 else Vector3.ZERO
	if bool(info.get("heavy", false)):
		_blow *= 1.3
	_blow_at_head = bool(info.get("to_face", false))
	# A boot or a stamp on someone already lying there moves the body.
	if rig != null and rig.ragdolling and _blow != Vector3.ZERO:
		var pb := rig.ragdoll_bone(&"Head" if _blow_at_head else &"Chest")
		if pb != null:
			pb.apply_central_impulse(_blow * 0.6 + Vector3.UP * 2.0)


func _go_limp() -> void:
	var vel := fighter.velocity
	rig.start_ragdoll(Vector3.ZERO, vel)
	if _blow != Vector3.ZERO:
		var head := rig.ragdoll_bone(&"Head")
		var chest := rig.ragdoll_bone(&"Chest")
		var lift := Vector3.UP * _blow.length() * 0.2
		if _blow_at_head and head != null:
			head.apply_central_impulse(_blow * 0.45 + lift)  # the head goes first
			if chest != null:
				chest.apply_central_impulse(_blow * 0.35)
		elif chest != null:
			chest.apply_central_impulse(_blow * 0.8 + lift)
	_blow = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if rig == null or not rig.ragdolling or fighter == null:
		return
	if _settled:
		return
	var fastest := _cap_speeds()
	if _ko_t >= 0.0:
		_ko_t += delta
		_still_t = _still_t + delta if fastest < SETTLE_SPEED else 0.0
		if _still_t >= SETTLE_TIME or _ko_t >= SETTLE_MAX:
			_settle()
			return
	var hips := rig.ragdoll_bone(&"Hips")
	if hips == null:
		return
	var target := fighter.global_position + Vector3.UP * 0.25
	var err := target - hips.global_position
	if err.length() > TETHER_SNAP:
		rig.stop_ragdoll()
		rig.start_ragdoll(Vector3.ZERO, fighter.velocity)  # back onto the capsule
		return
	# Flat pull; vertical only when the body and capsule are well apart in height (it fell
	# off a ledge and the body got hung up on the rail, or the body was thrown too high).
	var vertical := absf(err.y) > 1.2
	if not vertical:
		err.y = 0.0
	var dist := err.length()
	if dist <= TETHER_SLACK:
		return
	err = err / dist * (dist - TETHER_SLACK)
	var rel := hips.linear_velocity - fighter.velocity
	if not vertical:
		rel.y = 0.0
	var accel := (err * TETHER_K - rel * TETHER_C).limit_length(60.0)
	var mass := rig.ragdoll_mass()
	hips.apply_central_impulse(accel * mass * delta)


## Caps every bone's speed. Returns the fastest bone's speed (m/s) after the cap.
func _cap_speeds() -> float:
	var fastest := 0.0
	for pb in rig.ragdoll_bones():
		var v := pb.linear_velocity
		if v.length() > MAX_SPEED:
			pb.linear_velocity = v.limit_length(MAX_SPEED)
		if pb.angular_velocity.length() > MAX_SPIN:
			pb.angular_velocity = pb.angular_velocity.limit_length(MAX_SPIN)
		fastest = maxf(fastest, pb.linear_velocity.length())
	return fastest


## Out cold and at rest: pin the body where it lies, then fade a punter away.
func _settle() -> void:
	_settled = true
	rig.freeze_ragdoll(true)
	if fighter.team == Fighter.Team.PLAYERS or _fade != null:
		return  # players wait there to be revived
	_fade = create_tween()
	_fade.tween_interval(FADE_DELAY)
	_fade.tween_method(_set_fade, 0.0, 1.0, FADE_TIME)
	_fade.tween_callback(_faded_out)


func _set_fade(amount: float) -> void:
	for m in rig.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).transparency = amount


func _faded_out() -> void:
	_faded = true
	rig.visible = false
	rig.stop_ragdoll()  # nothing left to see; stop simulating it


## Leaving KO (a revive): undo the pin and the fade.
func _end_ko() -> void:
	if _ko_t < 0.0 and not _settled and _fade == null and not _faded:
		return
	_ko_t = -1.0
	_still_t = 0.0
	if _fade != null:
		_fade.kill()
		_fade = null
	if _settled:
		rig.freeze_ragdoll(false)
	_settled = false
	if _faded or rig.visible == false:
		rig.visible = true
	_faded = false
	_set_fade(0.0)


## True once a knocked-out punter has faded away completely.
func is_faded() -> bool:
	return _faded
