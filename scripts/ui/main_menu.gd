extends Control
## Front end: title screen, then the "night out" setup (farmer, pub, difficulty), plus Settings.
## Solo play starts the chosen pub through Net.start_solo(). Host and join stay disabled until the
## lobby UI lands with the co-op milestone (M2); the setup screen is what the host will see then.

var _title_screen: Control
var _setup_screen: Control
var _farmer_cards: Array[FarmerCard] = []
var _name_edit: LineEdit
var _pub_pick: OptionButton
var _pub_hint: Label
var _difficulty_buttons: Array[Button] = []
var _difficulty_hint: Label
var _farmer_index := 0
var _difficulty_index := 1


func _ready() -> void:
	theme = UiTheme.get_theme()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_farmer_index = clampi(int(Settings.get_value("profile", "farmer")), 0, GameData.FARMERS.size() - 1)
	_difficulty_index = GameData.difficulty_index
	_title_screen = _build_title()
	add_child(_title_screen)
	_setup_screen = _build_setup()
	add_child(_setup_screen)
	_show(_title_screen)


func _show(screen: Control) -> void:
	_title_screen.visible = screen == _title_screen
	_setup_screen.visible = screen == _setup_screen
	var first := _first_focus(screen)
	if first:
		first.grab_focus.call_deferred()


func _first_focus(node: Node) -> Control:
	for c in node.get_children():
		if c is BaseButton and not c.disabled and c.visible:
			return c
		var found := _first_focus(c)
		if found:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _setup_screen.visible:
		get_viewport().set_input_as_handled()
		_show(_title_screen)


# --- Title ---------------------------------------------------------------------

func _build_title() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 440
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title := UiTheme.label("CROWN & PUNCHBOWL", "TitleLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tag := UiTheme.label("Four pubs. Six farmers. Nobody leaves standing.", "HintLabel")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	box.add_child(Control.new())

	box.add_child(UiTheme.button("Play solo", func(): _show(_setup_screen)))
	var host := UiTheme.button("Host co-op  (coming with online play)", Callable())
	host.disabled = true
	box.add_child(host)
	var join := UiTheme.button("Join co-op  (coming with online play)", Callable())
	join.disabled = true
	box.add_child(join)
	box.add_child(UiTheme.button("Settings", open_settings))
	box.add_child(UiTheme.button("Quit", get_tree().quit))
	return center


func open_settings() -> SettingsMenu:
	var s := SettingsMenu.new()
	var return_to := get_viewport().gui_get_focus_owner()
	s.closed.connect(func():
		_difficulty_index = GameData.difficulty_index
		_refresh_difficulty()
		if is_instance_valid(return_to):
			return_to.grab_focus())
	add_child(s)
	return s


# --- Night out setup --------------------------------------------------------------

func _build_setup() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(UiTheme.label("Pick your farmer", "HeaderLabel"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	col.add_child(grid)
	var group := ButtonGroup.new()
	for i in GameData.FARMERS.size():
		var card := FarmerCard.new().setup(i)
		card.button_group = group
		card.button_pressed = i == _farmer_index
		card.pressed.connect(func(): _farmer_index = i)
		grid.add_child(card)
		_farmer_cards.append(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UiTheme.label("Your name"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.text = Settings.get_value("profile", "name")
	left.add_child(_name_edit)
	left.add_child(UiTheme.label("Start the night at"))
	_pub_pick = OptionButton.new()
	for p in GameData.PUBS:
		_pub_pick.add_item(p["name"])
	_pub_pick.select(clampi(int(Settings.get_value("profile", "pub")), 0, GameData.PUBS.size() - 1))
	_pub_pick.item_selected.connect(func(_i): _refresh_pub())
	left.add_child(_pub_pick)
	_pub_hint = UiTheme.label("", "HintLabel")
	left.add_child(_pub_hint)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(UiTheme.label("Difficulty"))
	var diff_row := HBoxContainer.new()
	var diff_group := ButtonGroup.new()
	for i in GameData.DIFFICULTIES.size():
		var b := UiTheme.button(GameData.DIFFICULTIES[i]["name"], func(): _set_difficulty(i), 44)
		b.toggle_mode = true
		b.button_group = diff_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		diff_row.add_child(b)
		_difficulty_buttons.append(b)
	right.add_child(diff_row)
	_difficulty_hint = UiTheme.label("", "HintLabel")
	_difficulty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_difficulty_hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	buttons.add_child(UiTheme.button("Back", func(): _show(_title_screen)))
	var go := UiTheme.button("Get the first round in", _on_start)
	go.custom_minimum_size.x = 300
	buttons.add_child(go)

	_refresh_pub()
	_refresh_difficulty()
	return margin


func _refresh_pub() -> void:
	_pub_hint.text = "%s. Clear it and the whole group moves on to the next pub." % \
		GameData.PUBS[_pub_pick.selected]["era"]


func _set_difficulty(i: int) -> void:
	_difficulty_index = i
	_refresh_difficulty()


func _refresh_difficulty() -> void:
	if _difficulty_buttons.is_empty():
		return
	_difficulty_buttons[_difficulty_index].button_pressed = true
	_difficulty_hint.text = difficulty_summary(GameData.DIFFICULTIES[_difficulty_index])


## Plain-English summary of a difficulty table, shown under the picker.
static func difficulty_summary(d: Dictionary) -> String:
	return "%s\nPunters hit %s and take %s to drop. Up to %d at once can come for you. " % [
		d["blurb"], _pct(d["enemy_damage"]), _pct(d["enemy_health"]), d["max_attackers"]] + \
		"Food and drink heal %s. Police turn up %s." % [
		_pct(d["heal_multiplier"]), _chance(d["police_chance"])]


static func _pct(m: float) -> String:
	if is_equal_approx(m, 1.0):
		return "as normal"
	return "%d%% %s" % [roundi(absf(m - 1.0) * 100.0), "more" if m > 1.0 else "less"]


static func _chance(c: float) -> String:
	if c < 0.3:
		return "now and then"
	if c < 0.5:
		return "sometimes"
	if c < 0.75:
		return "often"
	return "almost every time"


func _on_start() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name == "":
		player_name = "Farmer"
	Settings.set_value("profile", "name", player_name)
	Settings.set_value("profile", "farmer", _farmer_index)
	Settings.set_value("profile", "pub", _pub_pick.selected)
	Settings.set_value("gameplay", "difficulty", _difficulty_index)
	GameData.current_pub_index = _pub_pick.selected
	GameData.difficulty_index = _difficulty_index
	Net.start_solo(player_name, _farmer_index)
	get_tree().change_scene_to_file(GameData.current_pub()["scene"])
