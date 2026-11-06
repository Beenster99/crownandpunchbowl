class_name WoundSkin
extends Node
## Draws a fighter's Wounds on their character: bruises, swelling and cuts on the skin.
##
## The character's "Body" mesh (head and body skin, one surface) gets a copy with each
## vertex's rest position in CUSTOM0, and its skin material gets wounds.gdshader as a
## next pass. The shader marks the skin around each spot and pushes swollen skin out, in
## rest-pose space, so the marks ride along with the bones, the head snap and the ragdoll.
##
## Spots are found on each model by aiming rays out from the head (and chest) at the skin,
## so they land on the brow, the cheekbone or the lip of any look. Both the patched mesh
## and the spot positions are cached per model and shared by every fighter wearing it.
## Works in Forward+ and Compatibility (no decals needed). Cosmetic only.

const SHADER := preload("res://scripts/fx/wounds.gdshader")
const MESH_NAME := "Body"

static var _mesh_cache := {}   # original mesh -> patched mesh
static var _spot_cache := {}   # original mesh -> Array of [pos, out, cut_dir]

var wounds: Node
var rig: Node
var material: ShaderMaterial
var _body: MeshInstance3D
var _skin_mat: Material
var _spots: Array = []
var _dirty := true
var _aging := false


func setup(w: Node, r: Node) -> void:
	wounds = w
	rig = r


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 1
	wounds.changed.connect(func(_i): _dirty = true)


func _exit_tree() -> void:
	if _skin_mat != null and _skin_mat.next_pass == material:
		_skin_mat.next_pass = null


func _process(_delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var sk: Skeleton3D = rig.get("skeleton")
	if sk == null:
		return
	# The rig can rebuild (a new look): patch the new body when it does.
	var body := sk.get_node_or_null(MESH_NAME) as MeshInstance3D
	if body != _body:
		_patch(body, sk)
	if _body == null:
		return
	if _dirty:
		_dirty = false
		_upload()
	elif _aging:
		_upload_ages()


## The model-space (rest pose) centre of a spot on this character, for tests and tools.
func spot_position(id: StringName) -> Vector3:
	var i := Wounds.spot_index(id)
	return _spots[i][0] if i >= 0 and i < _spots.size() else Vector3.ZERO


func is_showing() -> bool:
	return _skin_mat != null and _skin_mat.next_pass == material


# --- Building ------------------------------------------------------------------------

func _patch(body: MeshInstance3D, sk: Skeleton3D) -> void:
	_body = body
	_skin_mat = null
	_spots = []
	if body == null or body.mesh == null:
		return
	var src := body.mesh
	if src.has_meta("wound_source"):
		src = src.get_meta("wound_source")
	if not _mesh_cache.has(src):
		_mesh_cache[src] = _with_rest_positions(src)
		_spot_cache[src] = _find_spots(src, sk)
	var overrides := []
	for i in body.get_surface_override_material_count():
		overrides.append(body.get_surface_override_material(i))
	body.mesh = _mesh_cache[src]
	for i in overrides.size():
		body.set_surface_override_material(i, overrides[i])
	_spots = _spot_cache[src]
	_skin_mat = body.get_surface_override_material(0)
	if _skin_mat == null:
		_skin_mat = body.mesh.surface_get_material(0)
	if _skin_mat is BaseMaterial3D:
		var bm := _skin_mat as BaseMaterial3D
		material.set_shader_parameter("skin_tint", bm.albedo_color)
		material.set_shader_parameter("use_texture", bm.albedo_texture != null)
		if bm.albedo_texture != null:
			material.set_shader_parameter("skin_texture", bm.albedo_texture)
	_dirty = true


## A copy of `src` with every vertex's position also stored in CUSTOM0.
static func _with_rest_positions(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var rest := PackedFloat32Array()
		rest.resize(verts.size() * 4)
		for i in verts.size():
			rest[i * 4] = verts[i].x
			rest[i * 4 + 1] = verts[i].y
			rest[i * 4 + 2] = verts[i].z
		arrays[Mesh.ARRAY_CUSTOM0] = rest
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		if src is ArrayMesh:
			flags |= (src as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		if src is ArrayMesh:
			out.surface_set_name(s, (src as ArrayMesh).surface_get_name(s))
	out.set_meta("wound_source", src)
	return out


## Where each spot sits on this model: [position, outward normal, cut direction].
static func _find_spots(src: Mesh, sk: Skeleton3D) -> Array:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var head := _bone(sk, &"Head", Vector3(0, 1.63, -0.1))
	var brow := (_bone(sk, &"BrowL", Vector3(0, 1.73, -0.2)) + _bone(sk, &"BrowR", Vector3(0, 1.73, -0.2))) * 0.5
	var chest := _bone(sk, &"Chest", Vector3(0, 1.2, 0.0))
	# Level with the eyes when the model has them (they're a separate mesh), else under the brow.
	var eye_y := brow.y - 0.035
	var eyes := sk.get_node_or_null("Eyes") as MeshInstance3D
	if eyes != null and eyes.mesh != null:
		eye_y = eyes.mesh.get_aabb().get_center().y
	var face_o := Vector3(0.0, eye_y, head.z)
	var body_o := Vector3(0.0, chest.y + 0.03, chest.z)
	var out := []
	for spot in Wounds.SPOTS:
		var face: bool = spot["region"] == &"face"
		var o := face_o if face else body_o
		var yaw := deg_to_rad(float(spot["yaw"]))
		var pitch := deg_to_rad(float(spot["pitch"]))
		var d := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		var tol := 0.008 if face else 0.025
		var hit := -1
		for attempt in 3:
			hit = _ray_to_skin(verts, o, d, tol)
			if hit >= 0:
				break
			tol *= 2.0
		var pos := o + d * (0.1 if face else 0.15)
		var n := d
		if hit >= 0:
			pos = verts[hit]
			if hit < normals.size():
				n = normals[hit].normalized()
		var across := Vector3.UP.cross(n)
		across = across.normalized() if across.length() > 0.01 else Vector3.RIGHT
		var upward := n.cross(across).normalized()
		var a := deg_to_rad(float(spot["cut_angle"]))
		out.append([pos, n, (across * cos(a) + upward * sin(a)).normalized()])
	return out


## The outermost vertex within `tol` of the ray: where it comes out through the skin.
static func _ray_to_skin(verts: PackedVector3Array, o: Vector3, d: Vector3, tol: float) -> int:
	var best := -1
	var far := 0.0
	var tol2 := tol * tol
	for i in verts.size():
		var v := verts[i] - o
		var along := v.dot(d)
		if along <= far:
			continue
		if (v - d * along).length_squared() < tol2:
			far = along
			best = i
	return best


static func _bone(sk: Skeleton3D, bone: StringName, fallback: Vector3) -> Vector3:
	var i := sk.find_bone(bone)
	return sk.get_bone_global_rest(i).origin if i >= 0 else fallback


# --- Uniforms ------------------------------------------------------------------------

func _upload() -> void:
	if _skin_mat == null or _spots.is_empty():
		return
	var marked: bool = wounds.is_marked()
	if not marked:
		if _skin_mat.next_pass == material:
			_skin_mat.next_pass = null
		_aging = false
		return
	var pos: Array[Vector4] = []
	var dmg: Array[Vector4] = []
	var cuts: Array[Vector4] = []
	var outs: Array[Vector4] = []
	for i in Wounds.SPOTS.size():
		var s: Dictionary = Wounds.SPOTS[i]
		var r := float(s["radius"])
		var p: Vector3 = _spots[i][0]
		var n: Vector3 = _spots[i][1]
		var c: Vector3 = _spots[i][2]
		var face: bool = s["region"] == &"face"
		pos.append(Vector4(p.x, p.y, p.z, r))
		dmg.append(Vector4(wounds.bruise[i], wounds.swell[i], wounds.cut[i], wounds.age[i]))
		cuts.append(Vector4(c.x, c.y, c.z, r * 0.45))
		# How far a fully swollen spot stands out, as a share of its radius.
		var puff := 0.12
		if face:
			puff = 0.26 if String(s["id"]).begins_with("eye") else 0.28
		outs.append(Vector4(n.x, n.y, n.z, puff))
	material.set_shader_parameter("spot_count", Wounds.SPOTS.size())
	material.set_shader_parameter("spot_pos", pos)
	material.set_shader_parameter("spot_dmg", dmg)
	material.set_shader_parameter("spot_cut", cuts)
	material.set_shader_parameter("spot_out", outs)
	material.set_shader_parameter("blood", 1.0 if _blood_on() else 0.0)
	if _skin_mat.next_pass != material:
		_skin_mat.next_pass = material
	_aging = true


## Bruises colour up over the first half minute: keep the ages moving until then.
func _upload_ages() -> void:
	var still := false
	var dmg: Array[Vector4] = []
	for i in Wounds.SPOTS.size():
		var a: float = wounds.age[i]
		if a > 0.0 and a < 30.0:
			still = true
		dmg.append(Vector4(wounds.bruise[i], wounds.swell[i], wounds.cut[i], a))
	material.set_shader_parameter("spot_dmg", dmg)
	_aging = still


func _blood_on() -> bool:
	var settings := get_node_or_null("/root/Settings")
	if settings == null or not settings.has_method("get_value"):
		return true
	return int(settings.get_value("gameplay", "blood")) > 0
