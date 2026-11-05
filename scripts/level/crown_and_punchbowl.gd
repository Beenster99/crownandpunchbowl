extends PubLevel
## The Crown and Punchbowl, 17th century. One big low-beamed room with a minstrels'
## gallery over the snug in the back-left corner, reached by stairs along the left
## wall. Bar along the back right, inglenook on the right, darts and pool at the front.

const GALLERY_TOP := 2.5


func _init() -> void:
	pub_id = "crown_and_punchbowl"
	era = "17th"
	room = Rect2(-11, -7.5, 22, 15)


func _build(b: PubBuilder) -> void:
	b.floor_area(Rect2(-11.3, -7.8, 22.6, 15.6))
	var tall := GALLERY_TOP + 2.5
	# Back wall: tall behind the gallery, with a window up there; cellar door behind the bar.
	b.wall_x(-7.5, -11.15, 1.0, [{"c": -5.0, "w": 1.2, "sill": GALLERY_TOP + 0.9, "top": GALLERY_TOP + 2.0, "kind": "window"}], tall)
	b.wall_x(-7.5, 1.0, 11.15, [{"c": 8.6, "w": 1.0, "top": 2.0, "kind": "door"}])
	b.wall_x(7.5, -11.15, 11.15, [
		{"c": -7.0, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": -2.5, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": 2.5, "w": 1.4, "sill": 0.9, "top": 2.0, "kind": "window"},
		{"c": 7.5, "w": 1.4, "top": 2.1, "kind": "door"},
	])
	b.wall_z(-11, -7.35, -4.5, [], tall)
	b.wall_z(-11, -4.5, 7.35, [{"c": 6.0, "w": 1.0, "sill": 1.0, "top": 2.0, "kind": "window"}])
	b.wall_z(11, -7.35, 7.35, [{"c": 5.0, "w": 1.0, "sill": 1.0, "top": 2.0, "kind": "window"}])

	# Minstrels' gallery: railed, with a gap in the rail for throwing people off.
	b.platform(Rect2(-11.0, -7.5, 12.0, 3.0), GALLERY_TOP, ["front", "right"], ["front", "right"],
		[{"side": "front", "c": -10.1, "w": 1.5}, {"side": "front", "c": -4.0, "w": 1.6}])
	b.stairs(Vector3(-10.1, 0, 0.5), Vector3.FORWARD, 5.0, GALLERY_TOP)
	b.table_set(Vector3(-7.0, GALLERY_TOP, -6.3), 3, "chair")
	b.table_set(Vector3(-2.2, GALLERY_TOP, -6.3), 2, "stool", 1)
	b.lamp(Vector3(-7.0, GALLERY_TOP + 0.78, -6.3))
	b.marker(PUNTER, Vector3(-5.0, GALLERY_TOP, -5.2), {"pose": "standing"})
	# The snug underneath.
	b.table_set(Vector3(-7.0, 0, -6.2), 2, "stool", 2)
	b.table_set(Vector3(-2.6, 0, -6.2), 2, "stool", 1)

	# Bar along the back right.
	b.bar_counter(Rect2(2.5, -5.8, 7.5, 0.8), Vector3.FORWARD)
	b.back_bar(Vector3(6.2, 0, -7.1), 6.5, Vector3.BACK)
	b.prop("stool", Vector3(3.6, 0, -4.4))
	b.prop("stool", Vector3(8.8, 0, -4.4))

	b.fireplace(Vector3(10.85, 0, 0.5), Vector3.LEFT, "inglenook")
	b.settle(Vector3(8.0, 0, 3.4), Vector3.FORWARD, 1.8)
	b.dartboard(Vector3(-10.85, 1.73, 4.2), Vector3.RIGHT)
	b.pool_table(Vector3(2.0, 0, 3.4))

	b.table_set(Vector3(-4.8, 0, 0.4), 4, "chair")
	b.table_set(Vector3(-5.0, 0, 5.2), 4, "chair")
	b.table_set(Vector3(6.0, 0, -1.6), 3, "stool", 2)
	b.table_set(Vector3(5.6, 0, 5.4), 2, "chair", 1)

	for z in [-1.5, 2.0, 5.0]:
		b.beam_x(z, -11.0, 11.0)
	b.post(-1.0, 1.5)
	b.post(3.0, -2.2)

	b.lamp(Vector3(-10.75, 1.9, -2.0), Vector3.RIGHT)
	b.lamp(Vector3(-10.75, GALLERY_TOP + 1.6, -6.0), Vector3.RIGHT)
	b.lamp(Vector3(10.75, 1.9, -3.5), Vector3.LEFT)
	b.lamp(Vector3(10.75, 1.9, 5.8), Vector3.LEFT)
	b.lamp(Vector3(4.0, 1.9, -7.25), Vector3.BACK)
	b.lamp(Vector3(-4.8, 0.78, 0.4))
	b.lamp(Vector3(-5.0, 0.78, 5.2))
	b.lamp(Vector3(5.6, 0.78, 5.4))
	b.window_light(Vector3(-2.5, 1.5, 7.5), Vector3.FORWARD, Color("7d93b8"), 0.9)

	b.door(Vector3(7.5, 0, 9.1), Vector3(7.5, 0, 6.0))
	for i in 4:
		b.marker(PLAYERS, Vector3(5.6 + i * 1.0, 0, 6.0 - (i % 2) * 0.6), {"facing": Vector3.FORWARD})
	for p in [Vector3(-1.4, 0, -0.4), Vector3(-0.6, 0, -1.0), Vector3(8.0, 0, -2.6), Vector3(-8.0, 0, 2.6)]:
		b.marker(PUNTER, p, {"pose": "standing"})
