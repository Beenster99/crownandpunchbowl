extends PubLevel
## The King William, 18th century. Georgian: tall sash windows, painted panelled
## walls, brass and chandeliers. Two rooms joined by a wide arch: the saloon (left,
## fireplace and pool) and the tap room (right, the bar and darts).


func _init() -> void:
	pub_id = "king_william"
	era = "18th"
	room = Rect2(-10, -6, 20, 12)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-10.3, -6.3, 20.6, 12.6))
	var sash := func(c: float) -> Dictionary:
		return {"c": c, "w": 1.3, "sill": 0.8, "top": 2.6, "kind": "window"}
	b.wall_x(-6, -10.15, 10.15, [sash.call(-7.5), sash.call(-4.5), sash.call(0.6)])
	b.wall_x(6, -10.15, 10.15, [
		sash.call(-8.4), {"c": -6.0, "w": 1.4, "top": 2.3, "kind": "door"}, sash.call(-3.6),
		sash.call(1.4), sash.call(4.4), {"c": 7.2, "w": 1.4, "top": 2.3, "kind": "door"},
	])
	b.wall_z(-10, -5.85, 5.85, [sash.call(3.6)])
	b.wall_z(10, -5.85, 5.85)
	# Panelled partition with a wide arch between the rooms.
	b.wall_z(-2, -5.85, 5.85, [{"c": 0.8, "w": 3.6, "top": 2.6, "kind": "arch"}])

	# Saloon.
	b.fireplace(Vector3(-9.85, 0, -1.6), Vector3.RIGHT, "mantel")
	b.pool_table(Vector3(-6.0, 0, 2.4))
	b.table_set(Vector3(-7.6, 0, -3.6), 4, "chair")
	b.table_set(Vector3(-4.4, 0, -3.6), 4, "chair")
	b.settle(Vector3(-3.0, 0, 4.4), Vector3.LEFT, 2.0)
	b.chandelier(Vector3(-6.0, 2.5, -0.6))

	# Tap room: bar against the right-hand end of the back wall, brass foot rail.
	b.bar_counter(Rect2(3.6, -3.4, 6.4, 0.8), Vector3.FORWARD, true)
	b.back_bar(Vector3(6.8, 0, -5.6), 5.6, Vector3.BACK)
	b.prop("stool", Vector3(4.6, 0, -2.0))
	b.prop("stool", Vector3(8.6, 0, -2.0))
	b.dartboard(Vector3(-1.85, 1.73, -3.8), Vector3.RIGHT)
	b.table_set(Vector3(1.6, 0, 3.4), 4, "chair")
	b.table_set(Vector3(5.2, 0, 3.6), 4, "chair")
	b.table_set(Vector3(8.4, 0, 1.0), 2, "stool", 1)
	b.table_set(Vector3(2.6, 0, -1.0), 2, "stool", 2)
	b.chandelier(Vector3(4.0, 2.5, 0.4))

	# Brass sconces.
	b.lamp(Vector3(-6.0, 2.0, -5.75), Vector3.BACK)
	b.lamp(Vector3(-9.75, 2.0, 1.0), Vector3.RIGHT)
	b.lamp(Vector3(-2.25, 2.0, -3.6), Vector3.LEFT)
	b.lamp(Vector3(-1.75, 2.0, 4.2), Vector3.RIGHT)
	b.lamp(Vector3(9.75, 2.0, 1.8), Vector3.LEFT)
	b.lamp(Vector3(2.4, 2.0, -5.75), Vector3.BACK)
	for x in [-8.4, -3.6, 1.4, 4.4]:
		b.window_light(Vector3(x, 1.7, 6.0), Vector3.FORWARD, Color("e0a46a"), 0.6)

	b.door(Vector3(7.2, 0, 7.6), Vector3(7.2, 0, 4.6))
	b.door(Vector3(-6.0, 0, 7.6), Vector3(-6.0, 0, 4.6), false)
	for i in 4:
		b.marker(PLAYERS, Vector3(5.6 + i * 0.9, 0, 4.4 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(0.6, 0, 0.8), Vector3(-0.2, 0, 1.4), Vector3(-5.2, 0, 0.2), Vector3(6.5, 0, 0.6)]:
		b.marker(PUNTER, p, {"pose": "standing"})
