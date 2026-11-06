#!/usr/bin/env python3
"""Download the speech tools the game runs on the player's PC (no cloud, no account):

  speech/whisper/   whisper.cpp (MIT) + the base.en model: push-to-talk speech to text
  speech/piper/     Piper (MIT, uses espeak-ng, GPLv3) text to speech
  speech/voices/    en_GB VCTK voice for Piper (CC BY 4.0): every punter's voice

The folder sits next to CrownAndPunchbowl.exe in a build, and in the project root when
running from the editor. It is git-ignored: run this before exporting a build.

  python3 tools/fetch_speech.py                     # Windows tools into ./speech
  python3 tools/fetch_speech.py --platform linux --dest /tmp/speech   # for headless testing

On Linux there is no prebuilt whisper.cpp, so --platform linux builds it from source
(needs git, cmake and a C++ compiler).
"""
import argparse
import os
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
PIPER = "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/"
WHISPER_TAG = "v1.8.2"
WHISPER = "https://github.com/ggml-org/whisper.cpp/releases/download/%s/whisper-bin-x64.zip" % WHISPER_TAG
WHISPER_MODEL = "ggml-base.en-q5_1.bin"
WHISPER_MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + WHISPER_MODEL
VOICE = "en_GB-vctk-medium"
VOICE_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/vctk/medium/"

LICENCES = """Speech tools bundled with Crown and Punchbowl

whisper/   whisper.cpp %s, MIT licence. https://github.com/ggml-org/whisper.cpp
           Model %s: OpenAI Whisper weights, MIT licence.
piper/     Piper 2023.11.14-2, MIT licence. https://github.com/rhasspy/piper
           Includes espeak-ng (GPL v3), source at https://github.com/espeak-ng/espeak-ng
           and onnxruntime (MIT).
voices/    %s: trained on the CSTR VCTK corpus, CC BY 4.0.
           https://huggingface.co/rhasspy/piper-voices

These run as separate programs on your PC. Nothing you say leaves your computer unless
"Punters answer back" is on, in which case the words (not the audio) go to Claude.
""" % (WHISPER_TAG, WHISPER_MODEL, VOICE)


def fetch(url, path):
	if os.path.exists(path) and os.path.getsize(path) > 0:
		return path
	print("download", url)
	tmp = path + ".part"
	urllib.request.urlretrieve(url, tmp)
	os.replace(tmp, path)
	return path


def piper(dest, platform, cache):
	out = os.path.join(dest, "piper")
	exe = os.path.join(out, "piper.exe" if platform == "windows" else "piper")
	if os.path.exists(exe):
		return
	name = "piper_windows_amd64.zip" if platform == "windows" else "piper_linux_x86_64.tar.gz"
	archive = fetch(PIPER + name, os.path.join(cache, name))
	tmp = tempfile.mkdtemp(dir=cache)
	if name.endswith(".zip"):
		zipfile.ZipFile(archive).extractall(tmp)
	else:
		with tarfile.open(archive) as t:
			t.extractall(tmp)
	shutil.rmtree(out, ignore_errors=True)
	shutil.move(os.path.join(tmp, "piper"), out)
	shutil.rmtree(tmp, ignore_errors=True)


def whisper(dest, platform, cache):
	out = os.path.join(dest, "whisper")
	os.makedirs(out, exist_ok=True)
	if platform == "windows":
		if not os.path.exists(os.path.join(out, "whisper-cli.exe")):
			archive = fetch(WHISPER, os.path.join(cache, "whisper-bin-x64-%s.zip" % WHISPER_TAG))
			with zipfile.ZipFile(archive) as z:
				for info in z.infolist():
					base = os.path.basename(info.filename)
					# Just the command-line transcriber and the libraries it loads.
					if base == "whisper-cli.exe" or base.endswith(".dll"):
						with z.open(info) as src, open(os.path.join(out, base), "wb") as dst:
							shutil.copyfileobj(src, dst)
	elif not os.path.exists(os.path.join(out, "whisper-cli")):
		src = os.path.join(cache, "whisper.cpp")
		if not os.path.exists(src):
			subprocess.run(["git", "clone", "--depth", "1", "--branch", WHISPER_TAG,
				"https://github.com/ggml-org/whisper.cpp", src], check=True)
		build = os.path.join(src, "build")
		subprocess.run(["cmake", "-B", build, "-S", src, "-DCMAKE_BUILD_TYPE=Release",
			"-DBUILD_SHARED_LIBS=OFF", "-DWHISPER_BUILD_TESTS=OFF"], check=True)
		subprocess.run(["cmake", "--build", build, "-j", str(os.cpu_count() or 2),
			"--target", "whisper-cli"], check=True)
		shutil.copy(os.path.join(build, "bin", "whisper-cli"), os.path.join(out, "whisper-cli"))
	fetch(WHISPER_MODEL_URL, os.path.join(out, WHISPER_MODEL))


def voices(dest):
	out = os.path.join(dest, "voices")
	os.makedirs(out, exist_ok=True)
	for ext in ("onnx", "onnx.json"):
		fetch(VOICE_URL + "%s.%s" % (VOICE, ext), os.path.join(out, "%s.%s" % (VOICE, ext)))


def main():
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--platform", choices=["windows", "linux"], default="windows")
	ap.add_argument("--dest", default=os.path.join(ROOT, "speech"))
	ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "cp_speech_cache"))
	args = ap.parse_args()
	os.makedirs(args.dest, exist_ok=True)
	os.makedirs(args.cache, exist_ok=True)
	piper(args.dest, args.platform, args.cache)
	whisper(args.dest, args.platform, args.cache)
	voices(args.dest)
	# Godot shouldn't try to import any of this as game assets.
	open(os.path.join(args.dest, ".gdignore"), "w").close()
	with open(os.path.join(args.dest, "LICENCES.txt"), "w") as f:
		f.write(LICENCES)
	print("speech tools ready in", args.dest)


if __name__ == "__main__":
	main()
