class_name DartsRules
extends RefCounted
## Dartboard geometry and scoring. Pure functions, no nodes, so tests and the host
## agree exactly.
##
## Board coordinates are millimetres from the bull, x to the right and y DOWN (screen
## convention), as you look at the board. 20 is straight up. Radii are the regulation
## ones (WDF / PDC): bull 12.7 mm across, outer bull 31.8 mm, treble ring 99-107 mm,
## double ring 162-170 mm, board 451 mm across.

## Numbers clockwise from the top.
const ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
const R_BULL := 6.35
const R_OUTER_BULL := 15.9
const R_TREBLE_IN := 99.0
const R_TREBLE_OUT := 107.0
const R_DOUBLE_IN := 162.0
const R_DOUBLE_OUT := 170.0
## Edge of the board (the black number ring). Darts past this miss the board.
const R_BOARD := 225.5
## Doubles players like to finish on, best first. Used to pick checkout routes.
const PREFERRED_DOUBLES := [20, 16, 8, 18, 12, 10, 4, 2, 1, 14, 6, 9, 3, 5, 7, 11, 13, 15, 17, 19]


## What a dart at `p` (mm) scores: {number, mult, score, label, double}.
## number is 25 for the bulls and 0 for a miss; double is true for a double or the bull.
static func score_at(p: Vector2) -> Dictionary:
	var r := p.length()
	if r <= R_BULL:
		return _hit(25, 2)
	if r <= R_OUTER_BULL:
		return _hit(25, 1)
	if r > R_DOUBLE_OUT:
		return _hit(0, 0)
	var number := number_at_angle(p)
	var mult := 1
	if r >= R_TREBLE_IN and r <= R_TREBLE_OUT:
		mult = 3
	elif r >= R_DOUBLE_IN:
		mult = 2
	return _hit(number, mult)


## The segment number under the angle of `p` (ignores distance).
static func number_at_angle(p: Vector2) -> int:
	var deg := rad_to_deg(atan2(p.y, p.x)) + 90.0 + 9.0
	var idx := int(fposmod(deg, 360.0) / 18.0) % 20
	return ORDER[idx]


## Centre angle (radians, screen coordinates) of a segment.
static func segment_angle(number: int) -> float:
	var idx := ORDER.find(number)
	return deg_to_rad(-90.0 + idx * 18.0)


## The middle of a bed, for bots and tests: (20, 3) is the middle of treble 20,
## (25, 2) the bull, (n, 1) the fat single between the bull and the treble.
static func target_point(number: int, mult: int) -> Vector2:
	if number == 25:
		return Vector2.ZERO if mult == 2 else Vector2(0, -(R_BULL + R_OUTER_BULL) * 0.5)
	var r := 0.0
	match mult:
		3: r = (R_TREBLE_IN + R_TREBLE_OUT) * 0.5
		2: r = (R_DOUBLE_IN + R_DOUBLE_OUT) * 0.5
		_: r = (R_OUTER_BULL + R_TREBLE_IN) * 0.5
	var a := segment_angle(number)
	return Vector2(cos(a), sin(a)) * r


static func label(number: int, mult: int) -> String:
	if number == 0:
		return "Miss"
	if number == 25:
		return "Bull" if mult == 2 else "25"
	return ["", "", "D", "T"][mult] + str(number)


static func _hit(number: int, mult: int) -> Dictionary:
	return {"number": number, "mult": mult, "score": number * mult, "label": label(number, mult),
		"double": mult == 2}


## Every scoring dart as [label, score, double], biggest setup shots first.
static func all_darts() -> Array:
	var out := []
	for n in range(20, 0, -1):
		out.append([label(n, 3), n * 3, false])
	out.append(["25", 25, false])
	for n in range(20, 0, -1):
		out.append([label(n, 1), n, false])
	out.append(["Bull", 50, true])
	for n in range(20, 0, -1):
		out.append([label(n, 2), n * 2, true])
	return out


## Darts finishing `remaining` exactly in at most `darts_left` darts (labels), or [] when
## there is no checkout. With double_out the last dart must be a double or the bull.
## Prefers fewer darts, then a favourite double, then big setup shots.
static func checkout(remaining: int, darts_left: int, double_out := true) -> Array:
	if remaining <= 0 or darts_left <= 0 or remaining > 180:
		return []
	var darts := all_darts()
	var finishers := []
	for d in darts:
		if d[2] or not double_out:
			finishers.append(d)
	for n in range(1, darts_left + 1):
		var best := []
		var best_rank := INF
		for route in _routes(remaining, n, darts, finishers):
			var rank := _finish_rank(route[route.size() - 1])
			if rank < best_rank:
				best_rank = rank
				best = route
		if not best.is_empty():
			var labels := []
			for d in best:
				labels.append(d[0])
			return labels
	return []


static func _routes(remaining: int, n: int, darts: Array, finishers: Array) -> Array:
	var out := []
	if n == 1:
		for f in finishers:
			if f[1] == remaining:
				out.append([f])
		return out
	for d in darts:
		var left: int = remaining - int(d[1])
		if left < 2 and finishers.size() < darts.size() or left < 1:
			continue
		for rest in _routes(left, n - 1, darts, finishers):
			out.append([d] + rest)
		if out.size() > 40:
			break
	return out


static func _finish_rank(d: Array) -> float:
	var lbl: String = d[0]
	if lbl == "Bull":
		return 30.0
	if lbl.begins_with("D"):
		var i := PREFERRED_DOUBLES.find(int(lbl.substr(1)))
		return float(i)
	# Straight out: biggest finishing dart first, a plain single before a treble of the same.
	return 50.0 + float(60 - int(d[1])) + (0.5 if lbl.begins_with("T") else 0.0)
