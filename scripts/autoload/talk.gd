extends Node
## Talking to punters. Hold push-to-talk (V, or Back on a pad) and speak, or press Enter and
## type. The punter you're facing hears it:
##   Plan 1, always on: the words change how they behave. "Calm down mate, it was an
##     accident" can talk them out of a fight; "OI! I'm talking to you!" winds them up.
##     (TalkIntent reads the words, Npc.hear_words acts on them.) No key or internet needed.
##   Plan 2, with an Anthropic API key: they answer back in their own words, and Claude
##     decides whether you've talked them round (PunterMind).
## Replies are spoken in the punter's own voice (PunterVoice) and shown in a bubble.
##
## Co-op: your words are turned into text on your own PC, then sent to the host. The host
## runs the punters, so it picks who heard, asks Claude (with the host's key), changes their
## mood, and sends the reply to everyone. Each PC speaks the reply with its own voices.
## Bar staff answer but can't be wound up into a fight, and nobody can hit them.

signal player_said(player: Node, text: String)
## Host only: a punter answered, and what the words did to them.
signal punter_replied(npc: Node, text: String, outcome: String)
## Every peer: a punter's reply arrived (shown and spoken here).
signal punter_spoke(npc: Node, text: String)

## How far away a punter can be and still hear you (shouting carries further).
const HEAR_RANGE := 9.0
const SHOUT_RANGE := 13.0
## Lines of conversation each punter remembers (for Claude).
const MEMORY := 8
## Seconds between lines from one player, so held keys and spam don't flood the host.
const PLAYER_GAP := 0.8
const BUBBLE_SECONDS := 4.5

var listener: Listener
var voice: PunterVoice
var mind: PunterMind
var ui: TalkUi

var _rng := RandomNumberGenerator.new()
var _history := {}      # npc name -> Array of [who, line]
var _last_line := {}    # peer id -> Time (s)
var _pending := {}      # PunterMind request id -> {npc, player, heard, said}
var _ptt_down := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	listener = Listener.new()
	listener.name = "Listener"
	add_child(listener)
	listener.heard.connect(_on_heard)
	listener.not_heard.connect(func(why: String): _status(why, 3.0, Color(1.0, 0.75, 0.6)))
	voice = PunterVoice.new()
	voice.name = "PunterVoice"
	add_child(voice)
	mind = PunterMind.new()
	mind.name = "PunterMind"
	add_child(mind)
	mind.answered.connect(_on_answered)
	if DisplayServer.get_name() != "headless":
		ui = TalkUi.new()
		ui.name = "TalkUi"
		add_child(ui)
		ui.typed.connect(func(t: String): say(t, false))
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()


func _apply_settings() -> void:
	var v := int(Settings.get_value("talk", "punter_voices"))
	voice.engine = ["piper", "windows", "off"][clampi(v, 0, 2)]
	voice.eleven_key = String(Settings.get_value("talk", "elevenlabs_key")) if v == 0 else ""
	mind.api_key = String(Settings.get_value("talk", "api_key"))
	mind.model = PunterMind.MODELS[clampi(int(Settings.get_value("talk", "ai_model")), 0, PunterMind.MODELS.size() - 1)]


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "talk":
		_apply_settings()


## Is there a farmer of ours in a pub to talk with?
func local_player() -> Fighter:
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer():
		return null
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f != null and f.team == Fighter.Team.PLAYERS and f.is_multiplayer_authority() \
				and String(f.name) == "P%d" % multiplayer.get_unique_id():
			return f
	return null


# --- Local input -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if ui == null or get_tree().paused or DartsBoard.local_input_locked():
		return
	if ui.is_box_open():
		return
	if event.is_action_pressed("say_line") and not event.is_echo() and local_player() != null:
		get_viewport().set_input_as_handled()
		ui.open_box()


func _process(_delta: float) -> void:
	if ui == null:
		return
	var want := Input.is_action_pressed("push_to_talk") and not get_tree().paused \
		and not TalkUi.typing and bool(Settings.get_value("talk", "push_to_talk")) \
		and get_viewport().gui_get_focus_owner() == null and local_player() != null
	if want == _ptt_down:
		return
	_ptt_down = want
	if want:
		if listener.busy:
			_status("Still working out the last one...", 1.5)
			_ptt_down = false
			return
		listener.start()
		ui.listening(listener.recording)
		if not listener.recording:
			_status("No microphone found.", 3.0, Color(1.0, 0.75, 0.6))
	else:
		ui.listening(false)
		listener.stop()


func _on_heard(text: String, loud: bool) -> void:
	say(text, loud)


func _status(text: String, seconds: float, colour := Color(1.0, 0.95, 0.85)) -> void:
	if ui != null:
		ui.show_status(text, seconds, colour)


## Say a line as our farmer. Goes to the host, who decides who heard it.
func say(text: String, loud := false) -> void:
	text = text.strip_edges()
	if text == "" or local_player() == null:
		return
	if bool(Settings.get_value("talk", "show_heard")):
		_status("You: \"%s\"" % text, 3.0)
	if multiplayer.is_server():
		_said(text, loud)
	else:
		_said.rpc_id(1, text, loud)


# --- Host ------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _said(text: String, loud: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_line.get(peer, -10.0)) < PLAYER_GAP:
		return
	_last_line[peer] = now
	var who := _fighter("P%d" % peer)
	if who == null:
		return
	text = text.substr(0, 200)
	_show_player_line.rpc(String(who.name), text)
	if hear(who, text, loud) == null:
		if peer == multiplayer.get_unique_id():
			_nobody_heard()
		else:
			_nobody_heard.rpc_id(peer)


## Host: `who` said `text`. Picks the punter they meant, changes their mood, and gets them
## to reply. Returns that punter (or null if nobody was in earshot). Tests call this directly.
func hear(who: Fighter, text: String, loud := false) -> Npc:
	var heard := TalkIntent.classify(text, loud)
	loud = bool(heard["loud"])
	var npc := pick_listener(who, text, loud)
	if loud and String(heard["intent"]) == "provoke":
		_turn_heads(who)
	if npc == null:
		return null
	_remember(npc, _farmer_name(who), text)
	if _ai_on() and not _pending_for(npc):
		var id := mind.ask(situation(npc, who, text, heard))
		if id >= 0:
			_pending[id] = {"npc": npc, "player": who, "heard": heard, "said": text}
			_thinking.rpc(String(npc.name))
			return npc
	var outcome := npc.hear_words(who, heard)
	_reply(npc, TalkLines.reply_for(_persona(npc), String(npc.kind), outcome, _rng), outcome)
	return npc


func _ai_on() -> bool:
	return bool(Settings.get_value("talk", "ai_replies")) and mind.can_send()


func _pending_for(npc: Npc) -> bool:
	for p in _pending.values():
		if p["npc"] == npc:
			return true
	return false


func _on_answered(id: int, res: Dictionary) -> void:
	var p: Dictionary = _pending.get(id, {})
	_pending.erase(id)
	if p.is_empty():
		return
	var npc := p["npc"] as Npc
	var who := p["player"] as Fighter
	if not is_instance_valid(npc) or not is_instance_valid(who) or npc.is_ko():
		return
	if bool(res.get("ok", false)):
		var outcome := npc.apply_talk_effect(who, String(res["effect"]))
		_reply(npc, String(res["reply"]), outcome)
		return
	# Claude couldn't answer (no connection, bad key...): fall back to Plan 1.
	push_warning("Punter reply via Claude failed: %s" % res.get("error", ""))
	var outcome := npc.hear_words(who, p["heard"])
	_reply(npc, TalkLines.reply_for(_persona(npc), String(npc.kind), outcome, _rng), outcome)


func _reply(npc: Npc, text: String, outcome: String) -> void:
	_remember(npc, _persona(npc)["name"], text)
	_npc_line.rpc(String(npc.name), text)
	punter_replied.emit(npc, text, outcome)


## The punter `who` is talking to: the one they're facing and nearest, preferring anyone
## they're fighting, and anyone they name ("Oi, barman!", "Rupert, calm down").
func pick_listener(who: Fighter, text := "", loud := false) -> Npc:
	var words := " %s " % TalkIntent.normalise(text)
	var reach := SHOUT_RANGE if loud else HEAR_RANGE
	var facing := who.get_facing() if who.has_method("get_facing") else -who.global_basis.z
	facing.y = 0.0
	var best: Npc = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		var npc := node as Npc
		if npc == null or npc.is_down() or npc.is_ko():
			continue
		var to := npc.global_position - who.global_position
		var d := to.length()
		if d > reach or absf(to.y) > 2.5:
			continue  # out of earshot, or on another floor
		to.y = 0.0
		var dot := facing.normalized().dot(to.normalized()) if to.length() > 0.01 else 1.0
		var score := d + (1.0 - dot) * 2.5
		if npc.mood == Npc.Mood.ENGAGED and npc.foe == who:
			score -= 3.0
		if npc.has_method("hits_from") and npc.hits_from(who) > 0:
			score -= 0.5
		if _named(npc, words):
			score -= 6.0
		if score < best_score:
			best_score = score
			best = npc
	return best


func _named(npc: Npc, padded_words: String) -> bool:
	var first := String(_persona(npc)["name"]).split(" ")[0].to_lower()
	if padded_words.contains(" %s " % first):
		return true
	var role_words := {
		"staff": ["barman", "barmaid", "landlord", "landlady", "bartender"],
		"police": ["officer", "copper", "constable", "pc", "sergeant", "plod"],
		"rugby_lad": ["rugby"], "second_homer": ["posh"],
	}
	for w in role_words.get(String(npc.kind), []):
		if padded_words.contains(" %s " % w):
			return true
	return false


## Shouting at someone makes everyone nearby look round (it doesn't start a fight by itself).
func _turn_heads(who: Fighter) -> void:
	for node in get_tree().get_nodes_in_group(&"npcs"):
		var npc := node as Npc
		if npc != null and npc.mood == Npc.Mood.CALM and not npc.is_down() \
				and npc.global_position.distance_to(who.global_position) < SHOUT_RANGE:
			npc.alert()


## Everything Claude needs to play this punter right now.
func situation(npc: Npc, who: Fighter, text: String, heard: Dictionary) -> Dictionary:
	var p := _persona(npc)
	var director := get_tree().get_first_node_in_group(&"director")
	var heat := float(director.heat) if director != null else 0.0
	var pub_state := "The pub is quiet." if heat < 0.1 else ("A fight is going on." if heat < 0.6 \
		else "It's a full-on brawl.")
	var mood_words := {Npc.Mood.CALM: "calm, having a drink", Npc.Mood.ALERT: "on edge, watching the trouble",
		Npc.Mood.ENGAGED: "fighting"}
	var bravery := float(npc.type_value("bravery")) if npc.type_value("bravery") != null else 0.5
	var aggression := float(npc.type_value("aggression")) if npc.type_value("aggression") != null else 1.0
	var temperament := "%s, %s" % ["brave" if bravery > 0.7 else ("timid" if bravery < 0.35 else "no pushover"),
		"hot-headed" if aggression > 1.1 else ("slow to anger" if aggression < 0.8 else "short-tempered when pushed")]
	var hp := npc.hp / maxf(npc.max_hp, 1.0) if "hp" in npc else 1.0
	var s := {
		"name": p["name"], "background": p["background"], "temperament": temperament,
		"interests": TalkLines.interest_words(p),
		"mood": mood_words.get(npc.mood, "calm"),
		"fighting_speaker": npc.mood == Npc.Mood.ENGAGED and npc.foe == who,
		"hits_from_speaker": npc.hits_from(who), "seconds_since_hit": npc.since_hit_by(who),
		"pub": String(GameData.current_pub().get("name", "the pub")), "pub_state": pub_state,
		"farmer": _farmer_name(who), "shouted": bool(heard.get("loud", false)), "said": text,
		"history": (_history.get(String(npc.name), []) as Array).slice(0, -1),
	}
	if hp < 0.4:
		s["hurt"] = "badly hurt"
	elif hp < 0.75:
		s["hurt"] = "a bit battered"
	if String(heard.get("intent", "none")) != "none":
		s["hint"] = {"calm": "like an attempt to calm things down", "provoke": "provocative",
			"chat": "friendly"}.get(String(heard["intent"]), "")
		if bool(heard.get("apology", false)):
			s["hint"] = "like an apology"
	return s


func _persona(npc: Node) -> Dictionary:
	return TalkLines.persona(String(npc.name), String(npc.get("kind")), VoiceCast.sex(npc))


## What the punter calls whoever is talking to them: just a bloke at the bar, by first name
## if known (no "the farmer", or Claude keeps going on about farming).
func _farmer_name(who: Node) -> String:
	if "farmer" in who and who.get("farmer") is Dictionary:
		var n := String((who.get("farmer") as Dictionary).get("name", ""))
		if n != "":
			return n.split(" ")[0].replace("\"", "")
	return "Someone"


func _remember(npc: Npc, who: String, line: String) -> void:
	var key := String(npc.name)
	var h: Array = _history.get(key, [])
	h.append([who, line])
	while h.size() > MEMORY:
		h.pop_front()
	_history[key] = h


func history_of(npc: Node) -> Array:
	return _history.get(String(npc.name), [])


## Forget everyone's conversations (a new pub, new punters).
func reset() -> void:
	_history.clear()
	_pending.clear()


# --- Every peer: bubbles and voices ----------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show_player_line(player_name: String, text: String) -> void:
	var who := _fighter(player_name)
	if who == null:
		return
	if bool(Settings.get_value("talk", "show_heard")) and bool(Settings.get_value("gameplay", "subtitles")):
		_bubble(who).show_line(text, BUBBLE_SECONDS)
	player_said.emit(who, text)


## Tell the speaker nobody was close enough, so silence doesn't look like "it didn't understand".
@rpc("authority", "call_remote", "reliable")
func _nobody_heard() -> void:
	_status("Nobody's close enough to hear you. Get up to a punter and face them.", 3.5,
		Color(1.0, 0.85, 0.6))


@rpc("authority", "call_local", "reliable")
func _thinking(npc_name: String) -> void:
	var npc := _fighter(npc_name)
	if npc != null and bool(Settings.get_value("gameplay", "subtitles")):
		_bubble(npc).show_line("...", 3.0)


@rpc("authority", "call_local", "reliable")
func _npc_line(npc_name: String, text: String) -> void:
	var npc := _fighter(npc_name)
	if npc == null:
		return
	if bool(Settings.get_value("gameplay", "subtitles")):
		_bubble(npc).show_line(text, Chatter.line_seconds(text) + 1.0)
	if ui != null and ui._status.text == "Thinking...":
		ui.show_status("", 0.1)
	punter_spoke.emit(npc, text)
	var role := VoiceCast.role_of(npc)
	voice.speak(npc, text, VoiceCast.voice_id(npc), VoiceCast.sex(npc), role)


func _fighter(node_name: String) -> Fighter:
	for node in get_tree().get_nodes_in_group(Fighter.GROUP):
		if String(node.name) == node_name:
			return node as Fighter
	return null


func _bubble(who: Node3D) -> ChatterBubble:
	var b := who.get_node_or_null("ChatterBubble") as ChatterBubble
	if b == null:
		b = ChatterBubble.new()
		b.name = "ChatterBubble"
		who.add_child(b)
	return b
