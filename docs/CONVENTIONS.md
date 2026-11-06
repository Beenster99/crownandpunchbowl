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
`move_up`, `move_down`, `move_left`, `move_right`, `punch_left`, `punch_right`, `block`, `kick`, `headbutt`, `grab`,
`dodge`, `interact`, `order_food`, `throw`, `pause`. Defaults for keyboard/mouse and controller
are in `Settings.ACTIONS`. Never add input actions in `project.godot`. Add them to `Settings.ACTIONS`
so they appear in the keybinds screen.

## Groups
`fighters` (every Fighter, added automatically), `players`, `npcs`, `staff`, `police`, `items`,
`consumables`, `camera_occluders`.

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
- Pub scenes call `Net.level_ready()` at the end of `_ready()` and spawn only after
  `Net.all_peers_loaded`. Replicated nodes join `Net.SPAWNED_GROUP` and use `NetSync.attach()`.
  Details in [NETWORKING.md](NETWORKING.md).
- FX (blood, sound) are cosmetic. They're triggered by RPC or synced state and never affect gameplay.

## Fighter API

Implemented in `scripts/actors/fighter.gd` (`class_name Fighter`). Move numbers live in
`scripts/combat/moves.gd` (`Moves`), freeflow target picking in `scripts/combat/targeting.gd`
(`Targeting`). Tests: `godot --headless --fixed-fps 60 --path . --script res://tests/combat_test.gd`.

```gdscript
class_name Fighter extends CharacterBody3D        # every Fighter joins group "fighters"
enum State { IDLE, ATTACK, WINDUP, STAGGER, DOWN, CRAWL, KO, HELD, GRABBING, DODGE, BLOCK }
enum Team { PLAYERS, PUNTERS, POLICE, STAFF }      # 0, 1, 2, 3

# Exported tuning: team, max_hp, power, move_speed, toughness, grip, crawl_fraction,
# can_be_knocked_out, get_up_time
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
func can_attack() -> bool             # IDLE, BLOCK or chaining
func is_blocking_from(pos) -> bool    # guard up and pos is in front
func has_counter_ready() -> bool      # just parried: next punch counters
func defend_hint() -> String          # "block" or "dodge" for the move being wound up
func can_chain() -> bool              # in an attack's recovery
func can_be_targeted() -> bool
func can_be_hit() -> bool             # false for staff, and while KO, dodging (i-frames) or just got up
func can_be_grabbed() -> bool
func is_hostile_to(other) -> bool     # players vs punters and police; staff are nobody's enemy
func can_hit(other) -> bool           # same as is_hostile_to: nobody can hit staff
func is_counterable_by(defender) -> bool
func windup_remaining() -> float      # for defend prompts
func get_facing() -> Vector3
func hp_fraction() -> float

# Requests: call on the fighter's authority (owner for players, host for NPCs).
# Forwarded to the host, validated, and replicated to everyone.
func request_attack(move_id: StringName, target: Fighter = null, bonus := 1.0, combo_name := "")  # null = freeflow pick
func request_grab(victim: Fighter = null)
func request_release()
func request_throw()                  # throw the held fighter
func request_block(on: bool)          # hold the guard; raise it just before a punch lands to parry
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
  `shove`, `baton`). Its windup becomes the difficulty's `telegraph_time` times
  `Moves.ENEMY_WINDUP_SCALE` (and the move's `windup_scale`), the fighter flashes,
  `Events.attack_telegraphed` fires, and the target's prompt says Block high (head shots),
  Block low (body shots) or Dodge (moves with `guard_break`).
- **Blocking.** `BLOCK` covers `Moves.BLOCK_ARC` in front for `BLOCK_CHIP` damage. A guard
  raised within `PARRY_WINDOW` of a punch landing parries it: the attacker reels,
  `Events.attack_countered` fires and the defender's next punch gets `COUNTER_BONUS`. Guard
  breakers (kicks, headbutts, haymakers, shoves, batons, throws) stagger a blocker and fire
  `Events.guard_broken`. Blocked hits arrive in `hit_landed` with `blocked: true` (and
  parries with `parried: true`, damage 0), so FX can play a thud instead of blood.
- **Wind-ups are visible.** `move_started` fires once the windup is set, so a visual can read
  `windup_remaining()`. FighterVisual plays the strike's load slowly into the loaded pose and
  holds it (`CharacterRig.play_windup`) until the fighter enters ATTACK (`release_strike`).
- **Weight.** Footwork accelerates and decelerates (`Moves.ACCEL`/`DECEL`), a strike carries
  you forward (`FOLLOW_THROUGH`), and knockback slides off slowly while staggered
  (`STAGGER_DRAG`). `HitLean` (scripts/combat/hit_lean.gd) tips each rig away from blows on a
  damped spring; it is cosmetic and resets when a fighter goes down.
- **Player controls (pad, keyboard in brackets).** X jab (LMB), B hook (RMB), Y uppercut (F),
  R3 headbutt (Q), A dodge along the left stick (Space). LB head guard (Shift), RB body guard
  (Ctrl). RB + a punch goes to the body (`Moves.BODY_PUNCHES`). LB + X kick, LB + Y shoulder
  charge, LB + B clinch knee (`Moves.LB_MOVES`). LB + RB together grabs and holds; while
  holding, punches knee, A or Throw hurls them, LB + RB again lets go. The right stick
  (arrows) moves the head: a flick slips. Combos are in `Moves.COMBOS` and a string keeps
  going while a longer combo can still follow; a combo's `becomes` swaps its last move (jab,
  body jab, kick is "Below the belt", a `groin_kick`). Old saved keybinds from before this
  layout are dropped (`Settings.KEYBIND_LAYOUT`).
- **Head and body.** Every move has a `zone`: head (default), body or groin. A head guard only
  covers head shots, a body guard body and groin shots, so `defend_hint()` says
  `guard_head`, `guard_body` or `dodge`. Hit info carries `zone`, and hooks carry `side`: their
  `direction` is skewed sideways so the head is knocked round, not back. `HeadSnap`
  (scripts/combat/head_snap.gd) is a skeleton modifier that snaps the head (or folds the chest,
  for body shots) on a damped spring over whatever animation plays.
- **Slips.** `request_slip(dir)` (a right-stick flick) makes head shots miss for
  `Moves.SLIP_WINDOW`; slipping within `SLIP_COUNTER_WINDOW` of the hit sets up a counter like a
  parry. Missed hits arrive in `hit_landed` with `slipped: true` and damage 0.
- **Groin kicks** (`doubles`) put the victim in `State.DOUBLED` (on all fours) for
  `Moves.DOUBLED_TIME / toughness`. They can still be hit and held; they're not `is_down()`.
- **Shoulder charge** (`charge`) drives forward at `CHARGE_SPEED` after the wind-up and hits the
  first enemy within `CHARGE_HIT_RANGE`: knockdown, big knockback (for the physics thread's
  over-the-bar vault). **Clinch knee** (`clinch`) ignores a guard and can't be slipped.
- **Holds.** `Fighter.hold_resist` (from `NpcTypes` `hold_resist`) is the chance, over the
  holder's grip, that a grab is shrugged off (halved on a reeling or doubled-over man;
  `Events.grab_shrugged`), and it speeds up their escape.
- **Going down.** Poise is high (`Moves.POISE`) and recovers fast after `POISE_REGEN_DELAY`;
  hits on a staggered man chip less (`STAGGER_POISE_SCALE`). One punch doesn't drop a fresh man.
- **No chasing.** A move steps in at most `Moves.MAX_LUNGE_STEP`; further away it whiffs.
- **Stamina** (`Fighter.stamina` / `max_stamina`, `stamina_fraction()`, `is_gassed()`). Every
  strike costs its move's `stamina` (a whiff the same again), blocked hits drain the blocker by
  the move's `guard_drain` (jabs drain far more than they cost), body shots drain
  `damage * BODY_SHOT_DRAIN`. It regenerates after `STAMINA_REGEN_DELAY` when not striking (half
  rate behind a guard). Under `GASSED`: damage, wind-up and footwork suffer. A guard hit with
  no stamina left is crushed (`guard_crushed: true`, stagger `GUARD_CRUSH_STAGGER`). Costs are
  applied on every peer from the replicated move RPCs; host-side drains go out by `_rpc_stamina`.
- **Power shots.** `request_attack(..., hold = true)` on a `chargeable` move (hooks, uppercuts)
  keeps the fighter in WINDUP after the wind-up, loading (`is_charging()`, `charge_fraction()`,
  `power_charging` signal) until `request_unleash()` or `CHARGE_TIME + CHARGE_HOLD`. Damage,
  stagger and poise scale up to `POWER_MAX`; full charge breaks guards. Being hit cancels it.
  Hits carry `power` (the charge fraction).
- **Punishes.** A hit on a fighter in the recovery of their own strike does `PUNISH_BONUS` and
  carries `punish: true`. Parry and slip counters do `COUNTER_BONUS`.
- **Stance.** `in_stance` / `stance_changed` say when a fighter is squared up for a fight
  (an exchange in the last `STANCE_HOLD` seconds or, for players, an active enemy within
  `ENGAGE_RANGE`). Animations can use it to pick a relaxed idle or a guard.
- **Held fighters** take `Moves.HELD_DAMAGE_MULT` damage from everyone. A holder who is hit
  lets go. A held fighter who goes down is dropped.
- **Health thresholds.** Below `crawl_fraction`, a knocked-down fighter gets up only to crawl.
  At 0 hp they are KO'd: out of targeting and collision.
- **Throwing people off galleries.** A throw within `Moves.LEDGE_THROW_RANGE` of a ledge,
  roughly towards it, sends the victim over: lifted over a railing, or straight off an open
  edge. Ledges are the `Markers/Ledges` markers from the pubs (metadata `normal`, `drop`,
  `railing`) or any node in the `ledges` group (`scripts/combat/ledges.gd`). Emits
  `Events.fighter_thrown_off_ledge`.
- **Falls hurt.** Any landing after a drop of at least `Moves.FALL_MIN_HEIGHT` (1.2 m) does
  `FALL_DAMAGE_PER_M` per metre beyond that, plus a knockdown, and emits `Events.fighter_fell`.
  Daises and stairs don't hurt.
- **Nobody hits the bar staff.** Staff (`Team.STAFF`) can't be targeted, grabbed or hit by
  players or NPCs; attacks pass straight through them and `take_hit` ignores them.

## AI and Director

Implemented in `scripts/ai/`: `Npc` (`npc.gd`, extends Fighter), `Director` (`director.gd`) and
`NpcTypes` (`npc_types.gd`, stats and personality per kind). NPC scene: `scenes/actors/npc.tscn`.
Tests: `godot --headless --fixed-fps 60 --path . --script res://tests/ai_test.gd`.

- **One Director per pub scene**, in group `director`. It spawns NPCs (named `N<n>`) through its
  own `MultiplayerSpawner` under `actors`, and thinks on the host only.
- **Markers.** Pubs place `Marker3D` nodes in groups `npc_door`, `punter_spot` and `staff_spot`.
- **Kinds:** `second_homer`, `local`, `rugby_lad` (group `npcs`), `police` (`npcs` and `police`),
  `staff` (`staff` only; nobody hits them and the Director ignores any hit on them).
- **Moods:** `Npc.Mood.CALM / ALERT / ENGAGED`. Punters engage only when hit, when a mate nearby is
  hit, in a gang-up, or walking in on a hot fight. They cool off when it goes quiet.
- **Queries other workstreams use:** `director.heat` (0..1, HUD meter),
  `director.punters_left()`. Events emitted: `fight_started`, `reinforcements_arrived`,
  `police_called`, `pub_cleared`, `banner`. `all_players_down` belongs to co-op rules, not the Director.

### Pub chatter

`Chatter` (`scripts/ai/chatter.gd`) is added by the Director as `Director/Chatter` (export
`chatter`, on by default). While the pub is calm, second-homers pair up with someone standing
within `talk_distance` and talk at them. Tests:
`godot --headless --fixed-fps 60 --path . --script res://tests/chatter_test.gd`.

- **Lines** live in `ChatterLines` (`scripts/ai/chatter_lines.gd`): topics with `open`, `reply` and
  `more` lines, plus shared pools (`reply`, `segue`, `close`, `local`, `interrupt`). A local or rugby
  lad who gets cornered only answers from `local`. Add new lines at the end of an array so keys stay stable.
  The joke is always on the speaker, never on whoever they're talking about.
- **When:** only when `director.heat <= quiet_heat` and nobody has been hit for `resume_after`
  seconds. Any hit, `fight_started` or `police_called` ends every conversation, and a talker may
  yelp an `interrupt` line. A talker leaving CALM ends theirs too.
- **Npc hook:** `Npc.chatting_with` makes a calm NPC stop wandering and face its partner.
  `engage()` and `alert()` clear it.
- **Networking:** the host picks speakers and lines and sends `_say` / `_hush` RPCs. Every peer shows
  the bubble (`ChatterBubble`, a Label3D over the head, hidden when `gameplay/subtitles` is off) and
  plays the voice on the `Voice` bus. Cosmetic only.
- **Voice:** a recording at `ChatterLines.voice_path(key)` (e.g.
  `assets/audio/voice/chatter/dogs_open_03.ogg`, shared lines as `shared_<part>_NN.ogg`) wins.
  Otherwise `ChatterVoice` plays a synthesised posh murmur, or the OS text-to-speech voice when
  `voice_mode` is `TTS` and `audio/general/text_to_speech` is enabled. Male or female follows the
  fighter's `voice` property or meta (`"m"` / `"f"`, the FX convention).
  `ChatterLines.all_keys()` lists every line for a recording script.
