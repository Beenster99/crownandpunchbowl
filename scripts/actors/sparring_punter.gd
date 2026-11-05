class_name SparringPunter
extends Fighter
## A deliberately simple stand-in opponent for the combat sandbox and tests, until the AI
## workstream's punters land. Minds its own business until it (or a mate within
## `mate_radius`) is hit, then closes in and throws telegraphed swings and haymakers.
## Struggles when held. Host only; it never runs on clients.

@export var aggro_on_start := false
@export var mate_radius := 4.0
@export var attack_gap := Vector2(1.4, 3.0)
@export var haymaker_chance := 0.25

var angry := false
var _cooldown := 1.0
var _struggle_t := 0.0


func _ready() -> void:
	if team == Team.PLAYERS:
		team = Team.PUNTERS
	super()
	add_to_group("npcs")
	angry = aggro_on_start
	Events.hit_landed.connect(_on_hit_landed)


func _on_hit_landed(info: Dictionary) -> void:
	var victim := info.get("victim") as Node3D
	if victim == self:
		angry = true
	elif victim != null and victim is Fighter and (victim as Fighter).team == team \
			and victim.global_position.distance_to(global_position) <= mate_radius:
		angry = true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_think(delta)
	super(delta)


func _think(delta: float) -> void:
	move_input = Vector3.ZERO
	if state == State.HELD:
		_struggle_t -= delta
		if _struggle_t <= 0.0:
			_struggle_t = 0.3
			request_struggle()
		return
	if not angry or is_down():
		return
	var foe := _nearest_player()
	if foe == null:
		return
	var to := foe.global_position - global_position
	to.y = 0.0
	_cooldown -= delta
	if to.length() > 1.25:
		move_input = to.normalized()
	elif can_act():
		_face(to, delta, 10.0)
		if _cooldown <= 0.0:
			_cooldown = randf_range(attack_gap.x, attack_gap.y)
			request_attack(&"haymaker" if randf() < haymaker_chance else &"swing", foe)


func _nearest_player() -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(GROUP):
		var f := node as Fighter
		if f == null or not is_hostile_to(f) or not f.can_be_targeted() or f.is_down():
			continue
		var d := f.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = f
	return best
