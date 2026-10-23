"""The Kalona 4-way stop, where both runs start, laid out the way it really is.

IA 1 and IA 22 cross on the northwest corner of Kalona, concrete all through the
junction:
  - IA 1 opens a left-turn lane down the middle on each side: its through lanes shift
    half a lane out each way, from about 120 m south and 185 m north. IA 22 stays two lanes.
  - Every corner has a free right turn: its own lane round a curve, a painted gore
    between it and the highway, and a YIELD sign where it joins. A light pole leans a
    davit arm over each one.
  - All four ways stop.
  - Left-turners from IA 22 see IA-1 painted across the lane they're turning into, and
    the other way round for IA 22.
  - The welcome sign stands in a flower bed on the southwest corner by the flagpole.

Sources: the USGS NTD's lines for the curves; the 2019 lidar for the light poles, the
signs and the flagpole; the owner's Street View photos for the rest.

Everything is worked out in each route's game coordinates from both routes' own
centerlines (route.json): its own for its highway, the other route's (moved over from
its origin) for the one crossing it, so the junction meets both exactly. A spot is
written (t, w) on one of the highways: t meters from the middle along it (north on IA 1,
east on IA 22), w meters off its middle (east of IA 1, north of IA 22).

bake_streets.py builds it (and clips the side roads to it, and keeps the corn off it) and
writes junction.json for the game (scripts/world/junction.gd).
"""

from __future__ import annotations

import json
import math

import numpy as np
import shapely
from shapely import affinity
from shapely.ops import substring

import config

IA1, IA22 = "highway1", "highway22"
LANE = 3.66
PAVED = 4.26  # a two-lane highway's paved half width (RoadMesher.PAVED_HALF_WIDTH)
TURN_PAVED = PAVED + LANE / 2 + 0.3  # IA 1 with its left-turn lane: 6.39
CROWN = 0.04  # the middle of a two-lane road stands this much above its edges
# Past the edge of the pavement, as on the road (RoadMesher.SECTION): the gravel
# shoulder, the grass foreslope down to the ditch, and a short skirt tucked under it...
SECTION = [(2.24, -0.08, "gravel"), (5.74, -1.1, "grass"), (6.04, -1.5, "grass")]
# ...though round the turning lanes the grass comes right up to the concrete (along the
# highways the road's own shoulders carry on), easing from one to the other over EASE m.
EDGE = [(0.4, -0.03, "gravel"), (4.4, -1.1, "grass"), (4.7, -1.5, "grass")]
EASE = 20.0
SLIP_WIDTH = 4.6
LANE_STEP = 4.0
GRID = 2.0  # the surface is cut into squares this big (so it can follow the heights)
PAINT_LIFT = 0.012
TERRAIN_BELOW = 0.3  # the ground is kept this far under the pavement...
TERRAIN_RISE = 0.03  # ...rising this much a meter away from it...
TERRAIN_REACH = 12.0  # ...out to here

# Where the junction ends on each highway: stations on that highway's own route, on whole
# samples so the road mesh stops exactly where the junction starts.
ENDS = {IA1: (78.0, 386.0), IA22: (8.0, 282.0)}
# IA 1's left-turn lanes: full width out to here, back to two lanes at the ends (m from
# the middle, south and north).
TURN_FULL = (70.0, 80.0)
# The free right turns, by corner (east sign, north sign): the middle of the lane runs
# `a` m off IA 1's middle and `b` m off IA 22's, rounds the corner on a curve of radius
# `r`, and runs on alongside each highway `run_ia1`/`run_ia22` m past the curve, its gore
# closing and then the lane itself narrowing away (fitted to the NTD's lines).
SLIPS = {
    (1, 1): {"a": 13.0, "b": 6.6, "r": 21.0, "run_ia1": 50.0, "run_ia22": 166.0},  # IA 22 westbound turning north
    (1, -1): {"a": 13.0, "b": 8.0, "r": 21.0, "run_ia1": 45.0, "run_ia22": 63.0},  # IA 1 northbound turning east
    (-1, -1): {"a": 12.0, "b": 9.0, "r": 15.0, "run_ia1": 50.0, "run_ia22": 40.0},  # IA 22 eastbound turning south
    (-1, 1): {"a": 11.5, "b": 6.6, "r": 22.0, "run_ia1": 43.0, "run_ia22": 30.0},  # IA 1 southbound turning west
}
GORE_CLOSE = 25.0  # m past the curve the gore takes to close
NARROW = 35.0  # m the lane takes to narrow away at its far end
STOP_LINE = {IA1: 11.72, IA22: 10.0}  # m from the middle (IA 1's northbound one is Highway 1's start line)
# Light poles on davit arms, off the lidar: (m east, m north of the middle, the way the arm reaches).
LIGHTS = [(17.6, -32.8, "w"), (34.0, -13.2, "n"), (16.7, 29.7, "w"), (-17.1, -25.4, "e"),
          (-15.0, 31.0, "e"), (-68.2, -11.2, "n"), (-32.5, 10.0, "s")]
WELCOME_SIGN = (-30.8, -33.7)  # its middle, m east and north of the junction's (lidar)
FLAGPOLE = (-33.7, -26.4)


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=float) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Highway:
    """One of the two highways through the junction, in this route's game coordinates,
    with RouteData's position_at, tangent_at and right_at."""

    def __init__(self, route: dict, shift: np.ndarray, sense: float):
        self.points = np.array(route["points"], dtype=float).reshape(-1, 3) + shift
        self.spacing = float(route["spacing_m"])
        self.sense = sense  # +1: stations run the way t does (IA 1, north); -1 (IA 22, the route heads west)
        self.line = shapely.LineString(self.points[:, [0, 2]])
        self.s0 = 0.0

    def pos(self, s):
        f = np.clip(np.asarray(s, dtype=float) / self.spacing, 0.0, len(self.points) - 1.0)
        i = np.minimum(f.astype(int), len(self.points) - 2)
        return self.points[i] + (self.points[i + 1] - self.points[i]) * (f - i)[..., None]

    def right(self, s):
        """Unit (x, z) to the right of the route's way (east of IA 1, north of IA 22)."""
        s = np.asarray(s, dtype=float)
        t = self.pos(s + self.spacing) - self.pos(s - self.spacing)
        t = t / np.linalg.norm(t, axis=-1, keepdims=True)
        r = np.stack([-t[..., 2], t[..., 0]], axis=-1)
        return r / np.linalg.norm(r, axis=-1, keepdims=True)

    def station(self, t):
        return self.s0 + self.sense * np.asarray(t, dtype=float)

    def point(self, t, w):
        s = self.station(t)
        return self.pos(s)[..., [0, 2]] + self.right(s) * np.asarray(w, dtype=float)[..., None]

    def locate(self, xz: np.ndarray):
        """(t, w) of points."""
        s = shapely.line_locate_point(self.line, shapely.points(xz))
        w = np.einsum("ij,ij->i", xz - self.pos(s)[:, [0, 2]], self.right(s))
        return (s - self.s0) * self.sense, w


def _shift(src: dict, dst: dict) -> np.ndarray:
    """What to add to a point of route `src` to put it in route `dst`'s game coordinates."""
    a, b = src["origin"], dst["origin"]
    return np.array([a["easting"] - b["easting"], a["elevation_m"] - b["elevation_m"], b["northing"] - a["northing"]])


class Junction:
    """The 4-way in one route's game coordinates. `own` is the route's own highway,
    `cross` the other; `ia1` and `ia22` say which is which."""

    def __init__(self, route_id: str, routes: dict, street_height):
        self.route_id = route_id
        me = routes[route_id]
        self.hw = {IA1: Highway(routes[IA1], _shift(routes[IA1], me), 1.0),
                   IA22: Highway(routes[IA22], _shift(routes[IA22], me), -1.0)}
        self.own, self.cross = (IA1, IA22) if route_id == IA1 else (IA22, IA1)
        c = self.hw[IA1].line.intersection(self.hw[IA22].line)
        if c.geom_type != "Point":
            c = shapely.get_geometry(c, 0)
        self.center = np.array([c.x, c.y])
        for h in self.hw.values():
            h.s0 = float(shapely.line_locate_point(h.line, c))
        ia1, ia22 = self.hw[IA1], self.hw[IA22]
        # Each highway's ends, as t (the far end of each leg).
        self.ends = {k: tuple(sorted(((s - self.hw[k].s0) * self.hw[k].sense for s in ENDS[k]))) for k in self.hw}
        self.street_height = street_height  # (xz) -> heights of a street's surface there (bake_streets)
        # The local frame at the middle, for the curves.
        self.p1 = ia1.right(ia1.s0)  # east-ish
        self.p2 = ia22.right(ia22.s0)  # north-ish
        self.slips = {q: self._slip(q, spec) for q, spec in SLIPS.items()}
        self.paved = self._paved()

    # --- Widths -------------------------------------------------------------------------

    def turn_open(self, t):
        """0..1: how far IA 1's left-turn lane has opened at t."""
        t = np.asarray(t, dtype=float)
        south, north = self.ends[IA1]
        far = np.where(t < 0, -south, north)
        full = np.where(t < 0, TURN_FULL[0], TURN_FULL[1])
        return 1.0 - smoothstep(full, far, np.abs(t))

    def edge(self, k: str, t):
        """Paved half width of highway k at t."""
        return PAVED + (TURN_PAVED - PAVED) * self.turn_open(t) if k == IA1 else np.full(np.shape(t), PAVED)

    # --- The free right turns -------------------------------------------------------------

    def _slip(self, q, spec) -> dict:
        """A corner's turning lane: its middle, width, and where it meets each highway."""
        su, sv = q
        a, b, r = spec["a"], spec["b"], spec["r"]
        m = np.array([self.p1, self.p2])
        center = self.center + np.linalg.solve(m, np.array([su * (a + r), sv * (b + r)]))
        t1 = center - su * r * self.p1  # where the curve meets the line along IA 1
        t2 = center - sv * r * self.p2  # ...along IA 22
        a1, a2 = math.atan2(*(t1 - center)[::-1]), math.atan2(*(t2 - center)[::-1])
        sweep = (a1 - a2 + math.pi) % (2 * math.pi) - math.pi  # the short way round
        n = max(8, int(abs(sweep) * r / 1.0))
        ang = a2 + sweep * np.linspace(0.0, 1.0, n + 1)
        arc = center + r * np.column_stack([np.cos(ang), np.sin(ang)])
        out = {"q": q, "center": center, "r": r, "arc": arc}
        for k, tp, side, run in ((IA1, t1, su, spec["run_ia1"]), (IA22, t2, sv, spec["run_ia22"])):
            h = self.hw[k]
            t0 = float(h.locate(tp[None])[0][0])
            way = math.copysign(1.0, t0)  # outward along the highway
            gap0 = abs(float(h.locate(tp[None])[1][0])) - float(self.edge(k, t0)) - SLIP_WIDTH / 2
            s = np.linspace(0.0, run, max(4, int(run / 1.5)) + 1)
            t = t0 + way * s
            gap = gap0 * (1.0 - smoothstep(0.0, min(GORE_CLOSE, run * 0.45), s))
            width = SLIP_WIDTH * (1.0 - smoothstep(run - min(NARROW, run * 0.5), run, s))
            e = self.edge(k, t)
            out[k] = {"t": t, "side": side, "inner": h.point(t, side * (e + gap)),
                      "outer": h.point(t, side * (e + gap + width)), "mid": h.point(t, side * (e + gap + width / 2)),
                      "width": width, "gap": gap, "far": float(t[-1])}
        # Which way traffic goes round: from IA 22 to IA 1 on the NE and SW corners.
        out["from"] = IA22 if su * sv > 0 else IA1
        return out

    def slip_edges(self, q):
        """A corner's lane as (middle, outer edge, inner edge), each from its far end on IA 22
        round the curve to its far end on IA 1."""
        sl = self.slips[q]
        d = sl["arc"] - sl["center"]
        d /= np.linalg.norm(d, axis=1, keepdims=True)
        arc_out = sl["center"] + d * (sl["r"] - SLIP_WIDTH / 2)
        arc_in = sl["center"] + d * (sl["r"] + SLIP_WIDTH / 2)
        a, b = sl[IA22], sl[IA1]
        mid = np.vstack([a["mid"][::-1], sl["arc"][1:-1], b["mid"]])
        outer = np.vstack([a["outer"][::-1], arc_out[1:-1], b["outer"]])
        inner = np.vstack([a["inner"][::-1], arc_in[1:-1], b["inner"]])
        return mid, outer, inner

    # --- The pavement ---------------------------------------------------------------------

    def leg_edge(self, k: str, t0: float, t1: float, side: float, step=2.0) -> np.ndarray:
        n = max(2, int(abs(t1 - t0) / step) + 1)
        t = np.linspace(t0, t1, n)
        return self.hw[k].point(t, side * self.edge(k, t))

    def chains(self, which=False) -> dict:
        """The outline of the pavement round each corner, from where it leaves IA 1's end
        to where it reaches IA 22's (open polylines, (x, z)); with `which`, also 1 for each
        point along the turning lane and 0 along a highway."""
        out = {}
        for q in SLIPS:
            su, sv = q
            sl = self.slips[q]
            end1 = self.ends[IA1][1 if sv > 0 else 0]
            end22 = self.ends[IA22][1 if su > 0 else 0]
            _, outer, _ = self.slip_edges(q)
            along1 = self.leg_edge(IA1, end1, sl[IA1]["far"], su)
            along22 = self.leg_edge(IA22, sl[IA22]["far"], end22, sv)
            out[q] = np.vstack([along1[:-1], outer[::-1], along22[1:]])
            if which:
                out[q] = (out[q], np.concatenate([np.zeros(len(along1) - 1), np.ones(len(outer)), np.zeros(len(along22) - 1)]))
        return out

    def _paved(self) -> shapely.Polygon:
        ch = self.chains()
        cut = {}  # the cut across each leg's end, with a point in the middle (the crown)
        ring = []
        for q in ((1, 1), (1, -1), (-1, -1), (-1, 1)):  # NE, SE, SW, NW: round clockwise
            c = ch[q]
            ring.append(c if q in ((1, 1), (-1, -1)) else c[::-1])
        # NE ends on IA 22's east end; SE starts there. SE (reversed) ends on IA 1's south end...
        pts = []
        legs = [(IA22, 1), (IA1, 0), (IA22, 0), (IA1, 1)]  # the cut after each corner
        for c, (k, which) in zip(ring, legs):
            pts.extend(c.tolist())
            t = self.ends[k][which]
            pts.append(self.hw[k].point(np.array([t]), np.array([0.0]))[0].tolist())
            cut[k, which] = t
        poly = shapely.Polygon(pts)
        if not poly.is_valid:
            poly = shapely.make_valid(poly)
            poly = max(getattr(poly, "geoms", [poly]), key=lambda g: g.area)
        return poly

    # --- Heights ----------------------------------------------------------------------------

    def heights(self, xz: np.ndarray) -> np.ndarray:
        """The surface's height at points: the route's own highway (with its crown) near it,
        the crossing one (as bake_streets would draw it) near that, blended in between."""
        xz = np.atleast_2d(xz)
        own, cross = self.hw[self.own], self.hw[self.cross]
        t_o, w_o = own.locate(xz)
        h_own = own.pos(own.station(t_o))[:, 1] + CROWN * np.clip(1.0 - np.abs(w_o) / PAVED, 0.0, 1.0)
        t_c, w_c = cross.locate(xz)
        across = np.clip(w_c, -PAVED, PAVED)
        h_cross = self._cross_height(t_c, across)
        d_o, d_c = w_o * w_o, w_c * w_c
        k = d_o / np.maximum(d_o + d_c, 1e-9)
        return h_own * (1.0 - k) + h_cross * k

    def _cross_height(self, t, w):
        """The crossing highway's surface, from a street's heights across it every meter."""
        if not hasattr(self, "_cross_rows"):
            t0, t1 = self.ends[self.cross]
            ts = np.arange(math.floor(t0) - 2, math.ceil(t1) + 3, 1.0)
            h = self.hw[self.cross]
            rows = [self.street_height(h.point(ts, np.full(ts.shape, side * PAVED))) for side in (-1.0, 0.0, 1.0)]
            left, mid, right = rows
            mid = np.maximum(mid, (left + right) / 2)
            self._cross_rows = (ts, left, mid, right)
        ts, left, mid, right = self._cross_rows
        lo, m, hi = np.interp(t, ts, left), np.interp(t, ts, mid), np.interp(t, ts, right)
        f = np.asarray(w) / PAVED
        return np.where(f < 0, m + (m - lo) * f, m + (hi - m) * f)

    # --- Meshes -------------------------------------------------------------------------------

    def surface(self):
        """The pavement cut into GRID squares, triangulated: (vertices (x, z), triangles)."""
        poly = self.paved
        x0, z0, x1, z1 = poly.bounds
        xs = np.arange(math.floor(x0 / GRID) * GRID, x1 + GRID, GRID)
        zs = np.arange(math.floor(z0 / GRID) * GRID, z1 + GRID, GRID)
        gx, gz = np.meshgrid(xs[:-1], zs[:-1])
        cells = shapely.box(gx.ravel(), gz.ravel(), gx.ravel() + GRID, gz.ravel() + GRID)
        shapely.prepare(poly)
        cells = cells[shapely.intersects(poly, cells)]
        pieces = shapely.get_parts(shapely.intersection(cells, poly))
        pieces = pieces[shapely.get_type_id(pieces) == 3]  # polygons (not the odd sliver of a line)
        tris = shapely.get_parts(shapely.constrained_delaunay_triangles(pieces))
        tris = tris[shapely.area(tris) > 1e-6]
        coords = shapely.get_coordinates(shapely.get_exterior_ring(tris)).reshape(-1, 4, 2)[:, :3]
        return _index(coords)

    def bands(self):
        """Gravel shoulder and grass slopes round the outside, as (vertices (x, z), dy, kind,
        triangles), each corner's outline offset outward like the road's cross-section."""
        verts, dys, kinds, tris = [], [], [], []
        for q, (chain, slip) in self.chains(which=True).items():
            n = _normals(chain)
            # Square to the leg at each end, so the end lines up with the road (or street).
            su, sv = q
            end1 = self.ends[IA1][1 if sv > 0 else 0]
            end22 = self.ends[IA22][1 if su > 0 else 0]
            n[0] = su * self.hw[IA1].right(self.hw[IA1].station(np.array([end1])))[0]
            n[-1] = sv * self.hw[IA22].right(self.hw[IA22].station(np.array([end22])))[0]
            inside = shapely.contains_xy(self.paved, *(chain + n * 0.3).T)
            n[inside] *= -1.0
            # The road's shoulders along the highways, grass to the concrete round the
            # turning lanes: f is how near the nearest turning-lane point is (0 far, 1 on it).
            along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(chain, axis=0), axis=1))])
            on = along[slip > 0.5]
            gap = np.abs(along[:, None] - on[None, :]).min(axis=1) if len(on) else np.full(len(along), np.inf)
            # ...and always the road's own right where the junction meets the route's road.
            from_road = along if self.own == IA1 else along[-1] - along
            f = ((1.0 - smoothstep(0.0, EASE, gap)) * smoothstep(0.0, 12.0, from_road))[:, None]
            rows = [(chain, np.zeros(len(chain)), "concrete")]
            for (off0, dy0, kind), (off1, dy1, _) in zip(SECTION, EDGE):
                rows.append((chain + n * (off0 + (off1 - off0) * f), dy0 + (dy1 - dy0) * f[:, 0], kind))
            base = len(verts)
            m = len(chain)
            for pts, dy, kind in rows:
                verts.extend(pts.tolist())
                dys.extend(np.broadcast_to(dy, (m,)).tolist())
                kinds.extend([kind] * m)
            for r, (_, _, kind) in enumerate(rows[1:]):
                a0 = base + r * m
                b0 = a0 + m
                for i in range(m - 1):
                    tris.append(((a0 + i, b0 + i, b0 + i + 1), kind))
                    tris.append(((a0 + i, b0 + i + 1, a0 + i + 1), kind))
        return np.array(verts), np.array(dys), kinds, tris

    # --- Paint -----------------------------------------------------------------------------------

    def paint(self) -> dict:
        """Polygons by color: the lines, the gores, the stop lines, the arrows and the words."""
        out = {"white": [], "yellow": [], "black": []}

        def line(k, t0, t1, w_of_t, width, color):
            n = max(2, int(abs(t1 - t0) / 1.0) + 1)
            t = np.linspace(t0, t1, n)
            pts = self.hw[k].point(t, w_of_t(t))
            out[color].append(shapely.LineString(pts).buffer(width / 2, cap_style="flat", join_style="mitre",
                                                              mitre_limit=3.0))

        stop1, stop22 = STOP_LINE[IA1], STOP_LINE[IA22]
        s1, n1 = self.ends[IA1]
        w22, e22 = self.ends[IA22]
        k = self.turn_open
        # IA 1, each side of the middle (sign -1 south, +1 north): the double yellow down the
        # left of the turn lane, the white line between it and the through lane (once it's
        # open), and the edge lines, all shifting out as the turn lane opens.
        for far, sign in ((s1, -1.0), (n1, 1.0)):
            near = sign * stop1
            for g in (-0.17, 0.17):
                line(IA1, far, near, lambda t, g=g, sign=sign: sign * LANE / 2 * k(t) + g, 0.12, "yellow")
            ts = np.linspace(near, far, 400)
            opened = ts[k(ts) > 0.6]
            if len(opened) > 1:
                line(IA1, opened[0], opened[-1], lambda t, sign=sign: -sign * LANE / 2 * k(t), 0.15, "white")
            for side in (-1.0, 1.0):
                line(IA1, far, near, lambda t, side=side: side * (LANE + 0.08 + LANE / 2 * k(t)), 0.15, "white")
        # IA 22: the double yellow and the edge lines.
        for t0, t1 in ((w22, -stop22), (stop22, e22)):
            for g in (-0.17, 0.17):
                line(IA22, t0, t1, lambda t, g=g: np.full(t.shape, g), 0.12, "yellow")
            for side in (-1.0, 1.0):
                line(IA22, t0, t1, lambda t, side=side: np.full(t.shape, side * (LANE + 0.08)), 0.15, "white")
        # Stop lines, 0.6 m wide, across the lanes coming in.
        for k_, t, w0, w1 in ((IA1, -stop1, -LANE / 2 + 0.3, LANE * 1.5), (IA1, stop1, -LANE * 1.5, LANE / 2 - 0.3),
                              (IA22, -stop22, -LANE, -0.3), (IA22, stop22, 0.3, LANE)):
            way = math.copysign(1.0, t)
            a = self.hw[k_].point(np.array([t, t]), np.array([w0, w1]))
            b = self.hw[k_].point(np.array([t + way * 0.6, t + way * 0.6]), np.array([w0, w1]))
            out["white"].append(shapely.Polygon([a[0], a[1], b[1], b[0]]))
        # The corners: an edge line down each side of the turning lane, and the gore
        # between it and the highways hatched.
        for q in SLIPS:
            mid, outer, inner = self.slip_edges(q)
            sl = self.slips[q]
            width = np.concatenate([sl[IA22]["width"][::-1], np.full(len(sl["arc"]) - 2, SLIP_WIDTH), sl[IA1]["width"]])
            keep = width > 0.6
            for edge in (outer, inner):
                d = edge - mid
                d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
                e = (edge - d * 0.25)[keep]
                if len(e) > 1:
                    out["white"].append(shapely.LineString(e).buffer(0.075, cap_style="flat"))
            gore = self._gore(q)
            if gore is not None:
                out["white"].extend(_hatch(gore, sl))
        # Lane arrows: a left turn in each turn lane, straight-or-right in the through lanes.
        for sign in (-1.0, 1.0):
            way = -sign  # on the south leg (sign -1) traffic heads north, +t
            for back in (8.0, 38.0):
                out["white"].extend(self._place(IA1, ARROWS["left"], sign * (stop1 + back), 0.0, way))
            out["white"].extend(self._place(IA1, ARROWS["straight_right"], sign * (stop1 + 14.0), -sign * LANE, way))
        # IA-1 across the lane a left-turner from IA 22 turns into, the letters' tops away
        # from them; IA-22 likewise for left-turners from IA 1.
        for k_, t, w, text, up in ((IA1, -35.0, -LANE, "IA-1", -1.0), (IA1, 35.0, LANE, "IA-1", 1.0),
                                    (IA22, -32.0, LANE / 2, "IA-22", 1.0), (IA22, 32.0, -LANE / 2, "IA-22", -1.0)):
            white, black = self._words(k_, text, t, w, up)
            out["white"].extend(white)
            out["black"].extend(black)
        merged = {c: shapely.make_valid(shapely.union_all(v)) for c, v in out.items()}
        merged["black"] = merged["black"].difference(merged["white"])
        return {c: [g for g in shapely.get_parts(v) if g.geom_type == "Polygon" and g.area > 1e-4]
                for c, v in merged.items()}

    def _first(self, cond, t0, t1, step=0.5):
        ts = np.arange(t0, t1, step if t1 > t0 else -step)
        ok = cond(ts)
        return float(ts[np.argmax(ok)]) if ok.any() else None

    def _gore(self, q):
        """The paved corner between a turning lane and the two highways, inside the lane."""
        su, sv = q
        _, _, inner = self.slip_edges(q)
        sl = self.slips[q]
        corner1 = self.hw[IA1].point(np.array([sl[IA1]["far"]]), np.array([su * float(self.edge(IA1, sl[IA1]["far"]))]))
        # The highway edges from the lane's far end on IA 1 back to the middle and out to
        # its far end on IA 22, inside the gore.
        t1 = np.linspace(sl[IA1]["far"], 0.0, 40)
        t22 = np.linspace(0.0, sl[IA22]["far"], 40)
        e1 = self.hw[IA1].point(t1, su * (self.edge(IA1, t1) + 0.3))
        e22 = self.hw[IA22].point(t22, sv * (PAVED + 0.3))
        box = shapely.Polygon(np.vstack([inner, e1, e22]))
        if not box.is_valid:
            box = shapely.make_valid(box)
        # Only out past both highways' edges (the middle of the junction stays open).
        legs = shapely.union_all([self._strip(IA1, 0.3), self._strip(IA22, 0.3)])
        g = box.difference(legs)
        parts = [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 2.0]
        return max(parts, key=lambda p: p.area) if parts else None

    def keep_clear(self) -> shapely.Polygon:
        """Where no side road goes: the pavement, and along the crossing highway (whose
        own street pieces are replaced, both of them where the NTD splits it in two)."""
        t0, t1 = self.ends[self.cross]
        t = np.linspace(t0, t1, int((t1 - t0) / 2.0) + 1)
        h = self.hw[self.cross]
        corridor = shapely.Polygon(np.vstack([h.point(t, np.full(t.shape, -12.0)), h.point(t, np.full(t.shape, 12.0))[::-1]]))
        return shapely.union_all([self.paved, corridor])

    def _strip(self, k, extra=0.0):
        t0, t1 = self.ends[k]
        t = np.linspace(t0, t1, int((t1 - t0) / 2.0) + 1)
        e = self.edge(k, t) + extra
        left = self.hw[k].point(t, -e)
        right = self.hw[k].point(t, e)
        return shapely.Polygon(np.vstack([left, right[::-1]]))

    def _place(self, k, shapes, t, w, way):
        """A lane arrow (x to the driver's right, y ahead) on the ground at (t, w),
        pointing `way` along the highway (+1: toward +t)."""
        right = 1.0 if k == IA1 else -1.0  # which way w runs for a driver heading +t

        def ground(p):
            return self.hw[k].point(t + way * p[:, 1], w + way * right * p[:, 0])

        return [shapely.Polygon(ground(np.asarray(g.exterior.coords)), [ground(np.asarray(r.coords)) for r in g.interiors])
                for g in shapes]

    def _words(self, k, text, t, w, up):
        """Letters across a lane at (t, w), their tops toward `up` (+1: +w), reading to
        the right of someone facing that way; white with a black border."""
        glyphs, x = [], 0.0
        for ch in text:
            glyphs.extend(affinity.translate(g, x, 0.0) for g in LETTERS[ch])
            x += ADVANCE[ch]
        x -= LETTER_GAP
        along, across = 1.6, 2.4  # m per glyph unit along the lane (reading) and across it (up)
        # Facing +w on IA 1 (east), +t (north) is to your left; on IA 22 (facing north) to your right.
        read = (-up) if k == IA1 else up
        white, black = [], []
        for g in glyphs:
            def ground(p):
                return self.hw[k].point(t + read * (p[:, 0] - x / 2) * along, w + up * (p[:, 1] - 0.5) * across)

            poly = shapely.Polygon(ground(np.asarray(g.exterior.coords)), [ground(np.asarray(r.coords)) for r in g.interiors])
            white.append(poly)
            black.append(poly.buffer(0.09, join_style="mitre"))
        return white, black

    # --- Things standing by the road ---------------------------------------------------------

    def local(self, east, north):
        """A spot given in meters east and north of the junction's middle (true UTM axes)."""
        return self.center + np.array([east, -north])

    def stops(self):
        """Each way's STOP sign: (x, z, the way traffic comes, the crossing road's name)."""
        out = []
        for k, t, side in ((IA1, -STOP_LINE[IA1] - 1.0, 1.0), (IA1, STOP_LINE[IA1] + 1.0, -1.0),
                           (IA22, -STOP_LINE[IA22] - 1.0, -1.0), (IA22, STOP_LINE[IA22] + 1.0, 1.0)):
            h = self.hw[k]
            off = (LANE * 1.5 + 2.6) if k == IA1 else (PAVED + 2.0)
            p = h.point(np.array([t]), np.array([side * off]))[0]
            way = -math.copysign(1.0, t)  # traffic heads toward the middle
            fwd = (h.point(np.array([t + way]), np.array([0.0])) - h.point(np.array([t]), np.array([0.0])))[0]
            out.append({"at": p, "forward": fwd / np.linalg.norm(fwd), "street": "E Ave" if k == IA1 else "1st St"})
        return out

    def yields(self):
        """A YIELD sign on the outside of each turning lane where it joins the highway."""
        out = []
        for q, sl in self.slips.items():
            mid, outer, _ = self.slip_edges(q)
            arc_n = len(sl["arc"]) - 2
            n22 = len(sl[IA22]["t"])
            # The end of the curve on the side it joins.
            i = n22 + arc_n if sl["from"] == IA22 else n22 - 1
            j = i + 1 if sl["from"] == IA22 else i - 1
            fwd = mid[j] - mid[i]
            fwd /= np.linalg.norm(fwd)
            d = outer[i] - mid[i]
            d /= np.linalg.norm(d)
            out.append({"at": mid[i] + d * (SLIP_WIDTH / 2 + 1.2), "forward": fwd})
        return out

    def lights(self):
        out = []
        dirs = {"n": (0.0, 1.0), "s": (0.0, -1.0), "e": (1.0, 0.0), "w": (-1.0, 0.0)}
        shapely.prepare(self.paved)
        for east, north, arm in LIGHTS:
            p = self.local(east, north)
            d = np.array([dirs[arm][0], -dirs[arm][1]])
            # Off the pavement, if the layout put it on.
            for _ in range(20):
                if not shapely.contains_xy(self.paved, *p) and shapely.distance(self.paved, shapely.Point(p)) > 0.6:
                    break
                p = p - d * 0.5
            out.append({"at": p, "arm": d})
        return out

    def buggy(self):
        """Where the Amish buggy waits its turn: at the stop line on the crossing highway,
        on the side you see from the start (to your right)."""
        if self.own == IA1:  # the start faces north: IA 22's westbound lane, east of the middle
            k, t, w = IA22, STOP_LINE[IA22] + 1.0, LANE * 0.62
        else:  # the start faces west: IA 1's southbound lanes, north of the middle
            k, t, w = IA1, STOP_LINE[IA1] + 1.0, -LANE * 1.2
        h = self.hw[k]
        p = h.point(np.array([t]), np.array([w]))[0]
        q = h.point(np.array([t - 1.0]), np.array([w]))[0]
        fwd = (q - p) / np.linalg.norm(q - p)
        return {"at": p, "forward": fwd}

    # --- The ground under it ----------------------------------------------------------------------

    def terrain_changes(self, route: dict, heights: np.ndarray):
        """Ground vertices pulled down under and round the pavement: [[tile, vertex, height]]."""
        t = route["terrain"]
        size, grid = t["tile_size_m"], t["grid"]
        step = size / (grid - 1)
        reach = self.paved.buffer(TERRAIN_REACH)
        x0, z0, x1, z1 = reach.bounds
        shapely.prepare(self.paved)
        out = []
        for n, (a, b, _) in enumerate(t["tiles"]):
            if a * size > x1 or (a + 1) * size < x0 or b * size > z1 or (b + 1) * size < z0:
                continue
            lx, lz = np.meshgrid(np.arange(grid) * step + a * size, np.arange(grid) * step + b * size)
            xz = np.column_stack([lx.ravel(), lz.ravel()])
            near = shapely.contains_xy(reach, *xz.T)
            if not near.any():
                continue
            idx = np.nonzero(near)[0]
            p = xz[idx]
            pts = shapely.points(p)
            d = shapely.distance(self.paved, pts)
            inside = d <= 0.0
            ring = self.paved.exterior
            at = np.where(inside[:, None], p, shapely.get_coordinates(
                shapely.line_interpolate_point(ring, shapely.line_locate_point(ring, pts))))
            target = self.heights(at) - TERRAIN_BELOW + TERRAIN_RISE * d
            h = heights[n].ravel()[idx]
            lower = target < h
            for i, v in zip(idx[lower], target[lower]):
                out.append([n, int(i), round(float(v), 3)])
        return out

    # --- For the game ---------------------------------------------------------------------------

    def export(self, route: dict, terrain_heights: np.ndarray) -> dict:
        own = self.hw[self.own]
        sverts, stris = self.surface()
        stris = _clockwise(sverts, stris)
        joints = self._uv(sverts)
        bverts, bdys, bkinds, btris = self.bands()
        bh = _band_heights(self, bverts, bdys)
        shoulder = {"vertices": _xyz(bverts, bh)}
        for kind in ("gravel", "grass"):
            tri = np.array([t for t, kd in btris if kd == kind], dtype=int).reshape(-1, 3)
            shoulder[kind] = _clockwise(bverts, tri).ravel().tolist()
        paint = {}
        for color, polys in self.paint().items():
            v, tri = _triangulate(polys)
            paint[color] = {"vertices": _xyz(v, self.heights(v) + PAINT_LIFT), "indices": _clockwise(v, tri).ravel().tolist()}
        lo, hi = ENDS[self.own]

        def thing(d, **extra):
            return {"x": round(float(d["at"][0]), 2), "z": round(float(d["at"][1]), 2),
                    "y": round(float(self.heights(np.array([d["at"]]))[0]), 3), **extra}

        buggy = self.buggy()
        return {
            "name": "Kalona 4-way stop (IA 1 and IA 22)",
            "note": "game meters; written by tools/bake_streets.py (tools/junction.py)",
            "center": [round(float(self.center[0]), 3), round(float(own.pos(own.s0)[1]), 3), round(float(self.center[1]), 3)],
            "gap": [lo, hi],
            "start_lane": round(LANE if self.own == IA1 else LANE / 2, 2),
            # The middle of the right-hand lane every LANE_STEP m through the gap (IA 1's
            # through lanes shift out for the turn lanes; IA 22's don't).
            "lane_step": LANE_STEP,
            "lanes": [round(float(v), 3) for v in self._lane_middles(lo, hi)],
            "outline": [round(float(v), 2) for v in np.asarray(self.paved.exterior.coords)[:-1].ravel()],
            "concrete": {"vertices": _xyz(sverts, self.heights(sverts)), "joints": _flat(joints),
                         "indices": stris.ravel().tolist()},
            "shoulder": shoulder,
            "paint": paint,
            "stops": [thing(s, forward=_r(s["forward"]), street=s["street"]) for s in self.stops()],
            "yields": [thing(s, forward=_r(s["forward"])) for s in self.yields()],
            "lights": [thing(s, arm=_r(s["arm"])) for s in self.lights()],
            "buggy": thing(buggy, forward=_r(buggy["forward"])),
            "welcome_sign": {**thing({"at": self.local(*WELCOME_SIGN)}), "toward": [1.0, 0.0]},  # its point faces east
            "flagpole": thing({"at": self.local(*FLAGPOLE)}),
            "terrain": self.terrain_changes(route, terrain_heights),
        }

    def _lane_middles(self, lo, hi):
        s = np.arange(lo, hi + LANE_STEP / 2, LANE_STEP)
        if self.own == IA22:
            return np.full(s.shape, LANE / 2)
        t = (s - self.hw[IA1].s0) * self.hw[IA1].sense
        return LANE / 2 + LANE / 2 * self.turn_open(t)

    def _uv(self, xz):
        """Meters east and north of the middle along the two highways (for the concrete's joints),
        and which highway's joints show: 0 IA 1, 1 IA 22, 2 both (the middle), 3 none."""
        t1, w1 = self.hw[IA1].locate(xz)
        t22, w22 = self.hw[IA22].locate(xz)
        on1 = np.abs(w1) <= self.edge(IA1, t1) + 0.05
        on22 = np.abs(w22) <= PAVED + 0.05
        axis = np.where(on1 & on22, 2.0, np.where(on1, 0.0, np.where(on22, 1.0, 3.0)))
        return np.column_stack([w1, t1, w22, t22, axis])  # per vertex, for the shader


def _band_heights(j: Junction, verts: np.ndarray, dys: np.ndarray) -> np.ndarray:
    """Band vertices hang off the pavement's edge: each row's height is the edge point's
    (the first row of its group) plus the row's drop."""
    out = np.empty(len(verts))
    rows = len(SECTION) + 1
    start = 0
    for chain in j.chains().values():
        m = len(chain)
        edge = j.heights(chain)
        for r in range(rows):
            out[start + r * m:start + (r + 1) * m] = edge + dys[start + r * m:start + (r + 1) * m]
        start += rows * m
    return out


def _normals(chain: np.ndarray) -> np.ndarray:
    d = np.gradient(chain, axis=0)
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    n = np.column_stack([-d[:, 1], d[:, 0]])
    # A little smoothing, so tight bends don't fold the bands over.
    for _ in range(3):
        n[1:-1] = (n[:-2] + 2 * n[1:-1] + n[2:]) / 4
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    return n


def _index(coords: np.ndarray):
    """Triangles as (N, 3, 2) points -> shared vertices and index triples."""
    flat = coords.reshape(-1, 2)
    key = np.round(flat * 1000).astype(np.int64)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    verts = np.zeros((len(uniq), 2))
    verts[inv.ravel()] = flat
    tris = inv.reshape(-1, 3)
    return verts, tris


def _triangulate(polys) -> tuple[np.ndarray, np.ndarray]:
    tris = shapely.get_parts(shapely.constrained_delaunay_triangles(list(polys)))
    tris = tris[shapely.area(tris) > 1e-7]
    if len(tris) == 0:
        return np.zeros((0, 2)), np.zeros((0, 3), dtype=int)
    coords = shapely.get_coordinates(shapely.get_exterior_ring(tris)).reshape(-1, 4, 2)[:, :3]
    return _index(coords)


def _hatch(gore: shapely.Polygon, slip: dict, spacing=2.6, width=0.3) -> list:
    """Diagonal stripes across a gore, at 45 degrees to its curve's middle."""
    c = gore.centroid
    ang = math.atan2(c.y - slip["center"][1], c.x - slip["center"][0]) + math.pi / 4
    d = np.array([math.cos(ang), math.sin(ang)])
    n = np.array([-d[1], d[0]])
    r = math.hypot(*np.ptp(np.asarray(gore.exterior.coords), axis=0)) + 2
    inner = gore.buffer(-0.35)
    if inner.is_empty:
        return []
    out = []
    for k in np.arange(-r, r, spacing):
        mid = np.array([c.x, c.y]) + n * k
        s = shapely.LineString([mid - d * r, mid + d * r]).buffer(width / 2, cap_style="flat")
        g = s.intersection(inner)
        out.extend(p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05)
    return out


def _clockwise(xz: np.ndarray, tris: np.ndarray) -> np.ndarray:
    """Triangles turned so they face up in Godot (clockwise seen from above)."""
    tris = np.asarray(tris, dtype=int).reshape(-1, 3)
    if len(tris) == 0:
        return tris
    a, b, c = xz[tris[:, 0]], xz[tris[:, 1]], xz[tris[:, 2]]
    area = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1])
    out = tris.copy()
    flip = area < 0
    out[flip] = out[flip][:, [0, 2, 1]]
    return out


def _xyz(xz: np.ndarray, y: np.ndarray) -> list:
    return [round(float(v), 3) for v in np.column_stack([xz[:, 0], y, xz[:, 1]]).ravel()]


def _flat(a: np.ndarray) -> list:
    return [round(float(v), 2) for v in a.ravel()]


def _r(v) -> list:
    return [round(float(v[0]), 4), round(float(v[1]), 4)]


# --- Glyphs: x across, y along the way the arrow points (m) ------------------------------------

def _arrow_left():
    shaft = shapely.LineString([(0.0, -2.6), (0.0, 0.3), (-0.25, 0.95), (-0.75, 1.25)]).buffer(0.15, cap_style="flat")
    head = shapely.Polygon([(-0.7, 1.75), (-0.7, 0.75), (-1.45, 1.25)])
    return [shapely.union_all([shaft, head])]


def _arrow_straight_right():
    shaft = shapely.LineString([(0.0, -2.6), (0.0, 1.4)]).buffer(0.15, cap_style="flat")
    head = shapely.Polygon([(-0.45, 1.3), (0.45, 1.3), (0.0, 2.4)])
    branch = shapely.LineString([(0.0, -0.4), (0.25, 0.2), (0.75, 0.45)]).buffer(0.15, cap_style="flat")
    head2 = shapely.Polygon([(0.7, 0.95), (0.7, -0.05), (1.45, 0.45)])
    return [shapely.union_all([shaft, head, branch, head2])]


ARROWS = {"left": _arrow_left(), "straight_right": _arrow_straight_right()}

# Block letters, x along the reading direction and y up, in a unit tall cell.
LETTER_GAP = 0.18


def _letters():
    s = 0.2  # stroke
    I = [shapely.box(0.0, 0.0, s * 1.15, 1.0)]
    A = [shapely.Polygon([(0, 0), (0.2, 0), (0.25, 0.27), (0.53, 0.27), (0.58, 0), (0.78, 0), (0.5, 1), (0.28, 1)],
                         [[(0.29, 0.43), (0.49, 0.43), (0.39, 0.82)]])]
    dash = [shapely.box(0.04, 0.42, 0.36, 0.58)]
    one = [shapely.Polygon([(0.24, 0), (0.46, 0), (0.46, 1), (0.3, 1), (0.02, 0.8), (0.08, 0.66), (0.24, 0.76)])]
    two = [shapely.union_all([
        shapely.LineString([(0.12, 0.74), (0.2, 0.9), (0.38, 0.96), (0.56, 0.88), (0.6, 0.7), (0.52, 0.55),
                            (0.12, 0.16)]).buffer(s / 2, cap_style="flat", join_style="round"),
        shapely.box(0.02, 0.0, 0.7, s)])]
    return {"I": I, "A": A, "-": dash, "1": one, "2": two}


LETTERS = _letters()
ADVANCE = {ch: max(shapely.bounds(g)[2] for g in gs) + LETTER_GAP for ch, gs in LETTERS.items()}
