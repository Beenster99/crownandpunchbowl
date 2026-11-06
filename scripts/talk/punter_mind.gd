class_name PunterMind
extends Node
## Lets a punter answer back in their own words: one short call to Claude per thing a player
## says, made on the host with the host's own API key (Settings > Talk). Claude gets the
## punter's personality and the state of the pub, and returns a line to say plus what the
## words did to them (an `effect` the NPC acts on).
##
## Nothing here touches the scene: the Talk autoload feeds it a `situation` and acts on the
## answer. One request per punter at a time, a few at once in total, and a cap per night so
## a stuck key can't run up a bill.

signal answered(request_id: int, result: Dictionary)

const URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2026-10-21"
const MODELS := ["claude-haiku-5-5", "claude-sonnet-5-5"]
const EFFECTS := ["no_change", "calm_down", "stay_wary", "square_up", "attack", "cower"]
const MAX_IN_FLIGHT := 3
const TIMEOUT := 12.0
## Requests allowed per session (a night of play is maybe 100).
const SESSION_CAP := 400

const SYSTEM := """You voice the non-player characters in Crown and Punchbowl, a comic co-op \
brawler set in rough village pubs in rural England. The players are local farmers. The pubs \
are full of smug second-home owners from London, locals, rugby lads on tour, the occasional \
copper, and bar staff. A player has just spoken out loud to the character you are playing, \
using their microphone. Answer as that character, out loud, in one or two short sentences of \
spoken British English (at most 25 words). Be funny and in character: satire aimed at the \
characters' own smugness and pettiness, not at real groups of people. Mild swearing (bloody, \
sod, git, pillock) is fine; no slurs. Never mention being an AI or a game. If the player says \
something hateful, react with disgust in character.

Also decide what the words did to your character, as `effect`:
- calm_down: you are placated and stop fighting this farmer (a decent apology, a fair point, \
a pint offered, good humour). Harder if they have hit you a lot, or you are hot-headed.
- stay_wary: not convinced; you keep your distance and watch them.
- square_up: you are provoked and want a fight with them.
- attack: so provoked you go for them right now.
- cower: you want no part of it.
- no_change: small talk, or nothing that changes your mood.
Bar staff and police never calm_down; bar staff never fight."""

const SCHEMA := {
	"type": "object",
	"properties": {
		"reply": {"type": "string", "description": "What the character says out loud."},
		"effect": {"type": "string", "enum": EFFECTS},
	},
	"required": ["reply", "effect"],
	"additionalProperties": false,
}

var api_key := ""
var model := MODELS[0]
## Requests sent this session.
var sent := 0
## Last error, for the settings screen ("" when the last call worked).
var last_error := ""

var _in_flight := {}  # request_id -> HTTPRequest
var _next_id := 0


func can_send() -> bool:
	return api_key.strip_edges() != "" and _in_flight.size() < MAX_IN_FLIGHT and sent < SESSION_CAP


## Ask Claude what the punter says back. Returns a request id (or -1 if it can't be sent);
## `answered` fires with it and {ok, reply, effect, error}.
func ask(situation: Dictionary) -> int:
	if not can_send():
		return -1
	_next_id += 1
	var id := _next_id
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	_in_flight[id] = http
	http.request_completed.connect(_on_completed.bind(id, http))
	var err := http.request(URL, headers(api_key), HTTPClient.METHOD_POST,
		JSON.stringify(build_body(situation, model)))
	if err != OK:
		_finish(id, http, {"ok": false, "error": "couldn't send (%s)" % error_string(err)})
		return id
	sent += 1
	return id


static func headers(key: String) -> PackedStringArray:
	return PackedStringArray(["content-type: application/json", "x-api-key: " + key.strip_edges(),
		"anthropic-version: " + API_VERSION])


## The Messages API request body for one exchange.
static func build_body(situation: Dictionary, model_id := "claude-haiku-5-5") -> Dictionary:
	return {
		"model": model_id,
		"max_tokens": 300,
		# Quick, snappy banter: no extended thinking, low effort, JSON out.
		"thinking": {"type": "disabled"},
		"output_config": {"effort": "low", "format": {"type": "json_schema", "schema": SCHEMA}},
		"system": SYSTEM,
		"messages": [{"role": "user", "content": describe(situation)}],
	}


## The situation as plain text for the user turn. Keys (all optional): name, background, kind,
## temperament, mood, fighting_speaker, hits_from_speaker, seconds_since_hit, hurt, pub,
## pub_state, farmer, shouted, said, history (Array of [who, line]), hint.
static func describe(s: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("You are %s, %s." % [s.get("name", "a punter"), s.get("background", "a drinker in the pub")])
	if s.has("temperament"):
		lines.append("Temperament: %s." % s["temperament"])
	lines.append("Pub: %s. %s" % [s.get("pub", "the pub"), s.get("pub_state", "")])
	lines.append("Your mood right now: %s." % s.get("mood", "calm"))
	if bool(s.get("fighting_speaker", false)):
		lines.append("You are in a fight with the farmer who is speaking.")
	var hits := int(s.get("hits_from_speaker", 0))
	if hits > 0:
		var ago := float(s.get("seconds_since_hit", 999.0))
		lines.append("This farmer has hit you %d time%s tonight, the last one %s." % [hits,
			"" if hits == 1 else "s", "just now" if ago < 4.0 else "%d seconds ago" % roundi(ago)])
	if s.has("hurt"):
		lines.append("You are %s." % s["hurt"])
	var history: Array = s.get("history", [])
	if not history.is_empty():
		lines.append("Earlier tonight:")
		for h in history:
			lines.append("  %s: \"%s\"" % [h[0], h[1]])
	var farmer := String(s.get("farmer", "A farmer"))
	lines.append("%s %s to you: \"%s\"" % [farmer, "shouts" if bool(s.get("shouted", false)) else "says",
		String(s.get("said", "")).strip_edges()])
	if String(s.get("hint", "")) != "":
		lines.append("(It sounds %s.)" % s["hint"])
	return "\n".join(lines)


## Pull {ok, reply, effect, error} out of a Messages API response. Reads content blocks by
## type, since a response can begin with thinking blocks.
static func parse_response(code: int, body: String) -> Dictionary:
	var data: Variant = JSON.parse_string(body) if body != "" else null
	if code != 200:
		var msg := "HTTP %d" % code
		if data is Dictionary and data.get("error") is Dictionary:
			msg += ": " + String(data["error"].get("message", ""))
		if code == 401:
			msg = "API key rejected (check it in Settings > Talk)"
		return {"ok": false, "error": msg, "code": code}
	if not data is Dictionary:
		return {"ok": false, "error": "unreadable response"}
	if String(data.get("stop_reason", "")) == "refusal":
		return {"ok": false, "error": "declined"}
	var text := ""
	for block in data.get("content", []):
		if block is Dictionary and block.get("type") == "text":
			text += String(block.get("text", ""))
	var out: Variant = JSON.parse_string(text)
	if not out is Dictionary or String(out.get("reply", "")).strip_edges() == "":
		return {"ok": false, "error": "no reply in response"}
	var effect := String(out.get("effect", "no_change"))
	if not effect in EFFECTS:
		effect = "no_change"
	return {"ok": true, "reply": clean_reply(String(out["reply"])), "effect": effect}


## Keep it to something a bubble can show and a voice can say.
static func clean_reply(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ")
	if t.begins_with("\"") and t.ends_with("\"") and t.length() > 2:
		t = t.substr(1, t.length() - 2)
	if t.length() > 200:
		t = t.substr(0, 197) + "..."
	return t


func _on_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		id: int, http: HTTPRequest) -> void:
	var res := parse_response(code, body.get_string_from_utf8()) if code != 0 \
		else {"ok": false, "error": "no connection to Claude"}
	_finish(id, http, res)


func _finish(id: int, http: HTTPRequest, res: Dictionary) -> void:
	_in_flight.erase(id)
	http.queue_free()
	last_error = "" if bool(res.get("ok", false)) else String(res.get("error", ""))
	answered.emit(id, res)
