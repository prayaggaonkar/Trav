#!/usr/bin/env python3
"""Bake discrete purple point+line population glow into earth_night.jpg.

Night lights alone overstate the US/Europe and understate South Asia.
This bake blends night lights with a population prior (Natural Earth cities +
high-density rural belts) so glow and links track population more closely.
"""
from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

try:
    import shapefile
except ImportError:
    import subprocess
    import sys

    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp", "-q"])
    import shapefile

ROOT = Path(__file__).resolve().parents[1] / "Trav" / "Resources"
NE_CITIES = Path("/tmp/popdata/ne_cities/ne_10m_populated_places")
OUT_W, OUT_H = 4096, 2048
H, W = OUT_H, OUT_W


def ll_to_xy(lat: float, lon: float, w: int = W, h: int = H) -> tuple[int, int]:
    x = int(((lon + 180.0) / 360.0) * w) % w
    y = int(np.clip(((90.0 - lat) / 180.0) * h, 0, h - 1))
    return x, y


def blur_f32(arr: np.ndarray, radius: float) -> np.ndarray:
    """Gaussian blur a float32 field via uint8 proxy (preserves relative shape)."""
    mx = float(arr.max()) + 1e-6
    u8 = np.clip(arr / mx * 255.0, 0, 255).astype(np.uint8)
    out = np.asarray(Image.fromarray(u8).filter(ImageFilter.GaussianBlur(radius)), np.float32)
    return out / 255.0 * mx


def soft_box(lat: np.ndarray, lon: np.ndarray, la0, la1, lo0, lo1, amount, blur=14.0) -> np.ndarray:
    m = ((lat >= la0) & (lat <= la1) & (lon >= lo0) & (lon <= lo1)).astype(np.float32)
    m = blur_f32(m, blur)
    return m * amount


def build_population_prior(h: int, w: int) -> np.ndarray:
    """Persons-ish density field from cities + known high-density rural belts."""
    dens = np.zeros((h, w), np.float32)
    lat = (90.0 - (np.arange(h, dtype=np.float32) + 0.5) / h * 180.0)[:, None]
    lon = ((np.arange(w, dtype=np.float32) + 0.5) / w * 360.0 - 180.0)[None, :]

    if NE_CITIES.with_suffix(".shp").exists():
        r = shapefile.Reader(str(NE_CITIES))
        fields = [f[0] for f in r.fields[1:]]
        idx = {n: i for i, n in enumerate(fields)}
        tiers: dict[int, list[tuple[int, int, int]]] = {0: [], 1: [], 2: [], 3: [], 4: []}
        for rec, shape in zip(r.records(), r.shapes()):
            lo, la = shape.points[0]
            pop = int(rec[idx["POP_MAX"]] or 0)
            if pop < 25000:
                continue
            x, y = ll_to_xy(la, lo, w, h)
            if pop < 100_000:
                tiers[0].append((x, y, pop))
            elif pop < 500_000:
                tiers[1].append((x, y, pop))
            elif pop < 2_000_000:
                tiers[2].append((x, y, pop))
            elif pop < 8_000_000:
                tiers[3].append((x, y, pop))
            else:
                tiers[4].append((x, y, pop))
        params = {
            0: (max(1.5, 2.0 * w / 2048), 10),
            1: (max(2.5, 4.0 * w / 2048), 22),
            2: (max(4.0, 7.0 * w / 2048), 48),
            3: (max(7.0, 12.0 * w / 2048), 95),
            4: (max(10.0, 18.0 * w / 2048), 160),
        }
        for t, pts in tiers.items():
            rad, base = params[t]
            layer = Image.new("L", (w, h), 0)
            d = ImageDraw.Draw(layer)
            for x, y, pop in pts:
                s = int(np.clip(base * (pop / 1e5) ** 0.25, 18, 255))
                d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=s)
            dens += np.asarray(layer.filter(ImageFilter.GaussianBlur(rad * 0.7)), np.float32)

    # High rural-density belts that night lights under-represent
    scale = w / 2048.0
    dens += soft_box(lat, lon, 22, 32, 72, 90, 110, 16 * scale)  # Indo-Gangetic
    dens += soft_box(lat, lon, 21, 27, 88, 93, 130, 10 * scale)  # Bangladesh
    dens += soft_box(lat, lon, 8, 13, 76, 80.5, 55, 10 * scale)  # S India coast
    dens += soft_box(lat, lon, 15, 22, 72, 87, 50, 14 * scale)  # Deccan belt
    dens += soft_box(lat, lon, 28, 34, 70, 76, 70, 12 * scale)  # Pakistan Punjab
    dens += soft_box(lat, lon, -8.5, -5.8, 105, 114.5, 115, 8 * scale)  # Java
    dens += soft_box(lat, lon, 29.5, 31.5, 29.5, 32.5, 85, 6 * scale)  # Nile delta
    dens += soft_box(lat, lon, 21.5, 24, 112, 115, 65, 6 * scale)  # Pearl River
    dens += soft_box(lat, lon, 29.5, 32.5, 118, 122, 70, 8 * scale)  # Yangtze delta
    dens += soft_box(lat, lon, 6, 8.5, 2.5, 5.5, 60, 6 * scale)  # Lagos
    dens += soft_box(lat, lon, 13.5, 16.5, 120, 122, 50, 5 * scale)  # Luzon
    dens += soft_box(lat, lon, 7, 14, 36, 42, 40, 10 * scale)  # Ethiopia
    dens += soft_box(lat, lon, 20, 22, 105, 107, 55, 5 * scale)  # Hanoi
    dens += soft_box(lat, lon, 9.5, 11.5, 105.5, 107, 50, 5 * scale)  # Mekong
    dens += soft_box(lat, lon, 23, 31, 112, 121, 35, 18 * scale)  # E China corridor
    dens += soft_box(lat, lon, 33, 38, 126, 130, 45, 6 * scale)  # Seoul/NW

    dens = blur_f32(dens, 1.2 * scale)
    return dens


def lights_to_pop_weight(lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    """Correct night-light bias: US/Europe bright per capita, South Asia dim."""
    w = np.ones(lat.shape, np.float32)

    def apply(la0, la1, lo0, lo1, mul, blur=20.0):
        nonlocal w
        m = soft_box(lat, lon, la0, la1, lo0, lo1, 1.0, blur)
        w = w * (1.0 - m) + (w * mul) * m

    # Contiguous US — strong damp, especially east of Mississippi sprawl mesh
    apply(24, 49.5, -125, -66, 0.42, 22)
    apply(24, 48, -90, -66, 0.55, 14)  # extra cut on US East (multiplicative on top)
    # Canada south
    apply(42, 56, -125, -60, 0.50, 18)
    # Western Europe over-lit
    apply(36, 60, -10, 20, 0.62, 18)
    # Australia
    apply(-44, -10, 112, 154, 0.55, 16)
    # South Asia — boost hard (low lights / high population)
    apply(6, 37, 66, 98, 2.85, 18)
    apply(20, 27, 88, 93, 1.35, 8)  # Bangladesh extra
    # SE Asia
    apply(-10, 20, 95, 125, 1.85, 16)
    apply(-8.5, -5.5, 105, 115, 1.40, 6)  # Java extra
    # Sub-Saharan population belts
    apply(-5, 15, -5, 15, 1.70, 14)  # W Africa
    apply(-5, 5, 28, 42, 1.55, 12)  # E Africa
    # North Africa / Nile already handled by arid logic; mild boost Maghreb coast cities via lights
    apply(29, 32, 29, 33, 1.45, 5)
    # China: night lights already strong; mild boost inland
    apply(22, 42, 100, 122, 1.15, 16)
    # Latin America mid
    apply(-35, 12, -82, -34, 0.90, 18)
    # Alaska / northern Canada — only real towns (prior + lights); don't invent
    apply(55, 72, -170, -130, 0.85, 12)

    return np.clip(w, 0.25, 4.0)


def americas_mask(lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    in_n = (lat > 7.0) & (lat < 72.0) & (lon > -170.0) & (lon < -52.0)
    in_s = (lat > -56.0) & (lat < 13.0) & (lon > -82.0) & (lon < -34.0)
    in_cam = (lat > 7.0) & (lat < 33.0) & (lon > -118.0) & (lon < -77.0)
    mask = (in_n | in_s | in_cam).astype(np.float32)
    return blur_f32(mask, 18.0)


def main() -> None:
    day_src = np.asarray(
        Image.open(ROOT / "Textures/earth-blue-marble.jpg")
        .convert("RGB")
        .resize((OUT_W, OUT_H), Image.LANCZOS),
        np.float32,
    )
    night_src = np.asarray(
        Image.open(ROOT / "Textures/earth-night.jpg")
        .convert("RGB")
        .resize((OUT_W, OUT_H), Image.LANCZOS),
        np.float32,
    )

    r, g, b = day_src[:, :, 0], day_src[:, :, 1], day_src[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    ocean = (b > g + 5) & (b > r + 8) & (lum < 160)

    yy = np.linspace(-1, 1, H, dtype=np.float32)[:, None]
    xx = np.linspace(-1, 1, W, dtype=np.float32)[None, :]
    ice = (np.abs(yy) > 0.55) & (lum > 145)
    ice |= (lum > 170) & (np.abs(r - g) < 40) & (np.abs(g - b) < 40) & (np.abs(yy) > 0.42)
    ice |= (yy < -0.45) & (xx > -0.55) & (xx < -0.05) & (lum > 140)
    ice_m = blur_f32(ice.astype(np.float32), 2.0)

    topo = (
        np.asarray(
            Image.open(ROOT / "Textures/earth-topology.png")
            .convert("L")
            .resize((OUT_W, OUT_H), Image.LANCZOS),
            np.float32,
        )
        / 255.0
    )
    land = ((~ocean) | (topo > 0.018)).astype(np.float32)
    land = blur_f32(land, 1.0)
    land_only = np.clip(land * (1.0 - ice_m * 0.75), 0, 1)
    ocean_m = blur_f32(ocean.astype(np.float32), 1.0)
    ocean_m = np.clip(ocean_m * (1.0 - ice_m), 0, 1)

    greenness = (g - np.maximum(r, b)) / 255.0
    arid = (lum > 105) & (greenness < 0.02) & (b < r + 25) & (~ocean) & (ice_m < 0.25)
    arid_m = blur_f32(arid.astype(np.float32), 5.0)

    print("building population prior…")
    pop_prior = build_population_prior(H, W)
    # Normalize prior to ~0..1 with headroom for hubs
    prior_n = pop_prior / (np.percentile(pop_prior, 99.0) + 1e-6)
    prior_n = np.clip(prior_n, 0, 1.5)

    lat = (90.0 - (np.arange(H, dtype=np.float32) + 0.5) / H * 180.0)[:, None]
    lon = ((np.arange(W, dtype=np.float32) + 0.5) / W * 360.0 - 180.0)[None, :]
    lat = np.broadcast_to(lat, (H, W)).copy()
    lon = np.broadcast_to(lon, (H, W)).copy()
    lt_weight = lights_to_pop_weight(lat, lon)

    nr, ng, nb = night_src[:, :, 0], night_src[:, :, 1], night_src[:, :, 2]
    lights = np.maximum(nr, ng).astype(np.float32)
    airglow = np.clip(nb - np.maximum(nr, ng), 0, 255)
    lights = np.clip(lights - airglow * 1.25, 0, 255)

    blur = blur_f32(lights, 10)
    local = np.clip(lights - blur * 0.75, 0, 255)
    sheet = blur_f32(lights, 28)

    # Population-proportional field:
    #   - prior carries true dense regions (India etc.)
    #   - lights locate settlements, reweighted for lights-per-capita bias
    lights_n = np.clip(lights / 255.0, 0, 1)
    local_n = np.clip(local / 255.0, 0, 1)
    lights_adj = np.clip(lights_n * lt_weight, 0, 2.5)

    # Geometric blend: need BOTH some settlement signal and population context
    # High prior + modest lights (India villages) still scores; low prior + bright
    # suburban US lights get cut.
    pop_signal = np.power(np.clip(prior_n, 0, 1.5), 0.85)
    light_signal = np.power(np.clip(0.55 * lights_adj + 0.45 * local_n * lt_weight, 0, 2.0), 0.90)
    score = 255.0 * np.clip(0.58 * pop_signal + 0.42 * light_signal, 0, 1.6)
    # Extra: where prior is high, allow weaker lights to still place points
    score = np.maximum(score, 255.0 * np.clip(prior_n * 0.55 * np.clip(lights_adj * 2.2, 0.15, 1.0), 0, 1))

    score *= (1.0 - ocean_m) * (1.0 - np.clip(ice_m - 0.2, 0, 1))

    sheet_ratio = sheet / (lights + 8.0)
    score *= np.clip(1.35 - sheet_ratio * 0.85, 0.25, 1.0)

    desert_weak = (arid_m > 0.35) & ((lights < 48) | (local < 18)) & (prior_n < 0.35)
    score = np.where(desert_weak, 0.0, score)
    weak = np.clip(1.0 - score / 45.0, 0, 1)
    score *= 1.0 - arid_m * 0.65 * weak

    # Kill empty bush: no lights AND no population prior
    score = np.where((lights < 10) & (prior_n < 0.12), 0.0, score)
    score = np.where(score < 10.0, 0.0, score)

    amer = americas_mask(lat, lon)

    print("collecting points…")
    points: list[tuple[int, int, float, float]] = []  # x,y,inten,prior

    def collect(field: np.ndarray, block: int, min_val: float, weight: float):
        out = []
        for by in range(0, H, block):
            for bx in range(0, W, block):
                patch = field[by : by + block, bx : bx + block]
                if patch.size == 0:
                    continue
                mv = float(patch.max())
                if mv < min_val:
                    continue
                py, px = np.unravel_index(int(np.argmax(patch)), patch.shape)
                x, y = bx + int(px), by + int(py)
                p_lights = float(lights[y, x])
                p_prior = float(prior_n[y, x])
                if land_only[y, x] < 0.28 and p_lights < 30 and p_prior < 0.2:
                    continue
                if ice_m[y, x] > 0.6 and p_lights < 32 and p_prior < 0.15:
                    continue
                if arid_m[y, x] > 0.4 and p_lights < 45 and p_prior < 0.3:
                    continue
                # Intensity from population prior primarily, lights as secondary
                inten = float(
                    np.clip(
                        (0.62 * min(p_prior, 1.2) + 0.38 * min(p_lights / 160.0 * lt_weight[y, x], 1.2))
                        * weight,
                        0,
                        1,
                    )
                )
                if inten < 0.08:
                    continue
                out.append((x, y, inten, p_prior))
        return out

    # Denser sampling in high-prior regions via lower thresholds where prior is strong
    score_boosted = score * (0.75 + 0.55 * np.clip(prior_n, 0, 1))
    points += collect(score_boosted, 5, 11, 0.95)
    points += collect(score_boosted, 10, 22, 1.10)
    points += collect(score_boosted, 20, 40, 1.25)
    points.sort(key=lambda p: -p[2])

    kept: list[tuple[int, int, float, float]] = []
    occupied = np.zeros((H, W), np.uint8)
    for x, y, inten, pr in points:
        # US East sprawl: larger exclusion so mid-tier dots don't carpet
        us_east = (lat[y, x] > 24) & (lat[y, x] < 49) & (lon[y, x] > -90) & (lon[y, x] < -66)
        rad = 2 if inten < 0.45 else (3 if inten < 0.7 else 4)
        if us_east and inten < 0.55 and pr < 0.45:
            rad = max(rad, 4)  # thin suburban mesh
        y0, y1 = max(0, y - rad), min(H, y + rad + 1)
        x0, x1 = max(0, x - rad), min(W, x + rad + 1)
        if occupied[y0:y1, x0:x1].any():
            continue
        occupied[y, x] = 1
        kept.append((x, y, inten, pr))
    points = kept[:55000]
    print("points", len(points))

    point_img = Image.new("L", (W, H), 0)
    pdraw = ImageDraw.Draw(point_img)
    for x, y, inten, pr in points:
        rad = 0.5 + inten * 2.05
        strength = int(np.clip(45 + inten * 210, 35, 255))
        pdraw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=strength)
        if inten > 0.62 and (pr >= 0.35 or lights[y, x] >= 55):
            pdraw.ellipse([x - 1.0, y - 1.0, x + 1.0, y + 1.0], fill=255)
    point_buf = np.asarray(point_img, np.float32) / 255.0
    soft = blur_f32(point_buf * 255.0, 0.5) / 255.0
    point_layer = np.clip(point_buf * 1.05 + soft * 0.20, 0, 1)

    cell = 48
    grid: dict[tuple[int, int], list[int]] = defaultdict(list)
    for i, (x, y, inten, pr) in enumerate(points):
        grid[(x // cell, y // cell)].append(i)

    def neighbors(i: int, max_dist: float, k: int):
        x, y, inten, pr = points[i]
        cx, cy = x // cell, y // cell
        cands = []
        reach = int(max_dist // cell) + 1
        for dx in range(-reach, reach + 1):
            for dy in range(-reach, reach + 1):
                for j in grid.get((cx + dx, cy + dy), []):
                    if j <= i:
                        continue
                    x2, y2, inten2, pr2 = points[j]
                    ddx = x2 - x
                    if ddx > W / 2:
                        ddx -= W
                    elif ddx < -W / 2:
                        ddx += W
                    if abs(ddx) > W * 0.25:
                        continue
                    ddy = y2 - y
                    d = (ddx * ddx + ddy * ddy) ** 0.5
                    if d < 3 or d > max_dist:
                        continue
                    # Prefer linking toward other high-population nodes
                    score_link = d / (0.35 + 0.65 * max(inten2, pr2))
                    cands.append((score_link, d, j, ddx, ddy))
        cands.sort()
        return cands[:k]

    line_img = Image.new("L", (W, H), 0)
    ldraw = ImageDraw.Draw(line_img)
    for i, (x, y, inten, pr) in enumerate(points):
        if inten < 0.18:
            continue
        arid_here = float(arid_m[y, x])
        us_east = bool((lat[y, x] > 24) & (lat[y, x] < 49) & (lon[y, x] > -90) & (lon[y, x] < -66))
        # Population-dense areas get MORE links (India); US East sprawl gets FEWER
        if pr >= 0.45:
            k = 7 if inten >= 0.35 else 5
            max_d = 48 + inten * 38 + pr * 28
        elif pr >= 0.25:
            k = 5
            max_d = 38 + inten * 32
        else:
            k = 3 if inten < 0.5 else 4
            max_d = 28 + inten * 26

        if us_east and pr < 0.5:
            k = min(k, 3)
            max_d *= 0.62
        if arid_here > 0.35:
            k = min(k, 3)
            max_d = min(max_d, 28 + inten * 20)

        for _, d, j, ddx, ddy in neighbors(i, max_d, k):
            inten2, pr2 = points[j][2], points[j][3]
            if min(inten, inten2) < 0.20 and min(pr, pr2) < 0.25:
                continue
            # Stronger lines between high-population nodes
            pop_boost = 0.75 + 0.55 * min(1.0, (pr + pr2) * 0.5)
            strength = int(
                np.clip(42 + 115 * min(inten, inten2) * (1 - d / max_d) * pop_boost, 30, 195)
            )
            if us_east and pr < 0.45:
                strength = int(strength * 0.72)
            if arid_here > 0.4:
                strength = int(strength * 0.8)
            y2 = points[j][1]
            ldraw.line([(x, y), (x + ddx, y2)], fill=strength, width=1)

    # Long hub links — prefer high-prior hubs (Delhi–Kolkata–Mumbai etc.)
    hubs = [i for i, p in enumerate(points) if p[2] >= 0.48 or p[3] >= 0.55]
    for i in hubs:
        x, y, inten, pr = points[i]
        cands = []
        for j in hubs:
            if j <= i:
                continue
            x2, y2, inten2, pr2 = points[j]
            ddx = x2 - x
            if ddx > W / 2:
                ddx -= W
            elif ddx < -W / 2:
                ddx += W
            if abs(ddx) > W * 0.3:
                continue
            ddy = y2 - y
            d = (ddx * ddx + ddy * ddy) ** 0.5
            if d < 40 or d > 280:
                continue
            cands.append((d / (0.3 + 0.7 * max(inten2, pr2)), d, j, ddx))
        cands.sort()
        n_hub = 4 if pr >= 0.5 else 2
        for _, d, j, ddx in cands[:n_hub]:
            y2 = points[j][1]
            inten2, pr2 = points[j][2], points[j][3]
            strength = int(
                np.clip(55 + 120 * min(max(inten, pr), max(inten2, pr2)) * (1 - d / 280), 40, 200)
            )
            ldraw.line([(x, y), (x + ddx, y2)], fill=strength, width=1)

    line_buf = np.asarray(line_img, np.float32) / 255.0
    line_soft = blur_f32(line_buf * 255.0, 0.4) / 255.0
    line_layer = np.clip(line_buf * 1.05 + line_soft * 0.28, 0, 1)

    cable_img = Image.new("L", (W, H), 0)
    cd = ImageDraw.Draw(cable_img)

    def wrap_dx(a: int, b: int) -> int:
        d = b - a
        if d > W / 2:
            d -= W
        elif d < -W / 2:
            d += W
        return d

    for a, b in [
        ((40.7, -74), (51.5, -0.1)),
        ((28.6, 77.2), (19.08, 72.88)),  # Delhi–Mumbai
        ((28.6, 77.2), (22.57, 88.36)),  # Delhi–Kolkata
        ((19.08, 72.88), (12.97, 77.59)),  # Mumbai–Bangalore
        ((22.57, 88.36), (23.81, 90.41)),  # Kolkata–Dhaka
        ((48.8, 2.3), (35.7, 139.7)),
        ((35.7, 139.7), (37.8, -122.4)),
        ((30.0, 31.2), (41.9, 12.5)),
        ((-33.9, 151.2), (1.35, 103.8)),
        ((19.08, 72.88), (1.35, 103.8)),
        ((51.5, -0.1), (28.6, 77.2)),
    ]:
        p0, p1 = ll_to_xy(*a), ll_to_xy(*b)
        if abs(wrap_dx(p0[0], p1[0])) > W * 0.4:
            continue
        cd.line([p0, p1], fill=58, width=1)
    cables = (
        np.asarray(Image.fromarray(np.asarray(cable_img)).filter(ImageFilter.GaussianBlur(0.5)), np.float32)
        / 255.0
    )

    purple_line = np.array([160, 45, 240], np.float32)
    purple_point = np.array([230, 75, 255], np.float32)
    purple_hot = np.array([255, 110, 255], np.float32)

    emit = np.zeros((H, W, 3), np.float32)
    emit += line_layer[:, :, None] * purple_line * 1.35
    emit += cables[:, :, None] * purple_line * 0.45
    hot_mask = np.clip((point_buf - 0.65) / 0.35, 0, 1)
    emit += (
        point_layer[:, :, None]
        * (
            purple_point[None, None, :] * (1 - hot_mask)[:, :, None]
            + purple_hot[None, None, :] * hot_mask[:, :, None]
        )
        * 1.55
    )

    ice_kill = np.clip(ice_m - point_buf * 0.95, 0, 1)
    emit *= (1.0 - ice_kill)[:, :, None]
    land_emit = emit * (1.0 - ocean_m)[:, :, None]
    ocean_emit = cables[:, :, None] * purple_line * 0.35 * ocean_m[:, :, None]
    emit = land_emit + ocean_emit

    # Americas: ~20% less, extra on low-pop pixels
    emit_lum = emit.max(axis=2)
    low = np.clip(1.0 - emit_lum / 70.0, 0, 1)
    low_pop = np.clip(1.0 - prior_n / 0.45, 0, 1)
    amer_mul = 1.0 - amer * (0.20 + 0.20 * np.maximum(low, low_pop * 0.7))
    emit *= amer_mul[:, :, None]

    # Extra US-East sprawl thin (night lights invent a dense mesh east of the Mississippi)
    us_east = soft_box(lat, lon, 24, 49, -92, -66, 1.0, 20.0)
    mid = np.clip(1.0 - np.abs(emit_lum - 90.0) / 120.0, 0, 1)
    us_cut = us_east * (0.22 + 0.28 * low + 0.18 * mid)
    emit *= (1.0 - us_cut)[:, :, None]

    # Mild lift on existing South Asia network (high population, dim lights)
    sasia = soft_box(lat, lon, 7, 36, 68, 98, 1.0, 18.0)
    emit *= (1.0 + sasia * (emit_lum > 15).astype(np.float32) * 0.12)[:, :, None]

    night_out = np.clip(emit, 0, 255).astype(np.uint8)

    out_hi = ROOT / "Textures/earth_night.jpg"
    out_lo = ROOT / "Assets.xcassets/earth_night.imageset/earth_night.jpg"
    Image.fromarray(night_out).save(out_hi, "JPEG", quality=96, optimize=True, subsampling=0)
    # Keep catalog at full 4K so zoomed emission stays sharp.
    Image.fromarray(night_out).save(out_lo, "JPEG", quality=96, optimize=True, subsampling=0)
    print("wrote", out_hi)
    print("wrote", out_lo)

    def region(name, la0, la1, lo0, lo1):
        x0 = int((lo0 + 180) / 360 * W) % W
        x1 = int((lo1 + 180) / 360 * W) % W
        y0 = int((90 - la1) / 180 * H)
        y1 = int((90 - la0) / 180 * H)
        if x0 < x1:
            reg = night_out[y0:y1, x0:x1]
            pr = prior_n[y0:y1, x0:x1]
        else:
            reg = np.concatenate([night_out[y0:y1, x0:], night_out[y0:y1, :x1]], 1)
            pr = np.concatenate([prior_n[y0:y1, x0:], prior_n[y0:y1, :x1]], 1)
        bright = (reg.max(2) > 25).mean()
        print(
            f"{name:18s} bright={bright:.4f} mean={reg.mean():.1f} "
            f"prior={pr.mean():.3f} ratio={reg.mean() / max(pr.mean(), 0.01):.1f}"
        )

    def nbmax(la, lo, radius=6):
        x, y = ll_to_xy(la, lo)
        xs = [(x + dx) % W for dx in range(-radius, radius + 1)]
        return float(night_out[max(0, y - radius) : min(H, y + radius + 1)][:, xs].max())

    print("\nRegions:")
    for n, a in [
        ("US East", (24, 49, -90, -66)),
        ("US West", (31, 49, -125, -100)),
        ("India", (7, 36, 68, 98)),
        ("N China plain", (30, 42, 112, 122)),
        ("W Europe", (42, 54, -5, 15)),
        ("Nigeria", (4, 14, 2, 15)),
        ("N Africa", (15, 37, -17, 40)),
        ("Alaska", (55, 72, -170, -130)),
    ]:
        region(n, *a)

    print("\nCities:")
    for name, la, lo in [
        ("NYC", 40.7, -74),
        ("Rural Ohio", 40.5, -82.5),
        ("Delhi", 28.6, 77.2),
        ("Mumbai", 19.08, 72.88),
        ("Kolkata", 22.57, 88.36),
        ("Dhaka", 23.81, 90.41),
        ("Bangalore", 12.97, 77.59),
        ("Sahara", 24, 10),
        ("Anchorage", 61.2, -149.9),
        ("Cairo", 30.04, 31.24),
    ]:
        print(f"  {name:12s} {nbmax(la, lo):5.0f}")


if __name__ == "__main__":
    main()
