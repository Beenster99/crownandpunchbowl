extends Control
## Working co-op lobby built in code on top of Net: host or join, pick a farmer,
## ready up, and (host) pick the pub and difficulty, then start. The menus workstream
## can restyle or replace it; everything it does goes through the Net API.
## Opened from the main menu with mode "host" or "join".

const MENU_SCENE := "res://scenes/main/main_menu.tscn"

var mode := "host"

var _status: Label
var _connect_box: VBoxContainer
var _lobby_box: VBoxContainer
var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: SpinBox
var _farmer: OptionButton
var _pub: OptionButton
var _difficulty: OptionButton
var _player_list: ItemList
var _ready_toggle: CheckButton
var _start: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("2a1a10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(520, 0)
	root.position = Vector2(-260, -300)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "HOST A NIGHT OUT" if mode == "host" else "JOIN YOUR MATES"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("d9a441"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color("e8d7b0"))
	root.add_child(_status)

	# Shared: name and farmer (changeable in the lobby too).
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.text = "Farmer"
	_name_edit.max_length = 20
	_name_edit.text_submitted.connect(func(t: String): Net.set_player_name(t))
	_name_edit.focus_exited.connect(func(): Net.set_player_name(_name_edit.text))
	root.add_child(_row("Name", _name_edit))

	_farmer = OptionButton.new()
	for f in GameData.FARMERS:
		_farmer.add_item(f["name"])
	_farmer.item_selected.connect(func(i: int): Net.set_farmer(i))
	root.add_child(_row("Farmer", _farmer))

	# Before connecting.
	_connect_box = VBoxContainer.new()
	_connect_box.add_theme_constant_override("separation", 10)
	root.add_child(_connect_box)
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "Host IP address (e.g. 192.168.1.20)"
	_address_edit.text = "127.0.0.1"
	if mode == "join":
		_connect_box.add_child(_row("Address", _address_edit))
	_port_edit = SpinBox.new()
	_port_edit.min_value = 1024
	_port_edit.max_value = 65535
	_port_edit.value = Net.DEFAULT_PORT
	_connect_box.add_child(_row("Port", _port_edit))
	var go := _button(_connect_box, "Open the pub" if mode == "host" else "Join")
	go.pressed.connect(_on_connect)

	# After connecting.
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	root.add_child(_lobby_box)
	_pub = OptionButton.new()
	for p in GameData.PUBS:
		_pub.add_item("%s (%s)" % [p["name"], p["era"]])
	_pub.item_selected.connect(func(i: int): Net.set_pub(i))
	_lobby_box.add_child(_row("Starting pub", _pub))
	_difficulty = OptionButton.new()
	for d in GameData.DIFFICULTIES:
		_difficulty.add_item(d["name"])
	_difficulty.item_selected.connect(func(i: int): Net.set_difficulty(i))
	_lobby_box.add_child(_row("Difficulty", _difficulty))
	_player_list = ItemList.new()
	_player_list.custom_minimum_size.y = 140
	_lobby_box.add_child(_player_list)
	_ready_toggle = CheckButton.new()
	_ready_toggle.text = "Ready"
	_ready_toggle.toggled.connect(func(on: bool): Net.set_ready(on))
	_lobby_box.add_child(_ready_toggle)
	_start = _button(_lobby_box, "Start the night")
	_start.pressed.connect(Net.start_game)

	_button(root, "Back").pressed.connect(_on_back)

	Net.players_changed.connect(_refresh)
	Net.lobby_settings_changed.connect(_refresh)
	Net.joined_lobby.connect(_on_joined)
	Net.connection_failed.connect(_on_failed)
	_status.text = "Pick a name and a farmer."


func _on_connect() -> void:
	var port := int(_port_edit.value)
	var err: Error
	if mode == "host":
		err = Net.host(_name_edit.text, _farmer.selected, port)
		if err == OK:
			_status.text = "Pub's open on port %d. Mates join with your IP address. You'll need to forward UDP port %d to play over the internet." % [port, port]
			_show_lobby()
	else:
		err = Net.join(_address_edit.text.strip_edges(), _name_edit.text, _farmer.selected, port)
		if err == OK:
			_status.text = "Knocking on the door…"
	if err != OK:
		_status.text = Net.last_error


func _on_joined() -> void:
	_status.text = "You're in. Ready up when you're set; the host picks the pub."
	_show_lobby()


func _on_failed() -> void:
	_status.text = Net.last_error
	_connect_box.visible = true
	_lobby_box.visible = false


func _show_lobby() -> void:
	_connect_box.visible = false
	_lobby_box.visible = true
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var host := Net.is_host()
	_pub.select(GameData.current_pub_index)
	_difficulty.select(GameData.difficulty_index)
	_pub.disabled = not host
	_difficulty.disabled = not host
	_ready_toggle.visible = not host
	_start.visible = host
	_start.disabled = not Net.can_start()
	_player_list.clear()
	for id in Net.player_ids():
		var p: Dictionary = Net.players[id]
		var tag := "host" if id == 1 else ("ready" if p["ready"] else "not ready")
		var you := "  (you)" if id == Net.local_id() else ""
		_player_list.add_item("%s as %s  [%s]%s" % [p["name"], GameData.FARMERS[p["farmer"]]["name"], tag, you])


func _on_back() -> void:
	Net.leave()
	get_tree().change_scene_to_file(MENU_SCENE)


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	parent.add_child(b)
	return b
