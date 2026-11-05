# Weapons, items and the bar

Workstream 5. Code in `scripts/items/`, tests in `tests/items_test.gd`
(`godot --headless --path . --script res://tests/items_test.gd`).

## Pieces

| Script | What it does |
| --- | --- |
| `item_data.gd` (`ItemData`) | Every item kind and its numbers, plus bar, drink and tipsy tuning |
| `pub_item.gd` (`PubItem`) | One pickup. Weapon hooks for `Fighter.equip()`, throwing, breaking, consuming |
| `pub_items.gd` (`PubItems`) | One per pub. Spawns items with names `I<n>` on every peer and gives every Fighter a `Hands` node |
| `hands.gd` (`Hands`) | A fighter's hands: pick up, throw, drop, drink, eat, order. Owns the tipsy effect |
| `bar.gd` (`Bar`) | A counter you can order at. Orders are served onto the counter top |

## Setting up a pub

```gdscript
func _ready() -> void:
	var items := PubItems.install(self)          # goes under $Items if there is one
	items.add_item(&"bottle", Vector3(-4, 0.8, 0))  # same order on every peer
```

Drop a `Bar` node in the pub with its origin on the floor at the middle of the counter. The
counter runs along local X and customers stand on the local +Z side. Set `length`, `depth` and
`top_height` to match the mesh. `PubItems.furnish_test_pub()` shows a full set for the greybox pub.

## Controls

| Action | Does |
| --- | --- |
| `interact` | Pick up the nearest item (swaps with what you hold), or drink/eat it if it's a pint or food. At the bar with nothing in reach, order a pint. Otherwise drop what you hold |
| `order_food` | Order food at the bar |
| `throw` | Throw what you hold at the enemy you're facing. Darts go one at a time. Does nothing while you're holding a person, so the combat controller can use it to throw them |

Punches (and enemy `swing`, `haymaker`, `baton`, plus `counter`) use the held weapon. Kicks,
headbutts, stomps and knees stay bare-knuckle. `Hands.interact_hint()` returns `pick_up`,
`drink`, `eat`, `order`, `drop` or `""` for HUD prompts.

## Items

| Item | Swing | Breaks into | Thrown |
| --- | --- | --- | --- |
| Bottle | 1.5x, to the face, breaks on the first hit | Broken bottle (sharp) | Smashes |
| Pint glass | 1.45x, to the face, breaks on the first hit | Shards | Smashes |
| Chair | 2x, two-handed, wide sweep, knocks down, slows you | 2 chair legs | Knocks down |
| Bar stool | 1.8x, two-handed sweep | Chair leg | Knocks down |
| Chair / table leg | 1.35x / 1.6x, longer reach | Splinters after 6 / 8 hits | Lands on the floor |
| Pool cue | 1.25x, very long sweeping reach | Snapped cue (sharp) | Lands |
| Darts | Weak stab | | Three per set, thrown one at a time, stick in |
| Fire poker, coal shovel | 1.7x / 1.6x, heavy, never break | | Lands |
| Pint | Drink: +12 hp, +0.2 tipsy, leaves an empty pint glass in your hand | | |
| Pie and chips | Eat: +40 hp over 6 seconds | | |

A fighter who is knocked down, held or KO'd drops what they're holding.

## The bar and drinking

- Pints take 1.2 s to pour and food 4 s, then appear on the counter in front of whoever ordered.
  Anyone can take them. One order at a time each.
- Nobody hits the bar staff: thrown items fly straight past them, and the bar always serves.
- **Tipsy** (`Fighter.tipsy`, 0 to 1) wears off at 0.008 a second. At full tipsy: +15% damage,
  +25% toughness, -15% speed, and you sway off your line.
- Traits: Barrow (`seasoned_drinker`) gets double from ale, Dicky (`drunken_master`) gets +45%
  damage at full tipsy, and Kev's (`handyman`) weapons last 1.5x longer. The trait is read from
  the player's `farmer_index` or a `trait` meta on any Fighter.

## For other workstreams

- **AI**: NPCs get `Hands` too. On the host call `Hands.of(npc).request_interact()`,
  `request_throw_item()` or `request_order(&"pint")`. `PubItems.nearest_item(node, pos, range)`
  finds things to grab.
- **Gore and audio**: a hit's `info["weapon"]` is the `PubItem` (`kind`, `sharp`). Thrown hits
  have `move` = `throw_<kind>` and `thrown: true`. `Events.item_broken` fires when glass smashes
  or furniture splinters, and `Events.item_picked_up` on pick-ups.
- **Networking**: the host decides every pick-up, throw, hit and break and replicates it with
  RPCs on the item. Items never change parent, so their paths match on every peer. Thrown
  items fly on every peer from the same start; only the host checks what they hit.
