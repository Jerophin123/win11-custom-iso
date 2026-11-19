"""Procedural wallpaper generator (numpy only, no AI).

usage: python -I wallgen.py <out_dir> <width> <height> [name ...]
Writes <name>.png for each wallpaper (all if no names given).

Styles
  silk     - draped satin lit by a single soft light
  ridges   - layered ridges with atmospheric haze (dunes / misty hills)
  contour  - topographic contour lines over a soft relief
"""
import sys, zlib, struct
import numpy as np


# ------------------------------------------------------------------ utilities
def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def col(c):
    return np.array(c, np.float32) / 255.0


def lerp3(c0, c1, t):
    c0, c1 = col(c0), col(c1)
    return c0 + (c1 - c0) * t[..., None]


def grid(W, H):
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
    return xs / H, ys / H          # x: 0..aspect, y: 0..1


def finish(img, grain, seed=7):
    rng = np.random.default_rng(seed)
    img = img * 255 + rng.normal(0, grain, img.shape[:2]).astype(np.float32)[..., None]
    return np.clip(img + 0.5, 0, 255).astype(np.uint8)


def vignette(x, y, W, H, amount, inner=0.35, outer=0.85):
    a = W / H
    vr = np.sqrt(((x - a / 2) / a) ** 2 + (y - 0.5) ** 2)
    return (1 - amount * smoothstep(inner, outer, vr))[..., None]


# ------------------------------------------------------------------ silk
def silk_field(W, H, ph0=0.0, flip=False):
    x, y = grid(W, H)
    if flip:
        y = 1 - y
    u = x + 0.22 * np.sin(1.9 * y + 0.6 + ph0) + 0.08 * np.sin(4.1 * y - 1.3 * x + 2.0)
    v = y + 0.18 * np.sin(1.4 * x + 0.3 - ph0) + 0.06 * np.sin(3.3 * x + 2.2 * y)
    d = 0.62 * u - 0.78 * v
    ph = d * 6.5 + 1.3 * np.sin(u * 1.6 + 0.4 + ph0) + 0.6 * np.sin(v * 2.4 - u * 0.8)
    h = 0.60 * np.sin(ph) + 0.22 * np.sin(2.0 * ph + 0.7 + u) + 0.14 * np.sin(u * 2.3 + v * 3.1 + 0.5)
    m = smoothstep(0.40, 1.35, x * 0.85 + y * 0.9)
    h = h * m
    if flip:
        y = 1 - y
    # lighting
    k = 0.30
    gy, gx = np.gradient(h)
    nx, ny = -gx * k * H, -gy * k * H
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + 1.0)
    nx, ny, nz = nx * inv, ny * inv, inv
    L = np.array([-0.45, -0.55, 0.70], np.float32); L /= np.linalg.norm(L)
    Hv = L + np.array([0, 0, 1], np.float32); Hv /= np.linalg.norm(Hv)
    diff = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0, 1)
    spec = np.clip(nx * Hv[0] + ny * Hv[1] + nz * Hv[2], 0, 1)
    rel = np.clip((diff - L[2]) / (1 - L[2]), -1, 1)
    return x, y, rel, spec, m


def silk_dark(W, H, base0, base1, tint0, tint1, spec_c=(205, 215, 255), ph0=0.0, flip=False,
              pool_at=(1.30, 0.80), gain=1.0, pool_r=0.75):
    x, y, rel, spec, m = silk_field(W, H, ph0, flip)
    lit = np.clip(rel, 0, 1)[..., None]; shd = np.clip(-rel, 0, 1)[..., None]; mm = m[..., None]
    t = np.clip((x / (W / H)) * 0.6 + y * 0.4, 0, 1)
    base = lerp3(base0, base1, t); tint = lerp3(tint0, tint1, t)
    r = np.sqrt((x - pool_at[0]) ** 2 + (y - pool_at[1]) ** 2)
    pool = np.exp(-(r / pool_r) ** 2)[..., None]
    img = base + gain * tint * (0.10 + 0.80 * lit ** 1.3 + 1.10 * lit ** 5) * mm * (0.40 + 0.60 * pool)
    img *= 1 - 0.65 * shd * mm
    img += col(spec_c) * (spec[..., None] ** 140) * 0.30 * mm * pool
    img *= vignette(x, y, W, H, 0.40)
    return finish(img, 1.5)


def silk_light(W, H, base0, base1, shadow0, shadow1, ph0=0.0, flip=False):
    """Mid-tone 'light' silk: soft enough to sit behind icons without glare."""
    x, y, rel, spec, m = silk_field(W, H, ph0, flip)
    lit = np.clip(rel, 0, 1)[..., None]; shd = np.clip(-rel, 0, 1)[..., None]; mm = m[..., None]
    t = np.clip((x / (W / H)) * 0.6 + y * 0.4, 0, 1)
    base = lerp3(base0, base1, t)
    shadow = lerp3(shadow0, shadow1, t)
    img = base + (shadow - base) * (shd ** 1.1) * 0.75 * mm       # tinted shadows
    img += (1 - img) * (lit ** 1.4) * 0.55 * mm                    # satin highlights
    img += (spec[..., None] ** 120) * 0.08 * mm
    img *= vignette(x, y, W, H, 0.12, 0.45, 0.95)
    return finish(img, 1.3)


# ------------------------------------------------------------------ ridges
def ridges(W, H, sky_top, sky_low, near, far, layers=7, sun=None, haze=0.85, seed=3,
           rim=(255, 220, 190), rim_amt=0.35, top=0.42, bottom=0.95):
    x, y = grid(W, H)
    a = W / H
    rng = np.random.default_rng(seed)
    t = smoothstep(0.0, 0.75, y)
    img = lerp3(sky_top, sky_low, t)
    if sun is not None:
        sx, sy, sr, sc = sun
        r = np.sqrt((x - sx * a) ** 2 + (y - sy) ** 2)
        disc = smoothstep(sr, sr * 0.85, r)                       # crisp-but-soft sun disc
        img += col(sc) * (disc * 0.35 + np.exp(-(r / (sr * 5)) ** 2) * 0.22)[..., None]
    xs = x[0]
    for i in range(layers):
        f = i / (layers - 1)                     # 0 = far, 1 = near
        base = top + (bottom - top) * f ** 1.15
        amp = 0.035 + 0.09 * f
        p = rng.uniform(0, 6.28, 4)
        fr = rng.uniform(0.8, 1.6)
        line = (base
                - amp * (0.60 * np.sin(xs * 2.1 * fr + p[0])
                         + 0.30 * np.sin(xs * 4.3 * fr + p[1])
                         + 0.10 * np.sin(xs * 9.7 * fr + p[2]))
                - 0.04 * f * np.sin(xs * 0.9 + p[3]))
        slope = np.gradient(line) * H                               # >0 descending to the right
        below = y - line[None, :]
        aa = 1.5 / H
        mask = smoothstep(-aa, aa, below)[..., None]
        c = lerp3(far, near, np.full(y.shape, f ** 0.9, np.float32))
        # haze: far layers dissolve into the sky colour behind them
        hz = (1 - f) * haze
        c = c * (1 - hz) + lerp3(sky_low, sky_low, t) * hz
        # depth fade inside each layer + lit crest on slopes facing the light
        depth = np.clip(below / 0.25, 0, 1)[..., None]
        c = c * (1 - 0.18 * depth)
        crest = np.exp(-np.clip(below, 0, None) / (0.012 + 0.02 * f))[..., None]
        facing = np.clip(-slope * 0.9, 0, 1)[None, :, None]
        c = c + col(rim) * crest * facing * rim_amt * (0.4 + 0.6 * f)
        img = img * (1 - mask) + c * mask
    img *= vignette(x, y, W, H, 0.25)
    return finish(img, 1.4, seed)


# ------------------------------------------------------------------ contour
def contour(W, H, bg0, bg1, line_c, glow_c, levels=26, seed=11):
    x, y = grid(W, H)
    a = W / H
    rng = np.random.default_rng(seed)
    h = np.zeros_like(x)
    for _ in range(7):                                             # soft hills
        cx, cy = rng.uniform(0.2, a - 0.1), rng.uniform(0.1, 0.95)
        s = rng.uniform(0.18, 0.45)
        h += rng.uniform(0.5, 1.0) * np.exp(-(((x - cx) ** 2 + (y - cy) ** 2) / (2 * s * s)))
    h += 0.12 * np.sin(x * 3.1 + 0.4) * np.sin(y * 2.7 + 1.1)
    h = (h - h.min()) / (h.max() - h.min())
    f = h * levels
    gy, gx = np.gradient(f)
    g = np.sqrt(gx * gx + gy * gy) + 1e-6
    dist = np.abs((f - np.round(f))) / g                           # distance to nearest iso-line, px
    major = (np.round(f) % 5 == 0)
    width = np.where(major, 1.25, 0.65) * (W / 3840) ** 0.5 * 1.6
    line = 1 - smoothstep(width * 0.5, width * 0.5 + 1.0, dist)
    alpha = np.where(major, 0.55, 0.22) * line
    # calm upper-left area for icons
    alpha *= (0.35 + 0.65 * smoothstep(0.25, 1.2, x * 0.8 + y * 0.7))
    t = np.clip((x / a) * 0.5 + y * 0.5, 0, 1)
    img = lerp3(bg0, bg1, t)
    img += col(glow_c) * (h ** 2.2)[..., None] * 0.22             # summits glow faintly
    img = img * (1 - alpha[..., None]) + col(line_c) * alpha[..., None]
    img *= vignette(x, y, W, H, 0.35)
    return finish(img, 1.2, seed)


# ------------------------------------------------------------------ catalogue
WALLPAPERS = {
    # default pair used by the built-in Light / Dark themes
    "light": lambda W, H: silk_light(W, H, (188, 198, 214), (204, 196, 208),
                                     (96, 116, 160), (150, 118, 142)),
    "dark": lambda W, H: silk_dark(W, H, (9, 10, 18), (16, 14, 34), (70, 110, 230), (150, 95, 235)),
    # extras
    "emerald": lambda W, H: silk_dark(W, H, (6, 13, 12), (9, 20, 19), (24, 120, 100), (70, 150, 130),
                                      spec_c=(200, 255, 235), ph0=1.7, flip=True, pool_at=(1.25, 0.25),
                                      gain=0.55),
    "ember": lambda W, H: silk_dark(W, H, (13, 9, 8), (22, 13, 10), (230, 125, 60), (250, 175, 95),
                                    spec_c=(255, 230, 200), gain=0.95, pool_r=0.95),
    "dunes": lambda W, H: ridges(W, H, (28, 22, 48), (214, 140, 110), (58, 30, 34), (170, 96, 82),
                                 layers=6, sun=(0.72, 0.43, 0.035, (255, 200, 150)), haze=0.75,
                                 seed=5, rim=(255, 190, 140), rim_amt=0.45),
    "mist": lambda W, H: ridges(W, H, (150, 170, 198), (206, 210, 216), (52, 70, 98), (150, 166, 190),
                                layers=8, sun=(0.30, 0.30, 0.028, (255, 248, 235)), haze=0.9, seed=9,
                                rim=(235, 240, 255), rim_amt=0.25, top=0.38),
    "contour": lambda W, H: contour(W, H, (14, 20, 28), (20, 28, 40), (150, 190, 220), (40, 90, 130)),
}


if __name__ == "__main__":
    out, W, H = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    names = sys.argv[4:] or list(WALLPAPERS)
    for n in names:
        write_png(f"{out}\\{n}.png", WALLPAPERS[n](W, H))
        print("wrote", n)
