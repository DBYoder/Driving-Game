"""Roof colors for the baked buildings, from the 2015 aerial photos (tools/aerial.py).

Each building in the route's structures.json gets "roof_color": the median color of the
photo inside its footprint (a meter in from the edges, where the lidar and the photo
don't quite agree), leaving out what looks like leaves over it. A building the photos
don't cover, or that's mostly hidden under trees, gets none (the game picks one).
Run it after bake_lidar.py (which writes the footprints anew):

    python tools/bake_aerial.py --route=highway22
    python tools/bake_aerial.py --route=highway22 --sheet out.png   # and a contact sheet to check it
"""

from __future__ import annotations

import json
import math
import sys

import numpy as np

import config
from aerial import Aerial

INSET_M = 1.0          # sampled this far in from the footprint's edges
STEP_M = 0.75          # one sample every this far (the photo's pixels are 1.5 m)
MIN_SHARE = 0.35       # of the samples left once leaves and shadow are taken out, or no color
MIN_SAMPLES = 6


def samples(b: dict, o: dict) -> tuple[np.ndarray, np.ndarray]:
    """UTM (east, north) points over the building's roof, INSET_M in from its edges."""
    hl = max(b["length"] / 2 - INSET_M, 0.5)
    hw = max(b["width"] / 2 - INSET_M, 0.5)
    u = np.arange(-hl, hl + 1e-6, STEP_M)
    v = np.arange(-hw, hw + 1e-6, STEP_M)
    uu, vv = np.meshgrid(u - (u.mean()), v - (v.mean()))
    c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
    de = uu * c - vv * s
    dn = uu * s + vv * c
    return (b["x"] + o["easting"] + de).ravel(), (o["northing"] - b["z"] + dn).ravel()


def leafy(px: np.ndarray) -> np.ndarray:
    """Pixels (N x 3, 0-255) that look like leaves or grass: green over red and blue."""
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    return (2 * g - r - b > 18) & (g > b)


def roof_color(px: np.ndarray) -> list[int] | None:
    """The roof's color from its pixels (RGBA, N x 4), or None if too few are roof."""
    px = px[px[:, 3] > 127, :3]
    if len(px) < MIN_SAMPLES:
        return None
    total = len(px)
    lum = px @ np.array([0.299, 0.587, 0.114])
    keep = ~leafy(px) & (lum > 18)  # (deep shadow says nothing about the color)
    if keep.sum() < max(MIN_SAMPLES, MIN_SHARE * total):
        return None
    px = px[keep]
    lum = lum[keep]
    # The lit half of a gable: the shaded side reads darker than the roof is.
    bright = px[lum >= np.median(lum)]
    return [int(round(c)) for c in np.median(bright, axis=0)]


def main() -> None:
    config.use_args(sys.argv)
    path = config.OUT_DIR / "structures.json"
    route = json.loads((config.OUT_DIR / "route.json").read_text())
    o = route["origin"]
    data = json.loads(path.read_text())
    imagery = Aerial.for_quads(config.AERIAL_QUADS)
    done = 0
    for b in data["buildings"]:
        e, n = samples(b, o)
        color = roof_color(imagery.sample(e, n))
        if color is None:
            b.pop("roof_color", None)
        else:
            b["roof_color"] = color
            done += 1
    path.write_text(json.dumps(data, separators=(",", ":")))
    print(f"roof colors: {done}/{len(data['buildings'])} buildings")
    if "--sheet" in sys.argv:
        contact_sheet(imagery, data["buildings"], o, sys.argv[sys.argv.index("--sheet") + 1])


def contact_sheet(imagery: Aerial, buildings: list[dict], o: dict, out: str, count: int = 48) -> None:
    """A grid of photo crops of the biggest buildings, each with its color as a swatch."""
    from PIL import Image, ImageDraw
    cell = 160
    picks = sorted(buildings, key=lambda b: -b["length"] * b["width"])[:count]
    cols = 8
    sheet = Image.new("RGB", (cols * cell, math.ceil(len(picks) / cols) * cell), (40, 40, 40))
    for k, b in enumerate(picks):
        e, n = b["x"] + o["easting"], o["northing"] - b["z"]
        half = max(b["length"], b["width"]) * 0.8 + 5
        img = Image.fromarray(imagery.render(e - half, n - half, e + half, n + half, 2 * half / cell))
        d = ImageDraw.Draw(img)
        c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
        pts = []
        for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1), (-1, -1)):
            de = du * b["length"] / 2 * c - dv * b["width"] / 2 * s
            dn = du * b["length"] / 2 * s + dv * b["width"] / 2 * c
            pts.append(((de + half) / (2 * half) * cell, (half - dn) / (2 * half) * cell))
        d.line(pts, fill=(255, 0, 255), width=1)
        if "roof_color" in b:
            d.rectangle([0, 0, 24, 24], fill=tuple(b["roof_color"]), outline=(255, 255, 255))
        d.text((28, 4), b["kind"], fill=(255, 255, 0))
        sheet.paste(img, ((k % cols) * cell, (k // cols) * cell))
    sheet.save(out)
    print(f"contact sheet: {out}")


if __name__ == "__main__":
    main()
