extends Node
## Defend prompts: when an enemy winds up an attack on the local player, one small prompt
## shows under the player's feet saying how to defend the attack that lands soonest and
## which button to press, for the device the player is using ("LB  BLOCK HIGH" for a punch
## at the head, "RB  BLOCK LOW" for one at the body, "A  DODGE" for guard breakers: kicks,
## haymakers, shoves, batons). It turns green on a parry, and calls out power shots,
## punishes and broken guards. Respects the "counter_prompts" setting.
## PlayerFighter adds one of these for the local player.

const COLOURS := {"guard_head": Color(1.0, 0.85, 0.2), "guard_body": Color(1.0, 0.6, 0.15),
	"dodge": Color(1.0, 0.35, 0.25)}
## Defence hint (an action name, from Fighter.defend_hint()) -> the word on the prompt.
const WORDS := {"guard_head": "BLOCK HIGH", "guard_body": "BLOCK LOW", "dodge": "DODGE"}

var player: Fighter
## "kb" or "pad", from the last real input (Settings.device is used when it exists).
var device := "kb"

## Pixels (at pixel_size) the prompt sits below the player's feet on screen.
const PROMPT_DROP := 30.0

var _attackers: Array = []  # enemies winding up on the player
var _label: Label3D
var _hold := 0.0  # seconds left showing "PARRIED"


func _ready() -> void:
	Events.attack_telegraphed.connect(_on_telegraphed)
	Events.attack_countered.connect(_on_countered)
	Events.hit_landed.connect(_on_hit_landed)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion \
			and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		device = "pad"
	elif event is InputEventKey or event is InputEventMouseButton:
		device = "kb"


func current_device() -> String:
	var d: Variant = Settings.get("device")
	return String(d) if d is String and d != "" else device


## The prompt text for a defence ("guard_head", "guard_body" or "dodge") on the current device.
func prompt_text(hint: String) -> String:
	var key := ""
	if Settings.has_method("prompt"):
		key = String(Settings.call("prompt", hint))
	else:
		key = Settings.action_label(hint, current_device())
	return "%s  %s" % [key, WORDS.get(hint, hint.to_upper())]


func _on_telegraphed(attacker: Node, target: Node, _seconds: float) -> void:
	if target != player or not (attacker is Fighter):
		return
	if not bool(Settings.get_value("gameplay", "counter_prompts")):
		return
	if not _attackers.has(attacker):
		_attackers.append(attacker)


func _on_countered(defender: Node, _attacker: Node) -> void:
	if defender != player:
		return
	flash("PARRIED!  COUNTER", Color(0.4, 1.0, 0.45))


## Show `text` in place of the prompt for `seconds` (call-outs: power shots, punishes).
func flash(text: String, colour: Color, seconds := 0.6) -> void:
	var label := _get_label()
	label.text = text
	label.modulate = colour
	label.visible = true
	_hold = seconds


## Call out what the player just pulled off (or had done to them).
func _on_hit_landed(info: Dictionary) -> void:
	if player == null:
		return
	if info.get("victim") == player and bool(info.get("parried", false)) \
			and bool(info.get("perfect", false)):
		flash("PERFECT!  COUNTER", Color(0.45, 1.0, 0.6), 0.8)
		var fx := get_node_or_null(^"/root/Fx")
		if fx != null and fx.has_method("slow_mo"):
			fx.slow_mo(Moves.PERFECT_SLOWMO, Moves.PERFECT_TIME_SCALE)
		return
	if info.get("attacker") == player:
		if bool(info.get("finish", false)):
			flash("FINISHED HIM", Color(1.0, 0.4, 0.3), 0.9)
			var fx := get_node_or_null(^"/root/Fx")
			if fx != null and fx.has_method("slow_mo"):
				fx.slow_mo(Moves.PERFECT_SLOWMO, Moves.PERFECT_TIME_SCALE)
		elif bool(info.get("rocked", false)):
			flash("ROCKED HIM  FINISH IT", Color(1.0, 0.7, 0.3), 1.0)
		elif bool(info.get("winded", false)):
			flash("WINDED HIM", Color(1.0, 0.75, 0.35), 0.9)
		elif bool(info.get("setup", false)):
			flash(String(info.get("setup_name", "SET UP")).to_upper(), Color(1.0, 0.95, 0.45), 0.9)
		elif bool(info.get("guard_crushed", false)):
			flash("GUARD BROKEN", Color(1.0, 0.8, 0.3))
		elif float(info.get("power", 0.0)) >= 0.95 and not bool(info.get("blocked", false)):
			flash("FULL POWER", Color(1.0, 0.55, 0.2))
		elif bool(info.get("punish", false)):
			flash("PUNISHED", Color(0.4, 1.0, 0.45))
		elif bool(info.get("opening", false)):
			flash("CLEAN SHOT", Color(1.0, 0.9, 0.4))
	elif info.get("victim") == player and bool(info.get("guard_crushed", false)):
		flash("GUARD CRUSHED", Color(1.0, 0.35, 0.25))
	elif info.get("victim") == player and bool(info.get("rocked", false)):
		flash("ROCKED  COVER UP", Color(1.0, 0.35, 0.25), 1.0)
	elif info.get("victim") == player and bool(info.get("winded", false)):
		flash("WINDED  BACK OFF", Color(1.0, 0.45, 0.3), 1.0)


## The one small prompt, under the player's feet. Made on first use.
func _get_label() -> Label3D:
	if _label == null or not is_instance_valid(_label):
		_label = Label3D.new()
		_label.name = "DefendPrompt"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.fixed_size = true
		_label.pixel_size = 0.0006
		_label.font_size = 22
		_label.outline_size = 8
		_label.outline_modulate = Color(0, 0, 0, 0.85)
		_label.render_priority = 10
		_label.position = Vector3(0, 0.02, 0)
		_label.offset = Vector2(0, -PROMPT_DROP)  # pushed down the screen, below the feet
		_label.visible = false
		player.add_child(_label)
	return _label


## Under the feet from overhead. In first person your feet are out of sight, so the prompt
## sits low in the middle of the view instead, just in front of your chest.
func _place(label: Label3D) -> void:
	var fp := BrawlCamera.first_person and player is PlayerFighter and (player as PlayerFighter).first_person
	label.position = Vector3(0, 0.95, -0.75) if fp else Vector3(0, 0.02, 0)
	label.offset = Vector2.ZERO if fp else Vector2(0, -PROMPT_DROP)


## The enemy whose wind-up on the player lands soonest, or null.
func most_urgent() -> Fighter:
	var best: Fighter = null
	for a in _attackers.duplicate():
		var f := a as Fighter
		if not is_instance_valid(f) or f.state != Fighter.State.WINDUP or f.target != player:
			_attackers.erase(a)
			continue
		if best == null or f.windup_remaining() < best.windup_remaining():
			best = f
	return best


func _process(delta: float) -> void:
	if player == null:
		return
	if _label != null and is_instance_valid(_label):
		_place(_label)
	if _hold > 0.0:
		_hold -= delta
		return
	var f := most_urgent()
	if f == null:
		if _label != null and is_instance_valid(_label):
			_label.visible = false
		return
	var hint := f.defend_hint()
	if hint == "":
		return
	var label := _get_label()
	label.text = prompt_text(hint)
	label.modulate = COLOURS.get(hint, Color.WHITE)
	label.visible = true
