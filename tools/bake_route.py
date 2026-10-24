"""Bake a route (config.ROUTES: IA 1 from Kalona's 4-way stop to Iowa City's first stop
light, or IA 22 from the same 4-way stop to Wellman) into game data.

    python tools/bake_route.py [--route=highway1|highway22]

Writes game/data/routes/<id>/route.json, terrain.bin and the horizon. Downloads are
cached in tools/.cache/, so re-running is quick and works offline after the first time.

Game coordinates (Godot convention, meters): x = east, y = up, z = south,
relative to an origin near the route midpoint (config.ORIGIN) so nothing is more than ~13 km away.
"""

from __future__ import annotations

import json
import math
from datetime import date

import numpy as np
import shapely
from pyproj import Transformer
from scipy.ndimage import minimum_filter
from scipy.spatial import cKDTree
from shapely.ops import substring

import config
import geo
from sources import dem_sampler, read_roads

MILE_M = 1609.344
MEDIAN_PROBE_M = 60.0  # widest median we look across for the other carriageway
OPEN_EASE_M = 6.0      # the ground under an open bridge eases from the road bed over this


def project_roads(roads):
    to_utm = Transformer.from_crs(config.GEO_CRS, config.UTM_CRS, always_xy=True)
    for r in roads:
        r.lines = [np.column_stack(to_utm.transform(ln[:, 0], ln[:, 1])) for ln in r.lines]
    return to_utm


CROSSING_CLUSTER_M = 60.0  # the points of one crossing (a divided road's two carriageways)


def crossing_point(route: shapely.LineString, lines: list[np.ndarray]) -> shapely.Point | None:
    """Centroid of where `route` first meets any of `lines` (several points when a road is
    divided). Only the first crossing counts: a route running on past it can meet the
    same road again (IA 1 crosses Mormon Trek Blvd twice)."""
    hits = [route.intersection(shapely.LineString(ln)) for ln in lines]
    pts = [g for h in hits if not h.is_empty for g in getattr(h, "geoms", [h])]
    if not pts:
        return None
    first = min(pts, key=route.project)
    return shapely.MultiPoint([p for p in pts if p.distance(first) <= CROSSING_CLUSTER_M]).centroid


def find_route(roads, to_utm):
    hwy = [ln for r in roads if config.ROUTE_STATE in r.state_routes for ln in r.lines]
    g = geo.build_graph(hwy)
    a = geo.nearest_node(g, to_utm.transform(*config.SEARCH_FROM))
    b = geo.nearest_node(g, to_utm.transform(*config.SEARCH_TO))
    if config.SEARCH_VIA:  # by way of here (which carriageway of a divided road, say)
        v = geo.nearest_node(g, to_utm.transform(*config.SEARCH_VIA))
        raw = shapely.LineString(np.vstack([geo.path_polyline(g, a, v), geo.path_polyline(g, v, b)[1:]]))
    else:
        raw = shapely.LineString(geo.path_polyline(g, a, b))

    start_lines = [ln for r in roads if config.START_STATE in r.state_routes
                   and config.ROUTE_STATE not in r.state_routes for ln in r.lines]
    finish_lines = [ln for r in roads if r.name in config.FINISH_ROADS for ln in r.lines]
    start_cross = crossing_point(raw, start_lines)
    finish_cross = crossing_point(raw, finish_lines)
    if start_cross is None or finish_cross is None:
        raise RuntimeError(f"could not find the IA {config.START_STATE} crossing or the finish crossing "
                           f"({', '.join(sorted(config.FINISH_ROADS))}) on IA {config.ROUTE_STATE}")
    # Start and finish at the stop lines, short of the middle of each intersection.
    start_pt = raw.interpolate(raw.project(start_cross) - config.START_STOP_LINE_M)
    finish_pt = raw.interpolate(raw.project(finish_cross) - config.FINISH_STOP_LINE_M)

    s0 = raw.project(start_pt) - config.PRE_ROLL_M
    s1 = raw.project(finish_pt) + config.RUN_OUT_M
    clipped = substring(raw, max(s0, 0.0), min(s1, raw.length))
    return clipped, start_pt, finish_pt


def center_divided(dense: np.ndarray, hwy: shapely.MultiLineString) -> np.ndarray:
    """Where the highway is a divided road, move the path from its carriageway to the middle.

    Our path follows one carriageway; probing sideways finds the other one (if any)
    up to MEDIAN_PROBE_M away, and the point moves halfway toward it. The shift is
    smoothed so the road eases into and out of the median instead of jumping.
    """
    normals = geo.headings(dense) @ np.array([[0.0, -1.0], [1.0, 0.0]])  # 90 deg right
    reach = normals * MEDIAN_PROBE_M
    probes = shapely.linestrings(np.stack([dense - reach, dense + reach], axis=1))
    shift = np.zeros(len(dense))
    for i, hit in enumerate(shapely.intersection(probes, hwy)):
        pts = shapely.get_coordinates(hit)
        if len(pts) < 2:
            continue
        offsets = (pts - dense[i]) @ normals[i]
        others = offsets[np.abs(offsets) >= 1.0]  # our own carriageway sits at ~0
        if len(others):
            shift[i] = others[np.argmin(np.abs(others))] / 2
    shift = geo.gaussian_smooth(shift, 3.0)
    return dense + normals * shift[:, None]


def smooth_plan(line: shapely.LineString, hwy: shapely.MultiLineString) -> np.ndarray:
    dense = geo.resample(np.asarray(line.coords), 1.0)
    dense = center_divided(dense, hwy)
    dense = geo.gaussian_smooth(dense, config.PLAN_SMOOTH_SIGMA_M / 1.0)
    return geo.resample(dense, config.SPACING_M)


def nearest_station(xy: np.ndarray, pt) -> float:
    i = int(np.argmin(np.hypot(xy[:, 0] - pt[0], xy[:, 1] - pt[1])))
    return i * config.SPACING_M


def road_profile(xy: np.ndarray, dem):
    """The road surface's height along the route (dips filled, smoothed), and where it
    crosses a dip on a fill: [from, to] stations, then the deck's height over the
    ground at its deepest (see find_bridges)."""
    raw = dem(xy[:, 0], xy[:, 1])
    filled = geo.fill_dips(raw, int(config.DIP_FILL_WINDOW_M / config.SPACING_M))
    profile = geo.gaussian_smooth(filled, config.PROFILE_SMOOTH_SIGMA_M / config.SPACING_M)
    bridges = []
    for i0, i1 in geo.runs(filled - raw > config.BRIDGE_MIN_FILL_M):
        if bridges and i0 * config.SPACING_M - bridges[-1][1] < 20:
            bridges[-1][1] = i1 * config.SPACING_M
        else:
            bridges.append([i0 * config.SPACING_M, i1 * config.SPACING_M])
    bridges = [b for b in bridges if b[1] - b[0] >= 6]
    for b in bridges:
        i0, i1 = int(round(b[0] / config.SPACING_M)), int(round(b[1] / config.SPACING_M))
        b.append(round(float((profile[i0:i1 + 1] - raw[i0:i1 + 1]).max()), 1))
    return profile, bridges


def find_bridges(bridges, xy, roads):
    """Which of the filled dips are real bridges, and which of those are open underneath.

    Each becomes [from, to, height, open]: `height` is the deck over the ground at the
    deepest point; at RAILED_BRIDGE_M or more it's a bridge (deck and guardrails), a lower
    one a culvert under the fill. A bridge is `open` (1) when a creek, not a road, runs
    under it: the terrain under it is left at the real ground, not filled up to the road
    (US 218 runs under IA 1, and the game doesn't draw it, so that one stays filled)."""
    others = [shapely.LineString(ln) for r in roads if config.ROUTE_STATE not in r.state_routes for ln in r.lines]
    tree = shapely.STRtree(others) if others else None
    out = []
    for b0, b1, height in bridges:
        i0, i1 = int(round(b0 / config.SPACING_M)), int(round(b1 / config.SPACING_M))
        span = shapely.LineString(xy[i0:i1 + 1])
        under_road = tree is not None and any(span.intersects(others[k]) for k in tree.query(span))
        out.append([b0, b1, height, int(height >= config.RAILED_BRIDGE_M and not under_road)])
    return out


def route_label(r) -> str:
    us = sorted(f"US {n}" for n in r.us_routes)
    ia = sorted(f"IA {n}" for n in r.state_routes)
    return " / ".join(us + ia)


def base_name(name: str) -> str:
    """'Hazelwood Ave SW' and 'Hazelwood Ave' are the same road on either side of the highway."""
    words = name.split()
    return " ".join(words[:-1]) if words and words[-1] in {"N", "S", "E", "W", "NE", "NW", "SE", "SW"} else name


def passing_zones(xy, profile, start_s, finish_s):
    """Solid-line (no passing) zones for each direction, from sight distance, plus out of
    town at the start and into the finish (config.START/FINISH_NO_PASSING_M).

    "northbound" is the way the route runs (our way) and "southbound" against it, whichever
    way the highway really goes."""
    out = {}
    for direction in ("northbound", "southbound"):
        if direction == "northbound":
            blocked = geo.no_passing(xy, profile, config.SPACING_M)
        else:
            blocked = geo.no_passing(xy[::-1], profile[::-1], config.SPACING_M)[::-1]
        stations = np.arange(len(xy)) * config.SPACING_M
        blocked |= stations < start_s + config.START_NO_PASSING_M
        blocked |= stations > finish_s - config.FINISH_NO_PASSING_M
        out[direction] = geo.zones(blocked, config.SPACING_M, config.MIN_NO_PASSING_M)
    return out


def find_junctions(roads, raw_line: shapely.LineString, all_hwy: shapely.MultiLineString, xy: np.ndarray):
    """Side roads and driveways that end on the highway, as stations along the smoothed route.

    Distances are measured to both carriageways where it's divided, not just the one we drive.
    """
    tangents = geo.headings(xy)
    found = []
    for r in roads:
        # A highway passing under ours (US 218 under IA 1): its pieces end at the bridge
        # but it isn't a junction.
        if config.ROUTE_STATE in r.state_routes or config.UNDERPASS_US in r.us_routes:
            continue
        kind = config.ROAD_CLASSES.get(r.mtfcc)
        if kind is None and r.mtfcc in config.DRIVEWAY_CLASSES:
            kind = "driveway"
        if kind is None:
            continue
        label = route_label(r)
        if label:
            kind = "highway"
        for ln in r.lines:
            ends = [shapely.Point(ln[0]), shapely.Point(ln[-1])]
            d = [all_hwy.distance(p) for p in ends]
            k = int(np.argmin(d))
            # Must end on the highway and lead away from it (not run alongside or link two points on it).
            if d[k] > config.JUNCTION_TOL_M or d[1 - k] < 15 or raw_line.distance(ends[k]) > 30:
                continue
            s = nearest_station(xy, ln[0] if k == 0 else ln[-1])
            i = int(round(s / config.SPACING_M))
            far = ln[min(len(ln) - 1, 3)] if k == 0 else ln[max(0, len(ln) - 4)]
            found.append({
                "station": s,
                "name": r.name or {"ramp": "Ramp", "driveway": ""}.get(kind, "Unnamed road"),
                "route": label,
                "kind": kind,
                "side": geo.side_of(tangents[i], xy[i], far),
            })

    found.sort(key=lambda j: j["station"])
    merged = []
    for j in found:
        prev = merged[-1] if merged else None
        if (prev and prev["kind"] == j["kind"] and base_name(prev["name"]) == base_name(j["name"])
                and j["station"] - prev["station"] <= config.JUNCTION_MERGE_M):
            prev["sides"].add(j["side"])
            if len(j["name"]) > len(prev["name"]):
                prev["name"] = j["name"]
            continue
        merged.append({**j, "sides": {j["side"]}})
    for j in merged:
        sides = j.pop("sides")
        j["side"] = "both" if len(sides) == 2 else sides.pop()

    # Unnamed slip lanes of a highway junction are part of that junction, not their own crossroads.
    named_hwy = [j["station"] for j in merged if j["kind"] == "highway" and j["name"] != "Unnamed road"]
    return [j for j in merged if not (j["kind"] == "highway" and j["name"] == "Unnamed road"
                                      and any(abs(j["station"] - s) < 80 for s in named_hwy))]


def bake_terrain(xy, profile, dem, origin, bridges=()):
    """Heightmap tiles covering the corridor, with the road bed and ditches carved in,
    except under the open bridges: there the ground stays where it really is (the creek
    and its banks), easing back to the road bed over the first meters of each end."""
    e0, n0, h0 = origin
    size, grid = config.TILE_SIZE_M, config.TILE_GRID
    step = size / (grid - 1)
    gx, gz = xy[:, 0] - e0, -(xy[:, 1] - n0)
    tree = cKDTree(np.column_stack([gx, gz]))

    reach = config.CORRIDOR_HALF_WIDTH_M + size * math.sqrt(0.5)
    ix = range(math.floor((gx.min() - reach) / size), math.ceil((gx.max() + reach) / size))
    iz = range(math.floor((gz.min() - reach) / size), math.ceil((gz.max() + reach) / size))
    cands = np.array([(a, b) for a in ix for b in iz])
    centers = (cands + 0.5) * size
    dist, near = tree.query(centers)
    keep = dist <= reach
    cands, near = cands[keep], near[keep]
    order = np.lexsort((cands[:, 0], near))  # stream-friendly: sorted by station
    cands, near = cands[order], near[order]

    local = np.arange(grid) * step
    lx, lz = np.meshgrid(local, local)  # row = z, col = x
    # Per route sample: how far into an open bridge it is (0 outside), as a 0..1 weight.
    opening = np.zeros(len(xy))
    stations = np.arange(len(xy)) * config.SPACING_M
    for b0, b1, _, is_open in bridges:
        if is_open:
            inside = np.minimum(stations - b0, b1 - stations)
            opening = np.maximum(opening, smoothstep(0.0, OPEN_EASE_M, inside))
    heights = np.empty((len(cands), grid, grid), dtype=np.float32)
    road_dist = np.empty((len(cands), grid, grid), dtype=np.uint8)
    road_y = profile - h0
    for t, (a, b) in enumerate(cands):
        x, z = a * size + lx, b * size + lz
        natural = dem(e0 + x.ravel(), n0 - z.ravel()) - h0
        d, i = tree.query(np.column_stack([x.ravel(), z.ravel()]))
        carved = carve(natural, road_y[i], d)
        carved = carved + (np.minimum(natural, carved) - carved) * opening[i]
        heights[t] = carved.reshape(grid, grid)
        road_dist[t] = np.clip(np.round(d), 0, 255).reshape(grid, grid)

    tiles = [[int(a), int(b), round(float(k * config.SPACING_M), 1)] for (a, b), k in zip(cands, near)]
    return tiles, heights, road_dist


def bake_horizon(xy, tiles, heights, dem, origin):
    """Coarse ground out to the horizon around the whole route, kept under the corridor.

    Returns the grid's corner in game coordinates, its heights (rows along z) and each
    vertex's distance from the road.
    """
    e0, n0, h0 = origin
    step = config.HORIZON_STEP_M
    fine = config.TILE_SIZE_M / (config.TILE_GRID - 1)
    k = round(step / fine)
    chunk_m = step * config.HORIZON_CHUNK
    gx, gz = xy[:, 0] - e0, -(xy[:, 1] - n0)
    reach = config.HORIZON_REACH_M
    x0 = math.floor((gx.min() - reach) / chunk_m) * chunk_m
    z0 = math.floor((gz.min() - reach) / chunk_m) * chunk_m
    cols = math.ceil((gx.max() + reach - x0) / chunk_m) * config.HORIZON_CHUNK + 1
    rows = math.ceil((gz.max() + reach - z0) / chunk_m) * config.HORIZON_CHUNK + 1

    # The ground on the tiles' 8 m grid, with a coarse cell of padding all round: natural
    # elevation, except where the corridor tiles (with the road carved in) say otherwise.
    fx = x0 - step + np.arange((cols + 1) * k + 1) * fine
    fz = z0 - step + np.arange((rows + 1) * k + 1) * fine
    ground = np.empty((len(fz), len(fx)), dtype=np.float32)
    for r in range(0, len(fz), 256):
        xx, zz = np.meshgrid(fx, fz[r:r + 256])
        ground[r:r + 256] = (dem(e0 + xx.ravel(), n0 - zz.ravel()) - h0).reshape(xx.shape)
    g = config.TILE_GRID
    for t, (a, b, _) in enumerate(tiles):
        c = round((a * config.TILE_SIZE_M - fx[0]) / fine)
        r = round((b * config.TILE_SIZE_M - fz[0]) / fine)
        ground[r:r + g, c:c + g] = heights[t]

    horizon = coarse_floor(ground, k) - config.HORIZON_DROP_M
    cx, cz = np.meshgrid(x0 + np.arange(cols) * step, z0 + np.arange(rows) * step)
    d, _ = cKDTree(np.column_stack([gx, gz])).query(np.column_stack([cx.ravel(), cz.ravel()]))
    road_dist = np.clip(np.round(d), 0, 255).astype(np.uint8).reshape(rows, cols)
    return (x0, z0), horizon.astype(np.float32), road_dist


def coarse_floor(fine, k):
    """Every k-th sample of a fine height grid that has k samples of padding all round,
    each lowered to the lowest fine sample within k of it. Any mesh interpolating these
    stays on or under the fine ground."""
    low = minimum_filter(fine, size=2 * k + 1, mode="nearest")
    return low[k:-k:k, k:-k:k]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def carve(natural, road, d):
    """Terrain height given natural ground, road surface height and distance from centerline."""
    w = smoothstep(config.DITCH_OUTER_M, config.BLEND_OUTER_M, d)
    return (road - config.DITCH_DEPTH_M) * (1 - w) + natural * w


def main():
    import sys
    config.use_args(sys.argv)
    roads = read_roads(config.ROAD_BBOX)
    to_utm = project_roads(roads)
    raw_line, start_pt, finish_pt = find_route(roads, to_utm)
    hwy = shapely.MultiLineString([ln for r in roads if config.ROUTE_STATE in r.state_routes for ln in r.lines])
    xy = smooth_plan(raw_line, hwy)
    start_s = nearest_station(xy, start_pt.coords[0])
    finish_s = nearest_station(xy, finish_pt.coords[0])

    pad = config.CORRIDOR_HALF_WIDTH_M + config.TILE_SIZE_M * 2
    dem = dem_sampler(xy[:, 0].min() - pad, xy[:, 1].min() - pad, xy[:, 0].max() + pad, xy[:, 1].max() + pad)
    profile, bridges = road_profile(xy, dem)

    origin = config.ORIGIN
    e0, n0, h0 = origin
    to_geo = Transformer.from_crs(config.UTM_CRS, config.GEO_CRS, always_xy=True)
    lon0, lat0 = to_geo.transform(e0, n0)

    junctions = find_junctions(roads, raw_line, hwy, xy)
    no_pass = passing_zones(xy, profile, start_s, finish_s)
    bridges = find_bridges(bridges, xy, roads)
    tiles, heights, road_dist = bake_terrain(xy, profile, dem, origin, bridges)
    far = config.HORIZON_REACH_M + config.HORIZON_STEP_M * (config.HORIZON_CHUNK + 2)
    far_dem = dem_sampler(xy[:, 0].min() - far, xy[:, 1].min() - far, xy[:, 0].max() + far,
                          xy[:, 1].max() + far, res=config.HORIZON_DEM_RES_M, decimate=2)
    horizon_corner, horizon, horizon_dist = bake_horizon(xy, tiles, heights, far_dem, origin)

    points = np.column_stack([xy[:, 0] - e0, profile - h0, -(xy[:, 1] - n0)])
    grade = np.diff(profile) / config.SPACING_M
    route = {
        "version": 1,
        "name": config.ROUTE_NAME,
        "baked": date.today().isoformat(),
        "sources": [
            "USGS National Transportation Dataset (NTD) for Iowa, public domain",
            "USGS 3D Elevation Program 1/3 arc-second DEM, public domain",
        ],
        "origin": {"crs": config.UTM_CRS, "easting": e0, "northing": n0, "elevation_m": h0,
                   "lon": round(lon0, 6), "lat": round(lat0, 6)},
        "spacing_m": config.SPACING_M,
        "length_m": round((len(xy) - 1) * config.SPACING_M, 1),
        "start_station": start_s,
        "finish_station": finish_s,
        "points": [round(float(v), 2) for v in points.ravel()],
        "crossroads": [j for j in junctions if j["kind"] != "driveway"],
        "driveways": [{"station": j["station"], "side": j["side"]} for j in junctions if j["kind"] == "driveway"],
        "bridges": bridges,
        "no_passing": no_pass,
        "terrain": {
            "file": "terrain.bin",              # float32 height per vertex, tile after tile
            "distance_file": "terrain_dist.bin",  # uint8 meters from the road centerline
            "tile_size_m": config.TILE_SIZE_M,
            "grid": config.TILE_GRID,
            "tiles": tiles,                     # [ix, iz, station of nearest road point]
        },
        "horizon": {
            "file": "horizon.bin",              # float32 heights, rows along z
            "distance_file": "horizon_dist.bin",  # uint8 meters from the road centerline
            "corner": [horizon_corner[0], horizon_corner[1]],
            "step_m": config.HORIZON_STEP_M,
            "cols": horizon.shape[1],
            "rows": horizon.shape[0],
            "chunk": config.HORIZON_CHUNK,
        },
    }

    config.OUT_DIR.mkdir(parents=True, exist_ok=True)
    (config.OUT_DIR / "route.json").write_text(json.dumps(route, separators=(",", ":")))
    heights.astype("<f4").tofile(config.OUT_DIR / "terrain.bin")
    road_dist.tofile(config.OUT_DIR / "terrain_dist.bin")
    horizon.astype("<f4").tofile(config.OUT_DIR / "horizon.bin")
    horizon_dist.tofile(config.OUT_DIR / "horizon_dist.bin")

    drive_m = finish_s - start_s
    print(f"route: {len(xy)} samples, {route['length_m'] / 1000:.2f} km total")
    print(f"start line -> finish line: {drive_m / 1000:.2f} km = {drive_m / MILE_M:.2f} mi")
    print(f"origin: {lat0:.5f}, {lon0:.5f} at {h0} m")
    print(f"road elevation {profile.min():.1f}-{profile.max():.1f} m, max grade {np.abs(grade).max() * 100:.1f}%")
    for direction, zs in no_pass.items():
        share = sum(b - a for a, b in zs) / (len(xy) * config.SPACING_M)
        print(f"no-passing {direction}: {len(zs)} zones, {share:.0%} of the road")
    print(f"bridges (dips filled): {len(bridges)}")
    for b in bridges:
        kind = ("open bridge" if b[3] else "bridge over a road") if b[2] >= config.RAILED_BRIDGE_M else "culvert"
        print(f"  mile {(b[0] - start_s) / MILE_M:5.2f}  {b[1] - b[0]:3.0f} m  {b[2]:4.1f} m up  {kind}")
    print(f"crossroads: {len(route['crossroads'])}, driveways: {len(route['driveways'])}")
    for j in route["crossroads"]:
        print(f"  mile {(j['station'] - start_s) / MILE_M:5.2f}  {j['side']:5}  {j['kind']:7}  {j['name']}")
    size_mb = heights.nbytes / 1e6
    print(f"terrain: {len(tiles)} tiles, {size_mb:.1f} MB")
    km = (np.array(horizon.shape) - 1) * config.HORIZON_STEP_M / 1000
    print(f"horizon: {km[1]:.1f} x {km[0]:.1f} km at {config.HORIZON_STEP_M:g} m, {horizon.nbytes / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
