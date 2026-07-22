#!/usr/bin/env python3
"""Bake a daytime land/ocean diffuse for light mode from earth_day.jpg.

Oceans are recolored to daylight blues; land is lifted to a sunlit look.
Does not touch earth_night (purple network).
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "Trav/Resources/Textures/earth_day.jpg"
OUT_TEX = ROOT / "Trav/Resources/Textures/earth_day_light.jpg"
OUT_ASSET_DIR = ROOT / "Trav/Resources/Assets.xcassets/earth_day_light.imageset"
OUT_ASSET = OUT_ASSET_DIR / "earth_day_light.jpg"


def bake(source: Image.Image) -> Image.Image:
    a = np.asarray(source.convert("RGB"), dtype=np.float32)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

    blue_dom = b - np.maximum(r, g)
    ocean_score = np.clip(blue_dom / 40.0, 0, 1) * np.clip((110 - lum) / 90.0, 0, 1)
    navy = (lum < 55) & (b >= r) & (b >= g - 5)
    ocean_score = np.maximum(ocean_score, navy.astype(np.float32) * 0.95)
    landish = (lum > 95) & (blue_dom < 10)
    ocean_score = np.where(landish, ocean_score * 0.15, ocean_score)
    ocean_score = np.clip(ocean_score, 0, 1)[..., None]

    # Daytime ocean palette driven by original luminance (depth cue).
    t = np.clip(lum / 70.0, 0, 1)[..., None]
    deep = np.array([18, 95, 175], dtype=np.float32)
    mid = np.array([35, 145, 205], dtype=np.float32)
    shallow = np.array([85, 185, 220], dtype=np.float32)
    ocean_col = np.where(
        t < 0.45,
        deep + (mid - deep) * (t / 0.45),
        mid + (shallow - mid) * ((t - 0.45) / 0.55),
    )
    detail = (a - lum[..., None]) * 0.55
    ocean_col = np.clip(ocean_col + detail * ocean_score, 0, 255)

    # Sunlit land — preserve structure, warmer greens/tans.
    land = np.clip(a * 1.35 + 18, 0, 255)
    land[:, :, 1] = np.clip(land[:, :, 1] * 1.08 + 6, 0, 255)
    land[:, :, 0] = np.clip(land[:, :, 0] * 1.05 + 4, 0, 255)
    land[:, :, 2] = np.clip(land[:, :, 2] * 0.92, 0, 255)

    out = ocean_col * ocean_score + land * (1.0 - ocean_score)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    src = Image.open(SRC)
    out = bake(src)
    OUT_TEX.parent.mkdir(parents=True, exist_ok=True)
    OUT_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    out.save(OUT_TEX, quality=92, optimize=True)
    out.save(OUT_ASSET, quality=92, optimize=True)
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
