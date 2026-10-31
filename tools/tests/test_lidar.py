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


def test_landmarks_count_as_yards():
    rects = bl.landmark_footprints()
    assert rects, "the Kalona Cheese landmark is in game/data/route/landmarks.json"
    for r in rects:
        assert r["length"] > 10 and r["width"] > 10 and r["yaw"] == 0.0
    route = {"terrain": {"tile_size_m": 256.0, "grid": 33, "tiles": [[0, 0, 0.0]]}}
    box = {"x": 128.0, "z": 128.0, "length": 40.0, "width": 30.0, "yaw": 0.0, "height": 6.0, "kind": "landmark"}
    d = bl.yard_distances(route, [box])
    assert d[0, 16, 16] == 0 and d[0, 16, 18] == 0   # inside the rectangle
    assert abs(int(d[0, 16, 24]) - 44) <= 1           # 64 m east of the middle: 44 m past its 20 m half-length


def _patch(n, inside, height):
    """A north-up raster of roof cells (1 m, centered on 0, 0): `inside(e, n)` and `height(e, n)`."""
    roof = np.zeros((n, n), dtype=bool)
    top = np.zeros((n, n), dtype=np.float32)
    for j in range(n):
        for i in range(n):
            e, nn = i + 0.5 - n / 2, n / 2 - (j + 0.5)
            if inside(e, nn):
                roof[j, i] = True
                top[j, i] = height(e, nn)
    return roof, top


def test_the_largest_rectangle_in_a_grid():
    g = np.zeros((10, 12), dtype=bool)
    g[2:8, 1:4] = True     # 6 x 3 = 18
    g[4:9, 5:11] = True    # 5 x 6 = 30
    g[4, 4] = True
    assert bl.largest_rectangle(g) == (30, 4, 5, 9, 11)
    assert bl.largest_rectangle(np.zeros((3, 3), dtype=bool))[0] == 0


def test_an_l_shaped_roof_becomes_two_boxes():
    # A 30 x 10 m wing and a 10 x 16 m one off its end: an L, which a single box would
    # fill only half of (and stand in the yard).
    def inside(e, nn):
        return (-15 <= e <= 15 and 0 <= nn <= 10) or (5 <= e <= 15 and -16 <= nn <= 0)
    roof, top = _patch(60, inside, lambda e, nn: 6.0)
    out = bl.buildings_from_mask(roof, top, -30.0, 30.0, 1.0)
    assert len(out) == 2, out
    area = sum(b["length"] * b["width"] for b in out)
    assert 440 <= area <= 500, area   # the L's 460 m2, near enough
    for b in out:  # each box on the L, not out in the yard
        assert inside(b["e"], b["n"])


def test_a_gable_roof_is_read_with_its_eaves():
    # 20 x 10 m, the ridge along the length at 7 m, the eaves at 4 m.
    roof, top = _patch(40, lambda e, nn: abs(e) <= 10 and abs(nn) <= 5,
                       lambda e, nn: 7.0 - 0.6 * abs(nn))
    (b,) = bl.buildings_from_mask(roof, top, -20.0, 20.0, 1.0)
    assert b["roof"] == "gable"
    assert abs(b["height"] - 7.0) < 0.5 and abs(b["eave"] - 4.0) < 0.8, b
    assert abs(math.cos(b["yaw"])) > 0.99  # the length east-west, along the ridge


def test_a_ridge_across_a_building_turns_it():
    # 20 x 12 m with its ridge running north-south, across the long side.
    roof, top = _patch(40, lambda e, nn: abs(e) <= 10 and abs(nn) <= 6,
                       lambda e, nn: 8.0 - 0.5 * abs(e))
    (b,) = bl.buildings_from_mask(roof, top, -20.0, 20.0, 1.0)
    assert b["roof"] == "gable"
    assert abs(math.sin(b["yaw"])) > 0.99, b  # the "length" now north-south, along the ridge
    assert b["length"] < b["width"]


def test_a_flat_roof_is_flat():
    roof, top = _patch(50, lambda e, nn: abs(e) <= 15 and abs(nn) <= 10, lambda e, nn: 5.0)
    (b,) = bl.buildings_from_mask(roof, top, -25.0, 25.0, 1.0)
    assert b["roof"] == "flat" and b["eave"] == b["height"]


def test_tidy_keeps_buildings_and_trees_apart(tmp_path, monkeypatch):
    import json
    import config
    monkeypatch.setattr(config, "OUT_DIR", tmp_path)
    # A street running north-south through x = 100.
    (tmp_path / "streets.json").write_text(json.dumps({"streets": [
        {"name": "Main", "kind": "street", "half_width": 4.0, "joins": [],
         "points": [100, 0, 0, 0, -200, 100, 0, 0, 0, 200]}]}))
    (tmp_path / "landmarks.json").write_text(json.dumps({"landmarks": [{"clear": [[-310, -10, -290, 10]]}]}))

    def house(x, z, length=12.0, width=8.0, yaw=0.0):
        return {"x": x, "z": z, "length": length, "width": width, "yaw": yaw, "height": 6.0,
                "eave": 3.5, "roof": "gable", "kind": "house"}

    big = house(0.0, 0.0, 40.0, 20.0)
    structures = [
        big,
        house(5.0, 2.0, 10.0, 6.0),     # all inside the big one: a misread, left out
        house(108.0, 50.0),              # an edge on the street (and its clearance): moved off it
        house(100.0, -50.0),             # right in it: left out
        house(-300.0, 0.0),              # where a landmark stands: left out
        house(60.0, 60.0),               # nothing wrong with it
    ]
    trees = np.array([
        [0.0, 0.0, 12.0, 4.0, 0.0],      # trunk in the middle of the big building
        [22.0, 0.0, 12.0, 5.0, 0.0],     # trunk just outside its wall, the crown into it
        [100.0, 0.0, 10.0, 3.0, 0.0],    # in the street
        [60.0, 120.0, 10.0, 3.0, 0.0],   # nothing wrong with it
    ], dtype="<f4")
    far_road = np.array([[5000.0, -5000.0], [5000.0, 5000.0]])
    out, kept = bl.tidy(structures, trees, tmp_path, far_road)
    polys = [bl.footprint(b) for b in out]
    assert len(out) == 3 and big in out and any(b["x"] == 60.0 and b["z"] == 60.0 for b in out)
    (moved,) = [b for b in out if b["x"] > 100]
    assert 110.0 < moved["x"] < 112.0 and abs(moved["z"] - 50.0) < 0.5, moved
    assert not any(b["x"] < -200 for b in out), "out of the landmark"
    street = shapely.LineString([(100, -200), (100, 200)]).buffer(4.0)
    assert all(p.intersection(street).area < 1.0 for p in polys), "off the street"
    for i, p in enumerate(polys):
        for q in polys[i + 1:]:
            assert p.intersection(q).area < 0.2 * min(p.area, q.area)
    assert any(abs(t[0] - 60.0) < 0.01 and abs(t[1] - 120.0) < 0.01 for t in kept), "the good tree stays put"
    for x, z, h, r, _ in kept:
        trunk = shapely.Point(x, z)
        assert not any(p.contains(trunk) for p in polys)
        assert all(p.distance(trunk) >= r * (1 - bl.CROWN_OVERLAP) - 0.01 for p in polys)
        assert street.distance(trunk) > 0.5
    # The good house's yard light is out in its yard, clear of everything.
    (good,) = [b for b in out if b["x"] == 60.0]
    lx, lz = good["light"]
    pole = shapely.Point(lx, lz)
    assert all(p.distance(pole) >= bl.YARD_LIGHT_CLEAR_M for p in polys)
    assert pole.distance(bl.footprint(good)) < 12.0
    assert all(math.hypot(x - lx, z - lz) >= 2.0 for x, z, *_ in kept)


def test_a_roof_sloping_one_way_is_a_lean_to():
    # 20 x 8 m, rising 0.4 m a meter to the north: a lean-to, or half a gable roof.
    roof, top = _patch(40, lambda e, nn: abs(e) <= 10 and abs(nn) <= 4, lambda e, nn: 5.0 + 0.4 * nn)
    (b,) = bl.buildings_from_mask(roof, top, -20.0, 20.0, 1.0)
    assert b["roof"] == "lean", b
    assert abs(math.cos(b["yaw"])) > 0.99  # the length east-west: the slope runs across it
    # The high side's game z (south) is cos(yaw) * high: north is up the slope, -z.
    assert math.cos(b["yaw"]) * b["high"] < 0, b
    assert abs(b["height"] - 6.4) < 0.6 and abs(b["eave"] - 3.4) < 1.0, b
    s = bl.game_structures([b], {"easting": 0.0, "northing": 0.0})[0]
    assert s["roof"] == "lean" and s["high"] == b["high"]


def test_a_gable_cut_along_its_ridge_is_two_lean_tos_back_to_back():
    # A 24 x 12 m gable roof (ridge east-west) with a 10 x 6 m wing on the south-east
    # corner: cut up, the main roof can come apart along its ridge.
    def inside(e, nn):
        return (abs(e) <= 12 and abs(nn) <= 6) or (2 <= e <= 12 and -12 <= nn <= -6)

    def height(e, nn):
        return 4.0 if nn < -6 else 7.0 - 0.5 * abs(nn)
    roof, top = _patch(60, inside, height)
    out = bl.buildings_from_mask(roof, top, -30.0, 30.0, 1.0)
    main = [b for b in out if b["height"] > 5.5]
    for b in main:
        assert b["roof"] in ("gable", "lean"), b
        if b["roof"] == "lean":  # up toward the ridge at north 0
            c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
            high_z = -b["n"] + c * b["high"] * b["width"] / 2  # game z of its high edge
            assert abs(high_z) < abs(-b["n"]) + 0.5, b


def test_a_big_round_bin_stays_whole():
    # A 16 m grain bin fills only ~79% of its square: it's still one bin, not cut up.
    roof, top = _patch(40, lambda e, nn: e * e + nn * nn <= 8.0 ** 2, lambda e, nn: 14.0 - 0.3 * math.hypot(e, nn))
    out = bl.buildings_from_mask(roof, top, -20.0, 20.0, 1.0)
    assert len(out) == 1 and out[0]["kind"] == "bin", out


def test_a_co_ops_bin_and_elevator_stay_one_tall_box():
    # A 30 m bin with the elevator's leg alongside: together not round, nor filling their
    # box, but no barn's that tall: left whole, as the game's co-op structures.
    def inside(e, nn):
        return e * e + nn * nn <= 8.0 ** 2 or (8.0 <= e <= 12.0 and abs(nn) <= 3.0)
    roof, top = _patch(40, inside, lambda e, nn: 30.0)
    out = bl.buildings_from_mask(roof, top, -20.0, 20.0, 1.0)
    assert len(out) == 1 and out[0]["height"] > 25.0, out


def test_a_flat_roofed_building_in_town_by_a_street_is_a_store_facing_it(tmp_path, monkeypatch):
    import json
    import config
    monkeypatch.setattr(config, "OUT_DIR", tmp_path)
    (tmp_path / "places.json").write_text(json.dumps({"towns": [{"name": "Town", "outline": [-500, -500, 500, -500, 500, 500, -500, 500]}]}))
    # A street east-west along z = 0; the route far off.
    (tmp_path / "streets.json").write_text(json.dumps({"streets": [
        {"name": "Main", "kind": "paved", "half_width": 3.6, "joins": [False, False],
         "points": [v for x in range(-200, 201, 20) for v in (x, 0, 0, 0, 0)]}]}))
    store = {"x": 0.0, "z": 20.0, "length": 30.0, "width": 12.0, "yaw": math.pi / 2, "height": 6.0, "eave": 6.0,
             "roof": "flat", "kind": "shed"}  # turned: its length runs north-south, its end to the street
    house = {"x": 60.0, "z": 20.0, "length": 12.0, "width": 9.0, "yaw": 0.0, "height": 7.0, "eave": 4.0,
             "roof": "gable", "kind": "house"}
    far = dict(store, x=0.0, z=300.0)
    route_xz = np.array([[5000.0, -5000.0], [5000.0, 5000.0]])
    n = bl.mark_stores([store, house, far], tmp_path, route_xz)
    assert n == 1 and store["kind"] == "store" and house["kind"] == "house" and far["kind"] == "shed"
    # Turned so the street's off its own z side (the front's built there), length and width
    # swapped with it; its front toward the street at z = 0.
    assert abs(store["length"] - 12.0) < 1e-6 and abs(store["width"] - 30.0) < 1e-6
    c, s = math.cos(store["yaw"]), math.sin(store["yaw"])
    front = (s * store["front"], c * store["front"])  # local +z is world (sin, cos)
    assert abs(front[0]) < 1e-6 and front[1] < 0


def test_slivers_are_left_out(tmp_path, monkeypatch):
    import config
    monkeypatch.setattr(config, "OUT_DIR", tmp_path)
    keep = {"x": 0.0, "z": 0.0, "length": 12.0, "width": 8.0, "yaw": 0.0, "height": 6.0, "kind": "house"}
    sliver = {"x": 40.0, "z": 0.0, "length": 16.0, "width": 2.0, "yaw": 0.0, "height": 5.0, "kind": "shed"}
    out, _ = bl.tidy([keep, sliver], np.zeros((0, 5), dtype="<f4"), tmp_path, np.array([[5000.0, 0.0], [5000.0, 10.0]]))
    assert [b["x"] for b in out] == [0.0]
