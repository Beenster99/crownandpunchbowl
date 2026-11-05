extends Control
## Placeholder main menu. The menus workstream replaces this with the real
## front end (lobby, farmer select, settings screens).

var _pub: OptionButton
var _difficulty: OptionButton


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("2a1a10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.position = Vector2(-210, -220)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var title := Label.new()
	title.text = "CROWN & PUNCHBOWL"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("d9a441"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_pub = OptionButton.new()
	for p in GameData.PUBS:
		_pub.add_item("%s (%s)" % [p["name"], p["era"]])
	_pub.select(GameData.current_pub_index)
	box.add_child(_pub)

	_difficulty = OptionButton.new()
	for d in GameData.DIFFICULTIES:
		_difficulty.add_item(d["name"])
	_difficulty.select(GameData.difficulty_index)
	box.add_child(_difficulty)

	_button(box, "Play solo (test pub)", _on_solo)
	_button(box, "Host co-op", _open_lobby.bind("host"))
	_button(box, "Join co-op", _open_lobby.bind("join"))
	_button(box, "Settings", Callable(), true)
	_button(box, "Quit", get_tree().quit)

	if Net.last_error != "":
		var err := Label.new()
		err.text = Net.last_error
		err.add_theme_color_override("font_color", Color("e06c4c"))
		err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(err)
		Net.last_error = ""


func _button(parent: Control, text: String, cb: Callable, disabled := false) -> void:
	var b := Button.new()
	b.text = text + ("  (coming soon)" if disabled else "")
	b.disabled = disabled
	b.custom_minimum_size.y = 44
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)


func _on_solo() -> void:
	GameData.current_pub_index = _pub.selected
	GameData.difficulty_index = _difficulty.selected
	Net.start_solo("Player", 0)
	Net.start_game()


func _open_lobby(mode: String) -> void:
	var lobby: Control = preload("res://scripts/net/lobby_screen.gd").new()
	lobby.name = "Lobby"
	lobby.mode = mode
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	var tree := get_tree()
	tree.root.add_child(lobby)
	tree.current_scene = lobby
	queue_free()
