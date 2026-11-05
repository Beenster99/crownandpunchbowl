class_name Director
extends Node
## Runs the crowd in a pub: who is in, how hot the fight is, who gets to swing next,
## newcomers through the door, gang-up rushes, police raids and the win condition.
## One per pub scene. It exists on every peer (so the NPC spawner replicates), but only
## the host thinks.
##
## Heat (0..1) is the pace dial. Players raise it by fighting (hits and knockouts); it decays when they ease off. Heat sets:
##   - how many attack tokens are out (1 up to the difficulty's max_attackers)
##   - how likely onlookers are to wade in
##   - how likely a gang-up rush is (difficulty gang_up_chance)
##   - when a police raid is called (if the pub rolled one, difficulty police_chance)
##   - whether newcomers walk in ready for a fight or just stand and stare
##
## Placement: put Marker3D nodes in these groups in the pub scene, or set the exported
## positions. Groups win when present.
##   npc_door     where newcomers and police walk in (first one found)
##   punter_spot  tables and the bar front, where calm punters hang about
##   staff_spot   behind the bar
##
## Talks to the rest of the game only through Events (fight_started, reinforcements_arrived,
## police_called, pub_cleared, banner) and the queries below. The HUD reads `heat`.

const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
const GROUP := &"director"
## Onlookers within this distance of a hit react to it.
const MATE_RADIUS := 6.0

enum Police { NONE, WAITING, CALLED, ARRIVED }

## Node NPCs are parented to. Defaults to a sibling called "Actors".
@export var actors: Node
@export var door := Vector3(7.0, 0.0, 3.0)
@export var punter_spots: Array[Vector3] = []
@export var staff_spots: Array[Vector3] = []
## Kinds and weights for this pub's crowd.
@export var punter_mix: Dictionary = NpcTypes.DEFAULT_MIX
@export var initial_punters := 8
## Newcomers held back for waves, before the difficulty's `reinforcements` multiplier.
@export var reserve_punters := 8
@export var wave_size := Vector2i(2, 4)
## A wave comes in this often during a fight, or sooner if the room thins out.
@export var wave_interval := 30.0
@export var wave_when_standing_below := 3
@export var heat_decay := 0.025
@export var rush_interval := 8.0
@export var rush_duration := 4.0
@export var police_delay := 8.0
@export var police_count := 2
## Seed for crowd randomness (0 = random).
@export var rng_seed := 0
## Spawn the starting crowd by itself. Turn off to call start() yourself.
@export var auto_start := true

var heat := 0.0
var fight_on := false
var cleared := false
var reserve := 0
var police: Police = Police.NONE
var knockouts := 0

var _rng := RandomNumberGenerator.new()
var _spawner: MultiplayerSpawner
var _next_id := 0
var _tokens: Array[Npc] = []
var _wave_t := 0.0
var _rush_t := 0.0
var _police_t := 0.0
var _police_heat := 2.0
var _started := false


func _ready() -> void:
	add_to_group(GROUP)
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	if actors == null and get_parent() != null:
		actors = get_parent().get_node_or_null("Actors")
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "NpcSpawner"
	_spawner.spawn_function = _spawn_npc
	add_child(_spawner)
	if actors != null:
		_spawner.spawn_path = _spawner.get_path_to(actors)
	Events.hit_landed.connect(_on_hit_landed)
	Events.fighter_knocked_out.connect(_on_knocked_out)
	if auto_start:
		if Net.has_signal(&"all_peers_loaded"):
			Net.connect(&"all_peers_loaded", start, CONNECT_ONE_SHOT)
		else:
			start.call_deferred()


## Spawn the bar staff and the starting crowd. Host only; safe to call once.
func start() -> void:
	if _started or not multiplayer.is_server() or actors == null:
		return
	_started = true
	_read_markers()
	reserve = roundi(reserve_punters * float(GameData.difficulty()["reinforcements"]))
	for i in staff_spots.size():
		spawn(&"staff", staff_spots[i])
	for i in initial_punters:
		var spot := punter_spots[i % punter_spots.size()] if not punter_spots.is_empty() \
			else Vector3.ZERO
		var jitter := Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
		spawn(NpcTypes.pick_weighted(punter_mix, _rng), spot + jitter)


## Spawn one NPC of `kind` at `pos` (host only). Returns it.
func spawn(kind: StringName, pos: Vector3, home := Vector3.INF) -> Npc:
	if not multiplayer.is_server():
		return null
	_next_id += 1
	var npc := _spawner.spawn({
		"name": "N%d" % _next_id, "kind": String(kind), "pos": pos,
		"home": pos if home == Vector3.INF else home,
	}) as Npc
	return npc


func _spawn_npc(data: Variant) -> Node:
	var npc := NPC_SCENE.instantiate() as Npc
	npc.name = data["name"]
	npc.kind = StringName(data["kind"])
	npc.position = data["pos"]
	npc.home = data["home"]
	npc.director = self
	npc.set_multiplayer_authority(1)
	# The networking workstream's NetSync adds position/state synchronisers when present.
	var net_sync: Variant = _global_class(&"NetSync")
	if net_sync != null:
		net_sync.attach(npc, 1)
	return npc


# --- Queries and token API -------------------------------------------------------------

## How many NPCs may be attacking at once right now.
func token_cap() -> int:
	var most := int(GameData.difficulty()["max_attackers"])
	return maxi(1, roundi(lerpf(1.0, float(most), clampf(heat * 1.25, 0.0, 1.0))))


## An NPC asks for a turn to attack. Rushing NPCs always get one. Tokens are spread across
## players so one farmer isn't swamped while another stands idle (rushes excepted).
func request_token(npc: Npc) -> bool:
	_prune_tokens()
	if npc in _tokens:
		return true
	if npc.rushing > 0.0:
		_tokens.append(npc)
		return true
	var cap := token_cap()
	if _tokens.size() >= cap:
		return false
	var players := maxi(1, _standing_players().size())
	var per_target := maxi(1, ceili(float(cap) / players))
	var on_foe := 0
	for t in _tokens:
		if t.foe == npc.foe:
			on_foe += 1
	if on_foe >= per_target:
		return false
	_tokens.append(npc)
	return true


func release_token(npc: Npc) -> void:
	_tokens.erase(npc)


func tokens_out() -> int:
	_prune_tokens()
	return _tokens.size()


## NPCs (punters and police) still to be knocked out, counting ones not yet through the door.
func punters_left() -> int:
	var n := reserve
	for node in get_tree().get_nodes_in_group(&"npcs"):
		if not (node as Fighter).is_ko():
			n += 1
	return n


# --- Host loop -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not _started or cleared:
		return
	heat = maxf(heat - heat_decay * delta, 0.0)
	if not fight_on:
		return
	_tick_waves(delta)
	_tick_rush(delta)
	_tick_police(delta)
	_check_cleared()


func _tick_waves(delta: float) -> void:
	if reserve <= 0:
		return
	_wave_t += delta
	var standing := _standing_npcs().size()
	if _wave_t >= wave_interval or (standing < wave_when_standing_below and _wave_t > 4.0):
		_wave_t = 0.0
		send_wave()


## Newcomers walk in through the door. They're up for it if the room is hot.
func send_wave(count := -1) -> void:
	if count < 0:
		count = _rng.randi_range(wave_size.x, wave_size.y)
	count = mini(count, reserve)
	if count <= 0:
		return
	reserve -= count
	for i in count:
		var npc := spawn(NpcTypes.pick_weighted(punter_mix, _rng), _door_slot(i),
			_inside_from_door())
		if npc == null:
			continue
		if heat >= 0.4:
			npc.engage(_nearest_standing_player(npc.global_position))
		else:
			npc.mood = Npc.Mood.ALERT
	Events.reinforcements_arrived.emit(count)


func _tick_rush(delta: float) -> void:
	_rush_t += delta
	if _rush_t < rush_interval:
		return
	_rush_t = 0.0
	if heat < 0.25:
		return
	if _rng.randf() < float(GameData.difficulty()["gang_up_chance"]) * (0.5 + heat):
		gang_up()


## Several punters round on one player at once. Rugby lads and police may grab them for
## their mates. Returns the NPCs taking part.
func gang_up(victim: Fighter = null) -> Array[Npc]:
	var crew: Array[Npc] = []
	if victim == null:
		var players := _standing_players()
		if players.is_empty():
			return crew
		victim = players[_rng.randi() % players.size()]
	var candidates: Array[Npc] = []
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var npc := node as Npc
		if npc == null or npc.is_down() or npc.state == Fighter.State.HELD:
			continue
		if npc.mood == Npc.Mood.CALM:
			continue
		if npc.global_position.distance_to(victim.global_position) > 9.0:
			continue
		candidates.append(npc)
	if candidates.size() < 2:
		return crew
	candidates.sort_custom(func(a: Npc, b: Npc) -> bool:
		return a.global_position.distance_squared_to(victim.global_position) \
			< b.global_position.distance_squared_to(victim.global_position))
	var size := mini(candidates.size(), int(GameData.difficulty()["max_attackers"]) + 1)
	var grabber_picked := false
	for i in size:
		var npc := candidates[i]
		npc.engage(victim)
		npc.rushing = rush_duration
		if not grabber_picked and bool(npc.type_value("grabs")):
			npc.rush_grab = true
			grabber_picked = true
		crew.append(npc)
	Events.banner.emit("They're ganging up!", 2.0)
	return crew


func _tick_police(delta: float) -> void:
	match police:
		Police.WAITING:
			if heat >= _police_heat or knockouts >= 6:
				call_police()
		Police.CALLED:
			_police_t -= delta
			if _police_t <= 0.0:
				_police_arrive()


## Someone rings the Old Bill. They turn up after `police_delay` seconds.
func call_police() -> void:
	if police == Police.CALLED or police == Police.ARRIVED:
		return
	police = Police.CALLED
	_police_t = police_delay
	Events.police_called.emit()


func _police_arrive() -> void:
	police = Police.ARRIVED
	var count := police_count + GameData.difficulty_index / 2
	for i in count:
		var cop := spawn(&"police", _door_slot(i), _inside_from_door())
		if cop != null:
			cop.engage(_nearest_standing_player(cop.global_position))
	Events.banner.emit("Old Bill's here!", 2.5)


func _check_cleared() -> void:
	if reserve > 0 or police == Police.CALLED:
		return
	if not _standing_npcs().is_empty():
		return
	for node in get_tree().get_nodes_in_group(&"npcs"):
		if not (node as Fighter).is_ko():
			return
	cleared = true
	_tokens.clear()
	Events.pub_cleared.emit(String(GameData.current_pub()["id"]))


# --- Event handlers (host) -------------------------------------------------------------

func _on_hit_landed(info: Dictionary) -> void:
	if not multiplayer.is_server() or not _started:
		return
	var attacker := info.get("attacker") as Fighter
	var victim := info.get("victim") as Fighter
	if attacker == null or victim == null:
		return
	# Nobody hits the bar staff: a stray hit on them never counts towards the fight.
	if victim.team == Fighter.Team.STAFF:
		return
	if attacker.team == Fighter.Team.PLAYERS and victim.team != Fighter.Team.PLAYERS:
		_start_fight()
		heat = minf(heat + (0.08 if bool(info.get("heavy", false)) else 0.05), 1.0)
		_rouse_mates(victim, attacker)
	elif attacker.team != Fighter.Team.PLAYERS and victim.team == Fighter.Team.PLAYERS:
		heat = minf(heat + 0.02, 1.0)


func _on_knocked_out(fighter: Node) -> void:
	if not multiplayer.is_server() or not _started:
		return
	var f := fighter as Fighter
	if f == null:
		return
	if f is Npc:
		release_token(f)
	if f.team == Fighter.Team.PUNTERS or f.team == Fighter.Team.POLICE:
		knockouts += 1
		heat = minf(heat + 0.1, 1.0)


func _start_fight() -> void:
	if fight_on:
		return
	fight_on = true
	_wave_t = 0.0
	if _rng.randf() < float(GameData.difficulty()["police_chance"]):
		police = Police.WAITING
		_police_heat = _rng.randf_range(0.45, 0.8)
	for node in get_tree().get_nodes_in_group(&"npcs"):
		(node as Npc).alert()
	Events.fight_started.emit()


## Mates near a punter who's been hit either wade in (bravery roll) or start watching.
func _rouse_mates(victim: Fighter, attacker: Fighter) -> void:
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var npc := node as Npc
		if npc == null or npc == victim or npc.is_down() or npc.mood == Npc.Mood.ENGAGED:
			continue
		if npc.global_position.distance_to(victim.global_position) > MATE_RADIUS:
			continue
		if _rng.randf() < float(npc.type_value("bravery")):
			npc.engage(attacker)
		else:
			npc.alert()


# --- Helpers ---------------------------------------------------------------------------

func _read_markers() -> void:
	var door_marker := get_tree().get_first_node_in_group(&"npc_door") as Node3D
	if door_marker != null:
		door = door_marker.global_position
	var spots := _marker_positions(&"punter_spot")
	if not spots.is_empty():
		punter_spots = spots
	var staff := _marker_positions(&"staff_spot")
	if not staff.is_empty():
		staff_spots = staff


func _marker_positions(group: StringName) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for n in get_tree().get_nodes_in_group(group):
		if n is Node3D:
			out.append((n as Node3D).global_position)
	return out


## Spread newcomers out in a short line just inside the door.
func _door_slot(i: int) -> Vector3:
	var inward := _inside_from_door() - door
	inward.y = 0.0
	inward = inward.normalized() if inward.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-inward.z, 0.0, inward.x)
	return door + side * (float(i % 3) - 1.0) * 0.9 + inward * (0.4 + float(i / 3) * 0.9)


## A point a few metres into the room from the door, used as newcomers' home.
func _inside_from_door() -> Vector3:
	var centre := Vector3.ZERO
	if not punter_spots.is_empty():
		for s in punter_spots:
			centre += s
		centre /= punter_spots.size()
	var to := centre - door
	to.y = 0.0
	return door + (to.normalized() * minf(3.0, to.length()) if to.length() > 0.01 else Vector3.ZERO)


func _prune_tokens() -> void:
	for i in range(_tokens.size() - 1, -1, -1):
		var t := _tokens[i]
		if not is_instance_valid(t) or t.is_down() or not t.is_inside_tree():
			_tokens.remove_at(i)


func _standing_players() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f != null and f.team == Fighter.Team.PLAYERS and not f.is_down():
			out.append(f)
	return out


func _standing_npcs() -> Array[Fighter]:
	var out: Array[Fighter] = []
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var f := node as Fighter
		if f != null and not f.is_down():
			out.append(f)
	return out


func _nearest_standing_player(pos: Vector3) -> Fighter:
	var best: Fighter = null
	var best_d := INF
	for f in _standing_players():
		var d := f.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = f
	return best


static func _global_class(class_id: StringName) -> Variant:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == class_id:
			return load(c["path"])
	return null
