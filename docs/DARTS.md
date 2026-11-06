# Darts (501 and 301)

Every dartboard in every pub is playable, solo or with mates online.

## Playing

Darts is played on a **controller only**. Without one plugged in, the oche says so.

1. Walk up to the oche (the brass line 2.37 m from the board) and press **interact** (RT).
   You're chalked up and the darts screen opens. Your fight and item controls are off while
   it's open.
2. Up to four can chalk up at a board. The first to chalk up is the captain and picks
   **501 or 301**, **legs** (one leg, first to 2, first to 3) and **double out or straight out**,
   then presses Start. On your own it's a practice game.
3. On your turn you step up to the oche and the aim starts on the bull. Steer with the
   **left stick** (the aim drifts a little, so ease onto your target). Your hand wobbles, more
   after a few pints and more again while you draw back.
4. **Hold A** to draw back. The power meter rises and falls; **let go in the gold band** for a
   flat throw. Let go early and the dart drops low, late and it flies high (about 30 mm per
   tenth of the meter). Three darts a turn.
5. **RT** again (or Step away) leaves the board but keeps your place. **Leave game** gives it up.
6. If a fight kicks off, or you get hit, everyone at the board steps away. The game waits.

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
