#!/usr/bin/env python3
"""Picks the Mixamo clips the game uses and times them: writes assets/animations/mixamo/clips.json.

    python3 tools/mixamo_clips.py [--prune]

Run after tools/blender/mixamo_to_rig.py. The table below says what each clip is for. A
strike is trimmed and sped up so it lands at the same moment as the keyed take it stands in
for (combat's hit timing doesn't change), with the wind-up measured from the limb's motion.
A reaction loses the standing-still lead-in Mixamo clips start with. --prune deletes the
converted clips that aren't used.
"""

import json
import math
import os
import sys

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "animations", "mixamo")

# Contact and length of the keyed takes, seconds (CharacterRig timing for these names).
KEYED = {
    "punch_l": (0.10, 0.38), "punch_r": (0.13, 0.46), "hook_l": (0.16, 0.52), "hook_r": (0.16, 0.52),
    "uppercut_r": (0.19, 0.60), "kick": (0.22, 0.62), "headbutt": (0.24, 0.56), "clinch_knee": (0.34, 0.85),
    "throw": (0.30, 0.60), "stomp": (0.22, 0.62),
}

# name: settings. kind "strike" (base, limb, how contact is found), "react" (trim the lead-in,
# cap the length), "loop" (a standing or moving loop), "clip" (as is, from/to).
#   variant_of: joins the random takes of that animation. replaces: plays under that name.
#   pool: "fight_idle", "calm_idle" or "drunk_idle". then: what plays when it ends
#   ("idle", or an animation). mirror: left-right swapped copy. root: "keep" or "inplace".
TABLE = {
    # Punches, kicks, the dirty stuff.
    "mx_jab": {"clip": "lead_jab", "kind": "strike", "base": "punch_l", "limb": "hand_l"},
    "mx_jab_b": {"clip": "lead_jab_1", "kind": "strike", "base": "punch_l", "limb": "hand_l"},
    "mx_jab_c": {"clip": "lead_jab_2", "kind": "strike", "base": "punch_l", "limb": "hand_l"},
    "mx_cross": {"clip": "cross_punch", "kind": "strike", "base": "punch_r", "limb": "hand_r"},
    "mx_hook_r": {"clip": "hook", "kind": "strike", "base": "hook_r", "limb": "hand_r"},
    "mx_hook_l": {"clip": "hook", "kind": "strike", "base": "hook_l", "limb": "hand_l", "mirror": True},
    "mx_elbow": {"clip": "illegal_elbow_punch", "kind": "strike", "base": "hook_r", "limb": "swing_r"},
    "mx_uppercut": {"clip": "uppercut", "kind": "strike", "base": "uppercut_r", "limb": "rise", "recovery": 0.35},
    "mx_kick": {"clip": "mma_kick", "kind": "strike", "base": "kick", "limb": "foot"},
    "mx_kick_b": {"clip": "mma_kick_1", "kind": "strike", "base": "kick", "limb": "foot"},
    "mx_roundhouse": {"clip": "roundhouse_kick", "kind": "strike", "base": "kick", "limb": "foot"},
    "mx_headbutt": {"clip": "illegal_headbutt", "kind": "strike", "base": "headbutt", "limb": "head"},
    "mx_knee": {"clip": "illegal_knee", "kind": "strike", "base": "clinch_knee", "limb": "knee"},
    "mx_stomp": {"clip": "stomp", "kind": "strike", "base": "stomp", "limb": "stomp", "replaces": "stomp"},
    "mx_stomp_b": {"clip": "zombie_kicking", "kind": "strike", "base": "stomp", "limb": "stomp", "variant_of": "stomp"},
    # Defence.
    "mx_block_head": {"clip": "center_block", "kind": "react", "variant_of": "block_hit_head", "max": 0.7},
    "mx_parry_l": {"clip": "left_block", "kind": "react", "variant_of": "parry_l", "max": 0.6},
    "mx_parry_r": {"clip": "right_block", "kind": "react", "variant_of": "parry_r", "max": 0.6},
    "mx_dodge_r": {"clip": "dodging_right", "kind": "react", "variant_of": "dodge_r", "max": 0.8, "root": "inplace"},
    "mx_dodge_l": {"clip": "dodging_right", "kind": "react", "variant_of": "dodge_l", "max": 0.8, "root": "inplace", "mirror": True},
    "mx_step_r": {"clip": "medium_right_side_step", "kind": "react", "variant_of": "dodge_r", "max": 0.7, "root": "inplace"},
    "mx_step_l": {"clip": "medium_right_side_step", "kind": "react", "variant_of": "dodge_l", "max": 0.7, "root": "inplace", "mirror": True},
    "mx_duck": {"clip": "ducking", "kind": "react", "variant_of": "dodge", "max": 0.8, "root": "inplace"},
    "mx_weave": {"clip": "dodging", "kind": "react", "variant_of": "dodge_back", "max": 1.0, "root": "inplace"},
    # Getting hit.
    "mx_hit_head": {"clip": "light_hit_to_head", "kind": "react", "variant_of": "hit_front", "max": 0.7},
    "mx_hit_head_b": {"clip": "light_hit_to_head_1", "kind": "react", "variant_of": "hit_front", "max": 0.7},
    "mx_hit_reaction": {"clip": "reaction", "kind": "react", "variant_of": "hit_front", "max": 0.9},
    "mx_hit_body": {"clip": "hit_to_body", "kind": "react", "variant_of": "hit_body", "max": 1.0},
    "mx_hit_stomach": {"clip": "big_stomach_hit", "kind": "react", "variant_of": "hit_body", "max": 1.2},
    "mx_hit_stomach_b": {"clip": "receive_stomach_uppercut", "kind": "react", "variant_of": "hit_body", "max": 1.2},
    "mx_hit_ribs_l": {"clip": "big_rib_hit", "kind": "react", "variant_of": "hit_body_l", "max": 1.3},
    "mx_hit_ribs_r": {"clip": "big_rib_hit", "kind": "react", "variant_of": "hit_body_r", "max": 1.3, "mirror": True},
    "mx_hit_upper": {"clip": "receive_uppercut_to_the_face", "kind": "react", "variant_of": "hit_uppercut", "max": 1.0},
    "mx_hit_upper_b": {"clip": "receiving_an_uppercut", "kind": "react", "variant_of": "hit_uppercut", "max": 1.2, "root": "inplace"},
    "mx_stagger": {"clip": "receiving_a_big_uppercut", "kind": "react", "variant_of": "stagger", "max": 1.6, "root": "inplace"},
    "mx_hit_back": {"clip": "hit_on_back_of_head", "kind": "react", "variant_of": "hit_back", "max": 0.8, "root": "inplace"},
    "mx_groin": {"clip": "kick_to_the_groin", "kind": "react", "variant_of": "groin_down", "max": 1.4, "root": "inplace",
                 "then": "groin_hold"},
    "mx_get_up": {"clip": "getting_up_3", "kind": "clip", "variant_of": "get_up", "root": "inplace"},
    "mx_crawl": {"clip": "crawling", "kind": "loop", "variant_of": "crawl", "root": "inplace"},
    # Stances and the pub.
    "mx_fight_idle": {"clip": "bouncing_fight_idle", "kind": "loop", "pool": "fight_idle"},
    "mx_fight_idle_b": {"clip": "idle", "kind": "loop", "pool": "fight_idle"},
    "mx_idle_stand": {"clip": "standing_idle", "kind": "loop", "pool": "calm_idle"},
    "mx_idle_lean": {"clip": "leaning", "kind": "loop", "pool": "calm_idle"},
    "mx_idle_shoulder": {"clip": "one_shoulder_lean", "kind": "loop", "pool": "calm_idle"},
    "mx_idle_drunk": {"clip": "drunk_idle", "kind": "loop", "pool": "drunk_idle"},
    "mx_chat": {"clip": "talking", "kind": "loop", "replaces": "idle_chat"},
    "mx_walk": {"clip": "walking", "kind": "loop", "replaces": "walk_relaxed", "root": "inplace", "travel_speed": 2.0},
    "mx_cheer": {"clip": "cheering", "kind": "clip", "variant_of": "cheer"},
    "mx_clap": {"clip": "clapping", "kind": "clip", "variant_of": "cheer"},
    "mx_taunt": {"clip": "taunt", "kind": "clip", "variant_of": "taunt"},
    "mx_taunt_b": {"clip": "taunt_1", "kind": "clip", "variant_of": "taunt"},
    "mx_insult": {"clip": "insult", "kind": "clip", "variant_of": "taunt"},
    "mx_shrug": {"clip": "shrugging", "kind": "clip", "variant_of": "taunt"},
}

STRIKE_RECOVERY = 0.75  # Mixamo seconds kept after contact
RECOVERY_SPEED = 1.35   # playback rate after contact


def load(name):
    with open(os.path.join(DIR, name + ".json")) as f:
        return json.load(f)


def speed_of(track, fps):
    out = [0.0]
    for a, b in zip(track, track[1:]):
        out.append(math.dist(a, b) * fps)
    return out


def contact_frame(d, limb):
    pos, ext, fps = d["pos"], d["ext"], d["fps"]
    if limb in ("hand_l", "hand_r"):
        return max(range(len(ext[limb])), key=lambda i: ext[limb][i]), limb
    if limb == "foot":
        side = max(("foot_l", "foot_r"), key=lambda k: max(p[1] for p in pos[k]))
        return max(range(len(pos[side])), key=lambda i: pos[side][i][1]), side
    if limb == "knee":
        side = max(("foot_l", "foot_r"), key=lambda k: max(p[1] for p in pos[k]))
        return max(range(len(pos[side])), key=lambda i: pos[side][i][1]), side
    if limb == "stomp":
        side = max(("foot_l", "foot_r"), key=lambda k: max(p[1] for p in pos[k]))
        top = max(range(len(pos[side])), key=lambda i: pos[side][i][1])
        sp = speed_of(pos[side], fps)
        # Lands where the foot stops after coming down.
        for i in range(top + 1, len(sp)):
            if sp[i] < 0.4 and pos[side][i][1] < pos[side][top][1] - 0.15:
                return i, side
        return min(top + 6, len(sp) - 1), side
    if limb == "head":
        return min(range(len(pos["head"])), key=lambda i: pos["head"][i][2]), "head"
    if limb == "rise":
        side = max(("hand_l", "hand_r"), key=lambda k: max(p[1] for p in pos[k]))
        return max(range(len(pos[side])), key=lambda i: pos[side][i][1]), side
    if limb in ("swing_l", "swing_r"):
        side = "hand_" + limb[-1]
        sp = speed_of(pos[side], fps)
        return max(range(len(sp)), key=lambda i: sp[i]), side
    if limb == "throw":
        side = max(("hand_l", "hand_r"), key=lambda k: max(speed_of(pos[k], fps)))
        sp = speed_of(pos[side], fps)
        return max(range(len(sp)), key=lambda i: sp[i]), side
    raise ValueError(limb)


def motion_start(d, track_key, c):
    """The frame the strike starts moving: walking back from contact while the limb (or
    the hips, for a leg) is still going."""
    fps = d["fps"]
    track = d["pos"][track_key]
    sp = speed_of(track, fps)
    peak = max(sp[max(0, c - int(fps)):c + 1] or [0.0])
    i = c
    while i > 0 and sp[i] > peak * 0.18:
        i -= 1
    return i


def lead_in(d):
    """First frame where the body has started to move away from the first frame."""
    j = d["joints"]
    for f in range(d["frames"]):
        diff = 0.0
        for k in ("Hips", "Spine2", "Chest", "Head", "ShoulderL", "ShoulderR"):
            a, b = j[k][0], j[k][f]
            dot = abs(sum(x * y for x, y in zip(a, b)))
            diff = max(diff, 2 * math.degrees(math.acos(min(1.0, dot))))
        if diff > 4.0:
            return max(0, f - 2)
    return 0


def plan(name, spec):
    d = load(spec["clip"])
    fps, n = d["fps"], d["frames"]
    out = {"clip": spec["clip"]}
    for k in ("variant_of", "replaces", "pool", "then", "mirror", "root"):
        if k in spec:
            out[k] = spec[k]
    kind = spec["kind"]
    if kind == "strike":
        base = spec["base"]
        tc, base_len = KEYED[base]
        limb = spec["limb"]
        if spec.get("mirror"):
            # The analysis runs on the unmirrored clip: the other side's limb strikes there.
            limb = limb[:-1] + {"l": "r", "r": "l"}[limb[-1]] if limb[-2:] in ("_l", "_r") else limb
        c, key = contact_frame(d, limb)
        s = motion_start(d, key, c)
        s = max(0, s - 2)
        lead = (c - s) / fps
        speed = max(0.8, min(2.4, lead / tc))
        start = max(0.0, c / fps - tc * speed)
        # Into the blow at the speed that lands it on time, out of it nearer real time.
        after = min(speed, RECOVERY_SPEED)
        end = min((n - 1) / fps, c / fps + spec.get("recovery", STRIKE_RECOVERY) * after)
        out.update({"from": round(start, 3), "to": round(end, 3), "speed": round(speed, 3),
                    "hit_at": round(c / fps, 3), "speed_after": round(after, 3),
                    "contact": round((c / fps - start) / speed, 3), "load": round((c / fps - start) / speed * 0.6, 3),
                    "then": "idle"})
        if "variant_of" not in spec and "replaces" not in spec:
            out["variant_of"] = base
    elif kind == "react":
        s = lead_in(d)
        speed = spec.get("speed", 1.15)
        end = min((n - 1) / fps, s / fps + spec.get("max", 1.0) * speed)
        out.update({"from": round(s / fps, 3), "to": round(end, 3), "speed": speed})
        out.setdefault("then", "idle")
    elif kind == "clip":
        s = lead_in(d)
        out.update({"from": round(s / fps, 3), "to": spec.get("to", -1)})
        out.setdefault("then", "idle")
    elif kind == "loop":
        out["loop"] = True
        if "travel_speed" in spec:
            hips = d["hips"]
            travel = math.dist(hips[0][::2], hips[-1][::2]) / d["length"]
            # Played so that at speed_scale 1 the feet match travel_speed m/s, the walk speed
            # CharacterRig.set_move_speed() scales from.
            out["speed"] = round(spec["travel_speed"] / max(travel, 0.1), 3)
    return out


def main():
    clips = {name: plan(name, spec) for name, spec in TABLE.items()}
    with open(os.path.join(DIR, "clips.json"), "w") as f:
        json.dump(clips, f, indent=1, sort_keys=True)
    for name, c in clips.items():
        print("%-18s %-28s from %-6s to %-6s x%-5s contact %s" % (name, c["clip"], c.get("from"), c.get("to"),
                                                                  c.get("speed"), c.get("contact")))
    if "--prune" in sys.argv:
        used = {c["clip"] for c in clips.values()}
        for fn in os.listdir(DIR):
            if fn.endswith(".json") and fn != "clips.json" and fn[:-5] not in used:
                os.remove(os.path.join(DIR, fn))
                print("pruned", fn)


if __name__ == "__main__":
    main()
