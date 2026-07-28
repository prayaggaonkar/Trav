#!/usr/bin/env python3
"""Bake a daytime land/ocean diffuse for light mode from earth_day.jpg.

Oceans are recolored to daylight blues; land is lifted to a sunlit look
with highlight compression so Sahara / Arabia / other arid regions stay natural.
Does not touch earth_night (purple network).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Trav/Resources/Textures/earth_day.jpg"
OUT_TEX = ROOT / "Trav/Resources/Textures/earth_day_light.jpg"
OUT_ASSET_DIR = ROOT / "Trav/Resources/Assets.xcassets/earth_day_light.imageset"
OUT_ASSET = OUT_ASSET_DIR / "earth_day_light.jpg"


def blur_channel(arr: np.ndarray, radius: float) -> np.ndarray:
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="L")
    out = img.filter(ImageFilter.GaussianBlur(radius=radius))
    return np.asarray(out, dtype=np.float32)


def compress_arid_highlights(rgb: np.ndarray) -> np.ndarray:
    """Pull chalky Sahara / Arabia sand toward natural dusty beige."""
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    warmth = r - b
    greenish = g - np.maximum(r, b)
    arid = (
        np.clip((lum - 95.0) / 90.0, 0, 1)
        * np.clip((warmth - 10.0) / 55.0, 0, 1)
        * np.clip(1.0 - greenish / 20.0, 0, 1)
        * np.clip(1.0 - np.abs(r - g) / 55.0, 0.4, 1.0)
    )
    detail = rgb - lum[..., None]
    base = np.array([128.0, 112.0, 92.0], dtype=np.float32)
    target = np.clip(base + detail * 0.45 + (rgb - base) * 0.2, 0, 255)
    dest = target * 0.7 + lum[..., None] * 0.3
    mix = (np.power(np.clip(arid, 0, 1), 0.85) * 0.9)[..., None]
    return rgb * (1.0 - mix) + dest * mix


def bake(source: Image.Image) -> Image.Image:
    a = np.asarray(source.convert("RGB"), dtype=np.float32)
    a = compress_arid_highlights(a)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

    blue_dom = b - np.maximum(r, g)
    ocean_score = np.clip(blue_dom / 40.0, 0, 1) * np.clip((110 - lum) / 90.0, 0, 1)
    navy = (lum < 55) & (b >= r) & (b >= g - 5)
    ocean_score = np.maximum(ocean_score, navy.astype(np.float32) * 0.95)
    landish = (lum > 95) & (blue_dom < 10)
    ocean_score = np.where(landish, ocean_score * 0.15, ocean_score)
    ocean_score = blur_channel(np.clip(ocean_score, 0, 1) * 255.0, 1.5) / 255.0
    ocean_score = np.clip(ocean_score, 0, 1)[..., None]

    # Daytime blues follow the already-textured dark-mode ocean depth.
    soft_lum = blur_channel(lum, 9.0)
    t = np.clip((soft_lum - 8.0) / 85.0, 0, 1)[..., None]
    deep = np.array([8, 48, 108], dtype=np.float32)
    mid = np.array([16, 78, 138], dtype=np.float32)
    shallow = np.array([28, 102, 158], dtype=np.float32)
    ocean_col = np.where(
        t < 0.45,
        deep + (mid - deep) * (t / 0.45),
        mid + (shallow - mid) * ((t - 0.45) / 0.55),
    )
    # Keep open-ocean texture from the smoothed day map (land untouched via mask).
    ocean_col = np.clip(ocean_col * 0.62 + a * 0.38, 0, 255)

    # Sunlit land — lift shadows/midtones; skip warm boost on arid sand.
    shadow = 1.0 - np.clip(lum / 190.0, 0, 1)
    lift = 1.08 + 0.22 * shadow
    bias = 8.0 * shadow
    land = np.clip(a * lift[..., None] + bias[..., None], 0, 255)
    warmth = land[:, :, 0] - land[:, :, 2]
    arid_w = np.clip((lum - 90.0) / 85.0, 0, 1) * np.clip((warmth - 8.0) / 50.0, 0, 1)
    warm_amt = (1.0 - arid_w)[..., None]
    land_warm = land.copy()
    land_warm[:, :, 1] = np.clip(land[:, :, 1] * 1.05 + 4, 0, 255)
    land_warm[:, :, 0] = np.clip(land[:, :, 0] * 1.03 + 2, 0, 255)
    land_warm[:, :, 2] = np.clip(land[:, :, 2] * 0.94, 0, 255)
    land = land * (1.0 - warm_amt) + land_warm * warm_amt
    land = compress_arid_highlights(land)

    out = ocean_col * ocean_score + land * (1.0 - ocean_score)
    out = compress_arid_highlights(out)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    src = Image.open(SRC)
    out = bake(src)
    OUT_TEX.parent.mkdir(parents=True, exist_ok=True)
    OUT_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    out.save(OUT_TEX, quality=95, optimize=True, subsampling=0)
    out.save(OUT_ASSET, quality=95, optimize=True, subsampling=0)
    (OUT_ASSET_DIR / "Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "earth_day_light.jpg",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    )
    print(f"Wrote {OUT_TEX}")
    print(f"Wrote {OUT_ASSET}")


if __name__ == "__main__":
    main()
