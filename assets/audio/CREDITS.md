# Audio credits

Every sound in the game, where it came from and its licence. CC0 needs no credit but is
listed anyway. CC BY sources must be credited in the game's credits screen, using the text
below. Regenerate the recorded part with `assets/audio/tools/import_recordings.py`.

## Recorded sound effects (OpenGameArt.org)

Trimmed, mixed to mono, layered and re-encoded. See `import_recordings.py` for which take
went where.

| Pack | Author | Licence |
| --- | --- | --- |
| [37 hitspunches](https://opengameart.org/content/37-hitspunches) | Independent.nu (submitted by qubodup) | CC0 |
| [5 break crunch impacts](https://opengameart.org/content/5-break-crunch-impacts) | Independent.nu (submitted by qubodup) | CC0 |
| [35 wooden crackshitsdestructions](https://opengameart.org/content/35-wooden-crackshitsdestructions) | Independent.nu (submitted by qubodup) | CC0 |
| [12 wet towel hittingfallingpunching floor sounds](https://opengameart.org/content/12-wet-towel-hittingfallingpunching-floor-sounds) | Iwan Gabovitch (qubodup) | CC0 |
| [75 cc0 breaking falling hit sfx](https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx) | rubberduck | CC0 |
| [glass break](https://opengameart.org/content/glass-break) | Till Behrend | CC0 |
| [fleshy bone breaksnap sfx](https://opengameart.org/content/fleshy-bone-breaksnap-sfx) | Zane Little Music | CC0 |
| [deep bone crackbreak sfx](https://opengameart.org/content/deep-bone-crackbreak-sfx) | Zane Little Music | CC0 |
| [liquid bottle drink set](https://opengameart.org/content/liquid-bottle-drink-set) | Iwan Gabovitch (qubodup) | CC0 |
| [7 eating crunches](https://opengameart.org/content/7-eating-crunches) | StarNinjas | CC0 |
| [air whoosh](https://opengameart.org/content/air-whoosh) | Pyrano Studios | CC0 |
| [crowd shoutingspeaking ambience](https://opengameart.org/content/crowd-shoutingspeaking-ambience) | StarNinjas | CC0 |
| [15 vocal male strainhurtpainjump sounds](https://opengameart.org/content/15-vocal-male-strainhurtpainjump-sounds) | Iwan Gabovitch (qubodup) | CC0 |
| [11 male human paindeath sounds](https://opengameart.org/content/11-male-human-paindeath-sounds) | Michel Baradari | CC BY 3.0 |
| [aargh male screams](https://opengameart.org/content/aargh-male-screams) | JohnsonBrandEditing via congusbongus (files 3 to 7 only) | CC0 |
| [female hurt grunts groans](https://opengameart.org/content/female-hurt-grunts-groans) | Nocturnal_Vanguard | CC0 |
| [female screams](https://opengameart.org/content/female-screams) | tcrocker68, pushkin and Archeos via congusbongus (files 1 to 4 only) | CC0 |

## Spoken lines

Generated with [Piper](https://github.com/OHF-Voice/piper1-gpl) text-to-speech by
`assets/audio/tools/generate_voices.py`. Piper is only used offline to make the files;
none of it ships with the game. The voice models are
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) `en_GB-vctk-medium`,
trained on the CSTR VCTK Corpus.

- CSTR VCTK Corpus: English Multi-speaker Corpus for CSTR Voice Cloning Toolkit (version 0.92),
  Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald, University of Edinburgh, CSTR.
  https://doi.org/10.7488/ds/2645. Licence: CC BY 4.0.

## Synthesised in-house (CC0)

`sfx/grab_*`, `sfx/police_whistle_*` and `sfx/door_bang_*` come from
`assets/audio/tools/generate_placeholders.py`.

## Credits screen text

Sound effects by Michel Baradari (CC BY 3.0), Independent.nu, qubodup, rubberduck, Till Behrend,
Zane Little Music, StarNinjas, Pyrano Studios, Nocturnal_Vanguard and others via OpenGameArt.org.
Voices made with Piper TTS using the CSTR VCTK Corpus (University of Edinburgh, CC BY 4.0).
