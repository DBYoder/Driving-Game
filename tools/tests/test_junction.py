"""The Kalona 4-way (junction.py), built from the two routes' baked centerlines."""
import json

import numpy as np
import pytest
import shapely

import config
import junction as J


@pytest.fixture(scope="module")
def routes():
    return {k: json.loads((config.ROOT / config.ROUTES[k]["out_dir"] / "route.json").read_text()) for k in (J.IA1, J.IA22)}


def flat_street(y):
    return lambda p: np.full(len(p), y)


@pytest.fixture(scope="module")
def hw1(routes):
    return J.Junction(J.IA1, routes, flat_street(-37.6))


@pytest.fixture(scope="module")
def hw22(routes):
    return J.Junction(J.IA22, routes, flat_street(-16.7))


def test_both_routes_agree_where_it_is(routes, hw1, hw22):
    # The same spot on the ground, from each route's own origin.
    o1, o22 = routes[J.IA1]["origin"], routes[J.IA22]["origin"]
    utm1 = (hw1.center[0] + o1["easting"], o1["northing"] - hw1.center[1])
    utm22 = (hw22.center[0] + o22["easting"], o22["northing"] - hw22.center[1])
    assert np.hypot(utm1[0] - utm22[0], utm1[1] - utm22[1]) < 0.01
    assert hw1.own == J.IA1 and hw22.own == J.IA22


def test_its_ends_on_the_route_are_whole_samples(routes, hw1, hw22):
    for j, rid in ((hw1, J.IA1), (hw22, J.IA22)):
        lo, hi = J.ENDS[rid]
        assert lo % routes[rid]["spacing_m"] == 0 and hi % routes[rid]["spacing_m"] == 0
        assert lo < routes[rid]["start_station"] < hi  # the start is on it


def test_ia1_opens_a_turn_lane_each_side(hw1):
    south, north = hw1.ends[J.IA1]
    assert hw1.turn_open(np.array([0.0, -60.0, 60.0])) == pytest.approx(1.0)
    assert hw1.turn_open(np.array([south, north])) == pytest.approx(0.0, abs=1e-6)
    assert hw1.edge(J.IA1, np.array(0.0)) == pytest.approx(J.TURN_PAVED)
    assert hw1.edge(J.IA22, np.array(0.0)) == pytest.approx(J.PAVED)


def test_the_pavement_takes_in_every_turning_lane(hw1):
    paved = hw1.paved.buffer(0.05)
    assert hw1.paved.is_valid and hw1.paved.geom_type == "Polygon"
    for q in J.SLIPS:
        mid, outer, inner = hw1.slip_edges(q)
        assert shapely.contains_xy(paved, *mid.T).all()
        assert shapely.contains_xy(paved, *inner.T).all()
    # ...and both highways right across, at their stop lines.
    for k, t in ((J.IA1, -J.STOP_LINE[J.IA1]), (J.IA22, J.STOP_LINE[J.IA22])):
        w = np.linspace(-J.PAVED + 0.1, J.PAVED - 0.1, 9)
        assert shapely.contains_xy(paved, *hw1.hw[k].point(np.full(w.shape, t), w).T).all()


def test_traffic_turns_right_round_each_corner(hw1):
    for q, sl in hw1.slips.items():
        mid, _, _ = hw1.slip_edges(q)
        if sl["from"] == J.IA1:
            mid = mid[::-1]
        d = np.diff(mid, axis=0)
        cross = d[:-1, 0] * d[1:, 1] - d[:-1, 1] * d[1:, 0]  # x east, z south: a right turn is positive
        assert cross.sum() > 0, q


def test_it_meets_the_route_on_its_cross_section(hw1, routes):
    p = np.array(routes[J.IA1]["points"]).reshape(-1, 3)
    for s in J.ENDS[J.IA1]:
        h = hw1.hw[J.IA1]
        t = (s - h.s0) * h.sense
        w = np.array([-J.PAVED, -2.0, 0.0, 2.0, J.PAVED])
        pts = h.point(np.full(w.shape, t), w)
        expected = p[int(s / 2.0), 1] + J.CROWN * (1.0 - np.abs(w) / J.PAVED)
        assert np.abs(hw1.heights(pts) - expected).max() < 0.005


def test_the_paint_is_on_the_pavement(hw22):
    paint = hw22.paint()
    assert set(paint) == {"white", "yellow", "black"}
    on = hw22.paved.buffer(0.1)
    for color, polys in paint.items():
        assert polys, color
        assert all(on.contains(g) for g in polys), color
    # The double yellow is two lines a hair apart, all the way along both highways.
    assert sum(g.length for g in paint["yellow"]) / 2 > 2 * (sum(abs(t) for t in hw22.ends[J.IA1]) - 30)


def test_signs_face_the_traffic_they_stop(hw1):
    for s in hw1.stops():
        to_middle = hw1.center - s["at"]
        assert np.dot(s["forward"], to_middle) > 0  # traffic comes in toward the middle
    assert len(hw1.yields()) == 4 and len(hw1.lights()) == len(J.LIGHTS)
    for light in hw1.lights():
        assert not shapely.contains_xy(hw1.paved, *light["at"])
