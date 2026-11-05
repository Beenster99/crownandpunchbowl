class_name Moves
extends RefCounted
## Move table and global combat tuning. Owned by the combat workstream.
##
## Every attack a Fighter can do is a row in DATA. Controllers (player input, AI brains)
## only ever pass a move id to Fighter.request_attack(); the Fighter looks the numbers up
## here, lets an equipped weapon modify them, and runs the timeline.
##
## Move keys (all optional except damage):
##   damage: float      base damage before the attacker's power and difficulty
##   windup: float      seconds before the hit lands. For "telegraph" moves this is replaced
##                      by the difficulty's telegraph_time (times windup_scale), and it is
##                      the window the defender has to counter.
##   windup_scale: float scales telegraph_time for slower or faster tells (default 1.0)
##   active: float      seconds the hit is live (the hit resolves once, at the start)
##   recover: float     seconds after the hit before the fighter is free again
##   reach: float       metres from the attacker's centre to land the hit
##   arc: float         degrees of the hit cone in front of the attacker
##   sweep: bool        hit every enemy in the cone, not just the target (chairs, pool cues)
##   lunge: bool        travel to the target before striking (freeflow). Default true.
##   stagger: float     seconds the victim is staggered
##   poise: float       poise damage. A victim whose poise runs out is knocked down.
##   knockback: float   metres per second of shove on the victim
##   knockdown: bool    always knocks the victim down
##   heavy: bool        big impact: louder sound, shake, breaks grabs
##   to_face: bool      a face hit (can break a nose)
##   ground: bool       only hits fighters who are DOWN or CRAWLING (stomps)
##   telegraph: bool    an enemy tell: emits Events.attack_telegraphed and can be countered
##   keeps_hold: bool   used while GRABBING without letting go (knee)
##   self_damage: float damage the attacker takes on a hit (headbutts sting)
##   guard_break: bool  can't be blocked: a blocking victim is staggered (kicks, headbutts,
##                      haymakers). Telegraphed guard breakers are prompted as "dodge".

const HELD_DAMAGE_MULT := 1.5      ## held fighters take this much more damage from everyone
const GROUND_DAMAGE_MULT := 0.7    ## fighters on the floor take less (stomps excepted)
const LUNGE_SPEED := 4.5          ## m/s for the short step-in when a target is just out of reach
const LUNGE_RANGE := 2.6           ## how far soft-lock aiming will look for an enemy
const MAX_LUNGE_STEP := 0.8        ## the most a move will step in; further away, it whiffs in place
const MAX_LUNGE_TIME := 0.25       ## longest a step-in can delay the hit
const GRAB_RANGE := 1.5
const HOLD_TIME := 4.0             ## seconds a grip lasts before the victim slips free (x grip)
const ESCAPE_PER_STRUGGLE := 0.1   ## escape progress per struggle() call (1.0 = free)
const HOLD_DISTANCE := 0.75        ## how far in front of the holder the victim is held
const DODGE_TIME := 0.38
const DODGE_IFRAMES := 0.28
const DODGE_SPEED := 9.0
const DODGE_COOLDOWN := 0.15
const COUNTER_RANGE := 3.0         ## a tell within this distance is prompted to its target
const BLOCK_ARC := 140.0           ## degrees in front a block covers
const BLOCK_CHIP := 0.15           ## fraction of damage that gets through a block
const BLOCK_MOVE_SCALE := 0.45     ## speed while blocking
const PARRY_WINDOW := 0.2          ## block this soon before a punch lands to parry it
const PARRY_STAGGER := 1.0         ## how long a parried attacker reels
const COUNTER_WINDOW := 0.9        ## after a parry, a punch this soon is a counter
const COUNTER_BONUS := 1.6         ## damage multiplier on a counter
const GUARD_BREAK_STAGGER := 0.7   ## a blocker hit by a guard breaker reels this long
const ENGAGE_RANGE := 3.2          ## a player within this of an active enemy takes a stance
const STANCE_MOVE_SCALE := 0.7     ## speed in a fighting stance (footwork, not sprinting)
const STANCE_HOLD := 4.0           ## seconds a stance lasts after the last exchange
const POISE := 30.0                ## default poise, scaled by Fighter.toughness
const POISE_REGEN := 15.0          ## per second, when not being hit
const POISE_REGEN_DELAY := 1.2
const NOSE_BREAK_DAMAGE := 9.0     ## a face hit this hard can break a nose
const CRAWL_SPEED := 0.7
const GRAB_MOVE_SCALE := 0.45      ## holder's speed multiplier
const KNEE_COOLDOWN := 0.45
const LEDGE_THROW_RANGE := 2.2     ## a throw this close to a ledge, roughly towards it, goes over
const LEDGE_THROW_SPEED := 6.5     ## outward speed when thrown over an edge
const RAIL_VAULT_LIFT := 5.5       ## upward speed that carries a thrown body over a railing
const FALL_MIN_HEIGHT := 1.2       ## falls shorter than this don't hurt (a dais, the stairs)
const FALL_DAMAGE_PER_M := 12.0    ## damage per metre fallen beyond FALL_MIN_HEIGHT
const MAX_FALL := 12.0             ## sanity cap on a reported fall

const DATA := {
	# --- Player bare-knuckle ---------------------------------------------------
	&"jab": {"damage": 5.0, "windup": 0.07, "active": 0.05, "recover": 0.22, "reach": 1.3,
		"arc": 70.0, "stagger": 0.25, "poise": 6.0, "knockback": 1.0, "to_face": true},
	&"cross": {"damage": 7.0, "windup": 0.08, "active": 0.05, "recover": 0.25, "reach": 1.3,
		"arc": 70.0, "stagger": 0.3, "poise": 8.0, "knockback": 1.5, "to_face": true},
	&"hook": {"damage": 10.0, "windup": 0.12, "active": 0.06, "recover": 0.32, "reach": 1.3,
		"arc": 80.0, "stagger": 0.45, "poise": 14.0, "knockback": 2.5, "heavy": true, "to_face": true},
	&"uppercut": {"damage": 14.0, "windup": 0.16, "active": 0.06, "recover": 0.45, "reach": 1.2,
		"arc": 70.0, "stagger": 0.6, "poise": 30.0, "knockback": 3.0, "heavy": true, "to_face": true},
	&"kick": {"damage": 11.0, "windup": 0.16, "active": 0.07, "recover": 0.36, "reach": 1.65,
		"arc": 70.0, "stagger": 0.5, "poise": 16.0, "knockback": 4.0, "heavy": true, "guard_break": true},
	&"headbutt": {"damage": 14.0, "windup": 0.14, "active": 0.05, "recover": 0.42, "reach": 1.05,
		"arc": 60.0, "stagger": 0.7, "poise": 22.0, "knockback": 2.0, "heavy": true,
		"to_face": true, "self_damage": 2.0, "guard_break": true},
	&"stomp": {"damage": 9.0, "windup": 0.2, "active": 0.06, "recover": 0.4, "reach": 1.4,
		"arc": 90.0, "ground": true, "heavy": true},
	&"knee": {"damage": 8.0, "windup": 0.0, "active": 0.05, "recover": 0.0, "reach": 1.4,
		"arc": 60.0, "poise": 8.0, "keeps_hold": true, "lunge": false, "to_face": true},
	&"throw": {"damage": 8.0, "knockdown": true, "knockback": 7.0, "heavy": true, "lunge": false,
		"guard_break": true},

	# --- Enemy moves (telegraphed, counterable) --------------------------------
	&"swing": {"damage": 8.0, "telegraph": true, "windup_scale": 1.0, "active": 0.06,
		"recover": 0.5, "reach": 1.35, "arc": 70.0, "stagger": 0.35, "poise": 10.0,
		"knockback": 2.0, "to_face": true},
	&"haymaker": {"damage": 14.0, "telegraph": true, "windup_scale": 1.4, "active": 0.07,
		"recover": 0.7, "reach": 1.4, "arc": 80.0, "stagger": 0.6, "poise": 30.0,
		"knockback": 4.0, "heavy": true, "to_face": true, "guard_break": true},
	&"shove": {"damage": 3.0, "telegraph": true, "windup_scale": 0.8, "active": 0.05,
		"recover": 0.4, "reach": 1.3, "arc": 70.0, "stagger": 0.4, "poise": 12.0, "knockback": 5.0,
		"guard_break": true},
	&"baton": {"damage": 12.0, "telegraph": true, "windup_scale": 1.1, "active": 0.06,
		"recover": 0.55, "reach": 1.6, "arc": 80.0, "stagger": 0.5, "poise": 20.0,
		"knockback": 3.0, "heavy": true, "guard_break": true},
}

## Player punches: tap a hand for a quick punch, hold it for a heavy one.
const LEFT_TAP := &"jab"
const LEFT_HOLD := &"hook"
const RIGHT_TAP := &"cross"
const RIGHT_HOLD := &"uppercut"
const PUNCH_HOLD_TIME := 0.22            ## seconds a punch button is held to throw the heavy version
const BOTH_HANDS_WINDOW := 0.08    ## both punches pressed this close together = headbutt
## Strings of moves thrown in rhythm (each in the previous one's recovery, or just after)
## that pay off on the last move. Longest matches are checked first.
const COMBOS := [
	{"name": "The Full English", "seq": [&"jab", &"cross", &"hook", &"uppercut"],
		"bonus": 1.7, "knockdown": true},
	{"name": "Left, right, goodnight", "seq": [&"jab", &"cross", &"hook"], "bonus": 1.4},
	{"name": "Double jab, cross", "seq": [&"jab", &"jab", &"cross"], "bonus": 1.3},
	{"name": "Hook to the chin", "seq": [&"hook", &"uppercut"], "bonus": 1.3},
	{"name": "One-two", "seq": [&"jab", &"cross"], "bonus": 1.15},
]
const RHYTHM_GRACE := 0.4          ## after a move ends, the next one still continues the string
const INPUT_BUFFER := 0.15         ## a press this close before the chain window opens is kept
const MASH_LIMIT := 2              ## presses too early in a row before you fumble the string
const FUMBLE_TIME := 0.35          ## you're off balance this long after mashing
## Seconds without landing a hit before the combo counter resets.
const COMBO_TIMEOUT := 2.2


## The combo `history` (oldest first) completes, or {}.
static func match_combo(history: Array) -> Dictionary:
	for c in COMBOS:
		var seq: Array = c["seq"]
		if history.size() < seq.size():
			continue
		if history.slice(history.size() - seq.size()) == seq:
			return c
	return {}


static func has(move_id: StringName) -> bool:
	return DATA.has(move_id)


## A copy of the move row with defaults filled in.
static func get_move(move_id: StringName) -> Dictionary:
	var m: Dictionary = {
		"id": move_id, "damage": 0.0, "windup": 0.1, "windup_scale": 1.0, "active": 0.05,
		"recover": 0.3, "reach": 1.3, "arc": 70.0, "sweep": false, "lunge": true,
		"stagger": 0.3, "poise": 8.0, "knockback": 1.0, "knockdown": false, "heavy": false,
		"to_face": false, "ground": false, "telegraph": false, "keeps_hold": false,
		"self_damage": 0.0,
	}
	m.merge(DATA.get(move_id, {}), true)
	return m
