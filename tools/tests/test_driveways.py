import numpy as np

import bake_driveways as bd


def test_gravel_looks_like_gravel_and_grass_doesnt():
    px = np.array([[[200, 198, 190], [150, 150, 152], [60, 110, 50], [90, 140, 70], [40, 40, 42]]], float)
    g = bd.gravel_score(px)[0]
    assert g[0] > 0.8 and g[1] > 0.6        # pale gravel, grey concrete
    assert g[2] < 0.05 and g[3] < 0.05      # grass, crops
    assert g[4] < 0.05                      # deep shadow says nothing


def test_the_cheapest_way_follows_the_lane():
    # A field (dear) with a lane (cheap) that bends: the path from the yard (top left)
    # to the road (bottom row) keeps to it rather than cutting straight across.
    cost = np.full((40, 40), 10.0)
    cost[2:30, 3] = 1.0      # down from the yard...
    cost[29, 3:35] = 1.0     # ...along...
    cost[29:40, 34] = 1.0    # ...and down to the road
    starts = np.zeros_like(cost, bool)
    starts[2, 3] = True
    goals = np.zeros_like(cost, bool)
    goals[39, :] = True
    path = bd.cheapest_path(cost, starts, goals)
    rr, cc = np.unravel_index(np.array(path), cost.shape)
    assert (cost[rr, cc] == 1.0).mean() > 0.95
    assert rr[-1] == 39 and cc[-1] == 34


def test_a_wall_is_not_a_way_through():
    cost = np.ones((20, 20))
    cost[10, :18] = 1e4  # a building across all but the right edge
    starts = np.zeros_like(cost, bool)
    starts[2, 2] = True
    goals = np.zeros_like(cost, bool)
    goals[19, 2] = True
    path = bd.cheapest_path(cost, starts, goals)
    rr, cc = np.unravel_index(np.array(path), cost.shape)
    assert cost[rr, cc].max() < 10 and cc.max() >= 18


def test_smoothing_keeps_the_ends():
    xz = np.array([[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]])
    out = bd.chaikin(xz)
    assert np.allclose(out[0], xz[0]) and np.allclose(out[-1], xz[-1]) and len(out) > len(xz)


def test_farmsteads_one_pick_each():
    import shapely
    b = lambda x, z, kind, l=12.0, w=8.0: {"x": x, "z": z, "length": l, "width": w, "yaw": 0.0, "kind": kind}
    buildings = [b(0, 0, "house"), b(20, 10, "barn", 30, 15), b(30, -20, "shed"),  # one farmstead
                 b(500, 0, "shed", 20, 10), b(520, 15, "shed", 25, 12),           # another, no house
                 b(1000, 0, "bin")]                                               # a bin alone: none
    picks = bd.farmsteads(buildings, shapely.Polygon())
    assert len(picks) == 2
    assert any(p["kind"] == "house" and p["x"] == 0 for p in picks)
    assert any(p["x"] == 520 for p in picks)  # the biggest when there's no house
