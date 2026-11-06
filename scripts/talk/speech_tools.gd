class_name SpeechTools
extends RefCounted
## Where the on-PC speech programs live (fetched by tools/fetch_speech.py):
##   <game folder>/speech/whisper/whisper-cli(.exe) + ggml-base.en-q5_1.bin   listening
##   <game folder>/speech/piper/piper(.exe)                                   speaking
##   <game folder>/speech/voices/en_GB-vctk-medium.onnx(.json)                the voices
## <game folder> is the folder holding the .exe in a build, or the project folder in the
## editor. The CP_SPEECH_DIR environment variable overrides it (handy for testing).

const WHISPER_MODEL := "ggml-base.en-q5_1.bin"
const VOICE_MODEL := "en_GB-vctk-medium.onnx"


static func root() -> String:
	var env := OS.get_environment("CP_SPEECH_DIR")
	if env != "":
		return env
	if OS.has_feature("editor") or not OS.has_feature("template"):
		return ProjectSettings.globalize_path("res://speech")
	return OS.get_executable_path().get_base_dir().path_join("speech")


static func _exe(name: String) -> String:
	return name + ".exe" if OS.get_name() == "Windows" else name


static func whisper_exe() -> String:
	return root().path_join("whisper").path_join(_exe("whisper-cli"))


static func whisper_model() -> String:
	return root().path_join("whisper").path_join(WHISPER_MODEL)


static func piper_exe() -> String:
	return root().path_join("piper").path_join(_exe("piper"))


static func voice_model() -> String:
	return root().path_join("voices").path_join(VOICE_MODEL)


static func can_listen() -> bool:
	return FileAccess.file_exists(whisper_exe()) and FileAccess.file_exists(whisper_model())


static func can_speak() -> bool:
	return FileAccess.file_exists(piper_exe()) and FileAccess.file_exists(voice_model()) \
		and FileAccess.file_exists(voice_model() + ".json")


## VCTK speaker name ("p226") -> Piper speaker id, read from the voice's .json.
static func speaker_ids() -> Dictionary:
	var f := FileAccess.open(voice_model() + ".json", FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data.get("speaker_id_map", {}) if data is Dictionary else {}


## One line for the settings screen.
static func status() -> String:
	var bits := PackedStringArray()
	bits.append("Listening: " + ("ready" if can_listen() else "speech tools missing"))
	bits.append("Punter voices: " + ("ready" if can_speak() else "speech tools missing, using Windows voices"))
	return ". ".join(bits) + "."
