class_name Ledges
extends RefCounted
## Finds the drop-off edges of galleries, lofts and daises so throws can send people over.
##
## A ledge is a Node3D with metadata `normal` (outward Vector3), `drop` (height in metres)
## and `railing` (bool; false = open edge or a gap in the rail). Pubs put them under
## `Markers/Ledges` in the current scene (see docs/PUBS.md). Any other node in the
## "ledges" group counts too, which is how tests and custom levels add them.

const GROUP := &"ledges"


static func all(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if tree == null:
		return out
	if tree.current_scene != null:
		var parent := tree.current_scene.get_node_or_null("Markers/Ledges")
		if parent != null:
			for c in parent.get_children():
				if c is Node3D:
					out.append(c)
	for n in tree.get_nodes_in_group(GROUP):
		if n is Node3D and not out.has(n):
			out.append(n)
	return out


## The best ledge to throw someone over: within `max_dist` (flat) of `pos`, at about the
## same height (they're standing on that level), and facing roughly along `dir`.
## Returns null if there isn't one.
static func for_throw(tree: SceneTree, pos: Vector3, dir: Vector3,
		max_dist := Moves.LEDGE_THROW_RANGE) -> Node3D:
	var aim := Vector3(dir.x, 0.0, dir.z).normalized()
	var best: Node3D = null
	var best_score := INF
	for l in all(tree):
		var n := normal_of(l)
		if n == Vector3.ZERO or absf(l.global_position.y - pos.y) > 0.6:
			continue
		var to := l.global_position - pos
		to.y = 0.0
		var d := to.length()
		if d > max_dist:
			continue
		var facing := aim.dot(n)
		if facing < 0.35:
			continue
		var score := d - facing
		if score < best_score:
			best_score = score
			best = l
	return best


static func normal_of(ledge: Node3D) -> Vector3:
	var n: Vector3 = ledge.get_meta("normal", Vector3.ZERO)
	n.y = 0.0
	return n.normalized()


static func has_railing(ledge: Node3D) -> bool:
	return bool(ledge.get_meta("railing", false))
