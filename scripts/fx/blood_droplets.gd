class_name BloodDroplets
extends Node3D
## Fine blood that flies with the hit. Every droplet is a tiny ballistic body: it leaves the
## face along the punch at a speed set by how hard it landed, slows with air drag (fine mist
## slows fastest), falls under gravity and, where it actually lands (floor, wall, table, bar),
## leaves a small mark stretched along the way it was travelling. Shallow hits make long
## streaks, drops falling straight down make round dots.
##
## Purely cosmetic and cheap: droplets in flight and marks on surfaces are each one
## MultiMesh (two draw calls), and each droplet casts one short ray per physics frame.
## Lives under the current scene, so marks clear when the pub changes. Owned by BloodFx.

const GRAVITY := Vector3(0, -9.8, 0)
## World and props: what blood can land on. Fighters and ragdolls are ignored.
const SURFACE_MASK := 1 | 128
const MAX_AGE := 4.0

var max_drops := 900
var max_marks := 1600
## Drag per second for a 1 mm droplet; bigger drops get proportionally less.
var drag_mm := 3.0
## How big a mark is compared with the droplet that made it.
var mark_scale := 14.0
## Droplets in flight are drawn this much bigger than they are, or the camera (11 to 20 m
## away) would never see them.
var air_scale := 5.0

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _rad := PackedFloat32Array()
var _age := PackedFloat32Array()

var _air: MultiMeshInstance3D
var _marks: MultiMeshInstance3D
var _mark_next := 0
var _mark_total := 0
var _thrown_total := 0
var _landings := PackedVector3Array()  # last few landing points (tests, debugging)


func _init(drop_cap := 900, mark_cap := 1600) -> void:
	max_drops = drop_cap
	max_marks = mark_cap
	name = "BloodDroplets"


func _ready() -> void:
	var blood := StandardMaterial3D.new()
	blood.albedo_color = BloodFx.BLOOD_COLOR
	blood.roughness = 0.2
	blood.metallic_specular = 0.8
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 5
	sphere.rings = 3
	sphere.material = blood
	# No instance colours here: a MultiMesh with use_colors but no colours set draws nothing.
	_air = _multi("Air", sphere, max_drops, false)
	_air.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _mark_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2  # wet
	mat.metallic_specular = 0.45  # wet, but no sparkle at shallow angles
	mat.vertex_color_use_as_albedo = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plane.material = mat
	_marks = _multi("Marks", plane, max_marks, true)
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marks.multimesh.visible_instance_count = 0


## Throw `count` droplets from `origin`. `velocity` is the main direction and speed of the
## spray (metres/second); `spread` is the cone half-angle in degrees. Droplet radii are
## picked between `radius.x` and `radius.y` (metres), skewed towards the small end, and the
## smallest go fastest, as a fine mist does.
func emit(origin: Vector3, velocity: Vector3, count: int, radius: Vector2, spread := 25.0) -> void:
	var speed := velocity.length()
	if speed < 0.01 or count <= 0:
		return
	var axis := velocity / speed
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.1:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	for i in count:
		if _pos.size() >= max_drops:
			_remove(0)
		var t := pow(randf(), 2.2)  # mostly fine drops, the odd fat one
		var r := lerpf(radius.x, radius.y, t)
		# A random direction in the cone, denser near the middle.
		var ang := deg_to_rad(spread) * sqrt(randf())
		var roll := randf() * TAU
		var d := (axis * cos(ang) + (side * cos(roll) + up * sin(roll)) * sin(ang)).normalized()
		var s := speed * randf_range(0.55, 1.15) * lerpf(1.25, 0.7, t)
		_pos.append(origin + d * randf_range(0.0, 0.05))
		_vel.append(d * s)
		_rad.append(r)
		_age.append(0.0)
	_thrown_total += count


func drops_in_flight() -> int:
	return _pos.size()


## Marks ever left (not capped), so tests can see blood landing.
func marks_left() -> int:
	return _mark_total


## Droplets ever thrown.
func drops_thrown() -> int:
	return _thrown_total


## Where the last `n` droplets landed (newest last).
func recent_landings(n: int) -> PackedVector3Array:
	return _landings.slice(maxi(0, _landings.size() - n))


func _physics_process(delta: float) -> void:
	if not _pos.is_empty() and BloodFx.level() <= 0:
		_pos.clear(); _vel.clear(); _rad.clear(); _age.clear()  # blood switched off mid-spray
	if _pos.is_empty():
		_air.multimesh.visible_instance_count = 0
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = SURFACE_MASK
	q.hit_back_faces = false
	var i := 0
	while i < _pos.size():
		var r := _rad[i]
		var v := _vel[i]
		v += GRAVITY * delta
		v *= maxf(0.0, 1.0 - drag_mm * 0.001 / maxf(r, 0.0005) * delta)
		var from := _pos[i]
		var to := from + v * delta
		q.from = from
		q.to = to
		var hit := space.intersect_ray(q)
		_age[i] += delta
		if not hit.is_empty():
			_land(hit["position"], hit["normal"], v, r)
			_remove(i)
			continue
		if _age[i] > MAX_AGE:
			_remove(i)
			continue
		_pos[i] = to
		_vel[i] = v
		i += 1
	_draw_air()


func _land(at: Vector3, normal: Vector3, v: Vector3, r: float) -> void:
	var n := normal.normalized()
	var speed := v.length()
	var along := v - n * v.dot(n)  # travel across the surface
	# Hitting at a shallow angle stretches the mark into a streak.
	var cos_in := absf(v.dot(n)) / maxf(speed, 0.001)
	var stretch := clampf(1.0 / maxf(cos_in, 0.3), 1.0, 3.0)
	var size := r * mark_scale * clampf(0.8 + speed * 0.06, 0.8, 1.5)
	var z := along.normalized() if along.length() > 0.01 else n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD).normalized()
	var x := n.cross(z).normalized()
	z = x.cross(n).normalized()
	var basis := Basis(x * size, n, z * size * stretch)
	# Nudge it forward along the streak (the blob sits at the far end) and off the surface.
	var origin := at + n * (0.004 + randf() * 0.004) + z * size * (stretch - 1.0) * 0.3
	var mm := _marks.multimesh
	mm.set_instance_transform(_mark_next, Transform3D(basis, origin))
	var shade := randf_range(0.75, 1.0)
	mm.set_instance_color(_mark_next, Color(shade, shade, shade, 1.0))
	_mark_next = (_mark_next + 1) % max_marks
	_mark_total += 1
	_landings.append(at)
	if _landings.size() > 512:
		_landings = _landings.slice(256)
	mm.visible_instance_count = mini(_mark_total, max_marks)


func _draw_air() -> void:
	var mm := _air.multimesh
	var n := _pos.size()
	mm.visible_instance_count = n
	for i in n:
		var v := _vel[i]
		var r := _rad[i] * 2.0 * air_scale
		var speed := v.length()
		var basis := Basis.from_scale(Vector3(r, r, r))
		if speed > 0.5:
			# Stretched along its path, as a fast drop looks.
			var z := v / speed
			var x := z.cross(Vector3.UP)
			if x.length() < 0.1:
				x = z.cross(Vector3.RIGHT)
			x = x.normalized()
			var y := z.cross(x).normalized()
			basis = Basis(x * r, y * r, z * r * clampf(1.0 + speed * 0.25, 1.0, 3.0))
		mm.set_instance_transform(i, Transform3D(basis, _pos[i]))


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_rad[i] = _rad[last]
	_age[i] = _age[last]
	_pos.resize(last)
	_vel.resize(last)
	_rad.resize(last)
	_age.resize(last)


func _multi(node_name: String, mesh: Mesh, count: int, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	add_child(mi)
	return mi


## One droplet mark: a round blob with a tail of tiny satellite dots ahead of it (+Y in the
## texture, which maps to the direction of travel).
static func _mark_texture() -> ImageTexture:
	const N := 48
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var blobs: Array[Vector3] = [Vector3(0.5, 0.42, 0.2)]
	for i in 6:
		blobs.append(Vector3(0.5 + rng.randf_range(-0.07, 0.07), 0.62 + i * 0.05, rng.randf_range(0.02, 0.05)))
	for i in 5:
		var a := rng.randf() * TAU
		blobs.append(Vector3(0.5 + cos(a) * 0.3, 0.45 + sin(a) * 0.3, rng.randf_range(0.012, 0.028)))
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := BloodFx.BLOOD_COLOR
	for y in N:
		for x in N:
			var u := (x + 0.5) / N
			var v := (y + 0.5) / N
			var field := 0.0
			for b in blobs:
				var dx := u - b.x
				var dy := v - b.y
				field += (b.z * b.z) / maxf(dx * dx + dy * dy, 0.00001)
			var a := clampf((field - 1.0) * 2.5, 0.0, 1.0)
			var dark := clampf(field * 0.1, 0.0, 0.3)
			img.set_pixel(x, y, Color(c.r + 0.1 - dark * 0.5, c.g + 0.01, c.b + 0.01, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
