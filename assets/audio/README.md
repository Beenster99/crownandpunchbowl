# Audio

Everything the game plays, and how to rebuild it. Sources and licences are in
[CREDITS.md](CREDITS.md). Every file here is CC0 or CC BY, and the CC BY ones are credited.

| Folder | What | Made by |
| --- | --- | --- |
| `sfx/*.ogg` | Real recordings: bare-knuckle punches (face and body), kicks, headbutts, broken-nose crunches, bone cracks, body falls, glass, wood, swings, swallows, eating, crowd roar | `tools/import_recordings.py` (downloads from OpenGameArt, trims, layers, encodes) |
| `sfx/*.wav` | Grab scuffle, police whistle, door bang | `tools/generate_placeholders.py` (synthesised, CC0) |
| `voice/*.ogg` | Oofs, grunts, groans and knockout cries, male and female | `tools/import_recordings.py` |
| `voice/barks/<voice>/` | Spoken fight lines: taunts, complaints, crawling moans, "Night night!" | `tools/generate_voices.py` (Piper TTS, VCTK voices) |
| `voice/chatter/<voice>/` | Every overheard second-homer chatter line, plus the locals' replies | `tools/generate_voices.py` |
| `music/` | Empty until M4 | |

## Rebuild

```
pip install numpy soundfile py7zr piper-tts   # and ffmpeg with libvorbis on PATH
python3 assets/audio/tools/import_recordings.py
godot --headless --path . --script res://tests/dump_chatter_lines.gd > /tmp/chatter.tsv
python3 assets/audio/tools/generate_voices.py --chatter /tmp/chatter.tsv
```

Fight lines and the cast (which VCTK speaker plays which farmer) are at the top of
`generate_voices.py`. It also writes `scripts/fx/bark_lines.gd`, so don't edit that file by
hand. Chatter text lives in `scripts/ai/chatter_lines.gd`. After changing lines there, re-run
the last two commands. Existing chatter files are kept, so delete a file to re-record it.

## Replacing with studio recordings

Keep the file names. For barks, that's `voice/barks/<voice>/<category>_NN.ogg`, numbered in
the order the lines appear in `BarkLines`. For chatter, it's
`voice/chatter/<voice>/<topic>_<part>_NN.ogg`. Add any new source to `SOURCES` in
`import_recordings.py` so CREDITS.md stays complete.
