extends PubLevel
## The Crown and Punchbowl, 17th century. One big low-beamed room: inglenook on the
## left, bar along the back, darts and pool on the right, front door by the pool table.


func _init() -> void:
	pub_id = "crown_and_punchbowl"
	era = "17th"
	room = Rect2(-9, -6, 18, 12)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-9.3, -6.3, 18.6, 12.6))
	# Back wall: cellar door behind the bar and a small leaded window.
	b.wall_x(-6, -9.15, 9.15, [
		{"c": -6.5, "w": 1.2, "sill": 1.0, "top": 2.0, "kind": "window"},
		{"c": 5.6, "w": 1.0, "top": 2.0, "kind": "door"},
	])
	# Front wall: the way in, and leaded windows onto the village green.
	b.wall_x(6, -9.15, 9.15, [
		{"c": -5.5, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": -1.0, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": 2.6, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": 6.2, "w": 1.4, "top": 2.1, "kind": "door"},
	])
	b.wall_z(-9, -5.85, 5.85, [{"c": 4.0, "w": 1.0, "sill": 1.0, "top": 2.0, "kind": "window"}])
	b.wall_z(9, -5.85, 5.85, [{"c": 3.0, "w": 1.0, "sill": 1.0, "top": 2.0, "kind": "window"}])

	# Bar along the back with the shelves behind it.
	b.bar_counter(Rect2(-3.0, -4.4, 7.0, 0.8), Vector3.FORWARD)
	b.back_bar(Vector3(0.5, 0, -5.6), 6.0, Vector3.BACK)
	b.prop("stool", Vector3(-2.4, 0, -3.0))
	b.prop("stool", Vector3(3.4, 0, -3.0))

	b.fireplace(Vector3(-8.85, 0, -0.5), Vector3.RIGHT, "inglenook")
	b.dartboard(Vector3(8.85, 1.73, -2.5), Vector3.LEFT)
	b.pool_table(Vector3(5.0, 0, 1.6))

	b.table_set(Vector3(-5.4, 0, -3.2), 4, "chair")
	b.table_set(Vector3(-4.8, 0, 3.4), 4, "chair")
	b.table_set(Vector3(-1.0, 0, 3.5), 3, "stool", 1)
	b.table_set(Vector3(1.8, 0, -0.2), 2, "stool", 2)

	# Low oak beams and the posts holding them up.
	for z in [-3.0, 0.0, 3.0]:
		b.beam_x(z, -9.0, 9.0)
	b.post(-2.4, 0.0)
	b.post(3.0, -1.4)

	# Candle light.
	b.lamp(Vector3(-8.75, 1.9, -4.0), Vector3.RIGHT)
	b.lamp(Vector3(-8.75, 1.9, 2.4), Vector3.RIGHT)
	b.lamp(Vector3(8.75, 1.9, 0.6), Vector3.LEFT)
	b.lamp(Vector3(-3.0, 1.9, -5.75), Vector3.BACK)
	b.lamp(Vector3(-5.4, 0.78, -3.2))
	b.lamp(Vector3(-4.8, 0.78, 3.4))
	b.lamp(Vector3(-1.0, 0.78, 3.5))
	b.window_light(Vector3(-1.0, 1.5, 6.0), Vector3.FORWARD, Color("7d93b8"), 0.9)

	b.door(Vector3(6.2, 0, 7.6), Vector3(6.2, 0, 4.6))
	for i in 4:
		b.marker(PLAYERS, Vector3(4.2 + i * 1.0, 0, 4.5 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-0.6, 0, 1.2), Vector3(0.2, 0, 1.6), Vector3(7.0, 0, -0.2)]:
		b.marker(PUNTER, p, {"pose": "standing"})
