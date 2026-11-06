extends SceneTree
## Headless tests for pub physics and ragdolls: props are physics bodies, glass smashes,
## hits barge furniture about, a body knocked into the bar goes over it, slams shake the
## shelf bottles loose, and knockdowns go ragdoll and blend back on get-up.
## Run: godot --headless --fixed-fps 60 --path . --script res://tests/physics_test.gd

func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var script: GDScript = load("res://tests/physics_cases.gd")
	if script == null or not script.can_instantiate():
		push_error("physics_cases.gd failed to load")
		quit(1)
		return
	var cases: Node = script.new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
