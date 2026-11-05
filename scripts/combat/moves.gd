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

const HELD_DAMAGE_MULT := 1.5      ## held fighters take this much more damage from everyone
const GROUND_DAMAGE_MULT := 0.7    ## fighters on the floor take less (stomps excepted)
const LUNGE_SPEED := 10.0          ## m/s while closing on a target
const LUNGE_RANGE := 5.0           ## how far freeflow targeting will reach for an enemy
const MAX_LUNGE_TIME := 0.5        ## longest a lunge can delay the hit
const GRAB_RANGE := 1.5
const HOLD_TIME := 4.0             ## seconds a grip lasts before the victim slips free (x grip)
const ESCAPE_PER_STRUGGLE := 0.1   ## escape progress per struggle() call (1.0 = free)
const HOLD_DISTANCE := 0.75        ## how far in front of the holder the victim is held
const DODGE_TIME := 0.38
const DODGE_IFRAMES := 0.28
const DODGE_SPEED := 9.0
const DODGE_COOLDOWN := 0.15
const COUNTER_RANGE := 3.0         ## a tell within this distance can be countered
const POISE := 30.0                ## default poise, scaled by Fighter.toughness
const POISE_REGEN := 15.0          ## per second, when not being hit
const POISE_REGEN_DELAY := 1.2
const NOSE_BREAK_DAMAGE := 9.0     ## a face hit this hard can break a nose
const CRAWL_SPEED := 0.7
const GRAB_MOVE_SCALE := 0.45      ## holder's speed multiplier
const KNEE_COOLDOWN := 0.45

const DATA := {
	# --- Player bare-knuckle ---------------------------------------------------
	&"jab": {"damage": 5.0, "windup": 0.07, "active": 0.05, "recover": 0.22, "reach": 1.3,
		"arc": 70.0, "stagger": 0.25, "poise": 6.0, "knockback": 1.0, "to_face": true},
	&"cross": {"damage": 7.0, "windup": 0.08, "active": 0.05, "recover": 0.25, "reach": 1.3,
		"arc": 70.0, "stagger": 0.3, "poise": 8.0, "knockback": 1.5, "to_face": true},
	&"hook": {"damage": 10.0, "windup": 0.12, "active": 0.06, "recover": 0.32, "reach": 1.3,
		"arc": 80.0, "stagger": 0.45, "poise": 14.0, "knockback": 2.5, "heavy": true, "to_face": true},
	&"uppercut": {"damage": 16.0, "windup": 0.16, "active": 0.06, "recover": 0.45, "reach": 1.3,
		"arc": 70.0, "stagger": 0.6, "poise": 40.0, "knockback": 4.0, "knockdown": true,
		"heavy": true, "to_face": true},
	&"kick": {"damage": 11.0, "windup": 0.16, "active": 0.07, "recover": 0.36, "reach": 1.65,
		"arc": 70.0, "stagger": 0.5, "poise": 16.0, "knockback": 4.0, "heavy": true},
	&"headbutt": {"damage": 14.0, "windup": 0.14, "active": 0.05, "recover": 0.42, "reach": 1.05,
		"arc": 60.0, "stagger": 0.7, "poise": 22.0, "knockback": 2.0, "heavy": true,
		"to_face": true, "self_damage": 2.0},
	&"stomp": {"damage": 9.0, "windup": 0.2, "active": 0.06, "recover": 0.4, "reach": 1.4,
		"arc": 90.0, "ground": true, "heavy": true},
	&"counter": {"damage": 10.0, "windup": 0.0, "active": 0.05, "recover": 0.25, "reach": 1.4,
		"arc": 120.0, "stagger": 0.9, "poise": 25.0, "knockback": 3.0, "heavy": true, "to_face": true},
	&"counter_whiff": {"damage": 0.0, "windup": 0.0, "active": 0.0, "recover": 0.4, "lunge": false},
	&"knee": {"damage": 8.0, "windup": 0.0, "active": 0.05, "recover": 0.0, "reach": 1.4,
		"arc": 60.0, "poise": 8.0, "keeps_hold": true, "lunge": false, "to_face": true},
	&"throw": {"damage": 8.0, "knockdown": true, "knockback": 7.0, "heavy": true, "lunge": false},

	# --- Enemy moves (telegraphed, counterable) --------------------------------
	&"swing": {"damage": 8.0, "telegraph": true, "windup_scale": 1.0, "active": 0.06,
		"recover": 0.5, "reach": 1.35, "arc": 70.0, "stagger": 0.35, "poise": 10.0,
		"knockback": 2.0, "to_face": true},
	&"haymaker": {"damage": 14.0, "telegraph": true, "windup_scale": 1.4, "active": 0.07,
		"recover": 0.7, "reach": 1.4, "arc": 80.0, "stagger": 0.6, "poise": 30.0,
		"knockback": 4.0, "heavy": true, "to_face": true},
	&"shove": {"damage": 3.0, "telegraph": true, "windup_scale": 0.8, "active": 0.05,
		"recover": 0.4, "reach": 1.3, "arc": 70.0, "stagger": 0.4, "poise": 12.0, "knockback": 5.0},
	&"baton": {"damage": 12.0, "telegraph": true, "windup_scale": 1.1, "active": 0.06,
		"recover": 0.55, "reach": 1.6, "arc": 80.0, "stagger": 0.5, "poise": 20.0,
		"knockback": 3.0, "heavy": true},
}

## Light punch chain. The player's punch button walks along this, then loops.
const PUNCH_CHAIN: Array[StringName] = [&"jab", &"cross", &"hook"]
## A combo of at least this many hits turns the next punch into a finisher.
const FINISHER_COMBO := 8
const FINISHER_MOVE := &"uppercut"
## Seconds without landing a hit before the combo counter resets.
const COMBO_TIMEOUT := 2.2


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
