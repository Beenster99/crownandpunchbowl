class_name TalkLines
extends RefCounted
## Who each punter is (a name and a bit of background, so Claude has someone to play), and
## the canned answers they give when "Punters answer back" is off or Claude can't be reached.
##
## Canned answers are keyed by voice group (posh, local, rugby, police, staff) and by what
## the words did to them (Npc.hear_words outcomes):
##   calmed       talked down
##   unconvinced  not having it, but not angrier either
##   riled        wound up: squaring up now
##   fuming       already fighting you, now angrier
##   cowed        wanted no part of it
##   chat         a friendly word in a calm pub
##   shrug        didn't follow what you meant

const GROUP_OF := {"second_homer": "posh", "local": "local", "rambler": "local",
	"rugby_lad": "rugby", "police": "police", "staff": "staff"}

const LINES := {
	"posh": {
		"calmed": ["Fine. Fine! But I'm putting this on Tripadvisor.", "Well. Apology accepted, I suppose.",
			"Right. Let's all just be civilised, shall we?", "A pint? Make it a large Rioja and we'll say no more."],
		"unconvinced": ["An accident? I've got a QC in my contacts, you know.", "Don't you 'mate' me.",
			"That's what they all say. Around here.", "I'll be speaking to the parish council about you."],
		"riled": ["Right! I did a term of judo at Marlborough!", "How DARE you. Hold my gilet.",
			"Do you know who I am? You will in a minute!", "That's it. I'm taking my jumper off."],
		"fuming": ["You absolute peasant!", "I'll have you evicted!", "Now you've done it, you yokel!"],
		"cowed": ["I don't want any trouble! I've got a dinner party on Saturday!", "Please, not the face, I'm on Zoom tomorrow.",
			"Darling, get the car."],
		"chat": ["Oh, hello. Do you know if they do oat milk here?", "Charming village. We're only here weekends, obviously.",
			"Lovely pub. Terribly authentic.", "We're thinking of doing up the old forge. Bi-fold doors."],
		"shrug": ["Sorry, I don't speak... local.", "I'm sorry, what?", "Is that a farming thing?"],
	},
	"local": {
		"calmed": ["Go on then. Yours is a bitter.", "Alright. No harm done.", "Fair enough. Watch yourself though.",
			"Yeah, alright. Leave it."],
		"unconvinced": ["Accident my arse.", "Don't you 'calm down' me.", "Yeah? Tell it to my nose.",
			"I've known your dad thirty years, and he's a liar too."],
		"riled": ["Come on then!", "You what? Say that again.", "Right. Outside. Now.", "Who are you talking to?"],
		"fuming": ["You're dead, you are!", "I'll have you!", "Keep talking, see what happens!"],
		"cowed": ["Leave it out, I'm only here for the darts.", "Not me, mate. Not tonight."],
		"chat": ["Alright.", "Evening.", "Same as always, mild.", "Weather's turning.", "You seen the price of diesel?"],
		"shrug": ["You what?", "Eh?", "Speak up, I can't hear you over the jukebox."],
	},
	"rugby": {
		"calmed": ["Ha! Fair play. Jägerbombs then!", "Alright, alright. No hard feelings, big man.",
			"Good lad. Handshake?", "Yeah fine, but you're getting the next round in."],
		"unconvinced": ["Accident? I've seen better dives at Twickenham.", "Nah mate. Nah.",
			"Say sorry like you mean it."],
		"riled": ["LADS! He wants it!", "Oh, it's ON now!", "You're getting rucked, mate!", "Come here then!"],
		"fuming": ["I'm gonna fold you in half!", "Scrum down, you muppet!", "That's a red card for you!"],
		"cowed": ["Whoa, steady, I've got a match Saturday."],
		"chat": ["Alright big man! Fancy a pint?", "Lads on tour!", "You play? You've got the neck for it.",
			"Who's up for a boat race?"],
		"shrug": ["Eh? Can't hear you mate!", "Say again?", "LADS! What did he say?"],
	},
	"police": {
		"calmed": ["Calm down? I'm the one who says calm down.", "Right. Hands where I can see them.",
			"We'll see about that, sunshine."],
		"unconvinced": ["Save it for the station.", "Anything you say may be given in evidence.",
			"Accident, was it? Course it was."],
		"riled": ["Right, you're nicked!", "Resisting, are we?", "That's assaulting an officer, that is."],
		"fuming": ["Back-up's on its way, sunshine!", "You've just made it worse for yourself!"],
		"cowed": ["Now then, now then."],
		"chat": ["Evening all.", "Move along.", "Been drinking tonight, sir?"],
		"shrug": ["Come again?", "Speak clearly, sir.", "What was that?"],
	},
	"staff": {
		"calmed": ["Thank you. Now take it outside.", "Ta. Mind the glasses."],
		"unconvinced": ["Don't look at me, I just pour 'em."],
		"riled": ["Oi! Not in my pub!", "Any more of that and you're barred!", "I've got a cricket bat under here."],
		"fuming": ["Right, that's it, last orders for you!"],
		"cowed": ["I just work here."],
		"chat": ["What can I get you?", "Pint of the usual?", "Pies are fresh tonight.", "Mind the step on the way out."],
		"shrug": ["Sorry, love, didn't catch that.", "You what, love?"],
	},
}

## Names and backgrounds, picked from the NPC's node name so they're the same on every machine.
const NAMES := {
	"posh": {"m": ["Rupert", "Giles", "Hugo", "Jolyon", "Piers", "Crispin", "Toby", "Barnaby"],
		"f": ["Arabella", "Henrietta", "Camilla", "Octavia", "Pippa", "Clementine"]},
	"local": {"m": ["Dave", "Terry", "Big Steve", "Clive", "Mick", "Norman", "Keith", "Trev"],
		"f": ["Sharon", "Bev", "Jackie", "Mandy", "Tracy", "Pauline"]},
	"rugby": {"m": ["Chaz", "Monty", "Tarquin", "Bomber", "Hodgey", "Fitz"],
		"f": ["Jess", "Lottie", "Immy"]},
	"police": {"m": ["PC Dawson", "PC Wright", "Sergeant Pike", "PC Hollis"],
		"f": ["PC Reed", "Sergeant Okafor", "PC Lund"]},
	"staff": {"m": ["Bob the landlord", "Kev behind the bar"], "f": ["Maureen the landlady", "Shaz behind the bar"]},
}
const BACKGROUNDS := {
	"posh": ["a London hedge-fund manager with a weekend cottage he calls 'the bolthole'",
		"a property developer who keeps saying the village 'has potential'",
		"a barrister who mentions it within seconds of meeting anyone",
		"an interiors influencer up for the weekend, filming everything for content",
		"an ad executive who moved in last year and already runs the parish council",
		"a retired banker who complains about the tractors on 'his' lane"],
	"local": ["a builder who's drunk in this pub every night for thirty years",
		"a retired postman who knows everyone's business",
		"a mechanic from the garage up the road, quick to anger",
		"a darts player who takes the league very seriously",
		"a lorry driver who's just finished a long shift and wants a quiet pint"],
	"rugby": ["a rugby lad on a stag weekend from Cheltenham, six pints in",
		"a rugby club prop forward, loud, friendly until he isn't",
		"a public-school rugby lad down for the weekend with the club"],
	"police": ["a village bobby who's seen it all and is tired of it",
		"a keen young constable who quotes the rulebook"],
	"staff": ["runs the bar and has seen a thousand fights; nobody lays a finger on the bar staff"],
}


static func group_of(kind: String) -> String:
	return GROUP_OF.get(kind, "local")


## A canned answer for `kind` after `outcome`. Never empty.
static func reply(kind: String, outcome: String, rng: RandomNumberGenerator) -> String:
	var g: Dictionary = LINES[group_of(kind)]
	var pool: Array = g.get(outcome, g["shrug"])
	return String(pool[rng.randi_range(0, pool.size() - 1)])


## {name, background, group} for an NPC, stable for its node name.
static func persona(npc_name: String, kind: String, sex: String) -> Dictionary:
	var group := group_of(kind)
	var h := absi(hash(npc_name + kind))
	var names: Array = NAMES[group].get(sex, NAMES[group]["m"])
	var bgs: Array = BACKGROUNDS[group]
	return {"name": String(names[h % names.size()]), "background": String(bgs[(h / 7) % bgs.size()]),
		"group": group}
