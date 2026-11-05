# Crown and Punchbowl: design direction

## The pitch

A co-op pub brawler for 1 to 4 players. A rural English village has been bought up by
second-home owners who never turn up and never put anything back in. The farmers have had
enough. Pick one of six farmers, walk into one of four village pubs, be perfectly civilised
for about ninety seconds, then knock out everyone in the building except the bar staff.
Clear the pub and the whole group moves on to the next one.

Combat takes its cue from freeflow brawlers: linked attacks, counters on a tell, and
moving smoothly between targets. Two things change it here. First, it is co-op, so players
hold enemies for each other. Second, the pace is not frantic. Punters mostly mind their own
business until you start something, so the players decide how hot the room gets.

## Recommendation: camera and graphics

**Go full 3D with a fixed-angle, high three-quarter camera** (about 55° pitch, perspective
lens, no player camera rotation). That means 3D characters and pubs, viewed from a slightly
raised corner like a stage. This is not true isometric.

Why this over the alternatives:

| Option | Verdict |
| --- | --- |
| **Fixed-angle 3D (recommended)** | Every player shares one readable view of the room. Grabs, throws, ragdolls, flying chairs and blood on the floor all just work in 3D physics. One camera works for both online and couch co-op. Godot 4 handles it well. |
| Over-the-shoulder 3D (freeflow style) | Great for one player. In co-op, each player needs their own camera (or split screen), and the camera fights the cramped pub rooms. That costs a lot more animation and camera work. |
| True isometric 2D / 2.5D sprites | Charming, but every move, weapon and knockdown needs hand-drawn frames in 4 to 8 directions. Grab-and-hold, thrown furniture and crawling bodies get very expensive. Depth sorting in a crowded pub is fiddly. |
| Side-scrolling 2D (classic beat 'em up) | Loses the "whole room kicking off" feel, and pubs aren't corridors. |

How the camera behaves:
- It frames **all** players and pulls back as they spread out, with soft limits.
  Pubs are small enough that this rarely needs to go far. `scripts/level/brawl_camera.gd`
  is the starting point.
- Movement is camera-relative and the camera never yaws, so "up" is always "up the screen".
  This keeps controller and keyboard play simple.
- In online play each machine runs its own copy of the shared-framing camera. If local
  split screen is wanted later, the same script runs once per viewport.
- Walls and beams nearest the camera fade or cut away so the fight is never hidden.

### Art style

**Chunky, stylised low-poly characters with warm, smoky lighting.** Think slightly
exaggerated proportions: big hands, big heads, ruddy faces. Use hand-painted or flat-colour
textures. Why:
- A small team can produce it. Six farmers and about eight punter types can share one
  rig and one animation set.
- It keeps the violence funny rather than grim, while still showing broken noses, blood
  spray, floor smears and bloody faces when someone is down.
- Each of the three periods can be shown through set dressing and lighting rather than detail:
  - **17th century**: low dark oak beams, inglenook fireplace, flagstones, candle and fire light.
  - **18th century**: Georgian panelling, sash windows, brighter painted walls, brass.
  - **19th century**: Victorian tiles, etched glass, gas lamps, a big carved back bar.

Placeholder phase: capsules and boxes with flat colours (already in the skeleton), then
greybox pubs, then real art. The art direction should never block gameplay work.

### Pacing: "the room has a temperature"

The AI director keeps a **heat** value that rises as players fight and drops when they
stop. Heat controls how many punters may attack at once (attack tokens). Calm punters keep
drinking and only fight back if hit or if a mate nearby is hit. When the heat is high, groups
organise and rush a single player, and eventually someone calls the police. Players who want
a slow, tactical fight get one. Players who kick off everywhere get a crowd.
