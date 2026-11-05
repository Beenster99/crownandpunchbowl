class_name VoiceCast
extends RefCounted
## Who sounds like whom. Every fighter gets one voice for the night: farmers have their own,
## NPCs pick one from their role's pool by node name, so it's the same on every machine.
## Used by the FX director (fight barks, oofs) and by Chatter (overheard pub talk).
##
## Overrides, in order: a "voice_id" meta or property naming a BarkLines voice; then
## the farmer id; then the NPC kind. Sex comes from the character look (CharacterLook.feminine),
## or from an explicit `voice` property/meta of "f" or "m".

const KIND_ROLE := {
	"second_homer": "posh", "local": "local", "rambler": "local", "rugby_lad": "rugby",
	"police": "police", "staff": "staff",
}
const BARK_ROOT := "res://assets/audio/voice/barks/"
const CHATTER_ROOT := "res://assets/audio/voice/chatter/"


## Stable voice id from BarkLines.VOICES, e.g. "tom", "posh_m2", "staff_f1".
static func voice_id(f: Node) -> String:
	var explicit := String(f.get_meta("voice_id", ""))
	if explicit == "" and "voice_id" in f:
		explicit = String(f.get("voice_id"))
	if BarkLines.VOICES.has(explicit):
		return explicit
	if "farmer" in f and f.get("farmer") is Dictionary:
		var fid := String((f.get("farmer") as Dictionary).get("id", ""))
		if BarkLines.VOICES.has(fid):
			return fid
	var role := role_of(f)
	var want := sex(f)
	var pool: Array = BarkLines.ROLES.get(role, BarkLines.ROLES["local"])
	var matching := pool.filter(func(v): return BarkLines.VOICES[v]["sex"] == want)
	if matching.is_empty():
		matching = pool
	return String(matching[absi(hash(String(f.name))) % matching.size()])


static func role_of(f: Node) -> String:
	if "kind" in f:
		var r: String = KIND_ROLE.get(String(f.get("kind")), "")
		if r != "":
			return r
	if f.is_in_group("players"):
		return "farmer"
	if f.is_in_group("police"):
		return "police"
	if f.is_in_group("staff"):
		return "staff"
	return "local"


## "m" or "f".
static func sex(f: Node) -> String:
	var v: Variant = f.get("voice") if "voice" in f else f.get_meta("voice", "")
	if v is String and v != "":
		return "f" if String(v).begins_with("f") else "m"
	if "farmer" in f and f.get("farmer") is Dictionary:
		var fid := String((f.get("farmer") as Dictionary).get("id", ""))
		if BarkLines.VOICES.has(fid):
			return BarkLines.VOICES[fid]["sex"]
	if f is Fighter:
		var look := FighterVisual.look_for(f as Fighter)
		if look != null:
			return "f" if look.feminine else "m"
	return "m"


## Number of lines `voice` has in `category` (0 if none).
static func bark_count(voice: String, category: String) -> int:
	var v: Dictionary = BarkLines.VOICES.get(voice, {})
	return (v.get("lines", {}) as Dictionary).get(category, []).size()


static func bark_path(voice: String, category: String, index: int) -> String:
	return "%s%s/%s_%02d.ogg" % [BARK_ROOT, voice, category, index + 1]


static func bark_text(voice: String, category: String, index: int) -> String:
	var lines: Array = (BarkLines.VOICES.get(voice, {}).get("lines", {}) as Dictionary).get(category, [])
	return String(lines[index]) if index >= 0 and index < lines.size() else ""


## Recorded chatter for `line_key` in `who`'s voice, or "" if there isn't one.
static func chatter_path(line_key: String, who: Node) -> String:
	var bits := line_key.split("/")
	if bits.size() != 3:
		return ""
	var topic := "shared" if bits[0] == "_" else bits[0]
	var voices: Array = BarkLines.CHATTER_LOCAL_VOICES if (topic == "shared" and bits[1] == "local") \
		else BarkLines.CHATTER_VOICES
	if voices.is_empty():
		return ""
	var vid := voice_id(who)
	if not voices.has(vid):
		vid = voices[absi(hash(String(who.name))) % voices.size()]
	var path := "%s%s/%s_%s_%02d.ogg" % [CHATTER_ROOT, vid, topic, bits[1], bits[2].to_int()]
	return path if ResourceLoader.exists(path) else ""
