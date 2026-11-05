class_name PlayerFighter
extends Fighter
## Player-controlled fighter: camera-relative movement for now.
## The freeflow controls (combos, lunge, counters, grabs) land in the next combat PR.


func _ready() -> void:
	team = Team.PLAYERS
	super()


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		move_input = Vector3(input.x, 0.0, input.y)
	super(delta)
