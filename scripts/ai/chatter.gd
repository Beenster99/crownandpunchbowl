class_name Chatter
extends Node
## Overheard pub chatter. While the pub is calm, second-homers pair up with whoever is standing
## nearby (another second-homer, or a local who'd rather be anywhere else) and talk at them:
## dogs, Agas, tax, single malts. Lines come from ChatterLines. Each one shows as a speech
## bubble over the speaker's head and plays a voice: a recorded file if there is one, else a
## synthesised murmur (or the OS text-to-speech voice, if turned on).
##
## It all stops the moment the pub turns violent: any hit, the fight starting, or a talker
## leaving CALM. A talker may yelp an `interrupt` line on the way out. Chatter comes back
## once the heat has died down and nobody's thrown a punch for `resume_after` seconds.
##
## One per pub. The Director adds it as a child called "Chatter". The host picks who talks
## and what they say; every peer shows the bubbles and plays the voices (via RPC), so it is
## purely cosmetic and never touches gameplay apart from asking the two talkers to stand
## still and face each other (Npc.chatting_with).

signal line_said(speaker: Node, line_key: String, text: String)
signal conversation_started(a: Node, b: Node)
signal conversation_ended(a: Node, b: Node, interrupted: bool)

enum VoiceMode { MURMUR, TTS, SILENT }

## Who starts conversations.
@export var talker_kinds: Array[StringName] = [&"second_homer"]
## Who they'll talk at. Second-homers answer properly; anyone else gets ChatterLines "local".
@export var listener_kinds: Array[StringName] = [&"second_homer", &"local", &"rugby_lad"]
@export var max_conversations := 2
@export var talk_distance := 3.0
## Seconds between attempts to start a conversation.
@export var start_every := Vector2(2.0, 5.0)
## A talker rests this long after a conversation before starting another.
@export var talker_rest := Vector2(8.0, 18.0)
## Rounds of back-and-forth after the opening exchange.
@export var rounds := Vector2i(1, 3)
@export var change_topic_chance := 0.35
@export var close_chance := 0.5
## Director heat above this counts as violent.
@export var quiet_heat := 0.08
## Seconds after the last hit before anyone feels like chatting again.
@export var resume_after := 12.0
@export var interrupt_chance := 0.7
@export var voice_mode := VoiceMode.MURMUR
@export var voice_db := -9.0
@export var voice_range := 14.0
## Bubbles follow Settings gameplay/subtitles. Turn this off to hide them regardless.
@export var show_bubbles := true

var director: Node = null

var _rng := RandomNumberGenerator.new()
## Host only: {a, b, lines: Array[{s, key}], i, t, topic}
var _convos: Array[Dictionary] = []
var _rest := {}           # npc instance id -> seconds left resting
var _recent: Array[String] = []
var _start_t := 1.0
var _quiet_t := 999.0     # seconds since the last hit
var _tts_voice := ""


func _ready() -> void:
	_rng.randomize()
	if director == null:
		director = get_parent() if get_parent() is Director else null
	Events.hit_landed.connect(_on_violence)
	Events.fight_started.connect(_on_violence.bind({}))
	Events.police_called.connect(_on_violence.bind({}))


func is_quiet() -> bool:
	var heat := float(director.heat) if director != null else 0.0
	return heat <= quiet_heat and _quiet_t >= resume_after


func conversations() -> int:
	return _convos.size()


func is_talking(npc: Node) -> bool:
	for c in _convos:
		if c["a"] == npc or c["b"] == npc:
			return true
	return false


# --- Host: who talks, and when ---------------------------------------------------------

func _process(delta: float) -> void:
	_quiet_t += delta
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for id in _rest.keys():
		_rest[id] -= delta
		if _rest[id] <= 0.0:
			_rest.erase(id)
	for c in _convos.duplicate():
		_tick_conversation(c, delta)
	if not is_quiet():
		return
	_start_t -= delta
	if _start_t <= 0.0:
		_start_t = _rng.randf_range(start_every.x, start_every.y)
		if _convos.size() < max_conversations:
			try_start()


## Start a conversation between two calm NPCs standing close together (host). Returns true
## if one started. Called on a timer; tests call it directly.
func try_start() -> bool:
	if not multiplayer.is_server() or not is_quiet():
		return false
	var talkers: Array[Npc] = []
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var npc := node as Npc
		if npc != null and npc.kind in talker_kinds and _available(npc):
			talkers.append(npc)
	talkers.shuffle()
	for a in talkers:
		var b := _listener_for(a)
		if b != null:
			_begin(a, b)
			return true
	return false


func _available(npc: Npc) -> bool:
	return is_instance_valid(npc) and npc.mood == Npc.Mood.CALM \
		and npc.state == Fighter.State.IDLE and not _rest.has(npc.get_instance_id()) \
		and not is_talking(npc)


func _listener_for(a: Npc) -> Npc:
	var best: Npc = null
	var best_d := talk_distance
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var b := node as Npc
		if b == null or b == a or not (b.kind in listener_kinds) or not _available(b):
			continue
		var d := a.global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	return best


func _begin(a: Npc, b: Npc) -> void:
	var c := {"a": a, "b": b, "lines": _write_script(b.kind in talker_kinds), "i": 0,
		"t": _rng.randf_range(0.2, 0.8)}
	_convos.append(c)
	a.chatting_with = b
	b.chatting_with = a
	conversation_started.emit(a, b)


func _tick_conversation(c: Dictionary, delta: float) -> void:
	var a := c["a"] as Npc
	var b := c["b"] as Npc
	if not _still_chatting(a, b):
		_end(c, true)
		return
	c["t"] -= delta
	if c["t"] > 0.0:
		return
	var lines: Array = c["lines"]
	if int(c["i"]) >= lines.size():
		_end(c, false)
		return
	var line: Dictionary = lines[c["i"]]
	c["i"] = int(c["i"]) + 1
	var speaker := a if int(line["s"]) == 0 else b
	var other := b if speaker == a else a
	var seconds := line_seconds(ChatterLines.text(line["key"]))
	_say.rpc(String(speaker.name), String(other.name), line["key"], seconds)
	c["t"] = seconds + _rng.randf_range(0.3, 0.9)


func _still_chatting(a: Npc, b: Npc) -> bool:
	for n in [a, b]:
		if not is_instance_valid(n) or n.mood != Npc.Mood.CALM or n.is_down():
			return false
	return a.global_position.distance_to(b.global_position) <= talk_distance * 1.6


func _end(c: Dictionary, interrupted: bool) -> void:
	_convos.erase(c)
	for n in [c["a"], c["b"]]:
		if is_instance_valid(n):
			if n.chatting_with == c["a"] or n.chatting_with == c["b"]:
				n.chatting_with = null
			_rest[n.get_instance_id()] = _rng.randf_range(talker_rest.x, talker_rest.y)
	if interrupted:
		_hush.rpc(_names(c))
		var yelper: Npc = c["a"] if _rng.randf() < 0.6 else c["b"]
		if is_instance_valid(yelper) and not yelper.is_ko() and _rng.randf() < interrupt_chance:
			var k := ChatterLines.pick(&"_", "interrupt", _rng)
			_say.rpc(String(yelper.name), "", k, 1.6)
	conversation_ended.emit(c["a"], c["b"], interrupted)


func _on_violence(_info: Dictionary) -> void:
	_quiet_t = 0.0
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for c in _convos.duplicate():
		_end(c, true)


func _names(c: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for n in [c["a"], c["b"]]:
		if is_instance_valid(n):
			out.append(String(n.name))
	return out


## How long a line stays up, from its length.
static func line_seconds(text: String) -> float:
	return clampf(0.9 + text.length() * 0.05, 1.6, 6.5)


# --- Writing a conversation ------------------------------------------------------------

## The lines for one conversation: [{s: 0 or 1 (speaker a or b), key}]. `posh_b` is false
## when b is a local, who only ever grunts back.
func _write_script(posh_b: bool) -> Array:
	var out := []
	var topic: StringName = _pick_topic(&"")
	out.append({"s": 0, "key": _fresh(topic, "open")})
	out.append({"s": 1, "key": _answer(topic, posh_b)})
	var n := _rng.randi_range(rounds.x, rounds.y)
	for r in n:
		if r > 0 and _rng.randf() < change_topic_chance:
			topic = _pick_topic(topic)
			out.append({"s": 0, "key": ChatterLines.pick(&"_", "segue", _rng)})
			out.append({"s": 0, "key": _fresh(topic, "open")})
			out.append({"s": 1, "key": _answer(topic, posh_b)})
			continue
		# Posh listeners one-up the talker; locals just get talked at.
		var s := _rng.randi_range(0, 1) if posh_b else 0
		out.append({"s": s, "key": _fresh(topic, "more")})
		out.append({"s": 1 - s, "key": _answer(topic, posh_b) if s == 0 \
			else ChatterLines.pick(&"_", "reply", _rng)})
	if _rng.randf() < close_chance:
		out.append({"s": _rng.randi_range(0, 1) if posh_b else 0,
			"key": ChatterLines.pick(&"_", "close", _rng)})
	return out


func _answer(topic: StringName, posh: bool) -> String:
	if not posh:
		return ChatterLines.pick(&"_", "local", _rng)
	if _rng.randf() < 0.7:
		return _fresh(topic, "reply")
	return ChatterLines.pick(&"_", "reply", _rng)


func _pick_topic(not_this: StringName) -> StringName:
	var all := ChatterLines.topics()
	all.erase(not_this)
	return all[_rng.randi_range(0, all.size() - 1)]


## A line from the topic's part that hasn't been said recently.
func _fresh(topic: StringName, part: String) -> String:
	var k := ""
	for i in 6:
		k = ChatterLines.pick(topic, part, _rng)
		if not k in _recent:
			break
	_recent.append(k)
	if _recent.size() > 80:
		_recent.pop_front()
	return k


# --- Every peer: bubbles and voices ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _say(speaker_name: String, listener_name: String, line_key: String, seconds: float) -> void:
	var speaker := _find(speaker_name)
	var text := ChatterLines.text(line_key)
	if speaker == null or text == "":
		return
	var listener := _find(listener_name)
	if listener != null and speaker is Npc and not multiplayer.is_server():
		speaker.chatting_with = listener
	if show_bubbles and bool(Settings.get_value("gameplay", "subtitles")):
		_bubble(speaker).show_line(text, seconds)
	_voice(speaker, line_key, text)
	line_said.emit(speaker, line_key, text)


@rpc("authority", "call_local", "reliable")
func _hush(names: PackedStringArray) -> void:
	for n in names:
		var who := _find(n)
		if who == null:
			continue
		if who is Npc and not multiplayer.is_server():
			who.chatting_with = null
		var bubble := who.get_node_or_null("ChatterBubble") as ChatterBubble
		if bubble != null:
			bubble.hide_line()
		var player := who.get_node_or_null("ChatterVoice") as AudioStreamPlayer3D
		if player != null:
			player.stop()
	if voice_mode == VoiceMode.TTS and _tts_ok():
		DisplayServer.tts_stop()


func _find(node_name: String) -> Node3D:
	if node_name == "":
		return null
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		if node.name == node_name:
			return node as Node3D
	return null


func _bubble(who: Node3D) -> ChatterBubble:
	var b := who.get_node_or_null("ChatterBubble") as ChatterBubble
	if b == null:
		b = ChatterBubble.new()
		b.name = "ChatterBubble"
		who.add_child(b)
	return b


func _voice(who: Node3D, line_key: String, text: String) -> void:
	if voice_mode == VoiceMode.SILENT or DisplayServer.get_name() == "headless":
		return
	var stream: AudioStream = null
	# Recorded voices (see VoiceCast), then a single-file recording, then TTS or the murmur.
	var path := VoiceCast.chatter_path(line_key, who)
	if path == "":
		path = ChatterLines.voice_path(line_key)
	if ResourceLoader.exists(path):
		stream = load(path)
	elif voice_mode == VoiceMode.TTS and _tts_ok():
		DisplayServer.tts_speak(text, _tts_voice, 60, 0.95 if _voice_of(who) == "m" else 1.15)
		return
	else:
		stream = ChatterVoice.stream_for(line_key, text, _voice_of(who))
	var player := who.get_node_or_null("ChatterVoice") as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "ChatterVoice"
		player.bus = &"Voice"
		player.position.y = 1.6
		who.add_child(player)
	player.volume_db = voice_db
	player.max_distance = voice_range
	player.unit_size = 3.0
	# Wider spread than a single voice needs, so two second-homers sharing one recorded
	# voice still sound like two people.
	player.pitch_scale = 1.0 + (absi(hash(String(who.name))) % 9 - 4) * 0.025
	player.stream = stream
	player.play()


## "m" or "f". Uses the fighter's `voice` property or meta if it has one (the FX workstream's
## convention), else picks one from the name so it stays the same all night.
func _voice_of(who: Node) -> String:
	return VoiceCast.sex(who)


func _tts_ok() -> bool:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return false
	if _tts_voice == "":
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if voices.is_empty():
			return false
		_tts_voice = voices[0]
		for v in DisplayServer.tts_get_voices():
			if String(v.get("language", "")).begins_with("en_GB"):
				_tts_voice = v["id"]
				break
	return true
