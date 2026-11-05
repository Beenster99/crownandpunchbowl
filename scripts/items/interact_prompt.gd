class_name InteractPrompt
extends Node3D
## Shows the local player what they can grab and which button does it. Purely cosmetic and
## local to each peer. PubItems adds one to every pub.
##
## - Loose items near the local player get a faint outline. The one `interact` would take
##   gets a brighter, pulsing outline and a floating prompt like "[E] Pick up bottle".
## - At the bar: "[E] Order a pint  [C] Order food".
## - Holding something: a small "[T] Throw" over the player's head.
##
## Button labels come from Settings.prompt(action), which follows the last device used
## (keyboard and mouse or controller), so only the right prompts show. Respects the
## gameplay "context_prompts" setting.

const NODE_NAME := "InteractPrompt"
const NEARBY_RANGE := 4.0   ## items within this get the faint outline
const PROMPT_COLOR := Color(1.0, 0.93, 0.8)
const KEY_COLOR := Color(1.0, 0.78, 0.35)

var _label: Label3D
var _held_label: Label3D
var _lit: Array[PubItem] = []
## Fallback device tracking for when Settings has no prompt helper.
var _pad := false


func _ready() -> void:
	name = NODE_NAME
	_label = _make_label(30)
	_held_label = _make_label(24)
	_held_label.modulate.a = 0.85


func _make_label(size: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0008
	l.font_size = size
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = PROMPT_COLOR
	l.render_priority = 10
	l.outline_render_priority = 9
	l.visible = false
	add_child(l)
	return l


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or \
			(event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_pad = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_pad = false


## Key or button label for `action` on the device the player is using.
func key_for(action: String) -> String:
	if Settings.has_method("prompt"):
		return Settings.prompt(action)
	return Settings.action_label(action, "pad" if _pad else "kb")


func _process(_delta: float) -> void:
	var player := _local_player()
	var hands := Hands.of(player)
	var show := hands != null and bool(_setting("context_prompts", true)) \
		and not player.is_down() and player.state != Fighter.State.HELD
	var target: Dictionary = hands.interact_target() if show else {"hint": "", "node": null}
	_update_outlines(player if show else null, target["node"] as PubItem)
	_update_prompt(player, hands, target, show)


func _local_player() -> Fighter:
	for p in get_tree().get_nodes_in_group("players"):
		var f := p as Fighter
		if f != null and f.is_multiplayer_authority():
			return f
	return null


func _update_outlines(player: Fighter, target: PubItem) -> void:
	var now: Array[PubItem] = []
	if player != null:
		var at := player.global_position
		for node in get_tree().get_nodes_in_group(PubItem.GROUP):
			var item := node as PubItem
			if item != null and item.is_loose() and item.global_position.distance_to(at) <= NEARBY_RANGE:
				now.append(item)
	for item in _lit:
		if is_instance_valid(item) and not now.has(item):
			item.set_highlight(0)
	for item in now:
		item.set_highlight(2 if item == target else 1)
	_lit = now


func _update_prompt(player: Fighter, hands: Hands, target: Dictionary, show: bool) -> void:
	var hint := String(target["hint"])
	var node: Node3D = target["node"]
	_label.visible = show and hint != "" and hint != "drop" and node != null
	if _label.visible:
		match hint:
			"pick_up":
				var verb := "Swap for" if hands.held_item() != null else "Pick up"
				_label.text = "%s  %s %s" % [_key("interact"), verb, (node as PubItem).display_name().to_lower()]
			"drink", "eat":
				_label.text = "%s  %s %s" % [_key("interact"), hint.capitalize(),
					(node as PubItem).display_name().to_lower()]
			"order":
				_label.text = "%s  Order a pint     %s  Order food" % [_key("interact"), _key("order_food")]
		var at := node.global_position + Vector3.UP * 0.6
		if node is Bar:
			at = (node as Bar).serve_point(player.global_position) + Vector3.UP * 0.55
		_label.global_position = at
	var held := hands.held_item() if show else null
	_held_label.visible = held != null
	if _held_label.visible:
		_held_label.text = "%s  Throw     %s  Drop" % [_key("throw"), _key("interact")] \
			if hint == "drop" else "%s  Throw" % _key("throw")
		_held_label.global_position = player.global_position + Vector3.UP * 2.25


func _key(action: String) -> String:
	return "[%s]" % key_for(action)


func _setting(key: String, default: Variant) -> Variant:
	var section: Dictionary = Settings.values.get("gameplay", {})
	return section.get(key, default)
