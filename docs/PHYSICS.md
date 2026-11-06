# Pub physics and ragdolls

Everything loose in a pub is a physics body, and anyone knocked down goes ragdoll. Fights
should leave the room wrecked: chairs scattered, tables on their sides, glass everywhere,
bottles off the back bar, and bodies draped over the bar.

It runs on Godot Physics. Jolt also passes every test and handles big piles of bodies better,
but it logs an error for each ragdoll bone because the character models are scaled
non-uniformly (girth), so it stays off until the rig scales uniformly.

Tests: `godot --headless --fixed-fps 60 --path . --script res://tests/physics_test.gd`

## Pieces

| Script | What it does |
| --- | --- |
| `scripts/physics/pub_physics.gd` (`PubPhysics`) | One per pub (PubLevel adds it). Helpers to make props, `disturb()` and `shove()`, smashing glass, and host-to-client sync of every prop |
| `scripts/physics/body_impacts.gd` (`BodyImpacts`) | One per Fighter ("Impacts"). Fighters barge props, fly into them, go over the bar, and knock pinned things off the walls |
| `scripts/actors/ragdoll_driver.gd` (`RagdollDriver`) | One per rig (FighterVisual adds it). Knockdowns and KOs go ragdoll, tethered to the fighter, and blend back into the get-up |

## Props

A prop is a `RigidBody3D` in the `pub_props` group, set up with `PubPhysics.setup_prop(body, mass, blocks, fragile, pinned)`
(or `PubPhysics.make_prop(...)` / `PubBuilder.loose_cylinder(...)`). Spawn props on every peer in the
same order with readable names: they're synced by node path.

| Flag / meta | Effect |
| --- | --- |
| `blocks` | Also on the world layer, so fighters bump into it (tables, barrels, the piano). Without it fighters wade through and shove it aside (chairs, glasses) |
| `fragile` | Smashes when its speed changes by `SMASH_DV` (3.2 m/s) in one tick, e.g. knocked off a table. `Events.prop_smashed(prop)` fires, then it's freed |
| `pinned` | Frozen in place (on a shelf or wall) until `PubPhysics.disturb()` knocks it loose |

Props sleep until disturbed, so a quiet pub costs nothing.

What's physical today: every PubItem lying loose (bottles, glasses, pints, plates, food, chairs,
stools, cues, legs, darts, fire irons), the tables, barrels, pool balls and every bottle on the back
bar shelves. The props workstream adds decor (pictures, piano, coat stands, ashtrays...) through the
same helpers. The bar counter, back bar, pool table, settles, fireplaces and walls stay fixed.

### Layers

| Layer | Value | Who |
| --- | --- | --- |
| 1 world | 1 | Room, bar, plus props that block (tables, barrels) |
| 4 items | 8 | Optional for small loose things |
| 7 ragdoll | 64 | Rig physical bones. Collide with world, items and props |
| 8 props | 128 | Every prop |

Props collide with `PROP_MASK` (world, items, props). Fighters (mask 7) don't collide with layer 8,
so they never snag on a chair. BodyImpacts shoves what they pass through instead.

### PubItems

Each PubItem has a top-level `body` (RigidBody3D). While the item is loose the host simulates it
and the item rides on it; held, flying or gone, the body is frozen inside the item with its collision
off. A thrown item keeps some of its speed when it lands and tumbles on. The collision box is
the size of the item's visuals, so a model from the props library gets a matching box.

### Network

The host simulates every prop. About 20 times a second it sends the pose of each prop that's moving
(plus one last pose when it falls asleep) with an unreliable RPC; clients freeze their props and glide
to those poses. Clients' fighters send their shoves and slams to the host. Smashes are a reliable RPC.

## Bodies meeting the pub

`BodyImpacts.after_move()` runs after every `move_and_slide()` on the fighter's authority:

- **Walking** into or through props pushes them with a share of your speed (`WALK_PUSH`), less for
  heavy things. Standing still never nudges anything, so seated punters leave their chairs alone.
- **Flying** (knocked down, or carried by a hit faster than `FLYING_SPEED`) pushes much harder
  (`FLY_PUSH`) and lifts, so chairs cartwheel and tables tip over.
- **Over the top**: knocked down and carried at `VAULT_SPEED` (5.5 m/s) or more into anything
  whose top is 0.3 to 1.35 m above the feet (the bar, a table, the pool table, a railing), the
  fighter is launched over it and their ragdoll flips head first down the far side.
  `Events.fighter_flipped_over(fighter, obstacle)` fires on every peer.
- **Slams** into walls and anything taller at `SLAM_SPEED` (3.5 m/s) call `PubPhysics.disturb()`
  at the impact: pictures and shelf bottles nearby come down.

For combat: a move meant to send someone over the bar (shoulder charge, throws) needs a knockback of
at least `BodyImpacts.VAULT_SPEED` after the victim's toughness, with `knockdown`.

## Ragdolls

`RagdollDriver` hands the rig to physics on **DOWN** and **KO** (not only KO), starting every bone
with the fighter's own velocity plus a kick from the blow: at the head for face shots, the chest
otherwise, bigger for heavy hits and big knockback. Ground hits shove the limp body about.

Each peer runs its own ragdoll, so the hips are tethered to the fighter's capsule with a soft spring
(0.3 m of slack): the body lies however it fell but always ends up where gameplay thinks it is.
If it gets more than 3.5 m away it's reset onto the capsule.

Getting up blends out of the ragdoll over 0.45 s into the `get_up` animation
(`CharacterRig.stop_ragdoll(blend)`), so they rise from however they landed.
