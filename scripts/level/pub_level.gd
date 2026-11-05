class_name PubLevel
extends Node3D
## Base script for every pub scene. It builds the greybox pub (subclasses override
## `_build`), sets up lighting, the BrawlCamera and occluder fading, spawns players and
## props on markers, and runs the pub flow:
##
##   ARRIVING  banner, everyone's civilised
##   CALM      drinks and food, until someone kicks off
##   FIGHT     Events.fight_started; waits until every hostile is knocked out
##   CLEARED   Events.pub_cleared; host moves everyone to the next pub
##   LOST      every player knocked out; host restarts this pub
##
## Other workstreams find the level with `PubLevel.current()` and read markers with
## `get_markers(kind)`. See docs/PUBS.md for the marker contract.

signal phase_changed(phase: Phase)

enum Phase { ARRIVING, CALM, FIGHT, CLEARED, LOST }

# Marker kinds (child node names under Markers/).
const PLAYERS := "PlayerSpawns"
const PUNTER := "PunterSpots"
const STAFF := "StaffSpots"
const DOORS := "DoorSpawns"
const POLICE := "PoliceSpawns"
const PROPS := "PropSpawns"
const BAR_ZONES := "BarZones"

const GAME_UI_SCENE := preload("res://scenes/ui/game_ui.tscn")
const MENU_SCENE := "res://scenes/main/main_menu.tscn"
const ITEM_SCENE_PATH := "res://scenes/items/%s.tscn"

## Key into GameData.PUBS.
@export var pub_id := ""
## Key into PubEra.STYLES.
@export var era := "17th"
## Floor area of the pub (x, z, width, depth). The camera stays over it.
@export var room := Rect2(-8, -6, 16, 12)
## Seconds of "civilised" banner before the pub settles into CALM.
@export var arrival_time := 3.0
## Seconds after the pub is cleared before moving on.
@export var clear_delay := 5.0
## How far from the front wall the camera's framing centre stops.
@export var camera_front_margin := 3.5
## Drop greybox stand-ins on prop markers that have no item scene yet.
@export var spawn_placeholders := true
## Spawn the AI crowd (bar staff, punters, waves, police). Tests can turn it off.
@export var crowd := true

var phase := Phase.ARRIVING
var builder: PubBuilder
var camera: BrawlCamera
var fader: OccluderFader
var items: PubItems
var spawner: PlayerSpawner
var coop: CoopRules
var director: Director
## AI director sets this while more punters (or police) are still on their way in,
## so the pub doesn't count as cleared between waves.
var arrivals_pending := 0

var _knocked_out := {}
var _items_spawned := 0
var _flicker := FastNoiseLite.new()
var _time := 0.0


## The pub currently loaded, or null.
static func current() -> PubLevel:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene as PubLevel if tree else null


func _ready() -> void:
	for child_name in ["World", "Actors", "Items", "Markers"]:
		if not has_node(child_name):
			var n := Node3D.new()
			n.name = child_name
			add_child(n)
	builder = PubBuilder.new(self, $World, $Markers, PubEra.get_style(era))
	_build(builder)
	_build_environment()
	items = PubItems.install(self)
	_spawn_props()
	add_child(GAME_UI_SCENE.instantiate())  # HUD and pause menu
	camera = BrawlCamera.new()
	camera.name = "BrawlCamera"
	# Keep the framing centre inside the room. The front margin is bigger because the
	# camera looks down from the front: centring near the front wall shows the street.
	camera.bounds = Rect2(room.position + Vector2(2.0, 1.5), room.size - Vector2(4.0, 1.5 + camera_front_margin))
	add_child(camera)
	fader = OccluderFader.new()
	fader.name = "OccluderFader"
	fader.camera = camera
	add_child(fader)
	Events.fight_started.connect(_on_fight_started)
	Events.hit_landed.connect(_on_hit_landed)
	Events.fighter_knocked_out.connect(_on_knocked_out)
	# Connected before CoopRules exists so the crawl count is updated before anyone reacts.
	Events.pub_cleared.connect(_on_pub_cleared)
	Events.all_players_down.connect(_on_all_players_down)
	_setup_players()
	coop = CoopRules.new()
	coop.name = "CoopRules"
	coop.handle_pub_flow = false  # this level runs the pub-to-pub flow itself
	add_child(coop)
	if crowd:
		_setup_director()
	camera.snap()
	var pub := GameData.current_pub()
	Events.banner.emit("%s  ·  %s" % [pub["name"], pub["era"]], arrival_time)
	get_tree().create_timer(arrival_time).timeout.connect(func():
		if phase == Phase.ARRIVING:
			_set_phase(Phase.CALM))
	# Tell the host this peer has the pub loaded; it spawns players (and the crowd)
	# once every peer has.
	Net.level_ready()


## Override in each pub: build the room with `b` (a PubBuilder).
func _build(_b: PubBuilder) -> void:
	pass


# --- Queries for other workstreams -----------------------------------------------

func get_markers(kind: String) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var parent := get_node_or_null("Markers/" + kind)
	if parent:
		for c in parent.get_children():
			if c is Marker3D:
				out.append(c)
	return out


func get_bar_zones() -> Array[Area3D]:
	var out: Array[Area3D] = []
	var parent := get_node_or_null("Markers/" + BAR_ZONES)
	if parent:
		for c in parent.get_children():
			if c is Area3D:
				out.append(c)
	return out


func actors_root() -> Node3D:
	return $Actors


func items_root() -> Node3D:
	return $Items


func is_fighting() -> bool:
	return phase == Phase.FIGHT


# --- Flow ----------------------------------------------------------------------

func _set_phase(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


func _on_hit_landed(info: Dictionary) -> void:
	if not multiplayer.is_server() or phase != Phase.ARRIVING and phase != Phase.CALM:
		return
	var a: Node = info.get("attacker")
	var v: Node = info.get("victim")
	if a == null or v == null or v.is_in_group("staff"):
		return
	if a.is_in_group("players") or v.is_in_group("players"):
		Events.fight_started.emit()


func _on_fight_started() -> void:
	if phase == Phase.ARRIVING or phase == Phase.CALM:
		_set_phase(Phase.FIGHT)


func _on_knocked_out(fighter: Node) -> void:
	_knocked_out[fighter] = true
	if not multiplayer.is_server():
		return
	# Wipes are CoopRules' job (downed counts, not just KO). With an AI director in
	# the pub it owns the win condition (waves and police still to come).
	if not fighter.is_in_group("players") and director == null:
		check_cleared()


func _is_out(n: Node) -> bool:
	if _knocked_out.has(n):
		return true
	if n.has_method("is_knocked_out"):
		return n.is_knocked_out()
	return false


## Hostile = NPCs and police who aren't bar staff.
func hostiles() -> Array[Node]:
	var out: Array[Node] = []
	for group in ["npcs", "police"]:
		for n in get_tree().get_nodes_in_group(group):
			if not n.is_in_group("staff") and not out.has(n):
				out.append(n)
	return out


func check_cleared() -> void:
	if not multiplayer.is_server() or phase != Phase.FIGHT or arrivals_pending > 0:
		return
	var any_out := false
	for n in hostiles():
		if not _is_out(n):
			return
		any_out = true
	for n in _knocked_out:
		if is_instance_valid(n) and not n.is_in_group("players"):
			any_out = true
	if any_out:
		pub_cleared()


## Host: mark the pub cleared and move on after `clear_delay`. Public so tests and
## debug tools can force it.
func pub_cleared() -> void:
	if phase == Phase.CLEARED:
		return
	Events.pub_cleared.emit(pub_id)


func _on_pub_cleared(_id: String) -> void:
	if phase == Phase.CLEARED:
		return
	_set_phase(Phase.CLEARED)
	GameData.pubs_cleared += 1
	if not multiplayer.is_server():
		return
	if GameData.crawl_finished():
		_announce.rpc("Every pub in the village is yours. Time, gentlemen, please!", clear_delay)
		get_tree().create_timer(clear_delay).timeout.connect(func(): _back_to_menu.rpc())
		return
	var next := GameData.next_pub_index()
	_announce.rpc("%s is cleared. On to %s!" % [GameData.current_pub()["name"], GameData.PUBS[next]["name"]], clear_delay)
	get_tree().create_timer(clear_delay).timeout.connect(func():
		_sync_cleared.rpc(GameData.pubs_cleared)
		Net.next_pub())


func _on_all_players_down() -> void:
	if phase != Phase.CLEARED:
		_set_phase(Phase.LOST)


@rpc("authority", "call_local", "reliable")
func _announce(text: String, seconds: float) -> void:
	Events.banner.emit(text, seconds)


## Keeps clients' crawl count in step with the host before the next pub loads.
@rpc("authority", "call_remote", "reliable")
func _sync_cleared(cleared: int) -> void:
	GameData.pubs_cleared = cleared


@rpc("authority", "call_local", "reliable")
func _back_to_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Spawning ------------------------------------------------------------------

func _setup_players() -> void:
	spawner = PlayerSpawner.new()
	var points: Array[Vector3] = []
	for m in get_markers(PLAYERS):
		points.append(m.position)
	if points.is_empty():
		for i in 4:
			points.append(Vector3(-1.5 + i, 0.0, room.end.y - 1.5))
	spawner.spawn_points = points
	add_child(spawner)
	spawner.setup($Actors)
	spawner.player_spawned.connect(func(p: Node3D):
		camera.targets.append(p)
		camera.snap())


func _setup_director() -> void:
	director = Director.new()
	director.name = "Director"
	director.actors = $Actors
	var doors := get_markers(DOORS)
	if not doors.is_empty():
		director.door = doors[0].global_position
	var spots: Array[Vector3] = []
	for m in get_markers(PUNTER):
		spots.append(m.global_position)
	director.punter_spots = spots
	var staff: Array[Vector3] = []
	for m in get_markers(STAFF):
		staff.append(m.global_position)
	director.staff_spots = staff
	director.initial_punters = mini(maxi(spots.size(), 4), 10)
	add_child(director)


func _spawn_props() -> void:
	var placeholder_root := Node3D.new()
	placeholder_root.name = "Placeholders"
	$World.add_child(placeholder_root)
	for m in get_markers(PROPS):
		var kind: String = m.get_meta("item", "")
		var path := ITEM_SCENE_PATH % kind
		if ItemData.KINDS.has(StringName(kind)):
			# Pickups and weapons from the items workstream, named identically on every peer.
			items.add_item(StringName(kind), m.global_position, m.global_rotation.y)
		elif ResourceLoader.exists(path):
			var item := (load(path) as PackedScene).instantiate() as Node3D
			item.name = "I%d" % _items_spawned
			_items_spawned += 1
			$Items.add_child(item)
			item.global_transform = m.global_transform
		elif spawn_placeholders:
			_placeholder(placeholder_root, kind, m)


func _placeholder(parent: Node3D, kind: String, m: Marker3D) -> void:
	var b := builder
	var wood := b.material(b.style["furniture"])
	var root := Node3D.new()
	root.name = kind.to_pascal_case()
	root.transform = m.transform
	parent.add_child(root)
	match kind:
		"table":
			var body := b.solid(Vector3(1.1, 0.78, 1.1), Vector3(0, 0.39, 0), wood, 0.0, root, false)
			b.deco(body, Vector3(1.1, 0.06, 1.1), Vector3(0, 0.36, 0), wood)
			for x in [-0.45, 0.45]:
				for z in [-0.45, 0.45]:
					b.deco(body, Vector3(0.07, 0.72, 0.07), Vector3(x, -0.03, z), wood)
		"chair":
			var body := b.solid(Vector3(0.45, 0.95, 0.45), Vector3(0, 0.475, 0), wood, 0.0, root, false)
			b.deco(body, Vector3(0.45, 0.05, 0.45), Vector3(0, -0.03, 0), wood)
			b.deco(body, Vector3(0.45, 0.5, 0.05), Vector3(0, 0.24, 0.2), wood)
			for x in [-0.19, 0.19]:
				for z in [-0.19, 0.19]:
					b.deco(body, Vector3(0.05, 0.45, 0.05), Vector3(x, -0.25, z), wood)
		"stool":
			var body := b.solid(Vector3(0.36, 0.72, 0.36), Vector3(0, 0.36, 0), wood, 0.0, root, false)
			b.deco(body, Vector3(0.36, 0.05, 0.36), Vector3(0, 0.34, 0), wood)
			for x in [-0.13, 0.13]:
				for z in [-0.13, 0.13]:
					b.deco(body, Vector3(0.04, 0.7, 0.04), Vector3(x, -0.01, z), wood)
		"bottle":
			b.cylinder(root, 0.04, 0.28, Vector3(0, 0.14, 0), b.material(Color("1f5a2a"), 0.1, 0.2))
		"glass", "pint":
			b.cylinder(root, 0.045, 0.15, Vector3(0, 0.075, 0), b.material(Color("c9862a") if kind == "pint" else Color("d8e4e0"), 0.1, 0.15))
		"plate":
			b.cylinder(root, 0.13, 0.02, Vector3(0, 0.01, 0), b.material(Color("e8e2d0")))
			b.sphere(root, 0.06, Vector3(0, 0.05, 0), b.material(Color("a8642a")))
		"pool_cue":
			var cue := b.cylinder(root, 0.015, 1.45, Vector3(0, 0.02, 0), b.material(Color("b8925a")))
			cue.rotation.z = PI * 0.5
		"darts":
			for i in 3:
				b.cylinder(root, 0.008, 0.15, Vector3(-0.04 + i * 0.04, 0.9, 0), b.material(Color("c9a03a"), 0.8))
		"poker", "fire_tongs", "fire_shovel":
			b.cylinder(root, 0.015, 0.8, Vector3(0, 0.4, 0), b.material(Color("2a2a2a"), 0.8, 0.4))
		_:
			b.deco(root, Vector3(0.2, 0.2, 0.2), Vector3(0, 0.1, 0), b.material(Color.MAGENTA))


# --- Lighting ------------------------------------------------------------------

func _build_environment() -> void:
	var s := builder.style
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = s["background"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = s["ambient"]
	env.ambient_light_energy = float(s["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = s["fog"]
	env.fog_density = float(s["fog_density"])
	env.ssao_enabled = bool(Settings.get_value("graphics", "shadows"))
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
	# Weak key light so shapes read and everyone casts a shadow on the floor.
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-62, 25, 0)
	key.light_energy = 0.3
	key.light_color = Color("ffe2b8")
	key.shadow_enabled = bool(Settings.get_value("graphics", "shadows"))
	add_child(key)
	_flicker.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_flicker.frequency = 2.5
	for l in builder.flicker_lights:
		l.set_meta("base_energy", l.light_energy)


func _process(delta: float) -> void:
	_time += delta
	var i := 0
	for l in builder.flicker_lights:
		if is_instance_valid(l):
			var base: float = l.get_meta("base_energy", l.light_energy)
			l.light_energy = base * (0.85 + 0.15 * _flicker.get_noise_2d(_time * 10.0, i * 37.0))
		i += 1
