# Crown and Punchbowl

A co-op pub brawler (1 to 4 players) set in a rural English village, built with **Godot 4.7**.
Pick one of six farmers, walk into one of four village pubs, stay civilised for a minute,
then knock out everyone in the building except the bar staff.

- Design direction and camera/graphics recommendation: [docs/DESIGN.md](docs/DESIGN.md)
- Development plan and workstreams: [docs/PLAN.md](docs/PLAN.md)
- Folder layout and shared contracts: [docs/CONVENTIONS.md](docs/CONVENTIONS.md)
- The six farmers, punters, police and the shared rig: [docs/CHARACTERS.md](docs/CHARACTERS.md)

## Running

Open the folder in Godot 4.7 and press Play. The main menu lets you pick a pub and difficulty
and start a solo session in the greybox test pub. Move with WASD or the left stick. Press Esc
to go back to the menu.

## Tests

```
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --import   # once, so the character models are imported
godot --headless --path . --script res://tests/character_test.gd
```

The current state is the M0 skeleton: shared data, settings and keybind storage, a placeholder
player, and the recommended camera. Gameplay comes in through the workstreams in the plan.
