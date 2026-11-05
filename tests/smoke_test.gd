extends SceneTree
## Headless smoke test: loads the autoloads and the test pub, steps a few frames.
## Run: godot --headless --path . --script res://tests/smoke_test.gd
## (Autoloads are reached via root.get_node() because SceneTree scripts compile first.)

func _initialize() -> void:
	await process_frame  # let autoloads enter the tree
	var net := root.get_node("Net")
	net.start_solo("Smoke", 0)
	net.start_game()  # solo goes through the same RPC path as co-op
	await create_timer(1.0).timeout
	var players := get_nodes_in_group("players")
	if players.size() != 1:
		push_error("expected 1 player, got %d" % players.size())
		quit(1)
		return
	print("SMOKE OK: %s loaded with %d player(s)" % [current_scene.name, players.size()])
	quit(0)
