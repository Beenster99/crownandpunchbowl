extends SceneTree
## Headless AI tests: punter moods, attack tokens, gang-ups, waves, staff and police.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/ai_test.gd
## (--fixed-fps runs the simulation as fast as possible instead of in real time.)


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var script: GDScript = load("res://tests/ai_cases.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var cases: Node = script.new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
