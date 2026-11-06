# Talking to punters

Hold **push to talk** (V, or Back on a pad) and speak, or press **Enter** and type. The
punter you're facing hears you. Settings live on the **Talk** tab.

## What happens

1. **Listening** (`scripts/talk/listener.gd`). The mic is recorded while the key is held and
   turned into text on the player's own PC by whisper.cpp (`speech/whisper`). Nothing is
   uploaded. Silence either side is trimmed and quiet mics are brought up to level first.
   If nobody is in earshot, the speaker is told so. A loud recording counts as shouting.
2. **Who heard it** (`Talk.pick_listener`). The nearest punter in front of you, preferring
   whoever you're fighting and anyone you name ("Oi, barman!", "Rupert, calm down"). Shouting
   carries further, and a shouted provocation makes calm punters nearby look round.
3. **What it did** — two plans:
   - **Plan 1, always on, no key.** `TalkIntent.classify` reads calming words (calm down,
     sorry, accident, buy you a pint) and provoking ones (oi, come on then, insults,
     shouting). `Npc.hear_words` acts on them: an apology can settle a punter (they back off
     and won't volunteer back in for 20-35 s, unless hit again); provocation gets them
     squaring up. Each punch you've landed on them, and each plea in a row, makes talking
     them down less likely. The punter answers with a stock line from `TalkLines`.
   - **Plan 2, with an Anthropic API key.** `PunterMind` sends Claude (Haiku 5.5 by default)
     the punter's persona, mood, how often you've hit them, the state of the pub and the
     conversation so far. Claude returns a reply and an `effect` (calm_down, stay_wary,
     square_up, attack, cower, no_change) that `Npc.apply_talk_effect` acts on. If the call
     fails, Plan 1 answers instead.
4. **The reply** shows in a bubble and is spoken in the punter's voice (`PunterVoice`):
   ElevenLabs if a key is set, else Piper on the PC using the same VCTK speakers as the
   recorded barks, else the Windows voices.

Calm punters hold a proper conversation rather than trading quips: each has three interests
from the second-homers' chatter topics (dogs, wine, the second home, yoga...). Claude is told
to chat from middle-class values and not to keep bringing up fighting or farming. Without a
key, posh punters' and rugby lads' small talk comes from `ChatterLines`.

Bar staff answer but never fight, and nobody can hit them. Police are never talked down.

## Co-op

Speech-to-text runs on the speaker's PC; only the text goes to the host (`Talk._said`). The
host runs the punters, calls Claude with the host's key, changes moods, and sends the reply
to everyone (`Talk._npc_line`). Each PC speaks it with its own voices. Clients don't need a
key.

## Speech tools

Not in git. `python3 tools/fetch_speech.py` downloads them into `speech/` (whisper.cpp
v1.8.2 + small.en model (base.en misheard too much in play-testing; it's still used if it's
the only one there), Piper 2023.11.14-2, en_GB VCTK voice). Copy `speech/` next to
`CrownAndPunchbowl.exe` when packaging a build. Licences are in `speech/LICENCES.txt`
(Piper uses espeak-ng, GPL v3, run as a separate program). `CP_SPEECH_DIR` overrides the
location.

## Tests

`godot --headless --fixed-fps 60 --path . --script res://tests/talk_test.gd`, and
`tests/run_net_test.sh` covers a client talking to the host's punters.
The real whisper and Piper programs aren't run in the cloud tests: check push-to-talk and
the voices on Windows by hand.
