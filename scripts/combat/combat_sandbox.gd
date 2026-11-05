extends "res://scripts/level/test_pub.gd"
## Combat sandbox: the greybox test pub plus a few sparring punters and a tough one.
## Open scenes/actors/combat_sandbox.tscn in the editor and press F6 (Run Current Scene).
## Starts a solo session itself if launched directly.

const PUNTER_SCENE := preload("res://scenes/actors/sparring_punter.tscn")


func _ready() -> void:
	if Net.players.is_empty():
		Net.start_solo("Sparring", 0)
	super()
	var spots := [Vector3(-2, 0, -1), Vector3(2, 0, -1.5), Vector3(0, 0, -3), Vector3(-5.5, 0, 1.5)]
	for i in spots.size():
		var p: SparringPunter = PUNTER_SCENE.instantiate()
		p.name = "N%d" % i
		p.position = spots[i]
		if i == 3:  # a rugby lad: tougher and hits harder
			p.toughness = 1.8
			p.max_hp = 160.0
			p.power = 1.3
			p.haymaker_chance = 0.5
		$Actors.add_child(p)
	Events.banner.emit("Combat sandbox: punch someone to start it", 4.0)
