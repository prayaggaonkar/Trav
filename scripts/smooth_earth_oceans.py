#!/usr/bin/env python3
"""Smooth blotchy bathymetry in earth_day into soft ocean depth gradients.

Keeps land pixels essentially unchanged. Open ocean gets multi-scale soft
depth texture in the same style as the coastal shelves. Writes Textures +
asset-catalog copies, then rebakes earth_day_light from the smoothed day map.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
DAY_TEX = ROOT / "Trav/Resources/Textures/earth_day.jpg"
DAY_ASSET = ROOT / "Trav/Resources/Assets.xcassets/earth_day.imageset/earth_day.jpg"
TOPO = ROOT / "Trav/Resources/Textures/earth-topology.png"


def blur_channel(arr: np.ndarray, radius: float) -> np.ndarray:
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "L")
    out = img.filter(ImageFilter.GaussianBlur(radius=radius))
    return np.asarray(out, dtype=np.float32)


def soft_ocean_mask(rgb: np.ndarray) -> np.ndarray:
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    blue_dom = b - np.maximum(r, g)
    ocean = np.clip(blue_dom / 35.0, 0, 1) * np.clip((120.0 - lum) / 90.0, 0, 1)
    navy = ((lum < 62) & (b >= r) & (b >= g - 6)).astype(np.float32)
    ocean = np.maximum(ocean, navy * 0.98)
    # Bright ice / land must stay out of the ocean remap.
    landish = (lum > 105) & (blue_dom < 12)
    warm = (r > g + 8) & (r > b + 8) & (lum > 70)
    green = (g > r + 8) & (g > b + 5) & (lum > 55)
    ocean = np.where(landish | warm | green, 0.0, ocean)
    ocean = blur_channel(ocean * 255.0, 2.5) / 255.0
    return np.clip(ocean, 0, 1)


def soft_value_noise(h: int, w: int, cell: int, seed: int) -> np.ndarray:
    """Low-frequency value noise, bilinearly upsampled and blurred."""
    rng = np.random.default_rng(seed)
    gh = max(2, h // cell + 2)
    gw = max(2, w // cell + 2)
    grid = rng.random((gh, gw), dtype=np.float32)
    small = Image.fromarray((grid * 255).astype(np.uint8), "L").resize(
        (w, h), Image.BILINEAR
    )
    return blur_channel(np.asarray(small, dtype=np.float32), cell * 0.35) / 255.0


def ocean_depth_field(
    lum: np.ndarray, ocean: np.ndarray, land: np.ndarray
) -> np.ndarray:
    """Multi-scale soft depth in the same language as coastal shelves."""
    h, w = lum.shape
    # Masked luminance so land doesn't pollute open-ocean blur.
    filled_lum = np.where(ocean > 0.25, lum, 22.0)

    large = blur_channel(filled_lum, 48.0)
    medium = blur_channel(filled_lum, 18.0)
    fine = blur_channel(filled_lum, 8.0)

    # Soft ridges = medium structure above the large-scale basin.
    ridge = np.clip((medium - large) / 22.0 + 0.32, 0, 1)
    basin = np.clip((large - 10.0) / 60.0, 0, 1)
    fine_tex = np.clip((fine - medium) / 14.0 + 0.5, 0, 1)

    # Optional topology bathymetry cue (darker = deeper on many topo maps).
    topo_term = np.zeros_like(lum)
    if TOPO.exists():
        topo = np.asarray(
            Image.open(TOPO).convert("L").resize((w, h), Image.LANCZOS),
            dtype=np.float32,
        )
        topo = blur_channel(topo, 10.0)
        # Invert so deep basins push toward darker water.
        topo_term = np.clip(1.0 - topo / 255.0, 0, 1)

    n1 = soft_value_noise(h, w, 110, seed=11)
    n2 = soft_value_noise(h, w, 56, seed=29)
    swell = n1 * 0.65 + n2 * 0.35

    coast = blur_channel(land * 255.0, 34.0) / 255.0
    open_w = np.clip(1.0 - coast * 1.35, 0, 1)

    # Coasts: land proximity (existing look). Open ocean: soft basin + ridges + swell.
    t = (
        coast * 0.48
        + open_w
        * (
            basin * 0.26
            + ridge * 0.30
            + fine_tex * 0.10
            + topo_term * 0.14
            + swell * 0.18
        )
    )
    # Slight extra blur on the depth field for smoother color ramps.
    t = blur_channel(np.clip(t, 0, 1) * 255.0, 4.0) / 255.0
    return np.clip(t, 0, 1)


def smooth_oceans(source: Image.Image) -> Image.Image:
    rgb = np.asarray(source.convert("RGB"), dtype=np.float32)
    ocean = soft_ocean_mask(rgb)
    land = 1.0 - ocean

    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

    t = ocean_depth_field(lum, ocean, land)

    deep = np.array([4.0, 14.0, 42.0], dtype=np.float32)
    mid = np.array([9.0, 36.0, 78.0], dtype=np.float32)
    shelf = np.array([18.0, 58.0, 108.0], dtype=np.float32)
    shallow = np.array([26.0, 78.0, 128.0], dtype=np.float32)

    t3 = t[..., None]
    ocean_col = np.where(
        t3 < 0.35,
        deep + (mid - deep) * (t3 / 0.35),
        np.where(
            t3 < 0.7,
            mid + (shelf - mid) * ((t3 - 0.35) / 0.35),
            shelf + (shallow - shelf) * ((t3 - 0.7) / 0.3),
        ),
    )

    # Mild chroma undulation so large basins aren't paint-flat.
    deep_fill = np.array([6.0, 20.0, 52.0], dtype=np.float32)
    filled = rgb * ocean[..., None] + deep_fill * land[..., None]
    blurred = np.stack(
        [
            blur_channel(filled[:, :, 0], 28.0),
            blur_channel(filled[:, :, 1], 28.0),
            blur_channel(filled[:, :, 2], 28.0),
        ],
        axis=2,
    )
    ocean_col = np.clip(ocean_col * 0.88 + blurred * 0.12, 0, 255)

    # Soft composite — land stays original.
    m = np.clip(ocean * 1.15, 0, 1)[..., None]
    out = ocean_col * m + rgb * (1.0 - m)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    src = Image.open(DAY_TEX)
    out = smooth_oceans(src)
    DAY_TEX.parent.mkdir(parents=True, exist_ok=True)
    DAY_ASSET.parent.mkdir(parents=True, exist_ok=True)
    out.save(DAY_TEX, quality=95, optimize=True, subsampling=0)
    out.save(DAY_ASSET, quality=95, optimize=True, subsampling=0)
    print(f"Wrote {DAY_TEX}")
    print(f"Wrote {DAY_ASSET}")

    bake = ROOT / "scripts/bake_earth_day_light.py"
    subprocess.check_call([sys.executable, str(bake)])


if __name__ == "__main__":
    main()
