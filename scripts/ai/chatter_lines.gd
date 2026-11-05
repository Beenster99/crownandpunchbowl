class_name ChatterLines
extends RefCounted
## Everything the second-homers say while the pub is calm. Owned by the AI workstream; writers
## can add lines freely; nothing else needs to change.
##
## The joke is always on the speaker: their smugness, hypocrisy and total lack of
## self-awareness. Keep it that way. Nobody they talk *about* is the punchline.
##
## Each topic has three parts:
##   open   starts the topic. Said by the first speaker.
##   reply  a response that follows any `open` or `more` line of the same topic.
##   more   keeps it going or one-ups the last speaker. Either speaker can say these.
## Every line is identified by a key "<topic>/<part>/<index>" (see `key()`), which is also the
## name voice files use: res://assets/audio/voice/chatter/<topic>_<part>_<index>.ogg
## (index two digits, e.g. dogs_open_03.ogg). Adding lines at the END of an array keeps the
## existing keys stable for recorded audio.
##
## Shared pools (topic "_"): generic replies, segues between topics, sign-offs, things a
## local says when cornered by a second-homer, and the yelp when a fight breaks out nearby.

const TOPICS := {
	&"dogs": {
		"open": [
			"Hector's started his agility classes. He's top of the group, obviously.",
			"We've had the Labrador's portrait done. Oils. It's in the hall.",
			"Bramble's on a raw diet now. Organic venison. He eats better than the children.",
			"Our cockapoo has an Instagram. Eleven thousand followers. More than my business.",
			"The vet says Monty's anxious. We've got him a dog psychologist on Zoom.",
			"I take Ottoline to doggy day care in Henley. It's four hundred a month, but she's thriving.",
			"We drove the dogs down in the Volvo. They have their own row.",
			"Have you met Biscuit? He's a sprocker. You won't have heard of them.",
		],
		"reply": [
			"Ours sleeps in the bed. Between us. It's helped, honestly.",
			"Oh, he's a darling. Is he allowed in here?",
			"We've got a Hungarian Vizsla. Very bright. Very sensitive.",
			"Dogs just understand you, don't they? Not like Rupert.",
			"I wouldn't trust anyone who doesn't like dogs. Or Waitrose.",
			"Do you do the little boots? For the gravel?",
		],
		"more": [
			"He only drinks filtered water. The tap stuff upsets him.",
			"We're thinking of getting a second one so the first one has a friend.",
			"He's got a better pension plan than our cleaner. That's a joke. Mostly.",
			"The breeder had a two-year waiting list. We knew someone.",
			"He bit the postman, but the postman was being very aggressive with a parcel.",
			"Honestly, he's more of a person than most people.",
			"He's on a little course of CBD. Takes the edge off. For him, not me.",
			"We put him in the Christmas card. Well, he IS the Christmas card.",
		],
	},
	&"cars": {
		"open": [
			"I've just taken delivery of the new Range Rover. The old one was nearly two.",
			"We came down in the Porsche. You can't fit the dogs, but it's about the drive.",
			"Gerald's having a midlife crisis. He's bought a Morgan. In racing green.",
			"Do you find the Defender a bit agricultural? I love it, but it's agricultural.",
			"The car's on a lease, of course. Nobody actually BUYS a car any more.",
			"I had the number plate done. It nearly spells my name.",
			"Someone scratched the Audi in the Waitrose car park. In the parent and child bay.",
		],
		"reply": [
			"The Volvo is just so SAFE. You feel like nothing can touch you.",
			"We've got a little runaround for the village. Only an Audi.",
			"Gosh. What did that set you back?",
			"I never know what to drive to the farm shop. You don't want to look flash.",
			"I'm more of a classic car person. The smell of the leather.",
			"Is it the one with the massage seats?",
		],
		"more": [
			"It's got a fridge in the armrest. For the Chablis. For the passengers.",
			"I only drive it on the weekends, so it's basically carbon neutral.",
			"The insurance is ridiculous, because of all the crime. In the Cotswolds.",
			"It does nought to sixty in four seconds, not that you can, with all the speed bumps.",
			"I had the windows tinted. You do get looked at.",
			"I parked across two spaces, but the spaces are very narrow round here.",
			"It's never been off-road. It's never been near a road, really. It's mostly a garage.",
		],
	},
	&"houses": {
		"open": [
			"We're knocking through. Kitchen-diner-family-room. It's the only way to live.",
			"We've had the Aga converted to electric. It's not the same, but it's ethical.",
			"Did you see the price the old rectory went for? Obscene. We'd have paid more.",
			"We're doing a basement. Cinema room, wine cellar, little gym.",
			"The planning committee are being SO difficult about our orangery.",
			"We've gone for Farrow and Ball. Elephant's Breath in the snug.",
			"Our house is Grade Two listed. We can't change a thing. Except everything inside.",
		],
		"reply": [
			"We went for Dead Salmon in the boot room. Very brave.",
			"Islands. You need an island. Ours seats eight.",
			"Oh, the builders. Don't talk to me about the builders.",
			"Have you thought about underfloor heating? Life-changing.",
			"Gosh, that's a project. We just moved, it was easier.",
			"I love a period feature. As long as it's been fully modernised.",
		],
		"more": [
			"The architect is a genius. Bit of a nightmare. But a genius.",
			"Our builder's been with us three years. He's practically family. We don't pay him like family.",
			"We had to fight the neighbours about the hot tub. Ghastly people. Been here forty years.",
			"Of course, the value's gone up a fortune. Not that that's why we did it.",
			"It's a boot room, a mud room AND a dog room. Each one is different.",
			"We've put in a pantry. A walk-in pantry. You walk in. It's a whole thing.",
			"The house was a wreck when we bought it. There was a family living in it.",
		],
	},
	&"investments": {
		"open": [
			"My man at the bank says gold. Then he says crypto. Then he says gold again.",
			"I've put the bonus into a buy-to-let. Somebody has to provide housing.",
			"We're in whisky casks now. You don't drink it. You just own it.",
			"Have you looked into forestry? The tax position is wonderful.",
			"I'm very into ESG now. Ethical funds. Mostly oil, but ethical oil.",
			"I did a small angel investment. An app for booking ski instructors.",
			"Index funds, darling. Boring, but it's how the real money works.",
		],
		"reply": [
			"We've got a little portfolio. Nothing major. Seven flats.",
			"Property's still the safest bet. Bricks and mortar.",
			"Our financial adviser is Rupert's godson. Bright boy.",
			"I don't understand any of it. I just sign where they tell me.",
			"What's the yield on that, roughly? Ballpark?",
			"Gosh, aren't you clever. I'm all premium bonds.",
		],
		"more": [
			"I lost a bit on the NFTs, but it was a learning experience.",
			"The tenants keep ringing about the boiler. I've stopped answering.",
			"Crypto's fine. You just have to get out before everyone else.",
			"We bought a vineyard in Sussex. It doesn't make money, but it makes wine.",
			"Fine art's done well. We have a Hockney print in the downstairs loo.",
			"My accountant says I don't technically live in this country. On paper.",
			"Always diversify. We've got four houses in four different villages.",
		],
	},
	&"red_wine": {
		"open": [
			"Try this. It's a little Rioja. Not little in price, mind you.",
			"I've joined a wine club. They send you a case and a man in a fleece explains it.",
			"This Malbec's very drinkable. Jammy. Bit of leather. A hint of saddle.",
			"I only drink Burgundy now. Life's too short for Australian.",
			"Is the house red any good here? I'll have a bottle anyway.",
			"We did a tasting in Bordeaux. I spat. Like a professional.",
		],
		"reply": [
			"Ooh, I'm getting blackcurrant. And a sort of pencil shaving?",
			"Did you let it breathe? It needs at least an hour.",
			"I'm not a snob, but I can't drink anything under twelve quid.",
			"We had a Barolo at the Hendersons' that changed my life.",
			"Lovely legs on that. The wine, I mean.",
			"Red wine's good for the heart, actually. It's basically medicine.",
		],
		"more": [
			"We've got a wine fridge. Well, a wine room. With a wine fridge in it.",
			"I've been laying some down for when the children turn eighteen. Then I drank it.",
			"Of course, in France, they give it to toddlers.",
			"I had my sommelier qualification, level one. Online. Over a weekend.",
			"Cheap wine gives you headaches. That's why I need the expensive stuff, medically.",
			"I can tell a Merlot blindfolded. I can't tell you what day it is, mind.",
			"You should never drink before six. In this time zone.",
		],
	},
	&"single_malts": {
		"open": [
			"I'm on the Lagavulin tonight. Sixteen year old. Smells like a bonfire in a library.",
			"Do they do an Islay here? Anything peaty? Anything at all?",
			"I went on a distillery tour in Speyside. I'm basically Scottish now.",
			"Never put ice in it. A drop of water. Spring water. Highland, ideally.",
			"I've started collecting. I don't drink them. I just look at them.",
			"Proper whisky glass, please. Not a tumbler. I'm not an animal.",
		],
		"reply": [
			"I get smoke. And peat. And a sort of... seaweed?",
			"Rupert has a cabinet. With a key. He won't let me near it.",
			"I thought Japanese whisky was the thing now?",
			"I prefer a nice Armagnac, myself. More rounded.",
			"Isn't that the one in the TV advert with the stag?",
			"I'll have whatever's oldest.",
		],
		"more": [
			"It's thirty years old. Older than my wife. My current wife.",
			"The bottle cost more than the boiler. Better investment, too.",
			"You have to chew it. Chew the whisky. Let it coat the palate.",
			"I've got a cask maturing on Jura. I've never been to Jura.",
			"Proper connoisseurs take it neat at room temperature. In a dressing gown.",
			"I bought a kilt. I'm not entitled to the tartan, but it was in the sale.",
		],
	},
	&"jobs": {
		"open": [
			"Work's been mad. Back-to-back Teams calls. I barely got to the gym.",
			"I'm in consultancy. I advise people. On things. Strategically.",
			"We're having a restructure. I'm leading the synergy workstream.",
			"I'm in brand strategy. I came up with the word for a yoghurt.",
			"I'm technically on a sabbatical. Writing a novel. Well, thinking about it.",
			"I work from the second home on Fridays. And Mondays. And most Thursdays.",
			"I'm a partner now. Which mostly means longer lunches.",
		],
		"reply": [
			"I'm in HR. People think it's about people. It isn't.",
			"I'm in property. Not estate agent. Property.",
			"I couldn't do a nine-to-five. I do more of an eleven-to-three.",
			"Gosh, that sounds stressful. Are you being paid properly for it?",
			"I've got a portfolio career. Three non-execs and a podcast.",
			"I'm in finance. I couldn't tell you what I actually do. Nobody can.",
		],
		"more": [
			"I put 'thought leader' on my LinkedIn. Nobody's argued.",
			"We had an away day in a yurt. Lots of post-its. Very powerful.",
			"I've got eleven direct reports. I know at least four of their names.",
			"We're piloting a four-day week. I'm piloting a three-day one.",
			"I keep my camera off on calls. Nobody needs to see me in a hot tub.",
			"I circled back with stakeholders. Then I circled back again. It's a lot of circling.",
			"I've been made redundant three times. Each payout bigger than the last.",
		],
	},
	&"bosses": {
		"open": [
			"My boss is SO annoying. He wants me to come into the office. On a Tuesday!",
			"Our new CEO is thirty-one and does cold water swimming. It's unbearable.",
			"My manager keeps saying 'let's take this offline'. We're always offline!",
			"The boss had us do a personality test. I'm a red. Apparently that's bad.",
			"My boss sent an email at eleven at night. Who does that? Who READS that?",
			"They've hired a Head of Culture. She mostly organises the pizza.",
		],
		"reply": [
			"Ugh, mine's the same. Micro-manages EVERYTHING. Like my expenses.",
			"Just book a meeting called 'focus time' and go to the gym.",
			"Mine calls everyone 'mate'. Even the board. Even his wife.",
			"Have you thought about going freelance? You'd be your own boss!",
			"You should go over his head. Do you know anyone in Davos?",
			"I'm the boss, actually. And I'm lovely. Everyone says so. To my face.",
		],
		"more": [
			"He wants 'visibility'. I'm visible. I'm visible on Instagram, in Mykonos.",
			"She said my out-of-office was 'too long'. It was a month. I was skiing.",
			"I told HR. HR is his wife. That was a mistake.",
			"He has a standing desk. He stands at it to tell you you're sitting down too much.",
			"He started a book club. It's just his book. He wrote it. It's about him.",
			"I'm leaving anyway. I'm going to be a ceramicist. Or a consultant.",
		],
	},
	&"wife_swapping": {
		"open": [
			"The Hendersons have started leaving their car keys in a bowl again.",
			"Did you hear about the party at the Old Mill? Very... progressive.",
			"Simon and Fliss have an 'arrangement'. It involves a hot tub and a rota.",
			"Have you been to one of Gerald's 'supper clubs'? Don't. Or do. Bring a dish.",
			"Apparently the Pottingers are 'open' now. Their marriage, not the garden.",
		],
		"reply": [
			"We went to a key party once. Clive came home with a Vauxhall.",
			"I'm not judging. I'm just... interested. For research.",
			"Gosh. In THIS village? With THOSE knees?",
			"We tried it. Ended up talking about loft conversions until two.",
			"Is that why they put the pampas grass in? I thought it was just fashionable.",
			"I'm far too tired. I'm in bed by nine with a podcast about Tudor kings.",
		],
		"more": [
			"Apparently they swapped back after a week. Something about the dishwasher.",
			"I won't say who, but someone's husband was spotted in the wrong Range Rover.",
			"I always say, what happens in the Cotswolds stays in the Cotswolds. And the group chat.",
			"I'd do it, but have you SEEN the husbands? It's a downgrade either way.",
			"There were name tags. Laminated. Fliss is very organised.",
			"I did go once. Ended up doing the washing up for four hours. Best night of my life.",
		],
	},
	&"auctions": {
		"open": [
			"I picked up a Georgian commode at Bonhams. Lovely patina. No idea what it's for.",
			"Have you done online auctions? Dangerous. I bought a stuffed owl at three in the morning.",
			"We're selling Granny's silver at Christie's. She'd have wanted the conservatory.",
			"I outbid a dealer on a Victorian rocking horse. He was furious. I was thrilled.",
			"I've started watching the auction catalogues instead of the news. Much calmer.",
		],
		"reply": [
			"Oh, I LOVE a bit of brown furniture. It's coming back, you know.",
			"Did you get the provenance? You have to get the provenance.",
			"We found a Clarice Cliff jug at a car boot. Sold it for a weekend in Ibiza.",
			"I scratched my nose at a sale once and bought a tapestry.",
			"Gosh, did you overpay? You overpaid, didn't you.",
		],
		"more": [
			"The buyer's premium is ridiculous, but it's not about the money. It's about winning.",
			"We had a valuer round. He said the Monet was a print. I said it was a feeling.",
			"I bought a suit of armour. Nobody in the family can lift it.",
			"It's an investment piece. It's an investment in me looking at it.",
			"I've got a lot coming up in April. Lot two-oh-seven. Very exciting.",
			"I bid on a chair once just because the other man had a ponytail.",
		],
	},
	&"gardening": {
		"open": [
			"The roses are a disaster this year. Black spot. I'm devastated.",
			"Our gardener's doing a wildflower meadow. It's essentially letting it grow, for money.",
			"I've gone no-dig. The gardener doesn't dig. I don't dig. Nobody digs.",
			"We've got a kitchen garden now. Three courgettes. They cost about forty pounds each.",
			"The deer ate the topiary. It was shaped like a peacock. Now it's shaped like a deer.",
			"I've started composting. It's very spiritual. And it smells.",
		],
		"reply": [
			"Have you tried Chelsea? We go every year. For the Pimm's, mostly.",
			"Monty Don would be appalled. I imagine. I've never met him. Yet.",
			"Our lawn is a stripe lawn. Two directions. Very precise.",
			"Slugs! Don't get me started on slugs. I've got a man for slugs.",
			"I had a gardener but he kept wanting things. Like wages.",
			"Ooh, do you do dahlias? I'm a dahlia person.",
		],
		"more": [
			"We dug a pond for the wildlife. Then we filled it with koi. The herons were thrilled.",
			"I grow my own tomatoes. They're terrible. But they're MINE.",
			"The neighbours have leylandii. Leylandii! In this day and age!",
			"We had the hedge laid by a proper hedge-layer. He has a beard and everything.",
			"I've ordered a greenhouse from a catalogue. Victorian style, Chinese made.",
			"We let a bit go wild 'for the bees'. Really it's because I'm lazy. But the bees!",
		],
	},
	&"tv": {
		"open": [
			"Are you watching that Scandi thing? Everyone's miserable. It's wonderful.",
			"We don't really watch TV. Except Bake Off. And Strictly. And the news. And everything.",
			"Did you see the Antiques Roadshow? A man found a Fabergé egg in his shed!",
			"I'm on series four of that period drama. All bonnets and heaving.",
			"Have you watched the one about the rich people on holiday? So relatable.",
			"I only watch documentaries. About wine. And cheese. And wine.",
		],
		"reply": [
			"We're more of a Radio Four household, really.",
			"Oh, I couldn't. We haven't got a television. We've got a projector.",
			"I watched it on the plane. Business class has a lovely screen.",
			"No spoilers! I'm only on episode two. I fell asleep.",
			"Was that the one that was filmed in our village? We had a duke in the post office.",
			"I prefer the old ones. Before everything was in Welsh. Or Danish.",
		],
		"more": [
			"I saw a property programme. They bought a farmhouse for a hundred grand. A HUNDRED grand!",
			"My husband shouts at Question Time. It's the only exercise he gets.",
			"We had a camera crew round once. For the garden. They didn't use it.",
			"I'm very into the cooking ones. I don't cook. I just like the shouting.",
			"There's a dating show the cleaner told me about. I watch it purely sociologically.",
			"Everything's a box set now. I miss waiting a week. I don't, really.",
		],
	},
	&"yoga": {
		"open": [
			"I've started hot yoga. It's forty degrees. Like Marbella but sweatier.",
			"My yoga teacher says I have a very old soul. And very tight hamstrings.",
			"We did a yoga retreat in Goa. No phones, no wine. I lasted a day.",
			"I can nearly touch my toes now. I can see them, anyway.",
			"Do you do Ashtanga? I do Ashtanga. I tell everyone I do Ashtanga.",
		],
		"reply": [
			"I've got the mat. The mat was a hundred and twenty pounds. I've not unrolled it.",
			"Namaste. That's yoga for 'hello'. Or 'goodbye'. Or 'pay up front'.",
			"I love downward dog. Hector does it naturally. He's very spiritual.",
			"Is it the one where you lie down at the end? That's my favourite bit.",
			"I only go for the leggings, honestly.",
		],
		"more": [
			"The instructor's name is Sky. Well, it's Susan. But she's Sky now.",
			"I did a headstand once. Then I did my neck. Then I did six weeks of physio.",
			"I meditate on the drive to the office. Is that dangerous?",
			"It's all about the breath. In through the nose, out through the credit card.",
			"I'm doing my teacher training. Two weeks in Bali. Then I'm qualified to tell people things.",
		],
	},
	&"pilates": {
		"open": [
			"I've switched to reformer Pilates. It's like a medieval rack, but with a smoothie bar.",
			"My Pilates teacher says my core is 'sleeping'. Well, aren't we all.",
			"Pilates is so much more sophisticated than yoga. No chanting. Just suffering.",
			"I do Pilates three times a week. Well, I pay for it three times a week.",
			"There's a new studio in the village. Where the butcher used to be.",
		],
		"reply": [
			"Oh, the reformer! I fell off it. Twice. Nobody mentions that.",
			"Mine's a private session. In the house. The instructor brings the machine.",
			"I've heard it's very good for posture. For looking down on people.",
			"I can't do the hundred. I can do about the eleven.",
			"Is it the one where they shout at you, or the one where they whisper?",
		],
		"more": [
			"I bought the grippy socks. They were thirty pounds. For socks!",
			"I'm engaging my pelvic floor right now. You'd never know.",
			"The butcher's gone, mind. You can't get a decent chop. But you can get a decent plank.",
			"My physio recommends it. My physio also owns the studio.",
			"It's changed my life. I'm two centimetres taller. Allegedly.",
		],
	},
	&"spirituality": {
		"open": [
			"I've been doing a lot of work on myself. With crystals. And a man called River.",
			"Mercury's in retrograde, so I'm not making any big decisions. Except the Porsche.",
			"I had a sound bath on Sunday. It was mostly gongs. Very healing gongs.",
			"I'm a Pisces, so I feel EVERYTHING. Except guilt.",
			"We went on an ayahuasca retreat in Peru. Felix met God. God was a llama.",
			"My aura's been a bit murky lately. It's the commute.",
		],
		"reply": [
			"I'm very spiritual, but not religious. Except at Christmas. And weddings. And the school applications.",
			"Have you tried manifesting? I manifested this gilet.",
			"I had my chakras realigned. They were all over the place.",
			"Oh, a sound bath! Did you take the dog? Dogs love gongs.",
			"I do gratitude journaling. Mostly I'm grateful for me.",
		],
		"more": [
			"I'm living my truth. My truth has a pool.",
			"Everything happens for a reason. Usually money.",
			"I've let go of material things. I gave a rug to the cleaner.",
			"The universe gives you what you need. I need a bigger kitchen.",
			"My shaman's on WhatsApp now, which is handy.",
			"I've cleansed the house with sage. The smoke alarm went. Very spiritual.",
		],
	},
	&"second_home": {
		"open": [
			"We only come down at weekends. The village is SO much quieter during the week.",
			"The cottage is lovely, but the village shop closed. No idea why. We never used it.",
			"We let it out on Airbnb when we're not here. Which is always. It's basically a business.",
			"We've had it twenty years. We're practically locals. Well, we feel like locals.",
			"The locals are so authentic. Like something out of a period drama.",
			"It's just a little bolthole. Six bedrooms. A little bolthole.",
			"There's no signal at the cottage. It's wonderful. I have to drive to the top of the hill for my calls.",
		],
		"reply": [
			"We're thinking of a third. Somewhere by the sea. For the light.",
			"Oh, the PEACE. And the Ocado still delivers.",
			"We wanted to get involved in the community, but the parish council meets on Tuesdays.",
			"Isn't it nice, being part of a village? We bought the whole end of it.",
			"Ours is a converted chapel. We sleep where the altar was. Very peaceful.",
			"I just love that nobody locks their doors here. We do. But nobody else does.",
		],
		"more": [
			"They're always going on about affordable housing. We'd love more of it. Somewhere else.",
			"We objected to the new bungalows. They'd spoil the view from the hot tub.",
			"I joined the WI. I went once. They asked me to bake.",
			"The pub's gone a bit rough, mind. Who are THESE people?",
			"We went to the village fete. I bought a jar of jam for a pound. A POUND!",
			"The church bells start at eight on a Sunday. EIGHT. We've written to the vicar.",
			"We're very low impact. We only drive down in the big car once a week.",
		],
	},
	&"holidays": {
		"open": [
			"We've just got back from the Maldives. It's so relaxing. Nothing to do but book the next one.",
			"We do Verbier at Christmas, Tuscany in the summer and a bit of Barbados in between.",
			"We went to a tiny village in Provence. Very undiscovered. All our friends were there.",
			"The kids wanted Disney. We did Mustique. They'll thank us later.",
			"We've rented a villa on Corfu. Seven bedrooms. We're only three, but you want space.",
			"We did a safari in Botswana. The lions were lovely. The Wi-Fi was dreadful.",
		],
		"reply": [
			"Oh, we don't really do holidays. Just travel. It's different. More expensive.",
			"We tried the Algarve, but it was full of English people.",
			"We went glamping once. Never again. The yurt had no espresso machine.",
			"Is it the one Kate and Wills went to? That one?",
			"Did you fly? We flew. Well, everyone flew. We just flew better.",
			"Gosh. And how was the food? Was it very... foreign?",
		],
		"more": [
			"We met the most fascinating local. He was our driver. He had stories. About driving.",
			"We stayed somewhere with a butler. He unpacked my socks. Changed my life.",
			"The kids had a wonderful time. I think. They were at the kids' club the whole fortnight.",
			"I came back more stressed than I went. The pool was too small.",
			"We had to come home early. The olive oil tasting was overbooked.",
			"Everyone in Cornwall is from London now. You can't get away from them. From us.",
			"I've got a tan, but it's not a CHEAP tan. You can tell, can't you?",
		],
	},
	&"tax": {
		"open": [
			"The tax regime in this country is an absolute scandal. I'm paying nearly some of it!",
			"They're coming after second homes now. Second homes! As if we're made of houses.",
			"My accountant's found a lovely little loophole. Well, a structure. A very big structure.",
			"Inheritance tax is theft. My father worked VERY hard to inherit that money.",
			"VAT on school fees. I ask you. Where are the children of the rich supposed to go?",
			"I pay a lot of tax. Well, the company does. Well, the company's company does.",
		],
		"reply": [
			"We're thinking of moving to Monaco. The weather's better and nobody asks questions.",
			"It's the hard-working families who suffer. Like us. With our three houses.",
			"I don't mind paying tax. I just don't want to. There's a difference.",
			"Have you tried putting the house in the dog's name? Kidding. Mostly.",
			"It just goes on potholes and things. Not even nice potholes.",
			"Gosh. Are you allowed to do that?",
		],
		"more": [
			"Our neighbour's a non-dom. He dominates the whole lane.",
			"I put everything in a trust. The trust trusts me, and I trust the trust.",
			"I've got a man in Jersey. Not a sweater. An accountant.",
			"I'd happily pay more tax if it went to something sensible. Like reducing my tax.",
			"They should tax the people who can afford it. The other people who can afford it.",
			"Honestly, the only thing I object to more than taxes is people who don't pay theirs. The poor ones.",
		],
	},
	&"voting": {
		"open": [
			"Who are you voting for? Not that it matters. Nothing ever changes. Thank God.",
			"I've always voted for whoever promises to lower stamp duty.",
			"We're Lib Dems, really. In our hearts. Not in the polling booth.",
			"I'm a floating voter. I float towards whoever doesn't put my taxes up.",
			"Tactical voting, darling. I vote tactically for myself.",
			"I'm voting Green this time. I've got a heat pump. And a conscience. Mostly the heat pump.",
		],
		"reply": [
			"I'm socially liberal and fiscally... mine.",
			"I'll vote for anyone who fixes the A303.",
			"Politics is so divisive now. I just want everyone to agree with me.",
			"I went to school with half the cabinet. I wouldn't trust them with a guinea pig.",
			"Gosh, I don't talk politics in public. Unless I've had wine. Which I have.",
			"I don't vote. I write letters to The Telegraph. It's more effective.",
		],
		"more": [
			"I'm not left OR right. I'm upper-middle.",
			"The candidate came canvassing. I made him take his shoes off.",
			"I put a sign in the window. Not a party sign. A 'no cold callers' sign.",
			"The trouble with democracy is that everyone gets a vote. Even people without a garden.",
			"I like a strong leader. Who does what I say.",
			"I've been to Westminster. On a tour. I had a lovely scone.",
		],
	},
	&"vegetarianism": {
		"open": [
			"We've gone plant-based. Except bacon. And on Fridays. And when we're out.",
			"I'm flexitarian. I'm very flexible about it. Mostly I eat meat.",
			"Have you tried the oat milk here? There isn't any. I asked. Twice.",
			"Our daughter's gone vegan. Christmas is going to be a nightmare. A nut roast!",
			"I only eat meat I've met. Well, that the butcher's met. Well, a farm in Somerset.",
		],
		"reply": [
			"I could never go vegan. I love cheese too much. And Brie is basically a vegetable.",
			"We do Meat-Free Mondays. Then we have a steak on Tuesday to make up.",
			"Halloumi's not meat, is it? Good. Because I've had four.",
			"Isn't it all a bit... beige?",
			"I tried it for January. I'm still recovering.",
			"Gosh, that's very admirable. Can you pass the pork scratchings?",
		],
		"more": [
			"Jackfruit. It's like pulled pork, if pulled pork were disappointing.",
			"I get my protein from lentils. And smugness. Mostly smugness.",
			"The dogs aren't vegan. They're on venison. They need it. They're dogs.",
			"I eat fish. Fish don't count. They don't have faces. They do have faces, don't they?",
			"We had a vegan wedding. The cake was made of cashews and lies.",
			"I'm basically a vegetarian who eats meat.",
		],
	},
	&"sustainability": {
		"open": [
			"We've gone completely zero waste. Well, apart from the skip outside for the kitchen.",
			"I bought a bamboo toothbrush. And a bamboo kitchen. Bamboo floors. Bamboo everything.",
			"We take the train to the ski chalet now. Well, the train to the airport.",
			"I've stopped using plastic straws. I've personally saved a turtle. Possibly.",
			"We've got solar panels. On the garage. For the cars. The three cars.",
			"I only buy second hand. Vintage. Pre-loved. Mostly from Chelsea.",
		],
		"reply": [
			"We've got one of those reusable coffee cups. I've got eleven, actually.",
			"We offset our flights. I've no idea how. I tick a box.",
			"Have you seen the heat pump? Very quiet. We heat the pool with it.",
			"We do the recycling religiously. Well, the cleaner does.",
			"It's all about small changes. Like flying business, so you take up less room.",
			"Gosh, isn't it awful, the planet. Anyway, have you booked Mauritius?",
		],
		"more": [
			"We drink from the tap now. Through a filter. Imported from Switzerland.",
			"The children's school is very eco. They planted a tree. On a school trip to Costa Rica.",
			"We've rewilded the paddock. Mainly so we don't have to mow it.",
			"I bought an electric hot tub. Saving the planet, one bubble at a time.",
			"Every little helps. As they say in the supermarket we don't go to.",
			"We fly a lot, but we FEEL very bad about it. That counts, doesn't it?",
		],
	},
	&"electric_cars": {
		"open": [
			"We've gone electric. It's a Tesla. We're keeping the diesel for long trips. All trips.",
			"The charging point in the village is ALWAYS taken. By the other Tesla.",
			"I love the electric car. Silent. The pedestrians never hear you coming.",
			"I've got range anxiety. Not about the car. About the conversations at the service station.",
			"We had a charger installed. It took the electrician four months. And a crane.",
		],
		"reply": [
			"Ours is a hybrid. We've never plugged it in. Not once.",
			"I just like that it makes a noise like a spaceship.",
			"Doesn't it take ages to charge? I'd have to sit in a Starbucks. With people.",
			"We've got one of each. One to save the planet, one to get places.",
			"Is it the one Elon makes? Or the one the German man makes?",
		],
		"more": [
			"You can do all your Zoom calls from the car while it charges. Very productive.",
			"It's got a fart button. The kids love it. Gerald loves it more.",
			"We drove to Scotland in it. It took three days. We stopped in eleven Waitroses.",
			"The battery's made from minerals. I don't like to think about where. So I don't.",
			"It's better for the environment. We have two of them. So double better.",
		],
	},
	&"the_dole": {
		"open": [
			"Some people don't seem to want to work at all. Tarquin hasn't worked since 2009. But that's a sabbatical.",
			"They say benefits are too generous. I've never had them. I had a trust fund instead. Very different.",
			"I just think everyone should stand on their own two feet. Like I did. With Daddy's help.",
			"Imagine living on the dole. Imagine. Actually, I can't. I've tried. I got a headache.",
			"It's about personal responsibility. Like when I crashed the company and got a bonus.",
		],
		"reply": [
			"I was unemployed for a whole summer once. Between Oxford and the bank. It was hell.",
			"Gosh, how DO people manage? I can barely manage on mine.",
			"My son's 'finding himself'. He's twenty-nine. We pay his rent. It's different.",
			"It's all very complicated. I read a Guardian article about it. Half of it.",
			"Our cleaner works three jobs. I said, 'goodness, you're so lucky to be busy.'",
		],
		"more": [
			"I said to the cleaner, you should invest. She laughed. I don't know why.",
			"If they want money, they should just ask their parents. Like normal people.",
			"I tried to live on a budget once. For a week. For a charity. It was a VERY big week.",
			"Of course the farming subsidies are different. That's land. Land's important.",
			"People just need a leg up. I had a leg up. Two legs up. And a pony.",
		],
	},
	&"immigration": {
		"open": [
			"I'm all for controlled immigration. Like us, moving to the Dordogne in the summers.",
			"They come over here and do all the jobs. Our nanny. Our cleaner. The builders. The fruit picking. Thank God.",
			"Nobody wants to do the hard work any more. I certainly don't. That's why we hire people.",
			"We'd retire to Spain. We'd be expats, of course. Not immigrants. Expats.",
			"Our builder's from Poland. Best builder we've ever had. We pay him in exposure. Kidding. Mostly.",
		],
		"reply": [
			"I'm not against it at all. I've got so many friends who are foreign. In Tuscany.",
			"Without them, who'd make the flat whites? Not me. I can't work the machine.",
			"We lived in Hong Kong for six years. Never learned a word. Didn't need to.",
			"The village has always had incomers. Look at us!",
			"My great-grandfather came over from Germany. But that was before it was a thing.",
		],
		"more": [
			"I have to say, the Italian deli in the village is the only good thing that's happened here.",
			"We're incomers too, really. We've only been here since the conservatory.",
			"I don't think people realise how much they contribute. The NHS would collapse. Our kitchen would collapse.",
			"The farm couldn't run without seasonal workers. I know that. I've READ that.",
			"Honestly, my house in France has a better community spirit. They wave at me. Sometimes.",
		],
	},
	&"good_old_days": {
		"open": [
			"Things were better in the old days. When I was young. And it was cheaper. For me.",
			"When I was a child we had nothing. Well, one pony. Shared. With my sister.",
			"You could buy a house for three thousand pounds back then. We bought six.",
			"Remember when the pub was full of characters? Now it's full of... well, us.",
			"In my day you respected your elders. And your elders had nicer cars.",
		],
		"reply": [
			"We used to leave the door open. Of course, we had a gate. And a dog. And a man.",
			"Children these days don't know how lucky they are. Mine certainly don't.",
			"It was a simpler time. Fewer forms. More boarding schools.",
			"I miss proper Sunday roasts. Before everyone was a vegan.",
			"I miss the summers. They were longer. And in Antibes.",
		],
		"more": [
			"Nobody had mobile phones. You had to shout at the help across the house.",
			"We used to walk miles to school. Well, the chauffeur did. We were in the car.",
			"You could smoke in pubs. Cigars. Proper cigars. In someone else's face.",
			"Everyone knew their place. And their postcode.",
			"It's all political correctness now. You can't even say what you think. I do. Loudly. Constantly.",
			"Things were better before. Before what, I couldn't say. Before.",
		],
	},
}

## Shared pools. Keys use the topic "_" (e.g. "_/segue/2").
const SHARED := {
	## Works after any line, on any topic.
	"reply": [
		"Gosh.", "No!", "Well, quite.", "Totally.", "Mm. Mm-hm. Mm.",
		"That's SO interesting.", "We did exactly the same thing, actually.",
		"Oh, I know. I KNOW.", "That's what I said to Rupert!", "Ha! Classic.",
		"Isn't it just.", "Honestly, though.", "I couldn't agree more. What did you say?",
		"Oh, you're so funny. Are you being funny?", "Well, you would, wouldn't you.",
	],
	## Said before an `open` line when the conversation changes subject.
	"segue": [
		"Anyway.", "Speaking of which...", "Oh! That reminds me.", "Talking of money...",
		"But enough about you.", "Changing the subject...", "Not to be boring, but...",
		"You'll love this.",
	],
	## Wraps up a conversation.
	"close": [
		"Anyway. Same again?", "We should do supper.", "I'll WhatsApp you.",
		"Must dash, the babysitter's on double time.", "Let's get the Hendersons over.",
		"Gosh, is that the time? It's barely eight.", "Shall we get a bottle for the table?",
	],
	## What a local or rugby lad says when a second-homer won't stop talking at them.
	"local": [
		"Right.", "Is it.", "Mm.", "Couldn't tell you, mate.", "Lovely.", "Fair enough.",
		"I'm just here for the darts.", "You what?", "Yeah. No.", "Good for you.",
		"I drive a van.", "Never been.", "My nan lives in a bungalow.", "Cheers then.",
		"Pint?", "Not really my area.",
	],
	## Yelped when a fight breaks out (or someone gets hit) mid-conversation.
	"interrupt": [
		"Oh my GOD!", "Not in front of the Labrador!", "Somebody call someone!",
		"I'll have you know I'm a magistrate!", "Mind the Barolo!", "Is this... a pub fight?",
		"Gerald, DO something!", "I'm writing to the parish council!",
		"This is like that documentary!", "My gilet!", "We're leaving. After this drink.",
		"I KNEW we should have gone to the gastropub.", "Somebody get my phone. For a video.",
	],
}


## Every topic id, in a stable order.
static func topics() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in TOPICS:
		out.append(t)
	return out


static func key(topic: StringName, part: String, index: int) -> String:
	return "%s/%s/%d" % [topic, part, index]


## Text for a key, or "" if the key is unknown.
static func text(line_key: String) -> String:
	var bits := line_key.split("/")
	if bits.size() != 3 or not bits[2].is_valid_int():
		return ""
	var pool: Variant = null
	if bits[0] == "_":
		pool = SHARED.get(bits[1])
	else:
		var t: Variant = TOPICS.get(StringName(bits[0]))
		if t is Dictionary:
			pool = t.get(bits[1])
	var i := bits[2].to_int()
	if pool is Array and i >= 0 and i < pool.size():
		return pool[i]
	return ""


## Voice file a recorded line would live at (it may not exist).
static func voice_path(line_key: String) -> String:
	var bits := line_key.split("/")
	if bits.size() != 3:
		return ""
	var topic := "shared" if bits[0] == "_" else bits[0]
	return "res://assets/audio/voice/chatter/%s_%s_%02d.ogg" % [topic, bits[1], bits[2].to_int()]


## Every key, for recording scripts and tests.
static func all_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for t in TOPICS:
		for part in TOPICS[t]:
			for i in TOPICS[t][part].size():
				out.append(key(t, part, i))
	for part in SHARED:
		for i in SHARED[part].size():
			out.append(key(&"_", part, i))
	return out


static func pick(topic: StringName, part: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = SHARED[part] if topic == &"_" else TOPICS[topic][part]
	return key(topic, part, rng.randi_range(0, pool.size() - 1))
