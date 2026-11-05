# Characters and animation

Workstream 8. Every person in the game (six farmers, the punters, the police and the bar
staff) is a **rigged, skinned model** built in Blender on **one shared armature**, driven by
`CharacterRig` and dressed from a **look** (`CharacterLook`, data in `CharacterLooks`).
The rig retargets the full animation set onto each model's skeleton, and knockouts hand
over to a **physics ragdoll**.

![Line-up](images/characters_lineup.jpg)

Open `scenes/actors/character_lineup.tscn` and press F6 to see everyone. Left/Right cycles the
animation, B toggles blood, C switches to the in-game camera angle, K knocks everyone out
into ragdolls.

## How the models are made

`tools/blender/build_characters.py` builds every model from the look data. No hand-made art
files are needed, and changing a look and rebuilding takes about a minute for all 15.

- **Bodies** are a quick procedural sculpt: ellipsoids and capsules for the torso, belly,
  limbs and fists are voxel-remeshed into one watertight surface, smoothed so the joins
  fillet, and decimated. Each body part is remeshed separately so an arm never welds to
  the torso, and the part is remembered per vertex so skin weights never bleed across.
- **Heads** are sculpted the same way (cranium, jaw, brow ridge, cheeks, chin) with a
  separate nose on its own bone, ears, lips, eyebrows and eyes.
- **Clothes, hair and beards** are shells grown off the body or head surface (gilets,
  waistcoats, bibs, braces, hi-vis, collars, cuffs, pockets, hair caps, beards and stubble),
  with hems relaxed so cut edges read as seams. Hats are small modelled pieces.
- **Colours** come from named materials (`skin`, `top`, `trousers`, `over`, `hat`...).
  Godot recolours them from the look, so one model serves a whole crowd type. Shirts get a
  check pattern mapped triplanar, so the models need no UVs.
- **Variants**: optional pieces are separate meshes called `Hair_<STYLE>`, `Beard_<STYLE>`,
  `Hat_<STYLE>` and `Top_<TYPE>`. Each crowd model carries every piece its type can roll,
  and Godot shows the ones that match. `Blood_*` meshes appear as a fighter gets hurt.
- **Armature**: `Hips`, `Spine`, `Chest`, `Neck`, `Head`, `Nose`, `Shoulder/Elbow/Hand` and
  `Hip/Knee/Foot` with L and R. All models share these names.

Rebuild after changing `CharacterLooks`:

```
godot --headless --path . --script res://tools/export_looks.gd      # looks -> looks.json
blender -b -P tools/blender/build_characters.py                      # all models (Blender 4.5)
blender -b -P tools/blender/build_characters.py -- --blend tom gaz   # some, plus .blend files
godot --headless --path . --import                                   # reimport the .glb files
```

`--blend` also saves `tools/blender/out/<id>.blend` (not committed) so you can open a model,
tweak it or hand-sculpt over it. A hand-made model works as long as it keeps the bone names,
the material names and the piece names above. `tools/blender/preview.py` renders .blend files
with Cycles for a quick look without Godot.

## The six farmers

Ids match `GameData.FARMERS`. Each silhouette is meant to read from the high camera: you can
tell them apart by height, width, posture and hat.

| Id | Farmer | Look | How the trait shows |
| --- | --- | --- | --- |
| `tom` | Tom "Muckspreader" Pryce | The giant. Shaved head, stubble, rolled-sleeve boiler suit, rigger boots | Huge head and heavy brow ridge (iron forehead) |
| `gaz` | Gaz Whitlock | The whippet. Thin, long arms, ginger mop and goatee, orange beanie, ripped fleece | Long limbs for quick flurries |
| `barrow` | Old Man Barrow | Bent old boy. Tweed flat cap, white mutton chops, wax jacket, waistcoat, mustard cords, neckerchief | Stoop, and a big plum-red drinker's nose |
| `mags` | Margaret "Mags" Fenwick | Sturdy dairy farmer. Auburn bun, red check shirt, navy quilted gilet, green wellies | The biggest hands for her size (vice grip) |
| `dicky` | Dicky Thresher | The drunk. Battered trilby, comb-over, cream shirt, braces over a full ale belly | Sways on his feet all the time (drunken master) |
| `kev` | Kev Haybale | The handyman. Full black beard, red cap, bib-and-brace overalls, tool belt with a hammer | Tool belt (handyman) |

## Punters, police and staff

Looks only. How tough each type is belongs to the AI workstream.

| Id | Who |
| --- | --- |
| `second_homer_gilet` | Navy gilet, pale shirt, stone chinos, loafers |
| `second_homer_chinos` | Red trousers, jumper over a collar, floppy hair |
| `rambler` | Cagoule, bobble hat, walking shorts, glasses |
| `local` | Hoodie, jumper or fleece, jeans, trainers. The most varied type |
| `rugby_lad` | Big shoulders, hooped rugby shirt, thick neck |
| `constable` | Custodian helmet, black jacket, hi-vis vest |
| `sergeant` | Peaked cap, sleeve stripes, moustache, bigger build |
| `barman`, `barwoman` | White or black shirt with apron or waistcoat |

Crowds should never be clones, so `CharacterLooks.punter(type, seed)`, `police(type, seed)`
and `staff(type, seed)` vary skin tone, hair, build and clothing colours. **The same type and
seed always give the same person**, so use a seed every peer agrees on, such as the number in
the NPC's node name (`N12` → 12). That keeps a punter looking the same on every machine
without syncing their look.

## Using the rig

```gdscript
var rig := CharacterRig.new()
rig.look = CharacterLooks.farmer("mags")       # or rig.look_id = "rugby_lad"; rig.look_seed = 12
add_child(rig)

rig.set_move_speed(velocity.length())          # every frame: switches idle and walk
rig.set_guard(mood != Npc.Mood.CALM)           # fists up only when there's trouble
rig.set_talking(chatting_with != null)         # calm chatters gesture
rig.staff = true                               # before add_child: bar staff polish glasses
rig.play_move("punch")                         # alternates left and right
rig.play_state(Fighter.State.keys()[state])    # "STAGGER", "KO", "HELD"...
rig.play_hit(from_front, heavy)
rig.get_socket(&"hand_r").add_child(bottle)    # weapons, pints
rig.play_hit(true, false, hit_direction)       # remembers the direction for a ragdoll
rig.play_state("KO")                           # goes ragdoll, thrown along hit_direction
rig.start_ragdoll(impulse)                     # or do it yourself, any time
rig.ragdoll_hips_position()                    # where the body landed (for get-up / revive)
rig.set_blood(0.7)                             # cosmetic, 0 to 1
rig.break_nose()                               # hook to Events.nose_broken
rig.animation_finished.connect(...)            # e.g. to time the hit frame
```

### Calm and guarded

People start relaxed. Standing still, a calm character plays one of the calm idles
(`idle_relaxed` with weight shifts, or `idle_pint` with a sip now and then, picked from
`look_seed`), `idle_chat` while talking, or `idle_polish` for staff. Walking calm is
`walk_relaxed`. Only with the guard up do they play the fists-up `idle` and `walk`.
Any move or hit raises the guard on its own; `set_guard(false)` drops it again.

`FighterVisual` drives this for you: NPCs follow their AI mood (CALM is relaxed, ALERT and
ENGAGED are guarded; mood is synced so clients match), staff never square up, and players
keep their guard up for 6 s after a swing or hit, or while a riled-up NPC is within 4.5 m.
Every standing loop starts at a random point so a room doesn't move in step.

The rig is a `@tool` script, so you can drop a `CharacterRig` node into any scene, set
`look_id`, and see the character in the editor.

### Ragdoll

Each rig builds a `PhysicalBoneSimulator3D` with capsule bodies and cone joints for the hips,
spine, chest, head, arms and legs. `play_state("KO")` switches to it (turn off with
`ragdoll_on_ko`), and any later `play()` or `play_state()` switches back to animation.

- Ragdolls are **cosmetic**: every peer runs its own, so they never decide gameplay. The
  fighter's own body and KO state stay host-authoritative as usual.
- They sit on physics layer 7 (`ragdoll`) and only collide with the world (layer 1), so
  bodies don't trip the living or pile up on each other.
- When a downed fighter gets up or is revived, move the fighter to `ragdoll_hips_position()`
  first, then play `get_up`.

### Contract

These names are the contract with gameplay. Real art must keep them.

- **Facing** is -Z. The origin is on the floor between the feet. 1.0 scale is about 1.78 m.
- **Animations** (`CharacterRig.ANIMATIONS`): `idle`, `walk`, `idle_relaxed`, `idle_pint`,
  `idle_chat`, `idle_polish`, `walk_relaxed`, `punch_l`, `punch_r`, `kick`,
  `headbutt`, `windup`, `swing`, `throw`, `grab`, `hold`, `held_struggle`, `hit_front`,
  `hit_back`, `stagger`, `knockdown`, `down`, `get_up`, `crawl`, `ko`, `drink`, `eat`,
  `dodge`, `cheer`, `taunt`.
- **Fighter states** map one to one (`CharacterRig.STATE_ANIMS`):

  | State | Animation | Notes |
  | --- | --- | --- |
  | IDLE | a calm idle, `idle` or a walk | Picked from `set_move_speed`, guard, talking and staff |
  | ATTACK | `punch_r` | Use `play_move()` for the actual move |
  | WINDUP | `windup` | The big telegraphed haymaker. Holds on the last frame. Counter window |
  | STAGGER | `stagger` | |
  | DOWN | `knockdown` then `down` | Lying on the back, groggy |
  | CRAWL | `crawl` | Face down, dragging along. Pair with moaning |
  | KO | `ko` | Falls and lies still |
  | HELD | `held_struggle` | Arms pinned, kicking |
  | GRABBING | `grab` then `hold` | |
  | DODGE | `dodge` | Duck and weave |

- **Moves** (`CharacterRig.MOVE_ANIMS`): every move id in `scripts/combat/moves.gd` (jab, cross,
  hook, uppercut, haymaker, kick, knee, stomp, headbutt, counter, shove, throw, swing, baton)
  maps to an animation. Until there are dedicated ones, several share the nearest animation.
- **Chains**: `knockdown` → `down`, `grab` → `hold`. Attacks, hit reacts, `get_up`,
  `drink`, `eat`, `cheer` and `taunt` return to idle (turn off with `auto_return_to_idle`).
- **Sockets** (`get_socket`): `hand_r`, `hand_l`, `head`, `chest`, `hold_point` (where a
  held enemy goes, in front of the chest).

### Timings (placeholder)

| Animation | Length | Contact frame |
| --- | --- | --- |
| `punch_l` / `punch_r` | 0.42 s | 0.16 s |
| `kick` | 0.6 s | 0.22 s |
| `headbutt` | 0.55 s | 0.25 s |
| `swing` | 0.7 s | 0.33 s |
| `throw` | 0.6 s | release at 0.3 s |
| `windup` | 0.5 s | holds |
| `drink` / `eat` | 1.6 s | heal at about 1.1 s |

Combat owns the real timing. If it needs different numbers, change the keys in
`CharacterRig._anim_defs()` and update this table.

## How the animations work

The 25 animations are pose data in `CharacterRig._anim_defs()` (joint rotations in the
character's own axes). At load time they are retargeted onto each model's skeleton:
a bone's pose rotation is `rest_local * (M⁻¹ q M)`, where M is the bone's rest orientation.
That means one set of animation data drives every model, whatever its proportions. A
hand-keyed Blender action could later replace any of them by name.

## Performance

Models are 25k to 48k triangles with every variant included (only the shown pieces draw),
and Godot generates LODs on import, so a crowd in the high camera draws far fewer. The 15
`.glb` files are about 23 MB in the repo.

## Tests and tools

- `godot --headless --path . --script res://tests/character_test.gd` (after `--import`) builds
  every look, plays every animation, and checks sockets, state mapping, crowd variation,
  that the floor animations really are on the floor, and that a KO ragdoll falls the way it
  was hit and hands back to animation. The headless dummy renderer prints a few harmless
  `Parameter "material" is null` lines.
- `xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_characters.gd -- <dir>`
  renders the line-up to PNGs, which is how the images in this file were made.

![Actions: punch, headbutt, kick, drink](images/characters_actions.jpg)

![On the floor: crawling with blood, then everyone knocked out into ragdolls](images/characters_floor.jpg)
