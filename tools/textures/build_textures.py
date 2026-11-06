"""Builds the tiling PBR texture sets used by PubMaterials and the props.

    python3 tools/textures/build_textures.py           # every set
    python3 tools/textures/build_textures.py wood brick # some sets

Needs numpy and Pillow. Writes assets/textures/materials/<set>_albedo.jpg, _normal.jpg and
_rough.jpg (512 px, tileable). Albedo is mostly neutral detail around mid grey/white so Godot
can tint it with the era colours from PubEra; sets with fixed colours (encaustic tiles,
brick) are coloured. Also writes one-off prop textures into assets/textures/props/:
dartboard face, paintings, bottle labels, chalkboard menu, beer mats and pump clips.
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MAT_DIR = os.path.join(ROOT, "assets", "textures", "materials")
PROP_DIR = os.path.join(ROOT, "assets", "textures", "props")
N = 512
RNG = np.random.default_rng(7)

FONT_DIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype/freefont"]


def font(name, size):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


# --- Noise ----------------------------------------------------------------------------

def value_noise(cells, size=N, seed=0):
    """Tileable smooth value noise with `cells` lattice cells across."""
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells))
    t = np.arange(size) * cells / size
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3 - 2 * f)
    a = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
    b = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(base=4, octaves=5, size=N, seed=0, gain=0.5):
    out = np.zeros((size, size))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(base * 2 ** o, size, seed + o * 31) * amp
        total += amp
        amp *= gain
    return out / total


def stretched(cx, cy, octaves=4, seed=0):
    """Anisotropic noise: cx cells across, cy cells down (tileable)."""
    out = np.zeros((N, N))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        rng = np.random.default_rng(seed + o * 17)
        gx, gy = cx * 2 ** o, cy * 2 ** o
        grid = rng.random((gy, gx))
        ty = np.arange(N) * gy / N
        tx = np.arange(N) * gx / N
        y0 = np.floor(ty).astype(int) % gy
        x0 = np.floor(tx).astype(int) % gx
        fy = ty - np.floor(ty)
        fx = tx - np.floor(tx)
        fy = fy * fy * (3 - 2 * fy)
        fx = fx * fx * (3 - 2 * fx)
        a = grid[y0][:, x0] * (1 - fx) + grid[y0][:, (x0 + 1) % gx] * fx
        b = grid[(y0 + 1) % gy][:, x0] * (1 - fx) + grid[(y0 + 1) % gy][:, (x0 + 1) % gx] * fx
        out += (a * (1 - fy)[:, None] + b * fy[:, None]) * amp
        total += amp
        amp *= 0.5
    return out / total


def norm01(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / max(hi - lo, 1e-6)


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def save_set(name, albedo, height, rough, strength=4.0):
    os.makedirs(MAT_DIR, exist_ok=True)
    if albedo.ndim == 2:
        albedo = np.dstack([albedo] * 3)
    to8 = lambda a: np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(to8(albedo)).save(os.path.join(MAT_DIR, f"{name}_albedo.jpg"), quality=90)
    Image.fromarray(to8(normal_from_height(height, strength))).save(
        os.path.join(MAT_DIR, f"{name}_normal.jpg"), quality=92)
    Image.fromarray(to8(np.clip(rough, 0, 1))).save(os.path.join(MAT_DIR, f"{name}_rough.jpg"), quality=90)
    print("wrote", name)


def tint(grey, color):
    c = np.array(color, dtype=float) / 255.0
    return grey[..., None] * c[None, None, :]


# --- Material sets --------------------------------------------------------------------

def wood_field(seed, rings=26.0):
    """Long grain running down V with ring figure and fibres. Returns 0..1."""
    warp = stretched(3, 1, 4, seed) * 3.0
    x = np.linspace(0, 1, N, endpoint=False)[None, :] + 0 * warp
    r = np.sin((x * rings + warp) * math.tau) * 0.5 + 0.5
    r = r ** 2.2
    fibres = stretched(96, 3, 2, seed + 5)
    knots = fbm(3, 3, seed=seed + 9)
    return np.clip(0.55 + 0.3 * r * 0.8 - 0.25 * (fibres - 0.5) - 0.2 * np.clip(knots - 0.65, 0, 1) * 3, 0, 1)


def build_wood():
    g = wood_field(1)
    albedo = 0.72 + 0.42 * (g - 0.5)
    save_set("wood", albedo, g * 0.4, 0.62 + 0.2 * (1 - g), 3.0)


def build_planks():
    """Floorboards: 6 boards across, staggered butt joints, each board its own grain."""
    alb = np.zeros((N, N))
    h = np.zeros((N, N))
    rough = np.zeros((N, N))
    w = N // 6
    for b in range(6):
        g = wood_field(10 + b, 18 + b * 3)
        tone = 0.85 + 0.25 * RNG.random()
        sl = slice(b * w, (b + 1) * w)
        alb[:, sl] = (0.7 + 0.4 * (g[:, sl] - 0.5)) * tone
        h[:, sl] = g[:, sl] * 0.3
        rough[:, sl] = 0.55 + 0.2 * (1 - g[:, sl])
        alb[:, b * w:b * w + 3] *= 0.35
        h[:, b * w:b * w + 3] = -0.6
        joint = int(RNG.integers(40, N - 40))
        alb[joint:joint + 3, sl] *= 0.4
        h[joint:joint + 3, sl] = -0.6
        # Nail heads.
        for y in (joint - 14, joint + 16):
            for x in (b * w + 10, (b + 1) * w - 10):
                yy, xx = y % N, x % N
                alb[yy - 2:yy + 2, xx - 2:xx + 2] = 0.2
    wear = fbm(4, 4, seed=12)
    alb *= 0.9 + 0.2 * wear
    save_set("planks", alb, h, rough, 5.0)


def build_flagstone():
    alb = np.ones((N, N)) * 0.2
    h = np.full((N, N), -0.5)
    rough = np.full((N, N), 0.95)
    detail = fbm(8, 5, seed=20)
    rows = [0, 120, 260, 384, N]
    for r in range(len(rows) - 1):
        y0, y1 = rows[r], rows[r + 1]
        x = int(RNG.integers(0, 120))
        cuts = []
        while x < N + x:
            cuts.append(x)
            x += int(RNG.integers(130, 230))
            if x - cuts[0] >= N:
                break
        cuts.append(cuts[0] + N)
        for s in range(len(cuts) - 1):
            a, b = cuts[s], cuts[s + 1]
            shade = 0.72 + 0.28 * RNG.random()
            yy, xx = np.mgrid[y0 + 4:y1 - 4, a + 4:b - 4]
            xx %= N
            bevel = np.minimum.reduce([yy - y0, y1 - yy, (np.mgrid[y0 + 4:y1 - 4, a + 4:b - 4][1] - a),
                                       (b - np.mgrid[y0 + 4:y1 - 4, a + 4:b - 4][1])]) / 10.0
            bevel = np.clip(bevel, 0, 1)
            alb[yy, xx] = shade * (0.8 + 0.4 * detail[yy, xx])
            h[yy, xx] = bevel * 0.4 + detail[yy, xx] * 0.5
            rough[yy, xx] = 0.75 + 0.2 * detail[yy, xx]
    save_set("flagstone", alb, h, rough, 6.0)


def build_slate():
    """Riven slate slabs in a running bond: dark, low contrast, cleft surface."""
    alb = np.full((N, N), 0.35)
    h = np.full((N, N), -0.4)
    rough = np.full((N, N), 0.9)
    cleft = stretched(6, 24, 5, 200)
    fine = fbm(24, 3, seed=201)
    rows, cols = 4, 2
    sh, sw = N // rows, N // cols
    for r in range(rows):
        off = (sw // 2) * (r % 2)
        for c in range(cols + 1):
            shade = 0.82 + 0.18 * RNG.random()
            x0 = c * sw + off + 3
            for x in range(x0, x0 + sw - 6):
                xx = x % N
                ys = slice(r * sh + 3, (r + 1) * sh - 3)
                alb[ys, xx] = shade * (0.88 + 0.16 * cleft[ys, xx] + 0.06 * fine[ys, xx])
                h[ys, xx] = 0.3 * cleft[ys, xx] + 0.15 * fine[ys, xx]
                rough[ys, xx] = 0.55 + 0.25 * fine[ys, xx]
    save_set("slate", alb, h, rough, 4.0)


def build_tiles():
    """Victorian encaustic tiles: terracotta, cream and black with a quatrefoil motif."""
    terracotta, cream, black, blue = (150, 62, 40), (214, 196, 160), (34, 30, 26), (52, 72, 92)
    img = Image.new("RGB", (N, N), (60, 52, 44))
    d = ImageDraw.Draw(img)
    t = N // 8
    for j in range(8):
        for i in range(8):
            x0, y0 = i * t + 1, j * t + 1
            x1, y1 = x0 + t - 3, y0 + t - 3
            if (i + j) % 2 == 0:
                d.rectangle([x0, y0, x1, y1], fill=terracotta)
            else:
                d.rectangle([x0, y0, x1, y1], fill=cream)
                cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
                r = t * 0.22
                for ox, oy in ((-r, 0), (r, 0), (0, -r), (0, r)):
                    d.ellipse([cx + ox - r * 0.7, cy + oy - r * 0.7, cx + ox + r * 0.7, cy + oy + r * 0.7], fill=black)
                d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], fill=blue if (i * 3 + j) % 4 == 1 else terracotta)
    alb = np.asarray(img).astype(float) / 255.0
    grime = fbm(6, 4, seed=30)
    alb *= (0.82 + 0.25 * grime)[..., None]
    h = np.zeros((N, N))
    gx = np.arange(N) % t
    grout = (gx[None, :] < 2) | (gx[None, :] > t - 3) | (gx[:, None] < 2) | (gx[:, None] > t - 3)
    h[grout] = -0.5
    rough = np.where(grout, 0.95, 0.35 + 0.25 * grime)
    save_set("tiles", alb, h + grime * 0.05, rough, 4.0)


def build_plaster():
    blot = fbm(3, 6, seed=40)
    fine = fbm(32, 3, seed=41)
    alb = 0.88 + 0.16 * (blot - 0.5) + 0.06 * (fine - 0.5)
    # Faint hairline cracks.
    crack = np.abs(stretched(2, 6, 5, 42) - 0.5) < 0.006
    alb[crack] *= 0.8
    h = blot * 0.6 + fine * 0.3
    save_set("plaster", alb, h, 0.85 + 0.1 * fine, 3.0)


def build_brick():
    alb = np.zeros((N, N, 3))
    h = np.full((N, N), -0.5)
    rough = np.full((N, N), 0.95)
    mortar = np.array([0.55, 0.5, 0.44])
    alb[:] = mortar * (0.85 + 0.2 * fbm(16, 3, seed=50))[..., None]
    rows, cols = 8, 4
    bh, bw = N // rows, N // cols
    detail = fbm(16, 4, seed=51)
    for r in range(rows):
        off = (bw // 2) * (r % 2)
        for c in range(cols + 1):
            x0 = c * bw + off + 3
            col = np.array([0.45, 0.17, 0.11]) * (0.75 + 0.5 * RNG.random()) + np.array([0.05, 0.03, 0.0]) * RNG.random()
            for x in range(x0, x0 + bw - 6):
                xx = x % N
                alb[r * bh + 3:(r + 1) * bh - 3, xx] = col * (0.75 + 0.45 * detail[r * bh + 3:(r + 1) * bh - 3, xx])[:, None]
                h[r * bh + 3:(r + 1) * bh - 3, xx] = 0.3 + 0.3 * detail[r * bh + 3:(r + 1) * bh - 3, xx]
                rough[r * bh + 3:(r + 1) * bh - 3, xx] = 0.8
    save_set("brick", alb, h, rough, 5.0)


def build_panelling():
    """Raised and fielded panels (dado). 2 panels across, 1 down."""
    h = np.zeros((N, N))
    yy, xx = np.mgrid[0:N, 0:N]
    pw = N // 2
    lx = xx % pw
    d = np.minimum.reduce([lx, pw - lx, yy, N - yy]).astype(float)
    h = np.clip((d - 18) / 30.0, 0, 1)
    h[(d > 10) & (d < 18)] = -0.3
    g = wood_field(60, 12)
    alb = 0.7 + 0.35 * (g - 0.5) - 0.15 * (h < 0)
    save_set("panelling", alb, h * 0.8 + g * 0.1, 0.5 + 0.2 * (1 - g), 6.0)


def build_glazed_tile():
    """Victorian glazed wall tiles (dado): 4 x 8 brick-bond, glossy, slight colour drift."""
    alb = np.zeros((N, N))
    h = np.zeros((N, N))
    rows, cols = 8, 4
    th, tw = N // rows, N // cols
    drift = fbm(2, 3, seed=70)
    for r in range(rows):
        off = (tw // 2) * (r % 2)
        for c in range(cols + 1):
            shade = 0.85 + 0.25 * RNG.random()
            for x in range(c * tw + off, c * tw + off + tw):
                xx = x % N
                alb[r * th:(r + 1) * th, xx] = shade
                lx = x - (c * tw + off)
                edge = np.minimum(np.minimum(lx, tw - lx), np.minimum(np.arange(th), th - np.arange(th)))
                h[r * th:(r + 1) * th, xx] = np.clip(edge / 6.0, 0, 1)
    grout = h < 0.2
    alb = alb * (0.9 + 0.2 * drift)
    alb[grout] = 0.55
    save_set("glazed_tile", alb, h * 0.5, np.where(grout, 0.9, 0.12), 4.0)


def build_wallpaper():
    """Damask-style flock: repeating stylised leaf motif in two tones."""
    img = Image.new("L", (N, N), 200)
    d = ImageDraw.Draw(img)
    s = N // 4
    for j in range(4):
        for i in range(4):
            cx = i * s + (s // 2 if j % 2 else 0)
            cy = j * s + s // 2
            for dx in (-N, 0, N):
                x = cx + dx
                d.ellipse([x - s * 0.18, cy - s * 0.38, x + s * 0.18, cy + s * 0.38], fill=150)
                d.ellipse([x - s * 0.38, cy - s * 0.12, x + s * 0.38, cy + s * 0.12], fill=150)
                d.ellipse([x - s * 0.08, cy - s * 0.08, x + s * 0.08, cy + s * 0.08], fill=225)
                d.line([x, cy + s * 0.38, x, cy + s * 0.5], fill=150, width=4)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    a = np.asarray(img).astype(float) / 255.0
    a = a * (0.9 + 0.15 * fbm(4, 3, seed=80))
    stripes = 0.03 * np.sin(np.arange(N) / N * math.tau * 32)[None, :]
    save_set("wallpaper", a + stripes, (a < 0.7) * 0.3, 0.8 - 0.1 * (a < 0.7), 2.0)


def build_fabric():
    yy, xx = np.mgrid[0:N, 0:N]
    weave = (np.sin(xx / N * math.tau * 128) * np.sin(yy / N * math.tau * 128))
    alb = 0.82 + 0.08 * weave + 0.12 * (fbm(8, 4, seed=90) - 0.5)
    save_set("fabric", alb, weave * 0.3, np.full((N, N), 0.95), 2.0)


def build_leather():
    cells = fbm(24, 3, seed=100)
    creases = np.abs(fbm(6, 5, seed=101) - 0.5) < 0.015
    alb = 0.78 + 0.18 * (cells - 0.5) + 0.12 * (fbm(3, 3, seed=102) - 0.5)
    alb[creases] *= 0.75
    h = cells * 0.5 - creases * 0.6
    save_set("leather", alb, h, 0.45 + 0.25 * fbm(3, 3, seed=103) + 0.2 * creases, 3.0)


def build_metal():
    streaks = stretched(256, 2, 2, 110)
    blot = fbm(4, 4, seed=111)
    alb = 0.88 + 0.08 * (streaks - 0.5) - 0.12 * np.clip(blot - 0.6, 0, 1) * 3
    save_set("metal", alb, streaks * 0.08, 0.28 + 0.15 * streaks + 0.25 * np.clip(blot - 0.55, 0, 1) * 3, 1.0)


def build_cast_iron():
    pits = fbm(48, 3, seed=120)
    blot = fbm(4, 4, seed=121)
    alb = 0.8 + 0.2 * (pits - 0.5) + 0.15 * (blot - 0.5)
    save_set("cast_iron", alb, pits * 0.6, 0.55 + 0.3 * pits, 4.0)


def build_felt():
    f = fbm(64, 3, seed=130)
    alb = 0.9 + 0.12 * (f - 0.5) + 0.08 * (fbm(3, 3, seed=131) - 0.5)
    save_set("felt", alb, f * 0.2, np.full((N, N), 0.98), 2.0)


def build_stone():
    d = fbm(6, 6, seed=140)
    alb = 0.75 + 0.35 * (d - 0.5)
    save_set("stone", alb, d, 0.85 + 0.1 * d, 5.0)


def build_grime():
    """Generic dirt/wear detail for painted and ceramic surfaces."""
    d = fbm(4, 5, seed=150)
    alb = 0.95 + 0.1 * (d - 0.5)
    save_set("grime", alb, d * 0.1, 0.4 + 0.3 * d, 1.0)


# --- One-off prop textures ------------------------------------------------------------

def save_prop(img, name, quality=90):
    os.makedirs(PROP_DIR, exist_ok=True)
    path = os.path.join(PROP_DIR, name)
    if name.endswith(".png"):
        img.save(path)
    else:
        img.convert("RGB").save(path, quality=quality)
    print("wrote", name)


DART_NUMBERS = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]


def build_dartboard():
    """Regulation 451 mm board drawn to 1024 px (whole image = 0.5 m)."""
    S = 1024
    scale = S / 0.5  # px per metre
    img = Image.new("RGB", (S, S), (20, 20, 20))
    d = ImageDraw.Draw(img)
    c = S / 2
    black, cream, red, green = (24, 22, 20), (226, 210, 168), (186, 32, 30), (24, 120, 60)
    radii = {"board": 0.2255, "double_out": 0.170, "double_in": 0.162, "treble_out": 0.107,
             "treble_in": 0.099, "outer_bull": 0.0159, "bull": 0.00635}

    def ring(r):
        return [c - r * scale, c - r * scale, c + r * scale, c + r * scale]

    d.ellipse(ring(radii["board"]), fill=(28, 26, 24))
    for i in range(20):
        # PIL angles go clockwise from 3 o'clock; segment 20 is centred at the top (-90).
        a0 = -90 - 9 + i * 18
        a1 = a0 + 18
        base = black if i % 2 == 0 else cream
        ring_col = red if i % 2 == 0 else green
        d.pieslice(ring(radii["double_out"]), a0, a1, fill=ring_col)
        d.pieslice(ring(radii["double_in"]), a0, a1, fill=base)
        d.pieslice(ring(radii["treble_out"]), a0, a1, fill=ring_col)
        d.pieslice(ring(radii["treble_in"]), a0, a1, fill=base)
    d.ellipse(ring(radii["outer_bull"]), fill=green)
    d.ellipse(ring(radii["bull"]), fill=red)
    # Wire spider.
    wire = (196, 196, 190)
    for r in ("double_out", "double_in", "treble_out", "treble_in", "outer_bull", "bull"):
        d.ellipse(ring(radii[r]), outline=wire, width=2)
    for i in range(20):
        a = math.radians(-90 - 9 + i * 18)
        r0, r1 = radii["outer_bull"], radii["double_out"]
        d.line([c + math.cos(a) * r0 * scale, c + math.sin(a) * r0 * scale,
                c + math.cos(a) * r1 * scale, c + math.sin(a) * r1 * scale], fill=wire, width=2)
    # Number ring.
    f = font("DejaVuSans-Bold.ttf", 34)
    for i, n in enumerate(DART_NUMBERS):
        a = math.radians(-90 + i * 18)
        r = 0.196 * scale
        x, y = c + math.cos(a) * r, c + math.sin(a) * r
        d.text((x, y), str(n), fill=(232, 232, 226), font=f, anchor="mm")
    arr = np.asarray(img).astype(float)
    arr *= (0.9 + 0.15 * fbm(16, 3, size=S, seed=160))[..., None]  # sisal fibre
    save_prop(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), "dartboard.jpg", 92)


def painterly(base, seed, strokes=2200, size=256, blur=0.8):
    """Daubs random short brush strokes sampled from `base` over itself."""
    rng = np.random.default_rng(seed)
    img = base.copy()
    d = ImageDraw.Draw(img)
    px = base.load()
    w, h = base.size
    for _ in range(strokes):
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        col = px[x, y]
        jitter = tuple(int(np.clip(v + rng.normal(0, 10), 0, 255)) for v in col)
        ang = rng.normal(0.2, 0.6)
        L = rng.integers(3, 9)
        d.line([x, y, x + math.cos(ang) * L, y + math.sin(ang) * L], fill=jitter, width=int(rng.integers(2, 4)))
    img = img.filter(ImageFilter.GaussianBlur(blur))
    # Varnish yellowing and craquelure-ish darkening at the edges.
    arr = np.asarray(img).astype(float)
    yy, xx = np.mgrid[0:h, 0:w]
    vig = 1.0 - 0.35 * (((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    arr = arr * vig[..., None] * np.array([1.0, 0.95, 0.8])
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def build_paintings():
    W, H = 256, 192
    # 1. Landscape: sky, hills, a church spire.
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([0, y, W, y], fill=(int(120 + 80 * t), int(150 + 60 * t), int(185 + 20 * t)))
    d.polygon([(0, 110), (60, 85), (140, 105), (200, 80), (256, 100), (256, 192), (0, 192)], fill=(78, 110, 58))
    d.polygon([(0, 140), (90, 120), (180, 135), (256, 125), (256, 192), (0, 192)], fill=(98, 128, 60))
    d.rectangle([168, 70, 178, 108], fill=(140, 130, 110))
    d.polygon([(166, 70), (173, 45), (180, 70)], fill=(110, 100, 90))
    for x in (30, 52, 220):
        d.ellipse([x - 12, 100, x + 12, 128], fill=(50, 72, 40))
    save_prop(painterly(img, 1), "painting_landscape.jpg")
    # 2. Portrait of a stern gentleman.
    img = Image.new("RGB", (192, 256), (40, 30, 22))
    d = ImageDraw.Draw(img)
    d.ellipse([20, 150, 172, 330], fill=(25, 22, 30))
    d.polygon([(80, 160), (96, 200), (112, 160)], fill=(220, 215, 200))
    d.ellipse([62, 60, 130, 150], fill=(214, 170, 140))
    d.ellipse([58, 40, 134, 92], fill=(200, 200, 196))
    d.ellipse([76, 95, 86, 101], fill=(50, 40, 35))
    d.ellipse([106, 95, 116, 101], fill=(50, 40, 35))
    d.line([82, 128, 110, 128], fill=(130, 70, 60), width=3)
    d.polygon([(70, 120), (96, 140), (122, 120), (118, 150), (74, 150)], fill=(190, 190, 186))
    save_prop(painterly(img, 2, size=256), "painting_portrait.jpg")
    # 3. Hunting scene: horse and rider.
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([0, y, W, y], fill=(int(170 - 40 * t), int(160 - 30 * t), int(120 - 30 * t)))
    d.rectangle([0, 130, W, H], fill=(90, 100, 50))
    d.ellipse([80, 95, 170, 135], fill=(110, 60, 30))
    for x in (90, 108, 145, 160):
        d.line([x, 125, x - 6, 160], fill=(90, 50, 25), width=6)
    d.polygon([(160, 100), (195, 78), (200, 92), (172, 115)], fill=(110, 60, 30))
    d.rectangle([115, 60, 135, 100], fill=(170, 30, 25))
    d.ellipse([117, 44, 133, 62], fill=(210, 170, 140))
    d.rectangle([115, 38, 135, 46], fill=(20, 20, 20))
    for x in (40, 60, 210, 228):
        d.ellipse([x - 10, 140, x + 12, 152], fill=(200, 190, 170))
    save_prop(painterly(img, 3), "painting_hunt.jpg")
    # 4. Ship at sea.
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([0, y, W, y], fill=(int(90 + 70 * t), int(100 + 60 * t), int(110 + 50 * t)))
    d.rectangle([0, 120, W, H], fill=(40, 70, 80))
    d.polygon([(70, 120), (190, 120), (175, 140), (85, 140)], fill=(70, 45, 25))
    for x, top in ((105, 40), (135, 30), (162, 50)):
        d.line([x, 120, x, top], fill=(50, 35, 20), width=3)
        d.polygon([(x - 18, top + 10), (x + 18, top + 10), (x + 14, top + 60), (x - 14, top + 60)], fill=(225, 215, 190))
    for i in range(30):
        x = (i * 37) % W
        d.arc([x - 10, 150 + (i % 4) * 9, x + 10, 160 + (i % 4) * 9], 200, 340, fill=(200, 210, 210), width=2)
    save_prop(painterly(img, 4), "painting_ship.jpg")
    # 5. Prize bull.
    img = Image.new("RGB", (W, H), (150, 160, 120))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 90], fill=(170, 185, 200))
    d.rectangle([0, 130, W, H], fill=(80, 110, 50))
    d.ellipse([60, 80, 190, 140], fill=(120, 70, 40))
    d.ellipse([170, 78, 215, 115], fill=(120, 70, 40))
    d.polygon([(178, 82), (168, 66), (185, 80)], fill=(230, 220, 190))
    d.polygon([(205, 82), (215, 66), (200, 80)], fill=(230, 220, 190))
    for x in (75, 95, 155, 172):
        d.rectangle([x, 128, x + 10, 165], fill=(110, 62, 34))
    save_prop(painterly(img, 5), "painting_bull.jpg")
    # 6. Old brewery mirror (gold lettering on dark glass).
    img = Image.new("RGB", (256, 192), (18, 22, 20))
    d = ImageDraw.Draw(img)
    d.rectangle([8, 8, 248, 184], outline=(190, 150, 70), width=4)
    d.text((128, 70), "CROWN", font=font("DejaVuSerif-Bold.ttf", 44), fill=(214, 172, 80), anchor="mm")
    d.text((128, 120), "FINE ALES & STOUT", font=font("DejaVuSerif-Bold.ttf", 18), fill=(214, 172, 80), anchor="mm")
    d.text((128, 152), "EST. 1648", font=font("DejaVuSerif.ttf", 14), fill=(190, 150, 70), anchor="mm")
    save_prop(img, "mirror_brewery.jpg")
    # 7. Darts team photo (sepia).
    img = Image.new("RGB", (256, 192), (150, 128, 96))
    d = ImageDraw.Draw(img)
    for i in range(6):
        x = 30 + i * 39
        d.ellipse([x - 12, 50 + (i % 2) * 10, x + 12, 76 + (i % 2) * 10], fill=(200, 175, 135))
        d.rectangle([x - 18, 76 + (i % 2) * 10, x + 18, 150], fill=(70, 58, 44))
    d.rectangle([90, 150, 170, 175], fill=(180, 150, 60))
    save_prop(painterly(img, 7, strokes=800), "photo_team.jpg")


def build_labels():
    """Bottle labels, 256x128, wrapped round the bottle front."""
    labels = [
        ("label_ale", (176, 46, 34), "CROWN", "BEST BITTER"),
        ("label_stout", (24, 22, 20), "BLACK DOG", "STOUT"),
        ("label_lager", (40, 80, 150), "KRONEN", "PILS"),
        ("label_whisky", (226, 210, 160), "GLEN TICKLE", "SINGLE MALT"),
        ("label_gin", (230, 236, 230), "OLD TOM", "LONDON DRY GIN"),
        ("label_rum", (60, 30, 20), "PIRATE'S", "DARK RUM"),
        ("label_wine", (232, 222, 200), "CHATEAU", "PLONK 1987"),
        ("label_cider", (200, 160, 40), "SCRUMPY", "FARMHOUSE CIDER"),
        ("label_vodka", (210, 220, 230), "VOLGA", "VODKA"),
        ("label_crisps", (40, 90, 170), "CRISPS", "READY SALTED"),
        ("label_crisps2", (40, 140, 60), "CRISPS", "SALT & VINEGAR"),
        ("label_crisps3", (170, 40, 40), "CRISPS", "CHEESE & ONION"),
        ("label_scratchings", (190, 140, 40), "PORK", "SCRATCHINGS"),
        ("label_nuts", (200, 60, 30), "DRY ROAST", "PEANUTS"),
    ]
    for name, bg, title, sub in labels:
        img = Image.new("RGB", (256, 128), bg)
        d = ImageDraw.Draw(img)
        lum = sum(bg) / 3
        fg = (20, 18, 16) if lum > 140 else (240, 230, 200)
        accent = (190, 150, 60)
        d.rectangle([4, 4, 251, 123], outline=accent, width=3)
        size = 34
        while size > 14 and d.textlength(title, font=font("DejaVuSerif-Bold.ttf", size)) > 232:
            size -= 2
        d.text((128, 50), title, font=font("DejaVuSerif-Bold.ttf", size), fill=fg, anchor="mm")
        d.text((128, 92), sub, font=font("DejaVuSans-Bold.ttf", 17), fill=fg, anchor="mm")
        save_prop(img, name + ".jpg")


def build_chalkboard():
    img = Image.new("RGB", (256, 384), (34, 38, 36))
    d = ImageDraw.Draw(img)
    chalk = (226, 226, 214)
    d.text((128, 34), "TODAY", font=font("DejaVuSerif-Bold.ttf", 34), fill=chalk, anchor="mm")
    items = ["Pie & Chips  4.50", "Ploughman's  5.00", "Scotch Egg  2.00", "Fish & Chips  6.00",
             "Sunday Roast  8.00", "Pickled Egg  0.50", "NO FIGHTING"]
    f = font("DejaVuSans.ttf", 19)
    for i, t in enumerate(items):
        d.text((20, 80 + i * 40), t, font=f, fill=chalk if t != "NO FIGHTING" else (230, 140, 120))
    arr = np.asarray(img).astype(float)
    arr += (fbm(8, 3, size=384, seed=170)[:, :256, None] - 0.5) * 30
    save_prop(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), "chalkboard.jpg")


def build_beermats():
    for i, (bg, fg, t) in enumerate([((180, 30, 30), (250, 240, 220), "CROWN"), ((20, 60, 130), (240, 220, 120), "KRONEN"),
                                     ((20, 20, 20), (230, 200, 120), "BLACK DOG"), ((230, 220, 190), (120, 40, 20), "SCRUMPY")]):
        img = Image.new("RGB", (128, 128), bg)
        d = ImageDraw.Draw(img)
        d.ellipse([10, 10, 118, 118], outline=fg, width=4)
        d.text((64, 64), t, font=font("DejaVuSans-Bold.ttf", 16 if len(t) > 6 else 20), fill=fg, anchor="mm")
        save_prop(img, f"beermat_{i}.jpg")


SETS = {
    "wood": build_wood, "planks": build_planks, "flagstone": build_flagstone, "tiles": build_tiles, "slate": build_slate,
    "plaster": build_plaster, "brick": build_brick, "panelling": build_panelling,
    "glazed_tile": build_glazed_tile, "wallpaper": build_wallpaper, "fabric": build_fabric,
    "leather": build_leather, "metal": build_metal, "cast_iron": build_cast_iron, "felt": build_felt,
    "stone": build_stone, "grime": build_grime,
    "dartboard": build_dartboard, "paintings": build_paintings, "labels": build_labels,
    "chalkboard": build_chalkboard, "beermats": build_beermats,
}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(SETS)
    for w in wanted:
        SETS[w]()
