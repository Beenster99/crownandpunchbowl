@tool
class_name CharacterLook
extends Resource
## Everything that makes one character look different on the shared rig:
## build, colours, clothes, hair and hat. CharacterRig reads this and builds the body.
## The data for every farmer, punter, police officer and member of bar staff is in
## CharacterLooks. See docs/CHARACTERS.md.

enum Hair { BALD, SHAVED, SHORT, SIDE_PARTING, MOP, COMB_OVER, BUN, PONYTAIL, FLOPPY }
enum Beard { NONE, STUBBLE, FULL, GOATEE, MUTTON_CHOPS, MOUSTACHE }
enum Top { SHIRT, JUMPER, BOILER_SUIT, WAX_JACKET, FLEECE, RUGBY_SHIRT, POLICE, BAR_SHIRT, HOODIE, CAGOULE }
enum Over { NONE, GILET, OVERALLS, HI_VIS, APRON, WAISTCOAT, BRACES }
enum Hat { NONE, FLAT_CAP, BEANIE, TRILBY, BASEBALL_CAP, POLICE_HELMET, POLICE_CAP, BOBBLE_HAT, HEADSCARF }

@export var id := ""
@export var display_name := ""
## One line used on cards and in the docs.
@export_multiline var description := ""
@export var feminine := false

@export_group("Build")
## Uniform scale. 1.0 is about 1.78 m tall.
@export_range(0.8, 1.3) var height := 1.0
## Torso width and depth.
@export_range(0.7, 1.6) var girth := 1.0
## Extra on the shoulders, independent of girth.
@export_range(0.7, 1.6) var shoulders := 1.0
## 0 is a flat stomach, 1 is a proper ale belly.
@export_range(0.0, 1.0) var belly := 0.0
@export_range(0.6, 1.6) var limb_thickness := 1.0
@export_range(0.85, 1.25) var arm_length := 1.0
@export_range(0.85, 1.15) var leg_length := 1.0
@export_range(0.8, 1.4) var head_size := 1.0
@export_range(0.8, 1.6) var hand_size := 1.0
## Forward hunch in degrees, applied under the chest (old age, drink).
@export_range(0.0, 35.0) var stoop := 0.0
## Idle sway amount (drunks). 0 is steady.
@export_range(0.0, 1.0) var sway := 0.0

@export_group("Face and hair")
@export var skin := Color("e8b48f")
## Nose and cheek colour. Drinkers get a redder one.
@export var flush := Color("d9826b")
@export_range(0.7, 1.8) var nose_size := 1.0
## Heavy brow ridge (Tom's forehead).
@export_range(0.0, 1.0) var brow := 0.3
@export var hair := Hair.SHORT
@export var hair_color := Color("4a3222")
@export var beard := Beard.NONE
@export var beard_color := Color("4a3222")
@export var glasses := false

@export_group("Clothes")
@export var top := Top.SHIRT
@export var top_color := Color("7a8c9e")
## Stripes, collars, cuffs, checks.
@export var top_trim := Color("e8e1cf")
@export var sleeves_rolled := false
@export var over := Over.NONE
@export var over_color := Color("2a3550")
@export var trousers_color := Color("39465a")
@export var shorts := false
@export var boots_color := Color("2b2018")
## Wellies come up to the knee.
@export var wellies := false
@export var hat := Hat.NONE
@export var hat_color := Color("5a4a38")
@export var tool_belt := false
@export var neckerchief := false
@export var neckerchief_color := Color("a3302a")


## Builds a look from a plain dictionary. Unknown keys are an error so typos show up.
static func from_dict(d: Dictionary) -> CharacterLook:
	var look := CharacterLook.new()
	var names := {}
	for p in look.get_property_list():
		names[p["name"]] = true
	for key in d:
		if not names.has(key):
			push_error("CharacterLook: unknown key '%s' in '%s'" % [key, d.get("id", "?")])
			continue
		var value = d[key]
		if value is String and typeof(look.get(key)) == TYPE_COLOR:
			value = Color(value)
		look.set(key, value)
	return look
