extends Node
## Test cases for talking to punters. Loaded by talk_test.gd once the autoloads exist.

signal finished(failures: int)

var _failures := 0
var _arena: Node3D
var _talk: Node


func run() -> void:
	GameData.difficulty_index = 1
	var fx := get_node_or_null(^"/root/Fx")
	if fx != null and "hit_stop_time_scale" in fx:
		fx.hit_stop_time_scale = 1.0
	_talk = get_node(^"/root/Talk")
	Settings.values["talk"]["api_key"] = ""  # never call out from tests
	_talk._apply_settings()
	var tests := [
		"test_reading_the_words", "test_personas_and_stock_replies", "test_claude_request",
		"test_claude_response", "test_mic_helpers", "test_calm_down_works",
		"test_settled_punter_stays_out", "test_oi_winds_them_up", "test_who_hears_it",
		"test_staff_and_police", "test_hear_replies_without_key", "test_claude_effects",
	]
	for t in tests:
		_arena = Node3D.new()
		add_child(_arena)
		_floor()
		_talk.reset()
		await call(t)
		_arena.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	if _failures == 0:
		print("Talk OK: %d tests" % tests.size())
	finished.emit(_failures)


# --- Helpers ---------------------------------------------------------------------------

func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(60, 0.2, 60)
	body.add_child(shape)
	body.position.y = -0.1
	_arena.add_child(body)


func _player(pos: Vector3) -> Fighter:
	var f := Fighter.new()
	f.team = Fighter.Team.PLAYERS
	f.max_hp = 1000.0
	f.collision_layer = 2
	f.collision_mask = 7
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.shape.radius = 0.35
	shape.position.y = 0.875
	f.add_child(shape)
	f.position = pos
	_arena.add_child(f)
	return f


func _director() -> Director:
	var d := Director.new()
	d.actors = _arena
	d.auto_start = false
	d.rng_seed = 4321
	d.initial_punters = 0
	d.reserve_punters = 0
	d.chatter = false
	d.door = Vector3(8, 0, 0)
	d.punter_spots = [Vector3(0, 0, -4)]
	_arena.add_child(d)
	d.start()
	return d


func _wait(seconds: float) -> void:
	for i in int(ceil(seconds * 60.0)):
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("FAIL: " + what)
		print("FAIL: " + what)


# --- Tests -----------------------------------------------------------------------------

func test_reading_the_words() -> void:
	var calm := TalkIntent.classify("Calm down mate, it was an accident")
	_check(calm["intent"] == "calm" and calm["apology"] and calm["strength"] > 0.6,
		"'calm down mate, it was an accident' reads as a strong apology (%s)" % calm)
	var oi := TalkIntent.classify("OI! I'm talking to you!", false)
	_check(oi["intent"] == "provoke" and oi["loud"] and oi["strength"] > 0.7,
		"'OI! I'm talking to you!' reads as shouted provocation (%s)" % oi)
	var spoken := TalkIntent.classify("oi I'm talking to you", true)
	_check(spoken["intent"] == "provoke", "shouting into the mic counts as provoking")
	_check(TalkIntent.classify("Sorry, let me buy you a pint")["intent"] == "calm", "buying a pint calms")
	_check(TalkIntent.classify("I'm not sorry, you deserved it")["intent"] == "provoke",
		"'not sorry' isn't an apology")
	_check(TalkIntent.classify("Evening! What are you drinking?")["intent"] == "chat", "small talk is chat")
	_check(TalkIntent.classify("the cat sat on the mat")["intent"] == "none", "nonsense is nothing")
	_check(TalkIntent.classify("calm down", true)["intent"] == "calm",
		"shouting 'calm down' is still trying to calm things")
	_check(TalkIntent.normalise("Didn't MEAN it!!") == "didnt mean it", "normalising drops apostrophes")


func test_personas_and_stock_replies() -> void:
	var a := TalkLines.persona("N3", "second_homer", "m")
	_check(a == TalkLines.persona("N3", "second_homer", "m"), "a punter's persona is stable")
	_check(a["name"] != "" and a["background"] != "" and a["group"] == "posh", "persona has a name and story")
	var rng := RandomNumberGenerator.new()
	for kind in ["second_homer", "local", "rugby_lad", "police", "staff", "rambler"]:
		for outcome in ["calmed", "unconvinced", "riled", "fuming", "cowed", "chat", "shrug", "nonsense"]:
			_check(TalkLines.reply(kind, outcome, rng) != "", "%s has a %s reply" % [kind, outcome])


func test_claude_request() -> void:
	var body := PunterMind.build_body({"name": "Rupert", "background": "a barrister", "said": "Calm down",
		"history": [["A farmer", "Evening"], ["Rupert", "Do you know who I am?"]], "shouted": true,
		"hits_from_speaker": 2, "seconds_since_hit": 1.0})
	_check(body["model"] == "claude-haiku-5-5", "Haiku 5.5 by default")
	_check(body["thinking"]["type"] == "disabled" and body["output_config"]["effort"] == "low",
		"quick replies: no thinking, low effort")
	_check(body["output_config"]["format"]["type"] == "json_schema", "asks for JSON")
	var msg: String = body["messages"][0]["content"]
	_check(msg.contains("Rupert") and msg.contains("shouts to you: \"Calm down\""), "says who and what (%s)" % msg)
	_check(msg.contains("hit you 2 times") and msg.contains("just now"), "mentions the punches")
	_check(msg.contains("Do you know who I am?"), "includes the conversation so far")
	var h := PunterMind.headers("  sk-test  ")
	_check("x-api-key: sk-test" in h and "anthropic-version: 2026-10-21" in h, "API headers")
	var m := PunterMind.new()
	_check(not m.can_send(), "no key, no request")
	m.free()


func test_claude_response() -> void:
	var ok := JSON.stringify({"stop_reason": "end_turn", "content": [
		{"type": "thinking", "thinking": ""},
		{"type": "text", "text": JSON.stringify({"reply": "Accident? Pull the other one.", "effect": "stay_wary"})}]})
	var r := PunterMind.parse_response(200, ok)
	_check(r["ok"] and r["reply"] == "Accident? Pull the other one." and r["effect"] == "stay_wary",
		"reads the reply after a thinking block (%s)" % r)
	var odd := PunterMind.parse_response(200, JSON.stringify({"content": [{"type": "text",
		"text": JSON.stringify({"reply": "Eh?", "effect": "dance"})}]}))
	_check(odd["ok"] and odd["effect"] == "no_change", "unknown effects become no_change")
	_check(not PunterMind.parse_response(200, JSON.stringify({"stop_reason": "refusal", "content": []}))["ok"],
		"a refusal falls back")
	var bad := PunterMind.parse_response(401, JSON.stringify({"error": {"message": "invalid x-api-key"}}))
	_check(not bad["ok"] and String(bad["error"]).contains("API key"), "a bad key says so")
	_check(not PunterMind.parse_response(500, "")["ok"], "server errors fall back")


func test_mic_helpers() -> void:
	var frames := PackedVector2Array()
	for i in 48000:
		var s := sin(i * 0.05) * 0.8
		frames.append(Vector2(s, s))
	var mono := Listener.to_mono_16k(frames, 48000.0)
	_check(absi(mono.size() - 16000) <= 1, "one second at 48 kHz becomes 16000 samples (%d)" % mono.size())
	_check(Listener.is_loud(mono), "a loud signal counts as shouting")
	var quiet := PackedFloat32Array()
	quiet.resize(16000)
	quiet.fill(0.02)
	_check(not Listener.is_loud(quiet), "a mutter isn't a shout")
	var wav := Listener.to_wav(mono)
	_check(wav.mix_rate == 16000 and wav.data.size() == mono.size() * 2, "16-bit mono WAV for whisper")
	_check(Listener.clean_transcript(" [BLANK_AUDIO]\n Oi! Calm down. (laughs)\n") == "Oi! Calm down.",
		"transcript cleaned of whisper's tags")
	_check(Listener.clean_transcript("[BLANK_AUDIO]") == "", "silence is nothing")


func test_calm_down_works() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"local", Vector3(0, 0, -2))
	await _wait(0.2)
	npc.engage(p, true)
	d.heat = 0.5
	var chance := npc.placate_chance(p, 0.9, true)
	_check(chance > 0.5, "an apology to a fresh punter usually works (%.2f)" % chance)
	var calmed := false
	for i in 8:
		var outcome := npc.hear_words(p, TalkIntent.classify("Calm down mate, it was an accident"))
		if outcome == "calmed":
			calmed = true
			break
		npc.engage(p, true)
		npc._pleas = 0.0  # as if they'd had a moment between tries
	_check(calmed, "'calm down mate, it was an accident' talks a local down")
	_check(npc.mood != Npc.Mood.ENGAGED and npc.is_settled(), "calmed punter stops fighting")
	_check(d.heat < 0.5, "talking someone down cools the room (%.2f)" % d.heat)
	# Each plea in a row works less, and hitting them makes them less forgiving.
	var fresh := d.spawn(&"local", Vector3(2, 0, -2))
	await _wait(0.1)
	var before := fresh.placate_chance(p, 0.9, false)
	for i in 3:
		fresh._on_hit_taken({"attacker": p, "damage": 5.0})
	_check(fresh.hits_from(p) == 3, "punter counts who hit them")
	_check(fresh.placate_chance(p, 0.9, false) < before * 0.7, "punches make apologies weaker")


func test_settled_punter_stays_out() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"rugby_lad", Vector3(0, 0, -2))
	await _wait(0.2)
	npc.engage(p, true)
	npc.apply_talk_effect(p, "calm_down")
	_check(npc.is_settled() and npc.mood != Npc.Mood.ENGAGED, "Claude's calm_down settles them")
	npc.engage(p)  # e.g. a mate nearby got hit
	_check(npc.mood != Npc.Mood.ENGAGED, "a settled punter doesn't volunteer back in")
	npc._on_hit_taken({"attacker": p, "damage": 5.0})
	_check(npc.mood == Npc.Mood.ENGAGED and npc.foe == p and not npc.is_settled(),
		"hitting them again sets them off")


func test_oi_winds_them_up() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var lad := d.spawn(&"rugby_lad", Vector3(0, 0, -2))
	await _wait(0.2)
	_check(lad.mood == Npc.Mood.CALM, "starts calm")
	var engaged := false
	for i in 5:
		lad.hear_words(p, TalkIntent.classify("OI! I'm talking to you!", true))
		if lad.mood == Npc.Mood.ENGAGED:
			engaged = true
			break
	_check(engaged and lad.foe == p, "'OI!' gets a rugby lad squaring up to you")
	_check(lad.mood != Npc.Mood.CALM, "provoked punter isn't calm any more")
	# Already fighting: provoking them brings the next punch sooner.
	lad._attack_cd = 3.0
	_check(lad.hear_words(p, TalkIntent.classify("come on then you muppet")) == "fuming", "fighting and goaded")
	_check(lad._attack_cd <= 0.3, "goaded punter comes in sooner")


func test_who_hears_it() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))  # faces -Z
	var front := d.spawn(&"local", Vector3(0, 0, -2.5))
	var behind := d.spawn(&"local", Vector3(2.0, 0, 0))
	var far := d.spawn(&"local", Vector3(0, 0, -20))
	var barman := d.spawn(&"staff", Vector3(4, 0, 2))
	await _wait(0.2)
	_check(_talk.pick_listener(p, "evening") == front, "the punter you're facing hears you")
	_check(_talk.pick_listener(p, "oi barman, a pint") == barman, "naming the barman picks him")
	behind.engage(p, true)
	_check(_talk.pick_listener(p, "calm down") == behind, "whoever you're fighting is listening, even off to the side")
	front.queue_free()
	behind.queue_free()
	barman.queue_free()
	await get_tree().process_frame
	_check(_talk.pick_listener(p, "hello") == null, "nobody in earshot, nobody answers")
	_check(far.mood == Npc.Mood.CALM, "far punter unaffected")


func test_staff_and_police() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var barman := d.spawn(&"staff", Vector3(0, 0, -2))
	var cop := d.spawn(&"police", Vector3(2, 0, -2))
	await _wait(0.2)
	for i in 4:
		barman.hear_words(p, TalkIntent.classify("OI! Come on then!", true))
	_check(barman.team == Fighter.Team.STAFF and barman.mood != Npc.Mood.ENGAGED,
		"bar staff can be told off but never fight")
	barman.apply_talk_effect(p, "attack")
	_check(barman.mood != Npc.Mood.ENGAGED, "not even if Claude says so")
	_check(cop.placate_chance(p, 1.0, true) == 0.0, "the Old Bill aren't talked out of it")
	cop.engage(p, true)
	cop.apply_talk_effect(p, "calm_down")
	_check(cop.mood == Npc.Mood.ENGAGED, "police stay on the job")


func test_hear_replies_without_key() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"second_homer", Vector3(0, 0, -2))
	await _wait(0.2)
	var replies := []
	var cb := func(n, text, outcome): replies.append([n, text, outcome])
	_talk.punter_replied.connect(cb)
	var heard: Npc = _talk.hear(p, "Evening! Lovely weather.")
	_check(heard == npc, "the punter in front hears it")
	_check(replies.size() == 1 and replies[0][0] == npc and String(replies[0][1]) != "",
		"they reply with a stock line when there's no key (%s)" % [replies])
	var bubble := npc.get_node_or_null("ChatterBubble") as ChatterBubble
	_check(bubble != null and bubble.is_showing(), "the reply shows in a bubble")
	_check(_talk.history_of(npc).size() == 2, "the exchange is remembered")
	var situation: Dictionary = _talk.situation(npc, p, "Calm down", TalkIntent.classify("Calm down"))
	_check(situation["name"] != "" and situation["pub"] != "" and situation["history"].size() >= 1,
		"situation for Claude has persona, pub and history")
	_talk.punter_replied.disconnect(cb)


func test_claude_effects() -> void:
	var d := _director()
	var p := _player(Vector3(0, 0, 0))
	var npc := d.spawn(&"local", Vector3(0, 0, -2))
	await _wait(0.2)
	_check(npc.apply_talk_effect(p, "no_change") == "chat" and npc.mood == Npc.Mood.CALM, "no_change leaves them be")
	_check(npc.apply_talk_effect(p, "stay_wary") == "unconvinced" and npc.mood == Npc.Mood.ALERT,
		"stay_wary puts them on edge")
	npc.apply_talk_effect(p, "attack")
	_check(npc.mood == Npc.Mood.ENGAGED and npc.foe == p and npc._attack_cd <= 0.0, "attack goes for you")
	npc.apply_talk_effect(p, "stay_wary")
	_check(npc.mood == Npc.Mood.ALERT, "stay_wary steps back out of the fight")
	# A Claude answer arriving for a punter goes through the same path.
	_talk._pending[99] = {"npc": npc, "player": p, "heard": TalkIntent.classify("sorry"), "said": "sorry"}
	var got := []
	var cb := func(_n, text, outcome): got.append([text, outcome])
	_talk.punter_replied.connect(cb)
	_talk._on_answered(99, {"ok": true, "reply": "Go on then, a pint of mild.", "effect": "calm_down"})
	_check(got.size() == 1 and got[0][0] == "Go on then, a pint of mild." and got[0][1] == "calmed",
		"Claude's reply is said and its effect applied (%s)" % [got])
	_talk._pending[100] = {"npc": npc, "player": p, "heard": TalkIntent.classify("hello"), "said": "hello"}
	_talk._on_answered(100, {"ok": false, "error": "no connection"})
	_check(got.size() == 2 and String(got[1][0]) != "", "if Claude fails they still answer")
	_talk.punter_replied.disconnect(cb)
