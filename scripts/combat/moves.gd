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
##   zone: StringName   where it lands: &"head" (default), &"body" or &"groin". A head guard
##                      (LB) only stops head shots and a body guard (RB) body and groin shots.
##                      A fresh slip of the head (right stick) makes head shots miss.
##   side: float        a hook's sideways push (-1 from the left hand, +1 from the right). The
##                      victim's head is knocked that way instead of straight back.
##   charge: bool       a shoulder charge: after the wind-up the attacker drives forward at
##                      CHARGE_SPEED for `active` seconds and hits the first enemy it meets.
##   clinch: bool       the attacker grabs the victim's head with both hands first (the clinch
##                      knee): it ignores a guard and pulls the victim in.
##   doubles: bool      a hit doubles the victim over (on all fours, holding their crotch).
##   stamina: float     stamina it costs to throw (default 3 + damage * 0.8). A whiff costs
##                      the same again on top.
##   guard_drain: float stamina a blocker loses when it hits their guard (default damage *
##                      1.2). Jabs drain far more than they cost: that's how you open a guard.
##   chargeable: bool   held down, it loads into a power shot (hooks and uppercuts).

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
## A strike lands on its target only within reach plus this, and inside its arc: the man
## has to still be there. A miss costs WHIFF_RECOVER more recovery and stumbles you forward.
const REACH_SLACK := 0.15
const WHIFF_RECOVER := 0.18
const WHIFF_STUMBLE := 1.3
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
const COUNTER_BONUS := 1.8         ## damage multiplier on a counter
const GUARD_BREAK_STAGGER := 0.7   ## a blocker hit by a guard breaker reels this long
const ENGAGE_RANGE := 3.2          ## a player within this of an active enemy takes a stance
const STANCE_MOVE_SCALE := 0.6     ## speed in a fighting stance (footwork, not sprinting)
const STANCE_HOLD := 4.0           ## seconds a stance lasts after the last exchange
## Poise is how much punishment a fighter soaks before going down. It's high, and comes back
## quickly once they get a breather, so a fight is a series of exchanges with people backing
## off to recover, not one punch and they're on the floor.
const POISE := 70.0                ## default poise, scaled by Fighter.toughness
const POISE_REGEN := 24.0          ## per second, when not being hit
const POISE_REGEN_DELAY := 0.9
## Hits on a fighter who's still reeling chip less poise, so you can't stun-lock them down.
const STAGGER_POISE_SCALE := 0.6
## A head guard (LB) stops head shots; a body guard (RB) stops body and groin shots.
const GUARD_HEAD := &"head"
const GUARD_BODY := &"body"
## Slipping: a flick of the right stick moves the head. For this long after the flick, head
## shots miss, and slipping one right as it lands (SLIP_COUNTER_WINDOW) sets up a counter.
const SLIP_WINDOW := 0.35
const SLIP_COUNTER_WINDOW := 0.2
const SLIP_COOLDOWN := 0.25        ## a second flick this soon doesn't slip (no stick wiggling)
const SLIP_THRESHOLD := 0.6        ## stick deflection that counts as a flick
## Doubled over from a kick in the groin: on all fours for this long (divided by toughness).
const DOUBLED_TIME := 2.6
## Shoulder charge.
const CHARGE_SPEED := 8.5
const CHARGE_HIT_RANGE := 0.95     ## metres from the charger's centre that a body is hit
## Holds: a victim with hold_resist shrugs a grab off with this chance (resist / holder grip),
## halved if they're reeling or doubled over. Resist also makes them wriggle free faster.
const SHRUG_STAGGER := 0.45        ## the would-be holder reels this long when shrugged off
## Stamina is the gas tank. Every strike costs some, a miss costs double, blocking a hit
## drains it, and body shots sap it. It only comes back when you stop throwing. A gassed
## fighter (under GASSED of it) hits soft, winds up slow, moves slow, and a guard that
## runs dry is crushed: they reel, wide open. So the man who throws everything loses.
const STAMINA := 100.0
const STAMINA_REGEN := 22.0         ## per second, once you've stopped throwing
const STAMINA_REGEN_DELAY := 0.6    ## after a strike or a drain before it starts coming back
const STAMINA_BLOCK_REGEN := 0.5    ## regen rate while holding a guard
const WHIFF_STAMINA := 1.0          ## a miss costs this many times the move's cost again
const GASSED := 0.25                ## fraction of stamina below which you're gassed
const GASSED_DAMAGE := 0.6
const GASSED_WINDUP := 1.3
const GASSED_SPEED := 0.8
const GUARD_CRUSH_STAGGER := 0.9    ## a guard that runs out of stamina: they reel this long
const BODY_SHOT_DRAIN := 1.5        ## a body or groin shot also drains damage * this stamina
## Power shots: hold a hook or an uppercut and it loads. Let go to throw it. You're stood
## there coiled, so a jab in the face cancels it. Full power breaks a guard.
const CHARGE_TIME := 0.8            ## seconds of holding to full power
const CHARGE_HOLD := 0.5            ## held at full power this long, it goes on its own
const POWER_MAX := 1.9              ## damage (and stagger/poise) multiplier at full power
const POWER_MIN := 0.15             ## less charge than this is just a normal punch
const POWER_STAMINA := 0.8          ## a full-power shot costs this much extra (x its cost)
## A punch that goes into the gap in a guard (at the body of a man covering his head, or the
## head of one covering his body) is a clean shot: harder, heavier, and it rocks him.
const CLEAN_BONUS := 1.35
## A parry or slip timed this close to the punch landing is a perfect read: time dips for a
## beat (solo only) and the counter window opens as usual.
const PERFECT_WINDOW := 0.1
const PERFECT_SLOWMO := 0.35        ## seconds of slow motion (real time)
const PERFECT_TIME_SCALE := 0.3
## Catch a man in the recovery of a punch (above all one that missed) and it's a punish.
const PUNISH_BONUS := 1.35
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
	# Paced to read as weighty, not frantic: every punch has a visible load and a recovery
	# you have to respect. Heavier punches commit you for longer. Poise is the knockdown
	# meter: no single punch drops a fresh man, a good combination or a body-head mix does.
	&"jab": {"stamina": 6.0, "guard_drain": 13.0,
		"damage": 5.0, "windup": 0.12, "active": 0.06, "recover": 0.3, "reach": 1.3,
		"arc": 70.0, "stagger": 0.25, "poise": 6.0, "knockback": 1.2, "to_face": true},
	&"cross": {"stamina": 10.0, "guard_drain": 11.0, "chargeable": true,
		"damage": 9.0, "windup": 0.2, "active": 0.06, "recover": 0.4, "reach": 1.35,
		"arc": 70.0, "stagger": 0.4, "poise": 12.0, "knockback": 2.2, "to_face": true},
	&"hook": {"stamina": 13.0, "guard_drain": 10.0, "chargeable": true,
		"damage": 11.0, "windup": 0.22, "active": 0.07, "recover": 0.45, "reach": 1.25,
		"arc": 90.0, "stagger": 0.5, "poise": 16.0, "knockback": 2.4, "heavy": true,
		"to_face": true, "side": 1.0},
	&"uppercut": {"stamina": 17.0, "guard_drain": 9.0, "chargeable": true,
		"damage": 14.0, "windup": 0.3, "active": 0.07, "recover": 0.55, "reach": 1.15,
		"arc": 70.0, "stagger": 0.6, "poise": 22.0, "knockback": 3.0, "heavy": true, "to_face": true},
	# Body shots (RB + punch): less damage, but they sap poise and slow a man down, and a
	# fighter covering his head is open to them.
	&"body_jab": {"stamina": 6.0, "guard_drain": 10.0,
		"damage": 4.0, "windup": 0.13, "active": 0.06, "recover": 0.32, "reach": 1.25,
		"arc": 70.0, "stagger": 0.25, "poise": 10.0, "knockback": 0.9, "zone": &"body"},
	&"body_hook": {"stamina": 12.0, "guard_drain": 12.0, "chargeable": true,
		"damage": 8.0, "windup": 0.22, "active": 0.07, "recover": 0.45, "reach": 1.2,
		"arc": 90.0, "stagger": 0.45, "poise": 22.0, "knockback": 1.6, "zone": &"body", "side": 1.0},
	&"body_uppercut": {"stamina": 15.0, "guard_drain": 12.0, "chargeable": true,
		"damage": 10.0, "windup": 0.28, "active": 0.07, "recover": 0.5, "reach": 1.1,
		"arc": 70.0, "stagger": 0.55, "poise": 26.0, "knockback": 1.8, "heavy": true, "zone": &"body"},
	&"kick": {"stamina": 18.0,
		"damage": 11.0, "windup": 0.3, "active": 0.08, "recover": 0.5, "reach": 1.65,
		"arc": 70.0, "stagger": 0.55, "poise": 20.0, "knockback": 4.0, "heavy": true,
		"guard_break": true, "zone": &"body"},
	# The end of "Below the belt": a kick to the crotch that drops them on all fours.
	&"groin_kick": {"damage": 12.0, "windup": 0.26, "active": 0.08, "recover": 0.5, "reach": 1.55,
		"arc": 70.0, "stagger": 0.4, "poise": 0.0, "knockback": 0.6, "heavy": true,
		"zone": &"groin", "doubles": true},
	&"headbutt": {"damage": 14.0, "windup": 0.26, "active": 0.06, "recover": 0.5, "reach": 1.05,
		"arc": 60.0, "stagger": 0.7, "poise": 26.0, "knockback": 2.4, "heavy": true,
		"to_face": true, "self_damage": 2.0, "guard_break": true},
	# LB + Y: drop the shoulder and drive through them. Knocks them flat and sends them into
	# (or over) whatever is behind them.
	&"shoulder_charge": {"stamina": 24.0,
		"damage": 10.0, "windup": 0.28, "active": 0.42, "recover": 0.55,
		"reach": 1.0, "arc": 60.0, "stagger": 0.6, "poise": 0.0, "knockback": 9.5,
		"knockdown": true, "heavy": true, "guard_break": true, "lunge": false, "charge": true,
		"zone": &"body"},
	# LB + B: both hands behind their head, pull it down onto a rising knee.
	&"clinch_knee": {"stamina": 18.0,
		"damage": 15.0, "windup": 0.3, "active": 0.08, "recover": 0.55, "reach": 1.1,
		"arc": 70.0, "stagger": 0.8, "poise": 30.0, "knockback": 1.6, "heavy": true,
		"to_face": true, "guard_break": true, "clinch": true},
	&"stomp": {"damage": 9.0, "windup": 0.32, "active": 0.06, "recover": 0.5, "reach": 1.4,
		"arc": 90.0, "ground": true, "heavy": true},
	&"knee": {"stamina": 3.0,
		"damage": 8.0, "windup": 0.0, "active": 0.05, "recover": 0.0, "reach": 1.4,
		"arc": 60.0, "poise": 8.0, "keeps_hold": true, "lunge": false, "to_face": true},
	&"throw": {"stamina": 8.0,
		"damage": 8.0, "knockdown": true, "knockback": 7.0, "heavy": true, "lunge": false,
		"guard_break": true},

	# --- Enemy moves (telegraphed, counterable) --------------------------------
	&"swing": {"damage": 8.0, "telegraph": true, "windup_scale": 1.0, "active": 0.06,
		"recover": 0.7, "reach": 1.35, "arc": 70.0, "stagger": 0.35, "poise": 12.0,
		"knockback": 2.0, "to_face": true, "side": 1.0},
	&"body_swing": {"damage": 7.0, "telegraph": true, "windup_scale": 1.0, "active": 0.06,
		"recover": 0.7, "reach": 1.3, "arc": 70.0, "stagger": 0.35, "poise": 14.0,
		"knockback": 1.4, "zone": &"body"},
	# Off the back of a blocked punch: a short, quick tell, then a stiff jab back.
	&"counter_jab": {"damage": 6.0, "telegraph": true, "windup_scale": 0.55, "active": 0.06,
		"recover": 0.45, "reach": 1.35, "arc": 70.0, "stagger": 0.3, "poise": 8.0,
		"knockback": 1.4, "to_face": true},
	&"haymaker": {"damage": 14.0, "telegraph": true, "windup_scale": 1.5, "active": 0.07,
		"recover": 0.95, "reach": 1.4, "arc": 80.0, "stagger": 0.6, "poise": 30.0,
		"knockback": 4.0, "heavy": true, "to_face": true, "guard_break": true, "side": 1.0},
	&"shove": {"damage": 3.0, "telegraph": true, "windup_scale": 0.8, "active": 0.05,
		"recover": 0.4, "reach": 1.3, "arc": 70.0, "stagger": 0.4, "poise": 12.0, "knockback": 5.0,
		"guard_break": true, "zone": &"body"},
	&"baton": {"damage": 12.0, "telegraph": true, "windup_scale": 1.1, "active": 0.06,
		"recover": 0.55, "reach": 1.6, "arc": 80.0, "stagger": 0.5, "poise": 20.0,
		"knockback": 3.0, "heavy": true, "guard_break": true},
}

## Enemy tells are this much longer than the difficulty's telegraph_time, so you can see
## someone lining a punch up and decide what to do about it.
const ENEMY_WINDUP_SCALE := 1.35
## Locomotion has weight: speeding up and slowing down take a moment (m/s per second).
const ACCEL := 16.0
const DECEL := 20.0
## Knockback slides off more slowly while staggering, so a big hit makes you stumble.
const STAGGER_DRAG := 7.0
## A punch carries you forward into it (m/s on the strike).
const FOLLOW_THROUGH := 1.4

## Player buttons (controller): X jab, B hook, Y uppercut. Held with RB (body guard) they go
## to the body. Held with LB (head guard): X kick, Y shoulder charge, B clinch knee.
## LB + RB together is a hold. R3 headbutt. A dodges along the left stick.
const PUNCHES := {&"jab": &"jab", &"hook": &"hook", &"uppercut": &"uppercut"}
const BODY_PUNCHES := {&"jab": &"body_jab", &"hook": &"body_hook", &"uppercut": &"body_uppercut"}
const LB_MOVES := {&"jab": &"kick", &"uppercut": &"shoulder_charge", &"hook": &"clinch_knee"}
## LB and RB pressed this close together is a hold, not a guard.
const BOTH_GUARDS_WINDOW := 0.12
## Strings of moves thrown in rhythm (each in the previous one's recovery, or just after)
## that pay off on the last move. Longest matches are checked first. "becomes" swaps the last
## move for another (the kick at the end of "Below the belt" goes low).
const COMBOS := [
	{"name": "The Full English", "seq": [&"jab", &"jab", &"hook", &"uppercut"],
		"bonus": 1.7, "knockdown": true},
	{"name": "Below the belt", "seq": [&"jab", &"body_jab", &"kick"], "bonus": 1.0,
		"becomes": &"groin_kick"},
	{"name": "Up and under", "seq": [&"body_hook", &"hook", &"uppercut"], "bonus": 1.5},
	{"name": "Left, right, goodnight", "seq": [&"jab", &"hook", &"uppercut"], "bonus": 1.45},
	{"name": "Double jab, hook", "seq": [&"jab", &"jab", &"hook"], "bonus": 1.3},
	{"name": "Downstairs, upstairs", "seq": [&"body_hook", &"hook"], "bonus": 1.3},
	{"name": "Hook to the chin", "seq": [&"hook", &"uppercut"], "bonus": 1.3},
	{"name": "One-two", "seq": [&"jab", &"hook"], "bonus": 1.15},
	{"name": "Jab, uppercut", "seq": [&"jab", &"uppercut"], "bonus": 1.15},
]
const RHYTHM_GRACE := 0.45         ## after a move ends, the next one still continues the string
const INPUT_BUFFER := 0.2         ## a press this close before the chain window opens is kept
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


## The combo that `history` (oldest first) would complete if `move` came next, or {}.
## Matches the move as thrown, so "becomes" combos are found before the swap.
static func combo_for_next(history: Array, move: StringName) -> Dictionary:
	var h := history.duplicate()
	h.append(move)
	return match_combo(h)


## A longer combo starts with `seq` (so the string isn't over yet).
static func combo_continues(seq: Array) -> bool:
	for c in COMBOS:
		var longer: Array = c["seq"]
		if longer.size() > seq.size() and longer.slice(0, seq.size()) == seq:
			return true
	return false


static func has(move_id: StringName) -> bool:
	return DATA.has(move_id)


## A copy of the move row with defaults filled in.
static func get_move(move_id: StringName) -> Dictionary:
	var m: Dictionary = {
		"id": move_id, "damage": 0.0, "windup": 0.1, "windup_scale": 1.0, "active": 0.05,
		"recover": 0.3, "reach": 1.3, "arc": 70.0, "sweep": false, "lunge": true,
		"stagger": 0.3, "poise": 8.0, "knockback": 1.0, "knockdown": false, "heavy": false,
		"to_face": false, "ground": false, "telegraph": false, "keeps_hold": false,
		"self_damage": 0.0, "guard_break": false, "zone": &"head", "side": 0.0,
		"charge": false, "clinch": false, "doubles": false, "chargeable": false,
	}
	m.merge(DATA.get(move_id, {}), true)
	if not m.has("stamina"):
		m["stamina"] = 3.0 + float(m["damage"]) * 0.8
	if not m.has("guard_drain"):
		m["guard_drain"] = float(m["damage"]) * 1.2
	return m
