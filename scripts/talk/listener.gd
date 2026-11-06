class_name Listener
extends Node
## Push-to-talk: records the microphone while the key is held, then turns the words into text
## with whisper.cpp, on this PC, in a background thread. Emits `heard(text, loud)`.
##
## The microphone opens on the first press and stays open after that (with a quarter second
## kept from before each press, so the first word isn't clipped). Audio goes through a
## silent "Mic" bus with a capture effect, so you never hear yourself.

signal heard(text: String, loud: bool)
## Whisper couldn't make anything out (or isn't installed). `why` is for the HUD.
signal not_heard(why: String)

const BUS := "Mic"
const RATE := 16000
const PRE_ROLL := 0.25
const MAX_SECONDS := 12.0
const MIN_SECONDS := 0.3
## Peak level (0..1) that counts as shouting.
const LOUD_PEAK := 0.55
const LOUD_RMS := 0.12
## Biases whisper towards the words people say in a pub fight.
const PROMPT := "Oi! Calm down, mate, it was an accident. Come on then! Sorry, let me buy you a pint."

var recording := false
var busy := false

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _frames := PackedVector2Array()
var _pre := PackedVector2Array()
var _thread: Thread


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## Open the microphone (once). False if this machine has no input.
func open_mic() -> bool:
	if _player != null:
		return true
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		push_warning("Push-to-talk: audio input is disabled in project settings")
		return false
	var idx := AudioServer.get_bus_index(BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		# Effects run before the bus volume, so the capture still gets the full signal.
		AudioServer.set_bus_volume_db(idx, -80.0)
		AudioServer.add_bus_effect(idx, AudioEffectCapture.new())
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(idx, i)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	add_child(_player)
	_player.play()
	return true


func start() -> void:
	if busy or not open_mic():
		return
	recording = true
	_frames = _pre.duplicate()
	_pre.clear()


## Stop recording and transcribe. Short taps are ignored.
func stop() -> void:
	if not recording:
		return
	recording = false
	_drain()
	var rate := AudioServer.get_mix_rate()
	if _frames.size() < rate * MIN_SECONDS:
		_frames.clear()
		return
	var mono := to_mono_16k(_frames, rate)
	_frames.clear()
	transcribe(mono)


func _process(_delta: float) -> void:
	if _capture == null:
		return
	_drain()


func _drain() -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var buf := _capture.get_buffer(n)
	var rate := AudioServer.get_mix_rate()
	if recording:
		_frames.append_array(buf)
		if _frames.size() > rate * MAX_SECONDS:
			stop()
	else:
		_pre.append_array(buf)
		var keep := int(rate * PRE_ROLL)
		if _pre.size() > keep:
			_pre = _pre.slice(_pre.size() - keep)


## Stereo frames at `rate` -> mono floats at 16 kHz (linear interpolation).
static func to_mono_16k(frames: PackedVector2Array, rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if frames.is_empty():
		return out
	var step := rate / RATE
	var count := int(frames.size() / step)
	out.resize(count)
	for i in count:
		var pos := i * step
		var a := int(pos)
		var b := mini(a + 1, frames.size() - 1)
		var t := pos - a
		var fa := frames[a]
		var fb := frames[b]
		out[i] = lerpf((fa.x + fa.y) * 0.5, (fb.x + fb.y) * 0.5, t)
	return out


## Shouted? From the recording's peak and loudness.
static func is_loud(mono: PackedFloat32Array) -> bool:
	if mono.is_empty():
		return false
	var peak := 0.0
	var sum := 0.0
	for s in mono:
		peak = maxf(peak, absf(s))
		sum += s * s
	var rms := sqrt(sum / mono.size())
	return peak >= LOUD_PEAK and rms >= LOUD_RMS


static func to_wav(mono: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(mono.size() * 2)
	for i in mono.size():
		data.encode_s16(i * 2, int(clampf(mono[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


## Turn 16 kHz mono audio into text in the background. Emits `heard` or `not_heard`.
func transcribe(mono: PackedFloat32Array) -> void:
	if busy:
		return
	if not SpeechTools.can_listen():
		not_heard.emit("Speech recognition isn't installed. Press Enter to type instead.")
		return
	busy = true
	var loud := is_loud(mono)
	var path := OS.get_user_data_dir().path_join("talk_heard.wav")
	to_wav(mono).save_to_wav(path)
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_run_whisper.bind(path, loud))


func _run_whisper(path: String, loud: bool) -> void:
	var out := []
	var threads := clampi(OS.get_processor_count() - 1, 1, 8)
	var args := ["-m", SpeechTools.whisper_model(), "-f", path, "-l", "en", "-nt", "-np",
		"-t", str(threads), "--prompt", PROMPT]
	var code := OS.execute(SpeechTools.whisper_exe(), args, out, false)
	var text := clean_transcript("\n".join(out)) if code == 0 else ""
	_done.call_deferred(text, loud, code)


func _done(text: String, loud: bool, code: int) -> void:
	busy = false
	if text == "":
		not_heard.emit("Didn't catch that." if code == 0 else "Speech recognition failed (%d)." % code)
	else:
		heard.emit(text, loud)


## Whisper's output to one clean line: drops [BLANK_AUDIO], (laughs) and the like.
static func clean_transcript(raw: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]|\\([^)]*\\)|\\*[^*]*\\*")
	var t := re.sub(raw, " ", true).replace("\n", " ").replace("\r", " ").strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	# Whisper sometimes hears the prompt back on silence.
	if t == PROMPT or t.length() < 2:
		return ""
	return t
