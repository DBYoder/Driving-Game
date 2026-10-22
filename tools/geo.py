"""Pure geometry helpers for the route bake.

No file or network I/O lives here, so everything is easy to unit-test.
Coordinates are planar meters (UTM) unless a function says otherwise.
"""

from __future__ import annotations

import math

import networkx as nx
import numpy as np


def cumulative_length(xy: np.ndarray) -> np.ndarray:
    """Arc length at each vertex of a polyline, starting at 0."""
    seg = np.hypot(*np.diff(xy, axis=0).T)
    return np.concatenate([[0.0], np.cumsum(seg)])


def dedupe(xy: np.ndarray, tol: float = 1e-6) -> np.ndarray:
    """Drop consecutive duplicate vertices (zero-length segments break interpolation)."""
    keep = np.concatenate([[True], np.hypot(*np.diff(xy, axis=0).T) > tol])
    return xy[keep]


def resample(xy: np.ndarray, spacing: float) -> np.ndarray:
    """Points every `spacing` meters along a polyline, starting at its first vertex.

    Stations are exact multiples of `spacing`; any leftover shorter than one
    step at the end is dropped so that index * spacing == station everywhere.
    """
    xy = dedupe(np.asarray(xy, dtype=float))
    s = cumulative_length(xy)
    n = int(math.floor(s[-1] / spacing + 1e-9)) + 1
    t = np.arange(n) * spacing
    return np.column_stack([np.interp(t, s, xy[:, i]) for i in range(xy.shape[1])])


def _odd_pad(values: np.ndarray, n: int) -> np.ndarray:
    """Point-reflect the ends (2*v0 - v[k]) so straight lines and grades survive smoothing."""
    head = 2 * values[0] - values[n:0:-1]
    tail = 2 * values[-1] - values[-2:-n - 2:-1]
    return np.concatenate([head, values, tail])


def gaussian_smooth(values: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian smoothing along axis 0, with sigma given in samples.

    Uses odd reflection at the ends, so the endpoints stay put and a straight
    line (or a constant grade) comes back unchanged.
    """
    values = np.asarray(values, dtype=float)
    if sigma <= 0 or len(values) < 3:
        return values.copy()
    radius = min(int(math.ceil(3 * sigma)), len(values) - 1)
    k = np.arange(-radius, radius + 1)
    kernel = np.exp(-0.5 * (k / sigma) ** 2)
    kernel /= kernel.sum()
    cols = values.reshape(len(values), -1)
    out = np.empty_like(cols)
    for c in range(cols.shape[1]):
        out[:, c] = np.convolve(_odd_pad(cols[:, c], radius), kernel, mode="valid")
    return out.reshape(values.shape)


def fill_dips(values: np.ndarray, window: int) -> np.ndarray:
    """Morphological closing (max filter, then min filter) over `window` samples.

    The bare-earth elevation model has bridges removed, so a creek crossing shows
    up as a sharp, narrow dip under the road. Closing fills dips narrower than the
    window and leaves broader valleys (which the real road does follow) alone.
    """
    from scipy.ndimage import grey_closing

    return grey_closing(np.asarray(values, dtype=float), size=window, mode="nearest")


def runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """(start, end_exclusive) index pairs for each contiguous True run."""
    m = np.concatenate([[False], np.asarray(mask, dtype=bool), [False]])
    edges = np.flatnonzero(np.diff(m.astype(np.int8)))
    return list(zip(edges[0::2], edges[1::2]))


def no_passing(xy: np.ndarray, z: np.ndarray, spacing: float, sight: float = 275.0,
               eye: float = 1.08, clear_width: float = 12.0) -> np.ndarray:
    """Per sample, True where a driver heading toward increasing index can't see `sight`
    meters of road ahead: over a crest (an eye 1.08 m up can't see a car 1.08 m up that
    far away) or around a bend (the road strays more than `clear_width` from the
    straight line of sight, into the corn). 275 m is the MUTCD passing sight distance
    for 55 mph. For the other direction, pass the arrays reversed.
    """
    n = len(z)
    k = int(round(sight / spacing))
    blocked = np.ones(n, dtype=bool)  # the last `k` samples can't see far enough anyway
    if n <= k:
        return blocked
    t = np.arange(1, k) / k  # fractions along each sight line
    for i in range(n - k):
        j = i + k
        line = (z[i] + eye) + (z[j] - z[i]) * t
        crest = np.any(z[i + 1:j] > line)
        a, b = xy[i], xy[j]
        ab = b - a
        rel = xy[i + 1:j] - a
        off = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / max(np.hypot(*ab), 1e-9)
        blocked[i] = crest or off.max() > clear_width
    return blocked


def zones(mask: np.ndarray, spacing: float, min_length: float) -> list[list[float]]:
    """True runs of `mask` as [from, to] stations; runs shorter than `min_length` are
    stretched (around their middle) to that length, and overlapping runs merged."""
    out = []
    for i0, i1 in runs(mask):
        s0, s1 = i0 * spacing, i1 * spacing
        if s1 - s0 < min_length:
            mid = (s0 + s1) / 2
            s0, s1 = mid - min_length / 2, mid + min_length / 2
        s0, s1 = max(s0, 0.0), min(s1, (len(mask) - 1) * spacing)
        if out and s0 <= out[-1][1]:
            out[-1][1] = max(out[-1][1], s1)
        else:
            out.append([s0, s1])
    return [[round(a, 1), round(b, 1)] for a, b in out]


def headings(xy: np.ndarray) -> np.ndarray:
    """Unit tangent at each point (central differences)."""
    t = np.gradient(xy, axis=0)
    return t / np.linalg.norm(t, axis=1, keepdims=True)


def side_of(tangent: np.ndarray, origin: np.ndarray, point: np.ndarray) -> str:
    """'left' or 'right' of travel direction, for planar x=east, y=north."""
    v = point - origin
    cross = tangent[0] * v[1] - tangent[1] * v[0]
    return "left" if cross > 0 else "right"


class GridSampler:
    """Bilinear sampling of a north-up raster whose pixel (0, 0) top-left corner is (west, north)."""

    def __init__(self, data: np.ndarray, west: float, north: float, res: float):
        self.data = np.asarray(data, dtype=float)
        self.west, self.north, self.res = west, north, res

    def __call__(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)
        rows, cols = self.data.shape
        c = np.clip((x - self.west) / self.res - 0.5, 0, cols - 1.000001)
        r = np.clip((self.north - y) / self.res - 0.5, 0, rows - 1.000001)
        c0, r0 = np.floor(c).astype(int), np.floor(r).astype(int)
        fc, fr = c - c0, r - r0
        d = self.data
        top = d[r0, c0] * (1 - fc) + d[r0, c0 + 1] * fc
        bot = d[r0 + 1, c0] * (1 - fc) + d[r0 + 1, c0 + 1] * fc
        return top * (1 - fr) + bot * fr


def build_graph(lines: list[np.ndarray], snap: float = 0.1) -> nx.Graph:
    """Undirected graph whose edges are polylines joined at shared endpoints."""
    def key(p):
        return (round(p[0] / snap) * snap, round(p[1] / snap) * snap)

    g = nx.Graph()
    for ln in lines:
        a, b = key(ln[0]), key(ln[-1])
        if a == b:
            continue
        length = cumulative_length(ln)[-1]
        if g.has_edge(a, b) and g[a][b]["length"] <= length:
            continue
        g.add_edge(a, b, length=length, coords=ln, start=a)
    return g


def nearest_node(g: nx.Graph, xy) -> tuple:
    nodes = np.array(list(g.nodes))
    i = int(np.argmin(np.hypot(nodes[:, 0] - xy[0], nodes[:, 1] - xy[1])))
    return tuple(nodes[i])


def path_polyline(g: nx.Graph, a: tuple, b: tuple) -> np.ndarray:
    """Shortest path between two nodes, stitched into one correctly-oriented polyline."""
    nodes = nx.shortest_path(g, a, b, weight="length")
    parts = []
    for u, v in zip(nodes, nodes[1:]):
        e = g[u][v]
        coords = e["coords"] if e["start"] == u else e["coords"][::-1]
        parts.append(coords if not parts else coords[1:])
    return np.vstack(parts)
