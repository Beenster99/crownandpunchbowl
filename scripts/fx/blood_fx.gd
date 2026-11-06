class_name BloodFx
extends Node
## Cosmetic blood: sprays, floor splats and smears, pools under knocked-out bodies and
## bloody faces. Owned by the FX director. Purely visual, never touches gameplay.
##
## Respects Settings gameplay/blood: 0 = off, 1 = normal, 2 = extra (more spray,
## more floor decals, slower clean-up).
## Floor decals live under the current scene, so they clear when the pub changes.

const BLOOD_COLOR := Color(0.42, 0.015, 0.02)
const FACE_DECAL_NAME := "FxFaceBlood"

@export var max_floor_decals := 140
@export var spray_drops := 40
## Spray speed (m/s) for the lightest and the hardest hits.
@export var spray_speed := Vector2(2.5, 9.0)
@export var spray_spread := 28.0
@export var drop_radius := 0.03  ## the biggest spray droplet is about a third of this
@export var face_decal_size := 0.55
@export_group("Clean hit burst")
@export var mist_drops := 110  ## fine droplets off the face, per unit of intensity
@export var mist_radius := 0.011
@export var mist_spread := 24.0
@export var burst_drops := 14  ## heavier drops that carry further, per unit of intensity

var _decals: Array = []  # untyped: entries may already be freed
var _textures := {}
var _droplets: BloodDroplets


func _ready() -> void:
	_textures["splat"] = _make_texture(6, 0.2, 22, 1.0, 11)
	_textures["smear"] = _make_texture(5, 0.17, 6, 2.5, 23)
	_textures["pool"] = _make_texture(8, 0.22, 8, 1.0, 37)
	_textures["face"] = _make_texture(10, 0.15, 30, 1.0, 51)


static func level() -> int:
	return int(Settings.get_value("gameplay", "blood"))


func enabled() -> bool:
	return level() > 0


func decal_count() -> int:
	_decals = _decals.filter(func(d): return is_instance_valid(d))
	var fine := _droplets.marks_left() if is_instance_valid(_droplets) else 0
	return _decals.size() + fine


## A spray of droplets from `pos` along `dir`. `intensity` 0..2 sets how much blood,
## `force` (the move's knockback, roughly 0.5..4) how fast and far it flies; without it,
## intensity stands in. Droplets fly as real little bodies and mark where they land.
func spray(pos: Vector3, dir: Vector3, intensity: float, force := -1.0) -> void:
	if not enabled() or intensity <= 0.0:
		return
	var drops := droplets()
	if drops == null:
		return
	var extra := 1.6 if level() >= 2 else 1.0
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var f := force if force >= 0.0 else intensity * 1.5
	var v := (d + Vector3.UP * 0.35).normalized() * _speed(f)
	drops.emit(pos, v, maxi(4, int(spray_drops * intensity * extra)), Vector2(0.003, drop_radius * 0.3), spray_spread)


## A proper connect: a fine mist off the face, driven along the punch by its force, with a
## few heavier drops that carry further. `dir` is the way the punch went (it can lean up
## for an uppercut or across for a hook).
func face_burst(head: Vector3, dir: Vector3, intensity: float, force := -1.0) -> void:
	if not enabled() or intensity <= 0.0:
		return
	var drops := droplets()
	if drops == null:
		return
	var extra := 1.6 if level() >= 2 else 1.0
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var f := force if force >= 0.0 else intensity * 1.5
	var speed := _speed(f)
	var axis := (d + Vector3.UP * 0.2).normalized()
	# Fine mist: lots of tiny, fast drops in a tight cone.
	drops.emit(head, axis * speed * 1.15, maxi(12, int(mist_drops * intensity * extra)),
		Vector2(0.002, mist_radius * 0.45), mist_spread)
	# Heavier drops: fewer, slower, wider, and they fall sooner.
	drops.emit(head, (axis + Vector3.UP * 0.15).normalized() * speed * 0.75,
		maxi(4, int(burst_drops * intensity * extra)), Vector2(0.005, 0.01), mist_spread * 1.6)


func _speed(force: float) -> float:
	return lerpf(spray_speed.x, spray_speed.y, clampf(force / 4.0, 0.0, 1.0))


## The droplet simulator for the current pub (made on first use, cleared with the scene).
func droplets() -> BloodDroplets:
	var parent := _scene()
	if parent == null:
		return null
	if not is_instance_valid(_droplets) or _droplets.get_parent() != parent:
		var big := level() >= 2
		_droplets = BloodDroplets.new(1400 if big else 900, 3200 if big else 1600)
		parent.add_child(_droplets)
	return _droplets


## A flat blood mark on the floor below `pos`. Floors are flat, so these are textured quads
## rather than Decals: cheaper, and they render in every renderer (including Compatibility).
func floor_decal(pos: Vector3, size: float, kind := "splat", alpha := 1.0) -> MeshInstance3D:
	if not enabled():
		return null
	var parent := _scene()
	if parent == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = _floor_mesh(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transparency = 1.0 - clampf(alpha, 0.0, 1.0)
	parent.add_child(mi)
	# Tiny random lift so overlapping marks don't z-fight.
	mi.global_position = Vector3(pos.x, _floor_y(pos) + 0.006 + randf() * 0.008, pos.z)
	mi.rotation.y = randf() * TAU
	mi.scale = Vector3(size, 1.0, size * (2.2 if kind == "smear" else 1.0))
	_decals.append(mi)
	var cap := max_floor_decals * (2 if level() >= 2 else 1)
	while _decals.size() > cap:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return mi


## A smear pointing along `dir` (crawl trails).
func smear(pos: Vector3, dir: Vector3) -> void:
	var mark := floor_decal(pos, randf_range(0.25, 0.4), "smear", 0.85)
	if mark and dir.length() > 0.01:
		mark.rotation.y = atan2(dir.x, dir.z)


## A pool that spreads out under a knocked-out head.
func pool(pos: Vector3) -> void:
	var mark := floor_decal(pos, 0.2, "pool")
	if mark == null:
		return
	var final := randf_range(0.8, 1.3) * (1.3 if level() >= 2 else 1.0)
	var tw := mark.create_tween()
	tw.tween_property(mark, "scale", Vector3(final, 1.0, final), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Raise how bloody a fighter's face is (0..1). On Forward+/Mobile this projects a Decal onto
## the front of the head, so it works on the placeholder capsule now and on real character
## models later. The Compatibility renderer has no decals, so it gets a small quad instead.
func add_face_blood(fighter: Node, amount: float) -> void:
	if not enabled() or not is_instance_valid(fighter) or not (fighter is Node3D):
		return
	var f := fighter as Node3D
	var lvl := clampf(float(f.get_meta("fx_face_blood", 0.0)) + amount, 0.0, 1.0)
	f.set_meta("fx_face_blood", lvl)
	var node := f.get_node_or_null(FACE_DECAL_NAME) as Node3D
	var local_head := f.to_local(FxDirector.head_position(f))
	if node == null:
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			var quad := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1, 1)
			qm.material = _floor_mesh("face").material
			quad.mesh = qm
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			quad.rotation_degrees = Vector3(0, 180, 0)  # QuadMesh faces +Z; the face looks along -Z
			node = quad
		else:
			var dec := Decal.new()
			dec.texture_albedo = _textures["face"]
			dec.albedo_mix = 1.0
			dec.upper_fade = 0.2
			dec.lower_fade = 0.2
			dec.rotation_degrees = Vector3(-90, 0, 0)  # project along +Z, into the face
			node = dec
		node.name = FACE_DECAL_NAME
		f.add_child(node)
	var w := face_decal_size
	var h := face_decal_size * (0.8 + lvl * 0.6)
	if node is Decal:
		node.position = local_head + Vector3(0, -0.08, -0.28)
		(node as Decal).size = Vector3(w, 0.6, h)
		(node as Decal).modulate = Color(1, 1, 1, 0.25 + lvl * 0.75)
	else:
		node.position = local_head + Vector3(0, -0.08, -0.37)
		node.scale = Vector3(w * 0.7, h * 0.7, 1.0)
		(node as GeometryInstance3D).transparency = 0.75 - lvl * 0.75


func face_blood(fighter: Node) -> float:
	if fighter == null or not is_instance_valid(fighter):
		return 0.0
	return float(fighter.get_meta("fx_face_blood", 0.0))


func _floor_mesh(kind: String) -> PlaneMesh:
	var key := "mesh_" + kind
	if not _textures.has(key):
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _textures.get(kind, _textures["splat"])
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.2  # wet
		mat.metallic_specular = 0.7
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pm.material = mat
		_textures[key] = pm
	return _textures[key]


func _scene() -> Node:
	return get_tree().current_scene


func _floor_y(pos: Vector3) -> float:
	var world := get_viewport().find_world_3d()
	if world == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 4.0, 1)
	var hit := world.direct_space_state.intersect_ray(q)
	return float(hit["position"].y) if hit else 0.0


## Procedural blood texture: a few metaball blobs plus droplets, `stretch` elongates along Y.
func _make_texture(blobs: int, blob_size: float, drops: int, stretch: float, seed_value: int) -> ImageTexture:
	const N := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var centres: Array[Vector3] = []  # x, y, radius in 0..1 space
	for i in blobs:
		var r := blob_size * rng.randf_range(0.35, 1.0)
		centres.append(Vector3(0.5 + rng.randf_range(-0.18, 0.18), 0.5 + rng.randf_range(-0.18, 0.18), r))
	for i in drops:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.2, 0.46)
		centres.append(Vector3(0.5 + cos(ang) * dist, 0.5 + sin(ang) * dist, rng.randf_range(0.01, 0.045)))
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var u := float(x) / N
			var v := 0.5 + (float(y) / N - 0.5) * stretch
			var field := 0.0
			for c in centres:
				var dx := u - c.x
				var dy := v - c.y
				field += (c.z * c.z) / maxf(dx * dx + dy * dy, 0.00001)
			var edge := clampf((0.5 - Vector2(u - 0.5, float(y) / N - 0.5).length()) * 12.0, 0.0, 1.0)
			var a := clampf((field - 1.0) * 2.0, 0.0, 1.0) * edge
			var dark := clampf(field * 0.12, 0.0, 0.35)
			img.set_pixel(x, y, Color(BLOOD_COLOR.r - dark * 0.6, BLOOD_COLOR.g, BLOOD_COLOR.b, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
