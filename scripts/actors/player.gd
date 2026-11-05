class_name PlayerFighter
extends CharacterBody3D
## Placeholder player: camera-relative movement only.
## The combat workstream builds the real fighter (attacks, grabs, freeflow) on top.

@export var speed := 4.6
const GRAVITY := 20.0


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(12.0 * delta, 0.0, 1.0))
	move_and_slide()
