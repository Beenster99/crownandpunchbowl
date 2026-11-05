class_name OccluderFader
extends Node
## Fades walls, beams and anything else in the `camera_occluders` group when it sits
## between the camera and a player, so the fight is never hidden.
##
## Each occluder's world-space bounding box is tested against line segments from the
## camera to a few points on every target (feet, chest, head). Hit occluders fade
## towards `faded_alpha`. Meshes with a BaseMaterial3D override get a see-through copy
## of it while faded (works on every renderer); anything else falls back to
## GeometryInstance3D.transparency.
## Occluders added later (spawned props, doors) are picked up automatically.

@export var camera: BrawlCamera
## How see-through a faded occluder gets (0 = invisible, 1 = solid).
@export var faded_alpha := 0.18
@export var fade_speed := 6.0
## Extra space round each box, so walls start to fade just before they cover someone.
@export var margin := 0.35
## Heights on each target that must stay visible.
@export var sample_heights: PackedFloat32Array = PackedFloat32Array([0.2, 1.0, 1.75])
## How often (seconds) to rebuild the occluder cache. Movement is rare, so this is slow.
@export var refresh_interval := 1.0

## occluder Node3D -> {"meshes": Array, "originals": Array, "faded": Dictionary, "aabb": AABB, "alpha": float}
var _occluders := {}
var _refresh_timer := 0.0


func _ready() -> void:
	refresh()


func refresh() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group("camera_occluders"):
		var n := node as Node3D
		if n == null or not n.is_inside_tree():
			continue
		seen[n] = true
		var meshes := _collect_meshes(n)
		if meshes.is_empty():
			continue
		var aabb := _world_aabb(meshes).grow(margin)
		if _occluders.has(n) and (_occluders[n]["meshes"] as Array).size() == meshes.size():
			_occluders[n]["aabb"] = aabb
			continue
		if _occluders.has(n):
			_apply(_occluders[n], 1.0)
		var originals := []
		for m in meshes:
			originals.append((m as GeometryInstance3D).material_override)
		_occluders[n] = {"meshes": meshes, "originals": originals, "faded": {}, "aabb": aabb, "alpha": 1.0}
	for n in _occluders.keys():
		if not seen.has(n):
			_occluders.erase(n)


## True if `node` is currently faded (for tests and debugging).
func is_faded(node: Node3D) -> bool:
	return _occluders.has(node) and float(_occluders[node]["alpha"]) < 0.5


func is_blocking(node: Node3D) -> bool:
	if not _occluders.has(node) or camera == null:
		return false
	return _blocks(_occluders[node]["aabb"], camera.global_position, _target_points())


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = refresh_interval
		refresh()
	if camera == null:
		return
	var eye := camera.global_position
	var points := _target_points()
	var step := clampf(fade_speed * delta, 0.0, 1.0)
	for n in _occluders.keys():
		if not is_instance_valid(n):
			_occluders.erase(n)
			continue
		var entry: Dictionary = _occluders[n]
		var want := faded_alpha if _blocks(entry["aabb"], eye, points) else 1.0
		var alpha := lerpf(float(entry["alpha"]), want, step)
		if absf(alpha - want) < 0.01:
			alpha = want
		if alpha == float(entry["alpha"]):
			continue
		_apply(entry, alpha)


func _apply(entry: Dictionary, alpha: float) -> void:
	entry["alpha"] = alpha
	var meshes: Array = entry["meshes"]
	var faded: Dictionary = entry["faded"]
	for i in meshes.size():
		var g := meshes[i] as GeometryInstance3D
		if not is_instance_valid(g):
			continue
		var original := entry["originals"][i] as BaseMaterial3D
		if original == null:
			g.transparency = 1.0 - alpha
			continue
		if alpha >= 0.999:
			g.material_override = original
			continue
		if not faded.has(original):
			var copy := original.duplicate() as BaseMaterial3D
			copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			faded[original] = copy
		var mat: BaseMaterial3D = faded[original]
		mat.albedo_color.a = original.albedo_color.a * alpha
		g.material_override = mat


func _target_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	if camera == null:
		return pts
	for t in camera.targets:
		if not is_instance_valid(t) or not t.is_inside_tree():
			continue
		for h in sample_heights:
			pts.append(t.global_position + Vector3(0, h, 0))
	return pts


func _blocks(box: AABB, eye: Vector3, points: PackedVector3Array) -> bool:
	if box.has_point(eye):
		return true
	for p in points:
		if box.has_point(p):
			# A target standing inside the box (e.g. a doorway frame) doesn't count.
			continue
		if box.intersects_segment(eye, p):
			return true
	return false


func _collect_meshes(n: Node) -> Array:
	var out := []
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _world_aabb(meshes: Array) -> AABB:
	var box := AABB()
	var first := true
	for m in meshes:
		var g := m as VisualInstance3D
		var b := g.global_transform * g.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box
