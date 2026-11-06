"""Builds every character as a rigged, skinned .glb for Godot.

    blender -b -P tools/blender/build_characters.py            # all looks
    blender -b -P tools/blender/build_characters.py -- tom gaz # some looks
    blender -b -P tools/blender/build_characters.py -- --blend tom  # also save tools/blender/out/tom.blend

Reads assets/models/characters/looks.json (written by tools/export_looks.gd) and writes
assets/models/characters/<id>.glb. Every model shares one armature layout (bone names below),
faces +Y in Blender (-Z in Godot) and has its origin on the floor between the feet.

Bodies are metaballs (torso, arms, legs, head) converted to meshes and decimated, so they
blend organically like a quick sculpt. Clothes, hair and beards are shells grown off the
body surface. Hats and props are small modelled pieces. Colours come from named materials
that Godot recolours per look, so one model serves a whole crowd type.

Optional pieces are separate objects named Hair_<STYLE>, Beard_<STYLE>, Hat_<STYLE> and
Top_<TYPE>. Godot shows the ones that match the look. Blood_* objects are hidden until hurt.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "characters")
LOOKS = os.path.join(OUT_DIR, "looks.json")

BONES = [
    # name, parent
    ("Hips", None), ("Spine", "Hips"), ("Spine2", "Spine"), ("Chest", "Spine2"), ("Neck", "Chest"),
    ("Head", "Neck"), ("Nose", "Head"), ("Jaw", "Head"), ("BrowL", "Head"), ("BrowR", "Head"),
]
for _s in "LR":
    BONES += [
        ("Clavicle" + _s, "Chest"), ("Shoulder" + _s, "Clavicle" + _s), ("Elbow" + _s, "Shoulder" + _s),
        ("Hand" + _s, "Elbow" + _s),
        ("Thumb1" + _s, "Hand" + _s), ("Thumb2" + _s, "Thumb1" + _s),
        ("Index1" + _s, "Hand" + _s), ("Index2" + _s, "Index1" + _s),
        ("Fingers1" + _s, "Hand" + _s), ("Fingers2" + _s, "Fingers1" + _s),
    ]
for _s in "LR":
    BONES += [("Hip" + _s, "Hips"), ("Knee" + _s, "Hip" + _s), ("Foot" + _s, "Knee" + _s)]


HAND_SCALE = 1.3  # cartoon hands: big enough to read as fists from the game camera


def col(hexstr):
    h = hexstr.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, 1.0)


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------------------
# Proportions: one place that turns a look into joint positions (unscaled, 1.0 = 1.78 m).
# --------------------------------------------------------------------------------------

class Build:
    def __init__(self, look):
        L = self.L = look
        self.t = L["limb_thickness"]
        self.g = L["girth"]
        self.fem = L["feminine"]
        self.thigh = 0.44 * L["leg_length"]
        self.shin = 0.42 * L["leg_length"]
        self.foot_h = 0.08
        self.leg = self.thigh + self.shin + self.foot_h
        self.tw = 0.4 * self.g * (0.92 if self.fem else 1.0)
        self.td = 0.25 * self.g
        self.hw = self.tw * (1.06 if self.fem else 0.95)
        self.shx = 0.17 * L["shoulders"] + 0.06 * self.g
        self.upper = 0.3 * L["arm_length"]
        self.fore = 0.27 * L["arm_length"]
        self.r = 0.15 * L["head_size"]
        self.stoop = math.radians(L["stoop"])
        self.belly = L["belly"]

        lv = self.leg
        self.p = {}
        self.p["hips"] = Vector((0, 0, lv))
        self.p["spine"] = Vector((0, 0, lv + 0.02))
        self.p["chest"] = Vector((0, 0, lv + 0.2))
        self.chest_rot = Matrix.Rotation(-self.stoop, 3, "X")
        self.p["neck"] = self.p["chest"] + self.chest_rot @ Vector((0, 0, 0.38))
        self.p["head"] = self.p["neck"] + Vector((0, 0.01, 0.06))
        self.head_c = self.p["head"] + Vector((0, 0, self.r * 1.05))
        self.p["head_top"] = self.p["head"] + Vector((0, 0, self.r * 2.2))
        for side, s in ((-1, "L"), (1, "R")):
            sh = self.p["chest"] + self.chest_rot @ Vector((self.shx * side, 0, 0.31))
            a = math.radians(6) * side
            down = Vector((math.sin(a), 0, -math.cos(a)))
            self.p["shoulder" + s] = sh
            self.p["elbow" + s] = sh + down * self.upper
            self.p["wrist" + s] = self.p["elbow" + s] + down * self.fore
            self.p["fist" + s] = self.p["wrist" + s] + down * 0.1 * L["hand_size"]
            self._hand(s, side, down)
            hip = Vector((self.hw * 0.27 * side, 0, lv - 0.04))
            self.p["hip" + s] = hip
            self.p["knee" + s] = hip + Vector((0, 0, -self.thigh))
            self.p["ankle" + s] = self.p["knee" + s] + Vector((0, 0, -self.shin))
            self.p["toe" + s] = Vector((hip.x, 0.15, 0.03))
        self.segments = self._segments()

    def _hand(self, s, side, down):
        """Palm, three finger chains and a thumb. The hand hangs along the arm with the palm
        facing the thigh and the knuckles in a line from front (index) to back (pinky).
        Chunky, cartoon proportions to match the heads."""
        hs = self.L["hand_size"] * HAND_SCALE
        fwd = Vector((0, 1, 0))
        inward = Vector((-side, 0, 0))
        w = self.p["wrist" + s]
        k = w + down * 0.068 * hs
        self.p["knuckles" + s] = k
        h = {"palm": (w, k), "down": down, "fwd": fwd, "inward": inward, "fingers": []}
        # (name, offset along the knuckle line, length)
        for name, off, length in (("index", 0.027, 0.058), ("middle", 0.009, 0.064), ("ring", -0.009, 0.06),
                                  ("pinky", -0.026, 0.048)):
            base = k + fwd * off * hs
            tip = base + down * length * hs
            h["fingers"].append((name, base, tip))
        tb = w + down * 0.016 * hs + fwd * 0.036 * hs + inward * 0.01 * hs
        td = (down * 0.75 + fwd * 0.55 + inward * 0.3).normalized()
        h["thumb"] = (tb, tb + td * 0.06 * hs)
        h["finger_r"] = 0.0082 * hs
        self.hand = getattr(self, "hand", {})
        self.hand[s] = h

    def _segments(self):
        p = self.p
        seg = {
            "Hips": (p["hips"] + Vector((0, 0, -0.12)), p["spine"]),
            "Spine": (p["spine"], p["chest"]),
            "Chest": (p["chest"], p["neck"]),
            "Neck": (p["neck"], p["head"]),
            "Head": (p["head"], p["head_top"]),
            "Nose": (self.head_c + Vector((0, self.r * 0.95, -self.r * 0.05)),
                     self.head_c + Vector((0, self.r * 1.25, -self.r * 0.05))),
        }
        mid = (p["spine"] + p["chest"]) * 0.5
        seg["Spine"] = (p["spine"], mid)
        seg["Spine2"] = (mid, p["chest"])
        r, hc = self.r, self.head_c
        # Jaw: hinge just in front of the ears, down to the chin.
        seg["Jaw"] = (hc + Vector((0, 0.1 * r, -0.2 * r)), hc + Vector((0, 0.78 * r, -0.78 * r)))
        brow = self.L["brow"]
        for s, side in (("L", -1), ("R", 1)):
            # Brows run from the outer end (the pivot) to the inner end, so a twist lowers or
            # raises the inner end: a frown or a wince.
            seg["Brow" + s] = (hc + Vector((0.55 * r * side, (0.86 + 0.12 * brow) * r, (0.40 + 0.06 * brow) * r)),
                               hc + Vector((0.12 * r * side, (0.98 + 0.14 * brow) * r, (0.42 + 0.04 * brow) * r)))
        for s in "LR":
            # The clavicle runs from the base of the neck to the shoulder joint.
            side = -1 if s == "L" else 1
            seg["Clavicle" + s] = (p["chest"] + self.chest_rot @ Vector((0.035 * side, 0.01, 0.3)), p["shoulder" + s])
            seg["Shoulder" + s] = (p["shoulder" + s], p["elbow" + s])
            seg["Elbow" + s] = (p["elbow" + s], p["wrist" + s])
            h = self.hand[s]
            seg["Hand" + s] = h["palm"]
            fingers = {n: (a, b) for n, a, b in h["fingers"]}
            for bone, (a, b) in (("Index", fingers["index"]),
                                 ("Fingers", ((fingers["middle"][0] + fingers["ring"][0]) * 0.5,
                                              (fingers["middle"][1] + fingers["ring"][1]) * 0.5)),
                                 ("Thumb", h["thumb"])):
                j = a + (b - a) * 0.55
                seg[bone + "1" + s] = (a, j)
                seg[bone + "2" + s] = (j, b)
            seg["Hip" + s] = (p["hip" + s], p["knee" + s])
            seg["Knee" + s] = (p["knee" + s], p["ankle" + s])
            seg["Foot" + s] = (p["ankle" + s], p["toe" + s])
        return seg


# --------------------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


MATS = {}


def mat(name, color):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.8 if name not in ("eye_white", "eye_dark", "metal") else 0.3
        if name == "metal":
            bsdf.inputs["Metallic"].default_value = 0.8
        MATS[name] = m
    return MATS[name]


def metaballs(name, elements, resolution=0.016, smooth=6):
    """Solid union of primitives, like a quick sculpt: each element is meshed, the lot is
    voxel-remeshed into one watertight surface (voxel size = resolution), then smoothed so
    the joins fillet. elements: (type, co, radius, size, rotation, unused) where ELLIPSOID
    uses size as semi-axes, BALL uses radius, and CAPSULE runs size.x either side of co
    along its local X with the given radius."""
    bm = bmesh.new()
    for typ, co, radius, size, rot, _ in elements:
        part = bmesh.new()
        R = rot.to_4x4() if rot is not None else Matrix.Identity(4)
        if typ == "ELLIPSOID":
            bmesh.ops.create_uvsphere(part, u_segments=24, v_segments=16, radius=1.0)
            bmesh.ops.transform(part, matrix=Matrix.Translation(co) @ R @ Matrix.Diagonal((*size, 1.0)), verts=part.verts)
        elif typ == "BALL":
            bmesh.ops.create_uvsphere(part, u_segments=20, v_segments=12, radius=radius)
            bmesh.ops.translate(part, vec=co, verts=part.verts)
        elif typ == "CAPSULE":
            half = size.x
            for end in (-half, half):
                bmesh.ops.create_uvsphere(part, u_segments=16, v_segments=10, radius=radius)
                tmp = [v for v in part.verts if not v.tag]
                bmesh.ops.transform(part, matrix=Matrix.Translation(co) @ R @ Matrix.Translation((end, 0, 0)), verts=tmp)
                for v in part.verts:
                    v.tag = True
            geo = bmesh.ops.create_cone(part, cap_ends=True, segments=16, radius1=radius, radius2=radius, depth=half * 2)
            bmesh.ops.transform(part, matrix=Matrix.Translation(co) @ R @ Matrix.Rotation(math.pi / 2, 4, "Y"), verts=geo["verts"])
        tmp_me = bpy.data.meshes.new("part")
        part.to_mesh(tmp_me)
        part.free()
        bm.from_mesh(tmp_me)
        bpy.data.meshes.remove(tmp_me)
    me = bpy.data.meshes.new(name + "_src")
    bm.to_mesh(me)
    bm.free()
    if resolution <= 0:
        me.name = name
        return me
    obj = link(bpy.data.objects.new(name, me))
    rm = obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = resolution
    rm.adaptivity = 0.0
    if smooth > 0:
        sm = obj.modifiers.new("smooth", "LAPLACIANSMOOTH")
        sm.iterations = smooth
        sm.lambda_factor = 0.8
        sm.use_volume_preserve = True
        sm.use_normalized = True
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(me)
    out.name = name
    return out


def ellip(co, size, rot=None, stiff=2.0):
    return ("ELLIPSOID", Vector(co), 1.0, Vector(size), rot, stiff)


def ball(co, r, stiff=2.0):
    return ("BALL", Vector(co), r, None, None, stiff)


def capsule(a, b, r, stiff=2.0):
    """Capsule between points a and b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = Vector((1, 0, 0)).rotation_difference(d.normalized()).to_matrix() if d.length > 1e-6 else None
    return ("CAPSULE", (a + b) * 0.5, r, Vector((d.length * 0.5, 1, 1)), rot, stiff)


PART_TORSO, PART_ARM_L, PART_ARM_R, PART_LEG_L, PART_LEG_R = 1, 2, 3, 4, 5
PART_HAND_L, PART_HAND_R, PART_HEAD, PART_LIPS, PART_BROW = 6, 7, 8, 9, 10
FINGER_BONES = ["Thumb1", "Thumb2", "Index1", "Index2", "Fingers1", "Fingers2"]
PART_BONES = {
    PART_TORSO: ["Hips", "Spine", "Spine2", "Chest", "Neck", "Head", "ClavicleL", "ClavicleR"],
    PART_ARM_L: ["Chest", "ClavicleL", "ShoulderL", "ElbowL", "HandL"],
    PART_ARM_R: ["Chest", "ClavicleR", "ShoulderR", "ElbowR", "HandR"],
    PART_HAND_L: ["ElbowL", "HandL"] + [b + "L" for b in FINGER_BONES],
    PART_HAND_R: ["ElbowR", "HandR"] + [b + "R" for b in FINGER_BONES],
    PART_LEG_L: ["Hips", "HipL", "KneeL", "FootL"],
    PART_LEG_R: ["Hips", "HipR", "KneeR", "FootR"],
    PART_HEAD: ["Neck", "Head"],
    PART_LIPS: ["Head"],
    PART_BROW: ["Head"],
}


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def expand_candidates(cands):
    """Explicit bone lists predate the second spine bone and the clavicles: add them where
    their neighbours are listed, so clothes bend with the body."""
    out = list(cands)
    if "Spine" in out and "Chest" in out and "Spine2" not in out:
        out.append("Spine2")
    for s in "LR":
        if "Shoulder" + s in out and "Clavicle" + s not in out:
            out.append("Clavicle" + s)
    return out


def tag_part(me, part):
    """Remembers which body part each vertex came from, so skin weights never bleed
    between an arm and the torso it touches. Shells copied off the body keep the tag."""
    attr = me.attributes.new("part", "INT", "POINT")
    for d in attr.data:
        d.value = part
    return me


def decimate(me, target_faces):
    ratio = target_faces / max(1, len(me.polygons))
    if ratio >= 1.0:
        return me
    obj = link(bpy.data.objects.new("tmp", me))
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = False
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    bpy.data.objects.remove(obj)
    out.name = me.name
    bpy.data.meshes.remove(me)
    return out


def smooth_all(me):
    for poly in me.polygons:
        poly.use_smooth = True


def mesh_obj(name, me, materials):
    obj = link(bpy.data.objects.new(name, me))
    for m in materials:
        obj.data.materials.append(m)
    return obj


def box_mesh(name, center, size, rot=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    M = Matrix.Translation(Vector(center)) @ (rot.to_4x4() if rot else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def cyl_mesh(name, center, r_bottom, r_top, depth, segments=16, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=depth)
    M = Matrix.Translation(Vector(center)) @ (rot.to_4x4() if rot else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def torus_mesh(name, center, major, minor, scale_z=1.0, rot=None, segs=20, ring=6):
    bm = bmesh.new()
    verts = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            x = (major + minor * math.cos(b)) * math.cos(a)
            y = (major + minor * math.cos(b)) * math.sin(a)
            z = minor * math.sin(b) * scale_z
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for i in range(segs):
        for j in range(ring):
            bm.faces.new((verts[i][j], verts[(i + 1) % segs][j], verts[(i + 1) % segs][(j + 1) % ring], verts[i][(j + 1) % ring]))
    M = Matrix.Translation(Vector(center)) @ (rot.to_4x4() if rot else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def join_meshes(name, parts):
    """parts: list of (mesh, material_index). Returns one mesh with material indices set."""
    bm = bmesh.new()
    for me, mi in parts:
        tmp = bmesh.new()
        tmp.from_mesh(me)
        for f in tmp.faces:
            f.material_index = mi
        tmp_me = bpy.data.meshes.new("tmpj")
        tmp.to_mesh(tmp_me)
        tmp.free()
        bm.from_mesh(tmp_me)
        bpy.data.meshes.remove(tmp_me)
        bpy.data.meshes.remove(me)
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    return out


def shell(src_me, name, face_pred, thickness, face_mat=None, solid=True):
    """Copies the faces of src_me that pass face_pred(center, normal), pushed out along
    their vertex normals by thickness(co) metres. Optionally closes the edges.
    face_mat(center) -> material index for the new faces."""
    bm = bmesh.new()
    bm.from_mesh(src_me)
    bm.normal_update()
    keep = [f for f in bm.faces if face_pred(f.calc_center_median(), f.normal)]
    drop = [f for f in bm.faces if f not in set(keep)]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.normal_update()
    if not bm.faces:
        bm.free()
        return None
    # Relax the cut edge so it reads as a hem, not a staircase of voxels.
    boundary = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
    for _ in range(6):
        moved = {}
        for v in boundary:
            nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
            if len(nb) == 2:
                moved[v] = v.co * 0.4 + (nb[0].co + nb[1].co) * 0.3
        for v, co in moved.items():
            v.co = co
    bm.normal_update()
    for v in bm.verts:
        v.co = v.co + v.normal * thickness(v.co)
    if face_mat is not None:
        for f in bm.faces:
            f.material_index = face_mat(f.calc_center_median())
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if solid:
        # Give the shell a little depth so it doesn't vanish edge-on.
        obj = link(bpy.data.objects.new("tmp_shell", me))
        mod = obj.modifiers.new("solid", "SOLIDIFY")
        mod.thickness = 0.006
        mod.offset = -1.0
        mod.use_rim = True
        mod.use_quality_normals = True
        dg = bpy.context.evaluated_depsgraph_get()
        out = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(me)
        out.name = name
        me = out
    smooth_all(me)
    return me


def patch(src_me, name, center, half, thickness=0.006, front=True):
    """A flat-ish piece stuck to the surface (pocket, zip, badge): a shell of the faces
    inside a box around center (half = half sizes). front picks the +Y side."""
    c0 = Vector(center)

    def pred(c, n):
        d = c - c0
        if abs(d.x) > half[0] or abs(d.z) > half[2]:
            return False
        return (n.y > 0.2) if front else (n.y < -0.2)
    return shell(src_me, name, pred, lambda co: thickness)


# --------------------------------------------------------------------------------------
# Character
# --------------------------------------------------------------------------------------

class Character:
    def __init__(self, look):
        self.L = look
        self.b = Build(look)
        self.objects = []  # (obj, rigid_bone or None, candidate bones or None)
        self.face_objects = set()  # objects whose lower face follows the jaw and brows the brow bones
        L = look
        b = self.b
        self.M = {}
        hair = col(L["hair_color"])
        self.palette = {
            "skin": col(L["skin"]), "flush": col(L["flush"]), "lips": col("a8474a" if b.fem else "8a4a40"),
            "eye_white": col("f2ede2"), "eye_dark": col("1a1412"), "hair": hair, "beard": col(L["beard_color"]),
            "stubble": tuple(lerp(a, b_, 0.45) for a, b_ in zip(col(L["skin"]), col(L["beard_color"]))),
            "top": col(L["top_color"]), "trim": col(L["top_trim"]), "over": col(L["over_color"]),
            "trousers": col(L["trousers_color"]), "boots": col(L["boots_color"]), "hat": col(L["hat_color"]),
            "neckerchief": col(L["neckerchief_color"]), "metal": col("c8ccd4"), "leather": col("6b4a2a"),
            "dark": col("161616"), "white": col("ececec"), "socks": col("6a6a60"), "blood": col("7a0b0b"),
            "hivis_band": col("b9bcc4"), "brow": col(L["hair_color"] if L["hair"] != "BALD" else L["beard_color"]),
        }

    def m(self, name):
        return mat(name, self.palette[name])

    def add(self, name, me, materials, rigid=None, bones=None, face=False):
        smooth_all(me)
        obj = mesh_obj(name, me, [self.m(n) for n in materials])
        self.objects.append((obj, rigid, bones))
        if face:
            self.face_objects.add(name)
        return obj

    # --- Body ---------------------------------------------------------------------
    def build_body(self):
        b, L, p = self.b, self.L, self.b.p
        t, g = b.t, b.g
        tw, td = b.tw, b.td
        cr = b.chest_rot
        c0 = p["chest"]

        def cp(x, y, z):  # point in chest space (follows the stoop)
            return c0 + cr @ Vector((x, y, z))

        torso = [
            ellip(p["hips"] + Vector((0, -0.01, -0.03)), (b.hw * 0.52, td * 0.5, 0.13), stiff=2.0),
            ellip(p["spine"] + Vector((0, 0, 0.1)), (tw * 0.5, td * 0.5, 0.14), stiff=2.0),
            ellip(cp(0, 0, 0.17), (tw * 0.55, td * 0.55, 0.18), cr, stiff=2.0),
            ellip(cp(0, -0.01, 0.31), (b.shx + 0.03 * t, td * 0.46, 0.07), cr, stiff=2.0),
            capsule(p["neck"] + Vector((0, 0, -0.04)), p["head"] + Vector((0, 0, 0.04)), 0.055 * t + 0.02 * g, stiff=2.0),
        ]
        if b.belly > 0.05:
            torso.append(ellip(p["spine"] + Vector((0, td * 0.18 + 0.05 * b.belly, 0.08)),
                               (tw * 0.42, td * 0.35 + 0.1 * b.belly, 0.12 + 0.04 * b.belly), stiff=1.5))
        if b.fem:
            for s in (-1, 1):
                torso.append(ball(cp(0.07 * s, td * 0.32, 0.22), 0.065, stiff=1.2))
        torso_me = metaballs("torso", torso)
        tag_part(torso_me, PART_TORSO)
        parts = [(torso_me, 0)]

        limbs = []
        for s in "LR":
            hs = L["hand_size"]
            arm = [
                capsule(p["shoulder" + s], p["elbow" + s], 0.07 * t, 2.0),
                ball(p["shoulder" + s], 0.08 * t, 2.0),
                capsule(p["elbow" + s], p["wrist" + s] + (p["wrist" + s] - p["elbow" + s]).normalized() * 0.01, 0.058 * t, 2.0),
            ]
            limbs.append(("arm" + s, tag_part(metaballs("arm" + s, arm, resolution=0.013), PART_ARM_L if s == "L" else PART_ARM_R)))
            leg = [
                capsule(p["hip" + s] + Vector((0, 0, 0.04)), p["knee" + s], 0.09 * t * (0.9 + 0.1 * g), 2.0),
                capsule(p["knee" + s], p["ankle" + s], 0.072 * t, 2.0),
                ellip((p["ankle" + s] + p["toe" + s]) * 0.5 + Vector((0, 0.0, 0.0)), (0.065, 0.14, 0.055), stiff=2.0),
            ]
            limbs.append(("leg" + s, tag_part(metaballs("leg" + s, leg, resolution=0.016), PART_LEG_L if s == "L" else PART_LEG_R)))
        for _, me in limbs:
            parts.append((me, 0))

        body = join_meshes("Body", parts)
        self.body_dense = body.copy()
        # Material slots: 0 skin 1 top 2 trousers 3 boots 4 over 5 trim 6 socks
        mats = ["skin", "top", "trousers", "boots", "over", "trim", "socks"]
        waist_z = p["spine"].z + 0.04
        overalls = L["over"] == "OVERALLS"
        rugby = L["top"] == "RUGBY_SHIRT"
        part = body.attributes["part"].data
        for poly in body.polygons:
            c = poly.center
            pt = part[poly.vertices[0]].value
            mi = self.region(c, waist_z, rugby, pt)
            if overalls and mi == 2:
                mi = 4
            poly.material_index = mi
        body = decimate(body, 7000)
        self.body_me = decimate(self.body_dense, 10000)
        self.add("Body", body, mats)
        self.build_hands()

    def build_hands(self):
        """Proper hands with fingers, so fists clench, hands open to grab and fingers wrap a
        pint. A separate mesh (finer voxels than the arms), tucked into the sleeve."""
        parts = []
        for s in "LR":
            h = self.b.hand[s]
            w, k = h["palm"]
            d, fwd, inward = h["down"], h["fwd"], h["inward"]
            hs = self.L["hand_size"] * HAND_SCALE
            rot = Matrix((inward, fwd, d)).transposed()  # local x thick, y wide, z long
            fr = h["finger_r"]
            el = [ellip((w + k) * 0.5 + d * 0.004 * hs, (0.021 * hs, 0.038 * hs, 0.04 * hs), rot, stiff=2.0),
                  capsule(w - d * 0.02 * hs, w + d * 0.01 * hs, 0.03 * hs)]
            for name, a, b in h["fingers"]:
                el.append(capsule(a - d * 0.008 * hs, b, fr * (0.92 if name == "pinky" else 1.0)))
            ta, tb = h["thumb"]
            el.append(capsule(ta, tb, fr * 1.1))
            el.append(ellip(ta + (tb - ta) * 0.2, (0.016 * hs, 0.02 * hs, 0.022 * hs), rot))
            me = metaballs("hand" + s, el, resolution=0.0034, smooth=2)
            parts.append((tag_part(me, PART_HAND_L if s == "L" else PART_HAND_R), 0))
        hands = decimate(join_meshes("Hands", parts), 2600)
        self.add("Hands", hands, ["skin"])

    def region(self, c, waist_z, rugby, part):
        """Material index for a point on the body."""
        b, L, p = self.b, self.L, self.b.p
        # Head and neck
        if c.z > p["neck"].z + 0.02:
            return 0
        # Arms and hands
        if part in (PART_ARM_L, PART_ARM_R):
            s = "L" if part == PART_ARM_L else "R"
            sh, el, wr = p["shoulder" + s], p["elbow" + s], p["wrist" + s]
            if c.z < wr.z + 0.01:
                return 0
            if c.z > el.z:
                if rugby and abs(c.z - (sh.z + el.z) * 0.5) < 0.025:
                    return 5
                return 1
            if L["sleeves_rolled"] and c.z < el.z - 0.06:
                return 0
            return 1
        # Feet and lower legs
        if c.z < 0.13:
            return 3
        if c.z < p["knee" + "L"].z:
            if L["wellies"]:
                return 3
            if L["shorts"]:
                return 6 if c.z < 0.2 else 0
            return 2
        if c.z < waist_z:
            if L["top"] == "BOILER_SUIT":
                return 1
            if L["shorts"] and c.z < p["knee" + "L"].z + 0.18:
                return 2
            return 2
        # Torso
        if rugby:
            rel = c.z - waist_z
            if int(rel / 0.065) % 2 == 1:
                return 5
        return 1

    # --- Head -----------------------------------------------------------------------
    def build_head(self):
        b, L = self.b, self.L
        r, hc = b.r, b.head_c
        brow = L["brow"]
        fem = b.fem
        jaw_w = 0.74 if fem else 0.86
        el = [
            ellip(hc + Vector((0, -0.02 * r, 0.12 * r)), (r * 0.98, r * 1.04, r * 1.02)),
            ellip(hc + Vector((0, 0.22 * r, -0.45 * r)), (r * jaw_w, r * 0.72, r * 0.55), stiff=1.8),
            ellip(hc + Vector((0, 0.66 * r, 0.3 * r)), (r * 0.72, r * (0.16 + 0.1 * brow), r * (0.1 + 0.1 * brow) * (0.7 if fem else 1.0)), stiff=1.5),
            ball(hc + Vector((0, 0.66 * r, -0.72 * r)), r * 0.24, 1.6),
        ]
        for s in (-1, 1):
            el.append(ball(hc + Vector((0.48 * r * s, 0.55 * r, -0.12 * r)), r * 0.28, 1.3))
        head = metaballs("head", el, resolution=0.011)
        for poly in head.polygons:
            poly.material_index = 0
        tag_part(head, PART_HEAD)
        self.head_me = decimate(head.copy(), 4000)

        ears = []
        for s in (-1, 1):
            ears.append(ellip(hc + Vector((0.98 * r * s, -0.02 * r, -0.02 * r)), (r * 0.09, r * 0.2, r * 0.27), stiff=2.0))
        ears_me = tag_part(metaballs("ears", ears, resolution=0.006), PART_HEAD)
        nose_size = L["nose_size"]
        nose = metaballs("nose", [
            capsule(hc + Vector((0, 0.86 * r, 0.22 * r)), hc + Vector((0, 1.0 * r, -0.12 * r)), r * 0.1 * nose_size, 2.0),
            ellip(hc + Vector((0, 1.02 * r, -0.16 * r)), (r * 0.17 * nose_size, r * 0.16 * nose_size, r * 0.15 * nose_size)),
        ], resolution=0.005)
        lips = tag_part(metaballs("lips", [ellip(hc + Vector((0, 0.9 * r, -0.48 * r)), (r * 0.3, r * 0.07, r * (0.07 if fem else 0.05)))], resolution=0), PART_LIPS)
        brows = metaballs("brows", [
            capsule(hc + Vector((0.12 * r * s, (0.98 + 0.14 * brow) * r, (0.42 + 0.04 * brow) * r)),
                    hc + Vector((0.55 * r * s, (0.86 + 0.12 * brow) * r, (0.40 + 0.06 * brow) * r)), r * 0.065, 2.0)
            for s in (-1, 1)], resolution=0)
        tag_part(brows, PART_BROW)
        face = join_meshes("Head", [(decimate(head.copy(), 3000), 0), (ears_me, 0), (lips, 2), (brows, 3)])
        self.add("Face", face, ["skin", "flush", "lips", "brow"], bones=["Head", "Neck"], face=True)
        self.add("NoseMesh", nose, ["flush"], rigid="Nose")

        eyes = []
        for s in (-1, 1):
            c = hc + Vector((0.34 * r * s, 0.84 * r, 0.16 * r))
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=10, radius=r * 0.15)
            bmesh.ops.translate(bm, vec=c, verts=bm.verts)
            m1 = bpy.data.meshes.new("eye")
            bm.to_mesh(m1)
            bm.free()
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=r * 0.075)
            bmesh.ops.translate(bm, vec=c + Vector((0, r * 0.11, 0.0)), verts=bm.verts)
            m2 = bpy.data.meshes.new("pupil")
            bm.to_mesh(m2)
            bm.free()
            eyes += [(m1, 0), (m2, 1)]
        self.add("Eyes", join_meshes("Eyes", eyes), ["eye_white", "eye_dark"], rigid="Head")

        if L["glasses"]:
            parts = []
            for s in (-1, 1):
                parts.append((torus_mesh("lens", hc + Vector((0.36 * r * s, 0.97 * r, 0.16 * r)), r * 0.2, r * 0.025,
                                         rot=Matrix.Rotation(math.pi / 2, 3, "X")), 0))
                parts.append((box_mesh("arm", hc + Vector((0.6 * r * s, 0.4 * r, 0.2 * r)), (r * 0.03, r * 1.0, r * 0.04)), 0))
            parts.append((box_mesh("bridge", hc + Vector((0, 0.98 * r, 0.2 * r)), (r * 0.3, r * 0.03, r * 0.04)), 0))
            self.add("Glasses", join_meshes("Glasses", parts), ["dark"], rigid="Head")

    # --- Hair and beards --------------------------------------------------------------
    def hair_pred(self, front_z, back_z, side_cut=None, top_only=False):
        r, hc = self.b.r, self.b.head_c

        def pred(c, n):
            d = c - hc
            fy = max(-1.0, min(1.0, d.y / r))
            line = lerp(back_z, front_z, (fy + 1) * 0.5) * r
            if d.z < line:
                return False
            if d.y > 0.55 * r and d.z < 0.62 * r:
                return False  # never over the face
            if side_cut is not None and abs(d.x) > side_cut * r and d.z < 0.5 * r:
                return False
            if top_only and d.z < 0.55 * r:
                return False
            return True
        return pred

    def build_hair(self, styles):
        r, hc = self.b.r, self.b.head_c
        for style in styles:
            me = None
            extra = []
            if style == "BALD":
                def pred(c, n):
                    d = c - hc
                    return -0.45 * r < d.z < 0.25 * r and d.y < 0.35 * r and abs(d.x) > 0.25 * r or (-0.45 * r < d.z < 0.15 * r and d.y < -0.4 * r)
                me = shell(self.head_me, "hair", pred, lambda co: 0.01)
            elif style == "SHAVED":
                me = shell(self.head_me, "hair", self.hair_pred(0.55, -0.35), lambda co: 0.004, solid=False)
            elif style in ("SHORT", "SIDE_PARTING", "BUN", "PONYTAIL"):
                def th(co, style=style):
                    d = co - hc
                    base = 0.014 + 0.012 * max(0.0, d.z / r)
                    if style == "SIDE_PARTING" and d.x > 0 and d.y > 0:
                        base += 0.012
                    return base
                me = shell(self.head_me, "hair", self.hair_pred(0.58, -0.4), th)
                if self.b.fem:
                    extra.append(metaballs("locks", [
                        ellip(hc + Vector((0.86 * r * s, 0.2 * r, -0.15 * r)), (r * 0.2, r * 0.42, r * 0.62)) for s in (-1, 1)
                    ] + [ellip(hc + Vector((0, -0.55 * r, -0.2 * r)), (r * 0.9, r * 0.45, r * 0.7)),
                         ellip(hc + Vector((0.2 * r, 0.75 * r, 0.62 * r)), (r * 0.62, r * 0.25, r * 0.22), Matrix.Rotation(-0.35, 3, "Y"))],
                        resolution=0.01))
                if style == "BUN":
                    extra.append(metaballs("bun", [ball(hc + Vector((0, -0.75 * r, 0.75 * r)), r * 0.42)], resolution=0.01))
                if style == "PONYTAIL":
                    extra.append(metaballs("tail", [
                        capsule(hc + Vector((0, -0.95 * r, 0.45 * r)), hc + Vector((0, -1.2 * r, -0.9 * r)), r * 0.2),
                        ball(hc + Vector((0, -0.95 * r, 0.45 * r)), r * 0.22)], resolution=0.01))
            elif style == "MOP":
                def th(co):
                    d = co - hc
                    return 0.04 + 0.02 * max(0.0, d.z / r)
                me = shell(self.head_me, "hair", self.hair_pred(0.4, -0.75), th)
                extra.append(metaballs("fringe", [ellip(hc + Vector((0, 0.8 * r, 0.62 * r)), (r * 0.75, r * 0.25, r * 0.22))], resolution=0.01))
            elif style == "COMB_OVER":
                def pred(c, n):
                    d = c - hc
                    sides = -0.4 * r < d.z < 0.35 * r and d.y < 0.4 * r and abs(d.x) > 0.3 * r
                    back = -0.4 * r < d.z < 0.3 * r and d.y < -0.3 * r
                    strands = d.z > 0.75 * r and int((d.y / r + 2) * 6) % 2 == 0
                    return sides or back or strands
                me = shell(self.head_me, "hair", pred, lambda co: 0.008)
            elif style == "FLOPPY":
                def th(co):
                    d = co - hc
                    return 0.028 + 0.015 * max(0.0, d.z / r)
                me = shell(self.head_me, "hair", self.hair_pred(0.5, -0.5), th)
                extra.append(metaballs("fringe", [ellip(hc + Vector((-0.25 * r, 0.78 * r, 0.6 * r)), (r * 0.6, r * 0.22, r * 0.3),
                                                        Matrix.Rotation(0.4, 3, "Y"))], resolution=0.01))
            if me is None:
                continue
            parts = [(me, 0)] + [(e, 0) for e in extra]
            self.add("Hair_" + style, join_meshes("Hair_" + style, parts), ["hair"], rigid="Head")

    def build_beards(self, styles):
        r, hc = self.b.r, self.b.head_c
        for style in styles:
            pred = None
            th = None
            mats = ["beard"]
            if style == "NONE":
                continue
            if style in ("STUBBLE", "FULL"):
                def pred(c, n):
                    d = c - hc
                    if d.y < -0.05 * r or d.z > -0.08 * r:
                        return False
                    if d.y > 0.6 * r and -0.62 * r < d.z < -0.33 * r and abs(d.x) < 0.33 * r:
                        return False  # leave the mouth clear
                    return True
                th = (lambda co: 0.004) if style == "STUBBLE" else (lambda co: 0.03 + 0.03 * max(0.0, -(co - hc).z / r - 0.5))
            elif style == "GOATEE":
                def pred(c, n):
                    d = c - hc
                    return abs(d.x) < 0.3 * r and d.z < -0.6 * r and d.y > 0.3 * r or (abs(d.x) < 0.35 * r and -0.42 * r < d.z < -0.28 * r and d.y > 0.7 * r)
                th = lambda co: 0.02
            elif style == "MUTTON_CHOPS":
                def pred(c, n):
                    d = c - hc
                    chop = abs(d.x) > 0.5 * r and -0.65 * r < d.z < 0.2 * r and -0.15 * r < d.y < 0.75 * r
                    tache = abs(d.x) < 0.45 * r and -0.42 * r < d.z < -0.26 * r and d.y > 0.7 * r
                    return chop or tache
                th = lambda co: 0.03
            elif style == "MOUSTACHE":
                def pred(c, n):
                    d = c - hc
                    return abs(d.x) < 0.42 * r and -0.42 * r < d.z < -0.26 * r and d.y > 0.7 * r
                th = lambda co: 0.022
            me = shell(self.head_me, "beard", pred, th, solid=style != "STUBBLE")
            if me is not None:
                self.add("Beard_" + style, me, ["stubble"] if style == "STUBBLE" else mats, bones=["Head"], face=True)

    # --- Hats ---------------------------------------------------------------------
    def build_hats(self, styles):
        r, hc = self.b.r, self.b.head_c
        top = hc + Vector((0, 0, 0.9 * r))
        for style in styles:
            parts = []
            if style == "NONE":
                continue
            if style == "FLAT_CAP":
                parts.append((metaballs("crown", [ellip(top + Vector((0, 0.15 * r, -0.05 * r)), (r * 1.12, r * 1.22, r * 0.34),
                                                         Matrix.Rotation(-0.18, 3, "X"))], resolution=0.012), 0))
                parts.append((metaballs("peak", [ellip(hc + Vector((0, 1.08 * r, 0.62 * r)), (r * 0.72, r * 0.32, r * 0.06),
                                                       Matrix.Rotation(0.25, 3, "X"))], resolution=0.008), 0))
            elif style in ("BEANIE", "BOBBLE_HAT"):
                parts.append((shell(self.head_me, "beanie", self.hair_pred(0.62, -0.25), lambda co: 0.05), 0))
                parts.append((torus_mesh("band", hc + Vector((0, 0.0, 0.58 * r)), r * 1.0, r * 0.09,
                                         rot=Matrix.Rotation(-0.25, 3, "X")), 1))
                if style == "BOBBLE_HAT":
                    parts.append((metaballs("bobble", [ball(hc + Vector((0, 0, 1.45 * r)), r * 0.32)], resolution=0.01), 2))
            elif style == "TRILBY":
                tilt = Matrix.Rotation(0.15, 3, "Y") @ Matrix.Rotation(-0.1, 3, "X")
                base = hc + Vector((0.04 * r, 0, 0.55 * r))
                parts.append((cyl_mesh("brim", base, r * 1.75, r * 1.7, r * 0.06, 24, tilt), 0))
                parts.append((metaballs("crown", [ellip(base + tilt @ Vector((0, 0, r * 0.42)), (r * 0.92, r * 1.02, r * 0.5), tilt)],
                                        resolution=0.012), 0))
                parts.append((cyl_mesh("band", base + tilt @ Vector((0, 0, r * 0.13)), r * 0.98, r * 0.96, r * 0.16, 24, tilt), 1))
            elif style == "BASEBALL_CAP":
                parts.append((shell(self.head_me, "cap", self.hair_pred(0.6, -0.15), lambda co: 0.03), 0))
                parts.append((metaballs("peak", [ellip(hc + Vector((0, 1.2 * r, 0.55 * r)), (r * 0.6, r * 0.5, r * 0.05),
                                                       Matrix.Rotation(0.12, 3, "X"))], resolution=0.008), 0))
            elif style == "POLICE_HELMET":
                parts.append((metaballs("dome", [ellip(hc + Vector((0, 0.02 * r, 1.0 * r)), (r * 1.12, r * 1.26, r * 1.5)),
                                                 ball(hc + Vector((0, 0.02 * r, 2.45 * r)), r * 0.2)], resolution=0.012), 0))
                parts.append((cyl_mesh("brim", hc + Vector((0, 0, 0.32 * r)), r * 1.3, r * 1.2, r * 0.08, 24), 0))
                parts.append((box_mesh("badge", hc + Vector((0, 1.24 * r, 1.0 * r)), (r * 0.32, r * 0.05, r * 0.42),
                                       Matrix.Rotation(-0.15, 3, "X"), bevel=r * 0.03), 2))
            elif style == "POLICE_CAP":
                parts.append((cyl_mesh("crown", hc + Vector((0, 0.05 * r, 0.95 * r)), r * 1.08, r * 1.35, r * 0.4, 24,
                                       Matrix.Rotation(0.12, 3, "X")), 0))
                parts.append((cyl_mesh("band", hc + Vector((0, 0.03 * r, 0.7 * r)), r * 1.1, r * 1.1, r * 0.16, 24), 1))
                parts.append((metaballs("peak", [ellip(hc + Vector((0, 1.05 * r, 0.6 * r)), (r * 0.62, r * 0.36, r * 0.05),
                                                       Matrix.Rotation(0.35, 3, "X"))], resolution=0.008), 3))
                parts.append((box_mesh("badge", hc + Vector((0, 1.25 * r, 0.95 * r)), (r * 0.25, r * 0.04, r * 0.25)), 2))
            elif style == "HEADSCARF":
                parts.append((shell(self.head_me, "scarf", self.hair_pred(0.5, -0.6), lambda co: 0.025), 0))
            parts = [p for p in parts if p[0] is not None]
            self.add("Hat_" + style, join_meshes("Hat_" + style, parts), ["hat", "dark", "white", "dark"], rigid="Head")

    # --- Clothes ------------------------------------------------------------------
    def torso_pred(self, z_min, z_max, front=None, open_front=0.0, x_max=None, back=None):
        b = self.b
        p = b.p

        def pred(c, n):
            if not (z_min < c.z < z_max):
                return False
            for s in "LR":
                if abs(c.x) > abs(p["shoulder" + s].x) - 0.03 and c.z < p["shoulder" + s].z - 0.02:
                    return False  # arms
            if c.z < p["hips"].z - 0.12:
                return False
            if open_front > 0 and abs(c.x) < open_front and c.y > 0:
                return False
            if front is True and c.y < 0.02:
                return False
            if back is True and c.y > -0.02:
                return False
            if x_max is not None and abs(c.x) > x_max:
                return False
            return True
        return pred

    def build_clothes(self, tops):
        L, b, p = self.L, self.b, self.b.p
        body = self.body_me
        waist = p["spine"].z + 0.04
        chest_top = p["neck"].z - 0.04
        neck = p["neck"]
        r = b.r
        fixed = []  # (mesh, material name)

        def collar(color, h=0.05, open_v=True):
            def pred(c, n):
                d = c - neck
                if not (-0.05 < d.z < h * 0.7):
                    return False
                if (d.x * d.x + d.y * d.y) ** 0.5 > 0.075 * b.t + 0.035 * b.g + 0.02:
                    return False
                return not (open_v and c.y > 0.03 and abs(c.x) < 0.035)
            return shell(body, "collar", pred, lambda co: 0.018), color

        over = L["over"]
        if over == "GILET":
            fixed.append((shell(body, "gilet", self.torso_pred(waist - 0.1, chest_top + 0.02, open_front=0.03),
                                lambda co: 0.03 + 0.006 * math.sin((co.z - waist) * 70)), "over"))
            fixed.append(collar("over", 0.08, True))
        elif over == "WAISTCOAT":
            def pred(c, n):
                if self.torso_pred(waist - 0.12, chest_top - 0.06)(c, n):
                    # V neck
                    return not (c.y > 0 and abs(c.x) < 0.02 + max(0.0, (c.z - (waist + 0.12))) * 0.5)
                return False
            fixed.append((shell(body, "waistcoat", pred, lambda co: 0.016), "over"))
            for i in range(3):
                fixed.append((patch(body, "button", (0.035, 0, waist + 0.02 + i * 0.055), (0.012, 0, 0.012), 0.024), "metal"))
        elif over == "OVERALLS":
            fixed.append((shell(body, "bib", self.torso_pred(waist - 0.05, waist + 0.24, front=True, x_max=b.tw * 0.34),
                                lambda co: 0.012), "over"))
            for s in (-1, 1):
                def strap(c, n, s=s):
                    return waist < c.z < chest_top + 0.06 and abs(c.x - s * b.tw * 0.28) < 0.028 and self.torso_pred(0, 9)(c, n)
                fixed.append((shell(body, "strap", strap, lambda co: 0.012), "over"))
            fixed.append((patch(body, "pocket", (0, 0, waist + 0.14), (0.05, 0, 0.04), 0.02), "trim"))
        elif over == "HI_VIS":
            def band_mat(c):
                rel = c.z - waist
                return 1 if (0.06 < rel < 0.09 or 0.24 < rel < 0.27) else 0
            vest = shell(body, "vest", self.torso_pred(waist - 0.08, chest_top - 0.02), lambda co: 0.022, face_mat=band_mat)
            self.add("Vest", vest, ["over", "hivis_band"], bones=["Hips", "Spine", "Chest"])
            fixed.append((patch(body, "police_tag", (0, 0, chest_top - 0.09), (0.09, 0, 0.022), 0.03), "dark"))
        elif over == "APRON":
            fixed.append((shell(body, "apron", self.torso_pred(p["hips"].z - 0.12, waist + 0.24, front=True, x_max=b.tw * 0.4),
                                lambda co: 0.012), "over"))
            fixed.append((box_mesh("apron_skirt", Vector((0, b.td * 0.55 + 0.03, p["hips"].z - 0.3)), (b.hw * 0.95, 0.012, 0.36)), "over"))
        elif over == "BRACES":
            for s in (-1, 1):
                def strap(c, n, s=s):
                    return waist - 0.05 < c.z < chest_top + 0.08 and abs(c.x - s * b.tw * 0.24) < 0.018 and self.torso_pred(0, 9)(c, n)
                fixed.append((shell(body, "brace", strap, lambda co: 0.008), "over"))

        if L["tool_belt"]:
            def belt(c, n):
                return abs(c.z - (p["hips"].z + 0.03)) < 0.03 and self.torso_pred(0, 9)(c, n)
            fixed.append((shell(body, "belt", belt, lambda co: 0.022), "leather"))
            for s in (-1, 1):
                fixed.append((box_mesh("pouch", Vector((b.hw * 0.5 * s, 0.03, p["hips"].z - 0.04)), (0.1, 0.09, 0.12), bevel=0.01), "leather"))
            fixed.append((cyl_mesh("hammer_handle", Vector((b.hw * 0.62, -0.06, p["hips"].z - 0.12)), 0.014, 0.014, 0.24), "leather"))
            fixed.append((box_mesh("hammer_head", Vector((b.hw * 0.62, -0.06, p["hips"].z + 0.0)), (0.035, 0.11, 0.035)), "metal"))
        if L["neckerchief"]:
            fixed.append((torus_mesh("kerchief", neck + Vector((0, 0.01, -0.02)), 0.075 * b.t + 0.02 * b.g, 0.02), "neckerchief"))
            fixed.append((metaballs("knot", [ellip(neck + Vector((0, 0.09 * b.g + 0.02, -0.07)), (0.05, 0.02, 0.06))], resolution=0.006), "neckerchief"))
        if L["sleeves_rolled"]:
            for s in "LR":
                el = p["elbow" + s]
                fixed.append((torus_mesh("cuff", el + Vector((0, 0, -0.04)), 0.064 * b.t, 0.018), "top"))
        if L["top"] == "POLICE":
            for s in (-1, 1):
                fixed.append((box_mesh("epaulette", p["chest"] + b.chest_rot @ Vector((b.shx * 0.75 * s, 0, 0.385)), (0.1, 0.07, 0.015)), "top"))
            if L["hat"] == "POLICE_CAP":
                for s in "LR":
                    sh = p["shoulder" + s]
                    side = 1 if s == "R" else -1
                    for i in range(3):
                        fixed.append((box_mesh("stripe", sh + Vector((0.075 * b.t * side, 0, -0.09 - i * 0.03)), (0.01, 0.08, 0.012),
                                               Matrix.Rotation(0.4 * side, 3, "Y")), "white"))

        mats = []
        parts = []
        for me, mname in fixed:
            if me is None:
                continue
            if mname not in mats:
                mats.append(mname)
            parts.append((me, mats.index(mname)))
        if parts:
            self.add("Clothes", join_meshes("Clothes", parts), mats, bones=["Hips", "Spine", "Chest", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR"])

        # Top variants (detail pieces only, colours come from the body).
        for top in tops:
            parts = []
            if top in ("SHIRT", "BAR_SHIRT", "POLICE", "JUMPER"):
                c, _ = collar(None, 0.05, True)
                parts.append((c, 1 if top == "JUMPER" else 0))
            if top == "BAR_SHIRT":
                parts.append((metaballs("bow", [ellip(neck + Vector((0, 0.1 * b.g + 0.01, -0.05)), (0.05, 0.02, 0.025))], resolution=0.006), 1))
            if top == "BOILER_SUIT":
                c, _ = collar(None, 0.06, True)
                parts.append((c, 1))
                parts.append((patch(body, "zip", (0, 0, waist + 0.12), (0.006, 0, 0.2), 0.008), 2))
                parts.append((patch(body, "chest_pocket", (b.tw * 0.25, 0, chest_top - 0.1), (0.05, 0, 0.045), 0.01), 1))
            if top in ("FLEECE", "CAGOULE"):
                c, _ = collar(None, 0.09, False)
                parts.append((c, 0))
                parts.append((patch(body, "zip", (0, 0, waist + 0.12), (0.006, 0, 0.2), 0.008), 1))
                if top == "CAGOULE":
                    parts.append((torus_mesh("hood_roll", neck + Vector((0, -0.04, 0.0)), 0.1 * b.g + 0.02, 0.035), 0))
            if top == "WAX_JACKET":
                parts.append((shell(body, "jacket", self.torso_pred(p["hips"].z - 0.1, chest_top + 0.02, open_front=0.015),
                                    lambda co: 0.02), 0))
                c, _ = collar(None, 0.07, True)
                parts.append((c, 1))
                for s in (-1, 1):
                    parts.append((patch(body, "pocket", (b.tw * 0.3 * s, 0, waist - 0.04), (0.055, 0, 0.05), 0.035), 0))
            if top == "RUGBY_SHIRT":
                c, _ = collar(None, 0.07, True)
                parts.append((c, 3))
            if top == "HOODIE":
                parts.append((metaballs("hood", [ellip(neck + Vector((0, -0.09, -0.02)), (0.15 * b.g, 0.07, 0.07))], resolution=0.01), 0))
                parts.append((patch(body, "pocket", (0, 0, waist + 0.02), (b.tw * 0.27, 0, 0.06), 0.015), 0))
                for s in (-1, 1):
                    parts.append((cyl_mesh("string", neck + Vector((0.04 * s, 0.1 * b.g + 0.01, -0.1)), 0.006, 0.006, 0.12), 3))
            parts = [q for q in parts if q[0] is not None]
            if parts:
                self.add("Top_" + top, join_meshes("Top_" + top, parts), ["top", "trim", "metal", "white"],
                         bones=["Hips", "Spine", "Chest", "Neck"])

    # --- Blood ----------------------------------------------------------------------
    def build_blood(self):
        r, hc = self.b.r, self.b.head_c
        b = self.b
        drip = metaballs("drip", [capsule(hc + Vector((0.04 * r, 1.0 * r, -0.28 * r)), hc + Vector((0.06 * r, 0.95 * r, -0.62 * r)), r * 0.06),
                                  ball(hc + Vector((-0.06 * r, 1.0 * r, -0.3 * r)), r * 0.07)], resolution=0.005)
        self.add("Blood_Nose", drip, ["blood"], rigid="Head")

        def face(c, n):
            d = c - hc
            return d.y > 0.45 * r and -0.75 * r < d.z < -0.25 * r and abs(d.x) < 0.5 * r
        me = shell(self.head_me, "blood_face", face, lambda co: 0.004, solid=False)
        if me:
            self.add("Blood_Face", me, ["blood"], bones=["Head"], face=True)

        def cheek(c, n):
            d = c - hc
            return d.x > 0.35 * r and d.y > 0.2 * r and -0.3 * r < d.z < 0.35 * r
        me = shell(self.head_me, "blood_cheek", cheek, lambda co: 0.004, solid=False)
        if me:
            self.add("Blood_Cheek", me, ["blood"], rigid="Head")
        p = b.p

        def shirt(c, n):
            return c.y > 0.02 and abs(c.x + 0.02) < 0.09 * b.g and p["chest"].z + 0.1 < c.z < p["neck"].z - 0.03
        me = shell(self.body_me, "blood_shirt", shirt, lambda co: 0.035 if self.L["over"] in ("HI_VIS", "GILET") else 0.012, solid=False)
        if me:
            self.add("Blood_Shirt", me, ["blood"], bones=["Chest"])

    # --- Armature and weights ------------------------------------------------------------
    def build_armature(self, scale):
        arm_data = bpy.data.armatures.new("Armature")
        arm = link(bpy.data.objects.new("Armature", arm_data))
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        eb = {}
        for name, parent in BONES:
            head, tail = self.b.segments[name]
            bone = arm_data.edit_bones.new(name)
            bone.head = head * scale
            bone.tail = tail * scale
            bone.roll = 0.0
            if parent:
                bone.parent = eb[parent]
                bone.use_connect = False
            eb[name] = bone
        bpy.ops.object.mode_set(mode="OBJECT")
        return arm

    def weigh(self, obj, rigid, bones):
        me = obj.data
        names = [n for n, _ in BONES]
        groups = {n: obj.vertex_groups.new(name=n) for n in names}
        if rigid:
            groups[rigid].add(range(len(me.vertices)), 1.0, "REPLACE")
            return
        segs = self.b.segments
        p = self.b.p
        part = None
        if "part" in me.attributes:
            part = [d.value for d in me.attributes["part"].data]
        face = obj.name in self.face_objects
        for v in me.vertices:
            co = v.co
            cands = bones
            pt = part[v.index] if part is not None else 0
            if pt in PART_BONES:
                cands = PART_BONES[pt]
            if cands is None:
                cands = self.body_candidates(co)
            cands = expand_candidates(cands)
            ds = []
            for n in cands:
                a, bb = segs[n]
                ab = bb - a
                t = max(0.0, min(1.0, (co - a).dot(ab) / max(ab.length_squared, 1e-9)))
                d = (co - (a + ab * t)).length
                ds.append((d, n))
            ds.sort()
            ds = ds[:3]
            ws = [(1.0 / max(d, 0.01 if pt not in (PART_HAND_L, PART_HAND_R) else 0.002) ** 5, n) for d, n in ds]
            tot = sum(w for w, _ in ws)
            weights = {n: w / tot for w, n in ws}
            if face:
                self.face_weights(co, pt, weights)
            for n, w in weights.items():
                if w > 0.02:
                    groups[n].add([v.index], w, "REPLACE")

    def face_weights(self, co, pt, weights):
        """Moves some of the Head's weight to the jaw (chin, lower lip, beard) and the brows."""
        head = weights.get("Head", 0.0)
        if head <= 0.0:
            return
        r, hc = self.b.r, self.b.head_c
        d = co - hc
        if pt == PART_BROW:
            weights.pop("Head")
            weights["BrowL" if d.x < 0 else "BrowR"] = head
            return
        if pt == PART_LIPS:
            jaw = smoothstep(-0.46 * r, -0.52 * r, d.z)
        else:
            jaw = smoothstep(-0.3 * r, -0.62 * r, d.z) * smoothstep(-0.2 * r, 0.4 * r, d.y)
        brow = 0.0
        if pt == PART_HEAD and d.y > 0.5 * r:
            for s in "LR":
                a, b = self.b.segments["Brow" + s]
                ab = b - a
                t = max(0.0, min(1.0, (co - a).dot(ab) / ab.length_squared))
                dist = (co - (a + ab * t)).length
                f = 0.55 * smoothstep(0.2 * r, 0.06 * r, dist)
                if f > brow:
                    brow, brow_bone = f, "Brow" + s
        weights["Head"] = head * (1.0 - jaw - brow)
        if jaw > 0.0:
            weights["Jaw"] = weights.get("Jaw", 0.0) + head * jaw
        if brow > 0.0:
            weights[brow_bone] = weights.get(brow_bone, 0.0) + head * brow

    def body_candidates(self, co):
        p = self.b.p
        for s in "LR":
            if abs(co.x) > abs(p["shoulder" + s].x) - 0.035 and co.z > p["hips"].z - 0.05 and (s == "R") == (co.x > 0):
                return ["Chest", "Clavicle" + s, "Shoulder" + s, "Elbow" + s, "Hand" + s]
        if co.z < p["hips"].z - 0.06:
            s = "R" if co.x > 0 else "L"
            return ["Hips", "Hip" + s, "Knee" + s, "Foot" + s]
        if co.z > p["neck"].z - 0.03:
            return ["Chest", "Neck", "Head"]
        return ["Hips", "Spine", "Chest", "Neck"]

    def finish(self, path, keep_blend=False):
        scale = self.L["height"]
        arm = self.build_armature(scale)
        S = Matrix.Scale(scale, 4)
        for obj, rigid, bones in self.objects:
            self.weigh(obj, rigid, bones)
            obj.data.transform(S)
            obj.parent = arm
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = arm
            if obj.name.startswith("Blood_") or obj.name.startswith(("Hair_", "Beard_", "Hat_", "Top_")):
                pass  # Godot decides visibility; keep them visible in the file so they export.
        bpy.ops.object.select_all(action="SELECT")
        if keep_blend:
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "tools", "blender", "out", os.path.basename(path).replace(".glb", ".blend")))
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=False, export_apply=False,
            export_animations=False, export_skins=True, export_yup=True, export_materials="EXPORT",
            export_normals=True, export_tangents=False, export_texcoords=False, export_cameras=False,
            export_lights=False,
        )


def build(look_id, look, keep_blend=False):
    reset()
    MATS.clear()
    c = Character(look)
    c.build_body()
    c.build_head()
    v = look["variants"]
    c.build_hair(v["hair"])
    c.build_beards(v["beard"])
    c.build_hats(v["hat"])
    c.build_clothes(v["top"])
    c.build_blood()
    path = os.path.join(OUT_DIR, look_id + ".glb")
    c.finish(path, keep_blend)
    tris = sum(len(o.data.polygons) for o, _, _ in c.objects)
    print("built %s: %d faces, %d objects -> %s" % (look_id, tris, len(c.objects), path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    keep = "--blend" in argv
    ids = [a for a in argv if not a.startswith("--")]
    with open(LOOKS) as f:
        looks = json.load(f)
    for look_id in ids or list(looks):
        build(look_id, looks[look_id], keep)


main()
