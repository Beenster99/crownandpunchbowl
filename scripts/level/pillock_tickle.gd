extends PubLevel
## The Pillock Tickle, 17th century. A cramped, ramshackle old place: a dark tap room
## (left) with the bar along the side wall and barrels stacked up, through a low
## doorway to the lounge (right) with the inglenook, pool table and darts. A back
## door opens onto the beer garden, so punters can come in from two sides.


func _init() -> void:
	pub_id = "pillock_tickle"
	era = "17th"
	room = Rect2(-10, -5.5, 19, 11)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-10.3, -5.8, 19.6, 11.6))
	var leaded := func(c: float) -> Dictionary:
		return {"c": c, "w": 1.0, "sill": 1.0, "top": 1.9, "kind": "window"}
	b.wall_x(-5.5, -10.15, 9.15, [leaded.call(-4.0), {"c": 6.4, "w": 1.1, "top": 2.0, "kind": "door"}])
	b.wall_x(5.5, -10.15, 9.15, [
		leaded.call(-8.0), {"c": -4.6, "w": 1.3, "top": 2.0, "kind": "door"}, leaded.call(-2.2),
		leaded.call(2.4), leaded.call(6.6),
	])
	b.wall_z(-10, -5.35, 5.35)
	b.wall_z(9, -5.35, 5.35)
	# Thick old wall between the rooms with one low doorway.
	b.wall_z(-1, -5.35, 5.35, [{"c": 1.0, "w": 2.8, "top": 2.0, "kind": "arch"}])

	# Tap room: bar along the left wall, barrels in the corner.
	b.bar_counter(Rect2(-8.4, -4.2, 0.8, 5.0), Vector3.LEFT)
	b.back_bar(Vector3(-9.6, 0, -1.7), 4.6, Vector3.RIGHT)
	b.barrel(Vector3(-9.2, 0, 3.0))
	b.barrel(Vector3(-9.2, 0, 4.2))
	b.barrel(Vector3(-8.2, 0, 4.6), true)
	b.prop("stool", Vector3(-6.9, 0, -3.2))
	b.prop("stool", Vector3(-6.9, 0, 0.2))
	b.table_set(Vector3(-4.0, 0, -2.8), 4, "stool")
	b.table_set(Vector3(-4.2, 0, 2.8), 4, "chair")
	b.post(-5.6, 0.0)
	b.lamp(Vector3(-9.65, 1.8, 1.6), Vector3.RIGHT)
	b.lamp(Vector3(-1.15, 1.8, -3.6), Vector3.LEFT)
	b.lamp(Vector3(-4.0, 0.78, -2.8))
	b.lamp(Vector3(-4.2, 0.78, 2.8))

	# Lounge: inglenook with a settle facing it, darts on the back wall, pool.
	b.fireplace(Vector3(8.85, 0, -1.0), Vector3.LEFT, "inglenook")
	b.settle(Vector3(5.4, 0, -1.0), Vector3.RIGHT, 2.0)
	b.dartboard(Vector3(2.4, 1.73, -5.35), Vector3.BACK)
	b.pool_table(Vector3(3.0, 0, 2.8))
	b.table_set(Vector3(6.6, 0, 3.4), 4, "chair")
	b.table_set(Vector3(0.6, 0, -0.8), 2, "stool", 2)
	b.lamp(Vector3(-0.85, 1.8, 3.8), Vector3.RIGHT)
	b.lamp(Vector3(8.85, 1.8, 3.0), Vector3.LEFT)
	b.lamp(Vector3(6.6, 0.78, 3.4))

	for z in [-2.6, 1.4]:
		b.beam_x(z, -10.0, 9.0)
	b.beam_z(4.0, -5.5, 5.5, 2.5)
	b.beam_z(-6.0, -5.5, 5.5, 2.5)
	b.window_light(Vector3(2.4, 1.4, 5.5), Vector3.FORWARD, Color("7d93b8"), 0.8)

	b.door(Vector3(-4.6, 0, 7.1), Vector3(-4.6, 0, 4.1))
	b.door(Vector3(6.4, 0, -7.1), Vector3(6.4, 0, -4.1), false)
	for i in 4:
		b.marker(PLAYERS, Vector3(-6.0 + i * 0.9, 0, 4.1 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-6.0, 0, -1.4), Vector3(-2.4, 0, 0.6), Vector3(1.8, 0, 0.9), Vector3(4.8, 0, -3.4)]:
		b.marker(PUNTER, p, {"pose": "standing"})
