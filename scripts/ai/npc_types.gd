class_name NpcTypes
extends RefCounted
## Stats and personality for every kind of NPC. Owned by the AI workstream.
##
## Fighter stats (max_hp, power, move_speed, toughness, grip, crawl_fraction) are applied
## before the fighter enters the tree, so the difficulty's enemy_health still scales max_hp.
##
## Personality keys:
##   bravery: float      0..1 chance to join in when a mate nearby is hit (else just watch)
##   aggression: float   scales how often an engaged NPC attacks (shorter cooldowns)
##   watch_distance: float metres an ALERT NPC keeps from the nearest player. Cowards keep more.
##   circle_distance: float ring an ENGAGED NPC circles on while waiting for an attack token
##   struggle_interval: float seconds between struggles while held (lower escapes faster)
##   defence: float      0..1 chance to read a punch being lined up at them and cover up
##                       (or step back from a kick)
##   guard_skill: float  0..1 chance that cover is the right one (head or body)
##   parry: float        0..1 chance a last-moment cover parries (Fighter.parry_skill)
##   hold_resist: float  0..1 how hard they are to hold (Fighter.hold_resist)
##   stamina: float      the gas tank (Fighter.max_stamina). Soft types gas out sooner.
##   counter: float      0..1 chance to fire a quick counter jab straight off a blocked punch
##   combo: float        0..1 chance a punch is followed by one or two more (Moves.PUNTER_FOLLOW_UPS)
##   feint: float        0..1 chance a punch is a feint: the tell starts, then he pulls out
##   moves: Dictionary   move id -> weight. Enemy moves are telegraphed (see Moves.DATA).
##   grabs: bool         can grab a player during a gang-up so mates can lay into them
##   always_engaged: bool police never calm down
##   colour: Color       placeholder body tint until real character art lands

const DATA := {
	## Second-homers: gilets, chinos, soft hands. Fold quickly, often hang back.
	&"second_homer": {
		"max_hp": 60.0, "power": 0.75, "move_speed": 3.9, "toughness": 0.8, "grip": 0.8,
		"crawl_fraction": 0.35, "bravery": 0.25, "aggression": 0.7, "watch_distance": 5.5,
		"circle_distance": 3.2, "struggle_interval": 0.5, "defence": 0.25, "guard_skill": 0.5,
		"parry": 0.0, "hold_resist": 0.05, "stamina": 70.0, "counter": 0.1,
		"combo": 0.15, "feint": 0.05,
		"moves": {&"shove": 3, &"swing": 2, &"body_swing": 1, &"punter_jab": 1}, "grabs": false, "always_engaged": false,
		"colour": Color("9aa77a"),
	},
	## Locals who side with the incomers (or just fancy a scrap).
	&"local": {
		"max_hp": 90.0, "power": 1.0, "move_speed": 4.1, "toughness": 1.0, "grip": 1.0,
		"crawl_fraction": 0.25, "bravery": 0.6, "aggression": 1.0, "watch_distance": 4.0,
		"circle_distance": 2.8, "struggle_interval": 0.35, "defence": 0.45, "guard_skill": 0.65,
		"parry": 0.1, "hold_resist": 0.25, "stamina": 100.0, "counter": 0.3,
		"combo": 0.45, "feint": 0.25,
		"moves": {&"punter_jab": 3, &"punter_cross": 2, &"swing": 2, &"body_swing": 2, &"haymaker": 1,
			&"shove": 1}, "grabs": false,
		"always_engaged": false, "colour": Color("b9824f"),
	},
	## Rugby lads down for the weekend. Hard to put down, love a gang-up.
	&"rugby_lad": {
		"max_hp": 140.0, "power": 1.3, "move_speed": 4.4, "toughness": 1.6, "grip": 1.3,
		"crawl_fraction": 0.2, "bravery": 0.9, "aggression": 1.25, "watch_distance": 3.2,
		"circle_distance": 2.6, "struggle_interval": 0.2, "defence": 0.4, "guard_skill": 0.6,
		"parry": 0.05, "hold_resist": 0.6, "stamina": 120.0, "counter": 0.25,
		"combo": 0.3, "feint": 0.1,
		"moves": {&"haymaker": 2, &"swing": 2, &"body_swing": 2, &"shove": 1, &"punter_cross": 2,
			&"punter_jab": 1}, "grabs": true,
		"always_engaged": false, "colour": Color("8c2f39"),
	},
	## The Old Bill. Batons, always on the job.
	&"police": {
		"max_hp": 130.0, "power": 1.15, "move_speed": 4.6, "toughness": 1.4, "grip": 1.4,
		"crawl_fraction": 0.2, "bravery": 1.0, "aggression": 1.2, "watch_distance": 3.0,
		"circle_distance": 2.6, "struggle_interval": 0.25, "defence": 0.55, "guard_skill": 0.75,
		"parry": 0.15, "hold_resist": 0.45, "stamina": 110.0, "counter": 0.4,
		"combo": 0.2, "feint": 0.1,
		"moves": {&"baton": 3, &"shove": 1}, "grabs": true, "always_engaged": true,
		"colour": Color("1f2d5c"),
	},
	## Bar staff: never hostile, can't be knocked out, stay behind the bar.
	&"staff": {
		"max_hp": 100.0, "power": 0.0, "move_speed": 2.5, "toughness": 1.5, "grip": 1.0,
		"crawl_fraction": 0.0, "bravery": 0.0, "aggression": 0.0, "watch_distance": 0.0,
		"circle_distance": 0.0, "struggle_interval": 0.3, "defence": 0.0, "guard_skill": 0.0,
		"parry": 0.0, "hold_resist": 0.0, "stamina": 100.0, "counter": 0.0, "combo": 0.0, "feint": 0.0, "moves": {}, "grabs": false,
		"always_engaged": false, "colour": Color("d9d2c0"),
	},
}

## Default crowd mix for a pub (weights). Pubs can override Director.punter_mix.
const DEFAULT_MIX := {&"second_homer": 4, &"local": 4, &"rugby_lad": 2}


static func get_type(kind: StringName) -> Dictionary:
	if not DATA.has(kind):
		push_warning("Unknown NPC kind %s, using local" % kind)
		return DATA[&"local"]
	return DATA[kind]


## Weighted random pick from a {key: weight} dictionary.
static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys().back()
