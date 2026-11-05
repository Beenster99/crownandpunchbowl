class_name FarmerCard
extends Button
## One selectable farmer on the farmer select screen: name, blurb, stat bars and trait.
## Stat bars are scaled against the best farmer for each stat, so differences read clearly.

const STATS := [["max_hp", "Health"], ["power", "Power"], ["speed", "Speed"], ["grip", "Grip"]]

var farmer_index := 0


func setup(index: int) -> FarmerCard:
	farmer_index = index
	return self


func _ready() -> void:
	var f: Dictionary = GameData.FARMERS[farmer_index]
	toggle_mode = true
	custom_minimum_size = Vector2(300, 250)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 10
	box.offset_bottom = -10
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var title := UiTheme.label(f["name"])
	title.add_theme_color_override("font_color", UiTheme.BRASS)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var blurb := UiTheme.label(f["blurb"], "HintLabel")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.y = 44
	box.add_child(blurb)

	for s in STATS:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UiTheme.label(s[1], "HintLabel")
		l.custom_minimum_size.x = 70
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = _best(s[0])
		bar.value = float(f[s[0]])
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.ALE
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		box.add_child(row)

	var trait_label := UiTheme.label("Trait: " + String(f["trait"]).capitalize())
	trait_label.add_theme_font_size_override("font_size", 17)
	box.add_child(trait_label)
	for c in box.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _best(stat: String) -> float:
	var best := 0.0
	for f in GameData.FARMERS:
		best = maxf(best, float(f[stat]))
	return best
