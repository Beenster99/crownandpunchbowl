extends PubLevel
## The Pillock Tickle, 17th century. Cramped, ramshackle and on three levels. The tap
## room (left) has the bar on the side wall, barrels, and an old hay loft over the back
## with no railing at all, up a steep flight of stairs. Through a low doorway, the
## lounge (right) has the inglenook up on a raised hearth platform, pool and darts.
## A back door opens onto the beer garden.

const LOFT_TOP := 2.4
const HEARTH_TOP := 0.7


func _init() -> void:
	pub_id = "pillock_tickle"
	era = "17th"
	room = Rect2(-12.5, -7, 24, 14)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-12.8, -7.3, 24.6, 14.6))
	var leaded := func(c: float) -> Dictionary:
		return {"c": c, "w": 1.0, "sill": 1.0, "top": 1.9, "kind": "window"}
	var tall := LOFT_TOP + 2.2
	b.wall_x(-7.0, -12.65, -5.5, [], tall)
	b.wall_x(-7.0, -5.5, 11.65, [{"c": 5.0, "w": 1.1, "top": 2.0, "kind": "door"}])
	b.wall_x(7.0, -12.65, 11.65, [
		leaded.call(-10.0), {"c": -6.5, "w": 1.3, "top": 2.0, "kind": "door"}, leaded.call(-3.0),
		leaded.call(2.0), leaded.call(7.5),
	])
	b.wall_z(-12.5, -6.85, -3.5, [], tall)
	b.wall_z(-12.5, -3.5, 6.85)
	b.wall_z(11.5, -6.85, 2.0, [], HEARTH_TOP + 2.7)
	b.wall_z(11.5, 2.0, 6.85)
	b.wall_z(-1.0, -6.85, 6.85, [{"c": 1.5, "w": 3.0, "top": 2.0, "kind": "arch"}])

	# Hay loft: open edge, nothing to stop you going over.
	b.platform(Rect2(-12.5, -7.0, 7.0, 3.5), LOFT_TOP, ["front", "right"], ["right"],
		[{"side": "right", "c": -6.25, "w": 1.5}])
	b.stairs(Vector3(-1.9, 0, -6.25), Vector3.LEFT, 3.6, LOFT_TOP)
	b.barrel(Vector3(-11.6, LOFT_TOP, -6.2))
	b.barrel(Vector3(-10.7, LOFT_TOP, -6.3))
	b.solid(Vector3(1.6, 0.6, 1.0), Vector3(-8.0, LOFT_TOP + 0.3, -6.3), b.material(Color("c9a64a")))  # hay bales
	b.solid(Vector3(1.0, 0.6, 1.6), Vector3(-6.6, LOFT_TOP + 0.3, -5.6), b.material(Color("bf9c42")))
	b.table_set(Vector3(-9.0, LOFT_TOP, -4.6), 2, "stool", 1)
	b.marker(PUNTER, Vector3(-7.0, LOFT_TOP, -4.2), {"pose": "standing"})

	# Tap room: bar along the left wall, barrels in the front corner.
	b.bar_counter(Rect2(-10.9, -2.5, 0.8, 5.5), Vector3.LEFT)
	b.back_bar(Vector3(-12.1, 0, 0.25), 5.0, Vector3.RIGHT)
	b.barrel(Vector3(-11.7, 0, 5.0))
	b.barrel(Vector3(-11.7, 0, 6.1))
	b.barrel(Vector3(-10.4, 0, 6.3), true)
	b.prop("stool", Vector3(-9.4, 0, -1.6))
	b.prop("stool", Vector3(-9.4, 0, 2.0))
	b.table_set(Vector3(-6.0, 0, -0.4), 4, "stool")
	b.table_set(Vector3(-5.6, 0, 4.4), 4, "chair")
	b.table_set(Vector3(-9.0, 0, -5.8), 2, "stool", 1)
	b.post(-3.4, 1.8)
	b.lamp(Vector3(-12.4, 1.8, 3.8), Vector3.RIGHT)
	b.lamp(Vector3(-1.15, 1.8, -2.6), Vector3.LEFT)
	b.lamp(Vector3(-6.0, 0.78, -0.4))
	b.lamp(Vector3(-5.6, 0.78, 4.4))

	# Lounge: raised hearth platform with the inglenook, darts on the back wall, pool.
	b.platform(Rect2(7.0, -7.0, 4.5, 9.0), HEARTH_TOP, ["left", "front"])
	b.stairs(Vector3(5.8, 0, -1.0), Vector3.RIGHT, 1.2, HEARTH_TOP, 1.8)
	b.fireplace(Vector3(11.35, HEARTH_TOP, -3.0), Vector3.LEFT, "inglenook", HEARTH_TOP + 2.7)
	b.settle(Vector3(8.2, HEARTH_TOP, -5.6), Vector3.BACK, 1.6)
	b.table_set(Vector3(8.6, HEARTH_TOP, 0.4), 2, "stool", 2)
	b.marker(PUNTER, Vector3(8.0, HEARTH_TOP, -1.6), {"pose": "standing"})
	b.dartboard(Vector3(1.8, 1.73, -6.85), Vector3.BACK)
	b.pool_table(Vector3(3.2, 0, 3.6))
	b.table_set(Vector3(8.6, 0, 4.8), 4, "chair")
	b.table_set(Vector3(3.6, 0, -1.6), 2, "stool", 2)
	b.lamp(Vector3(-0.85, 1.8, 4.8), Vector3.RIGHT)
	b.lamp(Vector3(11.35, 1.8, 4.4), Vector3.LEFT)
	b.lamp(Vector3(8.6, 0.78, 4.8))

	b.beam_x(0.6, -12.5, 7.0)
	b.beam_x(4.0, -12.5, 11.5)
	b.beam_z(4.0, -7.0, 7.0, 2.5)
	b.window_light(Vector3(2.0, 1.4, 7.0), Vector3.FORWARD, Color("7d93b8"), 0.8)

	b.door(Vector3(-6.5, 0, 8.6), Vector3(-6.5, 0, 5.6))
	b.door(Vector3(5.0, 0, -8.6), Vector3(5.0, 0, -5.6), false)
	for i in 4:
		b.marker(PLAYERS, Vector3(-8.0 + i * 0.9, 0, 5.6 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-8.4, 0, 0.6), Vector3(-3.0, 0, 0.0), Vector3(1.8, 0, 0.6), Vector3(5.0, 0, -4.0)]:
		b.marker(PUNTER, p, {"pose": "standing"})
