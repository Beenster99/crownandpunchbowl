extends SceneTree
## Headless tests for darts: board scoring, checkouts, 501/301 rules (busts, double out,
## legs) and a solo game at a real pub board (chalk up at the oche, controls locked, throw,
## step away when a fight starts).
## Run: godot --headless --path . --script res://tests/darts_test.gd


func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var cases: Node = load("res://tests/darts_cases.gd").new()
	root.add_child(cases)
	cases.run()
	var failures: int = await cases.finished
	quit(1 if failures > 0 else 0)
