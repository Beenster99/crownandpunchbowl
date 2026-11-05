# Pubs and levels

The four village pubs are greybox scenes built in code from a small kit, so layouts
are quick to change and every pub shares the same markers and flow. Owned by the
Pubs workstream (`scenes/pubs/`, `scripts/level/`).

| Pub | Era | Layout |
| --- | --- | --- |
| The Crown and Punchbowl | 17th c. | One big low-beamed room. Inglenook on the left, bar along the back, darts and pool on the right, front door by the pool table. |
| The King William | 18th c. | Georgian. Saloon (fireplace with mantel, pool, chandelier) and tap room (bar with brass rail, darts) joined by a wide arch. Two front doors. Sash windows, painted panelled walls. |
| The Farmers Dog | 19th c. | Victorian. Island bar with a carved, mirrored gantry. Etched glass screen splits the public bar (pool, darts, iron range) from the saloon (fireside tables, settles). Encaustic tiles, gas lamps. Two front doors. |
| The Pillock Tickle | 17th c. | Cramped and ramshackle. Tap room (bar on the side wall, barrels) through a low doorway to the lounge (inglenook, settle, pool, darts). Back door to the beer garden. |

## Files

| File | What it does |
| --- | --- |
| `scripts/level/pub_level.gd` | `PubLevel`, the base for every pub: builds it, lighting, camera, occluder fading, player and prop spawning, and the pub flow. |
| `scripts/level/pub_builder.gd` | `PubBuilder`, the greybox kit: floors, walls with doors and windows, beams, bar, back bar, fireplaces, dartboard, pool table, tables, lamps, markers. |
| `scripts/level/pub_era.gd` | `PubEra`: colours, floor pattern, wall height and lighting for the 17th, 18th and 19th century. |
| `scripts/level/occluder_fader.gd` | `OccluderFader`: fades anything in `camera_occluders` that sits between the camera and a player. |
| `scripts/level/<pub_id>.gd` + `scenes/pubs/<pub_id>.tscn` | One per pub. The script sets `pub_id`, `era` and `room` and lays the pub out in `_build()`. |

## Pub flow

`PubLevel.phase` goes **ARRIVING → CALM → FIGHT → CLEARED** (or **LOST**).

- **ARRIVING**: banner with the pub's name and era. After `arrival_time` it becomes CALM.
- **CALM**: everyone's civilised. The first `Events.hit_landed` between a player and a
  non-staff fighter makes the host emit `Events.fight_started`. The AI director can also
  emit it.
- **FIGHT**: the host checks for a clear whenever a non-player is knocked out
  (`Events.fighter_knocked_out`). The pub is cleared when every node in `npcs` or
  `police` that isn't in `staff` is knocked out and `arrivals_pending` is 0.
- **CLEARED**: `Events.pub_cleared(pub_id)` and a banner. After `clear_delay` the host
  calls `travel_to.rpc(next_index, pubs_cleared)` and every peer loads the next pub.
  After all four pubs the crawl ends and everyone returns to the menu.
- **LOST**: every player is knocked out. `Events.all_players_down`, then the host
  reloads the same pub.

The crawl starts with `GameData.start_crawl(index)` (the main menu calls it with the
host's pick) and visits each pub once, in order, wrapping round.

### Hooks for other workstreams

- **AI director**: set `PubLevel.current().arrivals_pending` while punters or police are
  still on their way in, then call `check_cleared()` when it drops to 0. Spawn NPCs under
  `actors_root()`.
- **Fighter / combat**: emit `Events.fighter_knocked_out` on KO. Optionally give fighters
  `is_knocked_out() -> bool`.
- **Items**: put a scene at `scenes/items/<item>.tscn` and the pub spawns it on every
  matching prop marker, named `I<n>`, under `items_root()`. Until a scene exists the
  pub drops a greybox stand-in there. Stand-in tables, chairs and stools are solid.
- **Bar**: `get_bar_zones()` returns `Area3D`s (mask: players) along the front of each bar.
- **Net**: players are spawned on every peer as `P<peer_id>` in peer-id order on the
  `PlayerSpawns` markers. `travel_to` is the synced pub change.

## Markers

`PubLevel.get_markers(kind)` returns the `Marker3D`s under `Markers/<kind>`. A marker's
-Z axis faces where the thing should look. Extra data is stored in node metadata.

| Kind (constant) | Use | Metadata |
| --- | --- | --- |
| `PubLevel.PLAYERS` (`PlayerSpawns`) | Where players walk in | |
| `PubLevel.PUNTER` (`PunterSpots`) | Where calm punters start | `pose`: `seated`, `standing`, `bar`, `darts`, `pool` |
| `PubLevel.STAFF` (`StaffSpots`) | Behind the bar | |
| `PubLevel.DOORS` (`DoorSpawns`) | Arrivals, outside the door | `inside`: Vector3 to walk to |
| `PubLevel.POLICE` (`PoliceSpawns`) | Where the police come in | `inside` |
| `PubLevel.PROPS` (`PropSpawns`) | Weapon and consumable spawns | `item`: `bottle`, `glass`, `pint`, `plate`, `chair`, `stool`, `table`, `pool_cue`, `darts`, `poker`, `fire_tongs`, `fire_shovel` |

## Camera and fading

The pub makes a `BrawlCamera` and keeps its framing centre over the room (`room` minus
a margin, larger at the front so you don't look out at the street). `OccluderFader`
fades walls, beams, posts, chimney breasts and hanging lamps when they're between the
camera and a player's feet, chest or head, and brings them back when they're clear.

## Adding or changing a pub

1. Copy one of the pub scripts and scenes, and set `pub_id`, `era` and `room` in `_init()`.
2. Lay it out in `_build(b)`. Walls go on the room edges: `wall_x(z, x0, x1, openings)` and
   `wall_z(x, z0, z1, openings)`. Openings are `{c, w, top, sill, kind}`.
3. Add it to `GameData.PUBS`. `tests/pubs_test.gd` checks it automatically.

Greybox is code so it stays easy to change. When real art arrives, swap the builder
calls for imported models one piece at a time and keep the markers.
