extends Node
## Static game data shared by every workstream: farmers, pubs, difficulty levels.
## Tuning values here are first-pass placeholders; owners of each workstream
## should adjust them (and keep the keys stable so other systems don't break).

const FARMERS := [
	{
		"id": "tom", "name": "Tom \"Muckspreader\" Pryce",
		"blurb": "Built like a grain silo. Slow, but his forehead is a weapon.",
		"max_hp": 140.0, "power": 1.25, "speed": 4.0, "grip": 1.0,
		"trait": "iron_forehead",
	},
	{
		"id": "gaz", "name": "Gaz Whitlock",
		"blurb": "Wiry hedge-layer. Quick hands, quicker temper.",
		"max_hp": 95.0, "power": 0.9, "speed": 5.4, "grip": 0.8,
		"trait": "flurry",
	},
	{
		"id": "barrow", "name": "Old Man Barrow",
		"blurb": "Seventy-three and refuses to fall over. Ale heals him twice as much.",
		"max_hp": 120.0, "power": 1.0, "speed": 3.8, "grip": 1.1,
		"trait": "seasoned_drinker",
	},
	{
		"id": "mags", "name": "Margaret \"Mags\" Fenwick",
		"blurb": "Runs the dairy herd and the parish council. Kicks like a heifer, never lets go.",
		"max_hp": 105.0, "power": 1.05, "speed": 5.0, "grip": 1.6,
		"trait": "vice_grip",
	},
	{
		"id": "dicky", "name": "Dicky Thresher",
		"blurb": "Gets better the more he drinks. Gets worse at standing up.",
		"max_hp": 110.0, "power": 0.95, "speed": 4.6, "grip": 0.9,
		"trait": "drunken_master",
	},
	{
		"id": "kev", "name": "Kev Haybale",
		"blurb": "Treats everything in the pub as a tool. Weapons last longer in his hands.",
		"max_hp": 115.0, "power": 1.0, "speed": 4.6, "grip": 1.0,
		"trait": "handyman",
	},
]

## Era drives the look of each pub (beams, panelling, lighting, props).
const PUBS := [
	{"id": "crown_and_punchbowl", "name": "The Crown and Punchbowl", "era": "17th century",
		"scene": "res://scenes/pubs/test_pub.tscn"},
	{"id": "king_william", "name": "The King William", "era": "18th century",
		"scene": "res://scenes/pubs/test_pub.tscn"},
	{"id": "farmers_dog", "name": "The Farmers Dog", "era": "19th century",
		"scene": "res://scenes/pubs/test_pub.tscn"},
	{"id": "pillock_tickle", "name": "The Pillock Tickle", "era": "17th century",
		"scene": "res://scenes/pubs/test_pub.tscn"},
]

## Multipliers read by AI, combat and spawning. 1.0 = baseline.
const DIFFICULTIES := [
	{"id": "shandy", "name": "Pint of Shandy", "blurb": "A gentle evening out.",
		"enemy_damage": 0.6, "enemy_health": 0.8, "max_attackers": 2, "gang_up_chance": 0.15,
		"police_chance": 0.2, "heal_multiplier": 1.4, "telegraph_time": 0.75, "reinforcements": 0.7},
	{"id": "session", "name": "Session Ale", "blurb": "A proper night out.",
		"enemy_damage": 1.0, "enemy_health": 1.0, "max_attackers": 3, "gang_up_chance": 0.3,
		"police_chance": 0.4, "heal_multiplier": 1.0, "telegraph_time": 0.6, "reinforcements": 1.0},
	{"id": "scrumpy", "name": "Scrumpy", "blurb": "Your legs will go before your fists do.",
		"enemy_damage": 1.3, "enemy_health": 1.2, "max_attackers": 4, "gang_up_chance": 0.5,
		"police_chance": 0.6, "heal_multiplier": 0.8, "telegraph_time": 0.48, "reinforcements": 1.3},
	{"id": "last_orders", "name": "Last Orders", "blurb": "Nobody leaves standing.",
		"enemy_damage": 1.7, "enemy_health": 1.4, "max_attackers": 6, "gang_up_chance": 0.7,
		"police_chance": 0.85, "heal_multiplier": 0.6, "telegraph_time": 0.38, "reinforcements": 1.6},
]

## Session state chosen in the lobby. The host owns these and syncs them to clients.
var current_pub_index := 0
var difficulty_index := 1


func current_pub() -> Dictionary:
	return PUBS[current_pub_index]


func difficulty() -> Dictionary:
	return DIFFICULTIES[difficulty_index]


func advance_pub() -> void:
	current_pub_index = (current_pub_index + 1) % PUBS.size()
