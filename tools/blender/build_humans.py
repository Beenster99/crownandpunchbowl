"""Builds every character from the MakeHuman base mesh instead of the metaball sculpt.

    MH_DATA=/opt/mpfb/mpfb_data/data MH_ASSETS=/opt/mpfb/assets \\
        blender -b -P tools/blender/build_humans.py -- [ids...] [--blend]

Same outputs and contract as build_characters.py: one .glb per look in
assets/models/characters/, the shared bone names, named materials Godot recolours, and the
optional pieces Hair_<STYLE>, Beard_<STYLE>, Hat_<STYLE>, Top_<TYPE> and Blood_*.

The body is MakeHuman's (CC0): shaped from the look with MakeHuman's macro targets (gender,
age, muscle, weight, ethnicity) and detail targets (belly, nose, head), skinned with its
game-engine weights folded onto our bones, then put in our rest pose (arms hanging, the
look's stoop) so every existing animation fits. Clothes, hair, beards, hats, eyes, brows and
lashes are MakeHuman proxies (.mhclo) from the community asset packs (CC0 and CC-BY, see
CREDITS.md), fitted to the shaped body. Their textures are turned into greyscale detail maps
so Godot can tint them with the look's colours; the normal maps are kept.
"""

import importlib.util
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mh_human as mh  # noqa: E402

_spec = importlib.util.spec_from_file_location("build_characters", os.path.join(HERE, "build_characters.py"))
bc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bc)

ROOT = bc.ROOT
OUT_DIR = bc.OUT_DIR
TEX_DIR = os.path.join(HERE, "out", "tex")
ALL_BONES = bc.BONES + mh.EXTRA_BONES
STAND_HEIGHT = 1.80  # head top of a height-1.0 look, metres, before the look's height scale
DETAIL_MEAN = 0.8    # detail maps average this; Godot scales the tint up by 1 / DETAIL_MEAN

ARM_BONES = {b + s for s in "LR" for b in ("Clavicle", "Shoulder", "Elbow", "Hand", "Thumb1", "Thumb2", "Index1",
                                           "Index2", "Fingers1", "Fingers2", "Ring1", "Ring2", "Pinky1", "Pinky2")}
LEG_BONES = {b + s for s in "LR" for b in ("Hip", "Knee", "Foot")}

# --- What each look wears ---------------------------------------------------------------
TOPS_M = {
    "SHIRT": "male_casualsuit03", "JUMPER": "male_casualsuit02", "BOILER_SUIT": "elvs_male_coveralls_1",
    "WAX_JACKET": "male_casualsuit05", "FLEECE": "male_casualsuit04", "RUGBY_SHIRT": "male_casualsuit02",
    "POLICE": "male_casualsuit01", "BAR_SHIRT": "male_casualsuit06", "HOODIE": "male_casualsuit04",
    "CAGOULE": "male_casualsuit05",
}
TOP_F = "female_casualsuit01"
OVERALLS = "male_worksuit01"
HAIR = {
    "SHORT": "short02", "SIDE_PARTING": "short04", "MOP": "afro01", "FLOPPY": "short03", "COMB_OVER": "short01",
    "BUN": "ponytail01", "PONYTAIL": "ponytail01",
}
BEARDS = {
    "FULL": "grinsegold_full_beard", "GOATEE": "elvs_scruffy_beard1", "MUTTON_CHOPS": "culturalibre_faun_beard",
    "MOUSTACHE": "grinsegold_moustache",
}
HATS = {
    "FLAT_CAP": "elvs_male_flat_cap1", "BEANIE": "mindfront_knitted_hat_01", "TRILBY": "elvs_male_trilby_hat",
    "BASEBALL_CAP": "mindfront_patrol_cap", "POLICE_CAP": "mindfront_patrol_cap", "BOBBLE_HAT": "elvs_slouchy_beanie1",
}
BOOTS = {"tom", "gaz", "barrow", "kev", "mags", "rambler"}
SMART_SHOES = {"constable", "sergeant", "barman", "barwoman", "dicky"}
TRAINERS = {"local", "rugby_lad"}
EYES = {"tom": "brown", "gaz": "brownlight", "barrow": "grey", "mags": "green", "dicky": "lightblue",
        "kev": "brown", "rambler": "blue", "constable": "blue", "sergeant": "grey", "barman": "brown",
        "barwoman": "bluegreen"}


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def luminance(hexstr):
    c = bc.col(hexstr)
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def look_targets(L):
    """MakeHuman targets [(path, weight)] for a look."""
    fem = L["feminine"]
    old = clamp(L["stoop"] / 24.0) * 0.4 + (0.15 if luminance(L["hair_color"]) > 0.5 and L["hair"] != "BALD" else 0.0)
    if L["id"] == "barrow":
        old = 0.45
    age = 0.55 + old
    muscle = clamp(0.5 + (L["shoulders"] - 1.0) * 1.6 + (L["limb_thickness"] - 1.0) * 1.2)
    weight = clamp(0.5 + (L["girth"] - 1.0) * 1.8 + L["belly"] * 0.35)
    lum = luminance(L["skin"])
    african = clamp((0.32 - lum) * 4.0)
    caucasian = 1.0 - african
    t = mh.macro_targets(0.0 if fem else 1.0, age, muscle, weight, 0.5, 0.75, african, 0.0, caucasian)
    belly = L["belly"]
    if belly > 0.05:
        t.append(("stomach/stomach-pregnant-incr", belly * (0.55 if not fem else 0.3)))
    nose = L["nose_size"] - 1.0
    if abs(nose) > 0.02:
        d = "incr" if nose > 0 else "decr"
        for n in ("nose-scale-horiz", "nose-scale-vert", "nose-scale-depth", "nose-volume"):
            t.append(("nose/%s-%s" % (n, d), min(abs(nose) * 1.2, 1.0)))
        if nose > 0.3:
            t.append(("nose/nose-flaring-incr", 0.6))
    head = L["head_size"] - 1.0
    if abs(head) > 0.02:
        d = "incr" if head > 0 else "decr"
        for n in ("head-scale-horiz", "head-scale-vert", "head-scale-depth"):
            t.append(("head/%s-%s" % (n, d), min(abs(head) * 3.0, 1.0)))
    if L["brow"] > 0.5:
        t.append(("forehead/forehead-nubian-incr", min(L["brow"] - 0.5, 1.0)))
    return t


def look_age(L):
    if L["id"] in ("barrow", "dicky", "sergeant") or L["stoop"] > 12:
        return "old"
    if L["id"] in ("rugby_lad", "local", "barwoman", "constable", "gaz"):
        return "young"
    return "middleage"


# --- Textures -----------------------------------------------------------------------------

def read_mhmat(path):
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.split("#", 1)[0].split()
            if len(p) >= 2 and p[0] not in out:
                out[p[0]] = " ".join(p[1:])
    return out


def mat_textures(mhmat_path):
    """(diffuse, normal) texture paths named by a .mhmat, where they exist."""
    m = read_mhmat(mhmat_path)
    d = os.path.dirname(mhmat_path) if mhmat_path else ""
    out = []
    for key in ("diffuseTexture", "normalmapTexture"):
        p = os.path.join(d, m[key]) if key in m else None
        out.append(p if p and os.path.exists(p) else None)
    return tuple(out)


def texture(path, size, mode):
    """A processed copy of a texture, cached in tools/blender/out/tex.
    detail: greyscale averaging DETAIL_MEAN (alpha kept) for Godot to tint with the look's colour.
    keep: the colours as they are. normal: a normal map."""
    if not path:
        return None
    os.makedirs(TEX_DIR, exist_ok=True)
    stem = os.path.splitext(os.path.basename(path))[0]
    img = None
    alpha = False
    if mode != "normal":
        img = bpy.data.images.load(path, check_existing=False)
        alpha = img.channels == 4 and _has_alpha(img)
    ext = ".png" if alpha else ".jpg"
    out = os.path.join(TEX_DIR, "%s_%s_%d%s" % (stem, mode, size, ext))
    if os.path.exists(out):
        if img:
            bpy.data.images.remove(img)
        return out
    if img is None:
        img = bpy.data.images.load(path, check_existing=False)
    if img.size[0] > size or img.size[1] > size:
        img.scale(min(size, img.size[0]), min(size, img.size[1]))
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    if mode in ("detail", "fabric"):
        lum = px[:, 0] * 0.2126 + px[:, 1] * 0.7152 + px[:, 2] * 0.0722
        solid = px[:, 3] > 0.5
        if mode == "fabric":
            # Divide out the large shapes (printed logos, two-tone panels) so one colour
            # tints the whole garment, keeping the weave, seams and creases.
            grid = lum.reshape(h, w)
            mask = solid.reshape(h, w).astype(np.float32)
            rad = max(4, w // 64)
            local = _box_blur(grid * mask, rad) / np.maximum(_box_blur(mask, rad), 1e-3)
            ratio = np.clip(grid / np.maximum(local, 0.03), 0.72, 1.12)
            prints = _prints_mask(stem, w, h)
            if prints is not None:
                ratio[prints] = 1.0
            v = np.clip(DETAIL_MEAN * ratio, 0.0, 1.0).ravel()
        else:
            mean = float(lum[solid].mean()) if solid.any() else float(lum.mean())
            v = np.clip(lum * (DETAIL_MEAN / max(mean, 1e-3)), 0.0, 1.0)
        px[:, 0] = v
        px[:, 1] = v
        px[:, 2] = v
    if mode == "normal":
        # Soften: keeps the folds, blurs printed-on details (the logo embossed on some
        # MakeHuman T-shirts) into nothing much.
        prints = _prints_mask(stem, w, h)
        for ch, flat in zip(range(3), (0.5, 0.5, 1.0)):
            a = _box_blur(px[:, ch].reshape(h, w), max(2, w // 128))
            if prints is not None:
                a[prints] = flat
            px[:, ch] = a.ravel()
    if not alpha:
        px[:, 3] = 1.0
    new = bpy.data.images.new(stem + "_" + mode, w, h, alpha=alpha)
    new.pixels.foreach_set(px.ravel())
    new.filepath_raw = out
    new.file_format = "PNG" if alpha else "JPEG"
    scene = bpy.context.scene
    scene.render.image_settings.quality = 88
    new.save()
    bpy.data.images.remove(new)
    bpy.data.images.remove(img)
    return out


def _box_blur(a, r):
    """Separable box blur of a 2D array with radius r (edges clamped)."""
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
        lo = np.take(c, np.arange(0, n), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def _has_alpha(img):
    px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    return bool((px[3::4] < 0.9).any())


# Printed MakeHuman logos on some of the stock T-shirts: (u0, v0, u1, v1), v from the top.
# Painted out of the colour and normal maps so the shirts read as plain.
PRINTS = {
    "male_casualsuit02": [(0.48, 0.06, 0.64, 0.24)],
    "male_casualsuit04": [(0.47, 0.05, 0.63, 0.24)],
    "male_casualsuit06": [(0.18, 0.08, 0.35, 0.2), (0.43, 0.08, 0.64, 0.2), (0.7, 0.1, 0.78, 0.18)],
    "female_casualsuit01": [(0.68, 0.13, 0.9, 0.35)],
}


def _prints_mask(stem, w, h):
    for key, rects in PRINTS.items():
        if stem.startswith(key):
            m = np.zeros((h, w), dtype=bool)
            for u0, v0, u1, v1 in rects:
                m[int((1 - v1) * h):int((1 - v0) * h), int(u0 * w):int(u1 * w)] = True
            return m
    return None


MAT_CACHE = {}


def tex_mat(name, diffuse=None, normal=None, mode="detail", size=1024, alpha=False):
    """A material named for Godot's palette, with the processed textures. Untextured falls
    back to the plain shared material."""
    d = texture(diffuse, size, mode) if diffuse else None
    if not d:
        return bc.mat(name, (1, 1, 1, 1))
    n = texture(normal, min(size, 1024), "normal") if normal else None
    key = (name, d, n)
    if key in MAT_CACHE:
        return MAT_CACHE[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.8
    im = nt.nodes.new("ShaderNodeTexImage")
    im.image = bpy.data.images.load(d, check_existing=True)
    nt.links.new(im.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(im.outputs["Alpha"], bsdf.inputs["Alpha"])
    if n:
        nim = nt.nodes.new("ShaderNodeTexImage")
        nim.image = bpy.data.images.load(n, check_existing=True)
        nim.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nim.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    MAT_CACHE[key] = m
    return m


# --- The human ----------------------------------------------------------------------------

class Human:
    def __init__(self, look_id, look):
        self.id = look_id
        self.L = look
        self.co = mh.shaped(look_targets(look))
        base = mh.Base.get()
        # Metres, z up, facing +y, feet on the floor, scaled to the standard height.
        b = [mh.to_b(*c) for c in self.co]
        body = base.group_verts["body"]
        self.zmin = min(b[i].z for i in body)
        zmax = max(b[i].z for i in body)
        self.k = STAND_HEIGHT / (zmax - self.zmin)
        self.b = [self.ours(v) for v in b]
        self.weights = mh.skin_weights()
        self.objects = []        # (obj, weights by vertex index)
        self.top_deletes = []    # body vertices each top variant hides
        self.always_delete = set()
        self.body = None
        self.tops = {}

    def ours(self, v):
        return Vector((v.x * self.k, v.y * self.k, (v.z - self.zmin) * self.k))

    def jp(self, name):
        """A joint's position in our space."""
        return self.ours(mh.to_b(*mh.joint(self.co, name)))

    # --- Body -------------------------------------------------------------------------
    def build_body(self):
        base = mh.Base.get()
        bm = bmesh.new()
        verts = [bm.verts.new(v) for v in self.b]
        bm.verts.ensure_lookup_table()
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for vs, ts, g in base.faces:
            if g != "body":
                continue
            try:
                f = bm.faces.new([verts[i] for i in vs])
            except ValueError:
                continue
            for loop, ti in zip(f.loops, ts):
                if ti >= 0:
                    loop[uv_layer].uv = base.uv[ti]
        me = bpy.data.meshes.new("Body")
        bm.to_mesh(me)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        obj = bc.link(bpy.data.objects.new("Body", me))
        fem = "female" if self.L["feminine"] else "male"
        race = "african" if luminance(self.L["skin"]) < 0.25 else "caucasian"
        skin = os.path.join(mh.MH_ASSETS, "skins", "%s_%s_%s" % (look_age(self.L), race, fem))
        mhmat = os.path.join(skin, os.path.basename(skin) + ".mhmat")
        diffuse, normal = mat_textures(mhmat)
        obj.data.materials.append(tex_mat("skin", diffuse, normal, "detail", 1024))
        self.objects.append((obj, self.weights))
        self.body = obj
        return obj

    # --- Proxies ----------------------------------------------------------------------
    def proxy(self, asset, obj_name, mat_name, mode="detail", size=1024, alpha=False, mhmat=None):
        path = mh.find_proxy(asset)
        if not path:
            print("WARNING: no proxy", asset)
            return None
        p = mh.Proxy(path)
        if mhmat:
            p.material = mhmat
        pts = [self.ours(mh.to_b(*c)) for c in p.fit(self.co)]
        faces, uvs = p.mesh_data()
        bm = bmesh.new()
        verts = [bm.verts.new(v) for v in pts]
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for vs, ts in faces:
            try:
                f = bm.faces.new([verts[i] for i in vs])
            except (ValueError, IndexError):
                continue
            for loop, ti in zip(f.loops, ts):
                if 0 <= ti < len(uvs):
                    loop[uv_layer].uv = uvs[ti]
        me = bpy.data.meshes.new(obj_name)
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = True
        obj = bc.link(bpy.data.objects.new(obj_name, me))
        diffuse, normal = mat_textures(p.material)
        obj.data.materials.append(tex_mat(mat_name, diffuse, normal, mode, size, alpha))
        weights = p.weights(self.weights)
        for d in weights:
            if not d:
                d["Head"] = 1.0
        self.objects.append((obj, weights))
        return obj, p

    def dress(self):
        L = self.L
        fem = L["feminine"]
        tops = L["variants"].get("top") or [L["top"]]
        for top in tops:
            if L["over"] == "OVERALLS":
                got = self.proxy(OVERALLS, "Top_" + top, "keep_worksuit", "keep")
                if got:
                    self.tops[top] = got[0]
                    self.top_deletes.append(got[1].delete)
                continue
            got = self.proxy(TOP_F if fem else TOPS_M.get(top, "male_casualsuit03"), "Top_" + top, "top", "fabric")
            if not got:
                continue
            obj, p = got
            self.tops[top] = obj
            self.top_deletes.append(p.delete)
            self._split_top(obj, p)
        if self.id in BOOTS:
            shoes = "shoes03"
        elif self.id in SMART_SHOES:
            shoes = "shoes04"
        elif self.id in TRAINERS:
            shoes = "shoes06"
        else:
            shoes = "shoes01"
        got = self.proxy(shoes, "Shoes", "boots")
        if got:
            self.always_delete |= got[1].delete
        for style in L["variants"].get("hair") or [L["hair"]]:
            if style in HAIR:
                self.proxy(HAIR[style], "Hair_" + style, "hair", "detail", 1024, alpha=True)
        for style in L["variants"].get("beard") or [L["beard"]]:
            if style in BEARDS:
                self.proxy(BEARDS[style], "Beard_" + style, "beard", "detail", 512, alpha=True)
        for style in L["variants"].get("hat") or [L["hat"]]:
            if style in HATS:
                self.proxy(HATS[style], "Hat_" + style, "hat", "fabric", 512)
        colour = EYES.get(self.id, "brown")
        self.proxy("low-poly", "Eyes", "eyes", "keep", 256,
                   mhmat=os.path.join(mh.MH_ASSETS, "eyes", "materials", colour + ".mhmat"))
        self.proxy("eyebrow006" if fem else "eyebrow001", "Brows", "brow", "detail", 256, alpha=True)
        self.proxy("eyelashes02" if fem else "eyelashes01", "Lashes", "lashes", "detail", 256, alpha=True)
        self._tuck_hair_under_hat()
        if L["glasses"]:
            self.proxy("frankyaye_glasses_library_male", "Glasses", "dark", "keep", 256)

    def _tuck_hair_under_hat(self):
        """When the look always wears a hat, pull the hair that would poke through it back
        inside, along the line from the middle of the head."""
        hats = self.L["variants"].get("hat") or [self.L["hat"]]
        if "NONE" in hats:
            return
        from mathutils.bvhtree import BVHTree
        hat_objs = [o for o, _ in self.objects if o.name.startswith("Hat_")]
        hair_objs = [o for o, _ in self.objects if o.name.startswith("Hair_")]
        if not hat_objs or not hair_objs:
            return
        centre = self.jp("joint-head").lerp(self.jp("joint-head-2"), 0.45)
        for hat in hat_objs:
            bvh = BVHTree.FromObject(hat, bpy.context.evaluated_depsgraph_get())
            for hair in hair_objs:
                for v in hair.data.vertices:
                    d = v.co - centre
                    dist = d.length
                    if dist < 1e-4:
                        continue
                    hit = bvh.ray_cast(centre, d / dist, dist + 0.2)
                    if hit[0] is not None:
                        lim = (hit[0] - centre).length * 0.96
                        if dist > lim:
                            v.co = centre + d / dist * lim

    def _split_top(self, obj, p):
        """Suits are one mesh: give the trouser half its own material so it takes the look's
        trouser colour."""
        me = obj.data
        me.materials.append(tex_mat("trousers", *mat_textures(p.material), "fabric", 1024))
        waist = self.jp("joint-pelvis").lerp(self.jp("joint-spine-3"), 0.5).z
        weights = p.weights(self.weights)
        for poly in me.polygons:
            tot = {}
            for vi in poly.vertices:
                for bone, w in weights[vi].items():
                    tot[bone] = tot.get(bone, 0.0) + w
            arm = sum(w for b, w in tot.items() if b in ARM_BONES)
            leg = sum(w for b, w in tot.items() if b in LEG_BONES)
            rest = sum(tot.values()) - arm - leg
            if arm >= max(leg, rest):
                poly.material_index = 0
            elif leg >= rest:
                poly.material_index = 1
            else:
                poly.material_index = 1 if poly.center.z < waist else 0

    def hide_body_under_clothes(self):
        """Deletes the body faces every top variant (and the shoes) cover, so skin can't poke
        through. Runs before the rest pose, while vertex indices are still MakeHuman's."""
        hide = set(self.always_delete)
        if self.top_deletes:
            common = set(self.top_deletes[0])
            for d in self.top_deletes[1:]:
                common &= d
            hide |= common
        if not hide:
            return
        me = self.body.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        dead = [f for f in bm.faces if any(v.index in hide for v in f.verts)]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.to_mesh(me)
        bm.free()

    def cleanup(self):
        """Drops the helper vertices (no faces) the body was built with."""
        me = self.body.data
        bm = bmesh.new()
        bm.from_mesh(me)
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(me)
        bm.free()

    # --- Armature ---------------------------------------------------------------------
    def build_armature(self):
        arm_data = bpy.data.armatures.new("Armature")
        arm = bc.link(bpy.data.objects.new("Armature", arm_data))
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        eb = {}
        heads = {}
        for name, parent in ALL_BONES:
            if name in mh.JOINTS:
                h, t = mh.JOINTS[name]
                hp, tp = self.jp(h), self.jp(t)
            else:
                hp, tp = self._face_bone(name)
            heads[name] = (hp, tp)
        for name, parent in ALL_BONES:
            hp, tp = heads[name]
            b = arm_data.edit_bones.new(name)
            b.head, b.tail = hp, tp
            if (tp - hp).length < 1e-4:
                b.tail = hp + Vector((0, 0, 0.02))
            if parent:
                b.parent = eb[parent]
            eb[name] = b
        bpy.ops.object.mode_set(mode="OBJECT")
        self.arm = arm
        return arm

    def _face_bone(self, name):
        hp = self.jp("joint-head")
        top = self.jp("joint-head-2")
        r = (top - hp).length
        mouth = self.jp("joint-mouth")
        if name == "Jaw":
            return (mouth + Vector((0, -0.35 * r, 0.12 * r)), mouth + Vector((0, 0.2 * r, -0.25 * r)))
        if name == "Nose":
            nose = self._front_point(hp.z + 0.42 * r)
            return (nose + Vector((0, -0.08 * r, 0)), nose + Vector((0, 0.06 * r, -0.02 * r)))
        side = -1 if name.endswith("L") else 1
        brow = self._front_point(hp.z + 0.72 * r, 0.12 * r * side)
        return (brow + Vector((0.18 * r * side, -0.05 * r, 0)), brow)

    def _front_point(self, z, x=0.0):
        """The most forward body vertex near height z and side x (on the face)."""
        best = None
        for i in mh.Base.get().group_verts["body"]:
            v = self.b[i]
            if abs(v.z - z) < 0.012 and abs(v.x - x) < 0.015 and (best is None or v.y > best.y):
                best = v
        return best.copy() if best else Vector((x, 0.1, z))

    # --- Skinning ---------------------------------------------------------------------
    def skin(self, obj, weights):
        names = [n for n, _ in ALL_BONES]
        groups = {n: obj.vertex_groups.new(name=n) for n in names}
        for vi, d in (weights.items() if isinstance(weights, dict) else enumerate(weights)):
            if vi >= len(obj.data.vertices):
                continue
            for bone, w in d.items():
                if w > 0.005 and bone in groups:
                    groups[bone].add([vi], w, "REPLACE")
        obj.parent = self.arm
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = self.arm

    # --- Rest pose: arms hanging, the look's stoop --------------------------------------
    def set_rest_pose(self):
        """MakeHuman stands in an A-pose. Our animations are keyed from arms hanging at the
        sides (6 degrees out), so pose the arms down and make that the rest pose, and bend
        the spine forward by the look's stoop."""
        arm = self.arm
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="POSE")
        stoop = math.radians(self.L["stoop"])
        for bone_name, amount in (("Spine", 0.3), ("Spine2", 0.3), ("Chest", 0.4)):
            pb = arm.pose.bones[bone_name]
            pb.rotation_mode = "QUATERNION"
            self._rotate_world(pb, Matrix.Rotation(-stoop * amount, 4, "X"))
            bpy.context.view_layer.update()
        for s, side in (("L", -1), ("R", 1)):
            for bone_name in ("Shoulder" + s, "Elbow" + s, "Hand" + s):
                pb = arm.pose.bones[bone_name]
                pb.rotation_mode = "QUATERNION"
                head = arm.matrix_world @ pb.head
                tail = arm.matrix_world @ pb.tail
                cur = (tail - head).normalized()
                a = math.radians(6) * side
                want = Vector((math.sin(a), 0.0, -math.cos(a)))
                if bone_name.startswith("Hand"):
                    want = Vector((math.sin(a) * 0.6, 0.02, -1.0)).normalized()
                q = cur.rotation_difference(want)
                self._rotate_world(pb, q.to_matrix().to_4x4())
                bpy.context.view_layer.update()
        # Turn each hand so the palm faces the thigh with the knuckles in a line from front
        # (index) to back (little finger), which is how the finger curls are keyed.
        for s in "LR":
            pb = arm.pose.bones["Hand" + s]
            axis = (pb.tail - pb.head).normalized()
            idx = arm.pose.bones["Index1" + s].head
            mid = arm.pose.bones["Fingers1" + s].head
            cur = idx - mid
            cur = (cur - axis * cur.dot(axis)).normalized()
            want = Vector((0, 1, 0))
            want = (want - axis * want.dot(axis)).normalized()
            ang = cur.angle(want)
            if cur.cross(want).dot(axis) < 0:
                ang = -ang
            self._rotate_world(pb, Quaternion(axis, ang).to_matrix().to_4x4())
            bpy.context.view_layer.update()
        bpy.ops.object.mode_set(mode="OBJECT")
        # Bake the pose into the meshes, then make it the rest pose.
        for obj, _ in self.objects:
            bpy.context.view_layer.objects.active = obj
            mod = obj.modifiers["Armature"]
            bpy.ops.object.modifier_apply(modifier=mod.name)
            m2 = obj.modifiers.new("Armature", "ARMATURE")
            m2.object = arm
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="POSE")
        bpy.ops.pose.armature_apply(selected=False)
        bpy.ops.object.mode_set(mode="OBJECT")

    def _rotate_world(self, pb, R):
        """Rotate a pose bone by world rotation R about its head."""
        M = pb.matrix.copy()
        loc = M.to_translation()
        new = Matrix.Translation(loc) @ R @ Matrix.Translation(-loc) @ M
        pb.matrix = new

    # --- Landmarks in the rest pose ------------------------------------------------------
    def bone(self, name, tail=False):
        b = self.arm.data.bones[name]
        return (b.tail_local if tail else b.head_local).copy()

    def head_frame(self):
        """(centre, radius) of the skull in the rest pose."""
        h, t = self.bone("Head"), self.bone("Head", True)
        r = (t - h).length * 0.55
        return h.lerp(t, 0.5) + Vector((0, 0.08 * r, 0)), r

    def mouth(self):
        """Middle of the lips: the front-most face vertex at the jaw bone's level."""
        jaw = self.bone("Jaw")
        best = None
        for v in self.body.data.vertices:
            c = v.co
            if abs(c.x) < 0.006 and abs(c.z - jaw.z) < 0.03 and c.y > jaw.y and (best is None or c.y > best.y):
                best = c
        return best.copy() if best else jaw

    # --- Shells: pieces cut from a surface and pushed out -------------------------------
    def shell(self, src, name, pred, offset, materials, mat_fn=None, solid=0.006, rigid=None, cuts=0):
        """Copies the faces of src that pass pred(centre, normal, dominant bone), pushes them out
        by offset metres along the normals, keeps the source's skin weights."""
        bm = bmesh.new()
        bm.from_mesh(src.data)
        if cuts:
            # Finer faces first, so the cut edge follows the shape instead of the cloth's grid.
            bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
        bm.normal_update()
        deform = bm.verts.layers.deform.active
        names = {vg.index: vg.name for vg in src.vertex_groups}

        def dominant(f):
            tot = {}
            if deform is None:
                return ""
            for v in f.verts:
                for gi, w in v[deform].items():
                    tot[gi] = tot.get(gi, 0.0) + w
            return names.get(max(tot, key=tot.get), "") if tot else ""
        keep = set(f for f in bm.faces if pred(f.calc_center_median(), f.normal, dominant(f)))
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in keep], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        if not bm.faces:
            bm.free()
            return None
        boundary = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
        for _ in range(4):
            moved = {}
            for v in boundary:
                nb = [e.other_vert(v) for e in v.link_edges if e.is_boundary]
                if len(nb) == 2:
                    moved[v] = v.co * 0.4 + (nb[0].co + nb[1].co) * 0.3
            for v, co in moved.items():
                v.co = co
        bm.normal_update()
        for v in bm.verts:
            v.co = v.co + v.normal * (offset(v.co) if callable(offset) else offset)
        for f in bm.faces:
            f.material_index = mat_fn(f.calc_center_median()) if mat_fn else 0
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.clear()
        for m in materials:
            me.materials.append(m)
        for poly in me.polygons:
            poly.use_smooth = True
        obj = bc.link(bpy.data.objects.new(name, me))
        if not obj.vertex_groups:
            for gi in sorted(names):
                obj.vertex_groups.new(name=names[gi])
        if rigid:
            for vg in list(obj.vertex_groups):
                obj.vertex_groups.remove(vg)
            g = obj.vertex_groups.new(name=rigid)
            g.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        if solid:
            mod = obj.modifiers.new("solid", "SOLIDIFY")
            mod.thickness = solid
            mod.offset = -1.0
            mod.use_rim = True
        obj.parent = self.arm
        a = obj.modifiers.new("Armature", "ARMATURE")
        a.object = self.arm
        self.objects.append((obj, None))
        return obj

    def rigid(self, name, me, materials, bone):
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        for m in materials:
            me.materials.append(m)
        obj = bc.link(bpy.data.objects.new(name, me))
        g = obj.vertex_groups.new(name=bone)
        g.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        obj.parent = self.arm
        a = obj.modifiers.new("Armature", "ARMATURE")
        a.object = self.arm
        self.objects.append((obj, None))
        return obj

    def build_shells(self):
        L = self.L
        hc, r = self.head_frame()
        neck = self.bone("Neck")
        chest = self.bone("Chest")
        hips = self.bone("Hips")
        waist = hips.lerp(self.bone("Spine2"), 0.5).z
        shoulder_z = self.bone("ShoulderL").z
        knee_z = self.bone("KneeL").z
        body = self.body
        head_bones = ("Head", "Jaw", "Nose", "BrowL", "BrowR")
        mouth = self.mouth()
        print("head r %.3f, mouth %s, head centre %s" % (r, tuple(round(x, 3) for x in mouth), tuple(round(x, 3) for x in hc)))

        # Stubble: the jaw, chin and upper lip, a whisker above the skin.
        for style in L["variants"].get("beard") or [L["beard"]]:
            if style == "STUBBLE":
                def stubble(c, n, dom):
                    if dom not in head_bones + ("Neck",):
                        return False
                    if c.z > mouth.z + 0.022 or c.z < neck.z + 0.015 or c.y < hc.y - 0.35 * r:
                        return False
                    # Not the lips.
                    return not (abs(c.x) < 0.028 and mouth.z - 0.013 < c.z < mouth.z + 0.009 and c.y > mouth.y - 0.012)
                self.shell(body, "Beard_STUBBLE", stubble, 0.002, [bc.mat("stubble", (1, 1, 1, 1))], solid=0)
        # A shaved head: the scalp, a whisker above the skin.
        for style in L["variants"].get("hair") or [L["hair"]]:
            if style == "SHAVED":
                def scalp(c, n, dom):
                    d = c - hc
                    if dom not in head_bones:
                        return False
                    if abs(d.x) > 0.8 * r and d.z < 0.45 * r:
                        return False  # the ears
                    if d.y > 0.45 * r:
                        return d.z > 0.62 * r  # the hairline
                    return d.z > (-0.1 * r if d.y < -0.3 * r else 0.12 * r)
                self.shell(body, "Hair_SHAVED", scalp, 0.003, [bc.mat("hair", (1, 1, 1, 1))], solid=0)
        for style in L["variants"].get("hat") or [L["hat"]]:
            if style == "POLICE_HELMET":
                self.custodian_helmet(hc, r)

        top = next(iter(self.tops.values()), None)
        over = L["over"]
        if top is not None and over in ("GILET", "HI_VIS", "WAISTCOAT", "APRON", "BRACES"):
            over_m = bc.mat("over", (1, 1, 1, 1))
            band_m = bc.mat("hivis_band", (1, 1, 1, 1))

            def torso(c, n, dom):
                return dom not in ARM_BONES and dom not in LEG_BONES and waist - 0.12 < c.z < neck.z - 0.02
            if over in ("GILET", "HI_VIS"):
                bands = (waist + 0.02, chest.z + 0.02)

                def band(c):
                    return 1 if over == "HI_VIS" and any(abs(c.z - b) < 0.022 for b in bands) else 0
                self.shell(top, "Over", torso, 0.014, [over_m, band_m], band, cuts=1)
            elif over == "WAISTCOAT":
                def waistcoat(c, n, dom):
                    if not torso(c, n, dom) or c.z > neck.z - 0.06:
                        return False
                    # The V of the opening, from the breastbone to the neck.
                    v = 0.015 + max(0.0, (c.z - chest.z + 0.03)) * 0.6
                    return not (c.y > 0 and abs(c.x) < v)
                self.shell(top, "Over", waistcoat, 0.008, [over_m], cuts=2)
            elif over == "APRON":
                def apron(c, n, dom):
                    return c.y > 0.0 and n.y > 0.15 and knee_z + 0.08 < c.z < chest.z + 0.05 and abs(c.x) < 0.2
                self.shell(top, "Over", apron, 0.018, [over_m], cuts=2)
            elif over == "BRACES":
                def braces(c, n, dom):
                    return (dom not in ARM_BONES and waist - 0.03 < c.z < shoulder_z + 0.08
                            and abs(abs(c.x) - 0.07) < 0.011)
                self.shell(top, "Over", braces, 0.006, [bc.mat("dark", (1, 1, 1, 1))], cuts=3)
        if L["neckerchief"]:
            def scarf(c, n, dom):
                return dom in ("Neck", "Chest") and neck.z - 0.04 < c.z < neck.z + 0.05
            self.shell(body, "Neckerchief", scarf, 0.012, [bc.mat("neckerchief", (1, 1, 1, 1))])
        if L.get("tool_belt") and top is not None:
            def belt(c, n, dom):
                return dom not in ARM_BONES and abs(c.z - waist + 0.06) < 0.025
            self.shell(top, "ToolBelt", belt, 0.008, [bc.mat("leather", (1, 1, 1, 1))])
        self.build_blood(hc, r, chest, neck, top)

    def custodian_helmet(self, hc, r):
        parts = [
            (bc.metaballs("dome", [bc.ellip(hc + Vector((0, 0.02 * r, 0.75 * r)), (r * 1.12, r * 1.24, r * 1.45)),
                                   bc.ball(hc + Vector((0, 0.02 * r, 2.15 * r)), r * 0.2)], resolution=0.012), 0),
            (bc.cyl_mesh("brim", hc + Vector((0, 0, 0.1 * r)), r * 1.32, r * 1.22, r * 0.08, 24), 0),
            (bc.box_mesh("badge", hc + Vector((0, 1.22 * r, 0.8 * r)), (r * 0.32, r * 0.05, r * 0.42),
                         Matrix.Rotation(-0.15, 3, "X"), bevel=r * 0.03), 1),
        ]
        me = bc.join_meshes("Hat_POLICE_HELMET", parts)
        bc.smooth_all(me)
        self.rigid("Hat_POLICE_HELMET", me, [bc.mat("hat", (1, 1, 1, 1)), bc.mat("metal", (1, 1, 1, 1))], "Head")

    def build_blood(self, hc, r, chest, neck, top):
        blood = bc.mat("blood", (1, 1, 1, 1))
        nose = self.bone("Nose", True)
        drip = bc.metaballs("drip", [bc.capsule(nose + Vector((0.015, 0.0, -0.02)), nose + Vector((0.02, -0.004, -0.05)), 0.006),
                                     bc.ball(nose + Vector((-0.012, 0.0, -0.022)), 0.007)], resolution=0.004)
        self.rigid("Blood_Nose", drip, [blood], "Head")

        def face(c, n, dom):
            d = c - hc
            return d.y > 0.5 * r and -0.95 * r < d.z < -0.35 * r and abs(d.x) < 0.45 * r
        self.shell(self.body, "Blood_Face", face, 0.0012, [blood], solid=0)

        def cheek(c, n, dom):
            d = c - hc
            return d.x > 0.45 * r and d.y > 0.1 * r and -0.45 * r < d.z < 0.25 * r
        self.shell(self.body, "Blood_Cheek", cheek, 0.0012, [blood], solid=0)
        src = top or self.body

        def shirt(c, n, dom):
            return c.y > 0.0 and n.y > 0.3 and abs(c.x + 0.02) < 0.08 and chest.z + 0.04 < c.z < neck.z - 0.03
        self.shell(src, "Blood_Shirt", shirt, 0.003 if self.L["over"] not in ("HI_VIS", "GILET") else 0.018, [blood], solid=0)

    # --- Export -----------------------------------------------------------------------
    def finish(self, path, keep_blend=False):
        scale = self.L["height"]
        for obj, _ in self.objects:
            if not obj.data.uv_layers:
                obj.data.uv_layers.new(name="UVMap")
            if any(len(p.vertices) > 4 for p in obj.data.polygons):
                bm = bmesh.new()
                bm.from_mesh(obj.data)
                bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
                bm.to_mesh(obj.data)
                bm.free()
            obj.data.transform(Matrix.Scale(scale, 4))
            for mod in obj.modifiers:
                if mod.type == "SOLIDIFY":
                    mod.thickness *= scale
        bpy.context.view_layer.objects.active = self.arm
        self.arm.data.transform(Matrix.Scale(scale, 4))
        bpy.ops.object.select_all(action="SELECT")
        if keep_blend:
            os.makedirs(os.path.join(ROOT, "tools", "blender", "out"), exist_ok=True)
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "tools", "blender", "out",
                                                              os.path.basename(path).replace(".glb", ".blend")))
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=False, export_apply=True,
            export_animations=False, export_skins=True, export_yup=True, export_materials="EXPORT",
            export_image_format="AUTO", export_normals=True, export_tangents=True, export_texcoords=True,
            export_cameras=False, export_lights=False,
        )


def build(look_id, look, keep_blend=False):
    bc.reset()
    bc.MATS.clear()
    MAT_CACHE.clear()
    h = Human(look_id, look)
    h.build_body()
    h.dress()
    h.build_armature()
    for obj, weights in list(h.objects):
        h.skin(obj, weights)
    h.hide_body_under_clothes()
    h.cleanup()
    h.set_rest_pose()
    h.build_shells()
    path = os.path.join(OUT_DIR, look_id + ".glb")
    h.finish(path, keep_blend)
    print("built %s: %d faces, %d objects -> %s" % (look_id, sum(len(o.data.polygons) for o, _ in h.objects),
                                                    len(h.objects), path))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    keep = "--blend" in argv
    ids = [a for a in argv if not a.startswith("--")]
    with open(bc.LOOKS) as f:
        looks = json.load(f)
    for look_id in ids or list(looks):
        build(look_id, looks[look_id], keep)


if __name__ == "__main__":
    main()
