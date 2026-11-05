extends Node
## Defend prompts: when an enemy winds up an attack on the local player, a prompt pops up
## over their head saying how to defend it and which button to press, for the device the
## player is using ("Shift  BLOCK" on keyboard, "LB  BLOCK" on a pad). Punches say Block,
## guard breakers (kicks, haymakers, shoves, batons) say Dodge. The prompt shrinks as
## the hit gets closer and turns green on a parry. Respects the "counter_prompts" setting.
## PlayerFighter adds one of these for the local player.

const COLOURS := {"block": Color(1.0, 0.85, 0.2), "dodge": Color(1.0, 0.35, 0.25)}

var player: Fighter
## "kb" or "pad", from the last real input (Settings.device is used when it exists).
var device := "kb"

var _labels := {}  # attacker -> Label3D


func _ready() -> void:
	Events.attack_telegraphed.connect(_on_telegraphed)
	Events.attack_countered.connect(_on_countered)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion \
			and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		device = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		device = "kb"


func current_device() -> String:
	var d: Variant = Settings.get("device")
	return String(d) if d is String and d != "" else device


## The prompt text for a defence ("block" or "dodge") on the current device.
func prompt_text(hint: String) -> String:
	var key := ""
	if Settings.has_method("prompt"):
		key = String(Settings.call("prompt", hint))
	else:
		key = Settings.action_label(hint, current_device())
	return "%s  %s" % [key, hint.to_upper()]


func _on_telegraphed(attacker: Node, target: Node, _seconds: float) -> void:
	if target != player or not (attacker is Fighter):
		return
	if not bool(Settings.get_value("gameplay", "counter_prompts")):
		return
	var a := attacker as Fighter
	var hint := a.defend_hint()
	if hint == "":
		return
	var label: Label3D = _labels.get(a)
	if label == null or not is_instance_valid(label):
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0007
		label.font_size = 36
		label.outline_size = 12
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.render_priority = 10
		a.add_child(label)
		_labels[a] = label
	label.text = prompt_text(hint)
	label.modulate = COLOURS.get(hint, Color.WHITE)
	label.set_meta("start", a.windup_remaining())
	label.visible = true


func _on_countered(defender: Node, attacker: Node) -> void:
	if defender != player or not _labels.has(attacker):
		return
	var label: Label3D = _labels[attacker]
	if is_instance_valid(label):
		label.text = "PARRIED!  COUNTER"
		label.modulate = Color(0.4, 1.0, 0.45)
		label.set_meta("hold", 0.6)


func _process(delta: float) -> void:
	for a in _labels.keys():
		var label: Label3D = _labels[a]
		if not is_instance_valid(a) or not is_instance_valid(label):
			_labels.erase(a)
			continue
		var f := a as Fighter
		var hold := float(label.get_meta("hold", 0.0))
		if hold > 0.0:
			label.set_meta("hold", hold - delta)
			label.position = Vector3(0, 2.45, 0)
			continue
		if f.state != Fighter.State.WINDUP or f.target != player:
			label.visible = false
			continue
		var start := maxf(float(label.get_meta("start", 0.5)), 0.01)
		var t := clampf(f.windup_remaining() / start, 0.0, 1.0)
		label.position = f.to_local(f.get_head_position()) + Vector3(0, 0.55, 0) \
			if f.has_method("get_head_position") else Vector3(0, 2.3, 0)
		label.scale = Vector3.ONE * lerpf(1.0, 1.35, 1.0 - t)
