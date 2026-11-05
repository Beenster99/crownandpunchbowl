extends PubLevel
## The King William, 18th century. Georgian, two rooms joined by a wide arch.
## Saloon (left): a railed upper gallery along the back, stairs up the left wall,
## pool and a chandelier. Tap room (right): long brass-railed bar, fireplace and a
## raised dais by the windows with a step down on two sides.

const GALLERY_TOP := 3.0
const DAIS_TOP := 0.6


func _init() -> void:
	pub_id = "king_william"
	era = "18th"
	room = Rect2(-12.5, -7.5, 25, 15)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-12.8, -7.8, 25.6, 15.6))
	var tall := GALLERY_TOP + 2.8
	var sash := func(c: float, sill := 0.8, top := 2.6) -> Dictionary:
		return {"c": c, "w": 1.3, "sill": sill, "top": top, "kind": "window"}
	b.wall_x(-7.5, -12.65, -2.5, [sash.call(-9.5, GALLERY_TOP + 0.8, GALLERY_TOP + 2.4), sash.call(-5.5, GALLERY_TOP + 0.8, GALLERY_TOP + 2.4)], tall)
	b.wall_x(-7.5, -2.5, 12.65, [sash.call(1.5)])
	b.wall_x(7.5, -12.65, 12.65, [
		sash.call(-10.5), {"c": -7.5, "w": 1.4, "top": 2.3, "kind": "door"}, sash.call(-4.5),
		sash.call(1.0), {"c": 4.5, "w": 1.4, "top": 2.3, "kind": "door"}, sash.call(10.5, 1.2, 2.8),
	])
	b.wall_z(-12.5, -7.35, -4.0, [], tall)
	b.wall_z(-12.5, -4.0, 7.35, [sash.call(4.5)])
	b.wall_z(12.5, -7.35, 7.35)
	b.wall_z(-2.5, -7.35, 7.35, [{"c": 1.2, "w": 4.0, "top": 2.6, "kind": "arch"}], GALLERY_TOP + 0.2)

	# Saloon gallery with a gap at the stairs and one over the pool table.
	b.platform(Rect2(-12.5, -7.5, 10.0, 3.5), GALLERY_TOP, ["front"], ["front"],
		[{"side": "front", "c": -11.75, "w": 1.5}, {"side": "front", "c": -6.5, "w": 1.6}])
	b.stairs(Vector3(-11.75, 0, 1.6), Vector3.FORWARD, 5.6, GALLERY_TOP)
	b.table_set(Vector3(-9.0, GALLERY_TOP, -6.0), 3, "chair")
	b.table_set(Vector3(-4.6, GALLERY_TOP, -6.0), 2, "stool", 1)
	b.lamp(Vector3(-7.0, GALLERY_TOP + 1.9, -7.35), Vector3.BACK)
	b.marker(PUNTER, Vector3(-7.0, GALLERY_TOP, -4.9), {"pose": "standing"})
	b.table_set(Vector3(-8.0, 0, -6.0), 2, "stool", 2)
	b.pool_table(Vector3(-7.0, 0, 2.8))
	b.table_set(Vector3(-5.0, 0, -1.6), 4, "chair")
	b.settle(Vector3(-3.4, 0, 5.4), Vector3.LEFT, 2.0)
	b.chandelier(Vector3(-7.0, 2.4, 0.4))

	# Tap room.
	b.bar_counter(Rect2(4.0, -5.6, 8.5, 0.8), Vector3.FORWARD, true)
	b.back_bar(Vector3(8.2, 0, -7.1), 7.0, Vector3.BACK)
	b.prop("stool", Vector3(5.2, 0, -4.2))
	b.prop("stool", Vector3(10.8, 0, -4.2))
	b.dartboard(Vector3(-2.35, 1.73, -4.8), Vector3.RIGHT)
	b.fireplace(Vector3(12.35, 0, -1.2), Vector3.LEFT, "mantel")
	b.table_set(Vector3(1.6, 0, 4.6), 4, "chair")
	b.table_set(Vector3(5.0, 0, 1.0), 4, "chair")
	b.table_set(Vector3(2.0, 0, -2.2), 2, "stool", 2)
	b.chandelier(Vector3(4.5, 2.5, -1.0))

	# Raised dais by the front windows.
	b.platform(Rect2(8.0, 2.5, 4.5, 5.0), DAIS_TOP, ["left", "back"])
	b.stairs(Vector3(7.0, 0, 5.0), Vector3.RIGHT, 1.0, DAIS_TOP, 1.6)
	b.table_set(Vector3(10.4, DAIS_TOP, 4.8), 4, "chair")
	b.marker(PUNTER, Vector3(9.0, DAIS_TOP, 3.2), {"pose": "standing"})

	b.lamp(Vector3(-12.4, 2.0, 2.0), Vector3.RIGHT)
	b.lamp(Vector3(-2.75, 2.0, -3.0), Vector3.LEFT)
	b.lamp(Vector3(-2.25, 2.0, 5.0), Vector3.RIGHT)
	b.lamp(Vector3(12.4, 2.0, 2.2), Vector3.LEFT)
	b.lamp(Vector3(-0.5, 2.0, -7.25), Vector3.BACK)
	for x in [-10.5, -4.5, 1.0, 10.5]:
		b.window_light(Vector3(x, 1.7, 7.5), Vector3.FORWARD, Color("e0a46a"), 0.6)

	b.door(Vector3(4.5, 0, 9.1), Vector3(4.5, 0, 6.0))
	b.door(Vector3(-7.5, 0, 9.1), Vector3(-7.5, 0, 6.0), false)
	for i in 4:
		b.marker(PLAYERS, Vector3(3.0 + i * 0.9, 0, 6.0 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(0.4, 0, 1.0), Vector3(-0.4, 0, 1.6), Vector3(-9.0, 0, -1.0), Vector3(7.5, 0, -2.0)]:
		b.marker(PUNTER, p, {"pose": "standing"})
