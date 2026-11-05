extends Node
## Global signal bus. Systems talk to each other through these signals so that
## workstreams (combat, AI, audio, gore, HUD) stay decoupled.
## Add new signals here rather than reaching across the scene tree.
## Emit on the peer that owns the event (usually the server); FX listeners run everywhere.

# --- Combat ---------------------------------------------------------------
## A hit landed. `info` keys: attacker, victim (Node), move (String), damage (float),
## position (Vector3), direction (Vector3), heavy (bool), to_face (bool).
signal hit_landed(info: Dictionary)
signal fighter_knocked_down(fighter: Node)
signal fighter_crawling(fighter: Node)
signal fighter_knocked_out(fighter: Node)
signal nose_broken(fighter: Node)
signal grab_started(holder: Node, victim: Node)
signal grab_ended(holder: Node, victim: Node)
signal combo_changed(player: Node, combo: int)

# --- Items & bar ----------------------------------------------------------
signal item_picked_up(fighter: Node, item: Node)
signal item_broken(item: Node)
signal drink_ordered(player: Node)
signal food_ordered(player: Node)
signal player_healed(player: Node, amount: float)

# --- Pub flow -------------------------------------------------------------
signal fight_started()
signal reinforcements_arrived(count: int)
signal police_called()
signal pub_cleared(pub_id: String)
signal all_players_down()
## Short on-screen message, e.g. "Old Bill's here!".
signal banner(text: String, seconds: float)
