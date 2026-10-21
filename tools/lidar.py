"""Reading USGS 3DEP lidar point clouds from the public Entwine Point Tile (EPT) copy on AWS.

An EPT dataset is an octree of LAZ files: each node holds a thinned sample of the points
in its cube, and the children refine it. Asking for every node down to some depth over
an area gives an even sample of the points there, about 4x denser per level. Only the
hierarchy pages and nodes that touch the area are fetched, and the nodes are cached
under tools/.cache/ept/ so re-bakes are offline.
"""

from __future__ import annotations

import http.client
import io
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass

import laspy
import numpy as np
from pyproj import Transformer

import config


@dataclass
class Points:
    """Points in UTM (config.UTM_CRS) meters."""
    x: np.ndarray
    y: np.ndarray
    z: np.ndarray
    classification: np.ndarray  # ASPRS: 1 unclassified, 2 ground, 7/18 noise, 9 water...
    return_number: np.ndarray
    number_of_returns: np.ndarray

    def __len__(self) -> int:
        return len(self.x)

    def take(self, mask: np.ndarray) -> "Points":
        return Points(*(a[mask] for a in (self.x, self.y, self.z, self.classification,
                                            self.return_number, self.number_of_returns)))


def _fetch(url: str) -> bytes:
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=120) as resp:
                return resp.read()
        except (OSError, http.client.HTTPException):  # dropped connections, cut-off bodies
            if attempt == 4:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError


class EptReader:
    def __init__(self, base_url: str = config.LIDAR_EPT_URL):
        self.base = base_url.rstrip("/") + "/"
        self.cache = config.CACHE_DIR / "ept" / self.base.rstrip("/").rsplit("/", 1)[-1]
        self.cache.mkdir(parents=True, exist_ok=True)
        meta = self.cache / "ept.json"
        if not meta.exists():
            meta.write_bytes(_fetch(self.base + "ept.json"))
        info = json.loads(meta.read_text())
        self.bounds = info["bounds"]  # the root cube, in the dataset's CRS
        self.crs = "EPSG:" + str(info["srs"]["horizontal"])
        self._counts: dict[str, int] = {}
        self._pages = {"0-0-0-0"}  # hierarchy pages known to exist but not read yet
        self.to_native = Transformer.from_crs(config.UTM_CRS, self.crs, always_xy=True)
        self.to_utm = Transformer.from_crs(self.crs, config.UTM_CRS, always_xy=True)

    def _count(self, key: str) -> int:
        if key in self._counts:
            return self._counts[key]
        if key in self._pages:
            self._pages.discard(key)
            path = self.cache / f"h-{key}.json"
            if not path.exists():
                path.write_bytes(_fetch(self.base + f"ept-hierarchy/{key}.json"))
            for k, n in json.loads(path.read_text()).items():
                if n == -1:
                    self._pages.add(k)
                else:
                    self._counts[k] = n
        return self._counts.get(key, 0)

    def _node_box(self, key: str):
        d, x, y, _ = map(int, key.split("-"))
        w = (self.bounds[3] - self.bounds[0]) / 2 ** d
        return self.bounds[0] + x * w, self.bounds[1] + y * w, self.bounds[0] + (x + 1) * w, self.bounds[1] + (y + 1) * w

    def nodes(self, box, depth: int) -> list[str]:
        """Keys of the nodes down to `depth` that overlap a native-CRS (x0, y0, x1, y1) box."""
        out, stack = [], ["0-0-0-0"]
        while stack:
            key = stack.pop()
            x0, y0, x1, y1 = self._node_box(key)
            if x1 < box[0] or x0 > box[2] or y1 < box[1] or y0 > box[3] or not self._count(key):
                continue
            out.append(key)
            d, x, y, z = map(int, key.split("-"))
            if d < depth:
                stack += [f"{d + 1}-{2 * x + i}-{2 * y + j}-{2 * z + k}" for i in (0, 1) for j in (0, 1) for k in (0, 1)]
        return out

    def _node_bytes(self, key: str) -> bytes:
        path = self.cache / f"{key}.laz"
        if not path.exists():
            data = _fetch(self.base + f"ept-data/{key}.laz")
            tmp = path.with_suffix(".part")
            tmp.write_bytes(data)
            tmp.replace(path)
        return path.read_bytes()

    def prefetch(self, keys: list[str], threads: int = 16) -> None:
        with ThreadPoolExecutor(threads) as pool:
            list(pool.map(self._node_bytes, keys))

    def read(self, west: float, south: float, east: float, north: float, depth: int) -> Points:
        """All points down to `depth` inside a UTM box."""
        xs, ys = self.to_native.transform([west, east, west, east], [south, south, north, north])
        keys = self.nodes((min(xs), min(ys), max(xs), max(ys)), depth)
        self.prefetch(keys)
        parts = []
        for key in keys:
            las = laspy.read(io.BytesIO(self._node_bytes(key)))
            x, y = self.to_utm.transform(np.asarray(las.x), np.asarray(las.y))
            keep = (x >= west) & (x < east) & (y >= south) & (y < north)
            if keep.any():
                parts.append((x[keep], y[keep], np.asarray(las.z)[keep],
                              np.asarray(las.classification)[keep], np.asarray(las.return_number)[keep],
                              np.asarray(las.number_of_returns)[keep]))
        if not parts:
            e = np.empty(0)
            return Points(e, e, e, e.astype(np.uint8), e.astype(np.uint8), e.astype(np.uint8))
        return Points(*(np.concatenate(cols) for cols in zip(*parts)))
