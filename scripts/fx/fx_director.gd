class_name FxDirector
extends Node
## Autoload `Fx`: turns gameplay `Events` into cosmetic feedback. Impact sounds, oofs and
## grunts, moaning crawlers, blood, hit-stop and screen shake.
##
## It only listens. Gameplay never calls into it, so it can be tuned or swapped freely.
## Events fire on every peer (see CONVENTIONS.md), so each machine plays its own FX.
##
## Optional hooks a fighter can provide (all have fallbacks):
## - `get_head_position() -> Vector3` or a child Node3D named "Head" (fallback: 1.5 m up)
## - `voice: String` property or "voice" meta, "f" for a female voice (fallback: "m")
## - `is_down() -> bool` (Fighter API): stops crawl moaning once they get back up
## A hit's `info` can also carry `"sound": "<cue>"` to override the impact cue.

## Substring of the move name -> impact cue. First match wins.
const MOVE_CUES := [
	["headbutt", "headbutt"], ["kick", "kick"], ["stomp", "kick"],
	["bottle", "glass_clink"], ["glass", "glass_clink"], ["pint", "glass_clink"],
	["chair", "wood_hit"], ["stool", "wood_hit"], ["table", "wood_hit"], ["leg", "wood_hit"],
	["cue", "wood_hit"], ["poker", "wood_hit"], ["tongs", "wood_hit"], ["shovel", "wood_hit"],
	["baton", "wood_hit"],
]
const GLASS_WORDS := ["bottle", "glass", "pint", "jug", "mirror", "window"]

@export_group("Hit-stop")
@export var hit_stop_light := 0.035
@export var hit_stop_heavy := 0.085
@export var hit_stop_nose := 0.14
@export var hit_stop_time_scale := 0.05

@export_group("Shake")
@export var shake_light := 0.12
@export var shake_heavy := 0.32
@export var shake_nose := 0.45
@export var shake_local_victim := 1.5  ## multiplier when your own farmer gets hit

@export_group("Voice")
@export var oof_chance := 0.75
@export var grunt_chance := 0.3
@export var crawl_moan_every := Vector2(2.2, 4.5)
@export var ko_moan_every := Vector2(8.0, 16.0)
@export var ko_moan_chance := 0.4
@export var max_ko_moaners := 4

@export_group("Blood")
@export var face_blood_per_face_hit := 0.12
@export var crawl_smear_step := 0.45

@export_group("Falls")
@export var fall_shake_per_metre := 0.15
@export var fall_blood_per_metre := 0.45

@export_group("Pools")
@export var sfx_voices := 24
@export var voice_voices := 12

var blood: BloodFx

var _sfx: Array[AudioStreamPlayer3D] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: AudioStreamPlayer
## fighter instance id -> {player, priority}
var _speaking := {}
## fighter instance id -> {fighter, next, last_pos}
var _crawlers := {}
var _knocked_out := {}
var _hit_stop_until := 0
var _hit_stop_base := 1.0
var _hit_stop_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	blood = BloodFx.new()
	blood.name = "Blood"
	add_child(blood)
	for i in sfx_voices:
		_sfx.append(_make_player("SFX"))
	for i in voice_voices:
		_voices.append(_make_player("Voice"))
	_flat = AudioStreamPlayer.new()
	_flat.bus = "SFX"
	add_child(_flat)
	Events.hit_landed.connect(_on_hit_landed)
	Events.nose_broken.connect(_on_nose_broken)
	Events.fighter_knocked_down.connect(_on_knocked_down)
	Events.fighter_crawling.connect(_on_crawling)
	Events.fighter_knocked_out.connect(_on_knocked_out)
	Events.grab_started.connect(_on_grab_started)
	Events.item_broken.connect(_on_item_broken)
	Events.drink_ordered.connect(_on_drink)
	Events.food_ordered.connect(_on_food)
	Events.police_called.connect(func(): play_flat("police_whistle"))
	Events.reinforcements_arrived.connect(func(_n): play_flat("door_bang"))
	# Added by the combat PR; connected by name so this works before and after it lands.
	_connect_optional("fighter_thrown_off_ledge", _on_thrown_off_ledge)
	_connect_optional("fighter_fell", _on_fell)
	_connect_optional("fighter_got_up", _on_got_up)
	if OS.is_debug_build() and DisplayServer.get_name() != "headless":
		add_child(FxDebug.new())


func _exit_tree() -> void:
	Engine.time_scale = _hit_stop_base if _hit_stop_active else Engine.time_scale
	SoundBank.clear_cache()


func _process(_delta: float) -> void:
	if _hit_stop_active and Time.get_ticks_usec() >= _hit_stop_until:
		_hit_stop_active = false
		Engine.time_scale = _hit_stop_base
	var now := Time.get_ticks_msec() / 1000.0
	_tick_crawlers(now)
	_tick_knocked_out(now)


# --------------------------------------------------------------------------- public API

## Play a positional cue. Returns the player used (or null).
func play(cue: String, pos: Vector3, volume_db := 0.0) -> AudioStreamPlayer3D:
	if not SoundBank.has_cue(cue):
		push_warning("Fx: unknown cue %s" % cue)
		return null
	var p := _take(_sfx)
	_start(p, cue, pos, volume_db, 1.0)
	return p


## A non-positional cue (whistles, the door going).
func play_flat(cue: String) -> void:
	if not SoundBank.has_cue(cue):
		return
	var c: Dictionary = SoundBank.CUES[cue]
	_flat.bus = c["bus"]
	_flat.stream = SoundBank.stream(cue)
	_flat.volume_db = float(c["db"])
	_flat.play()


## Make a fighter say something. `kind` is oof, grunt, groan, moan, ko or ahh.
## A fighter only says one thing at a time; higher priority interrupts lower.
func say(fighter: Node, kind: String, priority := 1) -> void:
	if not _valid(fighter):
		return
	var cue := "%s_%s" % [kind, voice_of(fighter)]
	if not SoundBank.has_cue(cue):
		cue = kind + "_m"
	var id := fighter.get_instance_id()
	var cur: Dictionary = _speaking.get(id, {})
	if not cur.is_empty() and is_instance_valid(cur["player"]) and cur["player"].playing:
		if int(cur["priority"]) > priority:
			return
		cur["player"].stop()
	var p := _take(_voices)
	_start(p, cue, head_position(fighter), 0.0, _pitch_of(fighter))
	_speaking[id] = {"player": p, "priority": priority}


## Freeze the action for a few frames. Only real time is used, so it can't get stuck.
func hit_stop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if not _hit_stop_active:
		_hit_stop_base = Engine.time_scale
		_hit_stop_active = true
	Engine.time_scale = minf(_hit_stop_base, hit_stop_time_scale)
	_hit_stop_until = maxi(_hit_stop_until, Time.get_ticks_usec() + int(seconds * 1_000_000.0))


func shake(amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("add_shake"):
		cam.add_shake(amount)


func is_crawling(fighter: Node) -> bool:
	return _valid(fighter) and _crawlers.has(fighter.get_instance_id())


static func head_position(fighter: Node) -> Vector3:
	if fighter.has_method("get_head_position"):
		return fighter.get_head_position()
	var head := fighter.get_node_or_null("Head") as Node3D
	if head:
		return head.global_position
	return (fighter as Node3D).global_position + Vector3.UP * 1.5


static func voice_of(fighter: Node) -> String:
	var v: Variant = fighter.get("voice")
	if v == null:
		v = fighter.get_meta("voice", "m")
	return "f" if String(v).begins_with("f") else "m"


# --------------------------------------------------------------------------- event handlers

func _on_hit_landed(info: Dictionary) -> void:
	var victim: Variant = info.get("victim")
	var attacker: Variant = info.get("attacker")
	var has_victim := _valid(victim)
	var pos: Vector3 = info.get("position", head_position(victim) if has_victim else Vector3.ZERO)
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var move := String(info.get("move", "punch")).to_lower()
	var heavy := bool(info.get("heavy", false))
	var to_face := bool(info.get("to_face", false)) or move.contains("headbutt")
	var damage := float(info.get("damage", 10.0))

	var cue := String(info.get("sound", ""))
	if not SoundBank.has_cue(cue):
		cue = impact_cue(move, to_face)
	play(cue, pos, 2.0 if heavy else 0.0)

	if _valid(attacker) and randf() < grunt_chance:
		say(attacker, "grunt", 0)
	if has_victim and (heavy or randf() < oof_chance):
		say(victim, "oof", 1)

	# Blood: faces bleed, heavy body shots sometimes do.
	if has_victim and (to_face or (heavy and randf() < 0.4)):
		var intensity := clampf(damage / 12.0, 0.3, 1.6) * (1.3 if heavy else 1.0)
		blood.spray(pos, dir, intensity)
		if to_face:
			blood.add_face_blood(victim, face_blood_per_face_hit * (1.5 if heavy else 1.0))
		if heavy:
			play("blood_splat", pos)

	var local_victim := _is_local_player(victim)
	if local_victim or _is_local_player(attacker):
		hit_stop(hit_stop_heavy if heavy else hit_stop_light)
	shake((shake_heavy if heavy else shake_light) * (shake_local_victim if local_victim else 1.0))


func _on_nose_broken(fighter: Node) -> void:
	if not _valid(fighter):
		return
	var head := head_position(fighter)
	var f3 := fighter as Node3D
	var fwd := -f3.global_basis.z
	play("nose_crunch", head, 2.0)
	play("blood_splat", head)
	_later(0.12, say.bind(fighter, "groan", 2), fighter)
	blood.spray(head + fwd * 0.2, fwd + Vector3.DOWN * 0.3, 1.8)
	blood.add_face_blood(fighter, 0.6)
	# A nosebleed keeps dripping for a bit.
	for i in 4:
		_later(0.6 + i * 0.5, func():
			if _valid(fighter):
				blood.floor_decal(head_position(fighter) + fwd * 0.15, randf_range(0.12, 0.22), "splat"), fighter)
	hit_stop(hit_stop_nose)
	shake(shake_nose)


func _on_knocked_down(fighter: Node) -> void:
	if not _valid(fighter):
		return
	play("body_fall", (fighter as Node3D).global_position)
	if blood.face_blood(fighter) > 0.3:
		blood.floor_decal(head_position(fighter), randf_range(0.3, 0.5), "splat")
	shake(shake_light)


func _on_crawling(fighter: Node) -> void:
	if not _valid(fighter):
		return
	blood.add_face_blood(fighter, 0.8)
	var now := Time.get_ticks_msec() / 1000.0
	_crawlers[fighter.get_instance_id()] = {
		"fighter": fighter, "next": now + randf_range(0.6, 1.2),
		"last_pos": (fighter as Node3D).global_position,
	}


func _on_knocked_out(fighter: Node) -> void:
	if not _valid(fighter):
		return
	var id := fighter.get_instance_id()
	_crawlers.erase(id)
	say(fighter, "ko", 3)
	play("body_fall", (fighter as Node3D).global_position, 2.0)
	if blood.face_blood(fighter) > 0.2:
		_later(0.5, func():
			if _valid(fighter):
				blood.pool(head_position(fighter) + Vector3.DOWN * 1.0), fighter)
	shake(shake_heavy)
	var now := Time.get_ticks_msec() / 1000.0
	_knocked_out[id] = {"fighter": fighter, "next": now + randf_range(ko_moan_every.x, ko_moan_every.y)}


func _on_grab_started(holder: Node, victim: Node) -> void:
	if _valid(victim):
		play("grab", head_position(victim) + Vector3.DOWN * 0.4)
		say(victim, "grunt", 1)
	elif _valid(holder):
		play("grab", (holder as Node3D).global_position + Vector3.UP)


func _on_item_broken(item: Node) -> void:
	if not (item is Node3D) or not is_instance_valid(item):
		return
	var pos := (item as Node3D).global_position
	play("glass_smash" if is_glass(item) else "wood_break", pos)
	shake(shake_light)


func _on_drink(player: Node) -> void:
	if not _valid(player):
		return
	play("gulp", head_position(player))
	_later(0.75, say.bind(player, "ahh", 0), player)


func _on_food(player: Node) -> void:
	if _valid(player):
		play("munch", head_position(player))


func _on_thrown_off_ledge(fighter: Node, thrower: Node, railing: bool) -> void:
	if not _valid(fighter):
		return
	var pos := (fighter as Node3D).global_position + Vector3.UP * 0.9
	if railing:
		play("wood_break", pos, 3.0)
		play("wood_hit", pos)
		shake(shake_heavy)
		if _is_local_player(fighter) or _is_local_player(thrower):
			hit_stop(hit_stop_heavy)
	else:
		play("whoosh", pos, 6.0)
	say(fighter, "oof", 2)
	if _valid(thrower) and randf() < 0.6:
		say(thrower, "grunt", 0)


func _on_fell(fighter: Node, height: float) -> void:
	if not _valid(fighter):
		return
	var feet := (fighter as Node3D).global_position
	var h := maxf(height, 0.5)
	play("body_fall", feet, clampf(h * 1.5, 2.0, 8.0))
	play("kick", feet, -2.0)  # extra low-end thump under the fall
	play("blood_splat", feet)
	_later(0.25, say.bind(fighter, "groan", 2))
	var head := head_position(fighter)
	var amount := clampf(h * fall_blood_per_metre, 0.4, 2.0)
	blood.spray(feet + Vector3.UP * 0.3, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), amount)
	blood.floor_decal(Vector3(head.x, feet.y, head.z), randf_range(0.5, 0.8) * minf(amount, 1.5), "splat")
	blood.add_face_blood(fighter, clampf(h * 0.12, 0.1, 0.5))
	var local := _is_local_player(fighter)
	shake(clampf(h * fall_shake_per_metre, shake_light, 1.0) * (shake_local_victim if local else 1.0))
	if local:
		hit_stop(hit_stop_heavy)


func _on_got_up(fighter: Node) -> void:
	if _valid(fighter):
		_crawlers.erase(fighter.get_instance_id())
		_knocked_out.erase(fighter.get_instance_id())


# --------------------------------------------------------------------------- helpers

func _connect_optional(signal_name: String, fn: Callable) -> void:
	if Events.has_signal(signal_name):
		Events.connect(signal_name, fn)


static func impact_cue(move: String, to_face: bool) -> String:
	for pair in MOVE_CUES:
		if move.contains(pair[0]):
			return pair[1]
	return "punch_face" if to_face else "punch_body"


static func is_glass(item: Node) -> bool:
	var m: Variant = item.get("material")
	var key := (String(m) if m is String else String(item.name)).to_lower()
	for w in GLASS_WORDS:
		if key.contains(w):
			return true
	return false


func _tick_crawlers(now: float) -> void:
	for id in _crawlers.keys():
		var c: Dictionary = _crawlers[id]
		var f: Variant = c["fighter"]
		if not _valid(f) or (f.has_method("is_down") and not f.is_down()):
			_crawlers.erase(id)
			continue
		var pos := (f as Node3D).global_position
		var moved: Vector3 = pos - c["last_pos"]
		if moved.length() >= crawl_smear_step:
			blood.smear(pos, moved)
			c["last_pos"] = pos
		if now >= float(c["next"]):
			say(f, "moan" if randf() < 0.7 else "groan", 1)
			c["next"] = now + randf_range(crawl_moan_every.x, crawl_moan_every.y)


func _tick_knocked_out(now: float) -> void:
	var moaners := 0
	for id in _knocked_out.keys():
		var c: Dictionary = _knocked_out[id]
		var f: Variant = c["fighter"]
		if not _valid(f):
			_knocked_out.erase(id)
			continue
		if now >= float(c["next"]):
			c["next"] = now + randf_range(ko_moan_every.x, ko_moan_every.y)
			if moaners < max_ko_moaners and randf() < ko_moan_chance:
				say(f, "moan", 0)
				moaners += 1


func _make_player(bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 6.0
	p.panning_strength = 0.6
	add_child(p)
	return p


func _take(pool: Array[AudioStreamPlayer3D]) -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = pool[0]
	for p in pool:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	oldest.stop()
	return oldest


func _start(p: AudioStreamPlayer3D, cue: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	var c: Dictionary = SoundBank.CUES[cue]
	p.stream = SoundBank.stream(cue)
	p.bus = c["bus"]
	p.volume_db = float(c["db"]) + volume_db
	p.max_distance = float(c["range"])
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


## Each fighter gets a stable voice pitch so punters don't all sound like twins.
func _pitch_of(fighter: Node) -> float:
	var h := absi(hash(String(fighter.name))) % 1000
	return 0.9 + float(h) / 1000.0 * 0.2


func _valid(n: Variant) -> bool:
	return is_instance_valid(n) and n is Node3D and (n as Node).is_inside_tree()


func _is_local_player(n: Variant) -> bool:
	return _valid(n) and (n as Node).is_in_group("players") and (n as Node).is_multiplayer_authority()


## Run `fn` after `seconds`. If `subject` is given and has been freed by then, skip it
## (calling a callable that captured or bound a freed node logs an error).
func _later(seconds: float, fn: Callable, subject: Object = null) -> void:
	var ref: WeakRef = weakref(subject) if subject != null else null
	get_tree().create_timer(seconds, false).timeout.connect(func():
		if ref == null or ref.get_ref() != null:
			fn.call())
