"""Render the baked route so a human can sanity-check it.

    python tools/preview_route.py [--route=<id>]

Reads game/data/routes/<id>/ and writes route-map.png and route-profile.png to the
route's preview folder (docs/route-preview/ for Highway 1).
"""

from __future__ import annotations

import json

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import config

MILE_M = 1609.344
FT_PER_M = 3.28084


def load():
    route = json.loads((config.OUT_DIR / "route.json").read_text())
    t = route["terrain"]
    heights = np.fromfile(config.OUT_DIR / t["file"], dtype="<f4").reshape(-1, t["grid"], t["grid"])
    return route, heights


def mosaic(route, heights):
    """Stitch terrain tiles into one north-up image (NaN where there's no tile)."""
    t = route["terrain"]
    tiles = np.array([tile[:2] for tile in t["tiles"]])
    cells = t["grid"] - 1
    ix0, iz0 = tiles.min(axis=0)
    ix1, iz1 = tiles.max(axis=0) + 1
    img = np.full(((iz1 - iz0) * cells + 1, (ix1 - ix0) * cells + 1), np.nan, dtype=np.float32)
    for (ix, iz), h in zip(tiles, heights):
        r, c = (iz - iz0) * cells, (ix - ix0) * cells
        img[r:r + cells + 1, c:c + cells + 1] = h
    size = t["tile_size_m"]
    extent = (ix0 * size, ix1 * size, -iz1 * size, -iz0 * size)  # x east, y north
    return img, extent


def hillshade(z, res):
    gy, gx = np.gradient(np.nan_to_num(z, nan=np.nanmean(z)), res)
    slope = np.arctan(np.hypot(gx, gy) * 2.5)
    aspect = np.arctan2(-gx, gy)
    az, alt = np.radians(315), np.radians(45)
    shade = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    return np.where(np.isnan(z), np.nan, shade)


def mile_of(route, station):
    return (station - route["start_station"]) / MILE_M


def draw_map(route, heights):
    pts = np.array(route["points"]).reshape(-1, 3)
    img, extent = mosaic(route, heights)
    res = route["terrain"]["tile_size_m"] / (route["terrain"]["grid"] - 1)

    fig, ax = plt.subplots(figsize=(10, 12), dpi=120)
    ax.imshow(img, extent=extent, origin="upper", cmap="YlGn_r", alpha=0.55)
    ax.imshow(hillshade(img, res), extent=extent, origin="upper", cmap="gray", alpha=0.45)
    ax.plot(pts[:, 0], -pts[:, 2], color="#d62728", lw=2.2, zorder=5)

    spacing = route["spacing_m"]
    for mile in range(0, int(mile_of(route, len(pts) * spacing)) + 1):
        i = int((route["start_station"] + mile * MILE_M) / spacing)
        if i < len(pts):
            ax.plot(pts[i, 0], -pts[i, 2], "o", ms=4, color="black", zorder=6)
            ax.annotate(f"{mile}", (pts[i, 0], -pts[i, 2]), xytext=(-14, -3), textcoords="offset points",
                        fontsize=7, weight="bold")
    for j in route["crossroads"]:
        if j["kind"] == "ramp":
            continue
        i = int(j["station"] / spacing)
        ax.annotate(j["name"], (pts[i, 0], -pts[i, 2]), xytext=(6, 0), textcoords="offset points",
                    fontsize=6, color="#1f3b73", va="center")
    for label, s in ((f"START  {config.START_LABEL}", route["start_station"]),
                     (f"FINISH  {config.FINISH_LABEL}", route["finish_station"])):
        i = int(s / spacing)
        ax.plot(pts[i, 0], -pts[i, 2], "s", ms=8, color="#111", zorder=7)
        ax.annotate(label, (pts[i, 0], -pts[i, 2]), xytext=(8, -12), textcoords="offset points",
                    fontsize=9, weight="bold")

    ax.set_title(f"{route['name']}: {mile_of(route, route['finish_station']):.2f} mi, black dots = miles")
    ax.set_xlabel("meters east of origin")
    ax.set_ylabel("meters north of origin")
    ax.set_aspect("equal")
    fig.savefig(config.PREVIEW_DIR / "route-map.png", bbox_inches="tight")
    plt.close(fig)


def draw_profile(route):
    pts = np.array(route["points"]).reshape(-1, 3)
    spacing = route["spacing_m"]
    miles = mile_of(route, np.arange(len(pts)) * spacing)
    elev_ft = (pts[:, 1] + route["origin"]["elevation_m"]) * FT_PER_M

    fig, ax = plt.subplots(figsize=(16, 5), dpi=110)
    ax.fill_between(miles, elev_ft.min() - 30, elev_ft, color="#8fbf6f")
    ax.plot(miles, elev_ft, color="#333", lw=1)
    for b0, b1 in route["bridges"]:
        ax.axvspan(mile_of(route, b0), mile_of(route, b1), color="#3a7bd5", alpha=0.5)
    top = elev_ft.max() + 10
    for j in route["crossroads"]:
        if j["kind"] == "ramp":
            continue
        m = mile_of(route, j["station"])
        ax.axvline(m, color="#999", lw=0.5)
        ax.text(m, top, j["name"], rotation=90, fontsize=6, va="bottom", ha="center")
    for s in (route["start_station"], route["finish_station"]):
        ax.axvline(mile_of(route, s), color="black", lw=1.5)
    ax.set_xlim(miles[0], miles[-1])
    ax.set_ylim(elev_ft.min() - 30, top + 120)
    ax.set_xlabel(f"miles from the start line in {config.START_LABEL} (blue = bridge/culvert filled in)")
    ax.set_ylabel("road elevation (ft)")
    fig.savefig(config.PREVIEW_DIR / "route-profile.png", bbox_inches="tight")
    plt.close(fig)


def main():
    import sys
    config.use_args(sys.argv)
    config.PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    route, heights = load()
    draw_map(route, heights)
    draw_profile(route)
    print(f"wrote {config.PREVIEW_DIR}/route-map.png and route-profile.png")


if __name__ == "__main__":
    main()
