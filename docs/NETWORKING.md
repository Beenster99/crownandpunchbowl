# Networking and co-op

Owned by workstream 3. Code lives in `scripts/autoload/net.gd` (the `Net` autoload) and
`scripts/net/`. Rules every workstream follows are in [CONVENTIONS.md](CONVENTIONS.md#networking-rules-follow-from-day-one-even-in-solo).

## How a night out runs

1. **Lobby.** The host calls `Net.host(name, farmer)`. Mates call `Net.join(address, name, farmer)`.
   Clients register with the host, which keeps `Net.players` (`peer_id -> {name, farmer, ready}`)
   and broadcasts it. Anyone can `set_farmer()`, `set_player_name()`, `set_ready()`. Only the host can
   `set_pub()` and `set_difficulty()`; both are synced into `GameData` on every peer.
   Joins are refused when the lobby is full (4), the fight has started, or the build differs
   (`PROTOCOL_VERSION`).
2. **Start.** When `Net.can_start()` (every client ready), the host calls `Net.start_game()`.
   Every peer loads the pub scene from `GameData.current_pub()`.
3. **Load handshake.** Each pub's `_ready()` ends with `Net.level_ready()`. When every connected
   peer has reported in, the host emits `Net.all_peers_loaded`. Spawn things after that, never
   in `_ready()`, so a slow client never misses a spawn.
4. **Spawning.** `PlayerSpawner` (a `MultiplayerSpawner`) spawns `P<peer_id>` per player, owned
   by that peer. `NetSync.attach()` gives each actor two synchronizers: `MoveSync` (owner:
   position, rotation, velocity) and `StateSync` (host: `hp`, `max_hp`, `state`, `team` when the
   node has them). Every replicated node joins the `net_spawned` group.
5. **Pub to pub.** On the host, `Events.pub_cleared` makes `CoopRules` announce the next pub and
   call `Net.next_pub()` after a short pause. A wipe calls `Net.restart_pub()`. Both despawn all
   `net_spawned` nodes first, then move every peer to the new scene, and the handshake repeats.
6. **Drop-outs.** If a client leaves, the host removes them from `Net.players`, everyone gets
   `Net.player_dropped` and a banner, and their player node is despawned. If the host leaves,
   clients return to the main menu with `Net.last_error` shown.

Solo uses `OfflineMultiplayerPeer` and runs through exactly the same calls.

## Downed and revive (`CoopRules`)

- A player is downed when `Fighter.is_down()` is true.
- A standing mate within `revive_radius` (1.6 m) holding `interact` for `revive_time` (3 s)
  picks them up. Clients only send "holding / not holding" to the host; the host decides.
- The host calls `revive(fraction)` on the fighter if it has it (preferred), else
  `heal(max_hp * fraction)`. Default fraction 0.35.
- `CoopRules.revive_progress(downed, reviver, t)` fires on every peer for the HUD (t = -1 when
  the reviver lets go). `player_revived(downed, reviver)` fires when done.
- If every player is down at once: `Events.all_players_down`, a banner, and the pub restarts.

## What other workstreams need to do

- **Combat (1):** add `revive(fraction: float)` to `Fighter` to leave the down/crawl state. Send
  attacks, grabs and throws to the host as RPCs on the player node (it's owned by the client,
  so use `@rpc("any_peer")` and check `multiplayer.get_remote_sender_id()` matches the owner).
  Keep `hp` and `state` as plain properties so `StateSync` picks them up. Holding a punter for
  a mate is resolved on the host, so it works online with no extra net code.
- **AI (2):** spawn NPCs and items with your own `MultiplayerSpawner` after
  `Net.all_peers_loaded`, name them `N<n>` / `I<n>`, add them to `Net.SPAWNED_GROUP`, and call
  `NetSync.attach(node, 1)`. Emit `Events.pub_cleared` on the host when the pub is cleared.
- **Pubs (4):** every pub scene adds a `PlayerSpawner` and a `CoopRules` node (named
  `CoopRules`) and calls `Net.level_ready()` at the end of `_ready()`. See `scripts/level/test_pub.gd`.
- **Menus (7):** `scripts/net/lobby_screen.gd` is a working lobby built only on the `Net` API.
  Restyle or replace it freely.

## Playing over the internet

The host needs UDP port 24565 (or whatever they pick) forwarded on their router. On a LAN,
join with the host's local IP. Relay/NAT punch-through (e.g. Steam or a relay server) is a
later task.

## Tests

```
godot --headless --path . --script res://tests/smoke_test.gd       # solo path
godot --headless --path . --script res://tests/coop_rules_test.gd  # revive and wipe
tests/run_net_test.sh                                              # host + client over ENet
```

`run_net_test.sh` runs two headless Godot processes: it checks joining, lobby sync of pub,
difficulty and farmer, ready and start, spawning with the right owners, movement replicated
both ways, the move to the next pub, and the host handling the client leaving.
