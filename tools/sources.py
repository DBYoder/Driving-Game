"""Downloading and reading the raw USGS data. Results are cached under tools/.cache/."""

from __future__ import annotations

import shutil
import urllib.request
import zipfile
from dataclasses import dataclass, field

import numpy as np
import pyogrio
import rasterio
from affine import Affine
import shapely
from rasterio.warp import Resampling, reproject, transform_bounds
from rasterio.transform import from_origin
from rasterio.windows import from_bounds

import config
from geo import GridSampler


@dataclass
class Road:
    name: str
    mtfcc: str
    state_routes: set[str]
    us_routes: set[str]
    county_routes: set[str] = field(default_factory=set)
    lines: list[np.ndarray] = field(default_factory=list)  # lon/lat


def ntd_gpkg():
    """Path to the cached Iowa National Transportation Dataset, downloading it once (~190 MB)."""
    out_dir = config.CACHE_DIR / "ntd"
    gpkgs = list(out_dir.glob("*.gpkg"))
    if gpkgs:
        return gpkgs[0]
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / "ntd.zip"
    print(f"downloading {config.NTD_URL}")
    with urllib.request.urlopen(config.NTD_URL) as resp, open(zip_path, "wb") as f:
        shutil.copyfileobj(resp, f)
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.endswith(".gpkg")]
        z.extract(names[0], out_dir)
    zip_path.unlink()
    return out_dir / names[0]


def read_roads(bbox) -> list[Road]:
    meta, _, geoms, fields = pyogrio.raw.read(ntd_gpkg(), layer=config.NTD_LAYER, bbox=bbox)
    col = {n: i for i, n in enumerate(meta["fields"])}

    def vals(i, *names):
        return {fields[col[n]][i] for n in names} - {None, ""}

    roads = []
    for i, wkb in enumerate(geoms):
        geom = shapely.from_wkb(wkb)
        parts = getattr(geom, "geoms", [geom])
        name = fields[col["name"]][i] or ""
        roads.append(Road(
            name=config.NAME_FIXES.get(name, name),
            mtfcc=fields[col["mtfcc_code"]][i] or "",
            state_routes=vals(i, "state_route", "state_route_a", "state_route_b", "state_route_c"),
            us_routes=vals(i, "us_route", "us_route_a", "us_route_b", "us_route_c"),
            county_routes=vals(i, "county_route"),
            lines=[np.asarray(p.coords)[:, :2] for p in parts if len(p.coords) >= 2],
        ))
    return roads


def dem_sampler(west: float, south: float, east: float, north: float,
                res: float = config.DEM_RES_M, decimate: int = 1) -> GridSampler:
    """Elevation (meters) sampler over a UTM box, warped from the 1/3 arc-second 3DEP tile.

    Only the needed window is fetched over HTTP (the tile is a cloud-optimized GeoTIFF),
    then cached as .npz so re-bakes are offline. `decimate` reads one of the file's
    overviews instead of full resolution, for coarse output over big areas.
    """
    west, south = np.floor(west / res) * res, np.floor(south / res) * res
    east, north = np.ceil(east / res) * res, np.ceil(north / res) * res
    cache = config.CACHE_DIR / f"dem_{int(west)}_{int(south)}_{int(east)}_{int(north)}_{res:g}.npz"
    if cache.exists():
        z = np.load(cache)
        return GridSampler(z["data"], float(z["west"]), float(z["north"]), res)

    print(f"reading elevation window from {config.DEM_URL}")
    lon0, lat0, lon1, lat1 = transform_bounds(config.UTM_CRS, config.GEO_CRS, west, south, east, north)
    with rasterio.open("/vsicurl/" + config.DEM_URL) as ds:
        window = from_bounds(lon0 - 0.005, lat0 - 0.005, lon1 + 0.005, lat1 + 0.005, ds.transform)
        window = window.round_offsets().round_lengths()
        shape = (int(window.height) // decimate, int(window.width) // decimate)
        src = ds.read(1, window=window, out_shape=shape, resampling=Resampling.average).astype(np.float32)
        src_transform = ds.window_transform(window) * Affine.scale(
            window.width / shape[1], window.height / shape[0])
        src_crs = ds.crs
    cols, rows = int((east - west) / res), int((north - south) / res)
    dst = np.full((rows, cols), np.nan, dtype=np.float32)
    reproject(
        src, dst,
        src_transform=src_transform, src_crs=src_crs,
        dst_transform=from_origin(west, north, res, res), dst_crs=config.UTM_CRS,
        resampling=Resampling.bilinear,
    )
    if np.isnan(dst).any():
        raise RuntimeError("elevation window has holes; widen the read window")
    config.CACHE_DIR.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(cache, data=dst, west=west, north=north)
    return GridSampler(dst, west, north, res)
