import numpy as np
import shapely

import config
import geo
from bake_route import base_name, carve, center_divided


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
