"""Knobs for the route bake. Everything that's a judgment call lives here."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / "tools" / ".cache"

# Public-domain sources from the USGS National Map.
NTD_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Tran/GPKG/TRAN_Iowa_State_GPKG.zip"
NTD_LAYER = "Trans_RoadSegment"
DEM_URL = "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current/n42w092/USGS_13_n42w092.tif"

GEO_CRS = "EPSG:4269"   # NAD83 lon/lat, what both sources ship in
UTM_CRS = "EPSG:26915"  # NAD83 / UTM 15N, meters

# The routes. Every bake script takes --route=<id> (default highway1) and bakes into
# that route's folder; use() below sets the knobs from here.
#   route_state    the state highway driven
#   start_state    the state highway crossed at the start line (the Kalona 4-way stop)
#   finish_roads   names of the cross street at the finish line
#   underpass_us   a US highway that passes under ours: its pieces end at the bridge,
#                  but it isn't a junction
#   search_from/to lon/lat hints a little beyond each end; the path between them is
#                  trimmed to the real ends
#   road_bbox      roads are read from this lon/lat box (west, south, east, north)
#   origin         game coordinates are relative to this (UTM east, north, elevation),
#                  near the route's middle. Kept once baked, so the buildings, trees and
#                  landmarks baked against it keep their places.
#   *_stop_line_m  the start and finish lines: stop lines this far short of the middle
#                  of each intersection (a start line past the middle, negative, starts
#                  you in the intersection, pointed out of it)
#   search_via     optional: a point the route passes through on its way to search_to
#   pre_roll_m, run_out_m   road kept behind the start line and past the finish line
#   start/finish_no_passing_m   solid lines out of town at the start, and into the finish
#   nhd_hu8        the watersheds (USGS NHD) its creeks are in
#   aerial_quads   the USGS 7.5' quads (US Topo maps) its corridor is on, for the aerial photos
#   start/finish_label          for the preview map
ROUTES = {
    # IA 1 from the 4-way stop at IA 22 in Kalona to the first stop light in Iowa City,
    # at Mormon Trek Blvd (past the US 218 interchange).
    "highway1": {
        "name": "Iowa Highway 1: Kalona to Iowa City",
        "route_state": "1",
        "start_state": "22",
        "finish_roads": {"Mormon Trek Blvd"},
        "underpass_us": "218",
        "search_from": (-91.7144, 41.4790),
        "search_to": (-91.5420, 41.6475),  # (on past the finish, short of Riverside Dr)
        "search_via": (-91.5600, 41.6405),  # (where it ended before: the same carriageway to the finish)
        "road_bbox": (-91.78, 41.44, -91.50, 41.70),
        "origin": (608444, 4605201, 241),  # the midpoint when first baked
        "start_stop_line_m": 12.0,
        "finish_stop_line_m": 12.0,
        "pre_roll_m": 188.0,  # (station 0 where it's always been)
        "run_out_m": 2000.0,  # the road carries on past the finish, into town
        "start_no_passing_m": 300.0,    # out of Kalona
        "finish_no_passing_m": 1100.0,  # the divided stretch from US 218 into Iowa City
        "nhd_hu8": ["07080208", "07080209"],  # English River; Iowa River below Iowa City (Old Mans Creek)
        "aerial_quads": ["Kalona", "Frytown", "Hills", "Tiffin", "Iowa_City_West"],
        "start_label": "Kalona (IA 22)",
        "finish_label": "Mormon Trek Blvd",
        "out_dir": "game/data/routes/highway1",
        "preview_dir": "docs/route-preview",
    },
    # IA 22 west from the same 4-way stop in Kalona to downtown Wellman, at 8th Ave.
    "highway22": {
        "name": "Iowa Highway 22: Kalona to Wellman",
        "route_state": "22",
        "start_state": "1",
        "finish_roads": {"8th Ave N", "8th Ave SW"},
        "underpass_us": None,
        "search_from": (-91.6950, 41.4820),
        "search_to": (-91.8900, 41.4684),  # (on west out of Wellman)
        "road_bbox": (-91.90, 41.42, -91.66, 41.53),
        "origin": (602197, 4592402, 220),  # about the middle
        "start_stop_line_m": -12.0,  # the far side of the 4-way stop: straight out of it, west
        "finish_stop_line_m": 8.0,  # a town street
        "pre_roll_m": 224.0,  # (station 0 where it's always been)
        "run_out_m": 2000.0,  # the road carries on past the finish, into town
        "start_no_passing_m": 300.0,     # out of Kalona
        "finish_no_passing_m": 900.0,    # through the built-up part of Wellman
        "nhd_hu8": ["07080208", "07080209"],
        "aerial_quads": ["Kalona", "Wellman", "Amish"],
        "start_label": "Kalona (IA 1)",
        "finish_label": "Wellman (8th Ave)",
        "out_dir": "game/data/routes/highway22",
        "preview_dir": "docs/route-preview/highway22",
    },
}

ROUTE_ID = ""
ROUTE_NAME = ""
ROUTE_STATE = START_STATE = ""
FINISH_ROADS: set[str] = set()
UNDERPASS_US: str | None = None
SEARCH_FROM = SEARCH_TO = (0.0, 0.0)
SEARCH_VIA: tuple[float, float] | None = None
ROAD_BBOX = (0.0, 0.0, 0.0, 0.0)
ORIGIN = (0, 0, 0)
START_STOP_LINE_M = FINISH_STOP_LINE_M = 12.0
PRE_ROLL_M = RUN_OUT_M = 0.0
START_NO_PASSING_M = FINISH_NO_PASSING_M = 0.0
NHD_HU8: list[str] = []
AERIAL_QUADS: list[str] = []
START_LABEL = FINISH_LABEL = ""
OUT_DIR = PREVIEW_DIR = ROOT


def use(route_id: str) -> None:
    """Point every knob at this route (one of ROUTES)."""
    global ROUTE_ID, ROUTE_NAME, ROUTE_STATE, START_STATE, FINISH_ROADS, UNDERPASS_US, SEARCH_FROM, SEARCH_TO, SEARCH_VIA
    global ROAD_BBOX, ORIGIN, START_STOP_LINE_M, FINISH_STOP_LINE_M, PRE_ROLL_M, RUN_OUT_M
    global START_NO_PASSING_M, FINISH_NO_PASSING_M, NHD_HU8, START_LABEL, FINISH_LABEL, OUT_DIR, PREVIEW_DIR
    global AERIAL_QUADS
    r = ROUTES[route_id]
    ROUTE_ID, ROUTE_NAME = route_id, r["name"]
    ROUTE_STATE, START_STATE = r["route_state"], r["start_state"]
    FINISH_ROADS, UNDERPASS_US = set(r["finish_roads"]), r["underpass_us"]
    SEARCH_FROM, SEARCH_TO, ROAD_BBOX, ORIGIN = r["search_from"], r["search_to"], r["road_bbox"], r["origin"]
    SEARCH_VIA = r.get("search_via")
    START_STOP_LINE_M, FINISH_STOP_LINE_M = r["start_stop_line_m"], r["finish_stop_line_m"]
    PRE_ROLL_M, RUN_OUT_M = r["pre_roll_m"], r["run_out_m"]
    START_NO_PASSING_M, FINISH_NO_PASSING_M = r["start_no_passing_m"], r["finish_no_passing_m"]
    NHD_HU8 = list(r["nhd_hu8"])
    AERIAL_QUADS = list(r.get("aerial_quads", []))
    START_LABEL, FINISH_LABEL = r["start_label"], r["finish_label"]
    OUT_DIR, PREVIEW_DIR = ROOT / r["out_dir"], ROOT / r["preview_dir"]


def use_args(argv: list[str]) -> str:
    """use() the route named by --route=<id> (or --route <id>) in argv, else highway1."""
    route_id = "highway1"
    for i, a in enumerate(argv):
        if a.startswith("--route="):
            route_id = a.split("=", 1)[1]
        elif a == "--route" and i + 1 < len(argv):
            route_id = argv[i + 1]
    if route_id not in ROUTES:
        raise SystemExit(f"no route {route_id!r}; the routes are {', '.join(ROUTES)}")
    use(route_id)
    print(f"route: {ROUTE_NAME} -> {OUT_DIR.relative_to(ROOT)}")
    return route_id


NAME_FIXES = {"Morman Trek Blvd": "Mormon Trek Blvd"}  # typos in the road data

SPACING_M = 2.0                # route sample spacing; station = index * spacing
PLAN_SMOOTH_SIGMA_M = 10.0     # rounds off the kinks at source vertices
PROFILE_SMOOTH_SIGMA_M = 15.0  # vertical smoothing of the road surface
DIP_FILL_WINDOW_M = 120.0      # bare-earth DEM has no bridges; fill dips narrower than this
BRIDGE_MIN_FILL_M = 1.0        # a fill deeper than this counts as a bridge (or a culvert)...
RAILED_BRIDGE_M = 3.0          # ...one standing this high is a real bridge: a deck and guardrails,
                               # and open underneath (the creek shows) unless a road runs under it
STREAM_YARD_M = 25.0           # no crops this close to a named creek or river: grass on its banks
JUNCTION_TOL_M = 4.0           # a side road ending this close to the route joins it
JUNCTION_MERGE_M = 30.0        # side-road pieces this close together are one junction
MIN_NO_PASSING_M = 152.0       # MUTCD: no-passing zones are at least 500 ft long

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


use("highway1")
