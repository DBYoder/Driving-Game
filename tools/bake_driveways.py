"""Driveways and farm lanes, traced on the 2015 aerial photos (tools/aerial.py).

The road data has the public roads and only a handful of private lanes, so most farmsteads
along the route stood in the fields with no way in. For each one (a group of buildings,
out of town, with no street already near the house), this finds the way in on the photo:
the cheapest path from the house out to a road, where gravel and concrete (pale and grey)
cost little and grass, crops and trees a lot, and buildings can't be crossed. A path that
mostly runs on gravel is a lane that's really there; one that doesn't (a lane under trees,
or a house newer than the photos) is left out.

    python tools/bake_driveways.py [--route=<id>]      (after bake_lidar.py and bake_aerial.py)
    python tools/bake_driveways.py --route=<id> --sheet out.png   # and a contact sheet to check them

The lanes go into the route's streets.json as kind "lane" (with "driveway": true, so a
re-run replaces them), with their surface heights like every street's, and into
terrain_dist.bin, so the corn keeps off them. Trees and yard lights standing on one are
left out. Re-run it after bake_streets.py (which writes streets.json and terrain_dist.bin
afresh) or bake_lidar.py (trees and lights).
"""

from __future__ import annotations

import json
import math
import sys

import numpy as np
import shapely
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import dijkstra
from scipy.spatial import cKDTree

import config
from aerial import Aerial
from bake_lidar import footprint
from bake_streets import CORN_VERGE_M, IA1_EDGE_M, KINDS, SPACING_M, Ground, surface_heights

CELL_M = 1.0              # the photo's raster for the search (its pixels are 1.5 m)
FARMSTEAD_M = 45.0        # buildings this close together are one farmstead
MAX_LANE_M = 450.0        # no lane longer than this (a house that far off has its own road)
CONNECTED_M = 30.0        # a house with a street this near already has its way in
YARD_RING_M = (3.0, 9.0)  # the lane starts this far out from the house's walls
MIN_GRAVEL = 0.6          # share of the path out of the yard that has to look like a lane...
MAX_OFF_GRAVEL_M = 12.0   # ...with no longer stretch than this through grass or crops
YARD_M = 25.0             # (the yard: this far from the house, where it's all gravel or lawn)
MAX_DETOUR = 4.0          # a lane no longer than this times the straight way to the road
SHOULDER_M = 9.0          # a lane reaching this near IA 1's centerline is at its shoulder
LANE = KINDS["lane"]


def gravel_score(rgb: np.ndarray) -> np.ndarray:
    """0..1 per pixel (H x W x 3, 0-255): how much it looks like gravel, concrete or a dirt
    lane (pale, not green, not much color) rather than grass, crops or trees."""
    rgb = rgb.astype(float)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hi = rgb.max(axis=2)
    lo = rgb.min(axis=2)
    sat = (hi - lo) / np.maximum(hi, 1.0)
    bright = np.clip((hi - 95.0) / 60.0, 0.0, 1.0)
    grey = np.clip((0.32 - sat) / 0.16, 0.0, 1.0)
    green = np.clip((2 * g - r - b - 6.0) / 20.0, 0.0, 1.0)
    return bright * grey * (1.0 - green)


def grid_graph(cost: np.ndarray):
    """A sparse graph over a cost raster: each cell to its 8 neighbours, the step's cost the
    mean of the two cells' times its length."""
    h, w = cost.shape
    idx = np.arange(h * w).reshape(h, w)
    rows, cols, vals = [], [], []
    for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
        a = idx[max(0, -dr):h - max(0, dr), max(0, -dc):w - max(0, dc)]
        b = idx[max(0, dr):h + min(0, dr) or None, max(0, dc):w + min(0, dc) or None]
        ca = cost.ravel()[a.ravel()]
        cb = cost.ravel()[b.ravel()]
        v = (ca + cb) / 2.0 * math.hypot(dr, dc)
        rows += [a.ravel(), b.ravel()]
        cols += [b.ravel(), a.ravel()]
        vals += [v, v]
    return coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(h * w, h * w)).tocsr()


def cheapest_path(cost: np.ndarray, starts: np.ndarray, goals: np.ndarray) -> list[int] | None:
    """Cells (flat indices) of the cheapest path from any of `starts` to any of `goals`
    (boolean rasters), or None."""
    graph = grid_graph(cost)
    src = np.flatnonzero(starts)
    if len(src) == 0 or not goals.any():
        return None
    dist, pred, _ = dijkstra(graph, indices=src, min_only=True, return_predecessors=True)
    goal_cells = np.flatnonzero(goals)
    best = goal_cells[np.argmin(dist[goal_cells])]
    if not np.isfinite(dist[best]):
        return None
    path = [int(best)]
    while pred[path[-1]] >= 0:
        path.append(int(pred[path[-1]]))
    return path[::-1]


def farmsteads(buildings: list[dict], towns) -> list[dict]:
    """One building per farmstead out of town: its house (the biggest), or its biggest
    building if it has none."""
    keep = [b for b in buildings if b["kind"] != "bin" and not towns.contains(shapely.Point(b["x"], b["z"]))]
    if not keep:
        return []
    xz = np.array([[b["x"], b["z"]] for b in keep])
    pairs = cKDTree(xz).query_pairs(FARMSTEAD_M, output_type="ndarray")
    n = len(keep)
    graph = coo_matrix((np.ones(len(pairs)), (pairs[:, 0], pairs[:, 1])), shape=(n, n)) if len(pairs) else coo_matrix((n, n))
    from scipy.sparse.csgraph import connected_components
    _, label = connected_components(graph, directed=False)
    out = []
    for lab in np.unique(label):
        members = [keep[i] for i in np.flatnonzero(label == lab)]
        houses = [b for b in members if b["kind"] == "house"]
        pick = max(houses or members, key=lambda b: b["length"] * b["width"])
        out.append(pick)
    return out


def chaikin(xz: np.ndarray, rounds: int = 2) -> np.ndarray:
    """Corner-cut a polyline smooth (its ends stay put)."""
    for _ in range(rounds):
        q = 0.75 * xz[:-1] + 0.25 * xz[1:]
        r = 0.25 * xz[:-1] + 0.75 * xz[1:]
        mid = np.empty((2 * len(q), 2))
        mid[0::2], mid[1::2] = q, r
        xz = np.vstack([xz[:1], mid[1:-1], xz[-1:]])
    return xz


def trace(house: dict, imagery: Aerial, o: dict, roads, road_lines: list, buildings_near: list[dict]) -> dict | None:
    """The lane into one farmstead, or None: {"xz": points from the road to the yard,
    "gravel": share on gravel, "road": the road's index in road_lines}."""
    hx, hz = house["x"], house["z"]
    p = shapely.Point(hx, hz)
    near = [(line.distance(p), k) for k, line in enumerate(road_lines)]
    d_road, k_road = min(near)
    if d_road > MAX_LANE_M or d_road < CONNECTED_M:
        return None
    q = road_lines[k_road].interpolate(road_lines[k_road].project(p))
    pad = 60.0
    x0, x1 = min(hx, q.x) - pad, max(hx, q.x) + pad
    z0, z1 = min(hz, q.y) - pad, max(hz, q.y) + pad
    w, h = int((x1 - x0) / CELL_M), int((z1 - z0) / CELL_M)
    gx = x0 + (np.arange(w) + 0.5) * CELL_M
    gz = z0 + (np.arange(h) + 0.5) * CELL_M
    mx, mz = np.meshgrid(gx, gz)
    rgba = imagery.sample(mx.ravel() + o["easting"], o["northing"] - mz.ravel()).reshape(h, w, 4)
    if (rgba[..., 3] < 127).mean() > 0.2:
        return None  # off the photos
    gravel = gravel_score(rgba[..., :3])  # (not blurred: a lane is two or three pixels wide)
    near_gravel = ndimage.maximum_filter(gravel, 3)  # (for telling whether a path is on one)
    cost = 1.0 + 9.0 * (1.0 - gravel)
    pts = shapely.points(mx.ravel(), mz.ravel())
    walls = shapely.union_all([footprint(b).buffer(1.0) for b in buildings_near])
    shapely.prepare(walls)
    blocked = shapely.contains_xy(walls, mx.ravel(), mz.ravel())
    cost.ravel()[blocked] = 1e4
    road_mask = shapely.contains_xy(roads, mx.ravel(), mz.ravel()).reshape(h, w)
    fp = footprint(house)
    dist_house = shapely.distance(fp, pts).reshape(h, w)
    yard = (dist_house >= YARD_RING_M[0]) & (dist_house <= YARD_RING_M[1]) & ~blocked.reshape(h, w)
    path = cheapest_path(cost, yard, road_mask)
    if path is None or len(path) < 3:
        return None
    rr, cc = np.unravel_index(np.array(path), (h, w))
    xz = np.column_stack([gx[cc], gz[rr]])
    length = shapely.LineString(xz).length
    straight = shapely.distance(fp, shapely.Point(xz[-1]))
    if length > MAX_LANE_M or length > MAX_DETOUR * straight + 15.0:
        return None
    # Out of the yard it has to be a lane all the way: on gravel, not across a field. (No
    # lane to be seen, under the trees or newer than the photos: none drawn. A made-up
    # one, straight to the nearest road, was too often wrong.)
    out = dist_house[rr, cc] > YARD_M
    paved = near_gravel[rr, cc] > 0.35
    if out.sum() >= 5:
        if paved[out].mean() < MIN_GRAVEL or _longest_run(out & ~paved) * CELL_M > MAX_OFF_GRAVEL_M:
            return None
    return {"xz": xz[::-1], "road": k_road}  # from the road in


def _longest_run(flags: np.ndarray) -> int:
    best = run = 0
    for f in flags:
        run = run + 1 if f else 0
        best = max(best, run)
    return best


def main() -> None:
    config.use_args(sys.argv)
    out_dir = config.OUT_DIR
    route = json.loads((out_dir / "route.json").read_text())
    places = json.loads((out_dir / "places.json").read_text())
    o = route["origin"]
    pts = np.array(route["points"]).reshape(-1, 3)
    route_xz = pts[:, [0, 2]]
    route_tree = cKDTree(route_xz)
    ia1 = shapely.LineString(route_xz)
    towns = shapely.union_all([shapely.Polygon(np.reshape(t["outline"], (-1, 2))) for t in places.get("towns", [])])
    shapely.prepare(towns)
    data = json.loads((out_dir / "streets.json").read_text())
    streets = [s for s in data["streets"] if not s.get("driveway")]
    road_lines = [ia1] + [shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]) for s in streets]
    # Where a lane may meet a road: on IA 1's pavement or a street.
    roads = shapely.union_all([ia1.buffer(SHOULDER_M)] + [line.buffer(s["half_width"] + 1.0)
                                                         for line, s in zip(road_lines[1:], streets)])
    shapely.prepare(roads)
    buildings = json.loads((out_dir / "structures.json").read_text())["buildings"]
    b_index = shapely.STRtree([footprint(b) for b in buildings])
    imagery = Aerial.for_quads(config.AERIAL_QUADS)
    ground = Ground(route)

    lanes = []
    picks = farmsteads(buildings, towns)
    for n, house in enumerate(picks):
        span = shapely.Point(house["x"], house["z"]).buffer(MAX_LANE_M + 60.0)
        near = [buildings[j] for j in b_index.query(span)]
        lane = trace(house, imagery, o, roads, road_lines, near)
        if lane is not None:
            lanes.append(lane)
        if n % 50 == 0:
            print(f"farmstead {n + 1}/{len(picks)}: {len(lanes)} lanes")

    out = []
    for lane in lanes:
        xz = lane["xz"]
        road = road_lines[lane["road"]]
        # On into the road: to IA 1's pavement edge (square to it), or a street's middle.
        q = road.interpolate(road.project(shapely.Point(xz[0])))
        xz = np.vstack([[q.x, q.y], xz])
        line = shapely.LineString(chaikin(xz))
        line = shapely.simplify(line, 0.5)
        if lane["road"] == 0:  # cut back to IA 1's pavement edge (it raises to meet it there)
            line = line.difference(ia1.buffer(IA1_EDGE_M, cap_style="flat"))
            if line.geom_type == "MultiLineString":
                line = max(line.geoms, key=lambda g: g.length)
        if line.is_empty or line.length < 8.0:
            continue
        xz = np.asarray(shapely.segmentize(line, SPACING_M).coords)
        if ia1.distance(shapely.Point(xz[-1])) < ia1.distance(shapely.Point(xz[0])):
            xz = xz[::-1]  # (from the road end)
        hts = surface_heights(xz, LANE["half_width"], LANE["lift"], ground, route_tree, pts[:, 1])
        if np.isnan(hts).any():
            continue
        joins = [bool(ia1.distance(shapely.Point(xz[e])) < IA1_EDGE_M + 0.5) for e in (0, -1)]
        out.append({
            "name": "", "kind": "lane", "half_width": LANE["half_width"], "joins": joins, "driveway": True,
            "points": [round(float(v), 2) for row in np.column_stack([xz[:, 0], hts, xz[:, 1]]).tolist() for v in row],
        })
    data["streets"] = streets + out
    (out_dir / "streets.json").write_text(json.dumps(data, separators=(",", ":")))
    fold_into_distances(route, out)
    clear_lanes(out, out_dir)
    print(f"driveways: {len(out)} of {len(picks)} farmsteads, "
          f"{sum(shapely.LineString(np.reshape(s['points'], (-1, 5))[:, [0, 4]]).length for s in out) / 1000:.1f} km")
    if "--sheet" in sys.argv:
        contact_sheet(imagery, out, buildings, o, sys.argv[sys.argv.index("--sheet") + 1])


def fold_into_distances(route: dict, lanes: list[dict]) -> None:
    """terrain_dist.bin ("meters from the road") counts the lanes too, with a lane's verge."""
    if not lanes:
        return
    t = route["terrain"]
    size, grid = t["tile_size_m"], t["grid"]
    path = config.OUT_DIR / t["distance_file"]
    dist = np.fromfile(path, dtype=np.uint8).reshape(-1, grid, grid).astype(float)
    dense = np.vstack([np.asarray(shapely.segmentize(shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]), 1.0).coords)
                       for s in lanes])
    tree = cKDTree(dense)
    local = np.arange(grid) * (size / (grid - 1))
    lx, lz = np.meshgrid(local, local)
    for n, (a, b, _) in enumerate(t["tiles"]):
        q = np.column_stack([(a * size + lx).ravel(), (b * size + lz).ravel()])
        d = tree.query(q, distance_upper_bound=60.0)[0] + CORN_VERGE_M - LANE["corn_from"]
        dist[n] = np.minimum(dist[n], np.clip(d, 0, 255).reshape(grid, grid))
    np.round(dist).astype(np.uint8).tofile(path)


def clear_lanes(lanes: list[dict], out_dir) -> None:
    """No tree or yard light standing on a lane (within its half width and a meter or so)."""
    if not lanes:
        return
    area = shapely.union_all([shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]).buffer(s["half_width"] + 1.0)
                              for s in lanes])
    shapely.prepare(area)
    path = out_dir / "trees.bin"
    trees = np.fromfile(path, dtype="<f4").reshape(-1, 5)
    on = shapely.contains_xy(area, trees[:, 0], trees[:, 1])
    trees[~on].astype("<f4").tofile(path)
    spath = out_dir / "structures.json"
    data = json.loads(spath.read_text())
    lights = 0
    for b in data["buildings"]:
        if b.get("light") and area.distance(shapely.Point(b["light"])) < 0.5:
            b["light"] = None
            lights += 1
    spath.write_text(json.dumps(data, separators=(",", ":")))
    print(f"on the lanes: {int(on.sum())} trees and {lights} yard lights left out")


def contact_sheet(imagery: Aerial, lanes: list[dict], buildings: list[dict], o: dict, out: str, count: int = 32) -> None:
    from PIL import Image, ImageDraw
    cell = 200
    cols = 8
    picks = lanes[:: max(1, len(lanes) // count)][:count]
    sheet = Image.new("RGB", (cols * cell, math.ceil(len(picks) / cols) * cell), (40, 40, 40))
    for k, s in enumerate(picks):
        p = np.reshape(s["points"], (-1, 5))[:, [0, 4]]
        cx, cz = p.mean(axis=0)
        half = max(np.ptp(p[:, 0]), np.ptp(p[:, 1])) / 2 + 30
        e0, n0 = cx + o["easting"], o["northing"] - cz
        img = Image.fromarray(imagery.render(e0 - half, n0 - half, e0 + half, n0 + half, 2 * half / cell))
        d = ImageDraw.Draw(img)
        to_px = lambda x, z: ((x - (cx - half)) / (2 * half) * cell, (z - (cz - half)) / (2 * half) * cell)
        d.line([to_px(x, z) for x, z in p], fill=(255, 0, 255), width=2)
        sheet.paste(img, ((k % cols) * cell, (k // cols) * cell))
    sheet.save(out)
    print(f"contact sheet: {out}")


if __name__ == "__main__":
    main()
