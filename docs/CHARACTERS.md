# Characters and animation

Workstream 8. Every person in the game (six farmers, the punters, the police and the bar
staff) is **one shared rig** (`CharacterRig`) wearing a different **look** (`CharacterLook`).
Looks are data in `CharacterLooks`. The rig builds a chunky low-poly body out of primitives
and carries the full placeholder animation set, so gameplay can use real-looking characters
now and swap in real art later without code changes.

![Line-up](images/characters_lineup.jpg)

Open `scenes/actors/character_lineup.tscn` and press F6 to see everyone. Left/Right cycles the
animation, B toggles blood, C switches to the in-game camera angle.

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
rig.play_move("punch")                         # alternates left and right
rig.play_state(Fighter.State.keys()[state])    # "STAGGER", "KO", "HELD"...
rig.play_hit(from_front, heavy)
rig.get_socket(&"hand_r").add_child(bottle)    # weapons, pints
rig.set_blood(0.7)                             # cosmetic, 0 to 1
rig.break_nose()                               # hook to Events.nose_broken
rig.animation_finished.connect(...)            # e.g. to time the hit frame
```

The rig is a `@tool` script, so you can drop a `CharacterRig` node into any scene, set
`look_id`, and see the character in the editor.

### Contract

These names are the contract with gameplay. Real art must keep them.

- **Facing** is -Z. The origin is on the floor between the feet. 1.0 scale is about 1.78 m.
- **Animations** (`CharacterRig.ANIMATIONS`): `idle`, `walk`, `punch_l`, `punch_r`, `kick`,
  `headbutt`, `windup`, `swing`, `throw`, `grab`, `hold`, `held_struggle`, `hit_front`,
  `hit_back`, `stagger`, `knockdown`, `down`, `get_up`, `crawl`, `ko`, `drink`, `eat`,
  `dodge`, `cheer`, `taunt`.
- **Fighter states** map one to one (`CharacterRig.STATE_ANIMS`):

  | State | Animation | Notes |
  | --- | --- | --- |
  | IDLE | `idle` or `walk` | Picked from `set_move_speed` |
  | ATTACK | `punch_r` | Use `play_move()` for the actual move |
  | WINDUP | `windup` | The big telegraphed haymaker. Holds on the last frame. Counter window |
  | STAGGER | `stagger` | |
  | DOWN | `knockdown` then `down` | Lying on the back, groggy |
  | CRAWL | `crawl` | Face down, dragging along. Pair with moaning |
  | KO | `ko` | Falls and lies still |
  | HELD | `held_struggle` | Arms pinned, kicking |
  | GRABBING | `grab` then `hold` | |
  | DODGE | `dodge` | Duck and weave |

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

## Swapping in real art (M3/M4)

The plan is one humanoid skinned mesh in Blender, exported as glTF to
`assets/models/characters/`, with all animations above on one shared armature. Clothes, hair
and hats are separate meshes switched on per look, and colours come from the look. Put
`BoneAttachment3D` nodes on the hand, head and chest bones with the socket names above.
Then `CharacterRig` builds the imported scene instead of the primitives, and everything
that calls the API keeps working.

## Performance note

Each placeholder character is about 80 small meshes. That is fine for greybox fights of
20 to 30 people. If it becomes a problem before real art lands, merge each character's static
meshes per joint.

## Tests and tools

- `godot --headless --path . --script res://tests/character_test.gd` builds every look,
  plays every animation, and checks sockets, state mapping, crowd variation, and that the
  floor animations really are on the floor.
- `xvfb-run godot --path . --rendering-driver opengl3 --script res://tools/capture_characters.gd -- <dir>`
  renders the line-up to PNGs, which is how the images in this file were made.

![Actions: punch, headbutt, kick, drink](images/characters_actions.jpg)

![On the floor: crawl with blood, then KO from the game camera](images/characters_floor.jpg)
