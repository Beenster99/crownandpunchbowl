# Darts (501 and 301)

Every dartboard in every pub is playable, solo or with mates online.

## Playing

1. Walk up to the oche (the brass line 2.37 m from the board) and press **interact** (E / RT).
   A prompt over the oche says when you're close enough. You're chalked up and the darts
   screen opens; your fight and item controls are off while it's open.
2. Up to four can chalk up at a board. The first to chalk up is the captain and picks:
   **501 or 301**, **legs** (one leg, first to 2, first to 3) and **double out or straight out**,
   then presses Start. On your own it's a practice game.
3. On your turn you step up to the oche. Aim with the move stick, WASD or the mouse. Your hand
   wobbles, more after a few pints. Throw with **T**, **left click**, **Space/Enter**, or **X**
   on a pad. Three darts a turn. The screen shows the score, averages, last turn and a
   checkout route when you're on a finish.
4. **Interact** again (or Step away) leaves the board but keeps your place. Come back to the
   oche and press interact to carry on. **Leave game** gives up your place.
5. If a fight kicks off, or you get hit, everyone at the board steps away. The game waits.

Rules: standard X01. Going below zero, leaving 1, or reaching 0 without a double (with double
out) is a bust and the score goes back to the start of the turn. The bull counts as a double.
First to zero takes the leg; the first thrower moves round each leg.

## Code

- `scripts/darts/darts_rules.gd` (`DartsRules`): regulation board geometry, scoring, checkouts.
- `scripts/darts/darts_match.gd` (`DartsMatch`): the X01 game. Pure rules, `to_dict()` for sync.
- `scripts/darts/darts_board.gd` (`DartsBoard`): one per board, added by `DartsBoard.install(pub)`
  under each node in the `dartboards` group (PubBuilder.dartboard() adds the group and a
  `facing` meta). Host-authoritative: clients send requests, the host adds throw scatter,
  scores and sends the whole match to everyone. Also sticks the turn's darts in the 3D board.
- `scripts/darts/darts_panel.gd`: the darts screen.
- `DartsBoard.local_input_locked()` is checked by `PlayerFighter._read_input` and
  `Hands._read_input`; `DartsBoard.handle_local_interact()` gets first go at interact.

## Tests

```
godot --headless --path . --script res://tests/darts_test.gd   # rules + a solo game in a pub
tests/run_darts_net_test.sh                                    # host + client play a turn each over ENet
```
