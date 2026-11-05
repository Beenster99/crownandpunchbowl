extends SceneTree
## Prints every chatter line as "key<TAB>text" for assets/audio/tools/generate_voices.py.
## Run: godot --headless --path . --script res://tests/dump_chatter_lines.gd > /tmp/chatter.tsv


func _initialize() -> void:
	var lines: Script = load("res://scripts/ai/chatter_lines.gd")
	for k in lines.all_keys():
		print("%s\t%s" % [k, lines.text(k)])
	quit(0)
