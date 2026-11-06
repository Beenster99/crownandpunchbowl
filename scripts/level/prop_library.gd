class_name PropLibrary
extends RefCounted
## The pub prop models: every variant of every kind of prop, built in Blender by
## tools/blender/build_props.py into assets/models/props/<category>.glb, with a catalogue
## (catalogue.json) of each variant's item kind and physics.
##
## Kinds match ItemData kinds and prop marker kinds where they exist (table, chair, stool,
## glass, pint, bottle, broken_bottle, food, plate, pool_cue, broken_cue, darts, poker,
## fire_tongs, coal_shovel, chair_leg, table_leg) plus decor kinds (decor_glass,
## decor_bottle, decor_small, snack, picture, furniture, piano, dartboard, pool_table).
## Every variant can also be asked for by its own name ("chair_windsor").
##
## Models sit with their origin on the floor at their centre. Wall pieces (pictures,
## the dartboard) have their back on the wall at local z = 0 and face +Z. Seats face -Z.
##
## The physics workstream builds bodies from visual(), shape() and mass(); spawn() makes a
## ready-to-go RigidBody3D for loose decor.

const DIR := "res://assets/models/props/"
const CATALOGUE := DIR + "catalogue.json"
const GROUP := &"pub_props"
## Collision layers (see project.godot): world 1, items 8 (layer 4), props 128 (layer 8).
const LAYER_WORLD := 1
const LAYER_ITEMS := 8
const LAYER_PROPS := 128
const PROP_MASK := LAYER_WORLD | LAYER_ITEMS | LAYER_PROPS
## Marker kinds that are spelt differently from the model kinds.
const ALIASES := {"fire_shovel": "coal_shovel"}

static var _entries := {}            # variant name -> catalogue entry
static var _by_kind := {}            # kind -> PackedStringArray of variant names (sorted)
static var _meshes := {}             # variant name -> Mesh with materials applied
static var _shapes := {}             # variant name -> Shape3D
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CATALOGUE):
		push_warning("PropLibrary: no catalogue at %s" % CATALOGUE)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
	if typeof(data) != TYPE_DICTIONARY:
		return
	_entries = data
	var names: Array = _entries.keys()
	names.sort()
	for n in names:
		var k: String = _entries[n]["kind"]
		if not _by_kind.has(k):
			_by_kind[k] = PackedStringArray()
		_by_kind[k].append(n)


static func _kind(kind: String) -> String:
	return ALIASES.get(kind, kind)


## True if there's a model for this kind or variant name.
static func has(kind_or_name: String) -> bool:
	_load()
	var k := _kind(kind_or_name)
	return _by_kind.has(k) or _entries.has(k)


## Variant names of a kind, in a stable order.
static func variants(kind: String) -> PackedStringArray:
	_load()
	return _by_kind.get(_kind(kind), PackedStringArray())


static func kinds() -> PackedStringArray:
	_load()
	var out := PackedStringArray(_by_kind.keys())
	out.sort()
	return out


## Resolve `variant` to a variant name. `variant` can be a variant name, an int (an index
## or any seed, wrapped round), or a Vector3 position (hashed, so the same spot always
## gets the same look on every peer). A variant name passed as `kind` wins.
static func resolve(kind: String, variant: Variant = 0) -> String:
	_load()
	var k := _kind(kind)
	if _entries.has(k):
		return k
	if typeof(variant) == TYPE_STRING or typeof(variant) == TYPE_STRING_NAME:
		if _entries.has(String(variant)):
			return String(variant)
		variant = 0
	var list: PackedStringArray = _by_kind.get(k, PackedStringArray())
	if list.is_empty():
		return ""
	var i := 0
	if typeof(variant) == TYPE_VECTOR3:
		i = seed_for(variant)
	elif typeof(variant) == TYPE_INT:
		i = variant
	return list[posmod(i, list.size())]


## Deterministic seed from a position (rounded to centimetres so peers agree).
static func seed_for(pos: Vector3) -> int:
	return absi(hash(Vector3i(roundi(pos.x * 100.0), roundi(pos.y * 100.0), roundi(pos.z * 100.0))))


## Catalogue entry: category, kind, mass, shape, fragile, pinned, size, dims (Godot x, y, z).
static func info(kind: String, variant: Variant = 0) -> Dictionary:
	var n := resolve(kind, variant)
	return _entries.get(n, {})


static func mass(kind: String, variant: Variant = 0) -> float:
	return float(info(kind, variant).get("mass", 1.0))


## Size in metres (x, y, z) of a variant.
static func dims(kind: String, variant: Variant = 0) -> Vector3:
	var d: Array = info(kind, variant).get("dims", [0.2, 0.2, 0.2])
	return Vector3(d[0], d[1], d[2])


## The variant's mesh, shared between every copy (materials applied).
static func mesh(kind: String, variant: Variant = 0) -> Mesh:
	var n := resolve(kind, variant)
	if n == "":
		return null
	if not _meshes.has(n):
		_load_category(String(_entries[n]["category"]))
	return _meshes.get(n)


## A new MeshInstance3D of the variant, named "Model". Null if there's no model.
static func visual(kind: String, variant: Variant = 0) -> MeshInstance3D:
	var m := mesh(kind, variant)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = m
	var n := resolve(kind, variant)
	if bool(_entries[n].get("size", "") == "small"):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 30.0  # tiny things vanish when the camera is far out
	return mi


## A new CollisionShape3D for the variant, positioned for a body whose origin is the
## model's origin. Shapes: "box" and "cyl" fit the model's bounds, "convex" is a hull.
static func shape(kind: String, variant: Variant = 0) -> CollisionShape3D:
	var n := resolve(kind, variant)
	if n == "":
		return null
	var m := mesh(n)
	if m == null:
		return null
	var aabb := m.get_aabb()
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	if not _shapes.has(n):
		var kind_of: String = _entries[n].get("shape", "box")
		match kind_of:
			"convex":
				_shapes[n] = m.create_convex_shape(true, true)
			"cyl":
				var c := CylinderShape3D.new()
				c.radius = maxf(aabb.size.x, aabb.size.z) * 0.5
				c.height = maxf(aabb.size.y, 0.02)
				_shapes[n] = c
			_:
				var b := BoxShape3D.new()
				b.size = aabb.size.max(Vector3.ONE * 0.02)
				_shapes[n] = b
	cs.shape = _shapes[n]
	if not cs.shape is ConvexPolygonShape3D:
		cs.position = aabb.get_center()
	return cs


## A loose decor prop as a RigidBody3D, in group "pub_props". Sleeps until something hits
## it. Pinned props (pictures, mirrors, shelves) start frozen with meta "pinned"; the
## physics workstream knocks them loose. Fragile ones have meta "fragile". Big props
## block fighters (world | props layers), small ones only collide as props.
## Give it a name that is the same on every peer before adding it to the tree.
static func spawn(kind: String, variant: Variant = 0, xform := Transform3D.IDENTITY) -> RigidBody3D:
	var n := resolve(kind, variant)
	var e := info(n)
	if e.is_empty():
		return null
	var body := RigidBody3D.new()
	body.transform = xform
	body.mass = maxf(float(e.get("mass", 1.0)), 0.05)
	body.collision_layer = (LAYER_WORLD | LAYER_PROPS) if e.get("size", "") == "big" else LAYER_PROPS
	body.collision_mask = PROP_MASK
	body.can_sleep = true
	body.sleeping = true
	body.continuous_cd = float(e.get("mass", 1.0)) < 1.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05 if bool(e.get("fragile", false)) else 0.15
	body.physics_material_override = pm
	body.add_to_group(GROUP)
	body.set_meta("prop", n)
	body.set_meta("kind", String(e.get("kind", "")))
	body.set_meta("fragile", bool(e.get("fragile", false)))
	body.set_meta("pinned", bool(e.get("pinned", false)))
	if bool(e.get("pinned", false)):
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.freeze = true
	var vis := visual(n)
	if vis != null:
		body.add_child(vis)
	var cs := shape(n)
	if cs != null:
		body.add_child(cs)
	return body


static func _load_category(cat: String) -> void:
	var path := DIR + cat + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("PropLibrary: missing %s" % path)
		return
	var scene := (load(path) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var n := String(mi.name)
		if not _entries.has(n):
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat != null and mat.resource_name.begins_with("M_"):
				var lib := PubMaterials.named(mat.resource_name)
				if lib != null:
					m.surface_set_material(s, lib)
			elif mat is BaseMaterial3D and mat.resource_name.begins_with("T_"):
				(mat as BaseMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_meshes[n] = m
	scene.free()
