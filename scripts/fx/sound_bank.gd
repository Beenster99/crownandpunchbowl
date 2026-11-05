class_name SoundBank
extends RefCounted
## Cue table for every cosmetic sound. Gameplay never plays files directly: the FX
## director turns `Events` into cues, and each cue picks a random variant with a
## random pitch, so twenty punches in a row never sound the same.
##
## Files live in res://assets/audio/<path>_NN.<ext>. Most are recordings (CC0 / CC BY, see
## assets/audio/CREDITS.md, made by assets/audio/tools/import_recordings.py); grab, police
## whistle and door bang are still synthesised (generate_placeholders.py, ext "wav").
## Voice cues ending in `_m` have an `_f` twin for female fighters (see FxDirector).
## Spoken lines (barks, chatter) are not cues: see VoiceCast and BarkLines.

const ROOT := "res://assets/audio/"

## cue -> {path (prefix, no _NN), count, ext (default ogg), bus, pitch (random pitch
##         multiplier, >= 1), db (volume offset), range (metres to silence)}
const CUES := {
	# --- impacts
	"punch_body": {"path": "sfx/punch_body", "count": 12, "bus": "SFX", "pitch": 1.08, "db": 0.0, "range": 30.0},
	"punch_face": {"path": "sfx/punch_face", "count": 15, "bus": "SFX", "pitch": 1.08, "db": 1.0, "range": 30.0},
	"kick": {"path": "sfx/kick", "count": 6, "bus": "SFX", "pitch": 1.08, "db": 1.5, "range": 30.0},
	"headbutt": {"path": "sfx/headbutt", "count": 5, "bus": "SFX", "pitch": 1.06, "db": 2.0, "range": 30.0},
	"nose_crunch": {"path": "sfx/nose_crunch", "count": 6, "bus": "SFX", "pitch": 1.05, "db": 3.0, "range": 35.0},
	"bone_crack": {"path": "sfx/bone_crack", "count": 6, "bus": "SFX", "pitch": 1.06, "db": 0.0, "range": 30.0},
	"body_fall": {"path": "sfx/body_fall", "count": 6, "bus": "SFX", "pitch": 1.08, "db": 0.0, "range": 30.0},
	"glass_smash": {"path": "sfx/glass_smash", "count": 7, "bus": "SFX", "pitch": 1.08, "db": -1.0, "range": 35.0},
	"glass_clink": {"path": "sfx/glass_clink", "count": 4, "bus": "SFX", "pitch": 1.08, "db": -1.0, "range": 25.0},
	"wood_break": {"path": "sfx/wood_break", "count": 8, "bus": "SFX", "pitch": 1.08, "db": 0.0, "range": 35.0},
	"wood_hit": {"path": "sfx/wood_hit", "count": 6, "bus": "SFX", "pitch": 1.08, "db": 0.0, "range": 30.0},
	"whoosh": {"path": "sfx/whoosh", "count": 2, "bus": "SFX", "pitch": 1.2, "db": -8.0, "range": 15.0},
	"blood_splat": {"path": "sfx/blood_splat", "count": 5, "bus": "SFX", "pitch": 1.15, "db": -6.0, "range": 15.0},
	"grab": {"path": "sfx/grab", "count": 3, "ext": "wav", "bus": "SFX", "pitch": 1.1, "db": -3.0, "range": 20.0},
	"gulp": {"path": "sfx/gulp", "count": 5, "bus": "SFX", "pitch": 1.05, "db": -2.0, "range": 15.0},
	"munch": {"path": "sfx/munch", "count": 7, "bus": "SFX", "pitch": 1.08, "db": -4.0, "range": 15.0},
	"police_whistle": {"path": "sfx/police_whistle", "count": 1, "ext": "wav", "bus": "SFX", "pitch": 1.03, "db": 0.0, "range": 80.0},
	"door_bang": {"path": "sfx/door_bang", "count": 2, "ext": "wav", "bus": "SFX", "pitch": 1.08, "db": 0.0, "range": 60.0},
	"crowd_roar": {"path": "sfx/crowd_roar", "count": 3, "bus": "SFX", "pitch": 1.02, "db": -14.0, "range": 80.0},
	# --- non-verbal voice (male / female). Words are barks: see VoiceCast.
	"oof_m": {"path": "voice/oof_m", "count": 15, "bus": "Voice", "pitch": 1.06, "db": 0.0, "range": 30.0},
	"oof_f": {"path": "voice/oof_f", "count": 6, "bus": "Voice", "pitch": 1.05, "db": 0.0, "range": 30.0},
	"grunt_m": {"path": "voice/grunt_m", "count": 5, "bus": "Voice", "pitch": 1.06, "db": -4.0, "range": 20.0},
	"grunt_f": {"path": "voice/grunt_f", "count": 3, "bus": "Voice", "pitch": 1.05, "db": -4.0, "range": 20.0},
	"groan_m": {"path": "voice/groan_m", "count": 4, "bus": "Voice", "pitch": 1.05, "db": 0.0, "range": 30.0},
	"groan_f": {"path": "voice/groan_f", "count": 1, "bus": "Voice", "pitch": 1.05, "db": 0.0, "range": 30.0},
	"ko_m": {"path": "voice/ko_m", "count": 8, "bus": "Voice", "pitch": 1.05, "db": 1.0, "range": 30.0},
	"ko_f": {"path": "voice/ko_f", "count": 4, "bus": "Voice", "pitch": 1.05, "db": 1.0, "range": 30.0},
}

static var _cache := {}


static func has_cue(cue: String) -> bool:
	return CUES.has(cue)


static func clear_cache() -> void:
	_cache.clear()


## All file paths a cue can play. Used by tests to check nothing is missing.
static func files_for(cue: String) -> PackedStringArray:
	var out := PackedStringArray()
	var c: Dictionary = CUES[cue]
	for i in int(c["count"]):
		out.append("%s%s_%02d.%s" % [ROOT, c["path"], i + 1, c.get("ext", "ogg")])
	return out


## A randomizer stream over every variant of the cue (cached).
static func stream(cue: String) -> AudioStream:
	if _cache.has(cue):
		return _cache[cue]
	var c: Dictionary = CUES[cue]
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = float(c["pitch"])
	r.random_volume_offset_db = 1.5
	var i := 0
	for path in files_for(cue):
		var s := load(path) as AudioStream
		if s:
			r.add_stream(i, s)
			i += 1
		else:
			push_warning("SoundBank: missing %s" % path)
	_cache[cue] = r
	return r
