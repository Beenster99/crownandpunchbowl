"""Converts Mixamo FBX animations into pose data for CharacterRig.

    blender -b -P tools/blender/mixamo_to_rig.py -- <dir with .fbx files> [out_dir]

Writes one JSON per clip into assets/animations/mixamo/ (or out_dir). Each holds, per frame,
the rotation of each of our joints in the rig's pose convention: a quaternion in the
character's own axes (x right, y up, z back) composed down our bone chain, relative to our
rest pose (arms hanging, palms to the thighs). CharacterRig turns that into bone tracks for
any model with rest_local * (M^-1 * q * M), the same way it bakes its keyed poses, so one
file fits every look whatever its build. The hips' travel is stored in metres, scaled from
the Mixamo skeleton's leg length to ours.

Mixamo's rest pose is a T-pose, so the converter first poses the Mixamo skeleton into our
rest pose (arms down 6 degrees out, palms in) and measures every frame against that.

Download the clips with Skin: Without Skin, 30 fps, no keyframe reduction (see
docs/CHARACTERS.md).
"""

import glob
import json
import math
import os
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "animations", "mixamo")
OUR_HIPS_HEIGHT = 0.98  # hips above the floor for a height-1.0 look, metres

# Our joint -> (Mixamo bone whose global orientation it takes, our parent joint).
# Our second finger bone spans two Mixamo joints, so it takes the last one's orientation.
MAP = {"Hips": ("Hips", None), "Spine": ("Spine", "Hips"), "Spine2": ("Spine1", "Spine"),
       "Chest": ("Spine2", "Spine2"), "Neck": ("Neck", "Chest"), "Head": ("Head", "Neck")}
for _s, _m in (("L", "Left"), ("R", "Right")):
    MAP.update({
        "Clavicle" + _s: (_m + "Shoulder", "Chest"), "Shoulder" + _s: (_m + "Arm", "Clavicle" + _s),
        "Elbow" + _s: (_m + "ForeArm", "Shoulder" + _s), "Hand" + _s: (_m + "Hand", "Elbow" + _s),
        "Thumb1" + _s: (_m + "HandThumb1", "Hand" + _s), "Thumb2" + _s: (_m + "HandThumb3", "Thumb1" + _s),
        "Hip" + _s: (_m + "UpLeg", "Hips"), "Knee" + _s: (_m + "Leg", "Hip" + _s), "Foot" + _s: (_m + "Foot", "Knee" + _s),
    })
    for ours, theirs in (("Index", "Index"), ("Fingers", "Middle"), ("Ring", "Ring"), ("Pinky", "Pinky")):
        MAP[ours + "1" + _s] = (_m + "Hand" + theirs + "1", "Hand" + _s)
        MAP[ours + "2" + _s] = (_m + "Hand" + theirs + "3", ours + "1" + _s)
ORDER = list(MAP)  # parents come before children


def slug(path):
    s = os.path.splitext(os.path.basename(path))[0].lower()
    s = re.sub(r"\((\d+)\)", r"\1", s)
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def bone(arm, name):
    return arm.pose.bones.get("mixamorig:" + name) or arm.pose.bones.get(name)


def world_rot(arm, pb):
    return (arm.matrix_world @ pb.matrix).to_3x3().normalized().to_quaternion()


def world_pos(arm, pb, tail=False):
    return arm.matrix_world @ (pb.tail if tail else pb.head)


def rotate_world(arm, pb, q):
    """Rotate a pose bone by world rotation q about its head."""
    aw = arm.matrix_world.to_3x3().normalized()
    qa = (aw.inverted() @ q.to_matrix() @ aw).to_4x4()
    M = pb.matrix.copy()
    loc = M.to_translation()
    pb.matrix = Matrix.Translation(loc) @ qa @ Matrix.Translation(-loc) @ M
    bpy.context.view_layer.update()


def char_frame(arm):
    """Rotation from Blender world axes to the character's (x right, y up, z back), measured
    from the rest pose."""
    right = world_pos(arm, bone(arm, "RightArm")) - world_pos(arm, bone(arm, "LeftArm"))
    right.z = 0
    right.normalize()
    up = Vector((0, 0, 1))
    back = right.cross(up).normalized()
    return Matrix((right, up, back))  # rows: v_char = C @ v_world


def reference_pose(arm, C):
    """Pose the Mixamo skeleton into our rest pose and return each bone's world rotation."""
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    Ci = C.transposed()
    right, up, fwd = Ci @ Vector((1, 0, 0)), Ci @ Vector((0, 1, 0)), Ci @ Vector((0, 0, -1))
    a = math.radians(6)
    for side, m in ((-1, "Left"), (1, "Right")):
        for name in ("Arm", "ForeArm", "Hand"):
            pb = bone(arm, m + name)
            cur = (world_pos(arm, pb, True) - world_pos(arm, pb)).normalized()
            if name == "Hand":
                want = (right * (math.sin(a) * 0.6 * side) + fwd * 0.02 - up).normalized()
            else:
                want = (right * (math.sin(a) * side) - up * math.cos(a)).normalized()
            rotate_world(arm, pb, cur.rotation_difference(want))
        # Palm to the thigh: knuckles in a line from the index (front) back to the pinky.
        pb = bone(arm, m + "Hand")
        axis = (world_pos(arm, pb, True) - world_pos(arm, pb)).normalized()
        cur = world_pos(arm, bone(arm, m + "HandIndex1")) - world_pos(arm, bone(arm, m + "HandMiddle1"))
        cur = (cur - axis * cur.dot(axis)).normalized()
        want = (fwd - axis * fwd.dot(axis)).normalized()
        ang = cur.angle(want)
        if cur.cross(want).dot(axis) < 0:
            ang = -ang
        rotate_world(arm, pb, Quaternion(axis, ang))
    return {b: world_rot(arm, bone(arm, b)) for b in set(v[0] for v in MAP.values())}


def to_char(C, q):
    return (C @ q.to_matrix() @ C.transposed()).to_quaternion()


def convert(path, out_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    action = arm.animation_data.action if arm.animation_data else None
    if action is None:
        print("SKIP (no animation)", path)
        return None
    f0, f1 = (int(round(x)) for x in action.frame_range)
    arm.animation_data.action = None
    C = char_frame(arm)
    ref = reference_pose(arm, C)
    ref_c = {b: to_char(C, q) for b, q in ref.items()}
    hips_rest = C @ world_pos(arm, bone(arm, "Hips"))
    foot = C @ world_pos(arm, bone(arm, "LeftFoot"))
    k = OUR_HIPS_HEIGHT / max(hips_rest.y - foot.y + 0.08, 0.3)
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    arm.animation_data.action = action
    frames = {j: [] for j in ORDER}
    hips = []
    hips_abs = []
    hands = {"L": [], "R": []}
    feet = {"L": [], "R": []}
    head = []
    ext = {"hand_l": [], "hand_r": [], "foot_l": [], "foot_r": []}
    scene = bpy.context.scene
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        Q = {}
        for j in ORDER:
            theirs, parent = MAP[j]
            pb = bone(arm, theirs)
            g = to_char(C, world_rot(arm, pb)) @ ref_c[theirs].inverted()
            Q[j] = g
            q = (Q[parent].inverted() @ g) if parent else g
            q.normalize()
            if frames[j] and frames[j][-1].dot(q) < 0:
                q.negate()  # keep neighbouring keys on the same side for interpolation
            frames[j].append(q)
        hp = C @ world_pos(arm, bone(arm, "Hips"))
        hips.append((hp - hips_rest) * k)
        hips_abs.append(hp * k)
        for s, m in (("L", "Left"), ("R", "Right")):
            hands[s].append((C @ world_pos(arm, bone(arm, m + "Hand"))) * k)
            feet[s].append((C @ world_pos(arm, bone(arm, m + "Foot"))) * k)
        head.append((C @ world_pos(arm, bone(arm, "Head"))) * k)
        for s, m in (("L", "Left"), ("R", "Right")):
            ext["hand_" + s.lower()].append((world_pos(arm, bone(arm, m + "Hand")) - world_pos(arm, bone(arm, m + "Arm"))).length * k)
            ext["foot_" + s.lower()].append((world_pos(arm, bone(arm, m + "Foot")) - world_pos(arm, bone(arm, m + "UpLeg"))).length * k)
    n = f1 - f0 + 1
    fps = scene.render.fps / scene.render.fps_base

    def reach(track):
        # Furthest forward relative to the hips (forward is -z), and when.
        best, when = -1e9, 0
        for i, p in enumerate(track):
            d = hips_abs[i].z - p.z
            if d > best:
                best, when = d, i
        return best, when / fps

    out = {
        "name": slug(path), "source": os.path.basename(path), "fps": fps, "frames": n,
        "length": (n - 1) / fps,
        "joints": {j: [[round(c, 4) for c in (q.x, q.y, q.z, q.w)] for q in frames[j]] for j in ORDER},
        "hips": [[round(c, 4) for c in v] for v in hips],
        # When each limb reaches furthest forward: a hint for a strike's contact time.
        # Per frame: hand to shoulder and foot to hip distance (m), hands' and feet's
        # positions relative to the hips, for finding when a strike lands.
        "ext": {key: [round(x, 3) for x in v] for key, v in ext.items()},
        "pos": {"hand_l": [[round(c, 3) for c in (p - h)] for p, h in zip(hands["L"], hips_abs)],
                "hand_r": [[round(c, 3) for c in (p - h)] for p, h in zip(hands["R"], hips_abs)],
                "foot_l": [[round(c, 3) for c in (p - h)] for p, h in zip(feet["L"], hips_abs)],
                "foot_r": [[round(c, 3) for c in (p - h)] for p, h in zip(feet["R"], hips_abs)],
                "head": [[round(c, 3) for c in (p - h)] for p, h in zip(head, hips_abs)]},
        "reach": {"hand_l": reach(hands["L"])[1], "hand_r": reach(hands["R"])[1],
                  "foot_l": reach(feet["L"])[1], "foot_r": reach(feet["R"])[1], "head": reach(head)[1]},
    }
    os.makedirs(out_dir, exist_ok=True)
    dest = os.path.join(out_dir, out["name"] + ".json")
    with open(dest, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print("converted %s -> %s (%d frames)" % (os.path.basename(path), dest, n))
    return dest


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = argv[0]
    out_dir = argv[1] if len(argv) > 1 else OUT
    files = sorted(glob.glob(os.path.join(src, "*.fbx"))) if os.path.isdir(src) else [src]
    for f in files:
        convert(f, out_dir)


if __name__ == "__main__":
    main()
