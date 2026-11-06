class_name PunterVoice
extends Node
## Speaks punters' replies out loud, from the punter's own position in the pub.
##
## Engines, best first:
##   ElevenLabs   very natural voices, only if you paste an ElevenLabs key in Settings > Talk
##   Piper        free, on this PC (speech/piper), the same VCTK voices as the recorded barks,
##                so each punter sounds like themselves whether they're barking or chatting
##   Windows      the voices built into Windows, if the speech tools are missing
## If one fails it falls through to the next, and the bubble always shows the words.
##
## Piper runs as one long-lived process (the voice model loads once), fed one JSON line per
## sentence from a worker thread; it writes a WAV and prints its path.

signal spoken(who: Node3D, text: String, engine: String)

## Voice id (BarkLines / VoiceCast) -> VCTK speaker, plus extra women's voices per role for
## live replies (the recorded barks only have men in some roles). Pitch is a playback tweak.
const CAST := {
	"posh_m1": ["p226", 1.0], "posh_m2": ["p254", 1.0], "local_m1": ["p243", 0.97],
	"local_m2": ["p274", 0.98], "rugby_m1": ["p278", 0.95], "rugby_m2": ["p279", 0.94],
	"police_m1": ["p287", 0.97], "police_m2": ["p273", 0.96], "staff_f1": ["p276", 1.0],
	"staff_m1": ["p232", 0.97],
	"posh_f1": ["p225", 1.0], "posh_f2": ["p228", 1.0], "local_f1": ["p236", 1.0],
	"local_f2": ["p277", 1.0], "rugby_f1": ["p229", 1.0], "police_f1": ["p240", 1.0],
}
const FEMALE := {"posh": ["posh_f1", "posh_f2"], "local": ["local_f1", "local_f2"],
	"rugby": ["rugby_f1"], "police": ["police_f1"], "staff": ["staff_f1"]}
## ElevenLabs premade voices with British accents, by sex and role.
const ELEVEN := {
	"m": {"posh": ["JBFqnCBsd6RMkjVDRZzb", "onwK4e9ZLuTAKqWW03F9"], "local": ["CYw3kZ02Hs0563khs1Fj"],
		"rugby": ["CYw3kZ02Hs0563khs1Fj"], "police": ["onwK4e9ZLuTAKqWW03F9"], "staff": ["JBFqnCBsd6RMkjVDRZzb"]},
	"f": {"posh": ["Xb7hH8MSUJpSbSDYk0k2"], "local": ["pFZP5JQG7iQjIQuC4Bku"], "rugby": ["pFZP5JQG7iQjIQuC4Bku"],
		"police": ["Xb7hH8MSUJpSbSDYk0k2"], "staff": ["pFZP5JQG7iQjIQuC4Bku"]},
}
const ELEVEN_URL := "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=pcm_22050"
const ELEVEN_MODEL := "eleven_flash_v2_5"

## "piper" (falls back to Windows voices) or "off".
var engine := "piper"
var eleven_key := ""
var volume_db := 0.0

var _speaker_ids := {}
var _piper_pid := -1
var _piper_io: FileAccess
var _piper_broken := false
var _thread: Thread
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _queue: Array[Dictionary] = []
var _quit := false
var _next := 0
var _jobs := {}  # job id -> {who, text}
var _tts_voice := ""


func _exit_tree() -> void:
	_quit = true
	if _thread != null and _thread.is_started():
		_sem.post()
		_thread.wait_to_finish()
	if _piper_pid > 0:
		OS.kill(_piper_pid)
		_piper_pid = -1


## Say `text` as `who` (an NPC). `voice` is a VoiceCast voice id, `sex` "m" or "f", `role`
## a VoiceCast role. Safe to call on any peer: it only plays sound.
func speak(who: Node3D, text: String, voice: String, sex: String, role: String) -> void:
	if engine == "off" or text.strip_edges() == "" or DisplayServer.get_name() == "headless":
		return
	if eleven_key.strip_edges() != "":
		_speak_eleven(who, text, sex, role)
		return
	if _piper_ready():
		_speak_piper(who, text, pick_speaker(voice, sex, role, who.name))
		return
	_speak_windows(text, sex)


## The CAST id this NPC speaks with live: its bark voice, or a woman's voice for its role.
static func pick_speaker(voice: String, sex: String, role: String, npc_name: String) -> String:
	if sex == "f" and FEMALE.has(role):
		if CAST.has(voice) and voice.contains("_f"):
			return voice
		var pool: Array = FEMALE[role]
		return pool[absi(hash(npc_name)) % pool.size()]
	return voice if CAST.has(voice) else "local_m1"


# --- Piper -----------------------------------------------------------------------------

func _piper_ready() -> bool:
	if _piper_broken:
		return false
	if _piper_pid > 0:
		return true
	if not SpeechTools.can_speak():
		_piper_broken = true
		return false
	_speaker_ids = SpeechTools.speaker_ids()
	var out_dir := OS.get_user_data_dir().path_join("talk_voice")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in DirAccess.get_files_at(out_dir):
		DirAccess.remove_absolute(out_dir.path_join(f))
	var args := ["--model", SpeechTools.voice_model(), "--json-input", "--output_dir", out_dir, "--quiet"]
	var proc := OS.execute_with_pipe(SpeechTools.piper_exe(), args, true)
	if proc.is_empty():
		_piper_broken = true
		return false
	_piper_pid = int(proc["pid"])
	_piper_io = proc["stdio"]
	_thread = Thread.new()
	_thread.start(_piper_worker)
	return true


func _speak_piper(who: Node3D, text: String, cast_id: String) -> void:
	_next += 1
	_jobs[_next] = {"who": who, "text": text, "pitch": float(CAST[cast_id][1])}
	var spk := String(CAST[cast_id][0])
	var line := JSON.stringify({"text": text, "speaker_id": int(_speaker_ids.get(spk, 0))})
	_mutex.lock()
	_queue.append({"id": _next, "line": line})
	_mutex.unlock()
	_sem.post()


func _piper_worker() -> void:
	while true:
		_sem.wait()
		if _quit:
			return
		_mutex.lock()
		var job: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_mutex.unlock()
		if job.is_empty():
			continue
		_piper_io.store_line(String(job["line"]))
		_piper_io.flush()
		var path := ""
		# Piper prints the path of each WAV it writes. Anything else is noise.
		for i in 50:
			var l := _piper_io.get_line().strip_edges()
			if l.ends_with(".wav"):
				path = l
				break
			if _piper_io.get_error() != OK:
				break
		_piper_done.call_deferred(int(job["id"]), path)
		if path == "":
			return  # the process died: stop feeding it


func _piper_done(id: int, path: String) -> void:
	var job: Dictionary = _jobs.get(id, {})
	_jobs.erase(id)
	if path == "":
		push_warning("Piper stopped answering; using Windows voices for punters")
		_piper_broken = true
		if _piper_pid > 0:
			OS.kill(_piper_pid)
		_piper_pid = -1
		if not job.is_empty():
			_speak_windows(job["text"], "m")
		return
	var wav := AudioStreamWAV.load_from_file(path)
	DirAccess.remove_absolute(path)
	if job.is_empty() or wav == null or not is_instance_valid(job["who"]):
		return
	_play(job["who"], wav, float(job["pitch"]))
	spoken.emit(job["who"], job["text"], "piper")


# --- ElevenLabs ------------------------------------------------------------------------

func _speak_eleven(who: Node3D, text: String, sex: String, role: String) -> void:
	var pool: Array = ELEVEN.get(sex, ELEVEN["m"]).get(role, ELEVEN["m"]["local"])
	var voice_id: String = pool[absi(hash(String(who.name))) % pool.size()]
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if code != 200 or body.size() < 100:
			push_warning("ElevenLabs voice failed (HTTP %d); using Piper" % code)
			var role_voice := pick_speaker("", sex, role, who.name) if is_instance_valid(who) else ""
			if is_instance_valid(who) and _piper_ready():
				_speak_piper(who, text, role_voice)
			return
		if not is_instance_valid(who):
			return
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 22050
		wav.data = body
		_play(who, wav, 1.0)
		spoken.emit(who, text, "elevenlabs"))
	var headers := PackedStringArray(["content-type: application/json", "xi-api-key: " + eleven_key.strip_edges()])
	http.request(ELEVEN_URL % voice_id, headers, HTTPClient.METHOD_POST,
		JSON.stringify({"text": text, "model_id": ELEVEN_MODEL}))


# --- Windows voices --------------------------------------------------------------------

func _speak_windows(text: String, sex: String) -> void:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return
	if _tts_voice == "":
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if voices.is_empty():
			return
		_tts_voice = voices[0]
		for v in DisplayServer.tts_get_voices():
			if String(v.get("language", "")).begins_with("en_GB"):
				_tts_voice = v["id"]
				break
	DisplayServer.tts_speak(text, _tts_voice, 80, 0.95 if sex == "m" else 1.15)


func _play(who: Node3D, stream: AudioStream, pitch: float) -> void:
	var player := who.get_node_or_null("TalkVoice") as AudioStreamPlayer3D
	if player == null:
		player = AudioStreamPlayer3D.new()
		player.name = "TalkVoice"
		player.bus = &"Voice"
		player.position.y = 1.6
		player.unit_size = 4.0
		player.max_distance = 30.0
		who.add_child(player)
	# Stop any overheard chatter so two lines don't talk over each other.
	var chatter := who.get_node_or_null("ChatterVoice") as AudioStreamPlayer3D
	if chatter != null:
		chatter.stop()
	player.volume_db = volume_db
	player.pitch_scale = pitch * (1.0 + (absi(hash(String(who.name))) % 5 - 2) * 0.015)
	player.stream = stream
	player.play()
