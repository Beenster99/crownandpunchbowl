extends SceneTree
## Headless combat tests.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/combat_test.gd
## (--fixed-fps runs physics as fast as possible instead of in real time.)


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var script: GDScript = load("res://tests/combat_cases.gd")
	if script == null or not script.can_instantiate():
		push_error("combat_cases.gd failed to load")
		quit(1)
		return
	var cases: Node = script.new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
