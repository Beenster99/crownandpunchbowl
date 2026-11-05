class_name ChatterBubble
extends Label3D
## Speech bubble over a chatting NPC's head. Added on demand by Chatter, one per NPC.
## Billboarded, drawn on top, fades in and out.

const FADE := 0.25

var _t := 0.0
var _hold := 0.0


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = false
	pixel_size = 0.0045
	font_size = 34
	outline_size = 12
	outline_modulate = Color(0.08, 0.06, 0.05, 0.9)
	modulate = Color(1.0, 0.97, 0.88, 0.0)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	width = 520.0
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	position = Vector3(0.0, 2.15, 0.0)
	render_priority = 10
	visible = false


func show_line(line: String, seconds: float) -> void:
	text = "“%s”" % line
	_hold = seconds
	_t = 0.0
	visible = true


func hide_line() -> void:
	_hold = minf(_hold, _t)


func is_showing() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var a := minf(_t / FADE, 1.0) * clampf((_hold + FADE - _t) / FADE, 0.0, 1.0)
	modulate.a = a
	if _t >= _hold + FADE:
		visible = false
