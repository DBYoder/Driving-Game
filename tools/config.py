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

# The route: IA 1 from the 4-way stop at IA 22 in Kalona to the first stop light in Iowa
# City, at Mormon Trek Blvd (past the US 218 interchange).
ROUTE_STATE = "1"
START_STATE = "22"
FINISH_US = "218"  # passes under IA 1 near the end (not a junction)
FINISH_ROAD = "Mormon Trek Blvd"
STOP_LINE_M = 12.0  # start and finish lines: the northbound stop lines, this far short of the middle of each intersection
NAME_FIXES = {"Morman Trek Blvd": "Mormon Trek Blvd"}  # typos in the road data
# Lon/lat hints a little beyond each end; the path between them is trimmed to the real ends.
SEARCH_FROM = (-91.7144, 41.4790)
SEARCH_TO = (-91.5600, 41.6405)
PRE_ROLL_M = 188.0  # road kept behind the start line (station 0 where it's always been)
RUN_OUT_M = 300.0   # road kept past the finish line
# Game coordinates are relative to this (UTM east, north, elevation). It was the route's
# midpoint when first baked; it's kept so the buildings, trees and landmarks baked
# against it keep their places.
ORIGIN = (608444, 4605201, 241)

SPACING_M = 2.0                # route sample spacing; station = index * spacing
PLAN_SMOOTH_SIGMA_M = 10.0     # rounds off the kinks at source vertices
PROFILE_SMOOTH_SIGMA_M = 15.0  # vertical smoothing of the road surface
DIP_FILL_WINDOW_M = 120.0      # bare-earth DEM has no bridges; fill dips narrower than this
BRIDGE_MIN_FILL_M = 1.0        # a fill deeper than this counts as a bridge
JUNCTION_TOL_M = 4.0           # a side road ending this close to IA 1 joins it
JUNCTION_MERGE_M = 30.0        # side-road pieces this close together are one junction
MIN_NO_PASSING_M = 152.0       # MUTCD: no-passing zones are at least 500 ft long
TOWN_NO_PASSING_M = 300.0      # solid lines out of Kalona
INTERCHANGE_NO_PASSING_M = 1100.0  # and through the divided stretch from US 218 into Iowa City

# Terrain corridor around the road.
DEM_RES_M = 4.0
CORRIDOR_HALF_WIDTH_M = 1200.0
TILE_SIZE_M = 256.0
TILE_GRID = 33  # vertices per tile side -> 8 m spacing

# Low-detail ground out to the horizon, drawn under the corridor tiles so the world
# doesn't end where they do. It's coarse, so each vertex takes the lowest ground around
# it and then drops a little more: that keeps it under the detailed tiles and the road
# everywhere, and the detailed ground always wins where both are drawn.
HORIZON_REACH_M = 4400.0  # past the road in every direction (fog is total at ~3 km)
HORIZON_STEP_M = 64.0     # vertex spacing, a multiple of the tiles' 8 m
HORIZON_CHUNK = 16        # cells per chunk side -> 1024 m chunks
HORIZON_DROP_M = 1.0
HORIZON_DEM_RES_M = 16.0

# Buildings and trees, found in the USGS 3DEP lidar (the 2019 eastern Iowa flight, leaf-off)
# via its public Entwine copy on AWS. The points carry only ground/unclassified, so
# buildings and trees are told apart here (see tools/bake_lidar.py).
LIDAR_EPT_URL = "https://s3-us-west-2.amazonaws.com/usgs-lidar-public/IA_Eastern_1_2019/"
LIDAR_DEPTH = 11              # octree depth read: the full ~4.6 points per square meter
LIDAR_HALF_WIDTH_M = 1000.0   # either side of the road
LIDAR_TILE_M = 512.0          # processed in tiles this big...
LIDAR_MARGIN_M = 48.0         # ...plus this much around each, so buildings on an edge are whole
LIDAR_CELL_M = 1.0            # raster the points are sorted into
LIDAR_GROUND_CELL_M = 2.0

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
