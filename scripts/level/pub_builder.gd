class_name PubBuilder
extends RefCounted
## Greybox kit for building pubs in code: floors, walls with doors and windows,
## beams, the bar, fireplaces, dartboards, pool tables, lamps and gameplay markers.
## Every pub script (see PubLevel) calls these helpers from `_build()`.
##
## Coordinates: the room sits around the origin, -Z is the back wall (far from the
## camera) and +Z is the front wall (nearest the camera). Y is up. Sizes are metres.
## Walls, beams and anything else that can hide the fight are put in the
## `camera_occluders` group so OccluderFader can fade them.

const WALL_THICKNESS := 0.3
const DADO_HEIGHT := 1.05

var level: Node3D
var world: Node3D
var markers: Node3D
var style: Dictionary
## Lights that flicker (fire, candles, gas). PubLevel animates these.
var flicker_lights: Array[OmniLight3D] = []

var _materials := {}
var _glass_material: StandardMaterial3D
## Era colour (html) -> [PubMaterials texture set, repeats per metre, roughness multiplier].
var _textured := {}


func _init(p_level: Node3D, p_world: Node3D, p_markers: Node3D, p_style: Dictionary) -> void:
	level = p_level
	world = p_world
	markers = p_markers
	style = p_style
	var tex_scale := {"plaster": 0.45, "panelling": 0.9, "glazed_tile": 1.4, "wallpaper": 0.9}
	for key in ["trim", "timber", "bar", "furniture"]:
		_textured[(style[key] as Color).to_html()] = ["wood", 0.9, 1.0]
	_textured[(style["timber"] as Color).lightened(0.15).to_html()] = ["wood", 0.9, 1.0]
	_textured[(style["timber"] as Color).lightened(0.1).to_html()] = ["planks", 0.9, 1.0]
	_textured[(style["floor_a"] as Color).darkened(0.15).to_html()] = ["planks", 0.9, 1.0]
	_textured[(style["floor_b"] as Color).to_html()] = ["planks", 0.9, 1.0]
	_textured[(style["bar_top"] as Color).to_html()] = ["wood", 0.9, 0.55]
	var dado_set: String = style.get("dado_tex", "plaster")
	_textured[(style["dado"] as Color).to_html()] = [dado_set, tex_scale.get(dado_set, 0.6), 1.0]
	var wall_set: String = style.get("wall_tex", "plaster")
	_textured[(style["wall"] as Color).to_html()] = [wall_set, tex_scale.get(wall_set, 0.6), 1.0]
	_textured[Color("5a3024").to_html()] = ["brick", 1.0, 1.0]   # fireplaces
	_textured[Color("4a4440").to_html()] = ["stone", 0.8, 1.0]   # hearth stones


# --- Materials --------------------------------------------------------------

## Era colours come back as textured PubMaterials (wood grain on timber and the bar,
## plaster, panelling, glazed tiles or wallpaper on the walls, brick and stone round the
## fire, brushed metal on anything metallic). Other colours are plain.
func material(color: Color, metallic := 0.0, roughness := 0.85) -> Material:
	var key := "%s/%.2f/%.2f" % [color.to_html(), metallic, roughness]
	if not _materials.has(key):
		var tex: Array = _textured.get(color.to_html(), [])
		if metallic >= 0.5:
			_materials[key] = PubMaterials.surface("metal", color, 2.0, 1.3, metallic * 0.85)
		elif not tex.is_empty() and color.a >= 1.0:
			_materials[key] = PubMaterials.surface(tex[0], color, tex[1], tex[2])
		else:
			var m := StandardMaterial3D.new()
			m.albedo_color = color
			m.metallic = metallic
			m.roughness = roughness
			_materials[key] = m
	return _materials[key]


func emissive(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "emit/%s/%.2f" % [color.to_html(), energy]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_materials[key] = m
	return _materials[key]


func glass() -> StandardMaterial3D:
	if _glass_material == null:
		_glass_material = StandardMaterial3D.new()
		_glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_material.albedo_color = Color(0.75, 0.85, 0.8, 0.35)
		_glass_material.roughness = 0.15
		_glass_material.emission_enabled = true
		_glass_material.emission = Color("2b3b44")
		_glass_material.emission_energy_multiplier = 0.6
	return _glass_material


func _floor_texture(pattern: String, a: Color, b: Color) -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var grout := a.darkened(0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pattern)
	match pattern:
		"boards":
			# 8 planks per tile, staggered joints.
			var plank := size / 8
			for row in 8:
				var joint := (row * 37) % size
				var shade := a.lerp(b, rng.randf())
				for y in range(row * plank, (row + 1) * plank):
					for x in size:
						var c := shade
						if y == row * plank or x == joint:
							c = grout
						elif (x + y * 3) % 23 == 0:
							c = shade.darkened(0.08)
						img.set_pixel(x, y, c)
		"tiles":
			# Encaustic checker, 8x8 tiles per texture with thin grout.
			var tile := size / 8
			for y in size:
				for x in size:
					var c := a if ((x / tile) + (y / tile)) % 2 == 0 else b
					if x % tile == 0 or y % tile == 0:
						c = Color("3a3226")
					img.set_pixel(x, y, c)
		_:
			# Flagstones: rows of uneven slabs with offset joints.
			var rows := [0, 30, 66, 96, 128]
			for r in rows.size() - 1:
				var y0: int = rows[r]
				var y1: int = rows[r + 1]
				var cuts := [0]
				var x := (r * 41) % 50
				while x < size:
					cuts.append(x)
					x += rng.randi_range(34, 60)
				cuts.append(size)
				for s in cuts.size() - 1:
					var shade := a.lerp(b, rng.randf()).darkened(rng.randf_range(0.0, 0.12))
					for yy in range(y0, y1):
						for xx in range(cuts[s], cuts[s + 1]):
							var c := shade
							if yy - y0 < 2 or xx - cuts[s] < 2:
								c = grout
							img.set_pixel(xx, yy, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- Primitive helpers ------------------------------------------------------

## A visible box with no collision. Returns the MeshInstance3D.
func deco(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation_degrees.y = rot_y
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 16
	mesh.mesh = cyl
	mesh.position = pos
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 6
	mesh.mesh = s
	mesh.position = pos
	mesh.material_override = mat
	parent.add_child(mesh)
	return mesh


## A solid StaticBody3D box on the world layer.
## Pass `with_mesh = false` to dress it yourself (e.g. a table top and legs).
func solid(size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0, parent: Node3D = null, with_mesh := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot_y
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	(parent if parent else world).add_child(body)
	if with_mesh:
		deco(body, size, Vector3.ZERO, mat)
	return body


## A small loose cylinder (bottle, glass) as a physics prop under `parent` at local `pos`.
## `pinned` keeps it fixed (on a shelf) until PubPhysics.disturb() knocks it loose.
func loose_cylinder(parent: Node3D, prop_name: String, radius: float, height: float, pos: Vector3,
		mat: Material, mass := 0.5, fragile := true, pinned := false) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = prop_name
	var cs := CollisionShape3D.new()
	cs.shape = PubPhysics.shape_for(Vector2(radius, height))
	body.add_child(cs)
	cylinder(body, radius, height, Vector3.ZERO, mat)
	PubPhysics.setup_prop(body, mass, false, fragile, pinned)
	parent.add_child(body, true)
	body.position = pos
	return body


func occluder(node: Node3D) -> Node3D:
	node.add_to_group("camera_occluders")
	return node


# --- Room shell ---------------------------------------------------------------

## Floor covering `rect` (x, z, width, depth) with the era's pattern.
func floor_area(rect: Rect2, tile_metres := 2.0) -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var centre := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	body.position = centre
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 0.4, rect.size.y)
	shape.shape = box
	shape.position.y = -0.2
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = rect.size
	mesh.mesh = plane
	var floor_sets := {"boards": "planks", "tiles": "tiles", "flagstone": "flagstone", "slate": "slate"}
	var set: String = floor_sets.get(style["floor"], "flagstone")
	var tint: Color = Color(0.92, 0.9, 0.88) if set == "tiles" else (style["floor_a"] as Color).lerp(style["floor_b"], 0.5).lightened(0.08)
	var repeats := {"planks": 0.85, "tiles": 0.8, "flagstone": 0.42, "slate": 0.4}
	mesh.material_override = PubMaterials.surface(set, tint, repeats[set] * 2.0 / tile_metres, 1.0)
	body.add_child(mesh)
	world.add_child(body)


## Wall running along X at depth `z`, from `x0` to `x1`.
## `openings`: Array of {c: centre along the wall, w: width, top: height of the opening,
## sill: bottom (0 for doors), kind: "door" | "window" | "arch" | "hatch"}.
func wall_x(z: float, x0: float, x1: float, openings: Array = [], height := -1.0) -> Node3D:
	return _wall(Vector3(0, 0, z), true, x0, x1, openings, height)


## Wall running along Z at `x`, from `z0` to `z1`.
func wall_z(x: float, z0: float, z1: float, openings: Array = [], height := -1.0) -> Node3D:
	return _wall(Vector3(x, 0, 0), false, z0, z1, openings, height)


func _wall(origin: Vector3, along_x: bool, a0: float, a1: float, openings: Array, height: float) -> Node3D:
	var h: float = style["wall_height"] if height < 0.0 else height
	var root := Node3D.new()
	root.name = "Wall"
	world.add_child(root, true)
	occluder(root)
	walls_built.append({"origin": origin, "along_x": along_x, "a0": a0, "a1": a1, "height": h,
		"openings": openings.duplicate(true), "root": root})
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p["c"] < q["c"])
	var cursor := a0
	for op in ops:
		var o0: float = op["c"] - op["w"] * 0.5
		var o1: float = op["c"] + op["w"] * 0.5
		var top: float = minf(op.get("top", 2.1), h)
		var sill: float = op.get("sill", 0.0)
		if o0 > cursor:
			_wall_piece(root, origin, along_x, cursor, o0, 0.0, h)
		if top < h:
			_wall_piece(root, origin, along_x, o0, o1, top, h)  # lintel
		if sill > 0.0:
			_wall_piece(root, origin, along_x, o0, o1, 0.0, sill)
		var kind: String = op.get("kind", "door")
		if kind == "window":
			_window(root, origin, along_x, op["c"], op["w"], sill, top)
		elif kind == "door" or kind == "arch":
			_frame(root, origin, along_x, o0, o1, top)
		cursor = o1
	if cursor < a1:
		_wall_piece(root, origin, along_x, cursor, a1, 0.0, h)
	return root


func _axis_pos(origin: Vector3, along_x: bool, a: float, y: float) -> Vector3:
	return Vector3(a, y, origin.z) if along_x else Vector3(origin.x, y, a)


func _axis_size(along_x: bool, length: float, height: float, thick: float) -> Vector3:
	return Vector3(length, height, thick) if along_x else Vector3(thick, height, length)


func _wall_piece(root: Node3D, origin: Vector3, along_x: bool, a0: float, a1: float, y0: float, y1: float) -> void:
	var length := a1 - a0
	if length <= 0.01 or y1 - y0 <= 0.01:
		return
	var mid := (a0 + a1) * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = _axis_pos(origin, along_x, mid, (y0 + y1) * 0.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _axis_size(along_x, length, y1 - y0, WALL_THICKNESS)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	var centre_y := (y0 + y1) * 0.5
	# Lower dado (panelling or tiles) and upper wall in separate colours.
	if y0 < DADO_HEIGHT:
		var top := minf(y1, DADO_HEIGHT)
		deco(body, _axis_size(along_x, length, top - y0, WALL_THICKNESS),
			Vector3(0, (y0 + top) * 0.5 - centre_y, 0), material(style["dado"]))
	if y1 > DADO_HEIGHT:
		var bottom := maxf(y0, DADO_HEIGHT)
		deco(body, _axis_size(along_x, length, y1 - bottom, WALL_THICKNESS),
			Vector3(0, (bottom + y1) * 0.5 - centre_y, 0), material(style["wall"]))
	if y0 < DADO_HEIGHT and y1 > DADO_HEIGHT:
		deco(body, _axis_size(along_x, length, 0.07, WALL_THICKNESS + 0.05),
			Vector3(0, DADO_HEIGHT - centre_y, 0), material(style["trim"]))
	if style.get("posts", false) and y0 <= 0.01:
		# Timber framing: posts at the ends and every couple of metres.
		var n := maxi(1, int(round(length / 2.2)))
		for i in n + 1:
			var a := a0 + length * float(i) / float(n)
			var p := _axis_pos(Vector3.ZERO, along_x, a - mid, 0.0)
			p.y = 0.0
			deco(body, _axis_size(along_x, 0.2, y1 - y0, WALL_THICKNESS + 0.08), p, material(style["timber"]))
		deco(body, _axis_size(along_x, length, 0.18, WALL_THICKNESS + 0.08),
			Vector3(0, (y1 - y0) * 0.5 - 0.09, 0), material(style["timber"]))
	elif y1 >= float(style["wall_height"]) - 0.01:
		# Cornice along the top.
		deco(body, _axis_size(along_x, length, 0.12, WALL_THICKNESS + 0.1),
			Vector3(0, (y1 - y0) * 0.5 - 0.06, 0), material(style["trim"]))


func _frame(root: Node3D, origin: Vector3, along_x: bool, o0: float, o1: float, top: float) -> void:
	var m := material(style["timber"])
	for a in [o0, o1]:
		deco(root, _axis_size(along_x, 0.12, top, WALL_THICKNESS + 0.06), _axis_pos(origin, along_x, a, top * 0.5), m)
	deco(root, _axis_size(along_x, o1 - o0 + 0.24, 0.14, WALL_THICKNESS + 0.06),
		_axis_pos(origin, along_x, (o0 + o1) * 0.5, top), m)


func _window(root: Node3D, origin: Vector3, along_x: bool, c: float, w: float, sill: float, top: float) -> void:
	var pane := deco(root, _axis_size(along_x, w, top - sill, 0.04), _axis_pos(origin, along_x, c, (sill + top) * 0.5), glass())
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bar_mat := material(style["trim"] if style["label"] != "17th century" else Color("2a2a2a"), 0.3)
	# Glazing bars: sash (18th/19th) or leaded diamond-ish grid (17th).
	var rows := 2 if style["label"] != "17th century" else 4
	var cols := 3 if style["label"] != "17th century" else 4
	for r in range(1, rows):
		var y := sill + (top - sill) * float(r) / float(rows)
		deco(root, _axis_size(along_x, w, 0.04 if rows > 2 else 0.08, 0.08), _axis_pos(origin, along_x, c, y), bar_mat)
	for k in range(1, cols):
		var a := c - w * 0.5 + w * float(k) / float(cols)
		deco(root, _axis_size(along_x, 0.04, top - sill, 0.08), _axis_pos(origin, along_x, a, (sill + top) * 0.5), bar_mat)
	# Window frame.
	deco(root, _axis_size(along_x, w + 0.16, 0.1, WALL_THICKNESS + 0.08), _axis_pos(origin, along_x, c, sill), material(style["trim"]))


## Ceiling beam running along X at depth z.
func beam_x(z: float, x0: float, x1: float, y := -1.0) -> Node3D:
	var height: float = style["beam_height"] if y < 0.0 else y
	var b := Node3D.new()
	b.name = "Beam"
	world.add_child(b, true)
	deco(b, Vector3(x1 - x0, 0.28, 0.3), Vector3((x0 + x1) * 0.5, height, z), material(style["timber"]))
	_keep_out(_box_around(Vector3((x0 + x1) * 0.5, height, z), Vector3((x1 - x0) * 0.5, 0.25, 0.3)))
	return occluder(b)


## Ceiling beam running along Z at x.
func beam_z(x: float, z0: float, z1: float, y := -1.0) -> Node3D:
	var height: float = style["beam_height"] if y < 0.0 else y
	var b := Node3D.new()
	b.name = "Beam"
	world.add_child(b, true)
	deco(b, Vector3(0.3, 0.28, z1 - z0), Vector3(x, height, (z0 + z1) * 0.5), material(style["timber"]))
	_keep_out(_box_around(Vector3(x, height, (z0 + z1) * 0.5), Vector3(0.3, 0.25, (z1 - z0) * 0.5)))
	return occluder(b)


## Free-standing post (holds up a beam). Solid, so fighters can be shoved into it.
func post(x: float, z: float) -> void:
	var h: float = style["beam_height"]
	var body := solid(Vector3(0.28, h, 0.28), Vector3(x, h * 0.5, z), material(style["timber"]))
	occluder(body)


# --- Furniture and fixtures ---------------------------------------------------

## Bar counter. `rect` is (x, z, width, depth) on the floor. `staff_dir` is the world
## direction from the counter to where the staff stand (Vector3.FORWARD = behind it,
## towards the back wall). Adds the ordering zone, staff spots, punters at the bar
## and bottles to grab.
func bar_counter(rect: Rect2, staff_dir: Vector3, brass := false) -> void:
	var size := Vector3(rect.size.x, 1.1, rect.size.y)
	var centre := Vector3(rect.position.x + rect.size.x * 0.5, 0.55, rect.position.y + rect.size.y * 0.5)
	var body := solid(size, centre, material(style["bar"]))
	body.name = "Bar"
	deco(body, Vector3(size.x + 0.12, 0.08, size.z + 0.12), Vector3(0, 0.59, 0), material(style["bar_top"], 0.0, 0.4))
	# Panel lines on the punter side.
	var long_x := rect.size.x >= rect.size.y
	var length := rect.size.x if long_x else rect.size.y
	var panels := maxi(1, int(length / 1.2))
	for i in panels + 1:
		var a := -length * 0.5 + length * float(i) / float(panels)
		var p := Vector3(a, -0.05, 0) if long_x else Vector3(0, -0.05, a)
		deco(body, Vector3(0.08, 0.9, size.z + 0.04) if long_x else Vector3(size.x + 0.04, 0.9, 0.08), p, material(style["timber"]))
	var punter_dir := -staff_dir
	if brass:
		var rail_off := punter_dir * ((size.z if long_x else size.x) * 0.5 + 0.12)
		var rail := deco(body, Vector3(length, 0.05, 0.05) if long_x else Vector3(0.05, 0.05, length),
			rail_off + Vector3(0, -0.4, 0), material(style["accent"], 0.9, 0.3))
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Beer pumps along the top.
	var pumps := maxi(2, int(length / 1.5))
	for i in pumps:
		var a := -length * 0.35 + length * 0.7 * float(i) / float(maxi(1, pumps - 1))
		var p := Vector3(a, 0.8, 0) if long_x else Vector3(0, 0.8, a)
		cylinder(body, 0.04, 0.45, p, material(style["accent"], 0.8, 0.3))
		cylinder(body, 0.05, 0.18, p + Vector3(0, 0.3, 0), material(Color("1c1008")))
	# Where you order: an area along the punter side.
	var zone_size := Vector3(size.x + 0.8, 2.0, 1.4) if long_x else Vector3(1.4, 2.0, size.z + 0.8)
	var zone_pos := centre + punter_dir * ((size.z if long_x else size.x) * 0.5 + 0.6)
	zone_pos.y = 1.0
	bar_zone(zone_size, zone_pos)
	# Ordering logic from the items workstream: local +Z faces the customers.
	var order_bar := Bar.new()
	order_bar.name = "OrderBar%d" % _bar_count()
	order_bar.length = length
	order_bar.depth = size.z if long_x else size.x
	order_bar.top_height = size.y
	order_bar.position = Vector3(centre.x, 0.0, centre.z)
	order_bar.basis = Basis.looking_at(-punter_dir, Vector3.UP)
	world.add_child(order_bar)
	# Staff stand behind the middle of the bar; a second spot for wider bars.
	var depth := size.z if long_x else size.x
	var behind := centre + staff_dir * (depth * 0.5 + 0.7)
	behind.y = 0.0
	marker(PubLevel.STAFF, behind, {"facing": punter_dir})
	if length > 5.0:
		var side := Vector3(length * 0.3, 0, 0) if long_x else Vector3(0, 0, length * 0.3)
		marker(PubLevel.STAFF, behind + side, {"facing": punter_dir})
	# A couple of punters propping up the bar.
	for k in [-0.3, 0.25]:
		var along := Vector3(length * k, 0, 0) if long_x else Vector3(0, 0, length * k)
		var spot := centre + punter_dir * (depth * 0.5 + 0.55) + along
		spot.y = 0.0
		marker(PubLevel.PUNTER, spot, {"pose": "bar", "facing": staff_dir})
	# Bottles on the bar to grab.
	for k in [-0.4, 0.4]:
		var along := Vector3(length * k, 0, 0) if long_x else Vector3(0, 0, length * k)
		prop("bottle", centre + along + Vector3(0, 0.63, 0))
	prop("glass", centre + Vector3(0, 0.63, 0))
	_keep_out(_box_around(centre, size * 0.5 + Vector3(0.3, 0.5, 0.3) + punter_dir.abs() * 1.4))
	# Clutter along the punters' side of the counter: drip mats, half-finished drinks,
	# crisps, the tip jar, the bell for last orders.
	var rng := RandomNumberGenerator.new()
	rng.seed = PropLibrary.seed_for(centre)
	var once := ["bell_brass", "tip_jar", "snack_pickled_eggs", "ice_bucket", "pump_clip_stand", "menu_stand"]
	var many := ["beermat_stack", "ashtray_glass", "ashtray_tin", "snack_crisps", "snack_crisps_sv", "snack_crisps_co",
		"snack_scratchings", "snack_peanuts_bowl", "glass_half", "glass_empty_pint", "glass_tumbler", "glass_shot",
		"glass_wine_red", "bottle_candle"]
	var top_y := centre.y + size.y * 0.5 + 0.045
	var a := -length * 0.5 + 0.3
	while a < length * 0.5 - 0.3:
		var pick: String = once.pop_back() if not once.is_empty() and rng.randf() < 0.35 else many[rng.randi() % many.size()]
		var along := Vector3(a, 0, 0) if long_x else Vector3(0, 0, a)
		var out := punter_dir * (depth * rng.randf_range(0.18, 0.36))
		decor(pick, Vector3(centre.x, top_y, centre.z) + along + out, rng.randf_range(0.0, 360.0))
		a += rng.randf_range(0.45, 0.9)


func _bar_count() -> int:
	var n := 0
	for c in world.get_children():
		if c is Bar:
			n += 1
	return n


## Shelving and optics against a wall behind the bar. `facing` points into the room.
func back_bar(centre: Vector3, length: float, facing: Vector3, carved := false) -> void:
	var along_x := absf(facing.z) > absf(facing.x)
	var depth := 0.45
	var h := 2.2 if carved else 1.8
	var size := Vector3(length, h, depth) if along_x else Vector3(depth, h, length)
	var body := solid(size, Vector3(centre.x, h * 0.5, centre.z), material(style["bar"]))
	body.name = "BackBar"
	var front := facing * (depth * 0.5 + 0.02)
	# Shelves of real bottles and glasses. They're pinned props: slam someone into the back
	# bar and the physics knocks them off.
	var rng := RandomNumberGenerator.new()
	rng.seed = PropLibrary.seed_for(centre)
	var spirits := PropLibrary.variants("bottle")
	var glasses := PropLibrary.variants("decor_glass")
	_keep_out(_box_around(Vector3(centre.x, h * 0.5 + 0.3, centre.z), size * 0.5 + Vector3(0.3, 0.3, 0.3)))
	for shelf in 3:
		var y := -h * 0.5 + 0.9 + shelf * 0.38
		deco(body, (Vector3(length, 0.04, 0.3) if along_x else Vector3(0.3, 0.04, length)),
			front * 0.6 + Vector3(0, y, 0), material(style["bar_top"]))
		var n := int(length / 0.2)
		for i in n:
			var a := -length * 0.5 + 0.15 + i * 0.2 + rng.randf_range(-0.03, 0.03)
			var p := (Vector3(a, y + 0.02, 0) if along_x else Vector3(0, y + 0.02, a)) + front * 0.6
			var pool := glasses if shelf == 0 and glasses.size() > 0 else spirits
			if pool.is_empty():
				continue
			var pick: String = pool[rng.randi() % pool.size()]
			decor(pick, body.position + p, rad_to_deg(atan2(facing.x, facing.z)) + rng.randf_range(-25.0, 25.0), true, "ShelfBottle")
	if carved:
		# Victorian gantry: mirror panel and carved crest.
		deco(body, (Vector3(length * 0.8, 0.5, 0.02) if along_x else Vector3(0.02, 0.5, length * 0.8)),
			front + Vector3(0, -h * 0.5 + 0.55, 0), material(Color("c8d0d0"), 1.0, 0.05))
		deco(body, (Vector3(length + 0.2, 0.35, depth + 0.15) if along_x else Vector3(depth + 0.15, 0.35, length + 0.2)),
			Vector3(0, h * 0.5 + 0.17, 0), material(style["timber"]))
		deco(body, (Vector3(length * 0.3, 0.4, 0.1) if along_x else Vector3(0.1, 0.4, length * 0.3)),
			Vector3(0, h * 0.5 + 0.55, 0), material(style["accent"], 0.7, 0.35))
		occluder(body)


## Fireplace set into a wall. `pos` is the hearth centre on the floor against the wall,
## `facing` points into the room. Inglenook = big, walk-in 17th century hearth.
## `top` is the world height the chimney breast reaches (defaults to the wall height).
func fireplace(pos: Vector3, facing: Vector3, kind := "inglenook", top := -1.0) -> void:
	var along_x := absf(facing.z) > absf(facing.x)
	var root := Node3D.new()
	root.name = "Fireplace"
	root.position = pos
	world.add_child(root, true)
	var brick := material(Color("5a3024"))
	var dark := material(Color("140c08"))
	var w := 2.6 if kind == "inglenook" else 1.4
	var h := 1.9 if kind == "inglenook" else 1.2
	var d := 0.9 if kind == "inglenook" else 0.5
	# Cheeks either side of the opening, and the chimney breast above.
	for s in [-1.0, 1.0]:
		var cheek := StaticBody3D.new()
		cheek.position = _flip(along_x, Vector3(s * (w * 0.5 + 0.25), h * 0.5, 0)) + facing * (d * 0.5)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = _flip(along_x, Vector3(0.5, h, d))
		cs.shape = bs
		cheek.add_child(cs)
		root.add_child(cheek)
		deco(cheek, bs.size, Vector3.ZERO, brick)
	var breast_top: float = (float(style["wall_height"]) if top < 0.0 else top) - pos.y
	var breast := deco(root, _flip(along_x, Vector3(w + 1.0, breast_top - h, d)),
		_flip(along_x, Vector3(0, (h + breast_top) * 0.5, 0)) + facing * (d * 0.5), brick)
	breast.add_to_group("camera_occluders")
	deco(root, _flip(along_x, Vector3(w, h, 0.1)), Vector3(0, h * 0.5, 0) + facing * 0.05, dark)
	if kind == "inglenook":
		deco(root, _flip(along_x, Vector3(w + 1.2, 0.3, 0.35)), Vector3(0, h + 0.15, 0) + facing * (d + 0.05),
			material(style["timber"]))  # bressumer beam
	else:
		deco(root, _flip(along_x, Vector3(w + 1.2, 0.08, 0.3)), Vector3(0, h + 0.1, 0) + facing * (d + 0.1),
			material(style["trim"] if kind == "mantel" else Color("1a1a1a"), 0.4 if kind == "range" else 0.0))
	# Hearth stone and the fire.
	deco(root, _flip(along_x, Vector3(w + 0.6, 0.06, 0.9)), Vector3(0, 0.03, 0) + facing * (d + 0.4), material(Color("4a4440")))
	var logs := deco(root, _flip(along_x, Vector3(0.8, 0.25, 0.3)), Vector3(0, 0.15, 0) + facing * (d * 0.4), material(Color("2b1a0e")))
	logs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame := sphere(root, 0.28, Vector3(0, 0.4, 0) + facing * (d * 0.4), emissive(Color("ff7a1a"), 4.0))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.8, 0) + facing * (d + 0.4)
	light.light_color = Color("ff8a3a")
	light.light_energy = 2.6
	light.omni_range = 7.5
	light.shadow_enabled = _shadows()
	root.add_child(light)
	flicker_lights.append(light)
	_keep_out(_box_around(pos + facing * 1.0 + Vector3(0, float(style["wall_height"]) * 0.5, 0),
		_flip(along_x, Vector3(w * 0.5 + 1.3, 0, 0)).abs() + Vector3(0, float(style["wall_height"]) * 0.5, 0) + facing.abs() * 1.2))
	# Fireplace tools are weapons.
	var tools_pos := pos + _flip(along_x, Vector3(w * 0.5 + 0.7, 0, 0)) + facing * (d + 0.35)
	prop("poker", tools_pos)
	prop("fire_tongs", tools_pos + _flip(along_x, Vector3(0.15, 0, 0)))
	prop("fire_shovel", tools_pos + _flip(along_x, Vector3(0.3, 0, 0)))


## Dartboard on a wall at `pos` (centre of the board, on the wall face), facing into the room.
func dartboard(pos: Vector3, facing: Vector3) -> void:
	var root := Node3D.new()
	root.name = "Dartboard"
	root.position = pos
	# DartsBoard finds playable boards by this group and reads which way they face.
	root.add_to_group(DartsBoard.GROUP)
	root.set_meta("facing", facing)
	world.add_child(root, true)
	var along := Vector3(1, 0, 0) if absf(facing.z) > 0.5 else Vector3(0, 0, 1)
	# Regulation board in an open cabinet (PropLibrary "dartboard"); the root stays
	# unrotated and the model turns to face the room (its face is local +Z).
	var model := PropLibrary.visual("dartboard")
	if model != null:
		model.rotation.y = atan2(facing.x, facing.z)
		root.add_child(model)
	else:
		var board := cylinder(root, 0.23, 0.05, Vector3.ZERO, material(Color("1a1a1a")))
		board.rotation = Vector3(PI * 0.5, 0, 0) if absf(facing.z) > 0.5 else Vector3(0, 0, PI * 0.5)
	# Keep the wall round the board and the throwing lane clear of pictures and furniture.
	_keep_out(_box_around(pos, along * 0.8 + Vector3(0, 0.6, 0) + facing.abs() * 0.3))
	_keep_out(_box_around(Vector3(pos.x, 1.0, pos.z) + facing * 1.4, along * 0.9 + Vector3(0, 1.0, 0) + facing.abs() * 1.6))
	# Oche line 2.37 m out and a set of darts on a shelf/table near it.
	var oche := Vector3(pos.x, 0.01, pos.z) + facing * 2.37
	deco(world, (Vector3(0.6, 0.02, 0.05) if absf(facing.z) > 0.5 else Vector3(0.05, 0.02, 0.6)), oche, material(Color("c9a03a"), 0.8))
	prop("darts", Vector3(pos.x, 0.0, pos.z) + facing * 0.5 + along * 0.7)
	marker(PubLevel.PUNTER, Vector3(oche.x, 0, oche.z) + facing * 0.3, {"pose": "darts", "facing": -facing})


## Pool table centred on `pos`, long side along X unless `rot_y` is 90.
func pool_table(pos: Vector3, rot_y := 0.0) -> void:
	var model := PropLibrary.visual("pool_table")
	var body := solid(Vector3(2.4, 0.8, 1.3), Vector3(pos.x, 0.4, pos.z), material(style["furniture"]), rot_y, null, model == null)
	body.name = "PoolTable"
	if model != null:
		model.position.y = -0.4
		body.add_child(model)
	else:
		deco(body, Vector3(2.2, 0.04, 1.1), Vector3(0, 0.41, 0), material(Color("1f6a35"), 0.0, 0.95))
	var balls := [Color("e8e2d0"), Color("c22a1a"), Color("e0b81a"), Color("141414"), Color("c22a1a"), Color("e0b81a")]
	for i in balls.size():
		var ball := RigidBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = PubPhysics.shape_for(0.03)
		ball.add_child(cs)
		sphere(ball, 0.03, Vector3.ZERO, material(balls[i], 0.0, 0.2)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.name = "PoolBall"
		PubPhysics.setup_prop(ball, 0.17)
		ball.linear_damp = 0.6
		body.add_child(ball, true)
		ball.position = Vector3(-0.3 + (i % 3) * 0.08, 0.431, -0.1 + (i / 3) * 0.09)
	_keep_out(AABB(Vector3(pos.x - 2.2, 0, pos.z - 2.0), Vector3(4.4, 2.0, 4.0)))
	var basis := Basis(Vector3.UP, deg_to_rad(rot_y))
	prop("pool_cue", pos + basis * Vector3(0.0, 0.85, 0.55), rot_y)
	prop("pool_cue", pos + basis * Vector3(0.6, 0.0, 0.9), rot_y)
	marker(PubLevel.PUNTER, pos + basis * Vector3(-1.6, 0, 0.2), {"pose": "pool", "facing": basis * Vector3.RIGHT})
	marker(PubLevel.PUNTER, pos + basis * Vector3(1.0, 0, -1.1), {"pose": "pool", "facing": basis * Vector3.BACK})


## A table with chairs (or stools) round it, as prop spawns plus seated punter spots.
## Tables and chairs are weapons, so they're spawned by the items workstream; until
## then PubLevel drops greybox stand-ins on these markers.
func table_set(pos: Vector3, seats := 4, seat_kind := "chair", drinks := 2) -> void:
	var table := prop("table", pos)
	var top := pos.y + (PropLibrary.dims("table", table.get_meta("variant", "")).y if PropLibrary.has("table") else 0.78) + 0.005
	_keep_out(_box_around(pos + Vector3(0, 0.6, 0), Vector3(1.4, 0.6, 1.4)))
	# One style of chair round each table.
	var seat_variant := PropLibrary.resolve(seat_kind, PropLibrary.seed_for(pos) / 7) if PropLibrary.has(seat_kind) else ""
	var offsets := [Vector3(0, 0, -0.85), Vector3(0, 0, 0.85), Vector3(-0.85, 0, 0), Vector3(0.85, 0, 0)]
	for i in mini(seats, offsets.size()):
		var o: Vector3 = offsets[i]
		var rot := rad_to_deg(atan2(o.x, o.z))
		prop(seat_kind, pos + o, rot, seat_variant)
		if i < 2:
			marker(PubLevel.PUNTER, pos + o * 1.05, {"pose": "seated", "facing": -o.normalized()})
	for d in drinks:
		var kind := "pint" if d % 2 == 0 else "glass"
		prop(kind, Vector3(pos.x - 0.2 + d * 0.35, top, pos.z + 0.1 * (d % 2)))
	if drinks >= 2:
		prop("plate", Vector3(pos.x + 0.15, top, pos.z - 0.25))
	# Table-top clutter that gets sent flying: ashtrays, drip mats, a candle, crisps.
	var rng := RandomNumberGenerator.new()
	rng.seed = PropLibrary.seed_for(pos)
	var clutter := ["ashtray_glass", "ashtray_tin", "beermat_stack", "candle_stick", "bottle_candle", "salt_pepper",
		"snack_crisps", "snack_crisps_sv", "snack_scratchings", "snack_peanuts_bowl", "glass_half", "glass_wine_red",
		"glass_tumbler", "bottle_ketchup", "bottle_brown_sauce", "bottle_vinegar", "menu_stand", "glass_sherry"]
	var spots := [Vector3(0.24, 0, 0.22), Vector3(-0.26, 0, -0.2), Vector3(0.0, 0, 0.0), Vector3(-0.22, 0, 0.26)]
	for i in rng.randi_range(1, 3):
		var o: Vector3 = spots[i]
		decor(clutter[rng.randi() % clutter.size()], Vector3(pos.x + o.x, top, pos.z + o.z), rng.randf_range(0.0, 360.0))


## High-backed settle (fixed bench) — scenery, solid.
func settle(pos: Vector3, facing: Vector3, length := 1.8) -> void:
	var along_x := absf(facing.z) > absf(facing.x)
	var seat := solid((Vector3(length, 0.45, 0.5) if along_x else Vector3(0.5, 0.45, length)),
		Vector3(pos.x, 0.225, pos.z), material(style["furniture"]))
	deco(seat, (Vector3(length, 1.2, 0.08) if along_x else Vector3(0.08, 1.2, length)),
		-facing * 0.25 + Vector3(0, 0.6, 0), material(style["timber"]))


## Etched glass screen on a timber frame, solid. Victorian pubs use these to split rooms.
func glass_screen(from: Vector3, to: Vector3, height := 2.1) -> void:
	var along_x := absf(to.x - from.x) > absf(to.z - from.z)
	var length := from.distance_to(to)
	var centre := (from + to) * 0.5
	var body := solid((Vector3(length, 1.0, 0.12) if along_x else Vector3(0.12, 1.0, length)),
		Vector3(centre.x, 0.5, centre.z), material(style["timber"]))
	occluder(body)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, height - 1.0, 0.08) if along_x else Vector3(0.08, height - 1.0, length)
	col.shape = bs
	col.position.y = 0.5 + (height - 1.0) * 0.5
	body.add_child(col)
	var etched := StandardMaterial3D.new()
	etched.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	etched.albedo_color = Color(0.9, 0.92, 0.85, 0.45)
	etched.roughness = 0.3
	var pane := deco(body, bs.size, col.position, etched)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var panels := maxi(1, int(length / 0.9))
	for i in panels + 1:
		var a := -length * 0.5 + length * float(i) / float(panels)
		deco(body, (Vector3(0.08, height - 1.0, 0.14) if along_x else Vector3(0.14, height - 1.0, 0.08)),
			Vector3(a, col.position.y, 0) if along_x else Vector3(0, col.position.y, a), material(style["timber"]))
	deco(body, (Vector3(length, 0.1, 0.16) if along_x else Vector3(0.16, 0.1, length)),
		Vector3(0, height - 0.5, 0), material(style["timber"]))


## Era lamp. On a wall when `wall_facing` is set, otherwise hanging from the ceiling.
func lamp(pos: Vector3, wall_facing := Vector3.ZERO) -> void:
	var kind: String = style["lamp_kind"]
	var root := Node3D.new()
	root.name = "Lamp"
	root.position = pos
	world.add_child(root, true)
	var bulb_col: Color = style["lamp"]
	match kind:
		"candle":
			if wall_facing != Vector3.ZERO:
				deco(root, Vector3(0.1, 0.1, 0.1), -wall_facing * 0.05, material(Color("2a2a2a"), 0.6))
			cylinder(root, 0.03, 0.18, Vector3(0, 0.09, 0), material(Color("efe6cc")))
			sphere(root, 0.035, Vector3(0, 0.22, 0), emissive(bulb_col, 6.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"sconce":
			deco(root, Vector3(0.08, 0.3, 0.08), -wall_facing * 0.05, material(style["accent"], 0.9, 0.3))
			for s in [-0.12, 0.12]:
				var off := Vector3(s, 0.12, 0) if absf(wall_facing.z) > 0.5 else Vector3(0, 0.12, s)
				cylinder(root, 0.02, 0.14, off + wall_facing * 0.08, material(Color("efe6cc")))
				sphere(root, 0.03, off + wall_facing * 0.08 + Vector3(0, 0.1, 0), emissive(bulb_col, 6.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"gas":
			if wall_facing == Vector3.ZERO:
				var drop := float(style["wall_height"]) - pos.y
				cylinder(root, 0.015, drop, Vector3(0, drop * 0.5, 0), material(style["accent"], 0.9, 0.3))
				root.add_to_group("camera_occluders")
			else:
				deco(root, Vector3(0.06, 0.06, 0.3), -wall_facing * 0.1, material(style["accent"], 0.9, 0.3))
			sphere(root, 0.12, Vector3.ZERO, emissive(bulb_col, 3.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if wall_facing != Vector3.ZERO:
		_keep_out(_box_around(pos, Vector3(0.4, 0.4, 0.4)))
	var light := OmniLight3D.new()
	light.position = wall_facing * 0.3 + Vector3(0, 0.2, 0)
	light.light_color = bulb_col
	light.light_energy = float(style["lamp_energy"])
	light.omni_range = float(style["lamp_range"])
	light.shadow_enabled = false
	root.add_child(light)
	if kind != "sconce":
		flicker_lights.append(light)


## Light coming through a window: a soft spot outside pointing in. `facing` is into the room.
func window_light(pos: Vector3, facing: Vector3, color := Color("8fa6c4"), energy := 1.2) -> void:
	var light := SpotLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.spot_range = 8.0
	light.spot_angle = 50.0
	world.add_child(light)
	light.global_position = pos - facing * 0.6 + Vector3(0, 0.6, 0)
	light.look_at(pos + facing * 3.0 + Vector3(0, -1.5, 0), Vector3.UP)


## Swap X and Z when a fixture sits on a side wall (along Z).
func _flip(along_x: bool, v: Vector3) -> Vector3:
	return v if along_x else Vector3(v.z, v.y, v.x)


func _shadows() -> bool:
	return bool(Settings.get_value("graphics", "shadows"))


# --- Markers ------------------------------------------------------------------

## Gameplay marker. `kind` is one of the PubLevel marker kinds; `meta` is copied to node metadata.
func marker(kind: String, pos: Vector3, meta := {}) -> Marker3D:
	var parent := markers.get_node_or_null(kind) as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = kind
		markers.add_child(parent)
	var m := Marker3D.new()
	m.name = "%s%d" % [kind.trim_suffix("s"), parent.get_child_count()]
	m.position = pos
	for key in meta:
		m.set_meta(key, meta[key])
	if meta.has("facing") and (meta["facing"] as Vector3).length() > 0.01:
		var f: Vector3 = meta["facing"]
		m.rotation.y = atan2(-f.x, -f.z)
	parent.add_child(m)
	return m


## Spawn point for a weapon or consumable. `kind` matches an item id (bottle, glass,
## pint, plate, chair, stool, table, pool_cue, darts, poker, fire_tongs, fire_shovel).
## `variant` picks a model (PropLibrary); by default the position picks one, so every
## peer gets the same look. It's stored as the marker's "variant" meta.
func prop(kind: String, pos: Vector3, rot_y := 0.0, variant := "") -> Marker3D:
	var m := marker(PubLevel.PROPS, pos, {"item": kind})
	m.rotation_degrees.y = rot_y
	if PropLibrary.has(kind):
		m.set_meta("variant", variant if variant != "" else PropLibrary.resolve(kind, pos))
	return m


## Ordering area at the bar (Area3D on no layer, watching players).
func bar_zone(size: Vector3, pos: Vector3) -> Area3D:
	var parent := markers.get_node_or_null(PubLevel.BAR_ZONES) as Node3D
	if parent == null:
		parent = Node3D.new()
		parent.name = PubLevel.BAR_ZONES
		markers.add_child(parent)
	var area := Area3D.new()
	area.name = "BarZone%d" % parent.get_child_count()
	area.position = pos
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	parent.add_child(area)
	return area


## Door: NPCs and police arrive from `outside` and walk to `inside`.
func door(outside: Vector3, inside: Vector3, police := true) -> void:
	marker(PubLevel.DOORS, outside, {"inside": inside, "facing": (inside - outside).normalized()})
	if police:
		marker(PubLevel.POLICE, outside, {"inside": inside, "facing": (inside - outside).normalized()})


## Brass candle chandelier hanging from the ceiling (18th century rooms).
func chandelier(pos: Vector3, arms := 6) -> void:
	var root := Node3D.new()
	root.name = "Chandelier"
	root.position = pos
	world.add_child(root, true)
	occluder(root)
	var brass := material(style["accent"], 0.9, 0.3)
	var drop := float(style["wall_height"]) - pos.y
	cylinder(root, 0.015, drop, Vector3(0, drop * 0.5, 0), brass)
	sphere(root, 0.1, Vector3.ZERO, brass)
	for i in arms:
		var a := TAU * float(i) / float(arms)
		var p := Vector3(cos(a) * 0.45, 0.05, sin(a) * 0.45)
		deco(root, Vector3(0.45, 0.03, 0.03), p * 0.5, brass, -rad_to_deg(a))
		cylinder(root, 0.02, 0.14, p + Vector3(0, 0.07, 0), material(Color("efe6cc")))
		sphere(root, 0.03, p + Vector3(0, 0.17, 0), emissive(style["lamp"], 6.0)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.2, 0)
	light.light_color = style["lamp"]
	light.light_energy = float(style["lamp_energy"]) * 1.4
	light.omni_range = float(style["lamp_range"]) * 1.2
	root.add_child(light)
	flicker_lights.append(light)


## Ale barrel, a heavy physics body: a body flung into it rocks it, and one on its side rolls.
func barrel(pos: Vector3, on_side := false) -> void:
	var body := RigidBody3D.new()
	body.position = pos + Vector3(0, 0.45 if not on_side else 0.4, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 0.9
	shape.shape = cyl
	body.add_child(shape)
	body.name = "Barrel"
	PubPhysics.setup_prop(body, 55.0, true)
	world.add_child(body, true)
	var wood := material(Color("6a4524"))
	var hoop := material(Color("2a2a2a"), 0.7, 0.5)
	var m := cylinder(body, 0.35, 0.9, Vector3.ZERO, wood)
	for y in [-0.3, 0.3]:
		cylinder(m, 0.37, 0.05, Vector3(0, y, 0), hoop)
	if on_side:
		body.rotation.z = PI * 0.5



# --- Levels: galleries, platforms and stairs -------------------------------------

## Every flight of stairs built, as {"base": Vector3, "top": Vector3, "dir": Vector3}.
## Used by tests and handy for AI pathing.
var stairs_built: Array[Dictionary] = []

const _SIDES := {
	"front": Vector3.BACK, "back": Vector3.FORWARD, "left": Vector3.LEFT, "right": Vector3.RIGHT,
}


## A raised floor: a gallery, loft, balcony or dais. `rect` is (x, z, width, depth) and
## `top` is the height of its walking surface.
## `edges`: the sides that drop off ("front" = +Z, "back" = -Z, "left" = -X, "right" = +X).
## Sides not listed are against a wall.
## `rails`: the drop-off sides that get a railing. Railings are waist height, so a
## fighter can be thrown over them; open sides can be walked or shoved off.
## `gaps`: [{side, c, w}] breaks in a railing, e.g. at the top of stairs or a deliberate
## spot to throw someone off.
## Every drop-off edge gets Ledges markers (see PubLevel.LEDGES).
func platform(rect: Rect2, top: float, edges: Array = ["front"], rails: Array = [], gaps: Array = [],
		metal_rails := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Gallery" if top > 1.5 else "Dais"
	world.add_child(root, true)
	occluder(root)
	platforms_built.append({"rect": rect, "top": top})
	var thick := 0.25 if top > 1.0 else top
	var centre := Vector3(rect.get_center().x, top - thick * 0.5, rect.get_center().y)
	var floor_mat := material(style["floor_a"].darkened(0.15)) if top > 1.0 else material(style["timber"].lightened(0.1))
	var slab := solid(Vector3(rect.size.x, thick, rect.size.y), centre, floor_mat, 0.0, root)
	slab.name = "Floor"
	# Boards on top so it reads as a floor, edge beam on drop-off sides.
	deco(slab, Vector3(rect.size.x, 0.02, rect.size.y), Vector3(0, thick * 0.5 + 0.01, 0), material(style["floor_b"]))
	var rail_mat := material(Color("1c1c1c"), 0.8, 0.4) if metal_rails else material(style["timber"])
	for side in edges:
		var n: Vector3 = _SIDES[side]
		var along_x := absf(n.z) > 0.5
		var length := rect.size.x if along_x else rect.size.y
		var edge_mid := Vector3(centre.x, 0, centre.z) + Vector3(n.x * rect.size.x * 0.5, 0, n.z * rect.size.y * 0.5)
		if top > 1.0:
			deco(root, _flip(along_x, Vector3(length, 0.3, 0.18)), edge_mid + Vector3(0, top - 0.15, 0) - n * 0.09, material(style["timber"]))
		var side_gaps := gaps.filter(func(g): return g["side"] == side)
		# Supports under the front of a gallery.
		if top > 1.5:
			var posts := maxi(1, int(round(length / 3.5)))
			for i in posts + 1:
				var a := -length * 0.5 + length * float(i) / float(posts)
				var at := edge_mid + _flip(along_x, Vector3(a, 0, 0)) - n * 0.15
				if _in_gaps(a + (edge_mid.x if along_x else edge_mid.z), side_gaps, 0.2):
					continue
				solid(Vector3(0.24, top - thick, 0.24), at + Vector3(0, (top - thick) * 0.5, 0), material(style["timber"]), 0.0, root)
		if rails.has(side):
			_railing(root, edge_mid, n, along_x, length, top, side_gaps, rail_mat)
		# Ledge markers every ~1.5 m along the edge.
		var count := maxi(1, int(length / 1.5))
		for i in count:
			var a := -length * 0.5 + length * (float(i) + 0.5) / float(count)
			var world_a := a + (edge_mid.x if along_x else edge_mid.z)
			var railed := rails.has(side) and not _in_gaps(world_a, side_gaps, 0.0)
			var ledge := edge_mid + _flip(along_x, Vector3(a, 0, 0)) + Vector3(0, top, 0) - n * 0.3
			marker(PubLevel.LEDGES, ledge, {"normal": n, "drop": top, "railing": railed, "facing": n})
			if not railed:  # keep the landing clear for anyone thrown off
				_keep_out(AABB(Vector3(ledge.x - 1.0, 0, ledge.z - 1.0) + n * 0.8, Vector3(2.0, top, 2.0)))
	return root


func _in_gaps(a: float, gaps: Array, pad: float) -> bool:
	for g in gaps:
		if absf(a - float(g["c"])) < float(g["w"]) * 0.5 + pad:
			return true
	return false


func _railing(root: Node3D, edge_mid: Vector3, n: Vector3, along_x: bool, length: float, top: float,
		gaps: Array, mat: Material) -> void:
	var h := 0.95
	var start := (edge_mid.x if along_x else edge_mid.z) - length * 0.5
	var end := start + length
	# Split the rail into runs between gaps.
	var cuts := [[start, end]]
	for g in gaps:
		var g0: float = float(g["c"]) - float(g["w"]) * 0.5
		var g1: float = float(g["c"]) + float(g["w"]) * 0.5
		var next := []
		for run in cuts:
			if g1 <= run[0] or g0 >= run[1]:
				next.append(run)
			else:
				if g0 > run[0]:
					next.append([run[0], g0])
				if g1 < run[1]:
					next.append([g1, run[1]])
		cuts = next
	for run in cuts:
		var r0: float = run[0]
		var r1: float = run[1]
		if r1 - r0 < 0.1:
			continue
		var mid := (r0 + r1) * 0.5
		var base := Vector3(mid, top, edge_mid.z) if along_x else Vector3(edge_mid.x, top, mid)
		base -= n * 0.08
		var body := solid(_flip(along_x, Vector3(r1 - r0, 0.08, 0.1)), base + Vector3(0, h, 0), mat, 0.0, root, false)
		# Collision covers the whole height so you can't walk through; it's low enough to throw over.
		var cs := body.get_child(0) as CollisionShape3D
		var bs := BoxShape3D.new()
		bs.size = _flip(along_x, Vector3(r1 - r0, h, 0.1))
		cs.shape = bs
		cs.position.y = -h * 0.5
		deco(body, _flip(along_x, Vector3(r1 - r0, 0.08, 0.12)), Vector3.ZERO, mat)
		var balusters := maxi(1, int((r1 - r0) / 0.25))
		for i in balusters + 1:
			var a := -(r1 - r0) * 0.5 + (r1 - r0) * float(i) / float(balusters)
			deco(body, Vector3(0.04, h, 0.04), _flip(along_x, Vector3(a, -h * 0.5, 0)), mat)


## A straight flight of stairs from `base` (floor level, foot of the stairs) running in
## `dir` (one of the four axis directions) for `run` metres, climbing `rise`. The
## collision is a smooth ramp so fighters walk up without snagging; the steps are visual.
func stairs(base: Vector3, dir: Vector3, run: float, rise: float, width := 1.4) -> Node3D:
	var root := StaticBody3D.new()
	root.name = "Stairs"
	root.collision_layer = 1
	root.collision_mask = 0
	root.position = base
	world.add_child(root, true)
	var side := Vector3(-dir.z, 0, dir.x) * (width * 0.5)
	var far := dir * run
	var up := Vector3(0, rise, 0)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([side, -side, far + side, far - side, far + up + side, far + up - side])
	var cs := CollisionShape3D.new()
	cs.shape = shape
	root.add_child(cs)
	var steps := maxi(2, int(round(rise / 0.2)))
	var tread := run / float(steps)
	var step_rise := rise / float(steps)
	var along_x := absf(dir.x) > 0.5
	var wood := material(style["timber"].lightened(0.15))
	for i in steps:
		var h := step_rise * float(i + 1)
		var centre := dir * (tread * (float(i) + 0.5)) + Vector3(0, h * 0.5, 0)
		deco(root, Vector3(tread, h, width) if along_x else Vector3(width, h, tread), centre, wood)
	stairs_built.append({"base": base, "top": base + far + up, "dir": dir})
	return occluder(root)


# --- Decor: props, pictures and furniture -------------------------------------------

## Every wall built, as {origin, along_x, a0, a1, height, openings, root}. dress() hangs
## pictures and stands furniture along them.
var walls_built: Array[Dictionary] = []
## Every gallery, loft or dais, as {rect, top}.
var platforms_built: Array[Dictionary] = []
var _keepouts: Array[AABB] = []
var _decor_root: Node3D
var _decor_count := 0

## Wall pieces dress() picks from, most wanted first. Each goes up at most twice per pub,
## or as many times as PICTURE_LIMITS says.
const PICTURES := ["picture_landscape", "picture_portrait", "mirror_brewery", "picture_hunt", "chalkboard_menu",
	"picture_ship", "horse_brasses", "picture_bull", "wall_clock", "shelf_bottles", "plate_rack_plates",
	"picture_team_photo", "antlers", "fish_case", "pub_sign_small"]
const PICTURE_LIMITS := {"horse_brasses": 3, "mirror_brewery": 1, "wall_clock": 1, "chalkboard_menu": 1, "antlers": 1,
	"fish_case": 1}
## Floor-standing furniture, most wanted first (the piano always tries to go in).
const FURNITURE := ["piano_upright", "welsh_dresser", "grandfather_clock", "bookcase", "coat_stand", "sideboard",
	"armchair_wingback", "fruit_machine", "cask_small", "wine_rack", "jukebox", "aspidistra", "sea_chest",
	"umbrella_stand", "crate_bottles", "keg_steel", "log_basket", "coal_scuttle", "bench"]
## Models whose front is local -Z (seats); the rest face +Z.
const FACES_BACK := ["armchair_wingback"]
const MAX_FURNITURE := 11


## A loose decor prop (PropLibrary.spawn) at `pos` on the floor or a surface, turned
## `rot_y` degrees. Named D<n> in build order, so names match on every peer. `pinned`
## freezes it until the physics knocks it loose (shelf bottles). `prefix` replaces "D" in
## the name (back-bar bottles are ShelfBottle<n>, which the physics test looks for).
func decor(prop_name: String, pos: Vector3, rot_y := 0.0, pinned := false, prefix := "D") -> RigidBody3D:
	if not PropLibrary.has(prop_name):
		return null
	var body := PropLibrary.spawn(prop_name, 0, Transform3D(Basis(Vector3.UP, deg_to_rad(rot_y)), pos))
	if body == null:
		return null
	if pinned:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
		body.set_meta("pinned", true)
	if _decor_root == null:
		_decor_root = Node3D.new()
		_decor_root.name = "Decor"
		world.add_child(_decor_root)
	body.name = "%s%d" % [prefix, _decor_count]
	_decor_count += 1
	_decor_root.add_child(body)
	return body


## Space that dress() mustn't put anything in (fixtures, walkways, landings).
func _keep_out(box: AABB) -> void:
	_keepouts.append(box.abs())


func _box_around(centre: Vector3, half: Vector3) -> AABB:
	return AABB(centre - half.abs(), half.abs() * 2.0)


## Dress the pub after the layout is built: pictures, mirrors and shelves on the walls and
## furniture stood against them, wherever there's room. Deterministic, so every peer
## builds the same pub.
func dress() -> void:
	if not PropLibrary.has("picture"):
		return
	var room: Rect2 = level.get("room") if level.get("room") != null else Rect2(-50, -50, 100, 100)
	var blocked := _obstacles()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(level.get("pub_id")) if level.get("pub_id") != null else "pub")
	var sides: Array[Dictionary] = []
	for w in walls_built:
		for s in [-1.0, 1.0]:
			var n := Vector3(0, 0, s) if w["along_x"] else Vector3(s, 0, 0)
			var mid := _wall_point(w, (float(w["a0"]) + float(w["a1"])) * 0.5, 0.0) + n * 0.6
			if room.grow(-0.05).has_point(Vector2(mid.x, mid.z)):
				sides.append({"wall": w, "n": n})
	# Furniture first (it needs the floor), then pictures above and around it.
	var furniture := FURNITURE.duplicate()
	var placed := 0
	for i in sides.size():
		var side: Dictionary = sides[(i * 7 + 3) % sides.size()]  # spread round the room
		placed += _furnish_wall(side, furniture, blocked, rng, room, MAX_FURNITURE - placed)
		if placed >= MAX_FURNITURE:
			break
	var used := {}
	for side in sides:
		_hang_pictures(side, used, blocked, rng, room)


## Where a point along a wall is: `a` along it, `y` up, on the wall's centre line.
func _wall_point(w: Dictionary, a: float, y: float) -> Vector3:
	var o: Vector3 = w["origin"]
	return Vector3(a, y, o.z) if w["along_x"] else Vector3(o.x, y, a)


func _obstacles() -> Array[AABB]:
	var out: Array[AABB] = []
	var wall_roots := walls_built.map(func(w): return w["root"])
	for cs in world.find_children("*", "CollisionShape3D", true, false):
		var shape := (cs as CollisionShape3D).shape
		if shape == null:
			continue
		var skip := false
		var p := cs.get_parent()
		while p != null and p != world:
			if p in wall_roots or p == _decor_root:
				skip = true
				break
			p = p.get_parent()
		if skip:
			continue
		var box: AABB = (cs as CollisionShape3D).global_transform * shape.get_debug_mesh().get_aabb()
		if box.end.y <= 0.02:
			continue  # the floor
		out.append(box)
	for kind in [PubLevel.PLAYERS, PubLevel.PUNTER, PubLevel.STAFF, PubLevel.PROPS]:
		var parent := markers.get_node_or_null(kind)
		if parent == null:
			continue
		for m in parent.get_children():
			var r := 0.5 if kind == PubLevel.PROPS else 0.75
			out.append(AABB((m as Node3D).position - Vector3(r, 0.0, r), Vector3(r * 2.0, 1.9, r * 2.0)))
	for kind in [PubLevel.DOORS, PubLevel.POLICE]:
		var parent := markers.get_node_or_null(kind)
		if parent == null:
			continue
		for m in parent.get_children():
			var inside: Vector3 = m.get_meta("inside", (m as Node3D).position)
			out.append(_box_around(inside + Vector3(0, 1.0, 0), Vector3(1.2, 1.0, 1.2)))
	var zones := markers.get_node_or_null(PubLevel.BAR_ZONES)
	if zones != null:
		for z in zones.get_children():
			for cs in z.get_children():
				if cs is CollisionShape3D:
					out.append((cs as CollisionShape3D).global_transform * cs.shape.get_debug_mesh().get_aabb())
	# Doorways: keep a clear run in and out.
	for w in walls_built:
		for op in w["openings"]:
			var kind: String = op.get("kind", "door")
			if kind == "door" or kind == "arch":
				var c := _wall_point(w, float(op["c"]), 1.0)
				var half := Vector3(float(op["w"]) * 0.5 + 0.4, 1.1, 1.8) if w["along_x"] else Vector3(1.8, 1.1, float(op["w"]) * 0.5 + 0.4)
				out.append(_box_around(c, half))
	out.append_array(_keepouts)
	return out


func _clear(box: AABB, blocked: Array[AABB]) -> bool:
	for b in blocked:
		if b.intersects(box):
			return false
	return true


## True if `box` (spanning a0..a1 along the wall, y0..y1 up) runs into a door or window.
func _hits_opening(w: Dictionary, a0: float, a1: float, y0: float, y1: float) -> bool:
	for op in w["openings"]:
		var o0: float = float(op["c"]) - float(op["w"]) * 0.5 - 0.15
		var o1: float = float(op["c"]) + float(op["w"]) * 0.5 + 0.15
		var sill: float = op.get("sill", 0.0)
		var top: float = op.get("top", 2.1)
		if a1 > o0 and a0 < o1 and y1 > sill - 0.1 and y0 < top + 0.1:
			return true
	return false


func _footprint(w: Dictionary, n: Vector3, a0: float, a1: float, y0: float, y1: float, d0: float, d1: float) -> AABB:
	var face := _wall_point(w, 0.0, 0.0) + n * (WALL_THICKNESS * 0.5)
	var p0: Vector3
	var p1: Vector3
	if w["along_x"]:
		p0 = Vector3(a0, y0, face.z + n.z * d0)
		p1 = Vector3(a1, y1, face.z + n.z * d1)
	else:
		p0 = Vector3(face.x + n.x * d0, y0, a0)
		p1 = Vector3(face.x + n.x * d1, y1, a1)
	return AABB(p0, p1 - p0).abs()


func _inside(box: AABB, room: Rect2) -> bool:
	var r := room.grow(0.05)
	return r.has_point(Vector2(box.position.x, box.position.z)) and r.has_point(Vector2(box.end.x, box.end.z))


func _furnish_wall(side: Dictionary, pool: Array, blocked: Array[AABB], rng: RandomNumberGenerator, room: Rect2,
		budget: int) -> int:
	var w: Dictionary = side["wall"]
	var n: Vector3 = side["n"]
	var a := float(w["a0"]) + 0.35
	var placed := 0
	var tries := 0
	while a < float(w["a1"]) - 0.35 and placed < budget and not pool.is_empty() and tries < 60:
		tries += 1
		# The first few in the pool are the ones we most want; the rest are a lucky dip.
		var idx := 0 if rng.randf() < 0.5 else rng.randi() % pool.size()
		var pick: String = pool[idx]
		var m := PropLibrary.mesh(pick)
		if m == null:
			pool.remove_at(idx)
			continue
		var box := m.get_aabb()
		var flip := pick in FACES_BACK
		var width := box.size.x
		var back := -box.end.z if flip else box.position.z  # how far behind the origin the back is
		var depth := box.size.z
		var fp := _footprint(w, n, a, a + width, 0.0, box.size.y, 0.03, 0.03 + depth)
		if _inside(fp, room) and _clear(fp.grow(0.04), blocked) and not _hits_opening(w, a, a + width, 0.0, box.size.y):
			var face := _wall_point(w, a + width * 0.5 - box.get_center().x, 0.0) + n * (WALL_THICKNESS * 0.5 + 0.03 - back)
			var yaw := rad_to_deg(atan2(n.x, n.z)) + (180.0 if flip else 0.0)
			decor(pick, face, yaw)
			blocked.append(fp)
			pool.remove_at(idx)
			placed += 1
			if pick == "piano_upright":
				var stool_at := face + n * (depth + 0.3)
				var sb := _box_around(stool_at + Vector3(0, 0.25, 0), Vector3(0.35, 0.25, 0.35))
				if _clear(sb, blocked):
					decor("piano_stool", stool_at, yaw + rng.randf_range(-8.0, 8.0))
					blocked.append(sb)
			a += width + rng.randf_range(0.3, 1.4)
		else:
			a += 0.3
	return placed


func _hang_pictures(side: Dictionary, used: Dictionary, blocked: Array[AABB], rng: RandomNumberGenerator, room: Rect2) -> void:
	var w: Dictionary = side["wall"]
	var n: Vector3 = side["n"]
	var wall_top: float = w["height"]
	var ceiling: float = minf(wall_top, float(style["beam_height"]) if style.get("beams", false) else wall_top)
	var a := float(w["a0"]) + 0.5
	while a < float(w["a1"]) - 0.5:
		var pool := PICTURES.filter(func(p): return int(used.get(p, 0)) < int(PICTURE_LIMITS.get(p, 2)))
		if pool.is_empty():
			return
		var pick: String = pool[0] if rng.randf() < 0.4 else pool[rng.randi() % pool.size()]
		var d := PropLibrary.dims(pick)
		var width := d.x
		var hung := false
		# Ground floor, then any gallery or dais this bit of wall runs along.
		var floors := [0.0]
		var probe := _wall_point(w, a + width * 0.5, 0.0) + n * 0.6
		for pl in platforms_built:
			if (pl["rect"] as Rect2).grow(0.3).has_point(Vector2(probe.x, probe.z)):
				floors.append(float(pl["top"]))
		for floor_y in floors:
			var yc: float = floor_y + 1.55 + rng.randf_range(0.0, 0.25) + (0.3 if pick == "antlers" or pick == "wall_clock" else 0.0)
			var y0 := yc - d.y * 0.5
			var y1 := yc + d.y * 0.5
			var limit := ceiling if floor_y < 0.1 else wall_top
			if y1 > limit - 0.12 or (floor_y > 0.1 and y1 > wall_top - 0.1):
				continue
			var fp := _footprint(w, n, a, a + width, y0, y1, 0.0, maxf(d.z, 0.06) + 0.04)
			if not _inside(fp, room) or not _clear(fp.grow(0.05), blocked) or _hits_opening(w, a, a + width, y0, y1):
				continue
			var at := _wall_point(w, a + width * 0.5, yc) + n * (WALL_THICKNESS * 0.5 + 0.005)
			decor(pick, at, rad_to_deg(atan2(n.x, n.z)) + rng.randf_range(-1.5, 1.5))
			blocked.append(fp)
			used[pick] = int(used.get(pick, 0)) + 1
			hung = true
			break
		a += (width + rng.randf_range(0.6, 1.8)) if hung else 0.35
