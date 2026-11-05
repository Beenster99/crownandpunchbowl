extends SceneTree
## Headless test for CoopRules: a standing mate holding interact revives a downed mate,
## and a full wipe fires Events.all_players_down. Uses stand-in fighters so it doesn't
## depend on the combat workstream.
## Run: godot --headless --path . --script res://tests/coop_rules_test.gd

const FAKE_FIGHTER := """
extends Node3D
var max_hp := 100.0
var hp := 100.0
var downed := false
func is_down() -> bool:
	return downed
func revive(fraction: float) -> void:
	downed = false
	hp = max_hp * fraction
"""


func _initialize() -> void:
	await process_frame
	root.get_node("Net").start_solo("Test", 0)
	var script := GDScript.new()
	script.source_code = FAKE_FIGHTER
	script.reload()
	var level := Node3D.new()
	level.name = "Level"
	root.add_child(level)
	var rules: Node = load("res://scripts/net/coop_rules.gd").new()  # class names compile before autoloads
	rules.name = "CoopRules"
	rules.revive_time = 0.5
	rules.wipe_restart_delay = 60.0  # don't actually reload during the test
	level.add_child(rules)
	var a := _fighter(script, level, "P1", Vector3.ZERO)
	var b := _fighter(script, level, "P2", Vector3(1.0, 0, 0))
	b.downed = true

	var revived := [false]
	rules.player_revived.connect(func(d, _r): revived[0] = d == b)
	rules._holding[1] = true  # both stand-ins are owned by peer 1 in solo
	await create_timer(1.0).timeout
	if not revived[0] or b.downed or absf(b.hp - 35.0) > 0.01:
		return _done(false, "revive didn't happen (downed=%s hp=%s)" % [b.downed, b.hp])

	b.position = Vector3(5, 0, 0)
	b.downed = true
	await create_timer(1.0).timeout
	if not b.downed:
		return _done(false, "revived from too far away")

	var wiped := [false]
	root.get_node("Events").all_players_down.connect(func(): wiped[0] = true)
	a.downed = true
	await create_timer(0.3).timeout
	if not wiped[0]:
		return _done(false, "wipe not detected")
	_done(true, "")


func _fighter(script: GDScript, parent: Node, n: String, pos: Vector3) -> Node3D:
	var f := Node3D.new()
	f.set_script(script)
	f.name = n
	f.position = pos
	f.add_to_group("players")
	parent.add_child(f)
	return f


func _done(ok: bool, msg: String) -> void:
	if not ok:
		push_error(msg)
	print("COOP RULES %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
