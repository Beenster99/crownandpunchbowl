class_name FoeHealthBars
extends Node
## A subtle health bar on the floor under each punter squaring up to the local player (the
## one or two they're fighting), so you can see who's nearly done. It fades in when the
## fight starts, follows the punter, and fades out a moment after they leave the fight or
## go down for good. PlayerFighter adds one of these for the local player.

const WIDTH_PX := 70          ## bar size in texture pixels
const HEIGHT_PX := 5
const PIXEL_SIZE := 0.0008    ## world size per pixel at fixed screen size
const FADE := 3.0             ## alpha per second
const LINGER := 1.2           ## seconds a bar stays after the fight moves on
const BG := Color(0, 0, 0, 0.55)
const FILL := Color(0.86, 0.18, 0.14)
const FILL_LOW := Color(1.0, 0.55, 0.15)

var player: Fighter

var _bars := {}  # Fighter -> {"root": Node3D, "fill": Sprite3D, "bg": Sprite3D, "alpha": float, "seen": float}
static var _tex: ImageTexture


## Punters fighting the player right now.
func foes() -> Array[Fighter]:
	var out: Array[Fighter] = []
	if player == null or not player.is_inside_tree():
		return out
	for node in player.get_tree().get_nodes_in_group(Fighter.GROUP):
		var f := node as Fighter
		if f == null or f == player or f.is_ko() or not player.is_hostile_to(f):
			continue
		var engaged := f == player.stance_target
		if "mood" in f and "foe" in f:
			engaged = engaged or (int(f.get("mood")) == 2 and f.get("foe") == player)  # Npc.Mood.ENGAGED
		if engaged and f.global_position.distance_to(player.global_position) < 8.0:
			out.append(f)
	return out


## The bar node under `f`, or null.
func bar_for(f: Fighter) -> Node3D:
	return _bars[f]["root"] if _bars.has(f) and is_instance_valid(_bars[f]["root"]) else null


func _process(delta: float) -> void:
	var now := foes()
	for f in now:
		if not _bars.has(f) or not is_instance_valid(_bars[f]["root"]):
			_bars[f] = _make(f)
		_bars[f]["seen"] = LINGER
	for f in _bars.keys():
		var b: Dictionary = _bars[f]
		if not is_instance_valid(f) or not is_instance_valid(b["root"]):
			_bars.erase(f)
			continue
		var fighter := f as Fighter
		b["seen"] = float(b["seen"]) - delta
		var want := 1.0 if float(b["seen"]) > 0.0 and not fighter.is_ko() else 0.0
		b["alpha"] = move_toward(float(b["alpha"]), want, FADE * delta)
		var frac := fighter.hp_fraction()
		var fill: Sprite3D = b["fill"]
		fill.region_rect = Rect2(0, 0, maxf(WIDTH_PX * frac, 0.01), HEIGHT_PX)
		fill.modulate = (FILL_LOW if frac < 0.3 else FILL) * Color(1, 1, 1, float(b["alpha"]))
		(b["bg"] as Sprite3D).modulate = BG * Color(1, 1, 1, float(b["alpha"]))
		(b["root"] as Node3D).visible = float(b["alpha"]) > 0.01
		if float(b["alpha"]) <= 0.0 and want == 0.0:
			(b["root"] as Node3D).queue_free()
			_bars.erase(f)


func _exit_tree() -> void:
	for f in _bars:
		if is_instance_valid(_bars[f]["root"]):
			(_bars[f]["root"] as Node3D).queue_free()
	_bars.clear()


func _make(f: Fighter) -> Dictionary:
	if _tex == null:
		var img := Image.create(WIDTH_PX, HEIGHT_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_tex = ImageTexture.create_from_image(img)
	var root := Node3D.new()
	root.name = "FoeHealthBar"
	root.position = Vector3(0, 0.06, 0)  # just off the floor at his feet
	f.add_child(root)
	var bg := _sprite(0)
	var fill := _sprite(1)
	fill.region_enabled = true
	root.add_child(bg)
	root.add_child(fill)
	return {"root": root, "fill": fill, "bg": bg, "alpha": 0.0, "seen": LINGER}


func _sprite(priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _tex
	s.centered = false
	s.offset = Vector2(-WIDTH_PX * 0.5, 0.0)
	s.pixel_size = PIXEL_SIZE
	s.fixed_size = true
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Depth-tested, so a body in front hides it instead of it floating over them.
	s.shaded = false
	s.render_priority = 5 + priority
	s.modulate = Color(1, 1, 1, 0)
	return s
