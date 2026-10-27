"""Aerial photographs of the route, from USGS US Topo maps (public domain).

The 2015 US Topo GeoPDFs carry an orthoimage layer: USDA NAIP aerial photography, cut
into 1024 px tiles at about 1.5 m a pixel. The layer is off by default (and PDF renderers
here don't show it), so the tiles are read straight out of the PDF: the page's content
draws them in one form, each with its own placement, and the map's georeferencing (the
TerraGo LGIDict) turns the page into NAD83 / UTM 15N, the game data's own projection.

    imagery = Aerial.for_quads(["Kalona", "Frytown"])
    rgb = imagery.render(west, south, east, north, meters_per_pixel)  # north up, black off the maps
    rgba = imagery.sample(east, north)                                # per point; alpha 0 off the maps

The PDFs are downloaded once into tools/.cache/ustopo/ (15-22 MB each).
"""

from __future__ import annotations

import io
import re
import urllib.request
from pathlib import Path

import numpy as np

import config

USTOPO_BUCKET = "https://prd-tnm.s3.amazonaws.com"
USTOPO_PREFIX = "StagedProducts/Maps/USTopo/PDF/IA/"
EDITION = "2015"  # the last edition with the orthoimage in it (2018 and later have none)


def download(quad: str) -> Path:
    """The quad's 2015 US Topo PDF (cached)."""
    cache = config.CACHE_DIR / "ustopo"
    cache.mkdir(parents=True, exist_ok=True)
    found = sorted(cache.glob(f"IA_{quad}_{EDITION}*.pdf"))
    if found:
        return found[-1]
    listing = urllib.request.urlopen(
        f"{USTOPO_BUCKET}/?list-type=2&prefix={USTOPO_PREFIX}IA_{quad}_{EDITION}", timeout=60).read().decode()
    keys = re.findall(r"<Key>([^<]*_geo\.pdf)</Key>", listing)
    if not keys:
        raise FileNotFoundError(f"no {EDITION} US Topo map for {quad}")
    path = cache / keys[-1].rsplit("/", 1)[-1]
    print(f"downloading {path.name}")
    path.write_bytes(urllib.request.urlopen(f"{USTOPO_BUCKET}/{keys[-1]}", timeout=600).read())
    return path


def _numbers(text: str) -> list[float]:
    return [float(x) for x in re.findall(r"\(([-0-9.eE+]+)\)", text)]


class Tile:
    """One image tile: pixel (column, row) -> UTM by `to_utm` (a 2x3 affine), and back."""

    def __init__(self, doc, xref: int, width: int, height: int, to_utm: np.ndarray, mask_xref: int | None):
        self.doc, self.xref, self.width, self.height = doc, xref, width, height
        self.to_utm = to_utm
        m = np.vstack([to_utm, [0, 0, 1]])
        self.from_utm = np.linalg.inv(m)[:2]
        self.mask_xref = mask_xref
        self._rgb = None
        corners = np.array([[0, 0, 1], [width, 0, 1], [width, height, 1], [0, height, 1]], float) @ to_utm.T
        self.bounds = (corners[:, 0].min(), corners[:, 1].min(), corners[:, 0].max(), corners[:, 1].max())

    def rgb(self) -> np.ndarray:
        """The tile's pixels, height x width x 4 (alpha 0 where the map masks it off)."""
        if self._rgb is None:
            from PIL import Image
            img = Image.open(io.BytesIO(self.doc.xref_stream_raw(self.xref))).convert("RGB")
            a = np.full((self.height, self.width, 1), 255, np.uint8)
            if self.mask_xref:
                import pymupdf
                mask = pymupdf.Pixmap(self.doc, self.mask_xref)
                m = np.frombuffer(mask.samples, np.uint8).reshape(mask.height, mask.width, -1)[..., :1]
                if m.shape[:2] == (self.height, self.width):
                    a = m.copy()
                    if mask.n == 1 and m.max() <= 1:  # a 1-bit stencil
                        a = (m * 255).astype(np.uint8)
            self._rgb = np.concatenate([np.asarray(img, np.uint8), a], axis=2)
        return self._rgb


class Quad:
    """The orthoimage tiles of one US Topo map."""

    def __init__(self, path: Path):
        import pymupdf
        self.path = path
        self.doc = pymupdf.open(path)
        page = self.doc[0]
        page_obj = self.doc.xref_object(page.xref)
        # Page space -> UTM: the LGIDict whose CTM lands in UTM (the map layers', not the
        # little locator map's).
        self.page_to_utm = None
        for ctm, neat in zip(re.findall(r"/CTM \[([^\]]*)\]", page_obj), re.findall(r"/Neatline \[([^\]]*)\]", page_obj)):
            a, b, c, d, e, f = _numbers(ctm)
            n = _numbers(neat)
            x, y = np.mean(n[0::2]), np.mean(n[1::2])
            if 1e5 < a * x + c * y + e < 9e5:
                self.page_to_utm = np.array([[a, c, e], [b, d, f]])
                break
        if self.page_to_utm is None:
            raise ValueError(f"{path.name}: no UTM georeferencing")
        # The form drawn inside the Orthoimage layer's marked content.
        props = dict(re.findall(r"/(MC\d+) (\d+) 0 R", self.doc.xref_get_key(page.xref, "Resources/Properties")[1]))
        ortho = [name for name, x in props.items() if "(Orthoimage)" in self.doc.xref_object(int(x))]
        content = b"".join(self.doc.xref_stream(x) for x in page.get_contents()).decode("latin-1")
        forms = dict(re.findall(r"/(\w+) (\d+) 0 R", self.doc.xref_get_key(page.xref, "Resources/XObject")[1]))
        at = content.find(f"/OC /{ortho[0]} BDC") if ortho else -1
        if at < 0:
            raise ValueError(f"{path.name}: no orthoimage layer")
        form = int(forms[re.search(r"/(\w+) Do", content[at:]).group(1)])
        self.tiles = self._tiles(form)

    def _tiles(self, form: int) -> list[Tile]:
        images = dict(re.findall(r"/(\w+) (\d+) 0 R", self.doc.xref_get_key(form, "Resources/XObject")[1]))
        stream = self.doc.xref_stream(form).decode("latin-1")
        out = []
        for m in re.finditer(r"([-0-9.]+) ([-0-9.]+) ([-0-9.]+) ([-0-9.]+) ([-0-9.]+) ([-0-9.]+) cm\s*/(\w+) Do", stream):
            a, b, c, d, e, f = (float(v) for v in m.groups()[:6])
            xref = int(images[m.group(7)])
            w = int(self.doc.xref_get_key(xref, "Width")[1])
            h = int(self.doc.xref_get_key(xref, "Height")[1])
            mask = self.doc.xref_get_key(xref, "SMask")
            if mask[0] != "xref":
                mask = self.doc.xref_get_key(xref, "Mask")
            mask_xref = int(mask[1].split()[0]) if mask[0] == "xref" else None
            # Pixel (col, row) -> the image's unit square (row 0 at the top) -> page -> UTM.
            pix_to_unit = np.array([[1.0 / w, 0, 0], [0, -1.0 / h, 1.0], [0, 0, 1]])
            unit_to_page = np.array([[a, c, e], [b, d, f], [0, 0, 1]])
            page_to_utm = np.vstack([self.page_to_utm, [0, 0, 1]])
            out.append(Tile(self.doc, xref, w, h, (page_to_utm @ unit_to_page @ pix_to_unit)[:2], mask_xref))
        return out


class Aerial:
    """Several quads' imagery, sampled as one."""

    def __init__(self, quads: list[Quad]):
        self.quads = quads
        self.tiles = [t for q in quads for t in q.tiles]

    @classmethod
    def for_quads(cls, names: list[str]) -> "Aerial":
        return cls([Quad(download(n)) for n in names])

    def sample(self, east: np.ndarray, north: np.ndarray) -> np.ndarray:
        """RGBA (0-255, float) at each point; alpha 0 where no map has a photo."""
        east = np.asarray(east, float).ravel()
        north = np.asarray(north, float).ravel()
        out = np.zeros((east.size, 4))
        todo = np.ones(east.size, bool)
        for t in self.tiles:
            w, s, e, n = t.bounds
            inside = todo & (east >= w) & (east <= e) & (north >= s) & (north <= n)
            if not inside.any():
                continue
            idx = np.nonzero(inside)[0]
            col, row = t.from_utm @ np.vstack([east[idx], north[idx], np.ones(idx.size)])
            ok = (col >= 0) & (col < t.width) & (row >= 0) & (row < t.height)
            if not ok.any():
                continue
            idx, col, row = idx[ok], col[ok], row[ok]
            px = t.rgb()[np.minimum(row.astype(int), t.height - 1), np.minimum(col.astype(int), t.width - 1)].astype(float)
            good = px[:, 3] > 127
            out[idx[good]] = px[good]
            todo[idx[good]] = False
        return out

    def render(self, west: float, south: float, east: float, north: float, m_per_px: float) -> np.ndarray:
        """A north-up RGB image of the box (black where there's no photo)."""
        xs = np.arange(west, east, m_per_px) + m_per_px / 2
        ys = np.arange(north, south, -m_per_px) - m_per_px / 2
        gx, gy = np.meshgrid(xs, ys)
        px = self.sample(gx, gy)
        return px[:, :3].reshape(len(ys), len(xs), 3).astype(np.uint8)
