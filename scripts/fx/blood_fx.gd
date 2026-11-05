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
@export var spray_drops := 26
@export var spray_speed := Vector2(1.8, 4.2)
@export var drop_radius := 0.03
@export var face_decal_size := 0.55
@export var floor_splat_size := Vector2(0.25, 0.6)

var _decals: Array = []  # untyped: entries may already be freed
var _textures := {}
var _drop_mesh: SphereMesh


func _ready() -> void:
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = drop_radius
	_drop_mesh.height = drop_radius * 2.0
	_drop_mesh.radial_segments = 6
	_drop_mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOOD_COLOR
	mat.roughness = 0.25
	mat.metallic_specular = 0.8
	_drop_mesh.material = mat
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
	return _decals.size()


## A spray of droplets from `pos`, mostly along `dir`. `intensity` 0..2.
## Droplets land as floor splats a moment later.
func spray(pos: Vector3, dir: Vector3, intensity: float) -> void:
	if not enabled() or intensity <= 0.0:
		return
	var parent := _scene()
	if parent == null:
		return
	var extra := 1.6 if level() >= 2 else 1.0
	var p := CPUParticles3D.new()
	p.emitting = false  # emit only once it is in place, or the first drops spawn at the origin
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(4, int(spray_drops * intensity * extra))
	p.lifetime = 0.6  # roughly when the drops reach the floor (they don't collide)
	p.mesh = _drop_mesh
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	p.direction = (d + Vector3.UP * 0.6).normalized()
	p.spread = 28.0
	p.initial_velocity_min = spray_speed.x * (0.7 + intensity * 0.3)
	p.initial_velocity_max = spray_speed.y * (0.7 + intensity * 0.3)
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.8
	p.damping_min = 0.5
	p.damping_max = 1.5
	parent.add_child(p)
	p.global_position = pos
	p.restart()
	get_tree().create_timer(p.lifetime + 0.5, false).timeout.connect(p.queue_free)
	# Where the drops roughly land: a few splats along the spray direction.
	var flat := Vector3(d.x, 0.0, d.z).normalized()
	var splats := clampi(int(round(intensity * 2.0 * extra)), 1, 6)
	for i in splats:
		var at := pos + flat * randf_range(0.3, 1.4) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		var size := randf_range(floor_splat_size.x, floor_splat_size.y) * (0.6 + 0.3 * intensity)
		_later(randf_range(0.25, 0.45), floor_decal.bind(at, size, "splat"))


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


func _later(seconds: float, fn: Callable) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(fn)


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
