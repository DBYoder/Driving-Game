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
