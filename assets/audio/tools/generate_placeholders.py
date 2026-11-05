#!/usr/bin/env python3
"""Generate the placeholder sound set for Crown and Punchbowl.

Every sound is synthesised from scratch here (noise, sine partials and a small
formant voice), so the output has no third-party licence: treat it as CC0.
Real recorded audio replaces these at milestone M4; keep the file names so the
cue table in scripts/fx/sound_bank.gd still points at the right files.

Usage (from the repo root):  python3 assets/audio/tools/generate_placeholders.py
Needs only numpy. Output is deterministic (fixed seeds).
"""
import math
import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))


# --------------------------------------------------------------------------- helpers
def t_axis(dur):
	return np.arange(int(dur * SR)) / SR


def env_exp(n, tau):
	return np.exp(-np.arange(n) / SR / tau)


def adsr(n, a=0.005, r=0.05):
	e = np.ones(n)
	na, nr = max(1, int(a * SR)), max(1, int(r * SR))
	e[:na] = np.linspace(0, 1, na)
	e[-nr:] *= np.linspace(1, 0, nr)
	return e


def biquad(x, kind, f, q=0.707, gain_db=0.0):
	"""RBJ cookbook biquad. kind: lp, hp, bp, peak."""
	w0 = 2 * math.pi * min(f, SR * 0.45) / SR
	cw, sw = math.cos(w0), math.sin(w0)
	alpha = sw / (2 * q)
	if kind == "lp":
		b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "hp":
		b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "bp":
		b = [alpha, 0, -alpha]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	else:  # peak
		A = 10 ** (gain_db / 40)
		b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
		a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
	b0, b1, b2 = (v / a[0] for v in b)
	a1, a2 = a[1] / a[0], a[2] / a[0]
	y = [0.0] * len(x)
	x1 = x2 = y1 = y2 = 0.0
	for i, xi in enumerate(x.tolist()):
		yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2, x1, y2, y1 = x1, xi, y1, yi
		y[i] = yi
	return np.array(y)


def sweep_bp(x, f_start, f_end, q=2.0):
	"""Time-varying band-pass (state-variable filter) sweeping f_start -> f_end."""
	n = len(x)
	fs = np.geomspace(f_start, f_end, n)
	low = band = 0.0
	out = np.empty(n)
	damp = 1.0 / q
	xs = x.tolist()
	for i in range(n):
		f = 2 * math.sin(math.pi * fs[i] / SR)
		low += f * band
		high = xs[i] - low - damp * band
		band += f * high
		out[i] = band
	return out


def sine_drop(dur, f0, f1, tau):
	t = t_axis(dur)
	f = f1 + (f0 - f1) * np.exp(-t / (dur * 0.25))
	ph = 2 * math.pi * np.cumsum(f) / SR
	return np.sin(ph) * env_exp(len(t), tau)


def noise(dur, rng):
	return rng.uniform(-1, 1, int(dur * SR))


def pad(x, dur):
	n = int(dur * SR)
	if len(x) >= n:
		return x[:n]
	return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
	n = max(len(p) for p in parts)
	out = np.zeros(n)
	for p in parts:
		out[: len(p)] += p
	return out


def at(x, offset, total):
	out = np.zeros(int(total * SR))
	o = int(offset * SR)
	seg = x[: max(0, len(out) - o)]
	out[o : o + len(seg)] += seg
	return out


def soft_clip(x, drive=1.0):
	return np.tanh(x * drive) / math.tanh(drive)


def write(rel, x, peak=0.89):
	x = np.asarray(x, dtype=np.float64)
	x = x - np.mean(x)
	m = np.max(np.abs(x)) or 1.0
	x = x / m * peak
	fade = min(len(x), int(0.004 * SR))
	x[-fade:] *= np.linspace(1, 0, fade)
	data = (x * 32767).astype("<i2").tobytes()
	path = os.path.join(ROOT, rel)
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with wave.open(path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(data)
	print("wrote", rel, "%.2fs" % (len(x) / SR))


# --------------------------------------------------------------------------- impacts
def body_thud(rng, f0=120, dur=0.28, weight=1.0):
	body = sine_drop(dur, f0 * 1.6, f0 * 0.7, 0.05 * weight)
	n = noise(dur, rng) * env_exp(int(dur * SR), 0.018 * weight)
	n = biquad(n, "lp", 900)
	return body * 1.0 + n * 1.4


def slap(rng, bright=2500, dur=0.06):
	s = noise(dur, rng) * env_exp(int(dur * SR), 0.006)
	return biquad(biquad(biquad(s, "hp", 600), "peak", bright, 1.2, 6), "lp", 4500)


def knuckle_click(rng):
	c = noise(0.02, rng) * env_exp(int(0.02 * SR), 0.0015)
	return biquad(c, "bp", rng.uniform(1800, 3200), 4)


def punch(rng, face=False):
	dur = 0.32
	x = mix(body_thud(rng, rng.uniform(95, 140), dur), slap(rng, rng.uniform(1500, 2600)) * (0.9 if face else 0.45))
	if face:
		x = mix(x, at(knuckle_click(rng) * 1.2, 0.002, dur))
	return soft_clip(x, 2.0)


def kick(rng):
	dur = 0.4
	x = mix(body_thud(rng, rng.uniform(65, 90), dur, 1.6) * 1.3, slap(rng, rng.uniform(900, 1500)) * 0.5)
	whump = biquad(noise(dur, rng) * env_exp(int(dur * SR), 0.05), "lp", 300)
	return soft_clip(mix(x, whump * 1.5), 2.5)


def bone_crack(rng, dur=0.08, clicks=6):
	out = np.zeros(int(dur * SR))
	for _ in range(clicks):
		c = knuckle_click(rng) * rng.uniform(0.4, 1.0)
		o = int(rng.uniform(0, dur * 0.6) * SR)
		seg = c[: len(out) - o]
		out[o : o + len(seg)] += seg
	ring = biquad(noise(dur, rng) * env_exp(int(dur * SR), 0.01), "bp", rng.uniform(900, 1400), 8)
	return out + ring * 2.0


def headbutt(rng):
	dur = 0.4
	knock = sine_drop(0.25, rng.uniform(380, 520), rng.uniform(180, 240), 0.03)
	x = mix(at(bone_crack(rng, 0.05, 4) * 1.6, 0, dur), knock * 0.9, body_thud(rng, rng.uniform(85, 110), dur) * 0.9)
	return soft_clip(x, 2.5)


def nose_crunch(rng):
	dur = 0.45
	crunch = bone_crack(rng, 0.12, 14) * 1.4
	squelch = noise(0.25, rng) * env_exp(int(0.25 * SR), 0.06)
	squelch = sweep_bp(squelch, rng.uniform(1600, 2200), rng.uniform(300, 500), 3.0)
	x = mix(punch(rng, True) * 0.9, at(crunch, 0.005, dur), at(squelch * 3, 0.03, dur))
	return soft_clip(x, 2.0)


def body_fall(rng):
	dur = 0.7
	thump = body_thud(rng, rng.uniform(55, 75), 0.5, 2.2) * 1.4
	second = body_thud(rng, rng.uniform(80, 100), 0.3, 1.0) * 0.6
	scuff = biquad(noise(0.35, rng), "bp", 1200, 0.8) * np.linspace(0.4, 0, int(0.35 * SR))
	return soft_clip(mix(thump, at(second, rng.uniform(0.09, 0.16), dur), at(scuff * 0.5, 0.05, dur)), 1.8)


def glass_smash(rng):
	dur = 1.1
	t = t_axis(dur)
	out = np.zeros(len(t))
	for _ in range(60):
		f = rng.uniform(2500, 9000)
		start = rng.exponential(0.08)
		tau = rng.uniform(0.03, 0.25)
		tt = np.clip(t - start, 0, None)
		out += np.where(t >= start, np.sin(2 * math.pi * f * tt) * np.exp(-tt / tau), 0) * rng.uniform(0.2, 1.0)
	burst = biquad(noise(dur, rng) * env_exp(len(t), 0.03), "hp", 2000) * 6
	thunk = sine_drop(0.15, 300, 150, 0.02) * 2
	return mix(out * 0.25, burst, thunk)


def glass_clink(rng):
	dur = 0.5
	t = t_axis(dur)
	out = np.zeros(len(t))
	base = rng.uniform(1800, 2600)
	for k in (1, 2.71, 5.4):
		out += np.sin(2 * math.pi * base * k * t) * np.exp(-t / rng.uniform(0.08, 0.2)) / k
	return mix(out, punch(rng) * 0.8)


def wood_break(rng):
	dur = 0.8
	cracks = bone_crack(rng, 0.25, 22) * 1.2
	cracks = biquad(cracks, "lp", 3500)
	body = mix(*(sine_drop(0.5, f, f * 0.9, rng.uniform(0.04, 0.12)) * rng.uniform(0.3, 0.8) for f in rng.uniform(150, 700, 5)))
	clatter = np.zeros(int(dur * SR))
	for _ in range(5):
		c = sine_drop(0.12, rng.uniform(400, 900), 300, 0.02)
		clatter = mix(clatter, at(c * 0.4, rng.uniform(0.2, 0.6), dur))
	return soft_clip(mix(cracks, body, clatter), 1.5)


def wood_hit(rng):
	dur = 0.4
	knock = mix(*(sine_drop(0.3, f, f * 0.95, rng.uniform(0.02, 0.06)) for f in rng.uniform(250, 900, 4)))
	return soft_clip(mix(knock * 0.8, body_thud(rng, rng.uniform(90, 120), dur) * 0.9, slap(rng, 1500) * 0.4), 2.0)


def whoosh(rng):
	dur = rng.uniform(0.22, 0.32)
	n = noise(dur, rng)
	n = sweep_bp(n, rng.uniform(300, 500), rng.uniform(1600, 2400), 1.5)
	e = np.sin(np.linspace(0, math.pi, len(n))) ** 2
	return n * e


def splat(rng):
	dur = 0.35
	n = noise(dur, rng)
	e = np.zeros(len(n))
	for _ in range(5):
		o = int(rng.uniform(0, 0.15) * SR)
		e[o:] += env_exp(len(n) - o, rng.uniform(0.01, 0.04)) * rng.uniform(0.3, 1)
	return biquad(n * e, "lp", rng.uniform(700, 1200), 2.0)


def grab(rng):
	dur = 0.45
	n = noise(dur, rng)
	e = np.zeros(len(n))
	for _ in range(4):
		o = int(rng.uniform(0, 0.25) * SR)
		e[o:] += env_exp(len(n) - o, 0.04) * rng.uniform(0.4, 1)
	cloth = biquad(biquad(n * e, "hp", 800), "lp", 5000)
	return mix(cloth, body_thud(rng, 110, 0.2) * 0.5)


def gulp(rng):
	dur = 0.7
	out = np.zeros(int(dur * SR))
	for i in range(3):
		g = sine_drop(0.12, rng.uniform(500, 700), rng.uniform(180, 260), 0.03)
		g += biquad(noise(0.12, rng) * env_exp(int(0.12 * SR), 0.02), "bp", 400, 3) * 0.6
		out = mix(out, at(g, 0.05 + i * rng.uniform(0.18, 0.24), dur))
	return out


def munch(rng):
	dur = 0.8
	out = np.zeros(int(dur * SR))
	for i in range(4):
		c = biquad(noise(0.09, rng) * env_exp(int(0.09 * SR), 0.025), "bp", rng.uniform(1500, 3000), 1.0)
		c = mix(c, bone_crack(rng, 0.04, 3) * 0.3)
		out = mix(out, at(c, i * 0.19 + rng.uniform(0, 0.03), dur))
	return out


def whistle(rng):
	dur = 1.6
	t = t_axis(dur)
	trill = 1 + 0.06 * np.sign(np.sin(2 * math.pi * rng.uniform(22, 28) * t))
	f = 2900 * trill
	ph = 2 * math.pi * np.cumsum(f) / SR
	tone = np.sin(ph) + 0.25 * np.sin(2 * ph)
	breath = biquad(noise(dur, rng), "bp", 2900, 3) * 0.4
	e = adsr(len(t), 0.02, 0.15)
	e[int(0.55 * SR) : int(0.7 * SR)] *= 0.05  # two blasts
	return (tone + breath) * e


def door_bang(rng):
	dur = 0.9
	bang = mix(body_thud(rng, 70, 0.6, 2.5) * 1.5, *(sine_drop(0.5, f, f, 0.1) * 0.3 for f in (180, 260, 410)))
	creak = sweep_bp(noise(0.5, rng) * 0.6, 300, 900, 12) * adsr(int(0.5 * SR), 0.05, 0.1)
	return soft_clip(mix(creak * 3, at(bang, 0.35, dur)), 1.5)


# --------------------------------------------------------------------------- voice
VOWELS = {
	"uh": (640, 1190, 2390),
	"oo": (330, 870, 2240),
	"oh": (470, 820, 2600),
	"ah": (740, 1100, 2450),
	"er": (500, 1350, 1700),
	"eh": (560, 1700, 2500),
	"mm": (280, 1000, 2200),
}


def voice(rng, dur, f0_curve, vowels, breath=0.25, rough=0.0, female=False, amp_curve=None, vibrato=0.0):
	"""Tiny source-filter voice: a jittered glottal pulse train through three formant resonators."""
	n = int(dur * SR)
	t = np.arange(n) / SR
	f0 = np.interp(t, np.linspace(0, dur, len(f0_curve)), f0_curve)
	if female:
		f0 = f0 * 1.75
	f0 = f0 * (1 + vibrato * np.sin(2 * math.pi * 5.5 * t)) * (1 + 0.012 * rng.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1)))
	ph = np.cumsum(f0) / SR
	frac = ph % 1.0
	src = (1 - 2 * frac) * (frac < 0.6) + 0.0  # crude glottal pulse
	if rough:
		src *= 1 + rough * rng.uniform(-1, 1, n)  # creak / strain
	asp = rng.uniform(-1, 1, n) * breath
	src = src * (1 - breath) + asp
	# formants interpolated through the vowel list
	idx = np.linspace(0, len(vowels) - 1, n)
	out = np.zeros(n)
	scale = 1.17 if female else 1.0
	for k, (gain, bw) in enumerate(((1.0, 80), (0.6, 100), (0.3, 140))):
		fk = np.interp(idx, range(len(vowels)), [VOWELS[v][k] * scale for v in vowels])
		# piecewise-constant per 256-sample block keeps the python loop cheap enough
		y = np.zeros(n)
		y1 = y2 = 0.0
		xs = src.tolist()
		for start in range(0, n, 256):
			f = fk[start]
			r = math.exp(-math.pi * bw / SR)
			c1, c2 = 2 * r * math.cos(2 * math.pi * f / SR), -r * r
			g = 1 - r
			for i in range(start, min(n, start + 256)):
				yi = g * xs[i] + c1 * y1 + c2 * y2
				y2, y1 = y1, yi
				y[i] = yi
		out += y * gain
	if amp_curve is None:
		amp_curve = [0, 1, 0.8, 0]
	amp = np.interp(t, np.linspace(0, dur, len(amp_curve)), amp_curve)
	return biquad(out * amp, "hp", 70)


def oof(rng, female=False):
	dur = rng.uniform(0.25, 0.4)
	p = rng.uniform(110, 150)
	v = [rng.choice(["uh", "oo", "oh"]), "oo"]
	return voice(rng, dur, [p * 1.25, p, p * 0.8], v, breath=0.35, rough=0.3, female=female, amp_curve=[0, 1, 0.6, 0])


def grunt(rng, female=False):
	dur = rng.uniform(0.18, 0.28)
	p = rng.uniform(100, 130)
	v = [rng.choice(["ah", "uh", "eh"])] * 2
	return voice(rng, dur, [p, p * 1.1, p * 0.9], v, breath=0.45, rough=0.5, female=female, amp_curve=[0, 1, 0.7, 0])


def groan(rng, female=False):
	dur = rng.uniform(0.8, 1.3)
	p = rng.uniform(95, 120)
	v = ["uh", "er", "oh", "mm"] if rng.random() < 0.5 else ["oh", "uh", "uh"]
	return voice(rng, dur, [p * 1.2, p * 1.1, p * 0.9, p * 0.75], v, breath=0.3, rough=0.25, female=female,
		amp_curve=[0, 0.9, 1, 0.7, 0.4, 0], vibrato=0.01)


def moan(rng, female=False):
	dur = rng.uniform(1.4, 2.3)
	p = rng.uniform(85, 105)
	v = ["mm", "oh", "oo", "oh", "mm"]
	return voice(rng, dur, [p, p * 1.12, p * 1.05, p * 0.95, p * 0.8], v, breath=0.5, rough=0.15, female=female,
		amp_curve=[0, 0.5, 0.8, 0.7, 0.6, 0.3, 0], vibrato=0.025)


def ko(rng, female=False):
	dur = rng.uniform(0.7, 1.0)
	p = rng.uniform(120, 150)
	v = ["ah", "uh", "er", "mm"]
	return voice(rng, dur, [p * 1.3, p, p * 0.7, p * 0.55], v, breath=0.4, rough=0.45, female=female,
		amp_curve=[0, 1, 0.8, 0.4, 0])


def ahh(rng, female=False):
	dur = rng.uniform(0.7, 1.0)
	p = rng.uniform(105, 125)
	return voice(rng, dur, [p * 1.15, p * 1.05, p * 0.85], ["ah", "ah", "ah"], breath=0.55, female=female,
		amp_curve=[0, 1, 0.6, 0])


# --------------------------------------------------------------------------- main
def batch(folder, name, fn, count, seed, **kw):
	for i in range(count):
		rng = np.random.default_rng(seed * 100 + i)
		write("%s/%s_%02d.wav" % (folder, name, i + 1), fn(rng, **kw))


def main():
	batch("sfx", "punch_body", punch, 4, 1)
	batch("sfx", "punch_face", punch, 4, 2, face=True)
	batch("sfx", "kick", kick, 4, 3)
	batch("sfx", "headbutt", headbutt, 3, 4)
	batch("sfx", "nose_crunch", nose_crunch, 3, 5)
	batch("sfx", "body_fall", body_fall, 3, 6)
	batch("sfx", "glass_smash", glass_smash, 3, 7)
	batch("sfx", "glass_clink", glass_clink, 3, 8)
	batch("sfx", "wood_break", wood_break, 3, 9)
	batch("sfx", "wood_hit", wood_hit, 3, 10)
	batch("sfx", "whoosh", whoosh, 4, 11)
	batch("sfx", "blood_splat", splat, 3, 12)
	batch("sfx", "grab", grab, 3, 13)
	batch("sfx", "gulp", gulp, 2, 14)
	batch("sfx", "munch", munch, 2, 15)
	batch("sfx", "police_whistle", whistle, 1, 16)
	batch("sfx", "door_bang", door_bang, 2, 17)
	for female, tag in ((False, "m"), (True, "f")):
		s = 50 if female else 20
		batch("voice", "oof_" + tag, oof, 6 if not female else 4, s + 1, female=female)
		batch("voice", "grunt_" + tag, grunt, 4 if not female else 3, s + 2, female=female)
		batch("voice", "groan_" + tag, groan, 4 if not female else 2, s + 3, female=female)
		batch("voice", "moan_" + tag, moan, 4 if not female else 2, s + 4, female=female)
		batch("voice", "ko_" + tag, ko, 3 if not female else 2, s + 5, female=female)
		batch("voice", "ahh_" + tag, ahh, 2, s + 6, female=female)


if __name__ == "__main__":
	main()
