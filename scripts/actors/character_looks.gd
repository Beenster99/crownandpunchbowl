@tool
class_name CharacterLooks
extends RefCounted
## Look data for every character in the game. Farmer ids match GameData.FARMERS.
## Punter, police and staff ids are the types the AI workstream spawns.
##
## Crowds must not be clones, so punter(), police() and staff() take a seed and vary
## colours, hair and build. Use a seed every peer agrees on (for example the NPC's
## number from its node name "N<n>") so a punter looks the same on every machine.

const H := CharacterLook.Hair
const B := CharacterLook.Beard
const T := CharacterLook.Top
const O := CharacterLook.Over
const C := CharacterLook.Hat

## The six playable farmers. Five men and one woman, each with a silhouette you can
## pick out from the camera height: a giant, a whippet, a stooped old boy, a sturdy
## dairy farmer, a swaying drunk and a bearded handyman.
const FARMERS := {
	"tom": {
		"display_name": "Tom \"Muckspreader\" Pryce",
		"description": "Six foot five of shaved head and boiler suit. The forehead is load-bearing.",
		"height": 1.12, "girth": 1.45, "shoulders": 1.4, "belly": 0.55, "limb_thickness": 1.45,
		"head_size": 1.18, "hand_size": 1.35, "brow": 1.0,
		"skin": "e9a98a", "flush": "d4705c", "nose_size": 1.25,
		"hair": H.SHAVED, "hair_color": "8a6a4e", "beard": B.STUBBLE, "beard_color": "6b4a32",
		"top": T.BOILER_SUIT, "top_color": "3f5f86", "top_trim": "2f4866", "sleeves_rolled": true,
		"trousers_color": "3f5f86", "boots_color": "6b4b2a",
	},
	"gaz": {
		"display_name": "Gaz Whitlock",
		"description": "Wiry hedge-layer in a ripped fleece and a beanie. Long arms, ginger goatee, never still.",
		"height": 0.96, "girth": 0.78, "shoulders": 0.9, "belly": 0.0, "limb_thickness": 0.75,
		"arm_length": 1.12, "leg_length": 1.04, "head_size": 0.95, "hand_size": 1.05, "brow": 0.2,
		"skin": "f1c6a6", "flush": "e08a77",
		"hair": H.MOP, "hair_color": "c2622d", "beard": B.GOATEE, "beard_color": "b5582a",
		"top": T.FLEECE, "top_color": "556b2f", "top_trim": "3d4d22", "sleeves_rolled": false,
		"trousers_color": "4b5320", "boots_color": "3a2a1a",
		"hat": C.BEANIE, "hat_color": "e0752a",
	},
	"barrow": {
		"display_name": "Old Man Barrow",
		"description": "Seventy-three, bent like a hawthorn, tweed cap, white mutton chops and a nose like a plum.",
		"height": 0.94, "girth": 0.92, "shoulders": 0.88, "belly": 0.25, "limb_thickness": 0.82,
		"arm_length": 1.05, "head_size": 1.02, "hand_size": 1.2, "stoop": 24.0, "brow": 0.6,
		"skin": "e7b9a0", "flush": "c4413a", "nose_size": 1.6,
		"hair": H.BALD, "hair_color": "e9e6df", "beard": B.MUTTON_CHOPS, "beard_color": "efece6",
		"top": T.WAX_JACKET, "top_color": "7a5a3a", "top_trim": "a68a5b",
		"over": O.WAISTCOAT, "over_color": "8f6a3f",
		"trousers_color": "b08a3e", "boots_color": "4a3220",
		"hat": C.FLAT_CAP, "hat_color": "8a7356",
		"neckerchief": true, "neckerchief_color": "b03a2e",
	},
	"mags": {
		"display_name": "Margaret \"Mags\" Fenwick",
		"description": "Dairy farmer and parish councillor. Quilted gilet, red check shirt, wellies and a grip like a gate latch.",
		"feminine": true,
		"height": 0.97, "girth": 1.05, "shoulders": 0.98, "belly": 0.1, "limb_thickness": 1.05,
		"head_size": 0.98, "hand_size": 1.45, "brow": 0.15,
		"skin": "e4ae8c", "flush": "d98270", "nose_size": 0.9,
		"hair": H.BUN, "hair_color": "8e3b22",
		"top": T.SHIRT, "top_color": "b0302c", "top_trim": "3b1a18", "sleeves_rolled": true,
		"over": O.GILET, "over_color": "1f3a5f",
		"trousers_color": "4d4a3a", "boots_color": "2f5a2e", "wellies": true,
	},
	"dicky": {
		"display_name": "Dicky Thresher",
		"description": "Battered trilby, comb-over, braces holding up the belly. Sways like a barley field in a breeze.",
		"height": 1.0, "girth": 1.25, "shoulders": 1.0, "belly": 1.0, "limb_thickness": 1.05,
		"head_size": 1.06, "hand_size": 1.05, "sway": 1.0, "stoop": 6.0, "brow": 0.3,
		"skin": "f0b89c", "flush": "d2433e", "nose_size": 1.4,
		"hair": H.COMB_OVER, "hair_color": "5a4632", "beard": B.STUBBLE, "beard_color": "6a5440",
		"top": T.SHIRT, "top_color": "d8c9a8", "top_trim": "8a2f2f", "sleeves_rolled": false,
		"over": O.BRACES, "over_color": "8a2f2f",
		"trousers_color": "5d4a3a", "boots_color": "2a1d14",
		"hat": C.TRILBY, "hat_color": "6d5b45",
	},
	"kev": {
		"display_name": "Kev Haybale",
		"description": "Bib-and-brace overalls, tool belt, full beard and a cap. Can fix anything, can break anything.",
		"height": 1.03, "girth": 1.15, "shoulders": 1.18, "belly": 0.2, "limb_thickness": 1.18,
		"head_size": 1.0, "hand_size": 1.25, "brow": 0.45,
		"skin": "8d5a3b", "flush": "7a4630",
		"hair": H.SHORT, "hair_color": "1d1712", "beard": B.FULL, "beard_color": "241a12",
		"top": T.SHIRT, "top_color": "6f8a5a", "top_trim": "4c6040", "sleeves_rolled": true,
		"over": O.OVERALLS, "over_color": "34506e",
		"trousers_color": "34506e", "boots_color": "7a5226",
		"hat": C.BASEBALL_CAP, "hat_color": "9a2a22", "tool_belt": true,
	},
}

## Punter types. The AI workstream decides how tough each one is. These are looks only.
const PUNTERS := {
	"second_homer_gilet": {
		"description": "Down from London for the weekend. Navy gilet, pale blue shirt, stone chinos, loafers.",
		"girth": 0.92, "shoulders": 0.92, "limb_thickness": 0.85, "brow": 0.1,
		"hair": H.SIDE_PARTING, "top": T.SHIRT, "top_color": "a9c4e0", "top_trim": "ffffff",
		"over": O.GILET, "over_color": "1d2a44",
		"trousers_color": "cbb98f", "boots_color": "6b3d22",
	},
	"second_homer_chinos": {
		"description": "Red trousers, jumper over a collared shirt, floppy hair, boat shoes. Owns three houses here.",
		"girth": 0.9, "shoulders": 0.9, "limb_thickness": 0.85, "brow": 0.1,
		"hair": H.FLOPPY, "top": T.JUMPER, "top_color": "e3c9a2", "top_trim": "ffffff",
		"trousers_color": "b8433b", "boots_color": "7b5a3a",
	},
	"rambler": {
		"description": "Weekend walker in a cagoule and a bobble hat. Came in for a ploughman's.",
		"girth": 0.95, "belly": 0.3, "limb_thickness": 0.9, "glasses": true,
		"hair": H.SHORT, "top": T.CAGOULE, "top_color": "2a7ab0", "top_trim": "1a4a70",
		"trousers_color": "4a4a46", "shorts": true, "boots_color": "5a3a22",
		"hat": C.BOBBLE_HAT, "hat_color": "c23b30",
	},
	"local": {
		"description": "A villager who isn't a farmer. Hoodie or jumper, jeans, trainers. Picks a side late.",
		"girth": 1.05, "belly": 0.35, "limb_thickness": 1.0,
		"hair": H.SHORT, "top": T.HOODIE, "top_color": "555b63", "top_trim": "3a3e44",
		"trousers_color": "33415c", "boots_color": "d8d8d8",
	},
	"rugby_lad": {
		"description": "Thick neck, hooped rugby shirt, collar up. Comes in fours.",
		"height": 1.06, "girth": 1.35, "shoulders": 1.45, "limb_thickness": 1.35, "head_size": 0.95,
		"brow": 0.6, "hair": H.SHAVED, "top": T.RUGBY_SHIRT, "top_color": "1f3d7a", "top_trim": "e6e0cf",
		"trousers_color": "b9ad8c", "boots_color": "4a2f1c",
	},
}

const POLICE := {
	"constable": {
		"description": "Custodian helmet, black jacket, hi-vis vest. Turns up in pairs.",
		"girth": 1.08, "shoulders": 1.1, "limb_thickness": 1.1, "brow": 0.4,
		"hair": H.SHORT, "top": T.POLICE, "top_color": "1a1d24", "top_trim": "ffffff",
		"over": O.HI_VIS, "over_color": "d8e83a",
		"trousers_color": "1a1d24", "boots_color": "0f0f12",
		"hat": C.POLICE_HELMET, "hat_color": "16192a",
	},
	"sergeant": {
		"description": "Peaked cap, stripes, bigger than the constables and in no mood.",
		"height": 1.07, "girth": 1.3, "shoulders": 1.3, "belly": 0.35, "limb_thickness": 1.25, "brow": 0.7,
		"hair": H.SHORT, "beard": B.MOUSTACHE,
		"top": T.POLICE, "top_color": "1a1d24", "top_trim": "ffffff",
		"over": O.HI_VIS, "over_color": "d8e83a",
		"trousers_color": "1a1d24", "boots_color": "0f0f12",
		"hat": C.POLICE_CAP, "hat_color": "16192a",
	},
}

const STAFF := {
	"barman": {
		"description": "Polishing a glass he has polished for twenty years. Never joins in.",
		"girth": 1.1, "belly": 0.5, "hair": H.SHORT,
		"top": T.BAR_SHIRT, "top_color": "f2efe6", "top_trim": "1b1b1b",
		"over": O.APRON, "over_color": "2b2b2b", "sleeves_rolled": true,
		"trousers_color": "222222", "boots_color": "111111",
	},
	"barwoman": {
		"description": "Has seen worse. Has served worse. Will not be knocked out.",
		"feminine": true, "girth": 0.95, "hair": H.PONYTAIL,
		"top": T.BAR_SHIRT, "top_color": "1b1b1b", "top_trim": "8a1f2a",
		"over": O.WAISTCOAT, "over_color": "5a1620", "sleeves_rolled": true,
		"trousers_color": "222222", "boots_color": "111111",
	},
}

## Palettes the crowd variations draw from.
const SKIN_TONES := ["f3d0b5", "eab595", "d99a74", "c08055", "9a6342", "7a4a30", "5a3522", "f0c8a8"]
const HAIR_COLORS := ["1d1712", "3b2a1e", "5a4030", "8a6a40", "c2a066", "a8502a", "8f8f8f", "d8d4cc"]
const VARY := {
	"second_homer_gilet": {"over_color": ["1d2a44", "2e4a3a", "5a1a2a", "3a3a3a"],
		"top_color": ["a9c4e0", "f2f0ea", "e3b8c4", "c6d9b8"], "trousers_color": ["cbb98f", "e6dcc4", "6d7b8e"]},
	"second_homer_chinos": {"top_color": ["e3c9a2", "f0a6b4", "8fb0d9", "f2efe6", "3a5a40"],
		"trousers_color": ["b8433b", "d36a4a", "e3d3a8", "7aa0c9"], "hair": [H.FLOPPY, H.SIDE_PARTING]},
	"rambler": {"top_color": ["2a7ab0", "c23b30", "e0a22a", "3a7a3a", "6a3a8a"],
		"hat_color": ["c23b30", "2a5a9a", "e0e0e0", "3a7a3a"], "shorts": [true, false]},
	"local": {"top": [T.HOODIE, T.JUMPER, T.FLEECE, T.SHIRT],
		"top_color": ["555b63", "2e3a59", "6b2a2a", "3f5a3a", "8a7a5a", "1f1f1f"],
		"hair": [H.SHORT, H.SHAVED, H.MOP, H.BALD, H.SIDE_PARTING],
		"beard": [B.NONE, B.NONE, B.STUBBLE, B.FULL, B.GOATEE],
		"hat": [C.NONE, C.NONE, C.NONE, C.BASEBALL_CAP, C.BEANIE]},
	"rugby_lad": {"top_color": ["1f3d7a", "6b1a2a", "1a5a32", "1b1b1b", "d0a020"],
		"top_trim": ["e6e0cf", "d0a020", "ffffff"], "hair": [H.SHAVED, H.SHORT, H.FLOPPY]},
}


static func farmer(id: String) -> CharacterLook:
	return _make(id, FARMERS, id)


static func punter(type: String, seed := 0) -> CharacterLook:
	var look := _make(type, PUNTERS, "%s_%d" % [type, seed])
	_vary(look, type, seed)
	return look


static func police(type := "constable", seed := 0) -> CharacterLook:
	var look := _make(type, POLICE, "%s_%d" % [type, seed])
	_vary(look, type, seed)
	return look


static func staff(type := "barman", seed := 0) -> CharacterLook:
	var look := _make(type, STAFF, type)
	_vary(look, type, seed)
	return look


## Any look by id, searching farmers, punters, police and staff in that order.
static func by_id(id: String, seed := 0) -> CharacterLook:
	if FARMERS.has(id):
		return farmer(id)
	if PUNTERS.has(id):
		return punter(id, seed)
	if POLICE.has(id):
		return police(id, seed)
	if STAFF.has(id):
		return staff(id, seed)
	push_error("CharacterLooks: no look called '%s'" % id)
	return CharacterLook.new()


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for table in [FARMERS, PUNTERS, POLICE, STAFF]:
		for id in table:
			ids.append(id)
	return ids


static func _make(type: String, table: Dictionary, id: String) -> CharacterLook:
	if not table.has(type):
		push_error("CharacterLooks: no look called '%s'" % type)
		return CharacterLook.new()
	var d: Dictionary = table[type].duplicate()
	d["id"] = id
	d["model"] = type
	d["model_height"] = d.get("height", 1.0)
	d["model_girth"] = d.get("girth", 1.0)
	if not d.has("display_name"):
		d["display_name"] = type.capitalize()
	return CharacterLook.from_dict(d)


## Deterministic per seed: the same type and seed always give the same person.
static func _vary(look: CharacterLook, type: String, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [type, seed])
	var skin := Color(SKIN_TONES[rng.randi() % SKIN_TONES.size()])
	look.skin = skin
	look.flush = skin.lerp(Color("c4483e"), rng.randf_range(0.15, 0.4))
	look.hair_color = Color(HAIR_COLORS[rng.randi() % HAIR_COLORS.size()])
	look.beard_color = look.hair_color
	look.height *= rng.randf_range(0.94, 1.06)
	look.girth *= rng.randf_range(0.92, 1.1)
	if look.feminine or look.top == CharacterLook.Top.POLICE:
		pass
	elif look.beard == CharacterLook.Beard.NONE and rng.randf() < 0.25:
		look.beard = CharacterLook.Beard.STUBBLE
	var options: Dictionary = VARY.get(type, {})
	for key in options:
		var choices: Array = options[key]
		var value = choices[rng.randi() % choices.size()]
		look.set(key, Color(value) if value is String else value)
