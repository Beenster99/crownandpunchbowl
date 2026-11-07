extends Node
## Global signal bus. Systems talk to each other through these signals so that
## workstreams (combat, AI, audio, gore, HUD) stay decoupled.
## Add new signals here rather than reaching across the scene tree.
## Combat signals fire on every peer (the Fighter replicates them), so FX and HUD work on
## clients. Gameplay listeners (AI, scoring, pub flow) must check multiplayer.is_server().

# --- Combat ---------------------------------------------------------------
## A hit landed. `info` keys: attacker, victim (Node), move (String), damage (float),
## position (Vector3), direction (Vector3), heavy (bool), to_face (bool).
signal hit_landed(info: Dictionary)
signal fighter_knocked_down(fighter: Node)
signal fighter_crawling(fighter: Node)
signal fighter_knocked_out(fighter: Node)
## A fighter stood back up after a knockdown (or healed out of a crawl).
signal fighter_got_up(fighter: Node)
## An enemy started a counterable attack. `seconds` is the counter window.
signal attack_telegraphed(attacker: Node, target: Node, seconds: float)
## `defender` parried `attacker`'s punch with a well-timed block (their next punch counters).
signal attack_countered(defender: Node, attacker: Node)
## A strike hit nothing: the target stepped out of reach or off to the side.
## A player locked on to `target` (null: let go). Local to the player's own peer.
signal lock_changed(player: Node, target: Node)
signal attack_whiffed(attacker: Node, move: StringName)
## A punter started a punch and pulled out of it (a feint).
signal attack_feinted(attacker: Node)
## `defender` was blocking, but a guard breaker (kick, headbutt, haymaker) went through.
signal guard_broken(defender: Node, attacker: Node)
## Head shots have him on wobbly legs (Fighter.is_rocked), or body shots have winded him.
signal fighter_rocked(fighter: Node)
signal fighter_winded(fighter: Node)
## `fighter` threw the last move of a named combo ("One-two", "Counter"...).
signal combo_performed(fighter: Node, combo_name: String)
## `fighter` was thrown over a railing or off an open edge.
signal fighter_thrown_off_ledge(fighter: Node, thrower: Node, railing: bool)
## `fighter` landed after falling `height` metres (only falls that hurt).
signal fighter_fell(fighter: Node, height: float)
signal nose_broken(fighter: Node)
signal grab_started(holder: Node, victim: Node)
signal grab_ended(holder: Node, victim: Node)
## A grab failed: the victim (a strong man) shrugged the holder off.
signal grab_shrugged(holder: Node, victim: Node)
signal combo_changed(player: Node, combo: int)

# --- Items & bar ----------------------------------------------------------
signal item_picked_up(fighter: Node, item: Node)
signal item_broken(item: Node)
## A pub prop (glass, plate, shelf bottle...) smashed. Fires on every peer, just before it's freed.
signal prop_smashed(prop: Node)
## A fighter knocked flying went over an obstacle (the bar, a table). Fires on every peer.
signal fighter_flipped_over(fighter: Node, obstacle: Node)
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
