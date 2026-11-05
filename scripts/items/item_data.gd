class_name ItemData
extends RefCounted
## Item table and bar/drink tuning. Owned by the items workstream (5).
##
## Every pickup in a pub is a row in KINDS. A PubItem only stores its kind id and its
## remaining durability; everything else is looked up here.
##
## Kind keys (all optional):
##   name: String         shown in the HUD / prompts
##   type: String         "weapon" (pick up and swing), "consumable" (drink or eat on pick-up)
##   two_handed: bool     big furniture: slower movement, held in front
##   speed_mult: float    holder's move speed while carrying it
##   damage_mult: float   multiplies the damage of every swing move (see SWING_MOVES)
##   reach_add: float     metres added to the swing's reach
##   arc: float           replaces the swing's arc (degrees) if set
##   sweep: bool          hits everyone in the arc (chairs, cues)
##   windup_add, recover_add: float   slower, heavier swings
##   poise_mult, knockback_mult, stagger_mult: float
##   heavy, to_face, knockdown: bool  forced onto the swing
##   sharp: bool          cuts (gore can read item.sharp from the hit's "weapon")
##   durability: int      hits before it breaks. -1 never breaks (iron pokers)
##   breaks_into: Array   kinds left behind when it breaks. The first goes in the
##                        holder's hand, the rest drop at their feet
##   throw_damage: float  damage when it hits someone in flight
##   throw_speed: float   m/s
##   throw_range: float   metres before it starts to drop
##   throw_knockdown: bool
##   fragile: bool        smashes when thrown, whether it hits someone or the floor
##   ammo: int            darts: how many come in a set; each throw sends one
##   heal: float          consumables: hp healed instantly
##   heal_over_time: float consumables: hp healed over HEAL_TICKS ticks (food)
##   tipsy: float         consumables: added to Fighter.tipsy
##   leaves: String       consumables: kind put in the drinker's hand afterwards (empty glass)
##   mesh: Array          placeholder look: ["cyl", radius, height, Color] or ["box", Vector3, Color]

const KINDS := {
	# --- Glassware ---------------------------------------------------------------------
	&"bottle": {"name": "Bottle", "type": "weapon", "damage_mult": 1.5, "reach_add": 0.15,
		"heavy": true, "to_face": true, "durability": 1, "breaks_into": [&"broken_bottle"],
		"throw_damage": 12.0, "throw_speed": 14.0, "throw_range": 9.0, "fragile": true,
		"mesh": ["cyl", 0.04, 0.3, Color("2f5d34")]},
	&"broken_bottle": {"name": "Broken bottle", "type": "weapon", "damage_mult": 1.35,
		"reach_add": 0.1, "sharp": true, "durability": 4, "stagger_mult": 1.2,
		"throw_damage": 7.0, "throw_speed": 13.0, "throw_range": 7.0, "fragile": true,
		"mesh": ["cyl", 0.04, 0.17, Color("3f7a45")]},
	&"glass": {"name": "Pint glass", "type": "weapon", "damage_mult": 1.45, "heavy": true,
		"to_face": true, "durability": 1, "breaks_into": [],
		"throw_damage": 11.0, "throw_speed": 14.0, "throw_range": 9.0, "fragile": true,
		"mesh": ["cyl", 0.045, 0.15, Color(0.85, 0.9, 0.95, 0.6)]},

	# --- Furniture ---------------------------------------------------------------------
	&"chair": {"name": "Chair", "type": "weapon", "two_handed": true, "speed_mult": 0.75,
		"damage_mult": 2.0, "reach_add": 0.5, "arc": 140.0, "sweep": true, "windup_add": 0.14,
		"recover_add": 0.2, "poise_mult": 2.0, "knockback_mult": 1.6, "knockdown": true,
		"heavy": true, "durability": 2, "breaks_into": [&"chair_leg", &"chair_leg"],
		"throw_damage": 16.0, "throw_speed": 9.0, "throw_range": 5.0, "throw_knockdown": true,
		"mesh": ["box", Vector3(0.45, 0.9, 0.45), Color("6b4325")]},
	&"stool": {"name": "Bar stool", "type": "weapon", "two_handed": true, "speed_mult": 0.82,
		"damage_mult": 1.8, "reach_add": 0.35, "arc": 120.0, "sweep": true, "windup_add": 0.1,
		"recover_add": 0.15, "poise_mult": 1.8, "knockback_mult": 1.4, "heavy": true,
		"durability": 3, "breaks_into": [&"chair_leg"],
		"throw_damage": 14.0, "throw_speed": 10.0, "throw_range": 6.0, "throw_knockdown": true,
		"mesh": ["cyl", 0.18, 0.75, Color("5a3a20")]},
	&"chair_leg": {"name": "Chair leg", "type": "weapon", "damage_mult": 1.35, "reach_add": 0.35,
		"durability": 6, "breaks_into": [],
		"throw_damage": 8.0, "throw_speed": 13.0, "throw_range": 8.0,
		"mesh": ["box", Vector3(0.05, 0.5, 0.05), Color("6b4325")]},
	&"table_leg": {"name": "Table leg", "type": "weapon", "damage_mult": 1.6, "reach_add": 0.5,
		"windup_add": 0.05, "heavy": true, "poise_mult": 1.4, "durability": 8, "breaks_into": [],
		"throw_damage": 10.0, "throw_speed": 12.0, "throw_range": 7.0,
		"mesh": ["box", Vector3(0.08, 0.75, 0.08), Color("4a2d18")]},

	# --- Games room --------------------------------------------------------------------
	&"pool_cue": {"name": "Pool cue", "type": "weapon", "damage_mult": 1.25, "reach_add": 1.0,
		"arc": 100.0, "sweep": true, "recover_add": 0.08, "durability": 3,
		"breaks_into": [&"broken_cue"],
		"throw_damage": 7.0, "throw_speed": 12.0, "throw_range": 8.0,
		"mesh": ["cyl", 0.015, 1.45, Color("c79a5a")]},
	&"broken_cue": {"name": "Snapped cue", "type": "weapon", "damage_mult": 1.3, "reach_add": 0.4,
		"sharp": true, "durability": 5, "breaks_into": [],
		"throw_damage": 7.0, "throw_speed": 13.0, "throw_range": 8.0,
		"mesh": ["cyl", 0.018, 0.7, Color("c79a5a")]},
	&"darts": {"name": "Darts", "type": "weapon", "damage_mult": 0.8, "reach_add": 0.05,
		"sharp": true, "durability": -1, "ammo": 3,
		"throw_damage": 6.0, "throw_speed": 20.0, "throw_range": 11.0,
		"mesh": ["box", Vector3(0.03, 0.03, 0.16), Color("c23b22")]},

	# --- Fireplace ---------------------------------------------------------------------
	&"poker": {"name": "Fire poker", "type": "weapon", "damage_mult": 1.7, "reach_add": 0.6,
		"heavy": true, "poise_mult": 1.3, "durability": -1,
		"throw_damage": 11.0, "throw_speed": 12.0, "throw_range": 7.0,
		"mesh": ["cyl", 0.012, 0.8, Color("2b2b2b")]},
	&"coal_shovel": {"name": "Coal shovel", "type": "weapon", "damage_mult": 1.6, "reach_add": 0.55,
		"heavy": true, "to_face": true, "knockback_mult": 1.8, "windup_add": 0.04,
		"durability": -1,
		"throw_damage": 10.0, "throw_speed": 11.0, "throw_range": 6.0,
		"mesh": ["box", Vector3(0.18, 0.7, 0.05), Color("3a3a3a")]},

	# --- Bar ---------------------------------------------------------------------------
	&"pint": {"name": "Pint of ale", "type": "consumable", "heal": 12.0, "tipsy": 0.2,
		"leaves": &"glass", "mesh": ["cyl", 0.05, 0.16, Color("b8741a")]},
	&"food": {"name": "Pie and chips", "type": "consumable", "heal_over_time": 40.0,
		"mesh": ["cyl", 0.14, 0.04, Color("e9e2d0")]},
}

## Moves that use the held weapon. Kicks, headbutts, stomps and knees stay bare.
const SWING_MOVES: Array[StringName] = [
	&"jab", &"cross", &"hook", &"uppercut", &"counter", &"swing", &"haymaker", &"baton",
]

const PICKUP_RANGE := 1.5        ## metres (flat) to pick up or consume a loose item
const PICKUP_HEIGHT := 1.6       ## items higher than this above the feet can't be reached
const BAR_RANGE := 1.4           ## metres from the bar's front edge to order
const DRINK_SERVE_TIME := 1.2    ## seconds the barman takes to pull a pint
const FOOD_SERVE_TIME := 4.0     ## seconds for the microwave to ding
const ORDER_COOLDOWN := 0.5
const HEAL_TICKS := 8            ## food heals over this many ticks...
const HEAL_TICK_TIME := 0.75     ## ...this far apart
const TIPSY_DECAY := 0.008       ## per second
const TIPSY_POWER := 0.15        ## +15% damage when fully tipsy (Dutch courage)
const TIPSY_TOUGHNESS := 0.25    ## +25% toughness when fully tipsy (feels no pain)
const TIPSY_SLOW := 0.15         ## -15% move speed when fully tipsy
const TIPSY_SWAY := 1.3          ## m/s of sideways wobble when fully tipsy
const DRUNKEN_MASTER_POWER := 0.45  ## Dicky's trait: replaces TIPSY_POWER
const SEASONED_DRINKER_HEAL := 2.0  ## Barrow's trait: ale heals this much more
const HANDYMAN_DURABILITY := 1.5    ## Kev's trait: weapons last this much longer
const THROW_AIM_RANGE := 10.0    ## throws home in on an enemy within this range
const THROW_HIT_RADIUS := 0.55
const THROW_HEIGHT := 1.3        ## height a throw is released at
const GRAVITY := 14.0
const MAX_FLIGHT_TIME := 3.0


static func has(kind: StringName) -> bool:
	return KINDS.has(kind)


static func get_kind(kind: StringName) -> Dictionary:
	return KINDS.get(kind, {})


static func is_weapon(kind: StringName) -> bool:
	return String(get_kind(kind).get("type", "")) == "weapon"


static func is_consumable(kind: StringName) -> bool:
	return String(get_kind(kind).get("type", "")) == "consumable"


## The trait id of a fighter's farmer ("" if none). Players spawned with a farmer_index
## use GameData.FARMERS; anyone else can carry a "trait" meta.
static func trait_of(f: Node) -> String:
	if f == null:
		return ""
	if "farmer_index" in f:
		var i := int(f.get("farmer_index"))
		if i >= 0 and i < GameData.FARMERS.size():
			return String(GameData.FARMERS[i].get("trait", ""))
	return String(f.get_meta("trait", ""))
