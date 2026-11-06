class_name TalkUi
extends CanvasLayer
## The little bits of screen push-to-talk needs: a "Listening..." light while the key is held,
## a line showing what was heard (or why not), and a box to type a line instead of speaking.
## Owned by the Talk autoload.

signal typed(text: String)

## True while the type-a-line box has focus, so the farmer doesn't walk off as you type WASD.
static var typing := false

var _status: Label
var _box: LineEdit
var _status_t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme_res := UiTheme.get_theme()
	_status = Label.new()
	_status.theme = theme_res
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -150
	_status.offset_bottom = -110
	_status.offset_left = -420
	_status.offset_right = 420
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	_status.add_theme_constant_override("outline_size", 8)
	_status.visible = false
	add_child(_status)
	_box = LineEdit.new()
	_box.theme = theme_res
	_box.placeholder_text = "Say something to the punter in front of you... (Enter to say, Esc to cancel)"
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_box.offset_top = -104
	_box.offset_bottom = -62
	_box.offset_left = -360
	_box.offset_right = 360
	_box.max_length = 160
	_box.visible = false
	_box.text_submitted.connect(_on_submitted)
	_box.gui_input.connect(_on_box_input)
	_box.focus_exited.connect(close_box)
	add_child(_box)


func _process(delta: float) -> void:
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			_status.visible = false


## Show a short line above the HUD for `seconds` (0 = until replaced).
func show_status(text: String, seconds := 3.0, colour := Color(1.0, 0.95, 0.85)) -> void:
	_status.text = text
	_status.modulate = colour
	_status.visible = text != ""
	_status_t = seconds if seconds > 0.0 else 99999.0


func listening(on: bool) -> void:
	if on:
		show_status("● Listening... (let go to say it)", 0.0, Color(1.0, 0.55, 0.45))
	elif _status.text.begins_with("●"):
		show_status("Thinking...", 6.0, Color(0.85, 0.85, 0.8))


func open_box() -> void:
	_box.text = ""
	_box.visible = true
	_box.grab_focus()
	typing = true


func close_box() -> void:
	_box.visible = false
	if _box.has_focus():
		_box.release_focus()
	typing = false


func is_box_open() -> bool:
	return _box.visible


func _on_submitted(text: String) -> void:
	close_box()
	if text.strip_edges() != "":
		typed.emit(text.strip_edges())


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_box.accept_event()
		close_box()
