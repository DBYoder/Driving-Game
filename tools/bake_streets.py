"""The side roads and town streets near IA 1, for the game to draw.

    python tools/bake_streets.py      (after bake_route.py and bake_places.py)

Writes game/data/route/streets.json: every public road (and private lane) within
STREET_REACH_M of IA 1 in the National Transportation Dataset, cut back to the edge of
IA 1's pavement, as game x/z polylines with a kind:
  paved   highways, county routes, and streets inside the city limits
  gravel  the rest (most of rural Iowa's county roads are gravel)
  lane    private drives and farm lanes
Each point also has the height of the street's surface at its left edge, middle and
right edge (just above the ground, except where it crosses IA 1's ditch on a fill and
climbs up to meet the highway); scripts/world/streets.gd builds the mesh from them.

And it folds the streets into terrain_dist.bin ("meters from the road" at every terrain
vertex), so grass verges run along them and the corn keeps off them.

Left out: freeways and their ramps (US 218 passes under IA 1 on a bridge the terrain
doesn't have), short turn lanes alongside IA 1, and parking lots, alleys, trails and paths.
"""

from __future__ import annotations

import json
import math

import numpy as np
import shapely
from scipy.spatial import cKDTree

import config
from bake_route import project_roads, smoothstep
from sources import read_roads

STREET_REACH_M = 700.0  # how far from IA 1 they're drawn
IA1_EDGE_M = 4.3        # cut off this far from IA 1's centerline (its pavement is 4.26 m)
ALONGSIDE_M = 30.0      # a short piece mostly this close to IA 1 is a turn lane: left out
ALONGSIDE_MAX_M = 200.0
END_OVERLAP_M = 1.5     # free ends run on a bit, so pieces meet without a notch at a bend
SPACING_M = 3.0         # point spacing along a street
JOIN_FULL_M = 12.0      # at IA 1's height out to here (over the ditch)...
JOIN_BLEND_M = 30.0     # ...and back down on the ground by here
JOIN_RAISE_M = 0.03     # a hair above IA 1 where they meet

# Per kind: half width (m), height above the ground (paved a bit higher, so it wins where
# a paved and a gravel road overlap), and where the corn starts (m from the middle).
KINDS = {
    "paved": {"half_width": 3.6, "lift": 0.15, "corn_from": 12.0},
    "gravel": {"half_width": 3.2, "lift": 0.12, "corn_from": 10.0},
    "lane": {"half_width": 1.8, "lift": 0.10, "corn_from": 6.0},
}
WIDE = {"Mormon Trek Blvd": 5.6, "State Hwy 22": 3.9, "E Ave": 3.9}  # half widths that differ
CORN_VERGE_M = 26.0  # CornField.VERGE: where the corn starts along IA 1
PAVED_CLASSES = {"S1200"}
STREET_CLASSES = {"S1200", "S1400"}
LANE_CLASSES = {"S1740"}


def street_kind(r, in_town: bool) -> str | None:
    if r.mtfcc in LANE_CLASSES:
        return "lane"
    if r.mtfcc not in STREET_CLASSES:
        return None
    if r.mtfcc in PAVED_CLASSES or r.state_routes or r.us_routes or r.county_routes or in_town:
        return "paved"
    return "gravel"


class Ground:
    """The rendered terrain's height, the same triangles as TerrainTiles.height_at."""

    def __init__(self, route: dict):
        t = route["terrain"]
        self.size, self.grid = t["tile_size_m"], t["grid"]
        self.step = self.size / (self.grid - 1)
        self.heights = np.fromfile(config.OUT_DIR / t["file"], dtype="<f4").reshape(-1, self.grid, self.grid)
        self.index = {(a, b): k for k, (a, b, _) in enumerate(t["tiles"])}

    def at(self, x: np.ndarray, z: np.ndarray) -> np.ndarray:
        x, z = np.atleast_1d(x), np.atleast_1d(z)
        a, b = np.floor(x / self.size).astype(int), np.floor(z / self.size).astype(int)
        out = np.full(len(x), np.nan)
        for i in range(len(x)):
            k = self.index.get((int(a[i]), int(b[i])))
            if k is None:
                continue
            fx = (x[i] - a[i] * self.size) / self.step
            fz = (z[i] - b[i] * self.size) / self.step
            col, row = min(int(fx), self.grid - 2), min(int(fz), self.grid - 2)
            fx, fz = fx - col, fz - row
            h = self.heights[k]
            h00, h01, h10, h11 = h[row, col], h[row, col + 1], h[row + 1, col], h[row + 1, col + 1]
            if fx >= fz:
                out[i] = h00 + fx * (h01 - h00) + fz * (h11 - h01)
            else:
                out[i] = h00 + fz * (h10 - h00) + fx * (h11 - h10)
        return out


def run_on(line: shapely.LineString, start: bool, end: bool, by: float) -> shapely.LineString:
    """The line with its start and/or end carried straight on `by` meters."""
    c = np.asarray(line.coords)
    if start:
        d = c[0] - c[1]
        c = np.vstack([c[0] + d / np.linalg.norm(d) * by, c])
    if end:
        d = c[-1] - c[-2]
        c = np.vstack([c, c[-1] + d / np.linalg.norm(d) * by])
    return shapely.LineString(c)


def surface_heights(xz: np.ndarray, half_width: float, lift: float, ground: Ground,
                    route_tree: cKDTree, route_y: np.ndarray) -> np.ndarray:
    """Heights (left edge, middle, right edge) at each point of a street."""
    fwd = np.gradient(xz, axis=0)
    fwd /= np.maximum(np.linalg.norm(fwd, axis=1, keepdims=True), 1e-6)
    right = np.column_stack([-fwd[:, 1], fwd[:, 0]])  # x east, z south: (-dz, dx) is to the right
    out = []
    for side in (-1.0, 0.0, 1.0):
        p = xz + right * side * half_width
        lifted = ground.at(p[:, 0], p[:, 1]) + lift
        d, i = route_tree.query(p)
        w = smoothstep(JOIN_FULL_M, JOIN_BLEND_M, d)
        out.append(np.maximum(lifted, (route_y[i] + JOIN_RAISE_M) * (1 - w) + lifted * w))
    left, mid, right_h = out
    mid = np.maximum(mid, (left + right_h) / 2)  # the crown never dips under a straight line across
    return np.column_stack([left, mid, right_h])


def main():
    route = json.loads((config.OUT_DIR / "route.json").read_text())
    places = json.loads((config.OUT_DIR / "places.json").read_text())
    o = route["origin"]
    pts = np.array(route["points"]).reshape(-1, 3)
    route_xz = pts[:, [0, 2]]
    route_tree = cKDTree(route_xz)
    # Game x/z throughout (x = east, z = south).
    to_game = lambda c: np.column_stack([c[:, 0] - o["easting"], o["northing"] - c[:, 1]])
    ia1 = shapely.LineString(route_xz)
    near = ia1.buffer(STREET_REACH_M)
    on_ia1 = ia1.buffer(IA1_EDGE_M, cap_style="flat")
    towns = shapely.union_all([shapely.Polygon(np.reshape(t["outline"], (-1, 2))) for t in places.get("towns", [])])
    ground = Ground(route)

    roads = read_roads(config.ROAD_BBOX)
    project_roads(roads)
    pieces: dict[tuple[str, str], list] = {}
    for r in roads:
        if config.ROUTE_STATE in r.state_routes or config.FINISH_US in r.us_routes:
            continue
        for ln in r.lines:
            g = shapely.LineString(to_game(ln)).intersection(near)
            if g.is_empty:
                continue
            for part, in_town in ((g.intersection(towns), True), (g.difference(towns), False)):
                kind = street_kind(r, in_town)
                if kind is None or part.is_empty:
                    continue
                pieces.setdefault((r.name, kind), []).extend(
                    p for p in getattr(part, "geoms", [part]) if p.geom_type == "LineString")

    streets = []
    for (name, kind), lines in sorted(pieces.items()):
        merged = shapely.line_merge(shapely.MultiLineString(lines))
        for line in getattr(merged, "geoms", [merged]):
            ends = [shapely.Point(line.coords[0]), shapely.Point(line.coords[-1])]
            free = [ia1.distance(p) > IA1_EDGE_M + 1.0 for p in ends]
            line = run_on(line, free[0], free[1], END_OVERLAP_M)
            cut = line.difference(on_ia1)
            for piece in getattr(cut, "geoms", [cut]):
                if piece.is_empty or piece.geom_type != "LineString" or piece.length < 8.0:
                    continue
                piece = shapely.segmentize(piece, SPACING_M)
                xz = np.asarray(piece.coords)
                d_ia1 = route_tree.query(xz)[0]
                if piece.length < ALONGSIDE_MAX_M and (d_ia1 < ALONGSIDE_M).mean() > 0.5:
                    continue  # slip lanes at a junction: the junction's simpler without them
                if not name and d_ia1.min() < ALONGSIDE_M - 10.0 and d_ia1.min() > IA1_EDGE_M + 1.0:
                    continue  # an unnamed bit that stops short in IA 1's ditch
                k = KINDS[kind]
                hw = WIDE.get(name, k["half_width"]) if kind == "paved" else k["half_width"]
                h = surface_heights(xz, hw, k["lift"], ground, route_tree, pts[:, 1])
                if np.isnan(h).any():  # off the terrain's corridor
                    keep = ~np.isnan(h).any(axis=1)
                    if keep.sum() < 3:
                        continue
                    xz, h = xz[keep], h[keep]  # (only ever trims the far ends)
                joins = [bool(ia1.distance(shapely.Point(xz[e])) < IA1_EDGE_M + 0.5) for e in (0, -1)]
                streets.append({
                    "name": name, "kind": kind, "half_width": hw, "joins": joins,
                    "points": [round(float(v), 2) for row in np.column_stack([xz[:, 0], h, xz[:, 1]]).tolist()
                               for v in row],
                })
    (config.OUT_DIR / "streets.json").write_text(json.dumps({
        "source": "USGS National Transportation Dataset (public domain)",
        "note": "points: x, left edge y, middle y, right edge y, z per point (game meters)",
        "streets": streets,
    }, separators=(",", ":")))

    # "Meters from the road" now counts the streets too, each with its own verge.
    t = route["terrain"]
    size, grid = t["tile_size_m"], t["grid"]
    local = np.arange(grid) * (size / (grid - 1))
    lx, lz = np.meshgrid(local, local)
    trees = {}
    for kind in KINDS:
        dense = [np.asarray(shapely.segmentize(shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]), 1.0).coords)
                 for s in streets if s["kind"] == kind]
        if dense:
            trees[kind] = cKDTree(np.vstack(dense))
    dist = np.empty((len(t["tiles"]), grid, grid), dtype=np.uint8)
    for n, (a, b, _) in enumerate(t["tiles"]):
        q = np.column_stack([(a * size + lx).ravel(), (b * size + lz).ravel()])
        d = route_tree.query(q)[0]
        for kind, tree in trees.items():
            d = np.minimum(d, tree.query(q, distance_upper_bound=300.0)[0] + CORN_VERGE_M - KINDS[kind]["corn_from"])
        dist[n] = np.clip(np.round(d), 0, 255).reshape(grid, grid)
    dist.tofile(config.OUT_DIR / t["distance_file"])

    total = {k: round(sum(shapely.LineString(np.reshape(s["points"], (-1, 5))[:, [0, 4]]).length
                          for s in streets if s["kind"] == k) / 1000.0, 1) for k in KINDS}
    print(f"streets: {len(streets)} pieces, km by kind {total}, "
          f"{sum(1 for s in streets if any(s['joins']))} meet IA 1")


if __name__ == "__main__":
    main()
