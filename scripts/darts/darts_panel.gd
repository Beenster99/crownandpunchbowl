extends CanvasLayer
## The darts screen for the local player at a DartsBoard: a big board to aim at, the
## scoreboard and the game options. DartsBoard opens it while you're chalked up and closes
## it when you step away. It only sends requests through the board.

const AIM_SPEED := 210.0        ## mm per second at full stick
const AIM_GRIP := 5.0           ## how quickly the aim follows the stick (lower = more drift)
const STICK_DEADZONE := 0.18
## The power meter fills in this many seconds, then falls back (and so on while held).
const POWER_TIME := 0.75
const THROW_COOLDOWN := 0.4
const WOBBLE := 9.0             ## mm, sober
const TIPSY_WOBBLE := 32.0      ## mm extra when fully tipsy
const BLACK := Color("161412")
const CREAM := Color("ead9b0")
const RED := Color("b3261e")
const GREEN := Color("1f6a35")
const WIRE := Color(0.8, 0.8, 0.82, 0.55)

var board: DartsBoard

var aim := Vector2.ZERO
var wobble := Vector2.ZERO
var _t := 0.0
var _cooldown := 0.0
var _was_turn := false
var _sent_for := -1
var _sent_t := 0.0
var _aim_vel := Vector2.ZERO
## Holding A: the power meter is running.
var drawing := false
var power := 0.0
var _draw_t := 0.0
## The pad that last pressed a button, for the stick.
var _pad := 0

var _view: Control
var _title: Label
var _info: Label
var _grid: GridContainer
var _status: Label
var _turn_label: Label
var _checkout: Label
var _options: HBoxContainer
var _game_btn: Button
var _legs_btn: Button
var _finish_btn: Button
var _start_btn: Button
var _away_btn: Button
var _leave_btn: Button
var _hint: Label


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(frame)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	frame.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	_view = BoardView.new()
	_view.panel = self
	_view.custom_minimum_size = Vector2(600, 540)
	row.add_child(_view)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(400, 0)
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)
	_title = _label(side, "Darts", 34, UiTheme.BRASS)
	_info = _label(side, "", 18, UiTheme.MUTED)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 18)
	side.add_child(_grid)
	_status = _label(side, "", 28, UiTheme.CREAM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_label = _label(side, "", 22, UiTheme.ALE)
	_checkout = _label(side, "", 20, UiTheme.BRASS)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	_options = HBoxContainer.new()
	_options.add_theme_constant_override("separation", 8)
	side.add_child(_options)
	_game_btn = _button(_options, "501", _on_game)
	_legs_btn = _button(_options, "1 leg", _on_legs)
	_finish_btn = _button(_options, "Double out", _on_finish)
	_start_btn = _button(side, "Start game", func(): board.request_start())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	side.add_child(bottom)
	_away_btn = _button(bottom, "Step away", func(): board.request_away())
	_leave_btn = _button(bottom, "Leave game", func(): board.request_leave())
	_hint = _label(side, "", 16, UiTheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aim = DartsRules.target_point(20, 3)
	refresh()


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_game() -> void:
	var g := board.game
	board.request_options(301 if g.start_score == 501 else 501, g.legs_to_win, g.double_out)


func _on_legs() -> void:
	var g := board.game
	board.request_options(g.start_score, g.legs_to_win % 3 + 1, g.double_out)


func _on_finish() -> void:
	var g := board.game
	board.request_options(g.start_score, g.legs_to_win, not g.double_out)


func _key(action: String) -> String:
	return Settings.prompt(action) if Settings.has_method("prompt") else action


## Redraws everything from board.game. DartsBoard calls it on every state change.
func refresh() -> void:
	if board == null or _grid == null:
		return
	var g := board.game
	var me := multiplayer.get_unique_id()
	var captain := g.captain_peer() == me
	var lobby := g.phase == DartsMatch.Phase.LOBBY
	_title.text = "Darts  ·  %d" % g.start_score
	_info.text = g.describe() + ("" if lobby else "  ·  leg %d" % g.leg)

	for c in _grid.get_children():
		c.queue_free()
	for h in ["", "Left", "Legs", "Avg", "Last"]:
		_label(_grid, h, 16, UiTheme.MUTED)
	for i in g.players.size():
		var p: Dictionary = g.players[i]
		var throwing := g.phase == DartsMatch.Phase.PLAYING and i == g.current
		var col := UiTheme.BRASS if throwing else UiTheme.CREAM
		var who := ("> " if throwing else "  ") + String(p["name"]) + (" (away)" if p["away"] else "")
		_label(_grid, who, 22, col if not p["away"] else UiTheme.MUTED)
		_label(_grid, str(p["remaining"]), 26, col)
		_label(_grid, str(p["legs"]), 22, col)
		_label(_grid, "%.1f" % g.average(i), 18, UiTheme.MUTED)
		var last := int(p["last"])
		_label(_grid, "Bust" if last == -1 else ("-" if last < 0 else str(last)), 18, UiTheme.MUTED)

	var my_turn := board.is_local_turn()
	var thrower := String(g.thrower().get("name", ""))
	match g.phase:
		DartsMatch.Phase.LOBBY:
			_status.text = "Chalked up. Pick the game and start." if captain \
				else "Waiting for %s to start the game." % String(g.players[0]["name"]) if not g.players.is_empty() else ""
		DartsMatch.Phase.PLAYING:
			if g.turn_over:
				match g.note:
					"BUST": _status.text = "Bust! %s stays on %d." % [thrower, int(g.thrower()["remaining"])]
					"GAME SHOT": _status.text = "Game shot! %s takes the leg." % thrower
					"MATCH": _status.text = "Game shot, and the match! %s wins." % thrower
					_: _status.text = "%s scored %d." % [thrower, _turn_total()]
			elif bool(g.thrower().get("away", false)):
				_status.text = "Waiting for %s to come back to the oche." % thrower
			elif my_turn:
				_status.text = "Your throw. %d %s left." % [g.darts_left(), "dart" if g.darts_left() == 1 else "darts"]
			else:
				_status.text = "%s to throw." % thrower
		DartsMatch.Phase.FINISHED:
			var w := String(g.players[g.winner]["name"]) if g.winner >= 0 and g.winner < g.players.size() else "Someone"
			_status.text = "%s wins the match!" % w
	var darts := []
	for d in g.turn:
		darts.append(String(d["label"]))
	_turn_label.text = "" if darts.is_empty() else "%s   =  %d" % ["   ".join(darts), _turn_total()]
	var route := g.suggested_checkout()
	_checkout.text = "Checkout: " + "  ".join(route) if not route.is_empty() else ""

	_options.visible = lobby
	_start_btn.visible = lobby
	for b in [_game_btn, _legs_btn, _finish_btn, _start_btn]:
		b.disabled = not captain
	_game_btn.text = "%d" % g.start_score
	_legs_btn.text = "1 leg" if g.legs_to_win == 1 else "First to %d" % g.legs_to_win
	_finish_btn.text = "Double out" if g.double_out else "Straight out"
	_start_btn.text = "Start game" if g.players.size() > 1 else "Start (practice on your own)"
	_hint.text = "Left stick: aim.  Hold A to draw back, let go in the gold band: early drops low, late flies high.  %s: step away." % \
		(Settings.action_label("interact", "pad") if Settings.has_method("action_label") else "RT")

	if my_turn and not _was_turn:
		aim = Vector2.ZERO  # each turn starts on the bull: steer to where you want
		_aim_vel = Vector2.ZERO
	_was_turn = my_turn
	var vp := get_viewport()
	if my_turn:
		if vp != null:
			vp.gui_release_focus()
	elif vp != null and vp.gui_get_focus_owner() == null:
		if _start_btn.visible and not _start_btn.disabled:
			_start_btn.grab_focus()
		else:
			_away_btn.grab_focus()
	_view.queue_redraw()


func _turn_total() -> int:
	var t := 0
	for d in board.game.turn:
		t += int(d["score"])
	return t


func _process(delta: float) -> void:
	if board == null or not is_instance_valid(board):
		queue_free()
		return
	_t += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	var tipsy := 0.0
	var f := board._fighter_of(multiplayer.get_unique_id())
	if f != null:
		tipsy = clampf(f.tipsy, 0.0, 1.0)
	# Drawing back makes the hand shake more.
	var amp := (WOBBLE + TIPSY_WOBBLE * tipsy) * (1.35 if drawing else 1.0)
	wobble = Vector2(sin(_t * 1.7) + 0.6 * sin(_t * 3.9 + 1.0), cos(_t * 1.4) + 0.6 * sin(_t * 3.3)) * amp
	if board.is_local_turn():
		var stick := Vector2(Input.get_joy_axis(_pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(_pad, JOY_AXIS_LEFT_Y))
		if stick.length() < STICK_DEADZONE:
			stick = Vector2.ZERO
		_aim_vel = _aim_vel.lerp(stick * AIM_SPEED, clampf(AIM_GRIP * delta, 0.0, 1.0))
		aim = (aim + _aim_vel * delta).limit_length(DartsRules.R_BOARD)
		if drawing:
			_draw_t += delta
			power = pingpong(_draw_t / POWER_TIME, 1.0)
	else:
		drawing = false
	_view.queue_redraw()


## Controller only: A starts the power meter, letting go throws.
func _input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	if jb == null:
		return
	_pad = jb.device
	if jb.button_index != JOY_BUTTON_A or not board.is_local_turn():
		return
	if jb.pressed and not drawing and _cooldown <= 0.0:
		drawing = true
		_draw_t = 0.0
		power = 0.0
		get_viewport().set_input_as_handled()
	elif not jb.pressed and drawing:
		drawing = false
		throw(power)
		get_viewport().set_input_as_handled()


## Throws at where the reticle is now (aim plus wobble) with `with_power` from the meter.
func throw(with_power := DartsBoard.SWEET_SPOT) -> void:
	var g := board.game
	if _cooldown > 0.0 or not board.is_local_turn():
		return
	var key := g.serial
	if _sent_for == key and _t - _sent_t < 1.5:
		return  # still waiting for the host to score the last one
	_sent_for = key
	_sent_t = _t
	_cooldown = THROW_COOLDOWN
	board.request_throw(aim + wobble, with_power)


## Where the darts are going right now, for the board view.
func reticle() -> Vector2:
	return aim + wobble


class BoardView extends Control:
	var panel

	const METER_W := 64.0  ## room on the right for the power meter

	func _centre() -> Vector2:
		return Vector2((size.x - METER_W) * 0.5, size.y * 0.5)

	func _scale() -> float:
		return (minf(size.x - METER_W, size.y) * 0.5 - 4.0) / DartsRules.R_BOARD

	func to_view(p: Vector2) -> Vector2:
		return _centre() + p * _scale()

	func _draw() -> void:
		var c := _centre()
		var s := _scale()
		draw_circle(c, DartsRules.R_BOARD * s, Color("0d0c0b"))
		var bands := [[DartsRules.R_OUTER_BULL, DartsRules.R_TREBLE_IN, false],
			[DartsRules.R_TREBLE_IN, DartsRules.R_TREBLE_OUT, true],
			[DartsRules.R_TREBLE_OUT, DartsRules.R_DOUBLE_IN, false],
			[DartsRules.R_DOUBLE_IN, DartsRules.R_DOUBLE_OUT, true]]
		for i in 20:
			var a0 := deg_to_rad(-99.0 + i * 18.0)
			var a1 := a0 + deg_to_rad(18.0)
			for band in bands:
				var col: Color
				if band[2]:
					col = RED if i % 2 == 0 else GREEN
				else:
					col = BLACK if i % 2 == 0 else CREAM
				draw_colored_polygon(_sector(c, band[0] * s, band[1] * s, a0, a1), col)
		draw_circle(c, DartsRules.R_OUTER_BULL * s, GREEN)
		draw_circle(c, DartsRules.R_BULL * s, RED)
		for r in [DartsRules.R_BULL, DartsRules.R_OUTER_BULL, DartsRules.R_TREBLE_IN,
				DartsRules.R_TREBLE_OUT, DartsRules.R_DOUBLE_IN, DartsRules.R_DOUBLE_OUT]:
			draw_arc(c, r * s, 0, TAU, 96, WIRE, 1.0, true)
		for i in 20:
			var a := deg_to_rad(-99.0 + i * 18.0)
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * DartsRules.R_OUTER_BULL * s, c + d * DartsRules.R_DOUBLE_OUT * s, WIRE, 1.0, true)
		var font := get_theme_default_font()
		var fs := int(maxf(14.0, 22.0 * s / 1.15))
		for i in 20:
			var a := deg_to_rad(-90.0 + i * 18.0)
			var at := c + Vector2(cos(a), sin(a)) * 197.0 * s
			var txt := str(DartsRules.ORDER[i])
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, at + Vector2(-w.x * 0.5, w.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e8e2d0"))
		# Darts of this turn.
		for d in panel.board.game.turn:
			var p := to_view(Vector2(float(d["x"]), float(d["y"])))
			draw_circle(p, 5.0, Color("c9a03a"))
			draw_circle(p, 2.0, Color.BLACK)
			draw_string(font, p + Vector2(8, -6), String(d["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.CREAM)
		# The reticle on your throw, with what it's over.
		if panel.board.is_local_turn():
			var r: Vector2 = panel.reticle()
			var p := to_view(r)
			var col := UiTheme.ALE
			draw_arc(p, 9.0, 0, TAU, 32, col, 2.0, true)
			draw_line(p + Vector2(-15, 0), p + Vector2(-5, 0), col, 2.0)
			draw_line(p + Vector2(5, 0), p + Vector2(15, 0), col, 2.0)
			draw_line(p + Vector2(0, -15), p + Vector2(0, -5), col, 2.0)
			draw_line(p + Vector2(0, 5), p + Vector2(0, 15), col, 2.0)
			var over := String(DartsRules.score_at(r)["label"])
			draw_string(font, Vector2(10, size.y - 12), "Aiming at " + over, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.CREAM)
			_draw_power(font)

	## Power meter down the right edge: gold band = flat throw.
	func _draw_power(font: Font) -> void:
		var h := size.y * 0.7
		var rect := Rect2(size.x - 40, (size.y - h) * 0.5, 26, h)
		draw_rect(rect, Color(0, 0, 0, 0.7))
		var band := 0.04
		var sweet := DartsBoard.SWEET_SPOT
		var y0 := rect.end.y - (sweet + band) * h
		draw_rect(Rect2(rect.position.x, y0, rect.size.x, band * 2.0 * h), UiTheme.BRASS)
		if panel.drawing:
			var fill: float = panel.power
			var col := UiTheme.ALE if absf(fill - sweet) <= band else UiTheme.BLOOD
			draw_rect(Rect2(rect.position.x + 3, rect.end.y - fill * h, rect.size.x - 6, fill * h), Color(col, 0.85))
		draw_rect(rect, UiTheme.MUTED, false, 1.0)
		draw_string(font, Vector2(rect.position.x + 5, rect.position.y - 10), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiTheme.CREAM)

	func _sector(c: Vector2, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var steps := 6
		for k in steps + 1:
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r1)
		for k in range(steps, -1, -1):
			var a := lerpf(a0, a1, float(k) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r0)
		return pts
