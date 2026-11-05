# Conventions and shared contracts

Every workstream builds on these. If you need to change one, do it in a small,
separate PR so other branches can rebase onto it.

## Folders

| Path | Contents |
| --- | --- |
| `scenes/main/` | Entry scenes (main menu, boot) |
| `scenes/actors/` | Player, NPC and staff scenes |
| `scenes/pubs/` | One scene per pub, plus `test_pub.tscn` greybox sandbox |
| `scenes/items/` | Weapon and consumable scenes |
| `scenes/ui/` | Menus, HUD, settings screens |
| `scripts/autoload/` | Singletons: `Events`, `GameData`, `Settings`, `Net` |
| `scripts/actors/` | Fighter base class, player and NPC actor scripts |
| `scripts/combat/` | Moves, hit resolution, targeting, grabs |
| `scripts/ai/` | NPC brains, director, waves, police |
| `scripts/items/` | Item behaviour and item data |
| `scripts/level/` | Pub flow, camera, spawn logic |
| `scripts/net/` | Lobby, spawners, sync helpers |
| `scripts/fx/` | Audio playback, blood, hit-stop, shake |
| `scripts/ui/` | UI scripts |
| `assets/` | `models/`, `textures/`, `audio/{sfx,voice,music}/`, `fonts/` |
| `tools/` | Developer scripts that need a renderer (e.g. character capture) |
| `tests/` | Headless tests (`godot --headless --path . --script res://tests/<name>.gd`) |

## Characters
Every character is a `CharacterRig` with a `CharacterLook` from `CharacterLooks`. Animation
names, the Fighter state mapping and sockets are a contract: see [CHARACTERS.md](CHARACTERS.md).
NPC looks take a seed every peer agrees on (the `N<n>` number) so crowds match on every machine.

## Code style
- GDScript with static types where practical. Tabs for indents. `snake_case` files, `PascalCase` `class_name`.
- One `class_name` per reusable script. Scenes are named after their root script.
- Don't reach across the tree with long `get_node` paths. Use groups, `Events` signals, or exported references.
- Tunable numbers live in `GameData` or exported vars, not inline constants.

## Autoloads
- **Events**: global signal bus (`scripts/autoload/events.gd`). Gameplay emits; FX, audio and HUD listen.
- **GameData**: farmers, pubs, difficulty tables, and the current pub and difficulty.
- **Settings**: Gameplay, Sound, Graphics and Keybinds, saved to `user://settings.cfg`. Read with
  `Settings.get_value(section, key)`. Listen to `Settings.changed`.
- **Net**: multiplayer entry point (solo, host, join).

## Input actions (contract)
`move_up`, `move_down`, `move_left`, `move_right`, `punch`, `kick`, `headbutt`, `counter`, `grab`,
`dodge`, `interact`, `order_food`, `throw`, `pause`. Defaults for keyboard/mouse and controller
are in `Settings.ACTIONS`. Never add input actions in `project.godot`. Add them to `Settings.ACTIONS`
so they appear in the keybinds screen.

## Groups
`players`, `npcs`, `staff`, `police`, `items`, `consumables`, `camera_occluders`.

## Physics layers
1 world · 2 players · 3 npcs · 4 items · 5 hitboxes · 6 hurtboxes · 7 ragdoll (cosmetic bodies; they only collide with the world).

## Audio buses
`Master` → `Music`, `SFX`, `Voice` (created by `Settings` at startup). Every sound must use one of these.

## Networking rules (follow from day one, even in solo)
- The **host is authoritative** for NPCs, items, damage, the director and pub flow.
- Each **player node is owned by its peer** (`set_multiplayer_authority(peer_id)`). The owner
  moves it. Actions (attack, grab, interact, throw) go to the host as RPCs. The host resolves
  them and replicates the results.
- Gameplay checks use `is_multiplayer_authority()` and `multiplayer.is_server()`, never "is solo".
  Solo runs through `OfflineMultiplayerPeer`, so the same paths are exercised.
- Spawned node names must be deterministic: players `P<peer_id>`, NPCs `N<n>`, items `I<n>`.
- FX (blood, sound) are cosmetic. They're triggered by RPC or synced state and never affect gameplay.

## Fighter API (draft, finalised by the Combat workstream's first PR)
```gdscript
class_name Fighter extends CharacterBody3D
enum State { IDLE, ATTACK, WINDUP, STAGGER, DOWN, CRAWL, KO, HELD, GRABBING, DODGE }
var team: int            # 0 players, 1 punters, 2 police, 3 staff
var hp: float
var max_hp: float
var state: State
func take_hit(info: Dictionary) -> void   # same keys as Events.hit_landed
func heal(amount: float) -> void
func is_down() -> bool                    # DOWN, CRAWL or KO
func can_be_targeted() -> bool
```
