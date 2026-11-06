"""Builds every pub prop as low-poly models, one .glb per category, plus a catalogue.

    python3 tools/textures/build_textures.py            # textures first (labels, dartboard...)
    blender -b -P tools/blender/build_props.py           # all categories
    blender -b -P tools/blender/build_props.py -- tables chairs

Writes assets/models/props/<category>.glb and assets/models/props/catalogue.json. Each object
in a .glb is one prop variant (all sit at the origin). The catalogue says which item kind
each variant belongs to plus its physics: mass in kg, collision shape, fragile (glass and
crockery smash), pinned (hangs on a wall until knocked loose) and size class (big decor
blocks people, small decor gets kicked about). Godot reads it through PropLibrary.

See props_kit.py for the coordinate and material conventions.
"""

import json
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
from props_kit import Prop  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models", "props")

REGISTRY = []  # (category, kind, name, fn, meta)


def prop(category, kind, name, mass, shape="convex", **meta):
    def deco(fn):
        REGISTRY.append((category, kind, name, fn, dict(mass=mass, shape=shape, **meta)))
        return fn
    return deco


def turned_leg(p, x, y, h, mat, r=0.024, foot=0.0):
    """Lathe-turned leg from the floor to height h at (x, y)."""
    prof = [(r * 0.8, 0), (r, 0.03), (r * 0.75, h * 0.15), (r * 1.25, h * 0.3), (r * 0.8, h * 0.42),
            (r * 0.85, h * 0.8), (r * 1.15, h * 0.86), (r * 1.15, h)]
    p.lathe(prof, mat, loc=(x, y, foot), segs=10, cap_top=True)


# =====================================================================================
# Tables  (kind "table")  - tops at 0.74-0.78 m. Footprint <= 1.2 x 1.0 so table_set chairs fit.
# =====================================================================================

@prop("tables", "table", "table_oak_square", 22, "box")
def _(p):
    p.box((0.9, 0.9, 0.05), (0, 0, 0.745), "M_wood_oak", bevel=0.012, segs=2)
    p.box((0.78, 0.78, 0.1), (0, 0, 0.67), "M_wood_oak")
    for x in (-0.38, 0.38):
        for y in (-0.38, 0.38):
            turned_leg(p, x, y, 0.72, "M_wood_oak")


@prop("tables", "table", "table_round_pedestal", 20, "cyl")
def _(p):
    p.cyl(0.46, 0.045, (0, 0, 0.75), "M_wood_dark", segs=32)
    p.torus(0.46, 0.022, (0, 0, 0.75), "M_wood_dark", segs=32)
    p.lathe([(0.07, 0.08), (0.05, 0.15), (0.09, 0.25), (0.045, 0.4), (0.06, 0.6), (0.04, 0.68), (0.12, 0.72)],
            "M_wood_dark", segs=14, cap_top=True)
    for i in range(3):
        a = math.tau * i / 3
        p.box((0.36, 0.06, 0.07), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.05), "M_wood_dark",
              rot=(0, 8, math.degrees(a)), bevel=0.01)


@prop("tables", "table", "table_britannia", 30, "cyl")
def _(p):
    """Victorian cast-iron pub table (Britannia base) with a mahogany top."""
    p.cyl(0.4, 0.04, (0, 0, 0.74), "M_wood_mahogany", segs=32)
    p.torus(0.4, 0.02, (0, 0, 0.74), "M_brass", segs=32, ring=5)
    p.lathe([(0.05, 0.12), (0.03, 0.3), (0.05, 0.45), (0.03, 0.6), (0.08, 0.7)], "M_iron", segs=10, cap_top=True)
    for i in range(3):
        a = math.tau * i / 3 + 0.3
        c, s = math.cos(a), math.sin(a)
        p.rod((c * 0.04, s * 0.04, 0.2), (c * 0.33, s * 0.33, 0.02), 0.025, "M_iron")
        p.rod((c * 0.04, s * 0.04, 0.5), (c * 0.15, s * 0.15, 0.25), 0.015, "M_iron")
        p.sphere(0.035, (c * 0.33, s * 0.33, 0.03), "M_iron", segs=8, rings=5)
    p.cyl(0.08, 0.04, (0, 0, 0.12), "M_iron", segs=12)


@prop("tables", "table", "table_trestle", 28, "box")
def _(p):
    for i, x in enumerate((-0.45, -0.15, 0.15, 0.45)):
        p.box((0.29, 0.72, 0.05), (x, 0, 0.75), "M_wood_pine", rot=(0, 0, 0.5 * (i - 1.5)), bevel=0.008)
    for x in (-0.45, 0.45):
        for s in (-1, 1):
            p.rod((x, s * 0.28, 0.0), (x, -s * 0.05, 0.72), 0.03, "M_wood_pine", segs=6)
    p.box((0.95, 0.06, 0.06), (0, 0, 0.36), "M_wood_pine")


@prop("tables", "table", "table_cricket", 16, "cyl")
def _(p):
    """Three-legged cricket table with a shelf."""
    p.cyl(0.42, 0.04, (0, 0, 0.73), "M_wood_oak", segs=28)
    p.cyl(0.3, 0.025, (0, 0, 0.18), "M_wood_oak", segs=3, rot=(0, 0, 30))
    for i in range(3):
        a = math.tau * i / 3
        p.rod((math.cos(a) * 0.3, math.sin(a) * 0.3, 0), (math.cos(a) * 0.26, math.sin(a) * 0.26, 0.71),
              0.025, "M_wood_oak", segs=8)
    for i in range(3):
        a0, a1 = math.tau * i / 3, math.tau * (i + 1) / 3
        p.rod((math.cos(a0) * 0.27, math.sin(a0) * 0.27, 0.66), (math.cos(a1) * 0.27, math.sin(a1) * 0.27, 0.66),
              0.018, "M_wood_oak", segs=6)


@prop("tables", "table", "table_copper", 18, "cyl")
def _(p):
    p.cyl(0.38, 0.03, (0, 0, 0.75), "M_copper", segs=32)
    p.torus(0.38, 0.02, (0, 0, 0.755), "M_brass", segs=32, ring=5)
    for i in range(4):
        a = math.tau * i / 4 + math.pi / 4
        p.rod((math.cos(a) * 0.3, math.sin(a) * 0.3, 0), (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.74),
              0.022, "M_wood_black", segs=8)
    p.torus(0.25, 0.012, (0, 0, 0.3), "M_brass", segs=24, ring=5)


@prop("tables", "table", "table_gateleg", 24, "box")
def _(p):
    p.cyl(0.55, 0.04, (0, 0, 0.75), "M_wood_mahogany", segs=32, rot=(0, 0, 0))
    p.bm.verts.ensure_lookup_table()
    # Squash the round top into an oval.
    for v in p.bm.verts:
        if v.co.z > 0.72:
            v.co.y *= 0.72
    for x in (-0.38, 0.38):
        for y in (-0.25, 0.25):
            p.lathe([(0.022, 0), (0.03, 0.06)] + [(0.024 + 0.008 * math.sin(k * 1.6), 0.06 + k * 0.045) for k in range(14)]
                    + [(0.03, 0.72)], "M_wood_mahogany", loc=(x, y, 0), segs=8, cap_top=True)
    p.box((0.8, 0.04, 0.04), (0, 0, 0.12), "M_wood_mahogany")


@prop("tables", "table", "table_cask", 45, "cyl")
def _(p):
    """An old barrel stood on end with a round top: the standing-room table."""
    prof = [(0.27, 0), (0.31, 0.2), (0.33, 0.4), (0.31, 0.6), (0.27, 0.8)]
    p.lathe(prof, "M_wood_oak", segs=20)
    for z, r in ((0.07, 0.285), (0.3, 0.33), (0.52, 0.33), (0.74, 0.28)):
        p.lathe([(r + 0.006, z - 0.025), (r + 0.006, z + 0.025)], "M_iron", segs=20, cap_bottom=False)
    p.cyl(0.42, 0.05, (0, 0, 0.83), "M_wood_dark", segs=28)


# =====================================================================================
# Chairs  (kind "chair") - seat 0.45 m. Sitter faces +Y, back at -Y.
# =====================================================================================

def four_legs(p, mat, w=0.19, d=0.19, h=0.44, r=0.018, splay=0.0, turned=False):
    for x in (-w, w):
        for y in (-d, d):
            if turned:
                turned_leg(p, x, y, h, mat, r=r)
            else:
                p.rod((x * (1 + splay), y * (1 + splay), 0), (x, y, h), r, mat, segs=8)


@prop("chairs", "chair", "chair_windsor", 6)
def _(p):
    p.box((0.46, 0.44, 0.045), (0, 0.0, 0.45), "M_wood_oak", bevel=0.015, segs=2)
    four_legs(p, "M_wood_oak", 0.17, 0.15, 0.44, 0.017, splay=0.25)
    p.rod((-0.2, 0.0, 0.18), (0.2, 0.0, 0.18), 0.012, "M_wood_oak", segs=6)
    p.torus(0.24, 0.018, (0, -0.2, 0.84), "M_wood_oak", rot=(95, 0, 0), segs=18, ring=6, arc=180)
    for i in range(7):
        x = -0.18 + i * 0.06
        top = 0.84 + math.sqrt(max(0.0, 0.24 ** 2 - x ** 2)) - 0.01
        p.rod((x * 0.8, -0.17, 0.47), (x, -0.2, top), 0.008, "M_wood_oak", segs=6)
    for s in (-1, 1):
        p.rod((s * 0.21, -0.18, 0.47), (s * 0.24, -0.2, 0.85), 0.013, "M_wood_oak", segs=6)


@prop("chairs", "chair", "chair_ladderback", 5)
def _(p):
    p.box((0.44, 0.42, 0.04), (0, 0, 0.45), "M_rush", bevel=0.01)
    for x in (-0.2, 0.2):
        p.rod((x, 0.18, 0), (x, 0.18, 0.47), 0.018, "M_wood_dark", segs=8)
        p.lathe([(0.018, 0), (0.02, 0.5), (0.016, 0.98), (0.03, 1.02), (0.0, 1.06)], "M_wood_dark",
                loc=(x, -0.19, 0), segs=8)
    for k in range(4):
        p.box((0.4, 0.02, 0.07 - k * 0.005), (0, -0.19, 0.62 + k * 0.11), "M_wood_dark", rot=(0, 0, 0), bevel=0.006)
    for y in (-0.19, 0.18):
        p.rod((-0.2, y, 0.15), (0.2, y, 0.15), 0.01, "M_wood_dark", segs=6)


@prop("chairs", "chair", "chair_wheelback", 6)
def _(p):
    p.box((0.46, 0.44, 0.045), (0, 0, 0.45), "M_wood_mahogany", bevel=0.015, segs=2)
    four_legs(p, "M_wood_mahogany", 0.18, 0.16, 0.44, 0.02, turned=True)
    p.torus(0.2, 0.02, (0, -0.2, 0.75), "M_wood_mahogany", rot=(90, 0, 0), segs=22, ring=6, arc=200)
    p.bm.verts.ensure_lookup_table()
    p.torus(0.08, 0.012, (0, -0.2, 0.8), "M_wood_mahogany", rot=(90, 0, 0), segs=14, ring=5)
    for i in range(8):
        a = math.tau * i / 8
        p.rod((math.cos(a) * 0.08, -0.2, 0.8 + math.sin(a) * 0.08),
              (math.cos(a) * 0.19, -0.2, 0.78 + math.sin(a) * 0.17), 0.007, "M_wood_mahogany", segs=5)
    for s in (-1, 1):
        p.rod((s * 0.19, -0.19, 0.47), (s * 0.19, -0.2, 0.74), 0.016, "M_wood_mahogany", segs=6)


@prop("chairs", "chair", "chair_captains", 8)
def _(p):
    """Tub-backed captain's chair with arms."""
    p.cyl(0.24, 0.045, (0, 0, 0.45), "M_wood_oak", segs=20)
    p.torus(0.235, 0.03, (0, 0, 0.73), "M_wood_oak", rot=(0, 0, 200), segs=16, ring=6, arc=220)
    for i in range(9):
        a = math.radians(200 + i * 220 / 8)
        p.rod((math.cos(a) * 0.21, math.sin(a) * 0.21, 0.47), (math.cos(a) * 0.235, math.sin(a) * 0.235, 0.72),
              0.009, "M_wood_oak", segs=5)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        p.rod((math.cos(a) * 0.24, math.sin(a) * 0.24, 0), (math.cos(a) * 0.17, math.sin(a) * 0.17, 0.44),
              0.02, "M_wood_oak", segs=8)
    p.torus(0.19, 0.01, (0, 0, 0.16), "M_wood_oak", segs=16, ring=5)


@prop("chairs", "chair", "chair_bentwood", 4)
def _(p):
    p.cyl(0.21, 0.04, (0, 0, 0.45), "M_rush", segs=20)
    p.torus(0.21, 0.015, (0, 0, 0.45), "M_wood_black", segs=20, ring=5)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        p.rod((math.cos(a) * 0.24, math.sin(a) * 0.24, 0), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.44),
              0.015, "M_wood_black", segs=8)
    p.torus(0.17, 0.008, (0, 0, 0.2), "M_wood_black", segs=16, ring=5)
    p.torus(0.17, 0.016, (0, -0.15, 0.68), "M_wood_black", rot=(90, 0, 0), segs=20, ring=5, arc=180)
    for s in (-1, 1):
        p.rod((s * 0.17, -0.16, 0.45), (s * 0.17, -0.15, 0.68), 0.016, "M_wood_black", segs=6)
    p.torus(0.08, 0.01, (0, -0.155, 0.6), "M_wood_black", rot=(90, 0, 0), segs=14, ring=5)


@prop("chairs", "chair", "chair_leather", 9)
def _(p):
    """Victorian dining chair, buttoned leather seat and back."""
    four_legs(p, "M_wood_mahogany", 0.19, 0.17, 0.42, 0.02, turned=True)
    p.box((0.47, 0.45, 0.09), (0, 0, 0.45), "M_leather_red", bevel=0.03, segs=3)
    p.box((0.42, 0.06, 0.38), (0, -0.21, 0.73), "M_leather_red", bevel=0.025, segs=3)
    for s in (-1, 1):
        p.box((0.04, 0.05, 0.55), (s * 0.21, -0.215, 0.7), "M_wood_mahogany", bevel=0.01)
    p.box((0.46, 0.05, 0.05), (0, -0.215, 0.95), "M_wood_mahogany", bevel=0.012)
    for x in (-0.1, 0.0, 0.1):
        for z in (0.65, 0.8):
            p.sphere(0.008, (x, -0.245, z), "M_brass", segs=6, rings=4)


@prop("chairs", "chair", "chair_spindle", 5)
def _(p):
    """Plain painted spindle chair (the knackered one in the corner)."""
    p.box((0.42, 0.4, 0.035), (0, 0, 0.45), "M_wood_painted_green", bevel=0.01)
    four_legs(p, "M_wood_painted_green", 0.17, 0.15, 0.44, 0.016)
    p.box((0.4, 0.035, 0.07), (0, -0.18, 0.88), "M_wood_painted_green", bevel=0.01)
    for i in range(5):
        p.rod((-0.16 + i * 0.08, -0.18, 0.47), (-0.16 + i * 0.08, -0.18, 0.85), 0.009, "M_wood_painted_green", segs=5)
    for s in (-1, 1):
        p.rod((s * 0.2, -0.17, 0.47), (s * 0.2, -0.18, 0.9), 0.014, "M_wood_painted_green", segs=6)


# =====================================================================================
# Stools (kind "stool")
# =====================================================================================

@prop("stools", "stool", "stool_bar_round", 5, "cyl")
def _(p):
    p.cyl(0.19, 0.06, (0, 0, 0.74), "M_wood_oak", segs=20)
    for i in range(4):
        a = math.radians(45 + 90 * i)
        p.rod((math.cos(a) * 0.22, math.sin(a) * 0.22, 0), (math.cos(a) * 0.13, math.sin(a) * 0.13, 0.72),
              0.018, "M_wood_oak", segs=8)
    p.torus(0.18, 0.01, (0, 0, 0.26), "M_brass", segs=18, ring=5)


@prop("stools", "stool", "stool_milking", 2.5, "cyl")
def _(p):
    p.cyl(0.16, 0.04, (0, 0, 0.42), "M_wood_pine", segs=14)
    for i in range(3):
        a = math.tau * i / 3
        p.rod((math.cos(a) * 0.17, math.sin(a) * 0.17, 0), (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.41),
              0.018, "M_wood_pine", segs=6)


@prop("stools", "stool", "stool_padded", 6, "cyl")
def _(p):
    p.cyl(0.2, 0.08, (0, 0, 0.74), "M_leather_brown", segs=20)
    p.torus(0.2, 0.012, (0, 0, 0.71), "M_brass", segs=20, ring=4)
    p.lathe([(0.2, 0), (0.18, 0.02), (0.04, 0.04), (0.03, 0.68), (0.06, 0.7)], "M_chrome", segs=16, cap_top=True)
    p.torus(0.16, 0.01, (0, 0, 0.28), "M_chrome", segs=18, ring=5)
    for i in range(3):
        a = math.tau * i / 3
        p.rod((0, 0, 0.28), (math.cos(a) * 0.16, math.sin(a) * 0.16, 0.28), 0.007, "M_chrome", segs=5)


@prop("stools", "stool", "stool_backed", 7)
def _(p):
    p.box((0.38, 0.36, 0.05), (0, 0, 0.74), "M_wood_dark", bevel=0.012, segs=2)
    for x in (-0.15, 0.15):
        for y in (-0.14, 0.14):
            p.rod((x * 1.25, y * 1.25, 0), (x, y, 0.72), 0.017, "M_wood_dark", segs=8)
    for x in (-0.15, 0.15):
        p.rod((x, -0.15, 0.76), (x, -0.17, 1.05), 0.016, "M_wood_dark", segs=6)
    p.box((0.36, 0.03, 0.09), (0, -0.17, 1.03), "M_wood_dark", bevel=0.01)
    p.rod((-0.19, -0.18, 0.3), (0.19, -0.18, 0.3), 0.01, "M_wood_dark", segs=6)
    p.rod((-0.19, 0.18, 0.3), (0.19, 0.18, 0.3), 0.01, "M_wood_dark", segs=6)


@prop("stools", "stool", "stool_tavern", 4, "box")
def _(p):
    p.box((0.34, 0.34, 0.05), (0, 0, 0.62), "M_wood_oak", bevel=0.01)
    for x in (-0.13, 0.13):
        for y in (-0.13, 0.13):
            p.box((0.045, 0.045, 0.6), (x * 1.05, y * 1.05, 0.3), "M_wood_oak", rot=(y * 30, -x * 30, 0))
    for y in (-0.15, 0.15):
        p.box((0.3, 0.025, 0.04), (0, y, 0.18), "M_wood_oak")


# =====================================================================================
# Glassware (kinds "glass" empty pint glass, "pint" full; plus decor glasses)
# =====================================================================================

def nonic(p, liquid=None, foam=True, fill=0.9, mat="M_glass"):
    prof = [(0.03, 0.0), (0.032, 0.004), (0.036, 0.09), (0.042, 0.125), (0.04, 0.135), (0.042, 0.15)]
    p.lathe(prof, mat, segs=20)
    if liquid:
        h = 0.145 * fill
        p.lathe([(0.03, 0.006), (0.035, 0.09), (0.04, min(h, 0.12)), (0.039, h)], liquid, segs=16, cap_top=True)
        if foam:
            p.cyl(0.04, 0.012, (0, 0, h + 0.004), "M_foam", segs=16)


def dimple_jug(p, liquid=None):
    prof = [(0.042, 0.0), (0.046, 0.01), (0.048, 0.12), (0.046, 0.13)]
    p.lathe(prof, "M_glass_thick", segs=10)  # faceted panels read as the dimples
    for z in (0.035, 0.065, 0.095):
        p.torus(0.0485, 0.003, (0, 0, z), "M_glass_thick", segs=10, ring=4)
    p.torus(0.035, 0.008, (0.07, 0, 0.065), "M_glass_thick", rot=(90, 0, 0), segs=12, ring=5, arc=200)
    if liquid:
        p.cyl(0.043, 0.11, (0, 0, 0.06), liquid, segs=16)
        p.cyl(0.044, 0.012, (0, 0, 0.118), "M_foam", segs=16)


@prop("glassware", "glass", "glass_nonic", 0.4, "cyl", fragile=True)
def _(p):
    nonic(p)


@prop("glassware", "glass", "glass_dimple_jug", 0.6, "cyl", fragile=True)
def _(p):
    dimple_jug(p)


@prop("glassware", "glass", "glass_sleever", 0.35, "cyl", fragile=True)
def _(p):
    p.lathe([(0.031, 0), (0.033, 0.004), (0.042, 0.155)], "M_glass", segs=20)


@prop("glassware", "glass", "glass_tankard", 0.5, "cyl", fragile=False)
def _(p):
    p.lathe([(0.046, 0), (0.048, 0.01), (0.042, 0.12), (0.044, 0.13)], "M_pewter", segs=20, both=True)
    p.torus(0.035, 0.009, (0.07, 0, 0.07), "M_pewter", rot=(90, 0, 0), segs=12, ring=5, arc=200)
    p.cyl(0.04, 0.004, (0, 0, 0.004), "M_pewter", segs=16)


@prop("glassware", "pint", "pint_ale", 0.9, "cyl", fragile=True)
def _(p):
    nonic(p, "M_ale")


@prop("glassware", "pint", "pint_stout", 0.9, "cyl", fragile=True)
def _(p):
    nonic(p, "M_stout", fill=0.86)
    p.cyl(0.041, 0.02, (0, 0, 0.137), "M_foam", segs=16)


@prop("glassware", "pint", "pint_lager", 0.9, "cyl", fragile=True)
def _(p):
    p.lathe([(0.031, 0), (0.033, 0.004), (0.042, 0.155)], "M_glass", segs=20)
    p.lathe([(0.029, 0.005), (0.04, 0.142)], "M_lager", segs=16, cap_top=True)
    p.cyl(0.041, 0.014, (0, 0, 0.148), "M_foam", segs=16)


@prop("glassware", "pint", "pint_jug_bitter", 1.0, "cyl", fragile=True)
def _(p):
    dimple_jug(p, "M_ale")


@prop("glassware", "pint", "pint_cider", 0.9, "cyl", fragile=True)
def _(p):
    nonic(p, "M_cider", foam=False, fill=0.92)


def stemmed(p, bowl, liquid=None, fill=0.5, stem=0.08):
    p.lathe([(0.035, 0), (0.035, 0.003), (0.005, 0.006), (0.004, stem)], "M_glass", segs=16)
    pts = [(0.005, stem)] + [(r, stem + z) for r, z in bowl]
    p.lathe(pts, "M_glass", segs=18, cap_bottom=False)
    if liquid:
        top = stem + bowl[-1][1] * fill
        sub = [(0.003, stem + 0.003)] + [(r * 0.94, stem + z) for r, z in bowl if stem + z <= top] + [(bowl[1][0] * 0.9, top)]
        p.lathe(sub, liquid, segs=14, cap_top=True)


@prop("glassware", "decor_glass", "glass_wine_red", 0.25, "cyl", fragile=True, size="small")
def _(p):
    stemmed(p, [(0.02, 0.01), (0.038, 0.04), (0.036, 0.08), (0.03, 0.1)], "M_wine_red", 0.45)


@prop("glassware", "decor_glass", "glass_sherry", 0.18, "cyl", fragile=True, size="small")
def _(p):
    stemmed(p, [(0.012, 0.005), (0.026, 0.04), (0.03, 0.07)], "M_whisky", 0.6, stem=0.06)


@prop("glassware", "decor_glass", "glass_tumbler", 0.3, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.038, 0), (0.04, 0.015), (0.04, 0.09)], "M_glass_thick", segs=20)
    p.cyl(0.036, 0.03, (0, 0, 0.03), "M_whisky", segs=16)
    p.box((0.03, 0.03, 0.03), (0.006, 0.004, 0.05), "M_water", rot=(20, 10, 30))


@prop("glassware", "decor_glass", "glass_half", 0.25, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.028, 0), (0.034, 0.1), (0.035, 0.11)], "M_glass", segs=18)
    p.lathe([(0.026, 0.005), (0.032, 0.085)], "M_ale", segs=14, cap_top=True)
    p.cyl(0.033, 0.01, (0, 0, 0.09), "M_foam", segs=14)


@prop("glassware", "decor_glass", "glass_shot", 0.08, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.02, 0), (0.024, 0.055)], "M_glass_thick", segs=14)
    p.cyl(0.02, 0.03, (0, 0, 0.02), "M_whisky", segs=12)


@prop("glassware", "decor_glass", "glass_flute", 0.2, "cyl", fragile=True, size="small")
def _(p):
    stemmed(p, [(0.012, 0.01), (0.022, 0.08), (0.024, 0.13)], "M_lager", 0.8, stem=0.07)


@prop("glassware", "decor_glass", "glass_snifter", 0.25, "cyl", fragile=True, size="small")
def _(p):
    stemmed(p, [(0.03, 0.02), (0.05, 0.05), (0.045, 0.09), (0.032, 0.11)], "M_whisky", 0.3, stem=0.04)


@prop("glassware", "decor_glass", "glass_empty_pint", 0.4, "cyl", fragile=True, size="small")
def _(p):
    nonic(p)
    p.lathe([(0.03, 0.006), (0.033, 0.02)], "M_ale", segs=14, cap_top=True)
    p.lathe([(0.036, 0.09), (0.0405, 0.12)], "M_foam", segs=16, cap_bottom=False, scale=(0.99, 0.99, 1))


# =====================================================================================
# Bottles (kind "bottle", plus "broken_bottle")
# =====================================================================================

def bottle(p, body, glass, label=None, cap="M_iron", liquid=None, label_band=None, segs=18):
    p.lathe(body, glass, segs=segs, cap_top=True)
    if liquid:
        inner = [(r * 0.86, z) for r, z in body if z < body[-1][1] * 0.6]
        p.lathe(inner, liquid, segs=12, cap_top=True)
    if label and label_band:
        r, z0, z1 = label_band
        p.band(r + 0.0015, z0, z1, "T_" + label, a0=-105, a1=105)
    top_r, top_z = body[-1]
    p.cyl(top_r + 0.002, 0.012, (0, 0, top_z + 0.004), cap, segs=12)


@prop("bottles", "bottle", "bottle_ale", 0.6, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.03, 0), (0.032, 0.005), (0.032, 0.15), (0.026, 0.19), (0.012, 0.22), (0.011, 0.25), (0.013, 0.26)],
           "M_glass_brown", "label_ale", label_band=(0.032, 0.04, 0.12))


@prop("bottles", "bottle", "bottle_stout", 0.6, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.031, 0), (0.033, 0.005), (0.033, 0.13), (0.02, 0.18), (0.012, 0.21), (0.012, 0.24), (0.014, 0.25)],
           "M_glass_brown", "label_stout", label_band=(0.033, 0.03, 0.11))


@prop("bottles", "bottle", "bottle_lager", 0.55, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.029, 0), (0.031, 0.005), (0.031, 0.14), (0.024, 0.18), (0.011, 0.22), (0.011, 0.26), (0.013, 0.27)],
           "M_glass_green", "label_lager", label_band=(0.031, 0.04, 0.11))


@prop("bottles", "bottle", "bottle_wine", 1.2, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.036, 0), (0.038, 0.005), (0.038, 0.2), (0.032, 0.24), (0.014, 0.27), (0.013, 0.31), (0.015, 0.315)],
           "M_glass_green", "label_wine", cap="M_wine_red", liquid="M_wine_red", label_band=(0.038, 0.06, 0.15))


@prop("bottles", "bottle", "bottle_whisky", 1.2, "box", fragile=True)
def _(p):
    p.box((0.085, 0.05, 0.19), (0, 0, 0.095), "M_glass", bevel=0.01, segs=2)
    p.box((0.075, 0.04, 0.12), (0, 0, 0.07), "M_whisky")
    p.lathe([(0.03, 0.188), (0.014, 0.22), (0.013, 0.25)], "M_glass", segs=12, cap_bottom=False, cap_top=True)
    p.cyl(0.016, 0.02, (0, 0, 0.255), "M_wood_dark", segs=10)
    p.quad(0.07, 0.07, (0, -0.0262, 0.1), "T_label_whisky", uv=(0, 0, 1, 1))


@prop("bottles", "bottle", "bottle_gin", 1.1, "box", fragile=True)
def _(p):
    p.box((0.07, 0.07, 0.2), (0, 0, 0.1), "M_glass_thick", bevel=0.008, segs=2)
    p.box((0.064, 0.064, 0.15), (0, 0, 0.078), "M_water")
    p.lathe([(0.03, 0.198), (0.014, 0.22), (0.013, 0.24)], "M_glass_thick", segs=12, cap_bottom=False, cap_top=True)
    p.cyl(0.016, 0.02, (0, 0, 0.245), "M_iron", segs=10)
    p.quad(0.06, 0.06, (0, -0.0362, 0.11), "T_label_gin")


@prop("bottles", "bottle", "bottle_rum", 1.1, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.04, 0), (0.042, 0.005), (0.042, 0.15), (0.03, 0.2), (0.015, 0.22), (0.014, 0.26), (0.016, 0.265)],
           "M_glass_brown", "label_rum", cap="M_wood_dark", liquid="M_whisky", label_band=(0.042, 0.04, 0.12))


@prop("bottles", "bottle", "bottle_vodka", 1.0, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.033, 0), (0.035, 0.005), (0.035, 0.22), (0.03, 0.25), (0.013, 0.28), (0.013, 0.31)],
           "M_glass", "label_vodka", cap="M_plastic_red", liquid="M_water", label_band=(0.035, 0.06, 0.15))


@prop("bottles", "bottle", "bottle_cider_flagon", 1.8, "cyl", fragile=True)
def _(p):
    p.lathe([(0.05, 0), (0.06, 0.03), (0.065, 0.12), (0.055, 0.18), (0.025, 0.22), (0.018, 0.25), (0.02, 0.26)],
            "M_stoneware", segs=18, cap_top=True)
    p.torus(0.03, 0.008, (0.055, 0, 0.2), "M_stoneware", rot=(90, 0, -20), segs=10, ring=5, arc=200)
    p.band(0.0655, 0.06, 0.12, "T_label_cider", a0=-80, a1=80)
    p.cyl(0.02, 0.02, (0, 0, 0.265), "M_wood_oak", segs=10)


@prop("bottles", "bottle", "bottle_champagne", 1.6, "cyl", fragile=True)
def _(p):
    bottle(p, [(0.042, 0), (0.044, 0.005), (0.044, 0.18), (0.035, 0.23), (0.016, 0.27), (0.015, 0.3), (0.017, 0.305)],
           "M_glass_green", None, cap="M_gilt")
    p.lathe([(0.0165, 0.25), (0.0175, 0.31)], "M_gilt", segs=12, cap_top=True, cap_bottom=False)


@prop("bottles", "broken_bottle", "bottle_broken", 0.4, "cyl", fragile=True)
def _(p):
    p.lathe([(0.03, 0), (0.032, 0.005), (0.032, 0.11), (0.031, 0.16)], "M_glass_brown", segs=14, jitter_top=0.05)
    p.band(0.0335, 0.03, 0.1, "T_label_ale", a0=-90, a1=90)


@prop("bottles", "decor_bottle", "bottle_ketchup", 0.4, "cyl", size="small")
def _(p):
    p.lathe([(0.025, 0), (0.028, 0.08), (0.02, 0.15), (0.012, 0.17)], "C_ketchup", segs=12, cap_top=True)
    p.cyl(0.014, 0.025, (0, 0, 0.18), "M_paper", segs=10)


@prop("bottles", "decor_bottle", "bottle_brown_sauce", 0.4, "cyl", size="small")
def _(p):
    p.lathe([(0.025, 0), (0.028, 0.08), (0.02, 0.15), (0.012, 0.17)], "C_brown_sauce", segs=12, cap_top=True)
    p.cyl(0.014, 0.025, (0, 0, 0.18), "M_plastic_black", segs=10)


@prop("bottles", "decor_bottle", "bottle_vinegar", 0.4, "cyl", fragile=True, size="small")
def _(p):
    bottle(p, [(0.025, 0), (0.026, 0.1), (0.01, 0.15), (0.009, 0.18)], "M_glass", None, liquid="C_vinegar")


@prop("bottles", "decor_bottle", "bottle_candle", 0.7, "cyl", fragile=True, size="small")
def _(p):
    """Wine bottle with a candle stuck in it, wax drips down the neck."""
    p.lathe([(0.036, 0), (0.038, 0.2), (0.014, 0.27), (0.013, 0.3)], "M_glass_green", segs=16, cap_top=True)
    p.cyl(0.011, 0.07, (0, 0, 0.335), "M_wax", segs=10)
    for i in range(6):
        a = math.tau * i / 6
        p.sphere(0.012, (math.cos(a) * 0.016, math.sin(a) * 0.016, 0.29 - i % 3 * 0.02), "M_wax",
                 scale=(0.7, 0.7, 1.8), segs=6, rings=4)
    p.sphere(0.01, (0, 0, 0.385), "M_flame", scale=(0.7, 0.7, 1.6), segs=6, rings=4)


# =====================================================================================
# Food and crockery (kinds "food", "plate"; decor snacks)
# =====================================================================================

def plate(p, r=0.13, mat="M_ceramic"):
    p.lathe([(r * 0.55, 0), (r * 0.6, 0.006), (r * 0.7, 0.008), (r, 0.018), (r * 1.02, 0.022)], mat, segs=24, both=True)
    p.torus(r * 0.98, 0.003, (0, 0, 0.021), "M_ceramic_blue", segs=24, ring=4)


def chips(p, cx, cy, n=14, seed=3):
    rnd = random.Random(seed)
    for i in range(n):
        p.box((0.012, 0.012, 0.07), (cx + rnd.uniform(-0.04, 0.04), cy + rnd.uniform(-0.03, 0.03), 0.03 + (i % 3) * 0.01),
              "C_chips", rot=(90 + rnd.uniform(-20, 20), rnd.uniform(-30, 30), rnd.uniform(0, 180)))


@prop("food", "food", "food_pie_chips", 0.7, "cyl", fragile=True)
def _(p):
    plate(p, 0.14)
    p.lathe([(0.055, 0.02), (0.06, 0.04), (0.058, 0.06), (0.04, 0.075), (0.0, 0.08)], "C_pastry", loc=(-0.035, 0.02, 0), segs=16)
    p.torus(0.058, 0.008, (-0.035, 0.02, 0.058), "C_pastry_dark", segs=20, ring=5)
    chips(p, 0.06, -0.02)
    for i in range(10):
        p.sphere(0.008, (0.02 + (i % 4) * 0.015, 0.07 + (i // 4) * 0.012, 0.026), "C_peas", segs=6, rings=4)


@prop("food", "food", "food_fish_chips", 0.7, "cyl", fragile=True)
def _(p):
    plate(p, 0.15)
    p.sphere(0.04, (-0.02, 0.02, 0.035), "C_batter", scale=(2.4, 1.0, 0.45), rot=(0, 0, 25), segs=12, rings=6)
    chips(p, 0.06, -0.05, seed=4)
    p.sphere(0.018, (-0.08, -0.06, 0.03), "C_lemon", scale=(1.2, 0.8, 0.6), segs=8, rings=5)
    for i in range(12):
        p.sphere(0.008, (0.02 + (i % 4) * 0.014, 0.06 + (i // 4) * 0.012, 0.026), "C_peas", segs=6, rings=4)


@prop("food", "food", "food_ploughmans", 0.8, "box", fragile=True)
def _(p):
    p.box((0.32, 0.2, 0.025), (0, 0, 0.0125), "M_wood_pine", bevel=0.006)
    p.sphere(0.05, (-0.09, 0.02, 0.05), "C_bread", scale=(1.3, 1, 0.8), segs=12, rings=6)
    p.box((0.07, 0.05, 0.04), (0.02, 0.04, 0.045), "C_cheese", rot=(0, 0, 20))
    p.box((0.05, 0.04, 0.035), (0.06, -0.04, 0.042), "C_cheese", rot=(0, 0, -15))
    p.cyl(0.025, 0.03, (0.11, 0.05, 0.04), "C_pickle", segs=10)
    p.sphere(0.03, (0.11, -0.04, 0.055), "C_apple", segs=10, rings=6)
    p.sphere(0.025, (-0.03, -0.06, 0.04), "C_ham", scale=(1.6, 1, 0.4), segs=10, rings=5)


@prop("food", "food", "food_bangers_mash", 0.7, "cyl", fragile=True)
def _(p):
    plate(p, 0.14)
    p.sphere(0.05, (0.02, 0.03, 0.03), "C_mash", scale=(1.3, 1, 0.6), segs=12, rings=6)
    for k in range(2):
        p.rod((-0.07, -0.05 + k * 0.035, 0.035), (0.05, -0.04 + k * 0.035, 0.035), 0.017, "C_sausage", segs=8)
    p.cyl(0.11, 0.004, (0, 0, 0.022), "C_gravy", segs=20)
    for i in range(10):
        p.sphere(0.008, (-0.07 + (i % 4) * 0.014, 0.06 + (i // 4) * 0.012, 0.028), "C_peas", segs=6, rings=4)


@prop("food", "food", "food_roast", 0.8, "cyl", fragile=True)
def _(p):
    plate(p, 0.15)
    for k in range(3):
        p.box((0.08, 0.06, 0.008), (0.02, -0.03 + k * 0.012, 0.03 + k * 0.006), "C_beef", rot=(10, 0, 15))
    p.lathe([(0.03, 0.02), (0.04, 0.035), (0.032, 0.06), (0.02, 0.04), (0.0, 0.03)], "C_yorkshire", loc=(-0.06, 0.04, 0), segs=12)
    for i in range(4):
        p.rod((-0.08 + i * 0.012, -0.07, 0.03), (-0.04 + i * 0.012, -0.03, 0.03), 0.007, "C_carrot", segs=6)
    p.cyl(0.12, 0.004, (0, 0, 0.022), "C_gravy", segs=20)


@prop("food", "food", "food_scotch_egg", 0.4, "cyl", fragile=True)
def _(p):
    plate(p, 0.1)
    p.sphere(0.035, (-0.02, 0, 0.055), "C_scotch_egg", segs=12, rings=8)
    p.sphere(0.035, (0.035, 0.0, 0.032), "C_scotch_egg", scale=(1, 1, 0.5), segs=12, rings=6)
    p.cyl(0.024, 0.004, (0.035, 0.0, 0.05), "C_egg_white", segs=14)
    p.cyl(0.012, 0.005, (0.035, 0.0, 0.052), "C_egg_yolk", segs=10)
    p.sphere(0.02, (0.04, 0.06, 0.03), "C_lettuce", scale=(1.6, 1, 0.4), segs=8, rings=5)


@prop("food", "food", "food_sandwich", 0.4, "box", fragile=True)
def _(p):
    plate(p, 0.12)
    for s in (-1, 1):
        p.box((0.09, 0.09, 0.012), (s * 0.03, 0, 0.03), "C_bread", rot=(0, 0, 45 * s))
        p.box((0.092, 0.092, 0.006), (s * 0.03, 0, 0.039), "C_ham", rot=(0, 0, 45 * s))
        p.box((0.095, 0.095, 0.004), (s * 0.03, 0, 0.044), "C_lettuce", rot=(0, 0, 45 * s))
        p.box((0.09, 0.09, 0.012), (s * 0.03, 0, 0.052), "C_bread", rot=(0, 0, 45 * s))


@prop("food", "plate", "plate_empty", 0.4, "cyl", fragile=True)
def _(p):
    plate(p, 0.13)


@prop("food", "plate", "plate_crumbs", 0.4, "cyl", fragile=True)
def _(p):
    plate(p, 0.13)
    p.box((0.12, 0.008, 0.004), (0.0, -0.02, 0.025), "M_iron", rot=(0, 0, 30))
    p.box((0.13, 0.01, 0.004), (0.0, 0.02, 0.025), "M_iron", rot=(0, 0, 25))
    for i in range(5):
        p.box((0.01, 0.01, 0.005), (-0.05 + i * 0.02, 0.05, 0.024), "C_pastry_dark", rot=(0, 0, i * 30))


@prop("food", "plate", "plate_chips_basket", 0.3, "cyl")
def _(p):
    p.lathe([(0.06, 0), (0.08, 0.05), (0.085, 0.055)], "M_iron", segs=10, both=True)
    chips(p, 0, 0, 20, seed=9)


def packet(p, label):
    p.box((0.11, 0.025, 0.15), (0, 0, 0.075), "M_paper", bevel=0.01, segs=2)
    p.quad(0.1, 0.13, (0, -0.0136, 0.075), "T_" + label)
    p.quad(0.1, 0.13, (0, 0.0136, 0.075), "T_" + label, rot=(0, 0, 180))


@prop("food", "snack", "snack_crisps", 0.04, "box", size="small")
def _(p):
    packet(p, "label_crisps")


@prop("food", "snack", "snack_crisps_sv", 0.04, "box", size="small")
def _(p):
    packet(p, "label_crisps2")


@prop("food", "snack", "snack_crisps_co", 0.04, "box", size="small")
def _(p):
    packet(p, "label_crisps3")


@prop("food", "snack", "snack_scratchings", 0.05, "box", size="small")
def _(p):
    packet(p, "label_scratchings")


@prop("food", "snack", "snack_peanuts_bowl", 0.3, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.03, 0), (0.06, 0.035), (0.062, 0.04)], "M_ceramic_blue", segs=16, both=True)
    rnd = random.Random(5)
    for i in range(20):
        p.sphere(0.008, (rnd.uniform(-0.035, 0.035), rnd.uniform(-0.035, 0.035), 0.03 + rnd.uniform(0, 0.01)),
                 "C_peanut", scale=(1.6, 1, 1), rot=(0, 0, rnd.uniform(0, 180)), segs=6, rings=4)


@prop("food", "snack", "snack_pickled_eggs", 2.0, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.07, 0), (0.08, 0.02), (0.08, 0.2), (0.06, 0.23), (0.06, 0.25)], "M_glass_thick", segs=18)
    p.cyl(0.076, 0.17, (0, 0, 0.11), "M_cider", segs=16)
    for i in range(9):
        a = i * 2.4
        p.sphere(0.022, (math.cos(a) * 0.04, math.sin(a) * 0.04, 0.04 + i * 0.017), "C_pickled_egg",
                 scale=(1, 1, 1.3), segs=8, rings=6)
    p.cyl(0.065, 0.03, (0, 0, 0.26), "M_iron", segs=16)


# =====================================================================================
# Bar bits (decor, small)
# =====================================================================================

@prop("barbits", "decor_small", "ashtray_glass", 0.5, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.05, 0), (0.06, 0.03), (0.055, 0.032), (0.04, 0.012)], "M_glass_thick", segs=20, both=True)
    for i in range(3):
        a = math.tau * i / 3
        p.rod((math.cos(a) * 0.02, math.sin(a) * 0.02, 0.016), (math.cos(a) * 0.06, math.sin(a) * 0.06, 0.03),
              0.004, "M_paper", segs=5)


@prop("barbits", "decor_small", "ashtray_tin", 0.2, "cyl", size="small")
def _(p):
    p.lathe([(0.055, 0), (0.06, 0.02), (0.058, 0.021)], "M_pewter", segs=16, both=True)


@prop("barbits", "decor_small", "beermat_stack", 0.05, "box", size="small")
def _(p):
    for i in range(4):
        p.box((0.1, 0.1, 0.0025), (0.003 * i, -0.002 * i, 0.0015 + i * 0.0026), "M_paper", rot=(0, 0, i * 7))
    p.quad(0.1, 0.1, (0.009, -0.006, 0.0115), "T_beermat_0", rot=(-90, 0, 21))


@prop("barbits", "decor_small", "candle_stick", 0.6, "cyl", size="small")
def _(p):
    p.lathe([(0.06, 0), (0.06, 0.01), (0.015, 0.02), (0.012, 0.08), (0.03, 0.1), (0.02, 0.11)], "M_brass", segs=14)
    p.torus(0.025, 0.006, (0.07, 0, 0.02), "M_brass", rot=(90, 0, 0), segs=10, ring=4)
    p.cyl(0.011, 0.12, (0, 0, 0.17), "M_wax", segs=10)
    p.sphere(0.01, (0, 0, 0.245), "M_flame", scale=(0.7, 0.7, 1.6), segs=6, rings=4)


@prop("barbits", "decor_small", "salt_pepper", 0.2, "box", fragile=True, size="small")
def _(p):
    for x, m in ((-0.025, "M_ceramic"), (0.025, "M_ceramic_blue")):
        p.lathe([(0.018, 0), (0.02, 0.05), (0.012, 0.08), (0.0, 0.085)], m, loc=(x, 0, 0), segs=12)


@prop("barbits", "decor_small", "bell_brass", 0.8, "cyl", size="small")
def _(p):
    p.lathe([(0.05, 0), (0.048, 0.01), (0.03, 0.05), (0.022, 0.08), (0.0, 0.09)], "M_brass", segs=16)
    p.lathe([(0.008, 0.09), (0.008, 0.15), (0.015, 0.16), (0.0, 0.18)], "M_wood_dark", segs=10)


@prop("barbits", "decor_small", "tip_jar", 0.6, "cyl", fragile=True, size="small")
def _(p):
    p.lathe([(0.05, 0), (0.055, 0.01), (0.055, 0.14), (0.045, 0.16)], "M_glass", segs=16)
    rnd = random.Random(2)
    for i in range(12):
        p.cyl(0.012, 0.003, (rnd.uniform(-0.03, 0.03), rnd.uniform(-0.03, 0.03), 0.01 + i * 0.004),
              "M_copper" if i % 3 else "M_brass", segs=8, rot=(rnd.uniform(-30, 30), 0, 0))


@prop("barbits", "decor_small", "ice_bucket", 0.8, "cyl", size="small")
def _(p):
    p.lathe([(0.06, 0), (0.08, 0.15), (0.082, 0.155)], "M_chrome", segs=18, both=True)
    for s in (-1, 1):
        p.torus(0.02, 0.005, (s * 0.085, 0, 0.12), "M_chrome", rot=(90, 0, 90), segs=8, ring=4, arc=180)


@prop("barbits", "decor_small", "pump_clip_stand", 0.4, "box", size="small")
def _(p):
    p.box((0.12, 0.03, 0.16), (0, 0, 0.08), "M_black_gloss", bevel=0.01)
    p.quad(0.1, 0.1, (0, -0.0155, 0.09), "T_beermat_2")


@prop("barbits", "decor_small", "menu_stand", 0.4, "box", size="small")
def _(p):
    p.box((0.12, 0.05, 0.015), (0, 0, 0.0075), "M_wood_dark")
    p.box((0.1, 0.004, 0.15), (0, 0, 0.09), "M_paper", rot=(-8, 0, 0))
    p.quad(0.09, 0.13, (0, -0.0035, 0.09), "T_chalkboard", rot=(-8, 0, 0))


# =====================================================================================
# Pictures and wall decor (pinned to walls). Back at Y=0, facing -Y, origin at the centre.
# =====================================================================================

def frame(p, w, h, art, mat="M_gilt", border=0.05, depth=0.035, ornate=False):
    b, d = border, depth
    for z in (-h / 2 - b / 2, h / 2 + b / 2):
        p.box((w + 2 * b, d, b), (0, -d / 2, z), mat, bevel=0.008 if ornate else 0.004, segs=2)
    for x in (-w / 2 - b / 2, w / 2 + b / 2):
        p.box((b, d, h), (x, -d / 2, 0), mat, bevel=0.008 if ornate else 0.004, segs=2)
    if ornate:
        for x in (-w / 2 - b / 2, w / 2 + b / 2):
            for z in (-h / 2 - b / 2, h / 2 + b / 2):
                p.sphere(b * 0.45, (x, -d, z), mat, segs=8, rings=5)
        p.sphere(b * 0.7, (0, -d * 0.9, h / 2 + b * 0.7), mat, scale=(2.2, 0.6, 1), segs=8, rings=5)
    p.box((w, 0.01, h), (0, -0.005, 0), "M_wood_dark")
    p.quad(w, h, (0, -0.0105, 0), "T_" + art)


@prop("pictures", "picture", "picture_landscape", 3, "box", pinned=True)
def _(p):
    frame(p, 0.6, 0.45, "painting_landscape", ornate=True)


@prop("pictures", "picture", "picture_portrait", 3, "box", pinned=True)
def _(p):
    frame(p, 0.4, 0.53, "painting_portrait", "M_gilt", 0.07, ornate=True)


@prop("pictures", "picture", "picture_hunt", 2.5, "box", pinned=True)
def _(p):
    frame(p, 0.56, 0.42, "painting_hunt", "M_wood_dark", 0.045)


@prop("pictures", "picture", "picture_ship", 2.5, "box", pinned=True)
def _(p):
    frame(p, 0.5, 0.375, "painting_ship", "M_wood_black", 0.04)


@prop("pictures", "picture", "picture_bull", 2.5, "box", pinned=True)
def _(p):
    frame(p, 0.48, 0.36, "painting_bull", "M_wood_oak", 0.05)


@prop("pictures", "picture", "picture_team_photo", 1.5, "box", pinned=True)
def _(p):
    frame(p, 0.36, 0.27, "photo_team", "M_wood_black", 0.03, depth=0.02)


@prop("pictures", "picture", "mirror_brewery", 6, "box", pinned=True, fragile=True)
def _(p):
    frame(p, 0.8, 0.6, "mirror_brewery", "M_wood_mahogany", 0.07, ornate=True)


@prop("pictures", "picture", "chalkboard_menu", 4, "box", pinned=True)
def _(p):
    frame(p, 0.5, 0.75, "chalkboard", "M_wood_oak", 0.05)


@prop("pictures", "picture", "wall_clock", 2, "cyl", pinned=True)
def _(p):
    p.torus(0.17, 0.025, (0, -0.03, 0), "M_wood_dark", rot=(90, 0, 0), segs=28, ring=6)
    p.cyl(0.17, 0.03, (0, -0.015, 0), "M_wood_dark", rot=(90, 0, 0), segs=28)
    p.cyl(0.15, 0.004, (0, -0.032, 0), "M_ivory", rot=(90, 0, 0), segs=28)
    for i in range(12):
        a = math.tau * i / 12
        p.box((0.008, 0.004, 0.025), (math.sin(a) * 0.125, -0.036, math.cos(a) * 0.125), "M_black_gloss", rot=(0, math.degrees(a), 0))
    p.box((0.008, 0.004, 0.09), (0.02, -0.04, 0.03), "M_black_gloss", rot=(0, 35, 0))
    p.box((0.006, 0.004, 0.12), (-0.045, -0.042, 0.03), "M_black_gloss", rot=(0, -60, 0))


@prop("pictures", "picture", "horse_brasses", 2, "box", pinned=True)
def _(p):
    p.box((0.06, 0.008, 0.8), (0, -0.004, 0), "M_leather_brown")
    for k in range(4):
        z = 0.3 - k * 0.2
        p.torus(0.055, 0.008, (0, -0.012, z), "M_brass", rot=(90, 0, 0), segs=18, ring=4)
        p.cyl(0.035, 0.006, (0, -0.012, z), "M_brass", rot=(90, 0, 0), segs=6 if k % 2 else 18)


@prop("pictures", "picture", "plate_rack_plates", 3, "box", pinned=True, fragile=True)
def _(p):
    p.box((0.9, 0.08, 0.025), (0, -0.04, -0.1), "M_wood_oak")
    p.box((0.9, 0.01, 0.02), (0, -0.075, -0.05), "M_wood_oak")
    for i in range(4):
        x = -0.33 + i * 0.22
        p.cyl(0.095, 0.012, (x, -0.035, 0.0), "M_ceramic" if i % 2 else "M_ceramic_blue", rot=(80, 0, 0), segs=22)
        p.torus(0.07, 0.004, (x, -0.042, 0.0), "M_ceramic_blue" if i % 2 else "M_ceramic", rot=(80, 0, 0), segs=22, ring=4)


@prop("pictures", "picture", "antlers", 3, "box", pinned=True)
def _(p):
    p.lathe([(0.11, 0), (0.1, 0.02), (0.0, 0.03)], "M_wood_dark", rot=(90, 0, 0), segs=6, scale=(1, 1.3, 1))
    for s in (-1, 1):
        pts = [(0, -0.04, 0.03), (s * 0.12, -0.08, 0.15), (s * 0.2, -0.09, 0.32), (s * 0.18, -0.08, 0.45)]
        for a, b in zip(pts, pts[1:]):
            p.rod(a, b, 0.014, "M_bone", segs=6, r2=0.011)
        for t, (x, y, z) in enumerate(pts[1:3]):
            p.rod((x, y, z), (x + s * 0.08, y - 0.03, z + 0.1), 0.01, "M_bone", segs=5, r2=0.004)


@prop("pictures", "picture", "fish_case", 4, "box", pinned=True, fragile=True)
def _(p):
    p.box((0.7, 0.15, 0.3), (0, -0.075, 0), "M_wood_dark", bevel=0.01)
    p.box((0.66, 0.01, 0.26), (0, -0.152, 0), "M_glass")
    p.box((0.64, 0.005, 0.24), (0, -0.01, 0), "C_lettuce")
    p.sphere(0.06, (0, -0.075, 0), "C_fish", scale=(4.5, 1, 1.6), segs=14, rings=8)
    p.box((0.08, 0.02, 0.12), (0.3, -0.075, 0), "C_fish", rot=(0, 0, 0))


@prop("pictures", "picture", "pub_sign_small", 2, "box", pinned=True)
def _(p):
    p.box((0.5, 0.025, 0.4), (0, -0.0125, 0), "M_black_gloss", bevel=0.006)
    p.quad(0.46, 0.36, (0, -0.026, 0), "T_mirror_brewery")


@prop("pictures", "picture", "shelf_bottles", 6, "box", pinned=True, fragile=True)
def _(p):
    """Wall shelf with a few old bottles and a stone jar."""
    p.box((0.9, 0.18, 0.03), (0, -0.09, -0.1), "M_wood_oak", bevel=0.005)
    for s in (-1, 1):
        p.box((0.025, 0.15, 0.12), (s * 0.35, -0.075, -0.17), "M_wood_oak", rot=(0, 0, 0))
    for i, (x, m, h) in enumerate(((-0.33, "M_glass_green", 0.22), (-0.2, "M_glass_brown", 0.18), (-0.08, "M_glass_blue", 0.15),
                                    (0.08, "M_stoneware", 0.2), (0.22, "M_glass_green", 0.26), (0.33, "M_glass_brown", 0.16))):
        p.lathe([(0.03, 0), (0.032, h * 0.6), (0.012, h * 0.85), (0.012, h)], m, loc=(x, -0.09, -0.085), segs=12, cap_top=True)


# =====================================================================================
# Furniture (decor, big)
# =====================================================================================

@prop("furniture", "furniture", "welsh_dresser", 90, "box", size="big")
def _(p):
    """Base cupboard with a plate rack above, crockery on the shelves. Back against the wall."""
    p.box((1.4, 0.5, 0.85), (0, -0.25, 0.425), "M_wood_oak", bevel=0.01)
    p.box((1.46, 0.54, 0.04), (0, -0.27, 0.87), "M_wood_oak", bevel=0.01)
    for x in (-0.35, 0.35):
        p.box((0.62, 0.02, 0.6), (x, -0.505, 0.38), "M_wood_oak", bevel=0.008)
        p.sphere(0.015, (x + (0.25 if x < 0 else -0.25), -0.52, 0.45), "M_brass", segs=8, rings=5)
    p.box((1.4, 0.03, 0.2), (0, -0.5, 0.78), "M_wood_oak")
    for s in (-1, 1):
        p.box((0.04, 0.25, 1.05), (s * 0.66, -0.125, 1.42), "M_wood_oak")
    p.box((1.3, 0.015, 1.05), (0, -0.008, 1.42), "M_wood_painted_cream")
    p.box((1.46, 0.32, 0.08), (0, -0.16, 1.98), "M_wood_oak", bevel=0.015, segs=2)
    for k, z in enumerate((1.15, 1.48, 1.8)):
        p.box((1.3, 0.2, 0.025), (0, -0.14, z), "M_wood_oak")
        for i in range(5):
            x = -0.5 + i * 0.25
            p.cyl(0.1, 0.012, (x, -0.06, z + 0.11), "M_ceramic_blue" if (i + k) % 2 else "M_ceramic", rot=(75, 0, 0), segs=20)
        if k == 0:
            for i in range(6):
                p.torus(0.025, 0.005, (-0.55 + i * 0.22, -0.2, z - 0.06), "M_ceramic", rot=(0, 90, 0), segs=8, ring=4)
                p.lathe([(0.03, 0), (0.035, 0.07)], "M_ceramic_blue", loc=(-0.55 + i * 0.22, -0.2, z - 0.15), segs=10)


@prop("furniture", "furniture", "bookcase", 70, "box", size="big")
def _(p):
    for s in (-1, 1):
        p.box((0.03, 0.32, 1.9), (s * 0.485, -0.16, 0.95), "M_wood_dark", bevel=0.005)
    p.box((1.04, 0.34, 0.05), (0, -0.17, 1.925), "M_wood_dark", bevel=0.01)
    p.box((0.94, 0.3, 0.1), (0, -0.16, 0.05), "M_wood_dark")
    p.box((0.94, 0.02, 1.8), (0, -0.01, 0.95), "M_wood_dark")
    rnd = random.Random(8)
    cols = ["C_book_red", "C_book_green", "C_book_blue", "C_book_brown"]
    for k in range(5):
        z = 0.1 + k * 0.36
        if k:
            p.box((0.94, 0.28, 0.025), (0, -0.16, z), "M_wood_dark")
        x = -0.45
        while x < 0.43:
            w = rnd.uniform(0.025, 0.05)
            h = rnd.uniform(0.2, 0.3)
            tilt = rnd.uniform(-8, 8) if rnd.random() < 0.2 else 0
            p.box((w, 0.2, h), (x + w / 2, -0.17, z + h / 2 + 0.012), rnd.choice(cols), rot=(0, tilt, 0))
            x += w + 0.003


@prop("furniture", "furniture", "grandfather_clock", 60, "box", size="big")
def _(p):
    p.box((0.5, 0.3, 0.4), (0, -0.15, 0.2), "M_wood_mahogany", bevel=0.01)
    p.box((0.38, 0.24, 1.1), (0, -0.14, 0.95), "M_wood_mahogany", bevel=0.01)
    p.box((0.46, 0.3, 0.5), (0, -0.15, 1.75), "M_wood_mahogany", bevel=0.01)
    p.box((0.52, 0.34, 0.06), (0, -0.17, 2.02), "M_wood_mahogany", bevel=0.01)
    p.sphere(0.05, (0, -0.17, 2.1), "M_gilt", segs=8, rings=5)
    p.cyl(0.16, 0.01, (0, -0.305, 1.75), "M_ivory", rot=(90, 0, 0), segs=24)
    p.torus(0.16, 0.012, (0, -0.31, 1.75), "M_gilt", rot=(90, 0, 0), segs=24, ring=4)
    p.box((0.006, 0.004, 0.1), (0.02, -0.315, 1.78), "M_black_gloss", rot=(0, 30, 0))
    p.box((0.005, 0.004, 0.13), (-0.03, -0.317, 1.77), "M_black_gloss", rot=(0, -50, 0))
    p.box((0.2, 0.01, 0.8), (0, -0.265, 1.0), "M_glass")
    p.rod((0, -0.2, 1.4), (0, -0.2, 0.75), 0.004, "M_brass", segs=5)
    p.cyl(0.06, 0.012, (0, -0.2, 0.72), "M_brass", rot=(90, 0, 0), segs=16)


@prop("furniture", "furniture", "coat_stand", 9, "cyl", size="big")
def _(p):
    p.lathe([(0.025, 0), (0.025, 1.75), (0.04, 1.78), (0.0, 1.85)], "M_wood_dark", segs=10)
    for i in range(3):
        a = math.tau * i / 3
        p.rod((0, 0, 0.25), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.0), 0.02, "M_wood_dark", segs=6)
    for i in range(4):
        a = math.tau * i / 4 + 0.4
        p.rod((0, 0, 1.6), (math.cos(a) * 0.17, math.sin(a) * 0.17, 1.72), 0.012, "M_brass", segs=6)
    p.sphere(0.12, (0.13, 0.0, 1.35), "C_coat", scale=(1.1, 0.8, 2.4), segs=10, rings=8)
    p.cyl(0.11, 0.08, (-0.1, 0.08, 1.75), "C_coat", segs=14, rot=(10, 0, 0))
    p.cyl(0.16, 0.01, (-0.1, 0.08, 1.71), "C_coat", segs=14, rot=(10, 0, 0))
    p.sphere(0.04, (-0.1, -0.12, 1.5), "C_scarf", scale=(1, 0.6, 5), segs=8, rings=6)


@prop("furniture", "furniture", "sideboard", 55, "box", size="big")
def _(p):
    p.box((1.5, 0.48, 0.82), (0, -0.24, 0.47), "M_wood_mahogany", bevel=0.012)
    p.box((1.56, 0.52, 0.04), (0, -0.26, 0.9), "M_wood_mahogany", bevel=0.01)
    for x in (-0.6, -0.2, 0.2, 0.6):
        p.box((0.36, 0.02, 0.5), (x, -0.485, 0.45), "M_wood_mahogany", bevel=0.01)
        p.cyl(0.012, 0.02, (x, -0.5, 0.65), "M_brass", rot=(90, 0, 0), segs=8)
    for x in (-0.7, 0.7):
        for y in (-0.05, -0.43):
            turned_leg(p, x, y, 0.08, "M_wood_mahogany", r=0.03)


@prop("furniture", "furniture", "bench", 25, "box", size="big")
def _(p):
    p.box((1.6, 0.36, 0.05), (0, 0, 0.45), "M_wood_oak", bevel=0.01)
    for x in (-0.65, 0.65):
        p.box((0.05, 0.32, 0.43), (x, 0, 0.215), "M_wood_oak")
    p.box((1.3, 0.04, 0.1), (0, 0, 0.25), "M_wood_oak")


@prop("furniture", "furniture", "sea_chest", 30, "box", size="big")
def _(p):
    p.box((0.9, 0.5, 0.45), (0, 0, 0.225), "M_wood_dark", bevel=0.01)
    p.box((0.92, 0.52, 0.12), (0, 0, 0.5), "M_wood_dark", bevel=0.03, segs=3)
    for x in (-0.3, 0.3):
        p.box((0.04, 0.53, 0.58), (x, 0, 0.29), "M_iron")
    p.box((0.08, 0.02, 0.1), (0, -0.265, 0.42), "M_brass")
    for s in (-1, 1):
        p.torus(0.04, 0.008, (s * 0.46, 0, 0.32), "M_iron", rot=(0, 90, 0), segs=10, ring=4, arc=180)


@prop("furniture", "furniture", "umbrella_stand", 6, "cyl", size="big")
def _(p):
    p.lathe([(0.12, 0), (0.12, 0.6), (0.13, 0.62)], "M_ceramic_blue", segs=18, both=True)
    for i, (a, c) in enumerate(((0.3, "C_paint_black"), (2.2, "C_paint_red"), (4.0, "C_book_green"))):
        x, y = math.cos(a) * 0.05, math.sin(a) * 0.05
        p.rod((x, y, 0.05), (x * 2, y * 2, 0.95), 0.012, "M_wood_dark", segs=6)
        p.cyl(0.04, 0.4, (x * 1.8, y * 1.8, 0.7), c, segs=8, r2=0.015)


@prop("furniture", "furniture", "crate_bottles", 12, "box", size="big")
def _(p):
    p.box((0.45, 0.32, 0.03), (0, 0, 0.015), "M_wood_pine")
    for s in (-1, 1):
        p.box((0.45, 0.02, 0.28), (0, s * 0.15, 0.14), "M_wood_pine")
        p.box((0.02, 0.32, 0.28), (s * 0.215, 0, 0.14), "M_wood_pine")
    for i in range(4):
        for j in range(3):
            p.lathe([(0.03, 0.03), (0.03, 0.18), (0.012, 0.24), (0.012, 0.28)], "M_glass_brown",
                    loc=(-0.16 + i * 0.105, -0.09 + j * 0.09, 0), segs=10, cap_top=True)


@prop("furniture", "furniture", "keg_steel", 15, "cyl", size="big")
def _(p):
    p.lathe([(0.2, 0), (0.2, 0.04), (0.19, 0.06), (0.2, 0.08), (0.2, 0.52), (0.19, 0.54), (0.2, 0.56), (0.2, 0.6)],
            "M_chrome", segs=24, cap_top=True)
    p.cyl(0.04, 0.04, (0, 0, 0.62), "M_iron", segs=12)
    for s in (-1, 1):
        p.box((0.1, 0.02, 0.03), (s * 0.12, 0, 0.59), "M_chrome")


@prop("furniture", "furniture", "cask_small", 20, "cyl", size="big")
def _(p):
    """Firkin on its side on a wooden stillage, with a tap."""
    prof = [(0.17, -0.22), (0.2, -0.1), (0.21, 0.0), (0.2, 0.1), (0.17, 0.22)]
    p.lathe(prof, "M_wood_oak", loc=(0, 0, 0.3), rot=(90, 0, 0), segs=18, cap_top=True)
    for y, r in ((-0.18, 0.18), (-0.07, 0.205), (0.07, 0.205), (0.18, 0.18)):
        p.lathe([(r + 0.006, -0.015), (r + 0.006, 0.015)], "M_iron", loc=(0, y, 0.3), rot=(90, 0, 0), segs=18, cap_bottom=False)
    p.cyl(0.015, 0.08, (0, -0.25, 0.25), "M_brass", rot=(90, 0, 0), segs=8)
    p.box((0.05, 0.02, 0.05), (0, -0.29, 0.24), "M_brass")
    for x in (-0.15, 0.15):
        p.box((0.06, 0.5, 0.12), (x, 0, 0.06), "M_wood_dark")


@prop("furniture", "furniture", "wine_rack", 25, "box", size="big")
def _(p):
    p.box((0.8, 0.3, 0.03), (0, -0.15, 1.0), "M_wood_pine")
    p.box((0.8, 0.3, 0.03), (0, -0.15, 0.015), "M_wood_pine")
    for x in (-0.39, 0.39):
        p.box((0.03, 0.3, 1.0), (x, -0.15, 0.5), "M_wood_pine")
    for i in range(5):
        for j in range(4):
            if (i * 3 + j) % 5 == 4:
                continue
            p.lathe([(0.036, -0.13), (0.036, 0.06), (0.014, 0.12), (0.014, 0.16)], "M_glass_green",
                    loc=(-0.3 + i * 0.15, -0.15, 0.15 + j * 0.23), rot=(90, 0, 0), segs=10, cap_top=True)


@prop("furniture", "furniture", "armchair_wingback", 35, "box", size="big")
def _(p):
    p.box((0.8, 0.75, 0.42), (0, 0, 0.27), "M_leather_green", bevel=0.04, segs=3)
    p.box((0.62, 0.6, 0.1), (0, 0.05, 0.5), "M_leather_green", bevel=0.04, segs=3)
    p.box((0.8, 0.16, 0.75), (0, -0.33, 0.85), "M_leather_green", bevel=0.05, segs=3)
    for s in (-1, 1):
        p.box((0.12, 0.7, 0.25), (s * 0.36, 0.0, 0.58), "M_leather_green", bevel=0.05, segs=3)
        p.box((0.1, 0.3, 0.5), (s * 0.37, -0.22, 0.95), "M_leather_green", bevel=0.04, segs=3)
    for x in (-0.33, 0.33):
        for y in (-0.3, 0.3):
            p.lathe([(0.025, 0), (0.035, 0.06)], "M_wood_mahogany", loc=(x, y, 0), segs=8, cap_top=True)
    for x in (-0.2, 0, 0.2):
        for z in (0.75, 0.95):
            p.sphere(0.012, (x, -0.415, z), "M_leather_green", segs=6, rings=4)


@prop("furniture", "furniture", "fruit_machine", 110, "box", size="big")
def _(p):
    p.box((0.7, 0.55, 1.75), (0, -0.275, 0.875), "M_black_gloss", bevel=0.02)
    p.box((0.62, 0.02, 0.3), (0, -0.555, 1.45), "C_screen")
    for i in range(3):
        p.cyl(0.08, 0.14, (-0.18 + i * 0.18, -0.52, 1.1), "C_reel", rot=(0, 90, 0), segs=16)
    p.box((0.6, 0.03, 0.08), (0, -0.56, 1.66), "C_light_amber")
    for i in range(6):
        p.sphere(0.022, (-0.25 + i * 0.1, -0.565, 0.85), "C_light_red" if i % 2 else "C_light_amber", segs=8, rings=5)
    p.box((0.6, 0.12, 0.06), (0, -0.6, 0.78), "M_chrome")
    p.rod((0.36, -0.3, 1.1), (0.45, -0.3, 1.2), 0.015, "M_chrome")
    p.sphere(0.04, (0.46, -0.3, 1.22), "M_plastic_red", segs=10, rings=6)
    p.box((0.3, 0.05, 0.12), (0, -0.55, 0.3), "M_chrome")


@prop("furniture", "furniture", "jukebox", 120, "box", size="big")
def _(p):
    p.box((0.9, 0.6, 1.0), (0, -0.3, 0.5), "M_wood_mahogany", bevel=0.03, segs=2)
    p.cyl(0.45, 0.6, (0, -0.3, 1.0), "M_wood_mahogany", rot=(90, 0, 0), segs=24)
    p.torus(0.42, 0.04, (0, -0.61, 1.0), "C_light_amber", rot=(90, 0, 0), segs=24, ring=6, arc=180)
    p.box((0.6, 0.02, 0.35), (0, -0.605, 0.92), "M_glass")
    p.box((0.7, 0.02, 0.3), (0, -0.605, 0.4), "M_chrome")
    for s in (-1, 1):
        p.box((0.06, 0.04, 1.2), (s * 0.43, -0.6, 0.62), "C_light_red", bevel=0.02)


@prop("furniture", "furniture", "aspidistra", 8, "cyl", size="big")
def _(p):
    p.lathe([(0.12, 0), (0.17, 0.25), (0.18, 0.28)], "M_ceramic_blue", segs=16, both=True)
    p.cyl(0.16, 0.02, (0, 0, 0.26), "M_soil", segs=14)
    rnd = random.Random(11)
    for i in range(14):
        a = rnd.uniform(0, math.tau)
        tilt = rnd.uniform(20, 55)
        p.sphere(0.05, (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.55), "M_foliage", scale=(0.7, 0.15, 4.0),
                 rot=(tilt * math.sin(a), -tilt * math.cos(a) * 0 + tilt * math.cos(a), 0), segs=8, rings=6)


@prop("furniture", "furniture", "log_basket", 15, "cyl", size="big")
def _(p):
    p.lathe([(0.2, 0), (0.25, 0.3), (0.26, 0.32)], "M_rope", segs=16, both=True)
    for i in range(5):
        p.cyl(0.05, 0.42, (-0.12 + (i % 3) * 0.12, -0.06 + (i // 3) * 0.1, 0.3 + (i // 3) * 0.08), "M_wood_oak",
              rot=(0, 90, i * 20), segs=8)


@prop("furniture", "furniture", "coal_scuttle", 7, "cyl", size="big")
def _(p):
    p.lathe([(0.12, 0), (0.15, 0.18), (0.13, 0.3)], "M_copper", segs=16, cap_top=False, both=True)
    p.cyl(0.12, 0.05, (0, 0, 0.27), "C_paint_black", segs=12)
    p.torus(0.13, 0.008, (0, 0, 0.33), "M_brass", rot=(90, 0, 0), segs=16, ring=4, arc=180)


# =====================================================================================
# Piano and the games room
# =====================================================================================

@prop("piano", "piano", "piano_upright", 230, "box", size="big")
def _(p):
    W, D = 1.5, 0.6
    p.box((W, 0.32, 1.25), (0, -0.16, 0.625), "M_wood_black", bevel=0.015)
    p.box((W + 0.04, 0.36, 0.04), (0, -0.18, 1.27), "M_wood_black", bevel=0.01)
    p.box((W, 0.3, 0.12), (0, -0.47, 0.71), "M_wood_black", bevel=0.01)
    for s in (-1, 1):
        p.box((0.07, 0.3, 0.78), (s * (W / 2 - 0.035), -0.47, 0.38 + 0.02), "M_wood_black", bevel=0.01)
        p.lathe([(0.03, 0), (0.04, 0.05), (0.028, 0.15)], "M_wood_black", loc=(s * (W / 2 - 0.035), -0.58, 0), segs=8, cap_top=True)
    # 52 white keys and the black ones.
    n = 52
    kw = (W - 0.16) / n
    for i in range(n):
        p.box((kw * 0.92, 0.14, 0.02), (-(W - 0.16) / 2 + kw * (i + 0.5), -0.55, 0.78), "M_ivory")
    pattern = [1, 1, 0, 1, 1, 1, 0]
    for i in range(n - 1):
        if pattern[(i + 5) % 7]:
            p.box((kw * 0.55, 0.085, 0.02), (-(W - 0.16) / 2 + kw * (i + 1), -0.52, 0.795), "M_black_gloss")
    p.box((W - 0.16, 0.02, 0.1), (0, -0.335, 0.86), "M_wood_black")
    p.box((0.5, 0.01, 0.3), (0, -0.33, 1.02), "M_paper", rot=(-12, 0, 0))
    for s in (-1, 1):
        p.lathe([(0.03, 0), (0.035, 0.03), (0.012, 0.05), (0.012, 0.12)], "M_brass", loc=(s * 0.55, -0.37, 0.92), segs=10)
        p.cyl(0.01, 0.05, (s * 0.55, -0.37, 1.06), "M_wax", segs=8)
    p.box((0.6, 0.02, 0.35), (0, -0.325, 0.25), "M_wood_black")
    for x in (-0.06, 0, 0.06):
        p.box((0.03, 0.08, 0.015), (x, -0.36, 0.05), "M_brass")
    # A pint left on top, as is tradition.
    p.lathe([(0.03, 1.29), (0.036, 1.38), (0.042, 1.43)], "M_glass", loc=(0.5, -0.15, 0), segs=14)


@prop("piano", "furniture", "piano_stool", 12, "box", size="big")
def _(p):
    p.box((0.6, 0.35, 0.08), (0, 0, 0.48), "M_leather_red", bevel=0.025, segs=3)
    p.box((0.58, 0.33, 0.06), (0, 0, 0.42), "M_wood_black")
    for x in (-0.26, 0.26):
        for y in (-0.14, 0.14):
            turned_leg(p, x, y, 0.4, "M_wood_black", r=0.022)


@prop("games", "dartboard", "dartboard", 6, "cyl", pinned=True)
def _(p):
    """Regulation board, face at Y = -0.045 (Godot +Z 0.045), centre at the origin, in an
    open cabinet. The face texture puts 20 at the top."""
    p.cyl(0.2255, 0.04, (0, -0.02, 0), "M_black_gloss", rot=(90, 0, 0), segs=40)
    p.disc(0.2255, (0, -0.0405, 0), "T_dartboard", rot=(0, 0, 0), segs=48)
    p.torus(0.228, 0.006, (0, -0.042, 0), "M_chrome", rot=(90, 0, 0), segs=40, ring=4)
    # Cabinet: back board and open doors.
    p.box((0.62, 0.02, 0.62), (0, -0.01, 0.0), "M_wood_mahogany")
    for z in (-0.32, 0.32):
        p.box((0.66, 0.1, 0.04), (0, -0.05, z), "M_wood_mahogany", bevel=0.006)
    for s in (-1, 1):
        p.box((0.04, 0.1, 0.68), (s * 0.33, -0.05, 0), "M_wood_mahogany", bevel=0.006)
        p.box((0.33, 0.025, 0.66), (s * 0.5, -0.07, 0), "M_wood_mahogany", rot=(0, 0, s * 15), bevel=0.006)
        p.box((0.24, 0.005, 0.5), (s * 0.5, -0.084, 0.0), "M_chalk", rot=(0, 0, s * 15))


@prop("games", "darts", "darts_set", 0.07, "box", size="small")
def _(p):
    for i in range(3):
        x = -0.02 + i * 0.02
        p.rod((x, -0.07, 0.005), (x, 0.0, 0.005), 0.0012, "M_chrome", segs=4)
        p.rod((x, 0.0, 0.005), (x, 0.05, 0.005), 0.0045, "M_brass", segs=8)
        p.rod((x, 0.05, 0.005), (x, 0.08, 0.005), 0.002, "M_plastic_black", segs=5)
        for a in (0, 90):
            p.box((0.016, 0.03, 0.0005), (x, 0.09, 0.005), "M_plastic_red", rot=(0, a, 0))


@prop("games", "pool_table", "pool_table", 300, "box", size="big")
def _(p):
    L, W = 2.4, 1.3
    p.box((L, W, 0.18), (0, 0, 0.7), "M_wood_mahogany", bevel=0.02)
    p.box((L - 0.2, W - 0.2, 0.02), (0, 0, 0.8), "M_felt")
    for s in (-1, 1):
        p.box((L - 0.2, 0.06, 0.05), (0, s * (W / 2 - 0.07), 0.815), "M_felt", bevel=0.01)
        p.box((0.06, W - 0.2, 0.05), (s * (L / 2 - 0.07), 0, 0.815), "M_felt", bevel=0.01)
        p.box((L, 0.1, 0.06), (0, s * (W / 2 - 0.02), 0.815), "M_wood_mahogany", bevel=0.01)
        p.box((0.1, W, 0.06), (s * (L / 2 - 0.02), 0, 0.815), "M_wood_mahogany", bevel=0.01)
    for x in (-L / 2 + 0.08, 0, L / 2 - 0.08):
        for y in (-W / 2 + 0.08, W / 2 - 0.08):
            p.cyl(0.055, 0.04, (x, y, 0.83), "M_black_gloss", segs=12)
    for x in (-L / 2 + 0.18, L / 2 - 0.18):
        for y in (-W / 2 + 0.15, W / 2 - 0.15):
            p.box((0.16, 0.16, 0.62), (x, y, 0.31), "M_wood_mahogany", bevel=0.02)
    p.box((0.18, 0.02, 0.12), (L / 2 - 0.01, 0, 0.66), "M_chrome")
    cols = ["C_paint_white", "C_paint_red", "C_light_amber", "C_paint_black", "C_paint_red", "C_light_amber", "C_paint_red"]
    for i, c in enumerate(cols):
        row = 0 if i == 0 else 1 + (i - 1) // 2
        x = -0.6 if i == 0 else 0.4 + row * 0.05
        y = 0 if i == 0 else ((i - 1) % 2 - 0.5) * 0.055 * row
        p.sphere(0.026, (x, y, 0.837), c, segs=10, rings=6)


@prop("games", "pool_cue", "pool_cue", 0.5, "box")
def _(p):
    """Lies along Godot's local Y (up) like the item's placeholder cylinder."""
    p.lathe([(0.016, 0), (0.016, 0.45), (0.012, 0.6), (0.0075, 1.44), (0.0065, 1.45)], "M_wood_pine", segs=10, cap_top=True)
    p.lathe([(0.0165, 0.0), (0.0165, 0.4)], "M_wood_black", segs=10, cap_bottom=True, cap_top=True)
    p.cyl(0.0068, 0.012, (0, 0, 1.455), "M_fabric_blue", segs=8)


@prop("games", "broken_cue", "pool_cue_snapped", 0.25, "box")
def _(p):
    p.lathe([(0.016, 0), (0.016, 0.45), (0.013, 0.7)], "M_wood_pine", segs=10, jitter_top=0.06)
    p.lathe([(0.0165, 0.0), (0.0165, 0.4)], "M_wood_black", segs=10, cap_bottom=True, cap_top=True)


# =====================================================================================
# Fireplace tools and broken furniture (weapon item kinds)
# =====================================================================================

@prop("tools", "poker", "poker", 1.4, "box")
def _(p):
    p.rod((0, 0, 0), (0, 0, 0.7), 0.008, "M_iron", segs=8)
    p.rod((0, 0, 0.0), (0.04, 0, -0.03), 0.007, "M_iron", segs=6)
    p.lathe([(0.012, 0.7), (0.016, 0.74), (0.012, 0.78), (0.018, 0.8), (0.0, 0.82)], "M_brass", segs=10)


@prop("tools", "fire_tongs", "fire_tongs", 1.2, "box")
def _(p):
    for s in (-1, 1):
        p.rod((s * 0.006, 0, 0.7), (s * 0.03, 0, 0.0), 0.006, "M_iron", segs=6)
        p.box((0.02, 0.03, 0.04), (s * 0.03, 0, 0.0), "M_iron")
    p.torus(0.02, 0.005, (0, 0, 0.72), "M_brass", rot=(90, 0, 0), segs=10, ring=4)


@prop("tools", "coal_shovel", "coal_shovel", 1.6, "box")
def _(p):
    p.rod((0, 0, 0.15), (0, 0, 0.7), 0.008, "M_iron", segs=8)
    p.box((0.17, 0.02, 0.2), (0, 0, 0.08), "M_iron", bevel=0.005)
    for s in (-1, 1):
        p.box((0.01, 0.05, 0.2), (s * 0.085, -0.02, 0.08), "M_iron")
    p.lathe([(0.012, 0.7), (0.018, 0.76), (0.0, 0.8)], "M_brass", segs=10)


@prop("tools", "chair_leg", "chair_leg", 0.5, "box")
def _(p):
    turned_leg(p, 0, 0, 0.48, "M_wood_oak", r=0.02)
    p.box((0.03, 0.03, 0.03), (0.01, 0, 0.49), "M_wood_oak", rot=(20, 30, 0))


@prop("tools", "table_leg", "table_leg", 1.0, "box")
def _(p):
    turned_leg(p, 0, 0, 0.73, "M_wood_dark", r=0.03)


# =====================================================================================

def build(only=()):
    os.makedirs(OUT, exist_ok=True)
    cats = {}
    for cat, kind, name, fn, meta in REGISTRY:
        cats.setdefault(cat, []).append((kind, name, fn, meta))
    catalogue = {}
    cat_path = os.path.join(OUT, "catalogue.json")
    if only and os.path.exists(cat_path):
        with open(cat_path) as f:
            catalogue = json.load(f)
    for cat, items in cats.items():
        if only and cat not in only:
            continue
        for ob in list(bpy.data.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for k in [k for k, v in catalogue.items() if v["category"] == cat]:
            del catalogue[k]
        col = bpy.data.collections.new(cat)
        bpy.context.scene.collection.children.link(col)
        for kind, name, fn, meta in items:
            p = Prop(name)
            fn(p)
            ob = p.finish(col)
            dims = ob.dimensions
            entry = {"category": cat, "kind": kind, "mass": meta["mass"], "shape": meta["shape"],
                     "fragile": meta.get("fragile", False), "pinned": meta.get("pinned", False),
                     "size": meta.get("size", "big" if meta["mass"] >= 3.0 else "small"),
                     "tris": sum(len(poly.vertices) - 2 for poly in ob.data.polygons),
                     "dims": [round(dims.x, 3), round(dims.z, 3), round(dims.y, 3)]}  # Godot x, y, z
            catalogue[name] = entry
        bpy.ops.object.select_all(action="DESELECT")
        for ob in col.objects:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = col.objects[0]
        path = os.path.join(OUT, cat + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format="AUTO", export_materials="EXPORT",
                                  export_animations=False, export_skins=False, export_morph=False)
        print("wrote", path, len(items), "props")
        bpy.data.collections.remove(col)
    with open(cat_path, "w") as f:
        json.dump(dict(sorted(catalogue.items())), f, indent=1)
    print("catalogue:", len(catalogue), "props")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build(tuple(argv))
