class_name GameUi
extends Node
## Everything a pub needs on screen: the HUD and the pause menu.
## Each pub scene adds one: `add_child(preload("res://scenes/ui/game_ui.tscn").instantiate())`.

var hud: Hud
var pause_menu: PauseMenu


func _ready() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
