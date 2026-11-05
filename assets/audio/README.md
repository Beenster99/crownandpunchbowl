# Audio

Placeholder sound set for milestone M1. Every file in `sfx/` and `voice/` is synthesised by
[`tools/generate_placeholders.py`](tools/generate_placeholders.py) from noise, sine partials
and a small formant voice model. Nothing is sampled or downloaded, so there is no third-party
licence: treat these files as CC0.

Regenerate (deterministic, needs only `numpy`):

```
python3 assets/audio/tools/generate_placeholders.py
```

## What's here

| Folder | Cues |
| --- | --- |
| `sfx/` | bare-knuckle punches (body and face), kicks, headbutt cracks, broken-nose crunches, body falls, glass smash and clink, wood break and hit, swing whoosh, blood splat, grab scuffle, gulp, munch, police whistle, door bang |
| `voice/` | oofs, effort grunts, groans, crawling moans, knockout cries and a post-pint "ahh". `_m` and `_f` sets for male and female fighters |
| `music/` | empty until M4 |

The cue table is `scripts/fx/sound_bank.gd`. Each cue plays a random variant at a random
pitch through the `SFX` or `Voice` bus.

## Replacing with real audio (M4)

Keep the `<name>_NN.wav` pattern and update `count` in `SoundBank.CUES`. `.ogg` works too if
the path pattern in `SoundBank.files_for()` is updated. Any sourced audio must be CC0 or have a
licence that allows commercial use. Record the source and licence for each file here.
