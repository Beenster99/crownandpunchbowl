extends PubLevel
## The Farmers Dog, 19th century. Victorian: an island bar with a carved mirrored
## gantry, encaustic tiles, gas lamps, and etched glass screens splitting the public
## bar (left, pool and darts) from the saloon (right, fireside tables).


func _init() -> void:
	pub_id = "farmers_dog"
	era = "19th"
	room = Rect2(-11, -6.5, 22, 13)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-11.3, -6.8, 22.6, 13.6), 2.4)
	var big := func(c: float) -> Dictionary:
		return {"c": c, "w": 1.8, "sill": 0.9, "top": 2.8, "kind": "window"}
	b.wall_x(-6.5, -11.15, 11.15)
	b.wall_x(6.5, -11.15, 11.15, [
		big.call(-9.0), {"c": -6.0, "w": 1.5, "top": 2.5, "kind": "door"}, big.call(-3.0),
		big.call(3.0), {"c": 6.0, "w": 1.5, "top": 2.5, "kind": "door"}, big.call(9.0),
	])
	b.wall_z(-11, -6.35, 6.35, [big.call(2.5)])
	b.wall_z(11, -6.35, 6.35, [big.call(3.5)])

	# Island bar: a U of counters round the staff, gantry against the back wall.
	b.bar_counter(Rect2(-2.5, -1.6, 5.0, 0.8), Vector3.FORWARD, true)
	b.bar_counter(Rect2(-2.5, -4.6, 0.8, 3.0), Vector3.RIGHT, true)
	b.bar_counter(Rect2(1.7, -4.6, 0.8, 3.0), Vector3.LEFT, true)
	b.back_bar(Vector3(0, 0, -6.1), 4.2, Vector3.BACK, true)
	for x in [-1.6, 0.0, 1.6]:
		b.prop("stool", Vector3(x, 0, -0.2))

	# Etched glass screen between the two bars.
	b.glass_screen(Vector3(0, 0, -0.7), Vector3(0, 0, 2.6))

	# Public bar.
	b.fireplace(Vector3(-7.0, 0, -6.35), Vector3.BACK, "range")
	b.dartboard(Vector3(-10.85, 1.73, -2.6), Vector3.RIGHT)
	b.pool_table(Vector3(-6.4, 0, 2.6))
	b.table_set(Vector3(-4.2, 0, -3.4), 3, "stool", 2)
	b.table_set(Vector3(-2.6, 0, 4.4), 2, "stool", 1)

	# Saloon.
	b.fireplace(Vector3(10.85, 0, -1.2), Vector3.LEFT, "mantel")
	b.table_set(Vector3(4.6, 0, 3.6), 4, "chair")
	b.table_set(Vector3(8.2, 0, 3.8), 4, "chair")
	b.table_set(Vector3(5.6, 0, -3.6), 4, "chair")
	b.settle(Vector3(4.0, 0, -6.0), Vector3.BACK, 2.4)
	b.settle(Vector3(8.6, 0, -6.0), Vector3.BACK, 1.6)

	# Gas lamps: pendants over the rooms and brackets on the walls.
	for p in [Vector3(-7.0, 2.7, -1.0), Vector3(-3.5, 2.7, 2.6), Vector3(0.0, 2.8, -3.0),
			Vector3(4.0, 2.7, 0.6), Vector3(8.0, 2.7, 1.0)]:
		b.lamp(p)
	b.lamp(Vector3(-10.75, 2.1, 0.0), Vector3.RIGHT)
	b.lamp(Vector3(10.75, 2.1, 2.0), Vector3.LEFT)
	b.lamp(Vector3(-4.0, 2.1, -6.25), Vector3.BACK)
	for x in [-9.0, -3.0, 3.0, 9.0]:
		b.window_light(Vector3(x, 1.8, 6.5), Vector3.FORWARD, Color("8fa6c4"), 0.7)

	b.door(Vector3(-6.0, 0, 8.1), Vector3(-6.0, 0, 5.1))
	b.door(Vector3(6.0, 0, 8.1), Vector3(6.0, 0, 5.1))
	for i in 4:
		b.marker(PLAYERS, Vector3(-7.4 + i * 0.95, 0, 5.0 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-8.6, 0, -0.4), Vector3(-1.4, 0, 1.6), Vector3(1.6, 0, 1.6), Vector3(6.8, 0, 0.2), Vector3(7.4, 0, 0.8)]:
		b.marker(PUNTER, p, {"pose": "standing"})
