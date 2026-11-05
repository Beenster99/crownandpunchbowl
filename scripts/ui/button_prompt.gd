class_name ButtonPrompt
extends HBoxContainer
## A keycap showing what `action` is bound to on the device the player is using right now,
## plus an optional caption: [E] Pick up bottle. Swaps between keyboard/mouse and controller
## labels as soon as the player touches the other device, and follows rebinding.
## Usage: add_child(ButtonPrompt.make("interact", "Order pint"))

var action := ""
var caption := ""
var _cap: PanelContainer
var _cap_label: Label
var _caption_label: Label


static func make(p_action: String, p_caption := "") -> ButtonPrompt:
	var b := ButtonPrompt.new()
	b.action = p_action
	b.caption = p_caption
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	_cap = PanelContainer.new()
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cap)
	_cap_label = Label.new()
	_cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap_label.add_theme_font_size_override("font_size", 16)
	_cap_label.add_theme_color_override("font_color", UiTheme.WOOD_DARK)
	_cap.add_child(_cap_label)
	_caption_label = Label.new()
	_caption_label.add_theme_font_size_override("font_size", 17)
	_caption_label.add_theme_color_override("font_color", UiTheme.CREAM)
	_caption_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption_label.add_theme_constant_override("outline_size", 6)
	_caption_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_caption_label)
	Settings.device_changed.connect(func(_d): refresh())
	Settings.changed.connect(func(section, _k): if section == "keybinds": refresh())
	refresh()


func set_caption(text: String) -> void:
	caption = text
	if _caption_label:
		_caption_label.text = text
		_caption_label.visible = text != ""


func refresh() -> void:
	if _cap_label == null:
		return
	var pad := Settings.device == "pad"
	_cap_label.text = Settings.prompt(action)
	# Keycaps are square-ish cream tiles; controller buttons are round and tinted like the pad.
	var box := StyleBoxFlat.new()
	box.bg_color = _pad_colour(_cap_label.text) if pad else UiTheme.CREAM
	box.set_corner_radius_all(14 if pad else 4)
	box.border_color = Color(0, 0, 0, 0.6)
	box.set_border_width_all(1)
	box.border_width_bottom = 3
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 2
	_cap.add_theme_stylebox_override("panel", box)
	_cap.custom_minimum_size = Vector2(28, 26)
	_cap_label.add_theme_color_override("font_color", Color.WHITE if pad and _cap_label.text.length() == 1
		else UiTheme.WOOD_DARK)
	set_caption(caption)


## Face buttons get their usual colours so they're recognisable at a glance.
static func _pad_colour(label: String) -> Color:
	match label:
		"A": return Color("3f9b4a")
		"B": return Color("c0392b")
		"X": return Color("2f6fbf")
		"Y": return Color("d4a017")
	return Color("cfc6b4")
