"""Parking lots and paved yards round the stores in town, traced on the 2015 aerial photos.

Round each store (and any big building in town) the photo is read for pavement: grey or
pale, not green, not a roof, not the road. What's left, joined up and tidied (small bits
and thin strips dropped, gaps closed), is a lot: its outline, and its color off the photo
(asphalt or concrete). The game drapes each over the ground (scripts/world/lots.gd).

    python tools/bake_lots.py [--route=<id>]      (after bake_lidar.py; bake_aerial.py's photos)
    python tools/bake_lots.py --route=<id> --sheet out.png   # and a picture of them to check

Writes the route's lots.json and leaves out the trees standing on a lot.
"""

from __future__ import annotations

import json
import math
import sys

import numpy as np
import shapely
from rasterio import features
from rasterio.transform import Affine
from scipy import ndimage

import config
from aerial import Aerial
from bake_driveways import gravel_score
from bake_lidar import footprint

CELL_M = 1.0
REACH_M = 45.0          # a lot is within this of its building
MIN_LOT_M2 = 150.0      # smaller paved bits are left out
MIN_WIDTH_M = 6.0       # as are strips narrower than this (sidewalks, a drive)
PAVED = 0.4             # gravel_score over this is pavement
ROAD_CLEAR_M = 1.0      # a lot stops this short of a road's or street's edge
BIG_M2 = 400.0          # a building in town this big has a yard too (a shop, the school, the co-op)
ROUND_M = 1.0           # the outline smoothed to this


def lots_near(group: list[dict], imagery: Aerial, o: dict, keep_off, buildings_near: list[dict]) -> list[dict]:
    """Lots round a group of buildings near each other."""
    shapes = shapely.union_all([footprint(b) for b in group])
    x0, z0, x1, z1 = shapes.buffer(REACH_M).bounds
    w, h = int((x1 - x0) / CELL_M), int((z1 - z0) / CELL_M)
    gx = x0 + (np.arange(w) + 0.5) * CELL_M
    gz = z0 + (np.arange(h) + 0.5) * CELL_M
    mx, mz = np.meshgrid(gx, gz)
    rgba = imagery.sample(mx.ravel() + o["easting"], o["northing"] - mz.ravel()).reshape(h, w, 4)
    if (rgba[..., 3] < 127).mean() > 0.3:
        return []
    paved = (gravel_score(rgba[..., :3]) > PAVED) & (rgba[..., 3] > 127)
    near = shapely.contains_xy(shapes.buffer(REACH_M), mx, mz)
    walls = shapely.union_all([footprint(b).buffer(0.5) for b in buildings_near])
    shapely.prepare(walls)
    paved &= near & ~shapely.contains_xy(walls, mx, mz) & ~shapely.contains_xy(keep_off, mx, mz)
    paved = ndimage.binary_closing(paved, np.ones((3, 3)))
    paved = ndimage.binary_opening(paved, np.ones((int(MIN_WIDTH_M / CELL_M),) * 2))
    if not paved.any():
        return []
    transform = Affine(CELL_M, 0, x0, 0, CELL_M, z0)  # (row = z, col = x: game x/z)
    out = []
    for geom, value in features.shapes(paved.astype(np.uint8), mask=paved, transform=transform):
        poly = shapely.geometry.shape(geom).buffer(ROUND_M).buffer(-ROUND_M).simplify(0.6)
        poly = poly.difference(keep_off).difference(walls)
        for part in getattr(poly, "geoms", [poly]):
            if part.geom_type != "Polygon" or part.area < MIN_LOT_M2:
                continue
            part = shapely.Polygon(part.exterior)  # (no islands: planters and light poles aren't drawn)
            inside = shapely.contains_xy(part, mx, mz) & paved
            px = rgba[..., :3][inside]
            color = [int(round(c)) for c in np.median(px, axis=0)] if len(px) else [120, 120, 118]
            out.append({"outline": [round(float(v), 1) for xy in np.asarray(part.exterior.coords)[:-1] for v in xy],
                        "color": color, "area": round(part.area)})
    return out


def main() -> None:
    config.use_args(sys.argv)
    out_dir = config.OUT_DIR
    route = json.loads((out_dir / "route.json").read_text())
    o = route["origin"]
    places = json.loads((out_dir / "places.json").read_text())
    towns = shapely.union_all([shapely.Polygon(np.reshape(t["outline"], (-1, 2))) for t in places.get("towns", [])])
    shapely.prepare(towns)
    pts = np.array(route["points"]).reshape(-1, 3)
    streets = json.loads((out_dir / "streets.json").read_text())["streets"]
    keep_off = shapely.union_all(
        [shapely.LineString(pts[:, [0, 2]]).buffer(9.0)]
        + [shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]).buffer(s["half_width"] + ROAD_CLEAR_M)
           for s in streets if len(s["points"]) >= 10])
    shapely.prepare(keep_off)
    landmarks = json.loads((out_dir / "landmarks.json").read_text()).get("landmarks", []) \
        if (out_dir / "landmarks.json").exists() else []
    for lm in landmarks:  # (a landmark has its own ground)
        for c in lm.get("clear", []):
            box = shapely.box(c[0], c[1], c[2], c[3]) if len(c) == 4 else shapely.Point(c[0], c[1]).buffer(max(c[2], c[3]))
            keep_off = keep_off.union(box)
    shapely.prepare(keep_off)
    buildings = json.loads((out_dir / "structures.json").read_text())["buildings"]
    index = shapely.STRtree([footprint(b) for b in buildings])
    seeds = [b for b in buildings if (b["kind"] == "store" or b["length"] * b["width"] >= BIG_M2)
             and towns.contains(shapely.Point(b["x"], b["z"]))]
    imagery = Aerial.for_quads(config.AERIAL_QUADS)
    # Stores next to each other share their lots: grouped, a block of town at a time.
    groups: dict[tuple[int, int], list[dict]] = {}
    for b in seeds:
        groups.setdefault((math.floor(b["x"] / 150.0), math.floor(b["z"] / 150.0)), []).append(b)
    lots = []
    for n, group in enumerate(groups.values()):
        area = shapely.union_all([footprint(b) for b in group]).buffer(REACH_M + 10.0)
        near = [buildings[j] for j in index.query(area)]
        lots += lots_near(group, imagery, o, keep_off, near)
    # Lots found from two groups overlap: merged.
    merged = shapely.union_all([shapely.Polygon(np.reshape(l["outline"], (-1, 2))) for l in lots]) if lots else None
    final = []
    for part in getattr(merged, "geoms", [merged]) if merged is not None else []:
        if part.geom_type != "Polygon" or part.area < MIN_LOT_M2:
            continue
        part = shapely.Polygon(part.exterior).simplify(0.6)
        same = [l for l in lots if shapely.Polygon(np.reshape(l["outline"], (-1, 2))).intersects(part)]
        color = [int(np.median([l["color"][k] for l in same])) for k in range(3)] if same else [120, 120, 118]
        final.append({"outline": [round(float(v), 1) for xy in np.asarray(part.exterior.coords)[:-1] for v in xy],
                      "color": color})
    (out_dir / "lots.json").write_text(json.dumps({
        "source": "2015 USGS US Topo aerial photos (NAIP), tools/bake_lots.py",
        "note": "outline: x, z, ... (game meters, counterclockwise or not); color: the photo's, 0-255",
        "lots": final,
    }, separators=(",", ":")))
    clear_trees(final, out_dir)
    print(f"lots: {len(final)} round {len(seeds)} buildings, {sum(shapely.Polygon(np.reshape(l['outline'], (-1, 2))).area for l in final) / 10000:.1f} ha")
    if "--sheet" in sys.argv:
        sheet(imagery, final, o, sys.argv[sys.argv.index("--sheet") + 1])


def clear_trees(lots: list[dict], out_dir) -> None:
    if not lots:
        return
    area = shapely.union_all([shapely.Polygon(np.reshape(l["outline"], (-1, 2))) for l in lots])
    shapely.prepare(area)
    path = out_dir / "trees.bin"
    trees = np.fromfile(path, dtype="<f4").reshape(-1, 5)
    on = shapely.contains_xy(area, trees[:, 0], trees[:, 1])
    trees[~on].astype("<f4").tofile(path)
    print(f"trees on the lots: {int(on.sum())} left out")


def sheet(imagery: Aerial, lots: list[dict], o: dict, out: str, count: int = 24) -> None:
    from PIL import Image, ImageDraw
    cell, cols = 220, 6
    picks = sorted(lots, key=lambda l: -len(l["outline"]))[:count]
    img_all = Image.new("RGB", (cols * cell, math.ceil(len(picks) / cols) * cell), (40, 40, 40))
    for k, l in enumerate(picks):
        p = np.reshape(l["outline"], (-1, 2))
        cx, cz = p.mean(axis=0)
        half = max(np.ptp(p[:, 0]), np.ptp(p[:, 1])) / 2 + 25
        img = Image.fromarray(imagery.render(cx + o["easting"] - half, o["northing"] - cz - half,
                                             cx + o["easting"] + half, o["northing"] - cz + half, 2 * half / cell))
        d = ImageDraw.Draw(img)
        to_px = lambda x, z: ((x - (cx - half)) / (2 * half) * cell, (z - (cz - half)) / (2 * half) * cell)
        d.polygon([to_px(x, z) for x, z in p], outline=(255, 0, 255))
        d.rectangle([0, 0, 20, 20], fill=tuple(l["color"]))
        img_all.paste(img, ((k % cols) * cell, (k // cols) * cell))
    img_all.save(out)
    print(f"sheet: {out}")


if __name__ == "__main__":
    main()
