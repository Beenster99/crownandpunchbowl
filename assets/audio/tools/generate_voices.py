#!/usr/bin/env python3
"""Generate every spoken line in the game: fight barks and the overheard pub chatter.

Voices are Piper text-to-speech with the en_GB VCTK model (CC BY 4.0, see ../CREDITS.md).
Piper only runs here, offline. The game ships the resulting .ogg files, not Piper.

Usage (from the repo root):
    pip install piper-tts soundfile numpy
    # 1. dump the chatter lines from the game's own table
    godot --headless --path . --script res://tests/dump_chatter_lines.gd > /tmp/chatter.tsv
    # 2. render (models are downloaded to --models on first run)
    python3 assets/audio/tools/generate_voices.py --chatter /tmp/chatter.tsv

Outputs:
    assets/audio/voice/barks/<voice>/<category>_NN.ogg
    assets/audio/voice/chatter/<voice>/<topic>_<part>_NN.ogg
    scripts/fx/bark_lines.gd    (generated: which lines exist, for the game and for subtitles)
Edit BARKS / CAST below, not the generated GDScript.
"""
import argparse
import hashlib
import json
import os
import subprocess
import urllib.request

import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio", "voice")
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/vctk/medium/"
MODEL = "en_GB-vctk-medium"
SR = 22050

# voice id -> VCTK speaker, sex, role and delivery.
# length: >1 slower. noise: expressiveness. pitch: resample factor (>1 higher, also faster).
CAST = {
	# The six farmers.
	"tom": {"spk": "p270", "sex": "m", "role": "farmer", "length": 1.08, "noise": 0.75, "pitch": 0.93},
	"gaz": {"spk": "p256", "sex": "m", "role": "farmer", "length": 0.88, "noise": 0.8, "pitch": 1.02},
	"barrow": {"spk": "p227", "sex": "m", "role": "farmer", "length": 1.18, "noise": 0.7, "pitch": 0.92},
	"mags": {"spk": "p267", "sex": "f", "role": "farmer", "length": 0.98, "noise": 0.75, "pitch": 0.97},
	"dicky": {"spk": "p286", "sex": "m", "role": "farmer", "length": 1.2, "noise": 0.95, "pitch": 0.97},
	"kev": {"spk": "p259", "sex": "m", "role": "farmer", "length": 1.0, "noise": 0.75, "pitch": 0.96},
	# Punters, police and staff. NPCs pick one of their role's voices by name.
	"posh_m1": {"spk": "p226", "sex": "m", "role": "posh", "length": 1.0, "noise": 0.7, "pitch": 1.0},
	"posh_m2": {"spk": "p254", "sex": "m", "role": "posh", "length": 1.02, "noise": 0.7, "pitch": 1.0},
	"local_m1": {"spk": "p243", "sex": "m", "role": "local", "length": 0.98, "noise": 0.8, "pitch": 0.97},
	"local_m2": {"spk": "p274", "sex": "m", "role": "local", "length": 1.0, "noise": 0.8, "pitch": 0.98},
	"rugby_m1": {"spk": "p278", "sex": "m", "role": "rugby", "length": 0.95, "noise": 0.8, "pitch": 0.95},
	"rugby_m2": {"spk": "p279", "sex": "m", "role": "rugby", "length": 0.95, "noise": 0.8, "pitch": 0.94},
	"police_m1": {"spk": "p287", "sex": "m", "role": "police", "length": 1.0, "noise": 0.65, "pitch": 0.97},
	"police_m2": {"spk": "p273", "sex": "m", "role": "police", "length": 1.0, "noise": 0.65, "pitch": 0.96},
	"staff_f1": {"spk": "p276", "sex": "f", "role": "staff", "length": 0.95, "noise": 0.75, "pitch": 1.0},
	"staff_m1": {"spk": "p232", "sex": "m", "role": "staff", "length": 1.05, "noise": 0.6, "pitch": 0.97},
}

# Lines per role and category. Farmers also get FARMER_EXTRA.
# Categories the game uses: taunt, hurt, down, crawl, win, drink, food, grab, thrown, panic.
BARKS = {
	"farmer": {
		"taunt": [
			"Come on then!", "Is that all you've got?", "Go back to Fulham!", "This is OUR pub!",
			"You're in the wrong village, pal.", "Get off my land!", "Have some of that!",
			"Call that a punch?", "Your Range Rover's blocking my tractor!", "Right. Who's next?",
			"Tell your estate agent about this!", "Second home? Second-hand face!",
		],
		"hurt": [
			"Ow!", "You cheeky sod!", "Right. Now I'm angry.", "Ooh, that smarts.", "Not the nose!",
			"You'll pay for that!", "Mind my pint!", "Bloody hell!",
		],
		"down": ["Oof. Me back!", "I'm alright! I'm alright!", "Who put the floor there?"],
		"crawl": [
			"Ohh... me head...", "Somebody get me a pint...", "Just... resting...",
			"I'll get you... in a minute...", "Is it closing time?",
		],
		"win": ["Night night!", "Stay down!", "And don't come back!", "That's for the house prices!", "Next!"],
		"drink": ["Ahh. That's the stuff.", "Lovely drop, that.", "Same again, landlord!"],
		"food": ["Mm. Proper pie, that.", "Lovely scratchings."],
		"grab": ["Hold still!", "Hit him! I've got him!", "Go on, lamp him!", "I've got this one!"],
		"thrown": ["Whoa!", "Put me down!"],
	},
	"posh": {
		"taunt": [
			"I'm warning you, I did a term of judo!", "Stay back! I've got a Waitrose card!",
			"I'll sue!", "Have at you, you yokel!", "Do you know who my father is?",
		],
		"hurt": [
			"Ow! My veneers!", "Not the face!", "I'll have you know I'm a barrister!", "My Barbour!",
			"I'm calling my solicitor!", "This is assault!", "That's going on Tripadvisor!", "Mummy!",
			"I pay council tax here! Some of it!",
		],
		"down": ["My chinos!", "Somebody film this, for the lawyers!"],
		"crawl": [
			"Somebody call Rupert...", "I want to go back to London...", "My gilet... is ruined...",
			"Is there a doctor? A private one?",
		],
		"win": ["Ha! Take that!", "That's what you get!"],
		"panic": ["Oh my God, it's kicking off!", "Darling, get the car!", "Not in front of the Labrador!"],
		"thrown": ["Not the Farrow and Ball!", "Aaah!"],
	},
	"local": {
		"taunt": ["Go on, have a go!", "Outside, now!", "You spilled my pint!", "I'll have you!"],
		"hurt": ["Ow, you prat!", "Right, that's it!", "My eye!"],
		"down": ["Oh, come on!"],
		"crawl": ["Me nose... me lovely nose...", "Where's me pint gone..."],
		"win": ["Have that!", "Lights out!"],
		"thrown": ["Oi!"],
	},
	"rugby": {
		"taunt": ["Ruck him!", "Come on, lads!", "Who wants some?", "Scrum down!"],
		"hurt": ["Is that it?", "Didn't feel a thing!", "Ooh, that's a yellow card!"],
		"down": ["Man down!"],
		"crawl": ["Is it half time...", "Where's the physio..."],
		"win": ["Try!", "Get in!"],
		"thrown": ["Lineout!"],
	},
	"police": {
		"taunt": [
			"Oi! Stop right there!", "Evening all. Who started it?", "Right, you're all nicked!",
			"Stop resisting!", "In the van!",
		],
		"hurt": ["Ow! That's another charge!", "Officer down!", "Assaulting an officer, that is!"],
		"down": ["Requesting backup!"],
		"crawl": ["Any units... any units at all..."],
		"win": ["You're nicked, sunshine.", "Mind your head on the van."],
		"thrown": ["Oi!"],
	},
	"staff": {
		"panic": [
			"Not the good glasses!", "You're all barred!", "Take it outside!", "I've just mopped that!",
			"Last orders! Last orders!", "Who's paying for that table?",
		],
		"hurt": ["Oi! I'm working!"],
	},
}

FARMER_EXTRA = {
	"tom": {"taunt": ["Say hello to my forehead!", "Built like a silo, me."]},
	"gaz": {"taunt": ["Too quick for you!", "Can't catch me!"]},
	"barrow": {"taunt": ["I've been fighting since nineteen sixty-eight!", "Back in my day we fought proper!",
		"Seventy-three and still swinging!"]},
	"mags": {"taunt": ["I run the parish council, dear!", "I've milked cows tougher than you!", "Language!"]},
	"dicky": {"taunt": ["Come 'ere. Hic.", "I'm not drunk, you're blurry!", "Whose round is it?"],
		"drink": ["Hair of the dog!"]},
	"kev": {"taunt": ["Right tool for the job!", "I'll fix your face!"]},
}

# Chatter: which voices say the second-homers' lines, and which say the locals' replies.
CHATTER_VOICES = ["posh_m1"]  # one voice keeps the repo small; Chatter varies pitch per talker
CHATTER_LOCAL_VOICES = ["local_m1", "rugby_m1"]


# --------------------------------------------------------------------------- rendering
def load_voice(models):
	from piper import PiperVoice
	os.makedirs(models, exist_ok=True)
	for ext in ("onnx", "onnx.json"):
		p = os.path.join(models, "%s.%s" % (MODEL, ext))
		if not os.path.exists(p):
			print("download", os.path.basename(p))
			urllib.request.urlretrieve(HF + "%s.%s" % (MODEL, ext), p)
	onnx = os.path.join(models, MODEL + ".onnx")
	ids = json.load(open(onnx + ".json"))["speaker_id_map"]
	return PiperVoice.load(onnx), ids


def render(voice, ids, cast, text, seed):
	from piper import SynthesisConfig
	cfg = SynthesisConfig(speaker_id=ids[cast["spk"]], length_scale=cast["length"],
		noise_scale=cast["noise"], noise_w_scale=0.8)
	np.random.seed(seed)
	x = np.concatenate([c.audio_float_array for c in voice.synthesize(text, cfg)])
	if cast["pitch"] != 1.0:  # resample: lower and slower, or higher and quicker
		n = int(len(x) / cast["pitch"])
		x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
	return finish(x)


def finish(x):
	thr = np.max(np.abs(x)) * 0.01
	idx = np.where(np.abs(x) > thr)[0]
	if len(idx):
		x = x[max(0, idx[0] - 200): idx[-1] + int(0.06 * SR)]
	# Gentle compression so shouts and mutters sit at a similar level.
	x = np.tanh(x / (np.max(np.abs(x)) or 1) * 1.6)
	return x / (np.max(np.abs(x)) or 1) * 0.89


def write(path, x, quality, rate=SR):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	tmp = path + ".tmp.wav"
	sf.write(tmp, x.astype(np.float32), SR, subtype="PCM_16")
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ac", "1", "-ar", str(rate), "-c:a", "libvorbis",
		"-q:a", str(quality), path], check=True)
	os.remove(tmp)


def seed_of(*parts):
	return int(hashlib.md5("|".join(parts).encode()).hexdigest()[:8], 16)


def lines_for(vid):
	cast = CAST[vid]
	out = {k: list(v) for k, v in BARKS[cast["role"]].items()}
	for cat, extra in FARMER_EXTRA.get(vid, {}).items():
		out.setdefault(cat, []).extend(extra)
	return out


def do_barks(voice, ids, only):
	manifest = {}
	for vid, cast in CAST.items():
		cats = lines_for(vid)
		manifest[vid] = {"sex": cast["sex"], "role": cast["role"], "lines": cats}
		if only and vid not in only:
			continue
		for cat, lines in cats.items():
			for i, text in enumerate(lines):
				path = os.path.join(AUDIO, "barks", vid, "%s_%02d.ogg" % (cat, i + 1))
				write(path, render(voice, ids, cast, text, seed_of(vid, cat, str(i))), 3)
		print("barks", vid, sum(len(v) for v in cats.values()))
	return manifest


def do_chatter(voice, ids, tsv):
	rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8") if "\t" in l]
	done = 0
	for key, text, *_ in rows:
		topic, part, idx = key.split("/")
		topic = "shared" if topic == "_" else topic
		name = "%s_%s_%02d.ogg" % (topic, part, int(idx))
		voices = CHATTER_LOCAL_VOICES if (topic == "shared" and part == "local") else CHATTER_VOICES
		for vid in voices:
			path = os.path.join(AUDIO, "chatter", vid, name)
			if os.path.exists(path):
				continue
			x = render(voice, ids, CAST[vid], text, seed_of(vid, key))
			write(path, x, -1, 16000)  # overheard across a pub: low bitrate is fine
			done += 1
	print("chatter files written", done)


def write_manifest(manifest):
	path = os.path.join(ROOT, "scripts", "fx", "bark_lines.gd")
	out = [
		"class_name BarkLines",
		"extends RefCounted",
		"## GENERATED by assets/audio/tools/generate_voices.py. Edit the lines there and re-run it.",
		"## Every voice, its role and sex, and the text of each fight bark it can say. Audio for",
		"## line i of a category is res://assets/audio/voice/barks/<voice>/<category>_<i+1, 2 digits>.ogg.",
		"",
		"const VOICES := {",
	]
	for vid, m in manifest.items():
		out.append('\t"%s": {"sex": "%s", "role": "%s", "lines": {' % (vid, m["sex"], m["role"]))
		for cat, lines in m["lines"].items():
			out.append('\t\t"%s": %s,' % (cat, json.dumps(lines, ensure_ascii=False)))
		out.append("\t}},")
	out += ["}", "", "## Voice ids per role, for NPCs that pick a voice by name.", "const ROLES := {"]
	roles = {}
	for vid, m in manifest.items():
		roles.setdefault(m["role"], []).append(vid)
	for r, v in roles.items():
		out.append('\t"%s": %s,' % (r, json.dumps(v)))
	out += ["}", "", "## Voices that have recorded chatter (res://assets/audio/voice/chatter/<voice>/...).",
		"const CHATTER_VOICES := %s" % json.dumps(CHATTER_VOICES),
		"const CHATTER_LOCAL_VOICES := %s" % json.dumps(CHATTER_LOCAL_VOICES), ""]
	with open(path, "w", encoding="utf-8") as f:
		f.write("\n".join(out))
	print("wrote", os.path.relpath(path, ROOT))


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--models", default="/tmp/cp-piper")
	ap.add_argument("--chatter", help="TSV from tests/dump_chatter_lines.gd; skip chatter if absent")
	ap.add_argument("--only", nargs="*", help="only render these voice ids (barks)")
	a = ap.parse_args()
	voice, ids = load_voice(a.models)
	write_manifest(do_barks(voice, ids, a.only))
	if a.chatter:
		do_chatter(voice, ids, a.chatter)


if __name__ == "__main__":
	main()
