import numpy as np
import shapely

import config
import geo
from bake_route import base_name, carve, center_divided, coarse_floor


def test_carve_keeps_ground_under_the_road_and_untouched_far_away():
    natural = np.array([5.0, 5.0, 5.0, 5.0])
    road = np.array([2.0, 2.0, 2.0, 2.0])
    d = np.array([0.0, 8.0, config.DITCH_OUTER_M, config.BLEND_OUTER_M + 1])
    out = carve(natural, road, d)
    assert np.allclose(out[:3], road[:3] - config.DITCH_DEPTH_M)  # flat ditch-depth bed
    assert np.isclose(out[3], natural[3])


def test_center_divided_moves_into_the_median():
    # One carriageway along y=0, the other along y=20 between x=100 and x=300.
    driven = geo.resample(np.array([[0.0, 0.0], [400.0, 0.0]]), 1.0)
    other = np.array([[100.0, 0.0], [120.0, 20.0], [280.0, 20.0], [300.0, 0.0]])
    hwy = shapely.MultiLineString([driven, other])
    out = center_divided(driven, hwy)
    assert abs(out[200, 1] - 10.0) < 0.1   # middle of the median
    assert abs(out[20, 1]) < 0.01          # undivided before
    assert abs(out[380, 1]) < 0.01         # and after


def test_base_name_ignores_quadrant_suffix():
    assert base_name("Hazelwood Ave SW") == base_name("Hazelwood Ave")
    assert base_name("W H Ave") == "W H Ave"


def test_coarse_floor_stays_under_the_fine_ground():
    rng = np.random.default_rng(3)
    k = 8
    fine = np.cumsum(np.cumsum(rng.normal(size=(6 * k + 1, 9 * k + 1)), 0), 1) * 0.05
    fine[3 * k:3 * k + 3, :] -= 4.0  # a narrow ditch the coarse grid could step over
    coarse = coarse_floor(fine, k)
    assert coarse.shape == (5, 8)
    # Bilinear across each coarse cell, compared at every fine sample inside it.
    for r in range(coarse.shape[0] - 1):
        for c in range(coarse.shape[1] - 1):
            t = np.linspace(0, 1, k + 1)
            u, v = np.meshgrid(t, t)
            q = coarse[r:r + 2, c:c + 2]
            interp = (q[0, 0] * (1 - u) * (1 - v) + q[0, 1] * u * (1 - v)
                      + q[1, 0] * (1 - u) * v + q[1, 1] * u * v)
            under = fine[k + r * k:k + (r + 1) * k + 1, k + c * k:k + (c + 1) * k + 1]
            assert (interp <= under + 1e-9).all()


def test_street_kinds():
    from bake_streets import street_kind
    from sources import Road
    county = Road(name="500th St SW", mtfcc="S1400", state_routes=set(), us_routes=set())
    assert street_kind(county, in_town=False) == "gravel"   # most county roads
    assert street_kind(county, in_town=True) == "paved"     # town streets
    hwy = Road(name="State Hwy 22", mtfcc="S1200", state_routes={"22"}, us_routes=set())
    assert street_kind(hwy, in_town=False) == "paved"
    lane = Road(name="", mtfcc="S1740", state_routes=set(), us_routes=set())
    assert street_kind(lane, in_town=False) == "lane"
    alley = Road(name="", mtfcc="S1730", state_routes=set(), us_routes=set())
    assert street_kind(alley, in_town=True) is None


def test_run_on_extends_free_ends_straight():
    from bake_streets import run_on
    line = shapely.LineString([(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)])
    out = np.asarray(run_on(line, True, True, 1.5).coords)
    assert np.allclose(out[0], [-1.5, 0.0]) and np.allclose(out[-1], [10.0, 11.5])
    assert len(np.asarray(run_on(line, False, False, 1.5).coords)) == 3


def test_streets_climb_out_of_the_ditch_to_meet_ia1():
    from scipy.spatial import cKDTree
    from bake_streets import JOIN_FULL_M, JOIN_RAISE_M, surface_heights

    class FlatGround:  # 1.25 m below the road everywhere (as in the ditch)
        def at(self, x, z):
            return np.full(len(np.atleast_1d(x)), -1.25)

    # IA 1 runs north-south along x = 0 at height 0; a street heads east from its edge.
    ia1 = np.column_stack([np.zeros(201), np.linspace(-200.0, 200.0, 201)])
    street = np.column_stack([np.arange(4.3, 80.0, 3.0), np.zeros(26)])
    h = surface_heights(street, 3.2, 0.12, FlatGround(), cKDTree(ia1), np.zeros(201))
    assert np.allclose(h[street[:, 0] < JOIN_FULL_M - 3.3], JOIN_RAISE_M)  # level with IA 1 over the ditch
    assert np.allclose(h[-1], -1.25 + 0.12)                                  # back on the ground
    assert np.all(np.diff(h[:, 1]) <= 1e-9)                                  # one smooth ramp down
