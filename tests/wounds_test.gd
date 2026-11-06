extends SceneTree
## Headless tests for localised damage (bruises, swelling, cuts).
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/wounds_test.gd


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var script: GDScript = load("res://tests/wounds_cases.gd")
	if script == null or not script.can_instantiate():
		push_error("wounds_cases.gd failed to load")
		quit(1)
		return
	var cases: Node = script.new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
