#!/usr/bin/env python3
"""Download, trim, layer and encode the recorded sound effects used in the game.

Every source is CC0 or CC BY, downloaded from OpenGameArt.org. Each one is listed in
SOURCES with its page, author and licence, and assets/audio/CREDITS.md is written from
that list, so the credits can't drift from what's actually shipped.

Usage (from the repo root):
    pip install soundfile numpy py7zr
    python3 assets/audio/tools/import_recordings.py [--cache /tmp/cp-audio]

Needs ffmpeg with libvorbis on PATH. Output: assets/audio/sfx/*.ogg and
assets/audio/voice/*.ogg (non-verbal voice: oofs, cries, swallows).
"""
import argparse
import os
import subprocess
import sys
import urllib.request
import zipfile

import numpy as np
import soundfile as sf

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
OGA = "https://opengameart.org/sites/default/files/"
SR = 44100

# key -> (download file, OGA page, author, licence)
SOURCES = {
	"hits": ("independent_nu_ljudbank-hits_and_punches.7z", "37-hitspunches", "Independent.nu (submitted by qubodup)", "CC0"),
	"crunch": ("independent_nu_ljudbank-break_crunch_impact.7z", "5-break-crunch-impacts", "Independent.nu (submitted by qubodup)", "CC0"),
	"wood": ("independent_nu_ljudbank-wood_crack_hit_destruction.7z", "35-wooden-crackshitsdestructions", "Independent.nu (submitted by qubodup)", "CC0"),
	"towel": ("wet_towel_on_floor.7z", "12-wet-towel-hittingfallingpunching-floor-sounds", "Iwan Gabovitch (qubodup)", "CC0"),
	"bfh": ("sfx_breaking_and_falling.zip", "75-cc0-breaking-falling-hit-sfx", "rubberduck", "CC0"),
	"glass": ("glass_breaking.wav", "glass-break", "Till Behrend", "CC0"),
	"wet": ("wet_breaks.zip", "fleshy-bone-breaksnap-sfx", "Zane Little Music", "CC0"),
	"deep": ("deep_breaks.zip", "deep-bone-crackbreak-sfx", "Zane Little Music", "CC0"),
	"drink": ("qubodup-bottle-and-drink-sounds.7z", "liquid-bottle-drink-set", "Iwan Gabovitch (qubodup)", "CC0"),
	"eat": ("crunch_-_tito.zip", "7-eating-crunches", "StarNinjas", "CC0"),
	"whoosh": ("whoosh2_0.wav", "air-whoosh", "Pyrano Studios", "CC0"),
	"crowd": ("crowd_shouting.ogg", "crowd-shoutingspeaking-ambience", "StarNinjas", "CC0"),
	"strain": ("slightscreams.7z", "15-vocal-male-strainhurtpainjump-sounds", "Iwan Gabovitch (qubodup)", "CC0"),
	"pain": ("michelbaradari-human.7z", "11-male-human-paindeath-sounds", "Michel Baradari", "CC BY 3.0"),
	"aargh": ("aargh.zip", "aargh-male-screams", "JohnsonBrandEditing via congusbongus (files 3 to 7 only)", "CC0"),
	"fhurt": ("female_hurt_grunts_groans_1.ogg", "female-hurt-grunts-groans", "Nocturnal_Vanguard", "CC0"),
	"fscream": ("female_screams.zip", "female-screams", "tcrocker68, pushkin and Archeos via congusbongus (files 1 to 4 only)", "CC0"),
}


# --------------------------------------------------------------------------- fetching
def fetch(cache):
	os.makedirs(cache, exist_ok=True)
	dirs = {}
	for key, (fname, *_rest) in SOURCES.items():
		path = os.path.join(cache, fname)
		if not os.path.exists(path):
			print("download", fname)
			urllib.request.urlretrieve(OGA + fname, path)
		out = os.path.join(cache, "x_" + key)
		if not os.path.isdir(out):
			os.makedirs(out)
			if fname.endswith(".zip"):
				with zipfile.ZipFile(path) as z:
					z.extractall(out)
			elif fname.endswith(".7z"):
				import py7zr
				with py7zr.SevenZipFile(path) as z:
					z.extractall(out)
			else:
				os.symlink(path, os.path.join(out, fname))
		dirs[key] = out
	return dirs


def find(dirs, key, name):
	for base, _d, files in os.walk(dirs[key]):
		if "__MACOSX" in base:
			continue
		for f in files:
			if f == name:
				return os.path.join(base, f)
	raise FileNotFoundError("%s/%s" % (key, name))


# --------------------------------------------------------------------------- processing
def load(path, start=None, end=None):
	x, sr = sf.read(path, always_2d=True)
	x = x.mean(axis=1)
	if start is not None:
		x = x[int(start * sr): int(end * sr) if end else None]
	if sr != SR:
		n = int(len(x) * SR / sr)
		x = np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)
	return x


def trim(x, floor_db=-48.0, tail=0.05, max_len=None):
	thr = np.max(np.abs(x)) * 10 ** (floor_db / 20)
	idx = np.where(np.abs(x) > thr)[0]
	if len(idx) == 0:
		return x
	a = max(0, idx[0] - int(0.004 * SR))
	b = min(len(x), idx[-1] + int(tail * SR))
	x = x[a:b]
	if max_len and len(x) > max_len * SR:
		x = x[: int(max_len * SR)]
	fade = min(len(x) // 3, int(0.03 * SR))
	x[-fade:] *= np.linspace(1, 0, fade) ** 2
	return x


def mix(base, *layers):
	"""layers: (signal, gain_db, offset_seconds)"""
	out = base.copy()
	for sig, gain, off in layers:
		o = int(off * SR)
		n = o + len(sig)
		if n > len(out):
			out = np.concatenate([out, np.zeros(n - len(out))])
		out[o:n] += sig * 10 ** (gain / 20)
	return out


def segments(x, min_len=0.12, gap=0.12, floor=0.06):
	"""Split a take with several sounds in it on silence."""
	w = int(0.01 * SR)
	env = np.array([np.max(np.abs(x[i:i + w])) for i in range(0, len(x) - w, w)])
	on = env > floor * env.max()
	segs, s, quiet = [], None, 0
	for i, v in enumerate(on):
		if v:
			if s is None:
				s = i
			quiet = 0
		elif s is not None:
			quiet += 1
			if quiet * 0.01 >= gap:
				if (i - quiet - s) * 0.01 >= min_len:
					segs.append(x[s * w: (i - quiet + 1) * w + int(0.08 * SR)])
				s, quiet = None, 0
	if s is not None:
		segs.append(x[s * w:])
	return segs


def write(rel, x, peak_db=-1.0, quality=4):
	x = np.asarray(x, dtype=np.float64)
	x = x / (np.max(np.abs(x)) or 1.0) * 10 ** (peak_db / 20)
	path = os.path.join(ROOT, rel)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	tmp = path + ".tmp.wav"
	sf.write(tmp, x.astype(np.float32), SR, subtype="PCM_16")
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis",
		"-q:a", str(quality), path], check=True)
	os.remove(tmp)
	print("wrote", rel, "%.2fs" % (len(x) / SR))


def batch(name, sigs, folder="sfx", **kw):
	for i, s in enumerate(sigs):
		write("%s/%s_%02d.ogg" % (folder, name, i + 1), s, **kw)


# --------------------------------------------------------------------------- the set
def build(d):
	hit = lambda n: trim(load(find(d, "hits", "hit%02d.mp3.flac" % n)), max_len=0.9)
	towel = lambda n: trim(load(find(d, "towel", "wet_towel_on_floor-%02d.flac" % n)))
	deep = lambda n: trim(load(find(d, "deep", "Deep Break %d.wav" % n)), max_len=0.7)
	wet = lambda n: trim(load(find(d, "wet", "Wet Break %d.wav" % n)), max_len=0.7)
	bfh = lambda n: trim(load(find(d, "bfh", n + ".ogg")))

	# Bare knuckles. The brighter, slappier takes go to the face; the duller ones to the body.
	batch("punch_face", [hit(n) for n in (1, 6, 9, 10, 11, 12, 13, 14, 16, 19, 21, 23, 31, 35, 36)])
	batch("punch_body", [hit(n) for n in (2, 4, 7, 17, 22, 24, 25, 28, 29, 32, 34, 37)])
	# Boots: a dull hit with a heavy cloth-and-body thump under it.
	batch("kick", [mix(hit(a), (towel(b), -4, 0.0)) for a, b in
		((8, 3), (20, 5), (26, 2), (30, 8), (33, 9), (3, 10))])
	# Headbutt: skull on skull, a crunch with a deep crack.
	batch("headbutt", [mix(trim(load(find(d, "crunch", "impactcrunch%02d.mp3.flac" % a))), (deep(b), -5, 0.0))
		for a, b in ((1, 1), (3, 6), (4, 2), (5, 8), (2, 4))])
	# Broken nose: a face punch with a wet cartilage snap on top.
	batch("nose_crunch", [mix(hit(a), (wet(b), -1, 0.01)) for a, b in
		((19, 1), (21, 3), (13, 5), (35, 7), (10, 8), (31, 2))])
	batch("bone_crack", [deep(n) for n in (1, 3, 4, 6, 7, 8)])
	batch("body_fall", [mix(towel(a), (towel(b), -8, 0.09)) for a, b in
		((3, 12), (5, 6), (2, 9), (7, 4), (8, 11), (10, 1))])
	batch("blood_splat", [towel(n) for n in (1, 4, 6, 11, 12)], peak_db=-6)
	batch("glass_smash", [bfh("bfh1_glass_breaking_%02d" % n) for n in range(1, 7)]
		+ [trim(load(find(d, "glass", "glass_breaking.wav")))])
	batch("glass_clink", [mix(bfh("bfh1_glass_hit_%02d" % a), (hit(b), -3, 0.0)) for a, b in
		((1, 2), (2, 7), (1, 24), (2, 28))])
	batch("wood_break", [bfh("bfh1_wood_breaking_%02d" % n) for n in range(1, 5)]
		+ [trim(load(find(d, "wood", "crack%02d.mp3.flac" % n)), max_len=1.2) for n in (1, 3, 5, 7)])
	batch("wood_hit", [mix(trim(load(find(d, "wood", "impactwood%02d.mp3.flac" % n)), max_len=0.8), (hit(h), -6, 0.0))
		for n, h in ((2, 2), (5, 4), (9, 7), (13, 17), (17, 22), (21, 29))])
	whooshes = [trim(s) for s in segments(load(find(d, "whoosh", "whoosh2_0.wav")), floor=0.1)]
	batch("whoosh", whooshes[:6] if whooshes else [trim(load(find(d, "whoosh", "whoosh2_0.wav")), max_len=0.5)])
	batch("gulp", [trim(load(find(d, "drink", "swallow-%02d.flac" % n))) for n in range(1, 6)])
	batch("munch", [trim(load(find(d, "eat", "crunch.%d.ogg" % n)), max_len=1.0) for n in range(1, 8)], peak_db=-4)
	crowd = load(find(d, "crowd", "crowd_shouting.ogg"))
	batch("crowd_roar", [trim(crowd[int(a * SR): int((a + 7) * SR)]) for a in (0, 9, 18)], peak_db=-3, quality=3)

	# Non-verbal voice. Words come from generate_voices.py.
	pain = lambda n: trim(load(find(d, "pain", n + ".wav")))
	strain = lambda n: trim(load(find(d, "strain", "slightscream-%02d.flac" % n)))
	batch("oof_m", [pain(n) for n in ("pain1", "pain2", "pain3", "pain4", "pain5", "pain6", "painh", "paino")]
		+ [strain(n) for n in (1, 3, 8, 11, 12, 13, 14)], folder="voice")
	batch("grunt_m", [strain(n) for n in (2, 4, 6, 7, 9)], folder="voice", peak_db=-3)
	batch("ko_m", [pain(n) for n in ("die1", "die2", "deathh")]
		+ [trim(load(find(d, "aargh", "aargh%d.ogg" % n))) for n in (3, 4, 5, 6, 7)], folder="voice")
	batch("groan_m", [strain(n) for n in (5, 10, 15)] + [pain("die2")], folder="voice")
	fh = segments(load(find(d, "fhurt", "female_hurt_grunts_groans_1.ogg")))
	fh = [trim(s) for s in fh]
	batch("oof_f", fh[:6], folder="voice")
	batch("groan_f", fh[6:] or fh[:2], folder="voice")
	batch("grunt_f", fh[:3], folder="voice", peak_db=-3)
	batch("ko_f", [trim(load(find(d, "fscream", "%d.ogg" % n)), max_len=1.4) for n in (1, 2, 3, 4)], folder="voice")


def write_credits():
	lines = [
		"# Audio credits",
		"",
		"Every sound in the game, where it came from and its licence. CC0 needs no credit but is",
		"listed anyway. CC BY sources must be credited in the game's credits screen, using the text",
		"below. Regenerate the recorded part with `assets/audio/tools/import_recordings.py`.",
		"",
		"## Recorded sound effects (OpenGameArt.org)",
		"",
		"Trimmed, mixed to mono, layered and re-encoded. See `import_recordings.py` for which take",
		"went where.",
		"",
		"| Pack | Author | Licence |",
		"| --- | --- | --- |",
	]
	for key, (_f, page, author, lic) in SOURCES.items():
		lines.append("| [%s](https://opengameart.org/content/%s) | %s | %s |" % (page.replace("-", " "), page, author, lic))
	lines += [
		"",
		"## Spoken lines",
		"",
		"Generated with [Piper](https://github.com/OHF-Voice/piper1-gpl) text-to-speech by",
		"`assets/audio/tools/generate_voices.py`. Piper is only used offline to make the files;",
		"none of it ships with the game. The voice models are",
		"[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) `en_GB-vctk-medium`,",
		"trained on the CSTR VCTK Corpus.",
		"",
		"- CSTR VCTK Corpus: English Multi-speaker Corpus for CSTR Voice Cloning Toolkit (version 0.92),",
		"  Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald, University of Edinburgh, CSTR.",
		"  https://doi.org/10.7488/ds/2645. Licence: CC BY 4.0.",
		"",
		"## Synthesised in-house (CC0)",
		"",
		"`sfx/grab_*`, `sfx/police_whistle_*` and `sfx/door_bang_*` come from",
		"`assets/audio/tools/generate_placeholders.py`.",
		"",
		"## Credits screen text",
		"",
		"Sound effects by Michel Baradari (CC BY 3.0), Independent.nu, qubodup, rubberduck, Till Behrend,",
		"Zane Little Music, StarNinjas, Pyrano Studios, Nocturnal_Vanguard and others via OpenGameArt.org.",
		"Voices made with Piper TTS using the CSTR VCTK Corpus (University of Edinburgh, CC BY 4.0).",
	]
	with open(os.path.join(ROOT, "CREDITS.md"), "w") as f:
		f.write("\n".join(lines) + "\n")
	print("wrote CREDITS.md")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--cache", default="/tmp/cp-audio")
	a = ap.parse_args()
	build(fetch(a.cache))
	write_credits()


if __name__ == "__main__":
	sys.exit(main())
