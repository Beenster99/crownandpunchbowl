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
var _friendly_fire: CheckButton
var _player_list: ItemList
var _ready_toggle: CheckButton
var _start: Button
var _join_button: Button
var _host_panel: VBoxContainer
var _host_lines: Label
var _copy_internet: Button
var _copy_lan: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("2a1a10")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	theme = UiTheme.get_theme()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(640, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

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
	_address_edit.placeholder_text = "Address from the host's lobby, e.g. 81.2.3.4"
	_address_edit.text_submitted.connect(func(_t: String): _on_connect())
	if mode == "join":
		_connect_box.add_child(_row("Address", _address_edit))
	_port_edit = SpinBox.new()
	_port_edit.min_value = 1024
	_port_edit.max_value = 65535
	_port_edit.value = Net.DEFAULT_PORT
	_connect_box.add_child(_row("Port", _port_edit))
	_join_button = _button(_connect_box, "Open the pub" if mode == "host" else "Join")
	_join_button.pressed.connect(_on_connect)

	# After connecting.
	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	root.add_child(_lobby_box)
	_build_host_panel()
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
	_friendly_fire = CheckButton.new()
	_friendly_fire.text = "Players can hit each other"
	_friendly_fire.tooltip_text = "Friendly fire. The host decides. Nobody can hit the bar staff."
	# The host's toggle is their own setting, which Net syncs to everyone.
	_friendly_fire.toggled.connect(func(on: bool):
		if Net.is_host():
			Settings.set_value("gameplay", "friendly_fire", on))
	_lobby_box.add_child(_friendly_fire)
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
	Net.host_info_changed.connect(_refresh_host_info)
	_status.text = "Pick a name and a farmer."


func _on_connect() -> void:
	var port := int(_port_edit.value)
	var err: Error
	if mode == "host":
		err = Net.host(_name_edit.text, _farmer.selected, port)
		if err == OK:
			_status.text = "The pub's open. Give your mates one of the addresses below."
			_show_lobby()
	else:
		err = Net.join(_address_edit.text, _name_edit.text, _farmer.selected, port)
		if err == OK:
			_status.text = "Knocking on the door… (giving up after %d seconds)" % int(Net.JOIN_TIMEOUT)
			_join_button.disabled = true
	if err != OK:
		_status.text = Net.last_error


func _on_joined() -> void:
	_status.text = "You're in. Ready up when you're set; the host picks the pub."
	_show_lobby()


func _on_failed() -> void:
	_status.text = Net.last_error
	_join_button.disabled = false
	_connect_box.visible = true
	_lobby_box.visible = false


func _show_lobby() -> void:
	_connect_box.visible = false
	_lobby_box.visible = true
	_refresh()
	_refresh_host_info()


func _refresh() -> void:
	if not is_inside_tree():
		return
	var host := Net.is_host()
	_pub.select(GameData.current_pub_index)
	_difficulty.select(GameData.difficulty_index)
	_pub.disabled = not host
	_difficulty.disabled = not host
	_friendly_fire.set_pressed_no_signal(GameData.friendly_fire)
	_friendly_fire.disabled = not host
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


# --- Host addresses -------------------------------------------------------------

func _build_host_panel() -> void:
	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 6)
	_host_panel.visible = false
	_lobby_box.add_child(_host_panel)
	_lobby_box.move_child(_host_panel, 0)
	_host_lines = Label.new()
	_host_lines.autowrap_mode = TextServer.AUTOWRAP_WORD
	_host_panel.add_child(_host_lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_host_panel.add_child(row)
	_copy_internet = _button(row, "Copy internet address")
	_copy_internet.pressed.connect(func(): _copy(Net.internet_address()))
	_copy_lan = _button(row, "Copy home-network address")
	_copy_lan.pressed.connect(func():
		var lan: Array = Net.host_info.get("lan", [])
		if not lan.is_empty():
			_copy(_with_port(lan[0])))


func _refresh_host_info() -> void:
	if not is_inside_tree() or _host_panel == null:
		return
	var info := Net.host_info
	_host_panel.visible = Net.is_host() and not info.is_empty()
	if info.is_empty():
		return
	var port: int = info["port"]
	var lines: Array[String] = []
	var internet := Net.internet_address()
	match info["upnp"]:
		"trying":
			lines.append("Over the internet: %s  (asking your router to open port %d…)" %
				[internet if internet != "" else "looking up…", port])
		"open":
			lines.append("Over the internet: %s  (your router opened port %d automatically)" %
				[internet if internet != "" else "unknown", port])
		_:
			lines.append("Over the internet: %s" % (internet if internet != "" else "unknown"))
			if info["upnp_error"] != "":
				lines.append("   %s To play over the internet, forward UDP port %d to %s in your router settings, or use a free VPN like Tailscale." %
					[info["upnp_error"], port, info["lan"][0] if not info["lan"].is_empty() else "this PC"])
	if info["cgnat"]:
		lines.append("   Warning: your internet provider shares your internet address with other customers, so mates can't reach you over the internet directly. Use a free VPN like Tailscale instead: you and your mates install it, sign in to the same network, and join on your Tailscale address.")
	var lan: Array = info["lan"]
	if not lan.is_empty():
		lines.append("Same Wi-Fi or home network: %s" % ", ".join(lan.map(_with_port)))
	var vpn: Array = info["vpn"]
	if not vpn.is_empty():
		lines.append("VPN (Tailscale, ZeroTier, Radmin): %s" % ", ".join(vpn.map(_with_port)))
	lines.append("If Windows asks whether to allow the game through the firewall, tick both boxes and press Allow.")
	_host_lines.text = "\n".join(lines)
	_copy_internet.disabled = internet == ""
	_copy_lan.disabled = lan.is_empty()


func _with_port(ip: String) -> String:
	var port: int = Net.host_info.get("port", Net.DEFAULT_PORT)
	return ip if port == Net.DEFAULT_PORT else "%s:%d" % [ip, port]


func _copy(text: String) -> void:
	if text == "":
		return
	DisplayServer.clipboard_set(text)
	_status.text = "Copied %s. Send it to your mates." % text
