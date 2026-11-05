class_name ChatterVoice
extends RefCounted
## Placeholder voice for overheard chatter: a muffled, posh "wah-wah" murmur shaped like the
## line (syllables per word, pauses at punctuation, pitch falling at the end, rising on a
## question). Built from a small bank of synthesised vowel syllables, so a whole line is just
## byte arrays stuck together. No per-sample work at say-time.
##
## Real recordings win: if ChatterLines.voice_path(key) exists, that file plays instead.

const RATE := 16000
## Vowel formants (F1, F2) in Hz: ah, eh, ee, oh, oo, uh.
const VOWELS := [Vector2(750, 1150), Vector2(530, 1850), Vector2(300, 2250),
	Vector2(500, 900), Vector2(330, 850), Vector2(620, 1200)]
## Pitch levels: rising, middle, falling.
const PITCH := [1.18, 1.0, 0.86]
const BASE_F0 := {"m": 112.0, "f": 205.0}
const MAX_CACHE := 48

## voice -> Array (pitch level) of Array (syllable) of PackedByteArray (PCM16 mono)
static var _banks := {}
## "voice|key" -> AudioStreamWAV
static var _cache := {}
static var _cache_order: Array[String] = []


## A murmur stream for `text`. `voice` is "m" or "f". Cached per line.
static func stream_for(line_key: String, text: String, voice: String) -> AudioStreamWAV:
	var ck := voice + "|" + line_key
	if _cache.has(ck):
		return _cache[ck]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ck)
	var bank := _bank(voice)
	var data := PackedByteArray()
	var words := text.split(" ", false)
	for wi in words.size():
		var w: String = words[wi]
		var syllables := clampi(roundi(w.length() / 3.2), 1, 4)
		var last_word := wi == words.size() - 1
		var level := 1
		if wi == 0:
			level = 0
		elif last_word:
			level = 0 if text.ends_with("?") else 2
		elif rng.randf() < 0.25:
			level = rng.randi_range(0, 2)
		for s in syllables:
			var sl: Array = bank[level]
			data.append_array(sl[rng.randi_range(0, sl.size() - 1)])
		var gap := 0.05
		if w.ends_with(",") or w.ends_with("..."):
			gap = 0.18
		elif w.ends_with(".") or w.ends_with("!") or w.ends_with("?"):
			gap = 0.28
		data.append_array(_silence(gap * rng.randf_range(0.8, 1.2)))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	_cache[ck] = wav
	_cache_order.append(ck)
	if _cache_order.size() > MAX_CACHE:
		_cache.erase(_cache_order.pop_front())
	return wav


static func length_of(wav: AudioStreamWAV) -> float:
	return wav.data.size() / 2.0 / RATE


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


## Build (once per voice) every vowel at every pitch level, at two lengths.
static func _bank(voice: String) -> Array:
	if _banks.has(voice):
		return _banks[voice]
	var f0: float = BASE_F0.get(voice, BASE_F0["m"])
	var levels := []
	for p in PITCH:
		var syl := []
		for v in VOWELS:
			var table := _period(f0 * p, v)
			syl.append(_syllable(table, 0.11))
			syl.append(_syllable(table, 0.17))
		levels.append(syl)
	_banks[voice] = levels
	return levels


## One period of a voiced vowel: harmonics of f0 weighted by two formant peaks, with the
## top end rolled off so it sounds heard through a pub's worth of noise.
static func _period(f0: float, formants: Vector2) -> PackedFloat32Array:
	var n := maxi(int(RATE / f0), 8)
	var table := PackedFloat32Array()
	table.resize(n)
	var harmonics := mini(int(2400.0 / f0), 24)
	var peak := 0.0
	for i in n:
		var ph := TAU * float(i) / float(n)
		var s := 0.0
		for k in range(1, harmonics + 1):
			var f := f0 * k
			var g := exp(-pow((f - formants.x) / 180.0, 2.0)) \
				+ 0.6 * exp(-pow((f - formants.y) / 260.0, 2.0)) + 0.25 / k
			s += g * sin(ph * k)
		table[i] = s
		peak = maxf(peak, absf(s))
	for i in n:
		table[i] /= maxf(peak, 0.001)
	return table


static func _syllable(table: PackedFloat32Array, seconds: float) -> PackedByteArray:
	var count := int(seconds * RATE)
	var out := PackedByteArray()
	out.resize(count * 2)
	var n := table.size()
	var attack := 0.02 * RATE
	var release := 0.05 * RATE
	for i in count:
		var env := minf(1.0, i / attack) * minf(1.0, (count - i) / release)
		# A slight wobble so it doesn't buzz like a synth.
		var idx := fmod(i * (1.0 + 0.012 * sin(i * 0.0015)), float(n))
		var a := int(idx)
		var t := idx - a
		var s := lerpf(table[a], table[(a + 1) % n], t) * env * 0.55
		out.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	return out


static func _silence(seconds: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(int(seconds * RATE) * 2)
	out.fill(0)
	return out
