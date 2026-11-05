class_name UiTheme
extends RefCounted
## Shared look for every menu and the HUD: dark stained oak, brass trim, cream text.
## Placeholder until real fonts and art arrive (M4). Use UiTheme.get_theme() on a root Control.

const WOOD := Color("2a1a10")
const WOOD_LIGHT := Color("3d2717")
const WOOD_DARK := Color("1a0f08")
const BRASS := Color("d9a441")
const CREAM := Color("f1e4c8")
const MUTED := Color("b59f7d")
const BLOOD := Color("b3261e")
const ALE := Color("e0a030")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", CREAM)

	t.set_stylebox("normal", "Button", _box(WOOD_LIGHT, MUTED.darkened(0.4), 2))
	t.set_stylebox("hover", "Button", _box(WOOD_LIGHT.lightened(0.08), BRASS, 2))
	t.set_stylebox("pressed", "Button", _box(WOOD_DARK, BRASS, 2))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), BRASS, 3))
	t.set_stylebox("disabled", "Button", _box(WOOD_DARK, WOOD_LIGHT, 2))
	for item in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(item, "Button", CREAM)
	t.set_color("font_hover_color", "Button", BRASS)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))

	t.set_stylebox("normal", "LineEdit", _box(WOOD_DARK, MUTED.darkened(0.4), 2))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), BRASS, 3))
	t.set_color("font_color", "LineEdit", CREAM)

	t.set_stylebox("panel", "Panel", _box(Color(WOOD, 0.96), BRASS.darkened(0.3), 2))
	t.set_stylebox("panel", "PanelContainer", _box(Color(WOOD, 0.96), BRASS.darkened(0.3), 2))
	t.set_stylebox("panel", "TabContainer", _box(Color(WOOD_DARK, 0.9), BRASS.darkened(0.4), 1))
	t.set_stylebox("tab_selected", "TabContainer", _box(WOOD_LIGHT, BRASS, 2))
	t.set_stylebox("tab_unselected", "TabContainer", _box(WOOD_DARK, WOOD_LIGHT, 1))
	t.set_stylebox("tab_hovered", "TabContainer", _box(WOOD_LIGHT, MUTED, 1))
	t.set_stylebox("tab_focus", "TabContainer", _box(Color(0, 0, 0, 0), BRASS, 3))
	t.set_color("font_selected_color", "TabContainer", BRASS)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", CREAM)

	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.8), 1, 3))
	t.set_stylebox("fill", "ProgressBar", _box(BLOOD, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("slider", "HSlider", _box(WOOD_DARK, MUTED.darkened(0.4), 1, 3))
	t.set_stylebox("grabber_area", "HSlider", _box(BRASS.darkened(0.2), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(BRASS, Color(0, 0, 0, 0), 0, 3))

	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 56)
	t.set_color("font_color", "TitleLabel", BRASS)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "TitleLabel", 3)
	t.set_constant("shadow_offset_y", "TitleLabel", 3)
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 28)
	t.set_color("font_color", "HeaderLabel", BRASS)
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 16)
	t.set_color("font_color", "HintLabel", MUTED)
	_theme = t
	return t


static func _box(bg: Color, border: Color, width: int, radius := 4) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	return l


static func button(text: String, cb: Callable, min_height := 48) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = min_height
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A full-screen dim layer that swallows clicks behind a popup screen.
static func dimmer(alpha := 0.75) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
