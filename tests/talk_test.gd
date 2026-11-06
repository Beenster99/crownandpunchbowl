extends SceneTree
## Headless tests for push-to-talk and punters answering back (scripts/talk, Talk autoload).
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/talk_test.gd


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var script: GDScript = load("res://tests/talk_cases.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var cases: Node = script.new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
