"""Small modelling kit for build_props.py: one bmesh per prop with material slots.

Coordinates are Blender's: X right, Y back (Godot -Z), Z up, metres. A prop's origin is on
the floor at its centre. Things that sit against a wall have their back at Y = 0 and face -Y
(Godot +Z). Seats face +Y (the sitter looks towards Godot -Z), so the backrest is at -Y.

Materials named M_<name> are shared library materials: Godot swaps them for PubMaterials
(textured, triplanar), so their UVs don't matter. T_<texture> materials carry a texture
from assets/textures/props and need UVs. C_<name> materials are plain colours kept as
imported (food, paint).
"""

import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROP_TEX = os.path.join(ROOT, "assets", "textures", "props")


def srgb(hexstr, a=1.0):
    h = hexstr.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    lin = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c]
    return (*lin, a)


# Preview colours for the shared materials (Godot replaces them). name: (hex, metallic, rough, alpha)
SHARED = {
    "wood_oak": ("7a5232", 0, 0.6, 1), "wood_dark": ("3e2716", 0, 0.55, 1), "wood_pine": ("b48a5a", 0, 0.65, 1),
    "wood_mahogany": ("5a2418", 0, 0.45, 1), "wood_painted_green": ("2f4a38", 0, 0.6, 1),
    "wood_painted_cream": ("d8cdb0", 0, 0.6, 1), "wood_black": ("1c1a18", 0, 0.5, 1),
    "iron": ("232323", 0.8, 0.55, 1), "brass": ("c9a03a", 1, 0.3, 1), "copper": ("b8683a", 1, 0.35, 1),
    "pewter": ("8a8c88", 1, 0.4, 1), "chrome": ("d0d0d0", 1, 0.12, 1), "gilt": ("c8a040", 1, 0.35, 1),
    "glass": ("dfe8e6", 0, 0.05, 0.25), "glass_green": ("2f5d34", 0, 0.08, 0.7),
    "glass_brown": ("4a2a10", 0, 0.08, 0.75), "glass_thick": ("cfdcd8", 0, 0.06, 0.4),
    "glass_blue": ("2a4a7a", 0, 0.08, 0.65),
    "ale": ("a8621a", 0, 0.1, 0.88), "lager": ("d8a830", 0, 0.1, 0.8), "stout": ("120a06", 0, 0.1, 0.97),
    "cider": ("d0a040", 0, 0.1, 0.7), "wine_red": ("4a0812", 0, 0.1, 0.9), "whisky": ("a0601a", 0, 0.1, 0.7),
    "foam": ("f0e6cc", 0, 0.8, 1), "water": ("d8e8e8", 0, 0.05, 0.3),
    "leather_red": ("6a1c16", 0, 0.5, 1), "leather_brown": ("4a2a16", 0, 0.5, 1), "leather_green": ("1f3a2a", 0, 0.5, 1),
    "fabric_red": ("7a2a2a", 0, 0.95, 1), "fabric_green": ("2a4a32", 0, 0.95, 1), "fabric_tweed": ("6a5a44", 0, 0.95, 1),
    "fabric_blue": ("2a3450", 0, 0.95, 1), "rush": ("a08a50", 0, 0.95, 1), "felt": ("1f6a35", 0, 0.98, 1),
    "ceramic": ("ece6d8", 0, 0.25, 1), "ceramic_blue": ("2a4a8a", 0, 0.25, 1), "stoneware": ("b8a07a", 0, 0.5, 1),
    "ivory": ("ece4cc", 0, 0.3, 1), "black_gloss": ("0e0e0e", 0, 0.15, 1), "paper": ("e8e0c8", 0, 0.9, 1),
    "wax": ("efe6cc", 0, 0.5, 1), "flame": ("ffb040", 0, 1, 1), "plaster": ("d8cdb4", 0, 0.9, 1),
    "stone": ("8a8478", 0, 0.85, 1), "rope": ("9a8050", 0, 0.95, 1), "plastic_red": ("b8201c", 0, 0.35, 1),
    "plastic_black": ("1a1a1a", 0, 0.4, 1), "neon": ("ff6a3a", 0, 0.5, 1), "foliage": ("2e5a2a", 0, 0.7, 1),
    "soil": ("2a1c10", 0, 0.95, 1), "bone": ("e4dcc4", 0, 0.6, 1), "chalk": ("2a2e2c", 0, 0.95, 1),
}

FOOD = {
    "pastry": ("c88a3a", 0.6), "pastry_dark": ("9a5a22", 0.6), "chips": ("e8c060", 0.6), "batter": ("d09040", 0.5),
    "peas": ("5a9a2a", 0.4), "gravy": ("5a3014", 0.2), "bread": ("c89a5a", 0.8), "crust": ("8a5a2a", 0.7),
    "cheese": ("f0d070", 0.5), "pickle": ("5a3018", 0.4), "apple": ("8a2a1a", 0.3), "apple_green": ("8ab040", 0.3),
    "lettuce": ("6aa040", 0.6), "tomato": ("c8301c", 0.3), "egg_white": ("f4f0e4", 0.3), "egg_yolk": ("f0b020", 0.3),
    "sausage": ("8a4a2a", 0.4), "mash": ("f0e4c0", 0.8), "beef": ("7a3a2a", 0.6), "yorkshire": ("d0a050", 0.7),
    "carrot": ("e0701c", 0.4), "scotch_egg": ("a06a30", 0.8), "ham": ("d89080", 0.5), "pork_crackling": ("c89050", 0.6),
    "peanut": ("c08a50", 0.6), "pickled_egg": ("e8dcc0", 0.3), "vinegar": ("8a6a2a", 0.1), "ketchup": ("a0140c", 0.2),
    "brown_sauce": ("3a1a0c", 0.2), "lemon": ("f0d040", 0.4), "paint_red": ("8a1c14", 0.6), "paint_gold": ("c8a040", 0.4),
    "paint_white": ("e8e4d8", 0.6), "paint_black": ("141414", 0.5), "coat": ("2a2420", 0.95), "scarf": ("8a2a1a", 0.95),
    "screen": ("102010", 0.2), "reel": ("e8d070", 0.4), "light_red": ("ff3a2a", 0.4), "light_amber": ("ffb030", 0.4),
    "book_red": ("6a1a14", 0.8), "book_green": ("1a3a20", 0.8), "book_blue": ("1a2440", 0.8), "book_brown": ("5a3a1a", 0.8),
    "fish": ("7a8a8a", 0.3), "hay": ("c8a860", 0.9),
}

EMISSIVE = {"flame", "neon", "light_red", "light_amber", "screen"}


def material(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if name.startswith("M_"):
        hexc, metal, rough, alpha = SHARED[name[2:]]
        bsdf.inputs["Base Color"].default_value = srgb(hexc)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if alpha < 1:
            bsdf.inputs["Alpha"].default_value = alpha
            m.surface_render_method = "BLENDED"
        if name[2:] in EMISSIVE:
            bsdf.inputs["Emission Color"].default_value = srgb(hexc)
            bsdf.inputs["Emission Strength"].default_value = 3.0
    elif name.startswith("C_"):
        hexc, rough = FOOD[name[2:]]
        bsdf.inputs["Base Color"].default_value = srgb(hexc)
        bsdf.inputs["Roughness"].default_value = rough
        if name[2:] in EMISSIVE:
            bsdf.inputs["Emission Color"].default_value = srgb(hexc)
            bsdf.inputs["Emission Strength"].default_value = 2.5
    elif name.startswith("T_"):
        tex = nodes.new("ShaderNodeTexImage")
        path = os.path.join(PROP_TEX, name[2:] + ".jpg")
        img = bpy.data.images.load(path, check_existing=True)
        tex.image = img
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.6
    else:
        raise ValueError("material names start with M_, C_ or T_: " + name)
    return m


def xform(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    s = Matrix.Diagonal((*scale, 1.0))
    return Matrix.Translation(Vector(loc)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ s


class Prop:
    """Builds one prop into a single bmesh, one material slot per material name."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.mats = []

    # --- bookkeeping ---
    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _faces_of(self, verts):
        return {f for v in verts for f in v.link_faces}

    def _assign(self, faces, mat, smooth=True):
        i = self._mi(mat)
        for f in faces:
            f.material_index = i
            f.smooth = smooth
        return faces

    # --- primitives ---
    def box(self, size, loc, mat, rot=(0, 0, 0), bevel=0.0, segs=1):
        """Axis box of `size` centred at `loc`, rotated by `rot` degrees (XYZ)."""
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=xform(loc, rot, size))
        faces = self._faces_of(r["verts"])
        if bevel > 0:
            edges = list({e for f in faces for e in f.edges})
            res = bmesh.ops.bevel(self.bm, geom=edges + list(r["verts"]), offset=bevel, segments=segs,
                                  affect="EDGES", profile=0.5, clamp_overlap=True)
            faces |= set(res.get("faces", []))
            faces = {f for f in faces if f.is_valid}
            for v in r["verts"]:
                if v.is_valid:
                    faces |= set(v.link_faces)
        return self._assign(faces, mat, smooth=bevel > 0)

    def cyl(self, r, h, loc, mat, segs=16, rot=(0, 0, 0), r2=None, caps=True):
        """Cylinder (or cone/frustum with r2) along local Z, centred at loc."""
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs,
                                    radius1=r, radius2=r if r2 is None else r2, depth=h,
                                    matrix=xform(loc, rot))
        return self._assign(self._faces_of(res["verts"]), mat)

    def rod(self, a, b, r, mat, segs=8, r2=None):
        """Cylinder from point a to point b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4()
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                                    radius1=r, radius2=r if r2 is None else r2, depth=d.length, matrix=m)
        return self._assign(self._faces_of(res["verts"]), mat)

    def sphere(self, r, loc, mat, scale=(1, 1, 1), segs=12, rings=8, rot=(0, 0, 0)):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=r,
                                        matrix=xform(loc, rot, scale))
        return self._assign(self._faces_of(res["verts"]), mat)

    def torus(self, R, r, loc, mat, rot=(0, 0, 0), segs=20, ring=6, arc=360.0):
        m = xform(loc, rot)
        rings = []
        n = segs if arc >= 360 else segs + 1
        for i in range(n):
            a = math.radians(arc) * i / segs
            c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
            out = Vector((math.cos(a), math.sin(a), 0))
            ringv = []
            for j in range(ring):
                b = math.tau * j / ring
                p = c + out * (math.cos(b) * r) + Vector((0, 0, math.sin(b) * r))
                ringv.append(self.bm.verts.new(m @ p))
            rings.append(ringv)
        faces = []
        for i in range(segs if arc >= 360 else segs):
            a, b = rings[i], rings[(i + 1) % len(rings)]
            for j in range(ring):
                faces.append(self.bm.faces.new((a[j], b[j], b[(j + 1) % ring], a[(j + 1) % ring])))
        return self._assign(faces, mat)

    def lathe(self, profile, mat, loc=(0, 0, 0), segs=24, rot=(0, 0, 0), cap_bottom=True, cap_top=False,
              jitter_top=0.0, seed=1, scale=(1, 1, 1), uv_band=None, flip=False, both=False):
        """Revolve [(radius, z), ...] (bottom to top) round Z. Faces point to the left of
        the profile's direction (outwards when it climbs, down when it runs outwards), so
        `flip` turns them round and `both` makes open dishes and baskets two-sided.
        `jitter_top` makes a jagged broken rim."""
        if both:
            self.lathe(profile, mat, loc, segs, rot, False, False, jitter_top, seed, scale, flip=not flip)
            return self.lathe(profile, mat, loc, segs, rot, cap_bottom, cap_top, jitter_top, seed, scale, flip=flip)
        import random
        rnd = random.Random(seed)
        m = xform(loc, rot, scale)
        rings = []
        for k, (r, z) in enumerate(profile):
            ring = []
            for i in range(segs):
                a = math.tau * i / segs
                zz = z
                if jitter_top and k == len(profile) - 1:
                    zz = z - rnd.random() * jitter_top
                ring.append(self.bm.verts.new(m @ Vector((math.cos(a) * r, math.sin(a) * r, zz))))
            rings.append(ring)
        faces = []
        for k in range(len(rings) - 1):
            a, b = rings[k], rings[k + 1]
            for i in range(segs):
                j = (i + 1) % segs
                if profile[k][0] < 1e-5:
                    continue
                quad = (a[i], a[j], b[j], b[i])
                faces.append(self.bm.faces.new(tuple(reversed(quad)) if flip else quad))
        if cap_bottom and profile[0][0] > 1e-5:
            faces.append(self.bm.faces.new(list(reversed(rings[0]))))
        if cap_top and profile[-1][0] > 1e-5:
            faces.append(self.bm.faces.new(rings[-1]))
        return self._assign(faces, mat)

    def band(self, r, z0, z1, mat, a0=-110.0, a1=110.0, segs=16, loc=(0, 0, 0), flat_y=None):
        """Textured label round a cylinder, centred on the front (-Y). Angles in degrees
        from the front, a0..a1. UVs span the texture once."""
        cols = []
        for i in range(segs + 1):
            t = i / segs
            ang = math.radians(a0 + (a1 - a0) * t) - math.pi * 0.5
            x, y = math.cos(ang) * r, math.sin(ang) * r
            v0 = self.bm.verts.new(Vector(loc) + Vector((x, y, z0)))
            v1 = self.bm.verts.new(Vector(loc) + Vector((x, y, z1)))
            cols.append((v0, v1, t))
        faces = []
        for i in range(segs):
            (a0v, a1v, ta), (b0v, b1v, tb) = cols[i], cols[i + 1]
            f = self.bm.faces.new((a0v, b0v, b1v, a1v))
            for loop, uv in zip(f.loops, ((ta, 0), (tb, 0), (tb, 1), (ta, 1))):
                loop[self.uv].uv = uv
            faces.append(f)
        return self._assign(faces, mat)

    def quad(self, w, h, loc, mat, rot=(0, 0, 0), uv=(0, 0, 1, 1)):
        """Flat textured rectangle in the XZ plane facing -Y, centred at loc."""
        m = xform(loc, rot)
        pts = [(-w / 2, 0, -h / 2), (w / 2, 0, -h / 2), (w / 2, 0, h / 2), (-w / 2, 0, h / 2)]
        vs = [self.bm.verts.new(m @ Vector(p)) for p in pts]
        f = self.bm.faces.new(vs)
        u0, v0, u1, v1 = uv
        for loop, c in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            loop[self.uv].uv = c
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
        return self._assign([f], mat, smooth=False)

    def disc(self, r, loc, mat, rot=(0, 0, 0), segs=48):
        """Textured disc in the XZ plane facing -Y; UVs map the square texture onto it."""
        m = xform(loc, rot)
        c = self.bm.verts.new(m @ Vector((0, 0, 0)))
        ring = [self.bm.verts.new(m @ Vector((math.cos(math.tau * i / segs) * r, 0,
                                               math.sin(math.tau * i / segs) * r))) for i in range(segs)]
        faces = []
        for i in range(segs):
            j = (i + 1) % segs
            f = self.bm.faces.new((c, ring[j], ring[i]))
            for loop in f.loops:
                p = m.inverted() @ loop.vert.co
                loop[self.uv].uv = (0.5 + p.x / (2 * r), 0.5 + p.z / (2 * r))
            faces.append(f)
        return self._assign(faces, mat, smooth=False)

    def finish(self, collection, sharp_angle=38.0):
        for e in self.bm.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(sharp_angle):
                e.smooth = False
        for f in self.bm.faces:
            f.smooth = True
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for name in self.mats:
            me.materials.append(material(name))
        ob = bpy.data.objects.new(self.name, me)
        collection.objects.link(ob)
        return ob
