"""Find the real buildings and trees along the route in the USGS lidar.

    python tools/bake_lidar.py      (after bake_route.py)

Writes game/data/route/structures.json (one footprint, height and kind per building),
trees.bin, and yard_dist.bin (meters from the nearest building at every terrain tile
vertex, so the game keeps corn out of farmyards). `--yards` redoes only the last from
structures.json. The point clouds come from the 2019 eastern Iowa flight (leaf-off, in
spring), read from the public Entwine copy on AWS and cached in tools/.cache/ept/. The
first run downloads ~1.5 GB; re-runs are offline.

The points are only sorted into ground and "unclassified", so the rest is done here:
  - Height above ground comes from a ground grid made of the ground points.
  - A roof sends a laser pulse back once; a bare tree in spring sends back several
    (twigs, branches, ground), so cells of mostly single returns, smooth on top, are
    roof, and the rest of what stands 3 m+ off the ground is tree. Evergreens return
    single pulses too, but they're rough on top, and their trees are marked conifer.
  - Thin lines (power lines, fences) are opened away, and anything sitting on a road
    (bridges, overpasses, signs) is dropped.
"""

from __future__ import annotations

import json
import math
import time

import numpy as np
import shapely
from scipy import ndimage
from scipy.spatial import cKDTree

import config
from bake_route import project_roads
from lidar import EptReader
from sources import read_roads

MIN_HEIGHT_M = 2.0       # lower than this above the ground is crops, cars, fences
TREE_MIN_HEIGHT_M = 3.0
ROOF_SINGLE_SHARE = 0.75  # share of single-return points in a roof cell's neighborhood
ROOF_ROUGHNESS_M = 0.9    # a roof's cells vary less than this in height (3x3)
MIN_BUILDING_M2 = 25.0
MAX_BUILDING_M2 = 8000.0
MIN_FILL = 0.4            # cells over minimum rectangle; less is probably trees
ROAD_CLEAR_M = 14.0       # nothing kept this close to IA 1's centerline...
OTHER_ROAD_CLEAR_M = 6.0  # ...or another road's
TREE_BLOCK_M = 8.0        # one tree per block of tree cells (bigger blocks: fewer, bigger trees)
TREE_MIN_COVER = 0.3      # share of a block that's canopy for a tree to stand there
CONIFER_SINGLE_SHARE = 0.6
BIN_ROUND_SHARE = 0.71


def ground_grid(x, y, z, is_ground, west, north, size, cell):
    """Lowest ground point per cell over a size x size box, holes filled from the nearest."""
    n = int(round(size / cell))
    i = np.clip(((x - west) / cell).astype(int), 0, n - 1)
    j = np.clip(((north - y) / cell).astype(int), 0, n - 1)
    grid = np.full((n, n), np.inf)
    np.minimum.at(grid, (j[is_ground], i[is_ground]), z[is_ground])
    hole = ~np.isfinite(grid)
    if hole.all():
        return None
    if hole.any():
        idx = ndimage.distance_transform_edt(hole, return_distances=False, return_indices=True)
        grid = grid[tuple(idx)]
    return grid


def cell_rasters(x, y, hag, single, west, north, size, cell):
    """Per cell, for points standing MIN_HEIGHT_M+ off the ground: count, single-return
    count and the highest point above ground."""
    n = int(round(size / cell))
    i = np.clip(((x - west) / cell).astype(int), 0, n - 1)
    j = np.clip(((north - y) / cell).astype(int), 0, n - 1)
    up = hag >= MIN_HEIGHT_M
    count = np.zeros((n, n), np.float32)
    singles = np.zeros((n, n), np.float32)
    top = np.zeros((n, n), np.float32)
    np.add.at(count, (j[up], i[up]), 1)
    np.add.at(singles, (j[up & single], i[up & single]), 1)
    np.maximum.at(top, (j[up], i[up]), hag[up])
    return count, singles, top


def classify_cells(count, singles, top):
    """Roof and tree masks, and the single-return share (for telling conifers apart)."""
    around = ndimage.uniform_filter(count, 3)
    share = ndimage.uniform_filter(singles, 3) / np.maximum(around, 1e-6)
    has = (top > 0).astype(np.float32)
    k = np.maximum(ndimage.uniform_filter(has, 3), 1e-6)
    mean = ndimage.uniform_filter(top, 3) / k
    rough = np.sqrt(np.maximum(ndimage.uniform_filter(top * top, 3) / k - mean * mean, 0))
    standing = around > 0.3
    roof = standing & (share >= ROOF_SINGLE_SHARE) & (rough < ROOF_ROUGHNESS_M) & (top >= MIN_HEIGHT_M + 0.5)
    roof = ndimage.binary_opening(roof, np.ones((2, 2)))
    tree = standing & ~roof & (top >= TREE_MIN_HEIGHT_M)
    tree = ndimage.binary_opening(tree, np.ones((3, 3)))  # power lines and fences are thinner
    return roof, tree, share


def building_kind(length, width, height, fill, round_share=0.0):
    """What a footprint most likely is (sets the model and colors in the game).
    `round_share` is its area over its smallest enclosing circle's: a (rasterized)
    circle scores ~0.75, a square 0.64."""
    area = length * width
    # Round, or small, square and tall (a bin or silo: houses that narrow aren't that tall).
    if length < 1.15 * width and 4.0 <= length <= 25.0 and height >= 4.0 \
            and (round_share >= BIN_ROUND_SHARE or (length <= 11.0 and height >= 0.9 * length)):
        return "bin"
    if area < 60.0:
        return "shed"
    if height >= 9.0 and area <= 900.0:
        return "barn"
    if area <= 320.0 and height <= 10.0:
        return "house"
    return "shed"  # machine sheds, hog buildings, shops


def buildings_from_mask(roof, top, west, north, cell):
    """One oriented box per connected patch of roof: center (east, north), length (the
    long side), width, yaw of the long side (radians counterclockwise from east), height."""
    labels, n = ndimage.label(roof, np.ones((3, 3)))
    out = []
    for k, sl in enumerate(ndimage.find_objects(labels), start=1):
        if sl is None:
            continue
        rows, cols = np.nonzero(labels[sl] == k)
        area = len(rows) * cell * cell
        if area < MIN_BUILDING_M2 or area > MAX_BUILDING_M2:
            continue
        e = west + (cols + sl[1].start + 0.5) * cell
        nn = north - (rows + sl[0].start + 0.5) * cell
        corners = np.concatenate([np.column_stack([e + dx, nn + dy])
                                  for dx in (-cell / 2, cell / 2) for dy in (-cell / 2, cell / 2)])
        cloud = shapely.MultiPoint(corners)
        rect = cloud.minimum_rotated_rectangle
        round_share = area / (math.pi * shapely.minimum_bounding_radius(cloud) ** 2)
        ring = np.asarray(rect.exterior.coords)[:4]
        sides = ring[1:] - ring[:-1]
        lengths = np.hypot(sides[:, 0], sides[:, 1])
        long_i = int(np.argmax(lengths[:2]))
        length, width = float(lengths[long_i]), float(lengths[1 - long_i])
        if width < 2.0:
            continue
        fill = area / (length * width)
        if fill < MIN_FILL:
            continue
        heights = top[sl][rows, cols]
        height = float(np.percentile(heights, 90))
        yaw = math.atan2(sides[long_i, 1], sides[long_i, 0])
        center = ring.mean(axis=0)
        out.append({"e": float(center[0]), "n": float(center[1]), "length": length, "width": width,
                    "yaw": yaw, "height": height, "fill": fill,
                    "kind": building_kind(length, width, height, fill, round_share)})
    return out


def trees_from_mask(tree, top, share, west, north, cell, block=TREE_BLOCK_M):
    """One tree per block of mostly-canopy cells: (east, north, height, crown radius,
    conifer 0/1), placed at the middle of the canopy in the block."""
    b = int(round(block / cell))
    n = tree.shape[0] // b * b
    t = tree[:n, :n].reshape(n // b, b, n // b, b)
    cover = t.mean(axis=(1, 3))
    out = []
    for bj, bi in zip(*np.nonzero(cover >= TREE_MIN_COVER)):
        r0, c0 = bj * b, bi * b
        rows, cols = np.nonzero(tree[r0:r0 + b, c0:c0 + b])
        h = top[r0 + rows, c0 + cols]
        e = west + (c0 + cols.mean() + 0.5) * cell
        nn = north - (r0 + rows.mean() + 0.5) * cell
        conifer = float(share[r0 + rows, c0 + cols].mean()) >= CONIFER_SINGLE_SHARE
        radius = block * 0.5 * math.sqrt(cover[bj, bi]) + 0.8
        out.append((e, nn, float(np.percentile(h, 90)), radius, 1.0 if conifer else 0.0))
    return out


def corridor_tiles(route_xy, half_width, tile):
    tree = cKDTree(route_xy)
    reach = half_width + tile * math.sqrt(0.5)
    xs = np.arange(math.floor((route_xy[:, 0].min() - reach) / tile), math.ceil((route_xy[:, 0].max() + reach) / tile))
    ys = np.arange(math.floor((route_xy[:, 1].min() - reach) / tile), math.ceil((route_xy[:, 1].max() + reach) / tile))
    cands = np.array([(a, b) for a in xs for b in ys])
    d, near = tree.query((cands + 0.5) * tile)
    keep = d <= reach
    return cands[keep][np.argsort(near[keep])]


def footprint(b: dict, east_north: bool = False) -> shapely.Polygon:
    """A building's footprint as a polygon, in game x/z (or UTM east/north)."""
    c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
    hl, hw = b["length"] / 2, b["width"] / 2
    # yaw is counterclockwise from east looking down, i.e. in east/north; game z = -north.
    pts = [(dx * c - dy * s, dx * s + dy * c) for dx, dy in ((-hl, -hw), (hl, -hw), (hl, hw), (-hl, hw))]
    if east_north:
        return shapely.Polygon([(b["e"] + u, b["n"] + v) for u, v in pts])
    return shapely.Polygon([(b["x"] + u, b["z"] - v) for u, v in pts])


def yard_distances(route: dict, structures: list[dict]) -> np.ndarray:
    """Meters (0-255) from each terrain tile vertex to the nearest building footprint, in
    the order and layout of terrain.bin."""
    t = route["terrain"]
    size, grid = t["tile_size_m"], t["grid"]
    step = size / (grid - 1)
    out = np.full((len(t["tiles"]), grid, grid), 255, dtype=np.uint8)
    if not structures:
        return out
    shapes = [footprint(b) for b in structures]
    index = shapely.STRtree(shapes)
    local = np.arange(grid) * step
    lx, lz = np.meshgrid(local, local)  # row = z, col = x
    for k, (a, b, _) in enumerate(t["tiles"]):
        pts = shapely.points(a * size + lx.ravel(), b * size + lz.ravel())
        nearest = index.query_nearest(pts, max_distance=255.0, return_distance=True, all_matches=False)
        (src, _), dist = nearest
        d = np.full(len(pts), 255.0)
        d[src] = dist
        out[k] = np.clip(np.round(d), 0, 255).reshape(grid, grid)
    return out


def landmark_footprints() -> list[dict]:
    """The hand-built landmarks' rectangles (game/data/route/landmarks.json), as buildings:
    the corn and the fences keep their distance from them too."""
    path = config.OUT_DIR / "landmarks.json"
    if not path.exists():
        return []
    out = []
    for lm in json.loads(path.read_text())["landmarks"]:
        for x0, z0, x1, z1 in lm["clear"]:
            out.append({"x": (x0 + x1) / 2, "z": (z0 + z1) / 2, "length": x1 - x0, "width": z1 - z0,
                        "yaw": 0.0, "height": 6.0, "kind": "landmark"})
    return out


def write_yards(route: dict, structures: list[dict]) -> None:
    yards = yard_distances(route, structures + landmark_footprints())
    yards.tofile(config.OUT_DIR / "yard_dist.bin")
    print(f"yards: {(yards < 30).sum()} terrain vertices within 30 m of a building")


def main():
    import sys
    out_dir = config.OUT_DIR
    if "--reclassify" in sys.argv:  # new kind rules, same footprints
        path = out_dir / "structures.json"
        data = json.loads(path.read_text())
        for b in data["buildings"]:
            if b["kind"] != "bin":  # (round ones already found stay bins)
                b["kind"] = building_kind(b["length"], b["width"], b["height"], 1.0)
        path.write_text(json.dumps(data, separators=(",", ":")))
        kinds = {k: sum(1 for b in data["buildings"] if b["kind"] == k) for k in ("house", "barn", "shed", "bin")}
        print(f"buildings: {len(data['buildings'])} {kinds}")
        return
    if "--yards" in sys.argv:
        route = json.loads((out_dir / "route.json").read_text())
        write_yards(route, json.loads((out_dir / "structures.json").read_text())["buildings"])
        return
    route = json.loads((out_dir / "route.json").read_text())
    o = route["origin"]
    pts = np.array(route["points"]).reshape(-1, 3)
    route_xy = np.column_stack([pts[:, 0] + o["easting"], o["northing"] - pts[:, 2]])
    route_tree = cKDTree(route_xy)
    roads = read_roads(config.ROAD_BBOX)
    project_roads(roads)
    other = shapely.MultiLineString([ln for r in roads for ln in r.lines if config.ROUTE_STATE not in r.state_routes])
    other_area = shapely.prepared.prep(other.buffer(OTHER_ROAD_CLEAR_M))

    reader = EptReader()
    tile, margin, cell = config.LIDAR_TILE_M, config.LIDAR_MARGIN_M, config.LIDAR_CELL_M
    tiles = corridor_tiles(route_xy, config.LIDAR_HALF_WIDTH_M, tile)
    buildings, trees = [], []
    t0 = time.time()
    for done, (a, b) in enumerate(tiles):
        west, south = a * tile - margin, b * tile - margin
        size = tile + 2 * margin
        north = south + size
        p = reader.read(west, south, west + size, north, config.LIDAR_DEPTH)
        p = p.take((p.classification != 7) & (p.classification != 18))
        if len(p) == 0:
            continue
        g = config.LIDAR_GROUND_CELL_M
        ground = ground_grid(p.x, p.y, p.z, p.classification == 2, west, north, size, g)
        if ground is None:
            continue
        n = ground.shape[0]
        gi = np.clip(((p.x - west) / g).astype(int), 0, n - 1)
        gj = np.clip(((north - p.y) / g).astype(int), 0, n - 1)
        hag = np.where(p.classification == 1, p.z - ground[gj, gi], 0.0)
        single = p.number_of_returns == 1
        count, singles, top = cell_rasters(p.x, p.y, hag, single, west, north, size, cell)
        roof, tree, share = classify_cells(count, singles, top)

        def core(e, nn):
            return a * tile <= e < (a + 1) * tile and b * tile <= nn < (b + 1) * tile

        for bl in buildings_from_mask(roof, top, west, north, cell):
            if not core(bl["e"], bl["n"]):
                continue
            d, _ = route_tree.query([bl["e"], bl["n"]])
            reach = math.hypot(bl["length"], bl["width"]) / 2
            if d - reach < ROAD_CLEAR_M or d > config.LIDAR_HALF_WIDTH_M + reach:
                continue
            if other_area.contains(shapely.Point(bl["e"], bl["n"])):
                continue
            buildings.append(bl)
        for tr in trees_from_mask(tree, top, share, west, north, cell):
            if not core(tr[0], tr[1]):
                continue
            d, _ = route_tree.query(tr[:2])
            if d - tr[3] < ROAD_CLEAR_M - 4.0 or d > config.LIDAR_HALF_WIDTH_M:
                continue
            if other_area.contains(shapely.Point(tr[0], tr[1])):
                continue
            trees.append(tr)
        if done % 10 == 0 or done == len(tiles) - 1:
            print(f"tile {done + 1}/{len(tiles)}: {len(buildings)} buildings, {len(trees)} trees, {time.time() - t0:.0f} s")

    # Game coordinates: x = east, z = south of the origin.
    structures = [{
        "x": round(bl["e"] - o["easting"], 2), "z": round(o["northing"] - bl["n"], 2),
        "length": round(bl["length"], 2), "width": round(bl["width"], 2),
        "yaw": round(bl["yaw"], 4), "height": round(bl["height"], 2), "kind": bl["kind"],
    } for bl in buildings]
    (out_dir / "structures.json").write_text(json.dumps({
        "source": "USGS 3DEP lidar, IA Eastern 2019 (public domain), via the usgs-lidar-public Entwine copy",
        "note": "yaw: long side (length) counterclockwise from east, radians; x east, z south (game meters)",
        "buildings": structures,
    }, separators=(",", ":")))
    arr = np.array([(e - o["easting"], o["northing"] - nn, h, r, c) for e, nn, h, r, c in trees], dtype="<f4")
    arr.tofile(out_dir / "trees.bin")
    write_yards(route, structures)
    kinds = {k: sum(1 for s in structures if s["kind"] == k) for k in ("house", "barn", "shed", "bin")}
    print(f"buildings: {len(structures)} {kinds}")
    print(f"trees: {len(trees)}, {int(arr[:, 4].sum()) if len(arr) else 0} conifers")


if __name__ == "__main__":
    main()
