class_name Targeting
extends RefCounted
## Freeflow target selection. Given a fighter and a stick direction, pick the enemy the
## player most likely means: close, roughly in the direction pushed, and preferably someone
## who is about to hit them. With no stick input it sticks with the current target or
## whoever is straight in front; nobody off to the side.


## Best enemy to lunge at, or null. `dir` is a world-space XZ direction (any length).
static func pick(attacker: Fighter, dir: Vector3, max_range := Moves.LUNGE_RANGE,
		want_ground := false) -> Fighter:
	var origin := attacker.global_position
	var aim := Vector3(dir.x, 0.0, dir.z)
	var has_aim := aim.length() > 0.25
	if not has_aim:
		aim = attacker.get_facing()
	aim = aim.normalized()
	var best: Fighter = null
	var best_score := INF
	for node in attacker.get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == attacker or not attacker.can_hit(f) or not f.can_be_targeted():
			continue
		if want_ground != (f.state == Fighter.State.DOWN or f.state == Fighter.State.CRAWL):
			continue
		var to := f.global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist > max_range:
			continue
		var angle := 0.0 if dist < 0.01 else rad_to_deg(aim.angle_to(to / dist))
		# With a direction pushed, ignore anything well off to the side. With the stick
		# centred, only the man in front (or the one you're squared up to): a punch never
		# swings you round to someone at your shoulder.
		if has_aim and angle > 70.0:
			continue
		var engaged := f == attacker.target or f == attacker.stance_target
		if not has_aim and angle > (55.0 if engaged else 35.0):
			continue
		var score := dist + angle / (25.0 if has_aim else 45.0)
		if not attacker.is_hostile_to(f):
			score += 2.5  # friendly fire: only go for a mate when they're clearly who you mean
		if f == attacker.target:
			score -= 0.6  # stickiness so the camera of your attention doesn't flicker
		if f.state == Fighter.State.WINDUP and f.target == attacker:
			score -= 0.4  # someone about to hit you is a natural target
		if f.state == Fighter.State.HELD:
			score -= 0.3  # a mate is holding them for you
		if score < best_score:
			best_score = score
			best = f
	return best


## Enemies currently winding up a counterable attack on `defender`, nearest first.
static func incoming_attackers(defender: Fighter, max_range := Moves.COUNTER_RANGE) -> Array[Fighter]:
	var out: Array[Fighter] = []
	for node in defender.get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == defender or not f.is_counterable_by(defender):
			continue
		if f.global_position.distance_to(defender.global_position) <= max_range:
			out.append(f)
	out.sort_custom(func(a: Fighter, b: Fighter) -> bool:
		return a.global_position.distance_squared_to(defender.global_position) \
			< b.global_position.distance_squared_to(defender.global_position))
	return out


## Nearest grabbable enemy roughly in front, or null. With friendly fire on, a mate as a last resort.
static func grab_candidate(holder: Fighter, max_range := Moves.GRAB_RANGE) -> Fighter:
	var best: Fighter = null
	var best_d := INF
	var fwd := holder.get_facing()
	for node in holder.get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == holder or not holder.can_hit(f) or not f.can_be_grabbed():
			continue
		var to := f.global_position - holder.global_position
		to.y = 0.0
		var d := to.length()
		if d > max_range:
			continue
		if d > 0.05 and rad_to_deg(fwd.angle_to(to / d)) > 75.0:
			continue
		if not holder.is_hostile_to(f):
			d += 1.0  # friendly fire: an enemy in reach is grabbed before a mate
		if d < best_d:
			best_d = d
			best = f
	return best
