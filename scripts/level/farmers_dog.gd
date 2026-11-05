extends PubLevel
## The Farmers Dog, 19th century. Victorian: an island bar with a carved mirrored
## gantry, encaustic tiles and gas lamps. A cast-iron balcony runs the whole back
## wall above the bar, with stairs at both ends. An etched glass screen splits the
## public bar (left: pool, darts, iron range) from the saloon (right: fireside tables).

const BALCONY_TOP := 3.3


func _init() -> void:
	pub_id = "farmers_dog"
	era = "19th"
	room = Rect2(-13.5, -8, 27, 16)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-13.8, -8.3, 27.6, 16.6), 2.4)
	var tall := BALCONY_TOP + 2.8
	var big := func(c: float) -> Dictionary:
		return {"c": c, "w": 1.8, "sill": 0.9, "top": 2.8, "kind": "window"}
	b.wall_x(-8.0, -13.65, 13.65, [
		{"c": -6.0, "w": 1.6, "sill": BALCONY_TOP + 0.9, "top": BALCONY_TOP + 2.3, "kind": "window"},
		{"c": 6.0, "w": 1.6, "sill": BALCONY_TOP + 0.9, "top": BALCONY_TOP + 2.3, "kind": "window"},
	], tall)
	b.wall_x(8.0, -13.65, 13.65, [
		big.call(-11.0), {"c": -7.0, "w": 1.5, "top": 2.5, "kind": "door"}, big.call(-3.0),
		big.call(3.0), {"c": 7.0, "w": 1.5, "top": 2.5, "kind": "door"}, big.call(11.0),
	])
	b.wall_z(-13.5, -7.85, -5.5, [], tall)
	b.wall_z(-13.5, -5.5, 7.85, [big.call(5.5)])
	b.wall_z(13.5, -7.85, -5.5, [], tall)
	b.wall_z(13.5, -5.5, 7.85, [big.call(5.5)])

	# Iron balcony along the back, stairs up both side walls.
	b.platform(Rect2(-13.5, -8.0, 27.0, 2.5), BALCONY_TOP, ["front"], ["front"],
		[{"side": "front", "c": -12.75, "w": 1.5}, {"side": "front", "c": 12.75, "w": 1.5},
		{"side": "front", "c": -8.0, "w": 1.6}, {"side": "front", "c": 8.0, "w": 1.6}], true)
	b.stairs(Vector3(-12.75, 0, 0.3), Vector3.FORWARD, 5.8, BALCONY_TOP)
	b.stairs(Vector3(12.75, 0, 0.3), Vector3.FORWARD, 5.8, BALCONY_TOP)
	b.table_set(Vector3(-10.0, BALCONY_TOP, -7.0), 2, "stool", 1)
	b.table_set(Vector3(10.0, BALCONY_TOP, -7.0), 2, "chair", 1)
	b.lamp(Vector3(-3.0, BALCONY_TOP + 2.0, -7.85), Vector3.BACK)
	b.lamp(Vector3(3.0, BALCONY_TOP + 2.0, -7.85), Vector3.BACK)
	for x in [-5.0, 4.0]:
		b.marker(PUNTER, Vector3(x, BALCONY_TOP, -6.4), {"pose": "standing"})

	# Island bar: a U of counters round the staff, gantry against the back wall.
	b.bar_counter(Rect2(-2.8, -2.4, 5.6, 0.8), Vector3.FORWARD, true)
	b.bar_counter(Rect2(-2.8, -5.4, 0.8, 3.0), Vector3.RIGHT, true)
	b.bar_counter(Rect2(2.0, -5.4, 0.8, 3.0), Vector3.LEFT, true)
	b.back_bar(Vector3(0, 0, -7.6), 4.6, Vector3.BACK, true)
	for x in [-1.8, 0.0, 1.8]:
		b.prop("stool", Vector3(x, 0, -1.0))
	b.glass_screen(Vector3(0, 0, -1.4), Vector3(0, 0, 3.4))

	# Public bar.
	b.fireplace(Vector3(-8.0, 0, -7.85), Vector3.BACK, "range", BALCONY_TOP - 0.3)
	b.dartboard(Vector3(-13.35, 1.73, 3.6), Vector3.RIGHT)
	b.pool_table(Vector3(-7.0, 0, 3.6))
	b.table_set(Vector3(-5.0, 0, -3.4), 3, "stool", 2)
	b.table_set(Vector3(-9.0, 0, -0.6), 2, "stool", 1)
	b.table_set(Vector3(-3.2, 0, 6.0), 2, "stool", 1)

	# Saloon.
	b.fireplace(Vector3(13.35, 0, 2.6), Vector3.LEFT, "mantel")
	b.table_set(Vector3(5.0, 0, 5.4), 4, "chair")
	b.table_set(Vector3(9.4, 0, 5.6), 4, "chair")
	b.table_set(Vector3(6.0, 0, -3.4), 4, "chair")
	b.table_set(Vector3(9.6, 0, -0.4), 2, "chair", 1)
	b.settle(Vector3(4.0, 0, 1.0), Vector3.RIGHT, 2.0)

	for p in [Vector3(-8.0, 2.8, -1.8), Vector3(-4.0, 2.8, 3.4), Vector3(0.0, 2.9, -4.0),
			Vector3(4.5, 2.8, 2.0), Vector3(9.0, 2.8, 2.4)]:
		b.lamp(p)
	b.lamp(Vector3(-13.25, 2.1, 0.6), Vector3.RIGHT)
	b.lamp(Vector3(13.25, 2.1, -1.0), Vector3.LEFT)
	for x in [-11.0, -3.0, 3.0, 11.0]:
		b.window_light(Vector3(x, 1.8, 8.0), Vector3.FORWARD, Color("8fa6c4"), 0.7)

	b.door(Vector3(-7.0, 0, 9.6), Vector3(-7.0, 0, 6.5))
	b.door(Vector3(7.0, 0, 9.6), Vector3(7.0, 0, 6.5))
	for i in 4:
		b.marker(PLAYERS, Vector3(-8.4 + i * 0.95, 0, 6.4 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-10.0, 0, 1.6), Vector3(-1.4, 0, 2.0), Vector3(1.6, 0, 2.0), Vector3(7.0, 0, 1.2), Vector3(7.6, 0, 1.8)]:
		b.marker(PUNTER, p, {"pose": "standing"})
