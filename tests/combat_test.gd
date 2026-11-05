extends SceneTree
## Headless combat tests.
## Run: godot --headless --path . --script res://tests/combat_test.gd


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var cases: Node = load("res://tests/combat_cases.gd").new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
