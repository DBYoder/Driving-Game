import math

import numpy as np
import shapely

import bake_lidar as bl
from bake_places import crossings, merge_close


def _box_raster(n, rows, cols, value=True):
    a = np.zeros((n, n), dtype=bool)
    a[rows, cols] = value
    return a


def test_a_roof_patch_becomes_one_oriented_box():
    n = 120
    roof = np.zeros((n, n), dtype=bool)
    # A 30 x 12 m barn turned 30 degrees, 1 m cells, north up.
    yaw = math.radians(30.0)
    for j in range(n):
        for i in range(n):
            e, nn = i + 0.5 - 60.0, 60.0 - (j + 0.5)
            u = e * math.cos(yaw) + nn * math.sin(yaw)
            v = -e * math.sin(yaw) + nn * math.cos(yaw)
            roof[j, i] = abs(u) <= 15.0 and abs(v) <= 6.0
    top = np.where(roof, 9.0, 0.0).astype(np.float32)
    out = bl.buildings_from_mask(roof, top, -60.0, 60.0, 1.0)
    assert len(out) == 1
    b = out[0]
    assert abs(b["length"] - 30.0) < 2.0 and abs(b["width"] - 12.0) < 2.0
    assert abs(b["e"]) < 1.0 and abs(b["n"]) < 1.0
    # Long side 30 degrees from east (or the same line the other way round).
    assert abs(math.sin(b["yaw"] - yaw)) < 0.08
    assert b["kind"] == "barn"


def test_building_kinds():
    assert bl.building_kind(9.0, 8.5, 12.0, 0.8) == "bin"            # tall, small, square
    assert bl.building_kind(16.0, 15.5, 7.0, 0.9) == "house"            # square but squat: no bin
    assert bl.building_kind(30.0, 12.0, 10.0, 0.9) == "barn"
    assert bl.building_kind(60.0, 15.0, 6.0, 0.9) == "shed"             # machine shed / hog barn
    assert bl.building_kind(14.0, 10.0, 7.0, 0.9) == "house"
    assert bl.building_kind(7.0, 6.0, 3.0, 0.9) == "shed"               # garage


def test_roofs_and_trees_are_told_apart():
    n = 60
    count = np.zeros((n, n), np.float32)
    singles = np.zeros((n, n), np.float32)
    top = np.zeros((n, n), np.float32)
    # A flat roof: every pulse comes back once, all at 6 m.
    count[10:25, 10:25] = 5
    singles[10:25, 10:25] = 5
    top[10:25, 10:25] = 6.0
    # A bare tree: most pulses come back more than once, ragged top.
    rng = np.random.default_rng(1)
    count[35:50, 35:50] = 5
    singles[35:50, 35:50] = 1
    top[35:50, 35:50] = rng.uniform(5.0, 14.0, (15, 15))
    roof, tree, share = bl.classify_cells(count, singles, top)
    assert roof[17, 17] and not tree[17, 17]
    assert tree[42, 42] and not roof[42, 42]
    trees = bl.trees_from_mask(tree, top, share, 0.0, float(n), 1.0)
    assert 2 <= len(trees) <= 8
    assert all(t[4] == 0.0 for t in trees)  # bare deciduous, not conifers


def test_power_lines_are_not_trees():
    n = 40
    count = np.zeros((n, n), np.float32)
    count[20, :] = 4  # a wire: one cell wide
    singles = np.zeros((n, n), np.float32)
    top = np.zeros((n, n), np.float32)
    top[20, :] = 8.0
    roof, tree, _ = bl.classify_cells(count, singles, top)
    assert not tree.any() and not roof.any()


def test_yard_distance_measures_to_the_footprint():
    route = {"terrain": {"tile_size_m": 256.0, "grid": 33, "tiles": [[0, 0, 0.0]]}}
    house = {"x": 128.0, "z": 128.0, "length": 16.0, "width": 10.0, "yaw": 0.0, "height": 7.0, "kind": "house"}
    d = bl.yard_distances(route, [house])
    assert d.shape == (1, 33, 33)
    assert d[0, 16, 16] == 0                     # the middle of the house
    assert abs(int(d[0, 16, 20]) - 24) <= 1      # 32 m east of center: 24 m past the 8 m half-length
    assert d[0, 0, 0] > 150                       # the far corner


def test_crossings_and_merging():
    route = shapely.LineString([(0, 0), (0, 1000)])
    creek = shapely.LineString([(-50, 300), (50, 310), (-50, 320)])  # crosses twice
    s = crossings(route, creek)
    assert len(s) == 2 and abs(s[0] - 305) < 6
    merged = merge_close([{"station": x, "name": "Dirty Face Creek"} for x in s], "name", 200.0)
    assert len(merged) == 1
