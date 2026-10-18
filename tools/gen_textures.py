"""Generate the original block texture atlases for AquaCraft.

Outputs (in assets/textures):
  albedo.rgba.gz  - 8x4 tiles of 32x32 RGBA8 (sRGB colour, alpha = cutout), full mip chain
  material.rgba.gz - same layout: R,G = tangent-space normal XY, B = roughness, A = height/AO
  atlas_preview.png - mip 0 albedo preview for documentation

Every mip level is downsampled tile by tile so neighbouring tiles never bleed into each other.
The textures are generated procedurally from a fixed seed; nothing is copied from other games.
"""
from pathlib import Path
import gzip
import numpy as np
from PIL import Image

T = 32                      # tile size in pixels
COLS, ROWS = 8, 4           # atlas grid
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
rng = np.random.default_rng(20261018)

# Tile indices shared with src/blocks.aqua and the shaders.
TILES = ["grass_top", "grass_side", "dirt", "stone", "sand", "log_side", "log_top", "leaves",
         "glass", "water", "planks", "gravel", "snow", "tall_grass", "flower", "cobble",
         "snow_side", "clay", "coal_ore", "iron_ore", "table_top", "table_side", "table_front", "furnace_front",
         "furnace_side", "furnace_top", "chest_top", "chest_side", "chest_front", "torch", "bedrock", "furnace_lit"]


def value_noise(size, cells, seed):
    """Tileable value noise in [0,1]."""
    r = np.random.default_rng(seed).random((cells, cells))
    y, x = np.mgrid[0:size, 0:size] / size * cells
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    x1, y1 = (x0 + 1) % cells, (y0 + 1) % cells
    a, b, c, d = r[y0 % cells, x0 % cells], r[y0 % cells, x1], r[y1, x0 % cells], r[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, seed, base=4, octaves=4):
    total, amp, norm = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        total += value_noise(size, base * 2 ** o, seed + o * 17) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def palette(t, stops):
    """Map t in [0,1] through colour stops [(pos,(r,g,b)),...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(p1 - p0, 1e-6))[..., None]
        out[m] = (np.array(c0) * (1 - k) + np.array(c1) * k)[m]
    return out


def speckle(n):
    return rng.random((T, T)) < n


def tile_grass_top():
    h = fbm(T, 1, 4) * 0.6 + rng.random((T, T)) * 0.4
    blades = rng.random((T, T))
    col = palette(h, [(0, (50, 82, 36)), (0.45, (68, 106, 46)), (0.8, (86, 124, 56)), (1, (104, 140, 68))])
    col[blades > 0.93] *= 1.12
    col[blades < 0.05] *= 0.8
    return col, h, 0.85


def tile_dirt(seed=2):
    h = fbm(T, seed, 4) * 0.7 + rng.random((T, T)) * 0.3
    col = palette(h, [(0, (88, 60, 40)), (0.5, (118, 84, 56)), (1, (146, 108, 74))])
    pebbles = speckle(0.04)
    col[pebbles] = col[pebbles] * 0.7 + np.array([120, 112, 104]) * 0.3
    return col, h, 0.95


def tile_grass_side():
    col, h, r = tile_dirt(3)
    g, gh, _ = tile_grass_top()
    edge = 6 + (value_noise(T, 8, 9)[0] * 5).astype(int)  # ragged fringe depth per column
    for x in range(T):
        col[:edge[x], x] = g[:edge[x], x] * 0.95
        h[:edge[x], x] = gh[:edge[x], x] * 0.5 + 0.5
        col[edge[x], x] *= 0.75                            # shadow under the turf
    return col, h, r


def tile_stone():
    h = fbm(T, 4, 3) * 0.75 + rng.random((T, T)) * 0.25
    col = palette(h, [(0, (96, 96, 98)), (0.5, (124, 124, 126)), (1, (150, 150, 152))])
    cracks = fbm(T, 44, 6, 2)
    m = np.abs(cracks - 0.5) < 0.025
    col[m] *= 0.72
    h[m] *= 0.5
    return col, h, 0.75


def tile_cobble():
    h = np.zeros((T, T))
    col = np.zeros((T, T, 3))
    pts = rng.random((14, 2)) * T
    y, x = np.mgrid[0:T, 0:T]
    d = np.full((T, T), 1e9)
    d2 = np.full((T, T), 1e9)
    idx = np.zeros((T, T), int)
    for i, (px, py) in enumerate(pts):
        for ox in (-T, 0, T):
            for oy in (-T, 0, T):
                dd = np.hypot(x - px - ox, y - py - oy)
                closer = dd < d
                d2 = np.where(closer, d, np.minimum(d2, dd))
                idx = np.where(closer, i, idx)
                d = np.minimum(d, dd)
    edge = np.clip((d2 - d) / 3.0, 0, 1)
    shade = rng.random(14)[idx] * 0.35 + 0.65
    base = palette(fbm(T, 5, 4), [(0, (100, 100, 102)), (1, (146, 146, 148))])
    col = base * (shade * (0.55 + 0.45 * edge))[..., None]
    h = edge * shade
    return col, h, 0.8


def tile_sand():
    h = fbm(T, 6, 8, 3) * 0.5 + rng.random((T, T)) * 0.5
    col = palette(h, [(0, (196, 178, 128)), (0.5, (214, 198, 148)), (1, (232, 220, 172))])
    return col, h * 0.5, 0.9


def tile_gravel():
    h = rng.random((T, T)) * 0.5 + fbm(T, 7, 8, 2) * 0.5
    col = palette(h, [(0, (92, 86, 82)), (0.4, (124, 118, 112)), (0.75, (148, 140, 132)), (1, (170, 162, 154))])
    return col, h, 0.85


def tile_snow():
    h = fbm(T, 8, 4) * 0.3 + rng.random((T, T)) * 0.1
    col = palette(h, [(0, (222, 230, 238)), (1, (250, 252, 255))])
    return col, h * 0.4, 0.55


def tile_snow_side():
    col, h, r = tile_dirt(12)
    s, sh, _ = tile_snow()
    edge = 7 + (value_noise(T, 8, 13)[0] * 4).astype(int)
    for x in range(T):
        col[:edge[x], x] = s[:edge[x], x]
        h[:edge[x], x] = 0.8
    return col, h, r


def tile_clay():
    h = fbm(T, 14, 4) * 0.6 + rng.random((T, T)) * 0.15
    col = palette(h, [(0, (140, 146, 158)), (1, (166, 172, 184))])
    return col, h * 0.5, 0.7


def tile_log_side():
    y, x = np.mgrid[0:T, 0:T]
    stripes = value_noise(T, 8, 15)[0][x] * 0.6 + value_noise(T, 16, 16) * 0.4
    h = stripes
    col = palette(h, [(0, (62, 44, 28)), (0.5, (92, 66, 40)), (1, (118, 86, 54))])
    grooves = (np.sin(x / T * np.pi * 2 * 5 + value_noise(T, 4, 17) * 3) > 0.82)
    col[grooves] *= 0.65
    h = np.where(grooves, h * 0.4, h)
    return col, h, 0.85


def tile_log_top():
    y, x = np.mgrid[0:T, 0:T] + 0.5
    r = np.hypot(x - T / 2, y - T / 2) + value_noise(T, 4, 18) * 2.5
    rings = 0.5 + 0.5 * np.sin(r * 1.35)
    col = palette(rings * 0.6 + 0.3, [(0, (128, 96, 58)), (1, (184, 146, 96))])
    bark = r > T / 2 - 2.5
    lt, _, _ = tile_log_side()
    col[bark] = lt[bark]
    return col, rings * 0.5, 0.8


def tile_planks():
    y, x = np.mgrid[0:T, 0:T]
    board = y // 8
    grain = value_noise(T, 16, 19) * 0.5 + np.sin((x + board * 7) / 3.0 + value_noise(T, 4, 20) * 4) * 0.25 + 0.4
    col = palette(grain, [(0, (130, 92, 52)), (0.5, (160, 118, 70)), (1, (186, 142, 88))])
    col *= (0.9 + 0.1 * rng.random(4)[board])[..., None]
    seam = (y % 8 == 7)
    joint = ((x + board * 13) % 32 == 0)
    col[seam | joint] *= 0.6
    h = np.where(seam | joint, 0.1, grain * 0.6)
    return col, h, 0.75


def tile_leaves():
    base = fbm(T, 21, 4)
    col = palette(base, [(0, (36, 70, 32)), (0.5, (52, 92, 40)), (1, (76, 116, 52))])
    alpha = np.ones((T, T))
    holes = (fbm(T, 22, 8, 2) + rng.random((T, T)) * 0.35) < 0.47
    alpha[holes] = 0
    col *= (0.85 + 0.3 * rng.random((T, T)))[..., None]
    return col, base, 0.6, alpha


def tile_glass():
    col = np.full((T, T, 3), (214.0, 232.0, 240.0))
    alpha = np.full((T, T), 0.10)
    y, x = np.mgrid[0:T, 0:T]
    frame = (x < 2) | (y < 2) | (x >= T - 2) | (y >= T - 2)
    col[frame] = (232, 240, 246)
    alpha[frame] = 0.85
    streak = (np.abs((x - y) - 6) < 1.2) & (x > 6) & (x < 16) | (np.abs((x - y) + 4) < 0.8) & (x > 12) & (x < 22)
    alpha[streak] = 0.45
    return col, np.where(frame, 1.0, 0.0), 0.05, alpha


def tile_water():
    h = fbm(T, 23, 4)
    col = palette(h, [(0, (34, 84, 150)), (1, (60, 120, 190))])
    return col, h, 0.05, np.full((T, T), 0.75)


def tile_tall_grass():
    col = np.zeros((T, T, 3))
    alpha = np.zeros((T, T))
    for i in range(11):
        x0 = rng.uniform(3, T - 4)
        lean = rng.uniform(-0.25, 0.25)
        height = rng.uniform(T * 0.45, T * 0.95)
        shade = rng.uniform(0.75, 1.15)
        for yy in range(int(height)):
            xx = int(round(x0 + lean * yy + np.sin(yy * 0.3 + i) * 0.6))
            y = T - 1 - yy
            if 0 <= xx < T:
                t = yy / height
                c = np.array([50, 88, 36]) * (1 - t) + np.array([94, 134, 60]) * t
                col[y, xx] = c * shade
                alpha[y, xx] = 1
                if t < 0.5 and 0 <= xx + 1 < T:
                    col[y, xx + 1] = c * shade * 0.85
                    alpha[y, xx + 1] = 1
    return col, alpha * 0.5, 0.7, alpha


def tile_flower():
    col, h, r, alpha = tile_tall_grass()
    col[:, :] *= 0.9
    cx, cy = T // 2, T // 3
    y, x = np.mgrid[0:T, 0:T]
    petals = np.hypot(x - cx, y - cy) < 4.2
    stem = (np.abs(x - cx) < 1) & (y > cy)
    col[stem] = (64, 128, 44)
    alpha[stem] = 1
    col[petals] = (236, 92, 70)
    alpha[petals] = 1
    centre = np.hypot(x - cx, y - cy) < 1.6
    col[centre] = (250, 214, 90)
    return col, alpha * 0.6, 0.6, alpha


def ore(seed, colours, density):
    """Stone with clusters of chunky mineral flecks (2x2 pixel grains with a dark rim)."""
    col, h, r = tile_stone()
    r2 = np.random.default_rng(seed)
    for _ in range(density):
        cx, cy = r2.uniform(4, T - 4, 2)
        for _ in range(int(r2.integers(3, 6))):
            px, py = int(cx + r2.normal(0, 2.2)), int(cy + r2.normal(0, 2.2))
            c = np.array(colours[int(r2.integers(0, len(colours)))], float)
            for oy in range(-1, 3):
                for ox in range(-1, 3):
                    qx, qy = (px + ox) % T, (py + oy) % T
                    if 0 <= ox <= 1 and 0 <= oy <= 1:
                        col[qy, qx] = c * r2.uniform(0.9, 1.1)
                        h[qy, qx] = 0.95
                    elif r2.random() < 0.5:
                        col[qy, qx] *= 0.8
    return col, h, 0.7


def tile_coal_ore():
    return ore(301, [(30, 28, 30), (46, 44, 48), (18, 18, 20)], 7)


def tile_iron_ore():
    return ore(302, [(214, 158, 112), (190, 126, 86), (232, 192, 150)], 7)


def tile_table_top():
    col, h, r = tile_planks()
    y, x = np.mgrid[0:T, 0:T]
    frame = (x < 2) | (y < 2) | (x >= T - 2) | (y >= T - 2)
    grid = ((x % 11 == 5) | (y % 11 == 5)) & ~frame
    col[frame] *= 0.62
    col[grid] *= 0.78
    h[frame] = 0.2
    return col, h, 0.7


def _tool_silhouettes(col, which):
    """Paint small original tool shapes (saw / hammer / chisel) onto a plank face."""
    if which == 0:   # saw: blade with teeth
        col[12:15, 6:22] = (150, 154, 160)
        for i in range(6, 22, 2):
            col[15, i] = (120, 124, 130)
        col[11:16, 22:26] = (96, 64, 36)
    else:            # hammer and chisel
        col[8:20, 9:11] = (96, 64, 36)
        col[8:11, 6:15] = (128, 132, 140)
        col[10:21, 20:22] = (140, 144, 150)
        col[18:22, 19:23] = (96, 64, 36)


def tile_table_side():
    col, h, r = tile_planks()
    y, x = np.mgrid[0:T, 0:T]
    col[:4] = tile_table_top()[0][:4] * 0.9
    col[4] *= 0.6
    legs = (x < 3) | (x >= T - 3)
    col[legs] *= 0.75
    _tool_silhouettes(col, 0)
    return col, h, r


def tile_table_front():
    col, h, r = tile_table_side()
    col2, _, _ = tile_planks()
    col[5:28, 3:T - 3] = col2[5:28, 3:T - 3]
    _tool_silhouettes(col, 1)
    return col, h, r


def tile_furnace_side():
    h = fbm(T, 401, 4) * 0.6 + rng.random((T, T)) * 0.25
    col = palette(h, [(0, (98, 98, 100)), (0.5, (118, 118, 120)), (1, (140, 140, 142))])
    y, x = np.mgrid[0:T, 0:T]
    bricks = (y % 8 == 0) | (((x + (y // 8) * 8) % 16) == 0)
    col[bricks] *= 0.7
    h = np.where(bricks, 0.15, h)
    return col, h, 0.8


def tile_furnace_top():
    col, h, r = tile_furnace_side()
    y, x = np.mgrid[0:T, 0:T]
    rim = (x < 2) | (y < 2) | (x >= T - 2) | (y >= T - 2)
    col[rim] *= 0.8
    return col, h, r


def _furnace_mouth(col, h, lit):
    col[16:27, 8:24] = (24, 22, 22)
    col[15, 7:25] = (70, 70, 72)
    col[16:27, 7] = (70, 70, 72)
    col[16:27, 24] = (70, 70, 72)
    h[16:27, 8:24] = 0.05
    if lit:
        y, x = np.mgrid[0:T, 0:T]
        flame = (y >= 19) & (y < 27) & (x >= 9) & (x < 23)
        wob = np.sin(x * 1.3) * 1.5
        core = flame & (y > 22 - wob)
        col[flame] = (220, 96, 30)
        col[core] = (255, 196, 72)
    col[8:11, 9:23] = (60, 60, 62)


def tile_furnace_front():
    col, h, r = tile_furnace_side()
    _furnace_mouth(col, h, False)
    return col, h, r


def tile_furnace_lit():
    col, h, r = tile_furnace_side()
    _furnace_mouth(col, h, True)
    return col, h, r


def tile_chest_top():
    col, h, r = tile_planks()
    col *= np.array([0.95, 0.88, 0.8])
    y, x = np.mgrid[0:T, 0:T]
    frame = (x < 2) | (y < 2) | (x >= T - 2) | (y >= T - 2)
    col[frame] = (72, 48, 28)
    return col, h, r


def tile_chest_side():
    col, h, r = tile_chest_top()
    y, x = np.mgrid[0:T, 0:T]
    col[10:12] = (72, 48, 28)
    return col, h, r


def tile_chest_front():
    col, h, r = tile_chest_side()
    col[8:15, 13:19] = (196, 186, 150)
    col[9:14, 14:18] = (150, 140, 110)
    return col, h, r


def tile_torch():
    col = np.zeros((T, T, 3))
    alpha = np.zeros((T, T))
    col[12:T, 14:18] = (104, 72, 38)
    col[12:T, 14] = (132, 92, 52)
    alpha[12:T, 14:18] = 1
    y, x = np.mgrid[0:T, 0:T]
    flame = ((x - 15.5) ** 2 / 6.0 + (y - 9.0) ** 2 / 14.0) < 1.0
    core = ((x - 15.5) ** 2 / 2.0 + (y - 10.0) ** 2 / 6.0) < 1.0
    col[flame] = (255, 150, 40)
    col[core] = (255, 236, 150)
    alpha[flame] = 1
    return col, alpha * 0.5, 0.8, alpha


def tile_bedrock():
    h = rng.random((T, T)) * 0.6 + fbm(T, 501, 8, 2) * 0.4
    col = palette(h, [(0, (34, 34, 36)), (0.5, (70, 70, 72)), (1, (110, 110, 112))])
    return col, h, 0.9


GENERATORS = {
    "grass_top": tile_grass_top, "grass_side": tile_grass_side, "dirt": tile_dirt, "stone": tile_stone,
    "sand": tile_sand, "log_side": tile_log_side, "log_top": tile_log_top, "leaves": tile_leaves,
    "glass": tile_glass, "water": tile_water, "planks": tile_planks, "gravel": tile_gravel,
    "snow": tile_snow, "tall_grass": tile_tall_grass, "flower": tile_flower, "cobble": tile_cobble,
    "snow_side": tile_snow_side, "clay": tile_clay, "coal_ore": tile_coal_ore, "iron_ore": tile_iron_ore,
    "table_top": tile_table_top, "table_side": tile_table_side, "table_front": tile_table_front,
    "furnace_front": tile_furnace_front, "furnace_side": tile_furnace_side, "furnace_top": tile_furnace_top,
    "chest_top": tile_chest_top, "chest_side": tile_chest_side, "chest_front": tile_chest_front,
    "torch": tile_torch, "bedrock": tile_bedrock, "furnace_lit": tile_furnace_lit,
}


def normal_from_height(h, strength=2.2):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-gx, gy, np.ones_like(h)], -1)  # +Y up in tangent space (texture v points down)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def build():
    W, H = COLS * T, ROWS * T
    albedo = np.zeros((H, W, 4))
    material = np.zeros((H, W, 4))
    material[..., :] = (128, 128, 230, 255)
    for i, name in enumerate(TILES):
        out = GENERATORS[name]()
        col, h, rough = out[:3]
        alpha = out[3] if len(out) > 3 else np.ones((T, T))
        tx, ty = (i % COLS) * T, (i // COLS) * T
        albedo[ty:ty + T, tx:tx + T, :3] = np.clip(col, 0, 255)
        albedo[ty:ty + T, tx:tx + T, 3] = alpha * 255
        n = normal_from_height(h)
        material[ty:ty + T, tx:tx + T, 0] = (n[..., 0] * 0.5 + 0.5) * 255
        material[ty:ty + T, tx:tx + T, 1] = (n[..., 1] * 0.5 + 0.5) * 255
        rough_map = np.clip(rough + (h - 0.5) * 0.1, 0.02, 1)
        material[ty:ty + T, tx:tx + T, 2] = rough_map * 255
        material[ty:ty + T, tx:tx + T, 3] = np.clip(0.55 + h * 0.45, 0, 1) * 255
    return albedo, material


def srgb_to_linear(c):
    c = c / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255


def mips(atlas, srgb, cutout):
    """Per-tile 2x2 box filter; colour is averaged in linear light weighted by alpha.
    Cutout alpha keeps its coverage so distant leaves stay dense instead of fading."""
    levels = [atlas]
    size = T
    while size > 1:
        prev = levels[-1]
        h, w = prev.shape[:2]
        p = prev.reshape(h // 2, 2, w // 2, 2, 4)
        if srgb:
            a = p[..., 3:4] / 255
            lin = srgb_to_linear(p[..., :3])
            wsum = a.sum(axis=(1, 3)) + 1e-6
            rgb = linear_to_srgb((lin * a).sum(axis=(1, 3)) / wsum)
            alpha = a.mean(axis=(1, 3)) * 255
            if cutout:
                alpha = np.minimum(255, alpha * 1.35)
            nxt = np.concatenate([rgb, alpha], -1)
            empty = wsum[..., 0] < 1e-3
            nxt[empty, :3] = linear_to_srgb(srgb_to_linear(p[..., :3]).mean(axis=(1, 3)))[empty]
        else:
            nxt = p.mean(axis=(1, 3))
        levels.append(nxt)
        size //= 2
    return levels


def write(levels, path):
    data = b"".join(np.clip(np.round(l), 0, 255).astype(np.uint8).tobytes() for l in levels)
    path.write_bytes(gzip.compress(data, 9, mtime=0))
    return len(data)


# ---------------------------------------------------------------- item icons
# 16x16 pixel-art icons drawn procedurally (doubled to 32x32 cells), 8x4 grid, shared with src/items.aqua:
#  0 stick, 1 coal, 2 iron ingot, 3-5 pickaxes (wood, stone, iron), 6-8 axes, 9-11 shovels, 12-14 swords.
ITEM_TIERS = {"wood": [(110, 78, 42), (146, 106, 62), (176, 134, 82)],
              "stone": [(92, 92, 96), (124, 124, 128), (156, 156, 160)],
              "iron": [(150, 150, 156), (198, 198, 204), (236, 236, 240)]}
HANDLE = [(74, 50, 26), (104, 72, 38), (130, 92, 52)]


def _px(img, x, y, c):
    if 0 <= x < 16 and 0 <= y < 16:
        img[y, x, :3] = c
        img[y, x, 3] = 255


def _line(img, x0, y0, x1, y1, cols, width=1):
    n = max(abs(x1 - x0), abs(y1 - y0)) + 1
    for i in range(n):
        t = i / max(n - 1, 1)
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        _px(img, x, y, cols[1])
        if width > 1:
            _px(img, x + 1, y, cols[2] if i % 3 else cols[1])


def _handle(img, length=9):
    # Diagonal from bottom-left upward to the right.
    for i in range(length):
        _px(img, 2 + i, 13 - i, HANDLE[1] if i % 2 else HANDLE[2])
        _px(img, 3 + i, 13 - i, HANDLE[0])


def _outline(img):
    a = np.pad(img[..., 3] > 0, 1)
    edge = np.zeros_like(a)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        edge |= np.roll(np.roll(a, dy, 0), dx, 1)
    edge = (edge & ~a)[1:-1, 1:-1]
    img[edge] = (28, 22, 18, 255)


def icon_pickaxe(tier):
    img = np.zeros((16, 16, 4))
    _handle(img, 10)
    c = ITEM_TIERS[tier]
    head = [(5, 2), (6, 2), (7, 2), (8, 2), (9, 3), (10, 3), (11, 4), (12, 5), (12, 6), (13, 7), (13, 8), (13, 9), (13, 10),
            (4, 3), (5, 3), (6, 3), (7, 3), (8, 3), (9, 4), (10, 4), (11, 5), (11, 6), (12, 7), (12, 8), (12, 9)]
    for i, (x, y) in enumerate(head):
        _px(img, x, y, c[2] if y < 4 or x > 12 else c[1])
    _px(img, 4, 2, c[0]); _px(img, 14, 10, c[0])
    _outline(img)
    return img


def icon_axe(tier):
    img = np.zeros((16, 16, 4))
    _handle(img, 12)
    c = ITEM_TIERS[tier]
    widths = [2, 3, 4, 4, 4, 3, 2]
    for k, w in enumerate(widths):
        y = 1 + k
        for x in range(10 - w, 11):
            _px(img, x, y, c[2] if x == 10 - w else c[1])
        _px(img, 11, y, c[0])
    _outline(img)
    return img


def icon_shovel(tier):
    img = np.zeros((16, 16, 4))
    _handle(img, 9)
    c = ITEM_TIERS[tier]
    for y in range(0, 7):
        for x in range(9, 16):
            if (x - 12.2) ** 2 + (y - 3.0) ** 2 < 8.5 and x + y > 11:
                _px(img, x, y, c[2] if x + y < 15 else c[1])
    _outline(img)
    return img


def icon_sword(tier):
    img = np.zeros((16, 16, 4))
    c = ITEM_TIERS[tier]
    for i in range(10):
        _px(img, 5 + i, 10 - i, c[2])
        _px(img, 6 + i, 10 - i, c[1])
        _px(img, 5 + i, 9 - i, c[1] if i < 9 else c[2])
    for i in range(-2, 3):
        _px(img, 5 + i, 11 + i, (64, 48, 30))
        _px(img, 6 + i, 12 + i, (84, 62, 38))
    _px(img, 3, 12, HANDLE[1]); _px(img, 2, 13, HANDLE[2]); _px(img, 1, 14, HANDLE[0])
    _outline(img)
    return img


def icon_stick():
    img = np.zeros((16, 16, 4))
    for i in range(11):
        _px(img, 3 + i, 13 - i, HANDLE[2] if i % 2 else HANDLE[1])
        _px(img, 4 + i, 13 - i, HANDLE[0])
    _outline(img)
    return img


def icon_coal():
    img = np.zeros((16, 16, 4))
    r2 = np.random.default_rng(77)
    for y in range(16):
        for x in range(16):
            d = ((x - 7.5) / 5.5) ** 2 + ((y - 8.0) / 4.8) ** 2
            if d < 1.0 + r2.uniform(-0.15, 0.15):
                v = 30 + r2.integers(0, 26)
                _px(img, x, y, (v, v - 2, v + 2))
    _px(img, 6, 6, (96, 96, 104)); _px(img, 9, 7, (80, 80, 88))
    _outline(img)
    return img


def icon_ingot():
    img = np.zeros((16, 16, 4))
    for y in range(6, 12):
        inset = (11 - y) // 2
        for x in range(2 + inset, 14 - (11 - y) // 3):
            top = y < 8
            _px(img, x, y, (238, 238, 242) if top else (196, 196, 202))
    for x in range(4, 12):
        _px(img, x, 11, (150, 150, 156))
    _outline(img)
    return img


def build_items():
    icons = [icon_stick(), icon_coal(), icon_ingot()]
    for maker in (icon_pickaxe, icon_axe, icon_shovel, icon_sword):
        for tier in ("wood", "stone", "iron"):
            icons.append(maker(tier))
    atlas = np.zeros((4 * 32, 8 * 32, 4))
    for i, ic in enumerate(icons):
        big = np.repeat(np.repeat(ic, 2, 0), 2, 1)
        tx, ty = (i % 8) * 32, (i // 8) * 32
        atlas[ty:ty + 32, tx:tx + 32] = big
    return atlas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    albedo, material = build()
    a_levels = mips(albedo, True, True)
    m_levels = mips(material, False, False)
    n = write(a_levels, OUT / "albedo.rgba.gz")
    write(m_levels, OUT / "material.rgba.gz")
    Image.fromarray(np.clip(albedo, 0, 255).astype(np.uint8)).resize((COLS * T * 4, ROWS * T * 4), Image.NEAREST).save(OUT / "atlas_preview.png")
    print(f"atlas {COLS * T}x{ROWS * T}, {len(a_levels)} mips, {n} bytes per atlas before gzip")
    items = build_items()
    write([items], OUT / "items.rgba.gz")
    Image.fromarray(items.astype(np.uint8)).resize((256 * 3, 128 * 3), Image.NEAREST).save(OUT / "items_preview.png")


if __name__ == "__main__":
    main()
