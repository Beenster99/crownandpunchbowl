# Development plan

This plan splits the game into workstreams that can run **in parallel**, each in its own
branch and pull request, building on the skeleton in this repo. Conventions and shared
contracts are in [CONVENTIONS.md](CONVENTIONS.md). Design direction is in [DESIGN.md](DESIGN.md).

Engine: **Godot 4.7** (GDScript, Forward+). Placeholder art and audio are fine everywhere until
milestone M4.

## Milestones

| Milestone | Goal | Done when |
| --- | --- | --- |
| **M0: Skeleton** (this PR) | Shared project, folders, data and contracts | Project opens, solo test pub loads, smoke test passes |
| **M1: One good fight** | Solo, greybox Crown and Punchbowl | Punch, kick, headbutt, grab, counter. Weapons and bar healing. Calm-to-hostile AI with waves. Pub can be cleared |
| **M2: Co-op** | 2 to 4 players online (host/join) | Host picks pub and difficulty. Hold-for-a-mate works over the network. Revive downed mates. Move to the next pub together |
| **M3: Four pubs** | Full loop | All 4 pubs with era styling. Police raids. Difficulty fully applied. Settings complete |
| **M4: Blood, beer and polish** | Feel | Real art, impact audio, voice barks, gore, hit-stop, camera feel, balance pass |

## Workstreams

Each workstream lists what it owns, the M1 target, later targets, and what it depends on.
"Owns" means the folders and files where that workstream is the main author. Changes to shared
contracts (`Events`, `GameData`, input action names, the Fighter API) go in their own small PR
so the other threads can see them.

### 1. Combat core and freeflow
- **Owns:** `scripts/combat/`, `scripts/actors/` (Fighter base class and player fighter), `scenes/actors/player.tscn`
- **M1:** Fighter base class (health, states: idle/attack/stagger/down/crawl/KO/held/grabbing).
  Punch combos, kick, headbutt. Target selection with a short lunge to the nearest enemy in the
  stick direction (freeflow feel). Counter window on enemy tells. Dodge. Grab and hold: held
  enemies take bonus damage from everyone. Combo counter and finishers. Hit reactions, knockdown,
  crawl when nearly out, KO.
- **Later:** per-farmer traits (iron forehead, vice grip, drunken master…), tag-team moves on a held enemy.
- **Depends on:** nothing. The other workstreams code against its Fighter API, so it publishes
  that API first (see CONVENTIONS.md).

### 2. Enemy AI, director, waves and police
- **Owns:** `scripts/ai/`, NPC actor scenes
- **M1:** Punter types (weak second-homers, locals, tough rugby lads). Calm/alert/engaged states.
  Punters only engage if attacked or a mate nearby is hit. Heat-driven attack tokens. Circling while
  waiting. Gang-up rushes. New arrivals through the door during the fight. Bar staff are never
  hostile and can't be knocked out (hitting them gets you refused service). Win condition:
  everyone except staff knocked out.
- **M3:** Police raid (whistle, arrive at the door, tougher, batons).
- **Depends on:** Fighter API (1). Reads difficulty from `GameData`.

### 3. Networking and co-op
- **Owns:** `scripts/net/`, `scripts/autoload/net.gd`
- **M2:** Host/join over ENet. Lobby state (names, farmer choice, ready). Host picks the starting
  pub and difficulty. Host-authoritative simulation: clients own their own movement and send
  actions as RPCs. MultiplayerSpawner/Synchronizer for actors and items. Synced pub-to-pub
  transitions. Downed and revive rules. Handling a player who drops out. Solo keeps the same
  code paths via OfflineMultiplayerPeer.
- **Depends on:** 1 and 2 using the authority rules in CONVENTIONS.md from day one. Before M2
  it can start on lobby and transport in parallel.

### 4. Pubs and levels
- **Owns:** `scenes/pubs/`, `scripts/level/`, `assets/models/pubs/`
- **M1:** Greybox Crown and Punchbowl. Bar, tables, fireplace, dartboard, pool table, door
  spawn, staff area. Fade walls that block the camera. Level script for start, cleared, and
  next pub.
- **M3:** King William (18th c.), Farmers Dog (19th c.), Pillock Tickle (17th c.) with
  era-specific dressing and lighting.
- **Depends on:** camera script (here). Prop spawn points are shared with workstream 5.

### 5. Weapons, items and the bar
- **Owns:** `scripts/items/`, `scenes/items/`
- **M1:** Pick up, swing, throw and break: bottles (break into a broken bottle), glasses,
  chairs (break into chair legs), stools, table legs, pool cues, darts (thrown), fireplace
  tools. Ordering at the bar: a pint is a quick small heal and makes you tipsy, food is a slower
  big heal. Pints and plates on tables can be picked up and consumed.
- **Depends on:** Fighter API (1). Prop placement from 4.

### 6. Audio, gore and game feel
- **Owns:** `scripts/fx/`, `assets/audio/`
- **M1 (placeholder):** Sound player with buses (SFX/Voice/Music) and random pitch. Impact
  sounds (bare-knuckle, kick, headbutt crack, glass, wood). Voice "oofs", groans and moans
  from crawling punters. Blood particles, a burst for broken noses, floor decals, bloody faces
  when nearly out. Hit-stop and camera shake. Respects the Blood and Camera Shake settings.
- **M4:** Real recorded or sourced audio, pub ambience and music.
- **Depends on:** listens to `Events` only. Can start now with test triggers.

### 7. Menus, settings, HUD and difficulty
- **Owns:** `scripts/ui/`, `scenes/ui/`, `scenes/main/`, `scripts/autoload/settings.gd`
- **M1:** Main menu. Farmer select (6 cards with stats and trait). Pub and difficulty pick.
  Settings screens: **Gameplay, Sound, Graphics, Keybinds** with separate keyboard/mouse and
  controller columns, rebinding and reset to defaults. Pause menu. HUD (player health bars,
  tipsy meter, combo, punters left, heat meter, banners, context prompts like "E: Order pint").
- **M2:** Lobby UI on top of workstream 3.
- **Depends on:** `Settings` and `GameData` (here). The HUD reads `Events`.

### 8. Characters and animation
- **Owns:** `assets/models/characters/`, character look data
- **M1:** One shared humanoid rig with placeholder animations: idle, walk, punch L/R, kick,
  headbutt, grab/hold, held struggle, hit reacts, knockdown, crawl, KO, drink.
- **M3/M4:** 6 distinct farmers (5 men, 1 woman; different builds, clothes and hats) and
  punter types (gilets and chinos for second-homers, rugby shirts, police). Low-poly
  stylised as per DESIGN.md.
- **Depends on:** state names from 1 so animations map one to one.

## Order and parallelism

```
M0 skeleton ──┬─ 1 Combat ──────┬─ 2 AI/director ─┐
              ├─ 6 Audio/gore   ├─ 5 Items/bar ───┼─ M1 one good fight ── 3 Co-op ── M2 ── 4 Pubs ×4 ── M3 ── polish ── M4
              ├─ 7 Menus/settings                 │
              ├─ 4 Greybox pub ───────────────────┘
              ├─ 3 Lobby/transport (early)
              └─ 8 Rig/anims
```

Workstreams 1, 4, 6, 7 and 8 can start immediately. 2 and 5 start once the Fighter API PR
from 1 lands (expected to be its first small PR). 3 can start on lobby and transport straight
away and integrates at M2.

## Open questions for the owner
- Does hitting the bar staff have a consequence beyond being refused service?
- Is local couch co-op (shared screen) wanted as well as online? The camera supports both.
  Input per device is the extra work.
- Pillock Tickle's era: the brief lists three eras for four pubs. The plan assumes a second
  17th-century pub. Should it be different?
