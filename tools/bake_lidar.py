"""Find the real buildings and trees along the route in the USGS lidar.

    python tools/bake_lidar.py [--route=<id>]      (after bake_route.py and bake_places.py)

Writes game/data/routes/<id>/structures.json (one footprint, height and kind per building),
trees.bin, and yard_dist.bin (meters from the nearest building at every terrain tile
vertex, so the game keeps corn out of farmyards; 0 everywhere in town, from places.json).
`--yards` redoes only the last from structures.json. `--extend OLD_ROUTE.json` re-bakes
only the tiles near road added past the end of an older route.json and swaps them in.
The point clouds come from the 2019 eastern Iowa flight (leaf-off, in spring), read
from the public Entwine copy on AWS and cached in tools/.cache/ept/. The
first run downloads ~1.5 GB; re-runs are offline.

The points are only sorted into ground and "unclassified", so the rest is done here:
  - Height above ground comes from a ground grid made of the ground points.
  - A roof sends a laser pulse back once; a bare tree in spring sends back several
    (twigs, branches, ground), so cells of mostly single returns, smooth on top, are
    roof, and the rest of what stands 3 m+ off the ground is tree. Evergreens return
    single pulses too, but they're rough on top, and their trees are marked conifer.
  - Thin lines (power lines, fences) are opened away, and anything sitting on a road
    (bridges, overpasses, signs) is dropped.
  - A patch of roof that fills its rectangle poorly (an L-shaped house, a row of hog
    barns joined at the ends, a farmstead's roofs run together) is cut into the
    rectangles that make it up, biggest first (not a round bin, or a co-op's bins and
    elevator, standing taller than any barn).
  - Each building's roof is read off its points: the ridge height, the eave height (from
    the slope of the roof), and its shape: a gable (the ridge along the length, which is
    set to be the ridge's direction), one slope (a lean-to, or half a gable the cutting
    parted from its other half: "high" says which side's up), or flat.
  - Then it's tidied (tidy()): no buildings on the town streets or in a landmark, none
    mostly inside another, and the trees are moved out of the buildings (a lidar tree is
    where its crown is, so one over a roof stood in the house) or left out.
"""

from __future__ import annotations

import json
import math
import time
from pathlib import Path

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
ROAD_CLEAR_M = 14.0       # nothing kept this close to the route's centerline...
OTHER_ROAD_CLEAR_M = 6.0  # ...or another road's
TREE_BLOCK_M = 8.0        # one tree per block of tree cells (bigger blocks: fewer, bigger trees)
TREE_MIN_COVER = 0.3      # share of a block that's canopy for a tree to stand there
CONIFER_SINGLE_SHARE = 0.6
BIN_ROUND_SHARE = 0.71
SPLIT_FILL = 0.8          # a roof patch filling less of its rectangle than this is cut up...
SPLIT_MIN_M2 = 150.0      # ...if it's this big
SPLIT_MAX_PIECES = 12
SPLIT_MAX_HEIGHT_M = 14.0  # ...but not a co-op's bins and elevators (as tall as no barn is)
FLAT_PITCH = 0.1          # rise per run: flatter than this (6 degrees) is a flat roof
MIN_EAVE_M = 2.4
OVERLAP_DROP = 0.2        # a building this much inside a bigger one is part of it (or a misread): left out
STREET_CLEAR_M = 1.0      # buildings and tree trunks keep this far off a street's edge...
STREET_SHIFT_M = 4.0      # ...a building moved up to this far to (the lidar's edges are a meter or two out)
TRUNK_CLEAR_M = 0.6       # a trunk this far outside a footprint at least
YARD_LIGHT_CLEAR_M = 2.0  # a yard light's pole this far from any building or street at least
CROWN_OVERLAP = 0.25      # a crown low enough to hit the walls reaches this share of its radius over the roof at most


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


def largest_rectangle(grid: np.ndarray) -> tuple[int, int, int, int, int]:
    """The biggest all-True axis-aligned rectangle in a boolean grid: (area, row0, col0,
    row1, col1), row1/col1 exclusive (the histogram-and-stack method, one pass a row)."""
    rows, cols = grid.shape
    heights = np.zeros(cols + 1, int)
    best = (0, 0, 0, 0, 0)
    for r in range(rows):
        heights[:cols] = np.where(grid[r], heights[:cols] + 1, 0)
        stack: list[int] = []
        for c in range(cols + 1):
            while stack and heights[stack[-1]] >= heights[c]:
                h = heights[stack.pop()]
                left = stack[-1] + 1 if stack else 0
                area = h * (c - left)
                if area > best[0]:
                    best = (area, r - h + 1, left, r + 1, c)
            stack.append(c)
    return best


def split_patch(e: np.ndarray, n: np.ndarray, cell: float, yaw: float) -> list[tuple]:
    """Cut a patch of roof cells (UTM centers) into rectangles in the frame turned by `yaw`,
    biggest first: [(center e, center n, size along yaw, size across, cell mask)]."""
    c, s = math.cos(yaw), math.sin(yaw)
    u = e * c + n * s
    v = -e * s + n * c
    i = np.round((u - u.min()) / cell).astype(int)
    j = np.round((v - v.min()) / cell).astype(int)
    grid = np.zeros((j.max() + 1, i.max() + 1), bool)
    grid[j, i] = True
    # Close one-cell gaps (the rotated cells don't tile the turned grid exactly).
    grid = ndimage.binary_closing(grid, np.ones((2, 2))) | grid
    out = []
    min_cells = MIN_BUILDING_M2 / (cell * cell)
    for _ in range(SPLIT_MAX_PIECES):
        area, r0, c0, r1, c1 = largest_rectangle(grid)
        if area < min_cells or min(r1 - r0, c1 - c0) * cell < 2.0:
            break
        grid[r0:r1, c0:c1] = False
        uc = u.min() + (c0 + c1 - 1) / 2 * cell
        vc = v.min() + (r0 + r1 - 1) / 2 * cell
        mask = (i >= c0) & (i < c1) & (j >= r0) & (j < r1)
        out.append((uc * c - vc * s, uc * s + vc * c, (c1 - c0) * cell, (r1 - r0) * cell, mask))
    return out


def roof_shape(u: np.ndarray, v: np.ndarray, h: np.ndarray, length: float, width: float) -> tuple[float, float, str, int]:
    """A roof read off its cells (u along the length, v across it, h above the ground):
    (ridge height, eave height, how it slopes, which way). It slopes "length" (a gable
    with its ridge along the length), "width" (the ridge across it), "flat", or one way
    only (a lean-to, or half a gable roof cut along its ridge from the other half):
    "lean_v" (across the width) or "lean_u" (along the length), up toward +v or +u if the
    last number is 1, -v or -u if it's -1."""
    ridge = float(np.percentile(h, 95))
    inner = (np.abs(u) <= length / 2 - 0.7) & (np.abs(v) <= width / 2 - 0.7)  # not the gutters
    if inner.sum() >= 8:
        u, v, h = u[inner], v[inner], h[inner]
    if len(h) < 6:
        return ridge, ridge, "flat", 0
    fits = {}
    for axis, d, run in (("length", np.abs(v), width / 2), ("width", np.abs(u), length / 2),
                         ("lean_v", v, width), ("lean_u", u, length)):
        a = np.column_stack([np.ones_like(d), d])
        coef, *_ = np.linalg.lstsq(a, h, rcond=None)
        resid = float(np.sqrt(np.mean((a @ coef - h) ** 2)))
        slope = float(coef[1])
        if axis in ("length", "width"):
            fits[axis] = (resid, -slope, run, 0)  # (down from the ridge)
        else:
            fits[axis] = (resid, abs(slope), run, 1 if slope > 0 else -1)
    # Ridges mostly run the long way: another shape only if it fits clearly better.
    axis = "length"
    for other in ("width", "lean_v", "lean_u"):
        if fits[other][0] < 0.75 * fits[axis][0] and fits[other][1] > FLAT_PITCH:
            axis = other
    _, pitch, run, side = fits[axis]
    if pitch < FLAT_PITCH:
        return ridge, ridge, "flat", 0
    eave = min(max(ridge - min(pitch, 1.6) * run, MIN_EAVE_M), ridge - 0.3)
    return ridge, eave, axis, side


def buildings_from_mask(roof, top, west, north, cell):
    """Oriented boxes for the patches of roof (a patch that fills its rectangle poorly is
    cut into the rectangles that make it up): center (east, north), length (along the
    ridge), width, yaw of the length (radians counterclockwise from east), ridge and eave
    heights, roof ("gable" or "flat")."""
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
        heights = top[sl][rows, cols]
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
        yaw = math.atan2(sides[long_i, 1], sides[long_i, 0])
        center = ring.mean(axis=0)
        tall = float(np.percentile(heights, 90)) >= SPLIT_MAX_HEIGHT_M
        if fill >= SPLIT_FILL or area < SPLIT_MIN_M2 or round_share >= BIN_ROUND_SHARE or tall:
            # (A round bin fills ~79% of its box; a co-op's bins and elevator stand together.)
            if fill < MIN_FILL:
                continue
            pieces = [(center[0], center[1], length, width, np.ones(len(e), bool))]
        else:
            pieces = split_patch(e - center[0], nn - center[1], cell, yaw)
            pieces = [(center[0] + pe, center[1] + pn, pl, pw, m) for pe, pn, pl, pw, m in pieces]
        for pe, pn, plen, pwid, mask in pieces:
            pyaw = yaw
            if pwid > plen:
                plen, pwid, pyaw = pwid, plen, yaw + math.pi / 2
            if pwid < 2.0 or mask.sum() < 4:
                continue
            h = heights[mask]
            c, s = math.cos(pyaw), math.sin(pyaw)
            du, dn = e[mask] - pe, nn[mask] - pn
            u = du * c + dn * s
            v = -du * s + dn * c
            ridge, eave, axis, side = roof_shape(u, v, h, plen, pwid)
            whole = len(pieces) == 1
            kind = building_kind(plen, pwid, float(np.percentile(h, 90)), fill if whole else 1.0,
                                 round_share if whole else 0.0)
            if axis in ("width", "lean_u") and kind != "bin":
                # Turned a quarter: the length along the ridge (or the high edge). The old
                # +u is the new -v.
                plen, pwid, pyaw = pwid, plen, pyaw + math.pi / 2
                side = -side
            roof = {"flat": "flat", "lean_v": "lean", "lean_u": "lean"}.get(axis, "gable")
            b = {"e": float(pe), "n": float(pn), "length": plen, "width": pwid, "yaw": pyaw,
                 "height": ridge, "eave": eave, "roof": roof, "fill": fill if whole else 1.0, "kind": kind}
            if roof == "lean":
                b["high"] = -side  # the high side, game z across the building (+v is -z)
            out.append(b)
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
    """The hand-built landmarks' rectangles (the route's landmarks.json), as buildings:
    the corn and the fences keep their distance from them too."""
    path = config.OUT_DIR / "landmarks.json"
    if not path.exists():
        return []
    out = []
    for lm in json.loads(path.read_text())["landmarks"]:
        for c in lm["clear"]:
            if len(c) == 5:  # [x, z, half_x, half_z, yaw]: turned with the building
                x, z, hx, hz, yaw = c
                out.append({"x": x, "z": z, "length": 2 * hx, "width": 2 * hz,
                            "yaw": yaw, "height": 6.0, "kind": "landmark"})
            else:  # [x0, z0, x1, z1], square to the compass
                x0, z0, x1, z1 = c
                out.append({"x": (x0 + x1) / 2, "z": (z0 + z1) / 2, "length": x1 - x0, "width": z1 - z0,
                            "yaw": 0.0, "height": 6.0, "kind": "landmark"})
    return out


def in_towns(route: dict) -> np.ndarray:
    """Per terrain tile vertex: inside city limits (the route's places.json "towns")."""
    t = route["terrain"]
    size, grid = t["tile_size_m"], t["grid"]
    out = np.zeros((len(t["tiles"]), grid, grid), dtype=bool)
    path = config.OUT_DIR / "places.json"
    towns = json.loads(path.read_text()).get("towns", []) if path.exists() else []
    if not towns:
        return out
    area = shapely.union_all([shapely.Polygon(np.reshape(tw["outline"], (-1, 2))) for tw in towns])
    shapely.prepare(area)
    local = np.arange(grid) * (size / (grid - 1))
    lx, lz = np.meshgrid(local, local)
    for k, (a, b, _) in enumerate(t["tiles"]):
        out[k] = shapely.contains_xy(area, a * size + lx, b * size + lz)
    return out


def along_streams(route: dict) -> np.ndarray:
    """Per terrain tile vertex: within STREAM_YARD_M of a named creek or river (the
    route's places.json "streams"), where the banks are grass and trees, not crops."""
    t = route["terrain"]
    size, grid = t["tile_size_m"], t["grid"]
    out = np.zeros((len(t["tiles"]), grid, grid), dtype=bool)
    path = config.OUT_DIR / "places.json"
    streams = json.loads(path.read_text()).get("streams", []) if path.exists() else []
    if not streams:
        return out
    banks = shapely.union_all([shapely.LineString(np.reshape(s["points"], (-1, 2))) for s in streams]).buffer(
        config.STREAM_YARD_M)
    shapely.prepare(banks)
    local = np.arange(grid) * (size / (grid - 1))
    lx, lz = np.meshgrid(local, local)
    for k, (a, b, _) in enumerate(t["tiles"]):
        out[k] = shapely.contains_xy(banks, a * size + lx, b * size + lz)
    return out


def write_yards(route: dict, structures: list[dict]) -> None:
    yards = yard_distances(route, structures + landmark_footprints())
    yards[in_towns(route)] = 0  # all lawns in town: no crops
    yards[along_streams(route)] = 0  # nor on the creeks' banks

    yards.tofile(config.OUT_DIR / "yard_dist.bin")
    print(f"yards: {(yards < 30).sum()} terrain vertices within 30 m of a building")


def bake_tiles(tiles, route_tree, other_area) -> tuple[list[dict], list[tuple]]:
    """Buildings and trees (UTM) in the cores of these lidar tiles, kept if they're within
    the corridor along the route but clear of it and of the other roads."""
    reader = EptReader()
    tile, margin, cell = config.LIDAR_TILE_M, config.LIDAR_MARGIN_M, config.LIDAR_CELL_M
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
    return buildings, trees


def main():
    import sys
    config.use_args(sys.argv)
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
    if "--tidy" in sys.argv:  # the tidying alone, over what's baked
        route = json.loads((out_dir / "route.json").read_text())
        pts = np.array(route["points"]).reshape(-1, 3)
        data = json.loads((out_dir / "structures.json").read_text())
        trees = np.fromfile(out_dir / "trees.bin", dtype="<f4").reshape(-1, 5)
        structures, trees = tidy(data["buildings"], trees, out_dir, pts[:, [0, 2]])
        write_structures(out_dir, structures, trees, route)
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
    tile = config.LIDAR_TILE_M
    if "--extend" in sys.argv:
        # The route got longer (same origin, same road up to the old end): bake just the
        # tiles near the new road and swap them in, keeping everything else as it was.
        old = json.loads(Path(sys.argv[sys.argv.index("--extend") + 1]).read_text())
        old_n = len(old["points"]) // 3
        tiles = corridor_tiles(route_xy[max(old_n - 1, 0):], config.LIDAR_HALF_WIDTH_M, tile)
        print(f"re-baking {len(tiles)} tiles past the old end")
        fresh_b, fresh_t = bake_tiles(tiles, route_tree, other_area)
        redone = {(int(a), int(b)) for a, b in tiles}

        def in_redone(e, nn):
            return (math.floor(e / tile), math.floor(nn / tile)) in redone

        data = json.loads((out_dir / "structures.json").read_text())
        kept = [s for s in data["buildings"] if not in_redone(s["x"] + o["easting"], o["northing"] - s["z"])]
        old_trees = np.fromfile(out_dir / "trees.bin", dtype="<f4").reshape(-1, 5)
        keep = np.array([not in_redone(x + o["easting"], o["northing"] - z) for x, z in old_trees[:, :2]], dtype=bool)
        print(f"kept {len(kept)}/{len(data['buildings'])} buildings and {keep.sum()}/{len(old_trees)} trees")
        structures = kept + game_structures(fresh_b, o)
        trees = old_trees[keep]
        if fresh_t:
            trees = np.vstack([trees, game_trees(fresh_t, o)])
        structures, trees = tidy(structures, trees, out_dir, pts[:, [0, 2]])
        write_structures(out_dir, structures, trees, route)
        return
    tiles = corridor_tiles(route_xy, config.LIDAR_HALF_WIDTH_M, tile)
    buildings, trees = bake_tiles(tiles, route_tree, other_area)
    structures, trees = tidy(game_structures(buildings, o), game_trees(trees, o), out_dir, pts[:, [0, 2]])
    write_structures(out_dir, structures, trees, route)


def game_structures(buildings: list[dict], o: dict) -> list[dict]:
    """Game coordinates: x = east, z = south of the origin."""
    return [{
        "x": round(bl["e"] - o["easting"], 2), "z": round(o["northing"] - bl["n"], 2),
        "length": round(bl["length"], 2), "width": round(bl["width"], 2),
        "yaw": round(bl["yaw"], 4), "height": round(bl["height"], 2),
        "eave": round(bl.get("eave", bl["height"] * 0.6), 2), "roof": bl.get("roof", "gable"), "kind": bl["kind"],
        **({"high": bl["high"]} if "high" in bl else {}),
    } for bl in buildings]


def street_area(out_dir: Path) -> shapely.Geometry:
    """The town streets and side roads (the route's streets.json, game x/z), each out to
    STREET_CLEAR_M past its edge."""
    path = out_dir / "streets.json"
    if not path.exists():
        return shapely.Polygon()
    parts = []
    for st in json.loads(path.read_text())["streets"]:
        p = np.reshape(st["points"], (-1, 5))
        if len(p) >= 2:
            parts.append(shapely.LineString(p[:, [0, 4]]).buffer(st["half_width"] + STREET_CLEAR_M))
    area = shapely.union_all(parts) if parts else shapely.Polygon()
    shapely.prepare(area)
    return area


def _away(poly: shapely.Geometry, x: float, z: float, need: float) -> tuple[float, float]:
    """(x, z) moved straight away from `poly` until it's `need` m clear of it."""
    p = shapely.Point(x, z)
    edge = poly.exterior
    q = edge.interpolate(edge.project(p))
    dx, dz = x - q.x, z - q.y
    d = math.hypot(dx, dz)
    if d < 1e-6:  # on the edge: out from the middle
        c = poly.centroid
        dx, dz, d = x - c.x, z - c.y, max(math.hypot(x - c.x, z - c.y), 1e-6)
    if poly.contains(p):
        dx, dz = -dx, -dz
    return q.x + dx / d * need, q.y + dz / d * need


def tidy(structures: list[dict], trees: np.ndarray, out_dir: Path, route_xz: np.ndarray) -> tuple[list[dict], np.ndarray]:
    """Buildings and trees that don't run into each other, the streets or the landmarks:
    - buildings on a street are moved off it (up to STREET_SHIFT_M) or left out, and ones in a
      landmark's rectangles are left out (the landmark stands there);
    - a building mostly inside a bigger one (OVERLAP_DROP) is left out;
    - a tree with its trunk in a building, or a crown low enough to hit the walls reaching
      well over the roof, is moved out from it (the lidar puts a tree where its crown is,
      and a crown hangs over a roof from a trunk in the yard); one that can't be is
      shrunk to fit or left out, as are trees on a street or in a landmark."""
    streets = street_area(out_dir)
    landmarks = [footprint(b) for b in landmark_footprints()]
    lm = shapely.union_all(landmarks) if landmarks else shapely.Polygon()
    shapely.prepare(lm)
    route_tree = cKDTree(route_xz)
    counts = {"off street": 0, "street": 0, "landmark": 0, "inside another": 0}
    kept: list[dict] = []
    for b in structures:
        poly = footprint(b)
        if lm.intersects(poly) and lm.intersection(poly).area > 1.0:
            counts["landmark"] += 1
            continue
        if streets.intersects(poly) and streets.intersection(poly).area > 1.0:
            moved = False
            for _ in range(int(STREET_SHIFT_M / 0.5)):  # half a meter at a time, away from it
                c = streets.intersection(poly).centroid
                dx, dz = b["x"] - c.x, b["z"] - c.y
                d = max(math.hypot(dx, dz), 1e-6)
                b = dict(b, x=b["x"] + dx / d * 0.5, z=b["z"] + dz / d * 0.5)
                poly = footprint(b)
                if streets.intersection(poly).area <= 1.0:
                    moved = True
                    break
            if moved and route_tree.query([b["x"], b["z"]])[0] - math.hypot(b["length"], b["width"]) / 2 >= ROAD_CLEAR_M:
                counts["off street"] += 1
            else:
                counts["street"] += 1
                continue
        kept.append(b)
    # Biggest first: a smaller one mostly inside a bigger one goes.
    kept.sort(key=lambda b: -b["length"] * b["width"])
    out: list[dict] = []
    polys: list[shapely.Polygon] = []
    for b in kept:
        poly = footprint(b)
        inside = sum(poly.intersection(q).area for q in polys if q.intersects(poly))
        if inside > OVERLAP_DROP * poly.area:
            counts["inside another"] += 1
            continue
        out.append(b)
        polys.append(poly)
    index = shapely.STRtree(polys)
    eaves = np.array([b.get("eave", b["height"] * 0.6) for b in out])
    moved = shrunk = dropped = 0
    tree_out = []
    for x, z, h, r, conifer in trees.astype(float):
        crown_low = h * (0.1 if conifer > 0.5 else 0.26)
        ok = True
        orig = (x, z)
        for _ in range(4):
            bad = None
            for j in index.query(shapely.Point(x, z).buffer(r)):
                d = polys[j].distance(shapely.Point(x, z))
                inside = polys[j].contains(shapely.Point(x, z))
                need = r * (1.0 - CROWN_OVERLAP) if crown_low < eaves[j] + 0.3 else TRUNK_CLEAR_M
                if inside or d < need:
                    bad = (j, need)
                    break
            if bad is None:
                break
            x, z = _away(polys[bad[0]], x, z, bad[1] + 0.05)
        else:
            ok = False
        p = shapely.Point(x, z)
        if not ok:
            # Shrink the crown to fit where it was, if that leaves a tree.
            x, z = orig
            p = shapely.Point(x, z)
            near = [polys[j].distance(p) for j in index.query(p.buffer(r))]
            room = min(near) if near else r
            if any(polys[j].contains(p) for j in index.query(p)) or room / (1.0 - CROWN_OVERLAP) < 1.5:
                dropped += 1
                continue
            r = min(r, room / (1.0 - CROWN_OVERLAP))
            shrunk += 1
        elif (x, z) != orig:
            moved += 1
        if streets.contains(p) or (not lm.is_empty and lm.distance(p) < r * (1.0 - CROWN_OVERLAP)) \
                or route_tree.query([x, z])[0] - r < ROAD_CLEAR_M - 4.0:
            dropped += 1
            continue
        tree_out.append((x, z, h, r, conifer))
    trees_out = np.array(tree_out, dtype="<f4").reshape(-1, 5)
    lights = place_yard_lights(out, polys, index, trees_out, streets, lm, route_tree)
    print(f"tidy: buildings {counts}; trees moved out of buildings {moved}, shrunk {shrunk}, left out {dropped}; "
          f"yard lights {lights}")
    return out, trees_out


def place_yard_lights(buildings: list[dict], polys: list, index, trees: np.ndarray, streets, lm, route_tree) -> int:
    """Each house's pole light (its "light": [x, z]) somewhere in its yard: off its
    corners or out from its sides, the first spot clear of every building, tree, street
    and landmark (null if there isn't one)."""
    tree_index = cKDTree(trees[:, :2]) if len(trees) else None
    biggest = float(trees[:, 3].max()) if len(trees) else 0.0
    placed = 0
    for b in buildings:
        b.pop("light", None)
        if b["kind"] != "house":
            continue
        b["light"] = None
        c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
        hl, hw = b["length"] / 2, b["width"] / 2
        for a, d in ((hl + 6, hw + 4), (-hl - 6, hw + 4), (hl + 6, -hw - 4), (-hl - 6, -hw - 4),
                     (hl + 8, 0.0), (-hl - 8, 0.0), (0.0, hw + 8), (0.0, -hw - 8)):
            # (a, d) along and across the house as the game turns it (Basis(UP, yaw)).
            x, z = b["x"] + a * c + d * s, b["z"] - a * s + d * c
            p = shapely.Point(x, z)
            if any(polys[j].distance(p) < YARD_LIGHT_CLEAR_M for j in index.query(p.buffer(YARD_LIGHT_CLEAR_M))):
                continue
            if tree_index is not None and any(
                    math.hypot(trees[k, 0] - x, trees[k, 1] - z) < max(trees[k, 3] * 0.8, YARD_LIGHT_CLEAR_M)
                    for k in tree_index.query_ball_point([x, z], biggest)):
                continue
            if streets.distance(p) < YARD_LIGHT_CLEAR_M or (not lm.is_empty and lm.distance(p) < YARD_LIGHT_CLEAR_M) \
                    or route_tree.query([x, z])[0] < ROAD_CLEAR_M:
                continue
            b["light"] = [round(x, 2), round(z, 2)]
            placed += 1
            break
    return placed


def game_trees(trees: list[tuple], o: dict) -> np.ndarray:
    return np.array([(e - o["easting"], o["northing"] - nn, h, r, c) for e, nn, h, r, c in trees], dtype="<f4").reshape(-1, 5)


def write_structures(out_dir, structures: list[dict], arr: np.ndarray, route: dict) -> None:
    (out_dir / "structures.json").write_text(json.dumps({
        "source": "USGS 3DEP lidar, IA Eastern 2019 (public domain), via the usgs-lidar-public Entwine copy",
        "note": "x east, z south (game meters); length runs along the ridge (the long side, mostly), "
                "yaw is its direction counterclockwise from east (radians); height is the ridge's, eave "
                "the eaves' (the same for a flat roof); roof gable, flat or lean (one slope, up to the high "
                "side: +1 or -1 along the building's own z); roof_color the roof's in the "
                "2015 aerial photo (tools/bake_aerial.py), if it was there",
        "buildings": structures,
    }, separators=(",", ":")))
    arr.astype("<f4").tofile(out_dir / "trees.bin")
    write_yards(route, structures)
    kinds = {k: sum(1 for s in structures if s["kind"] == k) for k in ("house", "barn", "shed", "bin")}
    print(f"buildings: {len(structures)} {kinds}")
    print(f"trees: {len(arr)}, {int(arr[:, 4].sum()) if len(arr) else 0} conifers")


if __name__ == "__main__":
    main()
