"""Real names along the route, for the signs.

    python tools/bake_places.py      (after bake_route.py)

Writes game/data/route/places.json: where IA 1 crosses each named creek (USGS National
Hydrography Dataset), enters and leaves each city (with its population) and crosses
the county line (USGS Governmental Units), as stations along the route; and the city
limits near the road ("towns", game x/z outlines), where there are lawns, not crops.
"""

from __future__ import annotations

import json
import shutil
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
import pyogrio
import shapely
from pyproj import Transformer

import config

NHD_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Hydrography/NHD/HU8/GPKG/NHD_H_{}_HU8_GPKG.zip"
NHD_HU8 = ["07080208", "07080209"]  # English River; Iowa River below Iowa City (Old Mans Creek)
GOVT_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/GovtUnit/GPKG/GOVTUNIT_Iowa_State_GPKG.zip"
STREAM_FTYPES = {460}  # StreamRiver


def cached_gpkg(url: str, folder: str) -> Path:
    out_dir = config.CACHE_DIR / folder
    name = url.rsplit("/", 1)[-1].replace(".zip", ".gpkg")
    path = out_dir / name
    if path.exists():
        return path
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / "download.zip"
    print(f"downloading {url}")
    with urllib.request.urlopen(url) as resp, open(zip_path, "wb") as f:
        shutil.copyfileobj(resp, f)
    with zipfile.ZipFile(zip_path) as z:
        member = next(n for n in z.namelist() if n.endswith(".gpkg"))
        z.extract(member, out_dir)
        (out_dir / member).rename(path)
    zip_path.unlink()
    return path


def crossings(route: shapely.LineString, geom) -> list[float]:
    """Stations (meters along `route`) where it crosses `geom`'s lines or boundary."""
    hits = route.intersection(geom)
    pts = [g for g in getattr(hits, "geoms", [hits]) if not g.is_empty]
    out = []
    for g in pts:
        for p in (getattr(g, "geoms", None) or [g]):
            if p.geom_type == "Point":
                out.append(route.project(p))
            else:  # runs along it for a while: take the middle
                out.append(route.project(p.interpolate(0.5, normalized=True)))
    return sorted(out)


def merge_close(items: list[dict], key: str, gap: float) -> list[dict]:
    """Drop repeats of the same name within `gap` meters (a creek's braids, a jagged boundary)."""
    out: list[dict] = []
    for it in sorted(items, key=lambda d: d["station"]):
        if out and out[-1][key] == it[key] and it["station"] - out[-1]["station"] < gap:
            continue
        out.append(it)
    return out


def main():
    route_json = json.loads((config.OUT_DIR / "route.json").read_text())
    o = route_json["origin"]
    pts = np.array(route_json["points"]).reshape(-1, 3)
    xy = np.column_stack([pts[:, 0] + o["easting"], o["northing"] - pts[:, 2]])
    route = shapely.LineString(xy)
    to_utm = Transformer.from_crs(config.GEO_CRS, config.UTM_CRS, always_xy=True)
    to_utm_geom = lambda g: shapely.transform(g, lambda c: np.column_stack(to_utm.transform(c[:, 0], c[:, 1])))
    lon0, lat0, lon1, lat1 = config.ROAD_BBOX

    creeks = []
    for hu in NHD_HU8:
        gpkg = cached_gpkg(NHD_URL.format(hu), "nhd")
        meta, _, geoms, fields = pyogrio.raw.read(gpkg, layer="NHDFlowline", bbox=(lon0, lat0, lon1, lat1),
                                                  columns=["gnis_name", "ftype"])
        for wkb, name, ftype in zip(geoms, fields[0], fields[1]):
            if not name or int(ftype) not in STREAM_FTYPES:
                continue
            line = to_utm_geom(shapely.force_2d(shapely.from_wkb(wkb)))
            for s in crossings(route, line):
                creeks.append({"station": round(float(s), 1), "name": str(name)})
    creeks = merge_close(creeks, "name", 200.0)

    govt = cached_gpkg(GOVT_URL, "govt")
    cities = []
    towns = []
    near = route.buffer(config.CORRIDOR_HALF_WIDTH_M)
    meta, _, geoms, fields = pyogrio.raw.read(govt, layer="GU_IncorporatedPlace", bbox=(lon0, lat0, lon1, lat1),
                                              columns=["PLACE_NAME", "POPULATION"])
    for wkb, name, pop in zip(geoms, fields[0], fields[1]):
        area = to_utm_geom(shapely.from_wkb(wkb))
        for s in crossings(route, area.boundary):
            ahead = route.interpolate(s + 5.0)
            cities.append({"station": round(float(s), 1), "name": str(name), "population": int(pop or 0),
                           "entering": bool(area.contains(ahead))})
        part = area.intersection(near).simplify(4.0)
        for poly in getattr(part, "geoms", [part]):
            if poly.geom_type == "Polygon" and poly.area > 1000.0:
                ring = np.asarray(poly.exterior.coords)[:-1]
                towns.append({"name": str(name), "outline": [round(float(v), 1) for e, n in ring
                                                             for v in (e - o["easting"], o["northing"] - n)]})
    cities = merge_close(cities, "name", 50.0)

    counties = []
    meta, _, geoms, fields = pyogrio.raw.read(govt, layer="GU_CountyOrEquivalent", bbox=(lon0, lat0, lon1, lat1),
                                              columns=["COUNTY_NAME"])
    shapes = [(str(n), to_utm_geom(shapely.from_wkb(w))) for w, n in zip(geoms, fields[0])]
    for name, area in shapes:
        for s in crossings(route, area.boundary):
            ahead, behind = route.interpolate(s + 20.0), route.interpolate(max(s - 20.0, 0.0))
            if area.contains(ahead) and not area.contains(behind):
                left = next((n for n, a in shapes if a.contains(behind)), "")
                counties.append({"station": round(float(s), 1), "entering": name, "leaving": left})

    out = {
        "sources": [
            "USGS National Hydrography Dataset (NHD), public domain",
            "USGS National Boundary Dataset (Governmental Units), public domain",
        ],
        "creeks": creeks,
        "cities": cities,
        "counties": counties,
        "towns": towns,
    }
    (config.OUT_DIR / "places.json").write_text(json.dumps(out, indent=1))
    start = route_json["start_station"]
    for c in creeks:
        print(f"creek  mile {(c['station'] - start) / 1609.344:6.2f}  {c['name']}")
    for c in cities:
        print(f"city   mile {(c['station'] - start) / 1609.344:6.2f}  {'enter' if c['entering'] else 'leave'} {c['name']} (pop {c['population']})")
    for c in counties:
        print(f"county mile {(c['station'] - start) / 1609.344:6.2f}  {c['leaving']} -> {c['entering']}")


if __name__ == "__main__":
    main()
