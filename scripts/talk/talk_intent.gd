class_name TalkIntent
extends RefCounted
## What a player meant by a spoken (or typed) line, without any AI: a quick phrase match.
## Used to make punters react when "Punters answer back" is off or has no API key, and as a
## hint to Claude when it's on.
##
## classify("calm down mate, it was an accident") -> {intent: "calm", strength: 0.9,
##   apology: true, ...}
## classify("OI! I'm talking to you!", true) -> {intent: "provoke", strength: 1.0, ...}
##
## Intents:
##   calm     placating: calm down, sorry, accident, let me buy you a pint
##   provoke  goading: oi, come on then, what you looking at, insults, shouting
##   chat     friendly or neutral talk: hello, cheers, what you drinking
##   none     nothing we recognise (still gets a reply from Claude when that's on)

## Phrase -> weight. Matched on whole words in lower case with punctuation stripped.
const CALM := {
	"calm down": 0.7, "calm it": 0.6, "calm yourself": 0.6, "relax": 0.5, "chill": 0.4,
	"chill out": 0.5, "easy": 0.25, "easy now": 0.5, "steady on": 0.5, "steady": 0.25,
	"no harm": 0.5, "no harm done": 0.6, "no offence": 0.5, "leave it": 0.5, "not worth it": 0.6,
	"settle down": 0.6, "take it easy": 0.6, "cool it": 0.5, "back off": 0.15, "peace": 0.4,
	"truce": 0.6, "shake hands": 0.6, "shake on it": 0.6, "no trouble": 0.5,
	"dont want any trouble": 0.7, "dont want trouble": 0.7, "were good": 0.4,
	"its fine": 0.35, "all good": 0.35, "forget it": 0.4, "my bad": 0.6,
	"my fault": 0.6, "sorry": 0.6, "apologies": 0.6, "apologise": 0.6, "apologize": 0.6,
	"accident": 0.6, "an accident": 0.7, "didnt mean": 0.6, "didnt mean it": 0.7, "slipped": 0.3, "buy you a pint": 0.8, "buy you a drink": 0.8,
	"get you a pint": 0.8, "get you a drink": 0.8, "have a drink on me": 0.8, "on me": 0.3,
	"friends": 0.3, "pal": 0.1, "mate": 0.15, "come on mate": 0.1, "be nice": 0.4,
	"lets not": 0.4, "stop": 0.25, "enough": 0.35, "pack it in": 0.3,
}
const PROVOKE := {
	"oi": 0.55, "talking to you": 0.6, "im talking to you": 0.7, "come on then": 0.8,
	"come on": 0.25, "what you looking at": 0.8, "what are you looking at": 0.8,
	"you want some": 0.8, "want some": 0.5, "fight me": 0.9, "outside": 0.4,
	"step outside": 0.8, "lets have it": 0.8, "have it": 0.3,
	"bring it": 0.7, "bring it on": 0.8, "your mum": 0.7, "your mother": 0.5,
	"prat": 0.5, "pillock": 0.5, "plonker": 0.5, "tosser": 0.7, "idiot": 0.5, "muppet": 0.5,
	"wanker": 0.8, "twat": 0.8, "knob": 0.6, "knobhead": 0.7, "dickhead": 0.8, "prick": 0.7,
	"git": 0.5, "coward": 0.7, "chicken": 0.5, "scared": 0.4, "pathetic": 0.6, "shut up": 0.6,
	"shut it": 0.6, "get out": 0.6, "go home": 0.5, "sod off": 0.7, "piss off": 0.8,
	"bugger off": 0.7, "clear off": 0.6, "fuck off": 0.9, "fuck": 0.4, "fucking": 0.35,
	"bastard": 0.7, "bellend": 0.7, "posh boy": 0.6, "townie": 0.5, "incomer": 0.4,
	"grockle": 0.5, "londoner": 0.4, "second homer": 0.5, "range rover": 0.3, "gilet": 0.3,
	"hit you": 0.6, "smack you": 0.8, "deck you": 0.8, "lamp you": 0.8, "knock you out": 0.9,
	"kick your": 0.8, "do you": 0.3, "having a go": 0.4, "mug": 0.4, "not sorry": 1.2,
	"im not sorry": 1.2, "deserved it": 0.8, "had it coming": 0.8, "wasnt an accident": 1.2,
	"on purpose": 0.8,
}
const CHAT := {
	"hello": 0.5, "hi": 0.4, "hiya": 0.5, "alright": 0.35, "evening": 0.5, "morning": 0.4,
	"afternoon": 0.4, "cheers": 0.5, "hows it going": 0.6,
	"how are you": 0.6, "what you drinking": 0.7, "what are you drinking": 0.7, "pint": 0.3,
	"nice": 0.2, "weather": 0.4, "good evening": 0.6, "how do": 0.5, "ey up": 0.6,
	"nice to meet you": 0.6, "whats your name": 0.6, "where you from": 0.5,
	"thanks": 0.4, "thank you": 0.4, "landlord": 0.3, "barman": 0.3, "same again": 0.5,
}
const APOLOGY := ["sorry", "apologies", "apologise", "apologize", "accident", "didnt mean",
	"my bad", "my fault", "slipped"]


## {intent, strength (0..1), calm, provoke, chat (raw scores), apology (bool), loud (bool)}.
## `loud` means it was shouted: the mic was hot, or the typed line was in capitals.
static func classify(text: String, loud := false) -> Dictionary:
	var letters := text.strip_edges()
	if not loud and letters.length() >= 4 and letters == letters.to_upper() \
			and letters != letters.to_lower():
		loud = true  # TYPED IN CAPITALS
	if not loud and RegEx.create_from_string("\\b[A-Z]{2,}!").search(text) != null:
		loud = true  # "OI!"
	var words := " %s " % normalise(text)
	var calm := _score(words, CALM)
	var provoke := _score(words, PROVOKE)
	var chat := _score(words, CHAT)
	# "Not sorry" shouldn't also count as sorry.
	if words.contains(" not sorry ") or words.contains(" wasnt an accident "):
		calm = maxf(calm - 1.2, 0.0)
	var apology := false
	for a in APOLOGY:
		if words.contains(" %s " % a):
			apology = calm > 0.0
	var bangs := text.count("!")
	if loud:
		provoke += 0.35 if calm < 0.6 else 0.1
	elif bangs >= 2 and calm < 0.5:
		provoke += 0.15
	var intent := "none"
	var strength := 0.0
	if provoke > 0.0 and provoke >= calm + 0.1:
		intent = "provoke"
		strength = provoke - calm * 0.5
	elif calm > 0.0 and calm >= provoke:
		intent = "calm"
		strength = calm - provoke * 0.5
	elif chat > 0.0:
		intent = "chat"
		strength = chat
	return {"intent": intent, "strength": clampf(strength, 0.0, 1.0), "calm": calm,
		"provoke": provoke, "chat": chat, "apology": apology, "loud": loud}


## Lower case, apostrophes dropped (I'm -> im), other punctuation turned to spaces, spaces squashed.
static func normalise(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == "'" or ch == "’":
			continue  # I'm -> im, didn't -> didnt
		else:
			out += " "
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges()


## Sum of matched phrase weights, with diminishing returns so a long rant doesn't go past 1.
static func _score(padded: String, table: Dictionary) -> float:
	var total := 0.0
	for phrase in table:
		if padded.contains(" %s " % phrase):
			total += float(table[phrase])
	return 1.0 - exp(-total * 1.3) if total > 0.0 else 0.0
