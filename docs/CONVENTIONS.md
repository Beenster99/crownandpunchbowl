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
`fighters` (every Fighter, added automatically), `players`, `npcs`, `staff`, `police`, `items`,
`consumables`, `camera_occluders`.

## Physics layers
1 world · 2 players · 3 npcs · 4 items · 5 hitboxes · 6 hurtboxes.

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
- Pub scenes call `Net.level_ready()` at the end of `_ready()` and spawn only after
  `Net.all_peers_loaded`. Replicated nodes join `Net.SPAWNED_GROUP` and use `NetSync.attach()`.
  Details in [NETWORKING.md](NETWORKING.md).
- FX (blood, sound) are cosmetic. They're triggered by RPC or synced state and never affect gameplay.

## Fighter API

Implemented in `scripts/actors/fighter.gd` (`class_name Fighter`). Move numbers live in
`scripts/combat/moves.gd` (`Moves`), freeflow target picking in `scripts/combat/targeting.gd`
(`Targeting`). Tests: `godot --headless --path . --script res://tests/combat_test.gd`.

```gdscript
class_name Fighter extends CharacterBody3D        # every Fighter joins group "fighters"
enum State { IDLE, ATTACK, WINDUP, STAGGER, DOWN, CRAWL, KO, HELD, GRABBING, DODGE }
enum Team { PLAYERS, PUNTERS, POLICE, STAFF }      # 0, 1, 2, 3

# Exported tuning: team, max_hp, power, move_speed, toughness, grip, crawl_fraction,
# can_be_knocked_out (false for staff), get_up_time
var hp: float
var state: State
var move_input: Vector3      # controller writes this every physics frame (world XZ, length <= 1)
var target: Fighter          # who the current move is aimed at
var held_by: Fighter         # set while HELD
var holding: Fighter         # set while GRABBING
var weapon: Node             # see equip()
var tipsy: float             # 0..1, written by the bar / drinks
var nose_broken: bool

# Signals (fire on every peer)
signal state_changed(old_state, new_state)
signal move_started(move_id)          # animation hook
signal hit_taken(info)
signal hit_dealt(info)

# Queries
func is_down() -> bool                # DOWN, CRAWL or KO
func is_ko() -> bool
func can_act() -> bool                # IDLE
func can_chain() -> bool              # in an attack's recovery
func can_be_targeted() -> bool
func can_be_hit() -> bool             # false while KO, dodging (i-frames) or just got up
func can_be_grabbed() -> bool
func is_hostile_to(other) -> bool     # players vs punters and police; staff are nobody's enemy
func can_hit(other) -> bool           # players can still hit staff on purpose
func is_counterable_by(defender) -> bool
func windup_remaining() -> float      # for counter prompts
func get_facing() -> Vector3
func hp_fraction() -> float

# Requests: call on the fighter's authority (owner for players, host for NPCs).
# Forwarded to the host, validated, and replicated to everyone.
func request_attack(move_id: StringName, target: Fighter = null)  # null = freeflow pick
func request_grab(victim: Fighter = null)
func request_release()
func request_throw()                  # throw the held fighter
func request_counter()
func request_dodge(dir: Vector3)
func request_struggle()               # call repeatedly while HELD

# Host only
func take_hit(info: Dictionary)       # keys as Events.hit_landed; see fighter.gd for extras
func heal(amount: float)              # applies difficulty heal_multiplier for players
func revive(hp_fraction := 0.3)       # co-op revive (M2)

# Weapons (workstream 5): call on every peer. Item may implement on_equipped(f),
# on_unequipped(f), modify_move(move: Dictionary) -> Dictionary, on_hit(info) (host only).
func equip(item: Node)
func unequip() -> Node
```

Rules other workstreams rely on:
- **Difficulty is applied inside Fighter.** Punters and police get `enemy_health` on `_ready`,
  hits on players get `enemy_damage`, and `heal()` applies `heal_multiplier`. Set `team`
  before the fighter enters the tree, and don't apply these multipliers again.
- **Enemy tells.** AI attacks with a move that has `telegraph: true` (`swing`, `haymaker`,
  `shove`, `baton`). Its windup becomes the difficulty's `telegraph_time`, the fighter flashes,
  `Events.attack_telegraphed` fires, and the target can counter it.
- **Held fighters** take `Moves.HELD_DAMAGE_MULT` damage from everyone. A holder who is hit
  lets go. A held fighter who goes down is dropped.
- **Health thresholds.** Below `crawl_fraction`, a knocked-down fighter gets up only to crawl.
  At 0 hp they are KO'd: out of targeting and collision. Staff go down but never out.
