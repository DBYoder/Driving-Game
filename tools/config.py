"""Knobs for the route bake. Everything that's a judgment call lives here."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / "tools" / ".cache"
OUT_DIR = ROOT / "game" / "data" / "route"
PREVIEW_DIR = ROOT / "docs" / "route-preview"

# Public-domain sources from the USGS National Map.
NTD_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Tran/GPKG/TRAN_Iowa_State_GPKG.zip"
NTD_LAYER = "Trans_RoadSegment"
DEM_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/n42w092/USGS_13_n42w092.tif"

GEO_CRS = "EPSG:4269"   # NAD83 lon/lat, what both sources ship in
UTM_CRS = "EPSG:26915"  # NAD83 / UTM 15N, meters

# Roads are read from this lon/lat box (west, south, east, north).
ROAD_BBOX = (-91.78, 41.44, -91.50, 41.70)

# The route: IA 1 from where it crosses IA 22 in Kalona to where it crosses US 218.
ROUTE_STATE = "1"
START_STATE = "22"
FINISH_US = "218"
# Lon/lat hints a little beyond each end; the path between them is trimmed to the real ends.
SEARCH_FROM = (-91.7144, 41.4790)
SEARCH_TO = (-91.5600, 41.6405)
PRE_ROLL_M = 200.0  # road kept behind the start line
RUN_OUT_M = 300.0   # road kept past the finish line

SPACING_M = 2.0                # route sample spacing; station = index * spacing
PLAN_SMOOTH_SIGMA_M = 10.0     # rounds off the kinks at source vertices
PROFILE_SMOOTH_SIGMA_M = 15.0  # vertical smoothing of the road surface
DIP_FILL_WINDOW_M = 120.0      # bare-earth DEM has no bridges; fill dips narrower than this
BRIDGE_MIN_FILL_M = 1.0        # a fill deeper than this counts as a bridge
JUNCTION_TOL_M = 4.0           # a side road ending this close to IA 1 joins it
JUNCTION_MERGE_M = 30.0        # side-road pieces this close together are one junction

# Terrain corridor around the road.
DEM_RES_M = 4.0
CORRIDOR_HALF_WIDTH_M = 1200.0
TILE_SIZE_M = 256.0
TILE_GRID = 33  # vertices per tile side -> 8 m spacing

# Cross-section the terrain is carved around (distance from centerline, meters).
# The game's road mesh covers the pavement, shoulders and the grass foreslope down to
# the ditch 10 m out (game/scripts/world/road_mesher.gd). Under all of that the ground
# sits flat at ditch depth, so its coarse 8 m triangles can never poke through; past
# the ditch bottom it blends back up to the natural ground.
DITCH_DEPTH_M = 1.25
DITCH_OUTER_M = 14.0
BLEND_OUTER_M = 36.0

# USGS/Census MAF/TIGER feature class codes.
ROAD_CLASSES = {
    "S1100": "highway",
    "S1200": "highway",
    "S1400": "road",
    "S1630": "ramp",
}
DRIVEWAY_CLASSES = {"S1640", "S1740", "S1780"}
