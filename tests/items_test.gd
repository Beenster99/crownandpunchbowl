extends SceneTree
## Headless tests for weapons, throwing, drinking, food and the bar.
## Run: godot --headless --path . --script res://tests/items_test.gd


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var cases: Node = load("res://tests/items_cases.gd").new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
