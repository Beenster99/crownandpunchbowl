"""MakeHuman base mesh, shaped and rigged onto the game's armature, from MakeHuman's data
files only (no MakeHuman or MPFB code runs). Used by build_humans.py.

Data comes from the MPFB extension zip (data/3dobjs/base.obj, data/targets, data/rigs) and
the CC0 asset packs (clothes, hair, eyes as .mhclo + .obj). Set MH_DATA to the extracted
data/ folder and MH_ASSETS to a folder of extracted asset packs (see docs/CHARACTERS.md).

MakeHuman's coordinates are decimetres, y up, facing +z. Ours are metres, z up, facing +y:
blender = (-x, z, y) / 10.
"""

import gzip
import json
import math
import os

from mathutils import Vector

MH_DATA = os.environ.get("MH_DATA", "/opt/mpfb/mpfb_data/data")
MH_ASSETS = os.environ.get("MH_ASSETS", "/opt/mpfb/assets")


def to_b(x, y, z):
    return Vector((-x * 0.1, z * 0.1, y * 0.1))


# --------------------------------------------------------------------------------------
# Base mesh
# --------------------------------------------------------------------------------------

class Base:
    """base.obj: vertices, uvs, and faces tagged with their group (body or a helper)."""

    _cache = None

    def __init__(self):
        self.co = []        # MakeHuman coordinates
        self.uv = []
        self.faces = []     # (vert indices, uv indices, group)
        group = ""
        with open(os.path.join(MH_DATA, "3dobjs", "base.obj")) as f:
            for line in f:
                if line.startswith("v "):
                    _, x, y, z = line.split()[:4]
                    self.co.append((float(x), float(y), float(z)))
                elif line.startswith("vt "):
                    _, u, v = line.split()[:3]
                    self.uv.append((float(u), float(v)))
                elif line.startswith("g "):
                    group = line.split(maxsplit=1)[1].strip()
                elif line.startswith("f "):
                    vs, ts = [], []
                    for tok in line.split()[1:]:
                        parts = tok.split("/")
                        vs.append(int(parts[0]) - 1)
                        ts.append(int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1)
                    self.faces.append((vs, ts, group))
        self.group_verts = {}
        for vs, _, g in self.faces:
            self.group_verts.setdefault(g, set()).update(vs)

    @classmethod
    def get(cls):
        if cls._cache is None:
            cls._cache = Base()
        return cls._cache


_targets = {}


def target(rel):
    """A .target(.gz): {vertex index: (dx, dy, dz)} in MakeHuman units."""
    if rel in _targets:
        return _targets[rel]
    path = os.path.join(MH_DATA, "targets", rel)
    if not path.endswith(".gz"):
        path += ".target.gz"
    out = {}
    if os.path.exists(path):
        with gzip.open(path, "rt") as f:
            for line in f:
                p = line.split()
                if len(p) == 4 and not line.startswith("#"):
                    out[int(p[0])] = (float(p[1]), float(p[2]), float(p[3]))
    _targets[rel] = out
    return out


def _pair(v, lo_name, hi_name, split=0.5):
    """Weights of the two ends a macro slider sits between (MakeHuman's macro rule)."""
    if v < split:
        return {lo_name[0]: 1.0 - v / split, lo_name[1]: v / split}
    return {hi_name[0]: 1.0 - (v - split) / (1.0 - split), hi_name[1]: (v - split) / (1.0 - split)}


def macro_targets(gender, age, muscle, weight, height=0.5, proportions=0.5,
                  african=0.0, asian=0.0, caucasian=1.0):
    """[(target path, weight)] for MakeHuman's macro sliders, all 0..1 (age 0.5 is 25)."""
    g = {"female": 1.0 - gender, "male": gender}
    if age < 0.5:
        a = {"child": 1.0 - (age - 0.1875) / 0.3125, "young": (age - 0.1875) / 0.3125}
    else:
        a = {"young": 1.0 - (age - 0.5) / 0.5, "old": (age - 0.5) / 0.5}
    m = _pair(muscle, ("minmuscle", "averagemuscle"), ("averagemuscle", "maxmuscle"))
    w = _pair(weight, ("minweight", "averageweight"), ("averageweight", "maxweight"))
    out = []
    for gn, gw in g.items():
        for an, aw in a.items():
            for mn, mw in m.items():
                for wn, ww in w.items():
                    base = gw * aw * mw * ww
                    if base < 1e-4:
                        continue
                    out.append(("macrodetails/universal-%s-%s-%s-%s" % (gn, an, mn, wn), base))
                    if height != 0.5:
                        hn = "maxheight" if height > 0.5 else "minheight"
                        out.append(("macrodetails/height/%s-%s-%s-%s-%s" % (gn, an, mn, wn, hn),
                                    base * abs(height - 0.5) * 2.0))
                    if proportions != 0.5:
                        pn = "idealproportions" if proportions > 0.5 else "uncommonproportions"
                        out.append(("macrodetails/proportions/%s-%s-%s-%s-%s" % (gn, an, mn, wn, pn),
                                    base * abs(proportions - 0.5) * 2.0))
            for race, rw in (("african", african), ("asian", asian), ("caucasian", caucasian)):
                if rw * gw * aw > 1e-4:
                    out.append(("macrodetails/%s-%s-%s" % (race, gn, an), rw * gw * aw))
    return out


def shaped(targets):
    """Base coordinates with [(target, weight)] applied, in MakeHuman units."""
    base = Base.get()
    co = [list(c) for c in base.co]
    for rel, wt in targets:
        if abs(wt) < 1e-4:
            continue
        for i, d in target(rel).items():
            c = co[i]
            c[0] += d[0] * wt
            c[1] += d[1] * wt
            c[2] += d[2] * wt
    return co


def joint(co, name):
    """Centre of a joint helper cube (MakeHuman's "CUBE" strategy), in MakeHuman units."""
    vs = Base.get().group_verts.get(name)
    if not vs:
        raise KeyError(name)
    n = float(len(vs))
    return (sum(co[i][0] for i in vs) / n, sum(co[i][1] for i in vs) / n, sum(co[i][2] for i in vs) / n)


# --------------------------------------------------------------------------------------
# The rig: MakeHuman's "game engine" skeleton folded onto our bone names
# --------------------------------------------------------------------------------------

# Our bone -> (MakeHuman head joint, MakeHuman tail joint).
JOINTS = {
    "Hips": ("joint-pelvis", "joint-spine-4"),
    "Spine": ("joint-spine-4", "joint-spine-3"),
    "Spine2": ("joint-spine-3", "joint-spine-2"),
    "Chest": ("joint-spine-2", "joint-spine-1"),
    "Neck": ("joint-neck", "joint-head"),
    "Head": ("joint-head", "joint-head-2"),
}
for _s, _m in (("L", "l"), ("R", "r")):
    JOINTS.update({
        "Clavicle" + _s: ("joint-%s-clavicle" % _m, "joint-%s-shoulder" % _m),
        "Shoulder" + _s: ("joint-%s-shoulder" % _m, "joint-%s-elbow" % _m),
        "Elbow" + _s: ("joint-%s-elbow" % _m, "joint-%s-hand" % _m),
        "Hand" + _s: ("joint-%s-hand" % _m, "joint-%s-finger-3-1" % _m),
        "Thumb1" + _s: ("joint-%s-finger-1-1" % _m, "joint-%s-finger-1-2" % _m),
        "Thumb2" + _s: ("joint-%s-finger-1-2" % _m, "joint-%s-finger-1-4" % _m),
        "Index1" + _s: ("joint-%s-finger-2-1" % _m, "joint-%s-finger-2-2" % _m),
        "Index2" + _s: ("joint-%s-finger-2-2" % _m, "joint-%s-finger-2-4" % _m),
        "Fingers1" + _s: ("joint-%s-finger-3-1" % _m, "joint-%s-finger-3-2" % _m),
        "Fingers2" + _s: ("joint-%s-finger-3-2" % _m, "joint-%s-finger-3-4" % _m),
        "Ring1" + _s: ("joint-%s-finger-4-1" % _m, "joint-%s-finger-4-2" % _m),
        "Ring2" + _s: ("joint-%s-finger-4-2" % _m, "joint-%s-finger-4-4" % _m),
        "Pinky1" + _s: ("joint-%s-finger-5-1" % _m, "joint-%s-finger-5-2" % _m),
        "Pinky2" + _s: ("joint-%s-finger-5-2" % _m, "joint-%s-finger-5-4" % _m),
        "Hip" + _s: ("joint-%s-upper-leg" % _m, "joint-%s-knee" % _m),
        "Knee" + _s: ("joint-%s-knee" % _m, "joint-%s-ankle" % _m),
        "Foot" + _s: ("joint-%s-ankle" % _m, "joint-%s-toe-2-4" % _m),
    })

# MakeHuman game-engine bone -> ours, for the skin weights.
WEIGHT_MAP = {"Root": "Hips", "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine2", "spine_03": "Chest",
              "neck_01": "Neck", "head": "Head"}
for _s, _m in (("L", "l"), ("R", "r")):
    WEIGHT_MAP.update({
        "clavicle_" + _m: "Clavicle" + _s, "upperarm_" + _m: "Shoulder" + _s, "lowerarm_" + _m: "Elbow" + _s,
        "hand_" + _m: "Hand" + _s, "thigh_" + _m: "Hip" + _s, "calf_" + _m: "Knee" + _s,
        "foot_" + _m: "Foot" + _s, "ball_" + _m: "Foot" + _s,
    })
    for _f, _o in (("thumb", "Thumb"), ("index", "Index"), ("middle", "Fingers"), ("ring", "Ring"), ("pinky", "Pinky")):
        WEIGHT_MAP.update({_f + "_01_" + _m: _o + "1" + _s, _f + "_02_" + _m: _o + "2" + _s,
                           _f + "_03_" + _m: _o + "2" + _s})

# Bones the MakeHuman bodies add to the shared armature: a chain for each finger. Older
# models don't have them; the rig curls them with the others where they exist.
EXTRA_BONES = []
for _s in "LR":
    EXTRA_BONES += [("Ring1" + _s, "Hand" + _s), ("Ring2" + _s, "Ring1" + _s),
                    ("Pinky1" + _s, "Hand" + _s), ("Pinky2" + _s, "Pinky1" + _s)]


def skin_weights():
    """{vertex index: {our bone: weight}} from MakeHuman's game-engine weights, plus the jaw
    from its default rig (taken out of the head)."""
    with open(os.path.join(MH_DATA, "rigs", "standard", "weights.game_engine.json")) as f:
        ge = json.load(f)["weights"]
    out = {}
    for bone, pairs in ge.items():
        ours = WEIGHT_MAP.get(bone)
        if ours is None:
            continue
        for vi, w in pairs:
            d = out.setdefault(vi, {})
            d[ours] = d.get(ours, 0.0) + w
    with open(os.path.join(MH_DATA, "rigs", "standard", "weights.default.json")) as f:
        jaw = json.load(f)["weights"].get("jaw", [])
    for vi, w in jaw:
        d = out.setdefault(vi, {})
        take = min(w, d.get("Head", 0.0))
        if take > 0.0:
            d["Head"] -= take
            d["Jaw"] = d.get("Jaw", 0.0) + take
    for d in out.values():
        tot = sum(d.values())
        if tot > 0:
            for k in d:
                d[k] /= tot
    return out


# --------------------------------------------------------------------------------------
# Proxies (clothes, hair, eyes, eyebrows): .mhclo fitted to the shaped body
# --------------------------------------------------------------------------------------

class Proxy:
    """A MakeHuman proxy: each of its vertices sits on a triangle of the base mesh (three
    vertices and weights) plus an offset scaled by the body's size along three references."""

    def __init__(self, path):
        self.path = path
        self.dir = os.path.dirname(path)
        self.name = ""
        self.obj = None
        self.material = None
        self.refs = []      # (v1, v2, v3, w1, w2, w3, dx, dy, dz)
        self.scales = {}    # axis -> (v1, v2, ref length)
        self.delete = set()
        self.z_depth = 50
        self.offset_mode = 0
        mode = ""
        with open(path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                words = line.split()
                key = words[0]
                if key == "verts" and len(words) > 1:
                    mode = "verts"
                    continue
                if key == "delete_verts":
                    mode = "delete"
                    continue
                if mode == "verts" and _is_num(key):
                    nums = [float(x) for x in words]
                    if len(nums) == 1:
                        self.refs.append((int(nums[0]), 0, 0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0))
                    else:
                        v1, v2, v3 = int(nums[0]), int(nums[1]), int(nums[2])
                        self.refs.append((v1, v2, v3, nums[3], nums[4], nums[5], nums[6], nums[7], nums[8]))
                    continue
                if mode == "delete" and (key == "-" or _is_num(key.replace("-", ""))):
                    # "12 - 40 44 50-52": ranges written with or without spaces round the dash.
                    toks = " ".join(words).replace("-", " - ").split()
                    i = 0
                    while i < len(toks):
                        if i + 2 < len(toks) and toks[i + 1] == "-":
                            self.delete.update(range(int(toks[i]), int(toks[i + 2]) + 1))
                            i += 3
                        elif toks[i] == "-":
                            i += 1
                        else:
                            self.delete.add(int(toks[i]))
                            i += 1
                    continue
                # Keyword lines can sit between "verts 0" and the numbers (hair puts its
                # material there), so they don't end a numeric section.
                if key == "name":
                    self.name = words[1]
                elif key == "obj_file":
                    self.obj = os.path.join(self.dir, words[1])
                elif key == "material":
                    self.material = os.path.join(self.dir, words[1])
                elif key in ("x_scale", "y_scale", "z_scale"):
                    self.scales[key[0]] = (int(words[1]), int(words[2]), float(words[3]))
                elif key == "z_depth":
                    self.z_depth = int(words[1])

    def fit(self, co):
        """The proxy's vertex positions on a shaped body (MakeHuman units)."""
        def scale(axis, k):
            if axis not in self.scales:
                return 1.0
            a, b, ref = self.scales[axis]
            return abs(co[a][k] - co[b][k]) / ref if ref else 1.0
        sx, sy, sz = scale("x", 0), scale("y", 1), scale("z", 2)
        out = []
        for v1, v2, v3, w1, w2, w3, dx, dy, dz in self.refs:
            a, b, c = co[v1], co[v2], co[v3]
            out.append((w1 * a[0] + w2 * b[0] + w3 * c[0] + dx * sx,
                        w1 * a[1] + w2 * b[1] + w3 * c[1] + dy * sy,
                        w1 * a[2] + w2 * b[2] + w3 * c[2] + dz * sz))
        return out

    def mesh_data(self):
        """Faces (vertex and uv indices) and uvs from the proxy's .obj."""
        uvs, faces = [], []
        with open(self.obj, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("vt "):
                    p = line.split()
                    uvs.append((float(p[1]), float(p[2])))
                elif line.startswith("f "):
                    vs, ts = [], []
                    for tok in line.split()[1:]:
                        parts = tok.split("/")
                        vs.append(int(parts[0]) - 1)
                        ts.append(int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1)
                    faces.append((vs, ts))
        return faces, uvs

    def texture(self):
        """The diffuse texture path from the .mhmat, if any."""
        if not self.material or not os.path.exists(self.material):
            return None
        with open(self.material, encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.split()
                if len(p) >= 2 and p[0] == "diffuseTexture":
                    path = os.path.join(os.path.dirname(self.material), p[1])
                    return path if os.path.exists(path) else None
        return None

    def weights(self, base_weights):
        """Skin weights for each proxy vertex, blended from the body vertices it sits on."""
        out = []
        for v1, v2, v3, w1, w2, w3, *_ in self.refs:
            d = {}
            for vi, wi in ((v1, w1), (v2, w2), (v3, w3)):
                if wi == 0.0:
                    continue
                for bone, bw in base_weights.get(vi, {}).items():
                    d[bone] = d.get(bone, 0.0) + bw * wi
            tot = sum(d.values()) or 1.0
            out.append({k: v / tot for k, v in d.items()})
        return out


def _is_num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def find_proxy(name):
    """Path of an asset's .mhclo by asset name, searched under MH_ASSETS."""
    for root, _, files in os.walk(MH_ASSETS):
        for fn in files:
            if fn.endswith(".mhclo") and (fn[:-6] == name or os.path.basename(root) == name):
                return os.path.join(root, fn)
    return None
