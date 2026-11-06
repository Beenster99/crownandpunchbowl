class_name Wounds
extends Node
## Localised damage: bruises, swelling and cuts that build up where punches land.
##
## Each fighter has a fixed set of spots (brows, eyes, cheeks, nose, lips, chin, jaw,
## forehead on the face; chest, gut and ribs on the body). Every clean hit marks one
## spot, picked from the move, the zone and the side it came from, and splashes a
## little bruising onto the spots next to it. Hitting the same spot again builds it up:
## the bruise darkens, the swelling grows faster with each repeat (a closing eye), and
## once a brow, cheekbone or lip has taken enough it splits open and bleeds.
##
## Networking: the host decides (it alone handles Fighter.hit_taken here) and sends the
## new values of the spot it changed to every peer, so everyone sees the same face.
## A peer that joins late asks the host for the whole lot. Nothing here touches gameplay.
##
## The look is drawn by WoundSkin (scripts/fx/wound_skin.gd) on the character's skin.
## Usage: Wounds.attach(fighter, rig). FighterVisual does it.

const NODE_NAME := "Wounds"

## Every spot. side: -1 = the fighter's left (model -X), +1 = right, 0 = middle.
## yaw/pitch (degrees) aim a ray at the skin from inside the head, level with the eyes (or
## from the chest); the spot sits where it comes out. cut: whether it splits (over bone: brows, cheekbones, lips);
## cut_angle tilts the split (0 runs across the face, 90 runs up and down).
const SPOTS: Array[Dictionary] = [
	{"id": &"forehead", "region": &"face", "side": 0, "yaw": 0.0, "pitch": 26.0, "radius": 0.04, "cut": true, "cut_angle": 8.0},
	{"id": &"brow_l", "region": &"face", "side": -1, "yaw": -18.0, "pitch": 11.0, "radius": 0.03, "cut": true, "cut_angle": -14.0},
	{"id": &"brow_r", "region": &"face", "side": 1, "yaw": 18.0, "pitch": 11.0, "radius": 0.03, "cut": true, "cut_angle": 14.0},
	{"id": &"eye_l", "region": &"face", "side": -1, "yaw": -17.0, "pitch": -3.0, "radius": 0.032, "cut": false, "cut_angle": 0.0},
	{"id": &"eye_r", "region": &"face", "side": 1, "yaw": 17.0, "pitch": -3.0, "radius": 0.032, "cut": false, "cut_angle": 0.0},
	{"id": &"cheek_l", "region": &"face", "side": -1, "yaw": -34.0, "pitch": -13.0, "radius": 0.034, "cut": true, "cut_angle": -32.0},
	{"id": &"cheek_r", "region": &"face", "side": 1, "yaw": 34.0, "pitch": -13.0, "radius": 0.034, "cut": true, "cut_angle": 32.0},
	{"id": &"nose", "region": &"face", "side": 0, "yaw": 0.0, "pitch": -10.0, "radius": 0.026, "cut": true, "cut_angle": 0.0},
	{"id": &"lip", "region": &"face", "side": 0, "yaw": 0.0, "pitch": -31.0, "radius": 0.026, "cut": true, "cut_angle": 90.0},
	{"id": &"chin", "region": &"face", "side": 0, "yaw": 0.0, "pitch": -47.0, "radius": 0.03, "cut": true, "cut_angle": 0.0},
	{"id": &"jaw_l", "region": &"face", "side": -1, "yaw": -52.0, "pitch": -38.0, "radius": 0.036, "cut": false, "cut_angle": 0.0},
	{"id": &"jaw_r", "region": &"face", "side": 1, "yaw": 52.0, "pitch": -38.0, "radius": 0.036, "cut": false, "cut_angle": 0.0},
	{"id": &"chest", "region": &"body", "side": 0, "yaw": 0.0, "pitch": 30.0, "radius": 0.08, "cut": false, "cut_angle": 0.0},
	{"id": &"gut", "region": &"body", "side": 0, "yaw": 0.0, "pitch": -42.0, "radius": 0.08, "cut": false, "cut_angle": 0.0},
	{"id": &"ribs_l", "region": &"body", "side": -1, "yaw": -75.0, "pitch": -5.0, "radius": 0.075, "cut": false, "cut_angle": 0.0},
	{"id": &"ribs_r", "region": &"body", "side": 1, "yaw": 75.0, "pitch": -5.0, "radius": 0.075, "cut": false, "cut_angle": 0.0},
]

## Neighbours that take a little of every hit (a black eye spreads to the cheek).
const NEAR := {
	&"forehead": [&"brow_l", &"brow_r"], &"brow_l": [&"eye_l", &"forehead"], &"brow_r": [&"eye_r", &"forehead"],
	&"eye_l": [&"brow_l", &"cheek_l"], &"eye_r": [&"brow_r", &"cheek_r"],
	&"cheek_l": [&"eye_l", &"jaw_l"], &"cheek_r": [&"eye_r", &"jaw_r"],
	&"nose": [&"eye_l", &"eye_r", &"lip"], &"lip": [&"nose", &"chin"], &"chin": [&"lip", &"jaw_l", &"jaw_r"],
	&"jaw_l": [&"cheek_l", &"chin"], &"jaw_r": [&"cheek_r", &"chin"],
	&"chest": [&"gut"], &"gut": [&"chest"], &"ribs_l": [&"gut"], &"ribs_r": [&"gut"],
}

## Where each kind of shot tends to land. "*" is a side spot: _l or _r from where it came.
const AIM := {
	&"jab": [&"nose", &"lip", &"eye*", &"brow*", &"cheek*"],
	&"counter_jab": [&"nose", &"lip", &"eye*", &"brow*", &"cheek*"],
	&"cross": [&"nose", &"eye*", &"cheek*", &"lip", &"brow*"],
	&"hook": [&"cheek*", &"eye*", &"jaw*", &"brow*"],
	&"swing": [&"cheek*", &"jaw*", &"eye*", &"brow*"],
	&"haymaker": [&"jaw*", &"cheek*", &"eye*", &"brow*"],
	&"uppercut": [&"chin", &"lip", &"nose"],
	&"headbutt": [&"nose", &"brow*", &"forehead"],
	&"clinch_knee": [&"nose", &"brow*", &"cheek*", &"forehead"],
	&"knee": [&"nose", &"brow*", &"cheek*", &"forehead"],
	&"stomp": [&"cheek*", &"brow*", &"forehead", &"jaw*"],
	&"body": [&"gut", &"chest", &"ribs*"],
	&"body_hook": [&"ribs*", &"ribs*", &"gut"],
	&"body_uppercut": [&"gut", &"chest"],
	&"kick": [&"ribs*", &"gut", &"chest"],
	&"face": [&"nose", &"cheek*", &"brow*", &"eye*", &"lip", &"forehead", &"chin", &"jaw*"],
}

const BODY_MOVES := [&"body_hook", &"body_uppercut", &"kick"]

## Per unit of hit strength (a cross is about 1): how much a spot bruises and swells.
const BRUISE_PER_HIT := 0.3
const SWELL_PER_HIT := 0.06  ## times the number of times the spot has been hit (up to 5)
const NEIGHBOUR_SHARE := 0.3
## Damage a spot soaks before it splits (the sum of hit strengths), and the strength of a
## single blow (or a bottle) that splits it at once.
const CUT_AFTER := 2.6
const CUT_ONE_SHOT := 1.5
const CUT_OPEN := 0.35
const CUT_GROW := 0.18

signal changed(spot: int)

var fighter: Node
## The look on the character. Null on a headless host or before the rig is built.
var skin: WoundSkin
var bruise := PackedFloat32Array()
var swell := PackedFloat32Array()
var cut := PackedFloat32Array()
var hits := PackedInt32Array()
var trauma := PackedFloat32Array()  # host only
## Seconds since each spot was first marked, counted locally (fresh red goes purple).
var age := PackedFloat32Array()
var _last := -1  # host: last spot hit (repeat shots favour it)
var _rng := RandomNumberGenerator.new()


static func attach(f: Node, rig: Node = null) -> Wounds:
	var w := f.get_node_or_null(NODE_NAME) as Wounds
	if w == null:
		w = Wounds.new()
		w.name = NODE_NAME
		w.fighter = f
		f.add_child(w)
	if rig != null and w.skin == null:
		w.skin = WoundSkin.new()
		w.skin.name = "WoundSkin"
		w.skin.setup(w, rig)
		w.add_child(w.skin)
	return w


static func spot_index(id: StringName) -> int:
	for i in SPOTS.size():
		if SPOTS[i]["id"] == id:
			return i
	return -1


func _init() -> void:
	bruise.resize(SPOTS.size())
	swell.resize(SPOTS.size())
	cut.resize(SPOTS.size())
	trauma.resize(SPOTS.size())
	age.resize(SPOTS.size())
	hits.resize(SPOTS.size())


func _ready() -> void:
	if fighter == null:
		fighter = get_parent()
	_rng.seed = hash(String(fighter.name))
	if fighter.has_signal("hit_taken"):
		fighter.hit_taken.connect(_on_hit_taken)
	# Through the node, not the autoload name: tests load this before autoloads exist.
	var events := get_node_or_null("/root/Events")
	if events != null and events.has_signal("nose_broken"):
		events.nose_broken.connect(func(f: Node): if f == fighter: break_nose())
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_request_all.rpc_id.call_deferred(1)


func _process(delta: float) -> void:
	for i in SPOTS.size():
		if bruise[i] > 0.0 or swell[i] > 0.0 or cut[i] > 0.0:
			age[i] += delta


# --- Queries ---------------------------------------------------------------------------

func bruise_of(id: StringName) -> float:
	var i := spot_index(id)
	return bruise[i] if i >= 0 else 0.0


func swell_of(id: StringName) -> float:
	var i := spot_index(id)
	return swell[i] if i >= 0 else 0.0


func cut_of(id: StringName) -> float:
	var i := spot_index(id)
	return cut[i] if i >= 0 else 0.0


func hits_on(id: StringName) -> int:
	var i := spot_index(id)
	return hits[i] if i >= 0 else 0


func is_marked() -> bool:
	for i in SPOTS.size():
		if bruise[i] > 0.0 or swell[i] > 0.0 or cut[i] > 0.0:
			return true
	return false


## The worst-hit spot's id, or &"" when unmarked.
func worst() -> StringName:
	var best := -1
	var score := 0.0
	for i in SPOTS.size():
		var s := bruise[i] + swell[i] + cut[i]
		if s > score:
			score = s
			best = i
	return SPOTS[best]["id"] if best >= 0 else &""


# --- Host: deciding where a hit lands ----------------------------------------------------

func _on_hit_taken(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if bool(info.get("blocked", false)) or bool(info.get("parried", false)) \
			or bool(info.get("slipped", false)):
		return
	var dmg := float(info.get("damage", 0.0))
	if dmg <= 0.0:
		return
	var spot := pick_spot(info)
	if spot < 0:
		return
	apply_hit(spot, strength(info))


## How hard a hit marks: about 1 for a cross, more for heavy, clean or weapon shots.
func strength(info: Dictionary) -> float:
	var k := float(info.get("damage", 0.0)) / 9.0
	if bool(info.get("heavy", false)):
		k *= 1.25
	if bool(info.get("clean", false)):
		k *= 1.25
	if info.get("weapon") != null:
		k *= 1.4
	# A fully loaded hook or uppercut (combat's "power", 0..1) cuts deeper.
	k *= 1.0 + 0.3 * clampf(float(info.get("power", 0.0)), 0.0, 1.0)
	return clampf(k, 0.1, 3.0)


## Which spot a hit marks (host). -1 when it lands somewhere that doesn't show (groin).
func pick_spot(info: Dictionary) -> int:
	var zone := StringName(info.get("zone", &"head"))
	if zone == &"groin":
		return -1
	var move := StringName(info.get("move", ""))
	var pool: Array = AIM.get(move, [])
	if zone == &"body" and not move in BODY_MOVES:
		pool = AIM[&"body"]
	elif pool.is_empty():
		pool = AIM[&"face"]
	var side := _struck_side(info)
	var picks: Array[int] = []
	for p in pool:
		var id := String(p)
		if id.ends_with("*"):
			id = id.trim_suffix("*") + ("_l" if side < 0 else "_r")
		var i := spot_index(StringName(id))
		if i >= 0:
			picks.append(i)
	if picks.is_empty():
		return -1
	# Keep hitting the same place: that's how a fighter gets cut up.
	if _last in picks and _rng.randf() < 0.45:
		return _last
	# Earlier entries are the likeliest.
	var weights: Array[float] = []
	var total := 0.0
	for n in picks.size():
		var w := 1.0 / (1.0 + n * 0.6)
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	for n in picks.size():
		r -= weights[n]
		if r <= 0.0:
			return picks[n]
	return picks[0]


## -1 if the hit came in on the fighter's left (it pushes them to their right), +1 right.
func _struck_side(info: Dictionary) -> int:
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var local := Vector3.ZERO
	if fighter is Node3D and dir != Vector3.ZERO:
		local = (fighter as Node3D).global_basis.inverse() * dir
	if absf(local.x) < 0.2:
		var side := float(info.get("side", 0.0))
		if side != 0.0:
			# A hook from the attacker's right lands on the victim's left (they face each other).
			return -1 if side > 0.0 else 1
		return -1 if _rng.randf() < 0.5 else 1
	return -1 if local.x > 0.0 else 1


## Mark spot `i` with a hit of strength `k` (host). Sends the result to every peer.
func apply_hit(i: int, k: float) -> void:
	_last = i
	var h := hits[i] + 1
	var b := minf(bruise[i] + BRUISE_PER_HIT * k, 1.0)
	var s := minf(swell[i] + SWELL_PER_HIT * k * mini(h, 5), 1.0)
	var c := cut[i]
	trauma[i] += k
	if bool(SPOTS[i]["cut"]):
		if c > 0.0:
			c = minf(c + CUT_GROW * k, 1.0)
		elif trauma[i] >= CUT_AFTER or k >= CUT_ONE_SHOT:
			c = CUT_OPEN
	_send(i, b, s, c, h)
	for id in NEAR.get(SPOTS[i]["id"], []):
		var n := spot_index(id)
		var nb := minf(bruise[n] + BRUISE_PER_HIT * k * NEIGHBOUR_SHARE, 1.0)
		var ns := minf(swell[n] + SWELL_PER_HIT * k * NEIGHBOUR_SHARE, 1.0)
		trauma[n] += k * NEIGHBOUR_SHARE
		_send(n, nb, ns, cut[n], hits[n])


## A broken nose swells up at once and blackens both eyes a little.
func break_nose() -> void:
	if not multiplayer.is_server():
		return
	var n := spot_index(&"nose")
	_send(n, maxf(bruise[n], 0.7), maxf(swell[n], 0.7), maxf(cut[n], CUT_OPEN), maxi(hits[n], 1))
	for id in [&"eye_l", &"eye_r"]:
		var e := spot_index(id)
		_send(e, maxf(bruise[e], 0.35), swell[e], cut[e], hits[e])


func _send(i: int, b: float, s: float, c: float, h: int) -> void:
	if multiplayer.has_multiplayer_peer() and is_inside_tree():
		_rpc_spot.rpc(i, b, s, c, h)
	else:
		_set_spot(i, b, s, c, h)


# --- Networking -------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func _rpc_spot(i: int, b: float, s: float, c: float, h: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_set_spot(i, b, s, c, h)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_all() -> void:
	if not multiplayer.is_server():
		return
	var data := PackedFloat32Array()
	for i in SPOTS.size():
		data.append_array([bruise[i], swell[i], cut[i], float(hits[i])])
	_rpc_all.rpc_id(multiplayer.get_remote_sender_id(), data)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_all(data: PackedFloat32Array) -> void:
	if multiplayer.get_remote_sender_id() != 1 or data.size() != SPOTS.size() * 4:
		return
	for i in SPOTS.size():
		_set_spot(i, data[i * 4], data[i * 4 + 1], data[i * 4 + 2], int(data[i * 4 + 3]))


func _set_spot(i: int, b: float, s: float, c: float, h: int) -> void:
	if i < 0 or i >= SPOTS.size():
		return
	bruise[i] = clampf(b, 0.0, 1.0)
	swell[i] = clampf(s, 0.0, 1.0)
	cut[i] = clampf(c, 0.0, 1.0)
	hits[i] = h
	changed.emit(i)
