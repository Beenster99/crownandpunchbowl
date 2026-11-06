# Crown and Punchbowl

A co-op pub brawler (1 to 4 players) set in a rural English village, built with **Godot 4.7**.
Pick one of six farmers, walk into one of four village pubs, stay civilised for a minute,
then knock out everyone in the building except the bar staff.

- Design direction and camera/graphics recommendation: [docs/DESIGN.md](docs/DESIGN.md)
- Development plan and workstreams: [docs/PLAN.md](docs/PLAN.md)
- Folder layout and shared contracts: [docs/CONVENTIONS.md](docs/CONVENTIONS.md)
- The six farmers, punters, police and the shared rig: [docs/CHARACTERS.md](docs/CHARACTERS.md)
- The four pubs, pub flow and level markers: [docs/PUBS.md](docs/PUBS.md)

## Running

Open the folder in Godot 4.7 and press Play. From the main menu, **Play solo** takes you to
farmer select, where you also pick the starting pub and difficulty. **Settings** has Gameplay,
Sound, Graphics and Keybinds (keyboard/mouse and controller, click a binding to change it).
In the pub, move with WASD or the left stick. Esc or Start opens the pause menu. Zoom the
camera with the mouse wheel, + and -, or D-pad up and down (hold to keep zooming); the zoom is
remembered. **Players can hit each other** (friendly fire, under Gameplay and in the lobby) is
the host's choice and applies to everyone; nobody can hit the bar staff either way.

## Tests

```
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --import   # once, so the character models are imported
godot --headless --path . --script res://tests/ui_test.gd
godot --headless --path . --script res://tests/coop_rules_test.gd
tests/run_net_test.sh   # two-process host + client co-op test
godot --headless --path . --script res://tests/character_test.gd
godot --headless --path . --script res://tests/pubs_test.gd
godot --headless --path . --script res://tests/items_test.gd
```

Co-op: Host co-op / Join co-op on the main menu. See [docs/NETWORKING.md](docs/NETWORKING.md).

The current state is the M0 skeleton: shared data, settings and keybind storage, a placeholder
player, and the recommended camera. Gameplay comes in through the workstreams in the plan.
