class_name Hud
extends CanvasLayer
## In-fight HUD: a panel per player (health and tipsy), punters still standing, the room's heat,
## the local combo, banners and a controls reminder that shows what each button does, using
## keyboard/mouse or controller labels depending on what the player last touched.
## World-space pickup and bar prompts belong to the items workstream (they use Settings.prompt()).
##
## It only reads, never drives gameplay. What it reads (all optional, so placeholders work):
## - Nodes in group `players`: `hp`, `max_hp`, `stamina`, `max_stamina` (floats), `tipsy` (0..1), and
##   The name and farmer come from Net.players[peer_id], keyed by the node's multiplayer authority.
## - Nodes in group `npcs`: counted as standing unless `is_down()` returns true.
## - The first node in group `director`: `heat` (0..1). The meter hides when there is none.
## - Events: banner, combo_changed, police_called, reinforcements_arrived, pub_cleared, all_players_down.
##   Those flow events get their banner here, so other systems needn't send one for them.

const PANEL_WIDTH := 280.0
## The stamina bar under health, and its colour when you're gassed.
const STAMINA_COLOUR := Color(0.55, 0.78, 0.35)
const STAMINA_LOW := Color(0.95, 0.5, 0.15)

var _players_box: HBoxContainer
var _panels := {}  # player node -> {"hp", "stamina", "tipsy": ProgressBar, ...}
var _standing: Label
var _heat_box: VBoxContainer
var _heat: ProgressBar
var _combo: Label
var _banner: Label
var _hints: VBoxContainer
var _combo_tween: Tween
var _banner_tween: Tween
## Shown in the controls reminder, in this order, if the action exists in Settings.ACTIONS.
const HINTS := [["jab", "Jab"], ["hook", "Hook (hold: power)"], ["uppercut", "Uppercut (hold: power)"],
	["guard_head", "Head guard / parry"], ["guard_body", "Body guard"], ["headbutt", "Headbutt"],
	["dodge", "Dodge"], ["lock_on", "Lock on"], ["lock_next", "Next man"], ["interact", "Pick up / order drink"], ["order_food", "Order food"],
	["throw", "Throw"]]
## Shoulder-button combinations, shown as "LB + X  Kick": [modifier, action, caption].
const COMBO_HINTS := [["guard_body", "jab", "Body shot"], ["guard_head", "jab", "Kick"],
	["guard_head", "uppercut", "Shoulder charge"], ["guard_head", "hook", "Clinch knee"],
	["guard_head", "guard_body", "Hold"], ["bob_left", "", "Slip / duck (with the other directions)"]]


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Your farmer's health sits in the bottom left, out of the way of the fight.
	_players_box = HBoxContainer.new()
	_players_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_players_box.offset_left = 20
	_players_box.offset_bottom = -20
	_players_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_players_box.add_theme_constant_override("separation", 16)
	root.add_child(_players_box)

	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -260
	right.offset_right = -20
	right.offset_top = 20
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(right)
	_standing = UiTheme.label("")
	_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_standing.add_theme_font_size_override("font_size", 24)
	_outline(_standing)
	right.add_child(_standing)
	_heat_box = VBoxContainer.new()
	right.add_child(_heat_box)
	var heat_label := UiTheme.label("Heat", "HintLabel")
	heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_heat_box.add_child(heat_label)
	_heat = _bar(Color("ff6a1a"), 14)
	_heat.max_value = 1.0
	_heat_box.add_child(_heat)

	_combo = UiTheme.label("")
	_combo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_combo.offset_left = -260
	_combo.offset_right = -40
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo.add_theme_font_size_override("font_size", 48)
	_combo.add_theme_color_override("font_color", UiTheme.BRASS)
	_outline(_combo)
	_combo.modulate.a = 0.0
	root.add_child(_combo)

	_banner = UiTheme.label("")
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -600
	_banner.offset_right = 600
	_banner.offset_top = 140
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.add_theme_color_override("font_color", UiTheme.CREAM)
	_outline(_banner)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_hints = VBoxContainer.new()
	_hints.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hints.offset_left = 20
	_hints.offset_top = 20
	_hints.add_theme_constant_override("separation", 4)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hints.modulate.a = 0.85
	root.add_child(_hints)
	for h in HINTS:
		if Settings.ACTIONS.has(h[0]):
			_hints.add_child(ButtonPrompt.make(h[0], h[1]))
	for h in COMBO_HINTS:
		if not Settings.ACTIONS.has(h[0]):
			continue
		if h[1] == "":
			_hints.add_child(ButtonPrompt.make(h[0], h[2]))
		elif Settings.ACTIONS.has(h[1]):
			_hints.add_child(ButtonPrompt.make(h[1], h[2], h[0]))
	_hints.visible = bool(Settings.get_value("gameplay", "control_hints"))
	Settings.changed.connect(func(section, key):
		if section == "gameplay" and key == "control_hints":
			_hints.visible = bool(Settings.get_value("gameplay", "control_hints")))

	Events.banner.connect(show_banner)
	Events.combo_changed.connect(_on_combo)
	Events.police_called.connect(func(): show_banner("Someone's called the Old Bill!", 3.0))
	Events.reinforcements_arrived.connect(func(n: int):
		show_banner("%d more through the door" % n if n > 1 else "Another one through the door", 2.0))
	Events.pub_cleared.connect(func(_id): show_banner("Pub cleared! Drink up, lads.", 4.0))
	Events.all_players_down.connect(func(): show_banner("Lights out.", 4.0))


func show_banner(text: String, seconds := 3.0) -> void:
	_banner.text = text
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	_banner_tween.tween_interval(maxf(seconds, 0.5))
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _process(_delta: float) -> void:
	_update_players()
	_update_room()


func _update_players() -> void:
	var players := get_tree().get_nodes_in_group("players")
	for p in _panels.keys():
		if not is_instance_valid(p) or not players.has(p):
			_panels[p]["panel"].queue_free()
			_panels.erase(p)
	for p in players:
		if not _panels.has(p):
			_add_panel(p)
		var ui: Dictionary = _panels[p]
		var max_hp: float = p.get("max_hp") if p.get("max_hp") != null else 100.0
		var hp: float = p.get("hp") if p.get("hp") != null else max_hp
		ui["hp"].max_value = max_hp
		ui["hp"].value = hp
		var stamina: Variant = p.get("stamina")
		ui["stamina"].visible = stamina != null
		if stamina != null:
			var max_st: float = p.get("max_stamina") if p.get("max_stamina") != null else 100.0
			ui["stamina"].max_value = max_st
			ui["stamina"].value = float(stamina)
			# Gassed: the bar goes a sickly orange so you know to back off and breathe.
			var gassed := float(stamina) < max_st * Moves.GASSED
			(ui["stamina_fill"] as StyleBoxFlat).bg_color = STAMINA_LOW if gassed else STAMINA_COLOUR
		var tipsy: Variant = p.get("tipsy")
		ui["tipsy"].visible = tipsy != null
		if tipsy != null:
			ui["tipsy"].value = float(tipsy)


func _add_panel(p: Node) -> void:
	var info: Dictionary = Net.players.get(p.get_multiplayer_authority(), {})
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	var name_label := UiTheme.label(info.get("name", String(p.name)))
	name_label.add_theme_color_override("font_color", UiTheme.BRASS)
	box.add_child(name_label)
	var farmer: int = info.get("farmer", -1)
	if farmer >= 0 and farmer < GameData.FARMERS.size():
		box.add_child(UiTheme.label(GameData.FARMERS[farmer]["name"], "HintLabel"))
	var hp := _bar(UiTheme.BLOOD, 18)
	box.add_child(hp)
	var stamina := _bar(STAMINA_COLOUR, 8)
	stamina.tooltip_text = "Stamina"
	box.add_child(stamina)
	var tipsy := _bar(UiTheme.ALE, 8)
	tipsy.max_value = 1.0
	tipsy.tooltip_text = "Tipsy"
	box.add_child(tipsy)
	_players_box.add_child(panel)
	_panels[p] = {"panel": panel, "hp": hp, "tipsy": tipsy, "stamina": stamina,
		"stamina_fill": stamina.get_theme_stylebox("fill")}


func _update_room() -> void:
	var standing := 0
	var npcs := get_tree().get_nodes_in_group("npcs")
	for n in npcs:
		if not (n.has_method("is_down") and n.is_down()):
			standing += 1
	_standing.visible = not npcs.is_empty()
	_standing.text = "%d punter%s standing" % [standing, "" if standing == 1 else "s"]
	var director := get_tree().get_first_node_in_group("director")
	_heat_box.visible = director != null and director.get("heat") != null
	if _heat_box.visible:
		_heat.value = float(director.get("heat"))


func _on_combo(player: Node, combo: int) -> void:
	if not is_instance_valid(player) or not player.is_multiplayer_authority():
		return
	if _combo_tween:
		_combo_tween.kill()
	if combo < 2:
		_combo.modulate.a = 0.0
		return
	_combo.text = "%d hit combo" % combo
	_combo.modulate.a = 1.0
	_combo.scale = Vector2.ONE * 1.25
	_combo.pivot_offset = _combo.size * Vector2(1.0, 0.5)
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo, "scale", Vector2.ONE, 0.15)
	_combo_tween.tween_interval(1.8)
	_combo_tween.tween_property(_combo, "modulate:a", 0.0, 0.4)


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(PANEL_WIDTH - 24, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
