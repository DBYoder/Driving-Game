import numpy as np
import pytest

import geo


def test_resample_hits_exact_stations():
    line = np.array([[0.0, 0.0], [10.0, 0.0], [10.0, 7.0]])
    pts = geo.resample(line, 2.0)
    assert len(pts) == 9  # 17 m of line -> stations 0..16
    assert np.allclose(pts[0], [0, 0])
    assert np.allclose(pts[5], [10, 0])
    assert np.allclose(pts[8], [10, 6])
    assert np.allclose(np.hypot(*np.diff(pts, axis=0).T)[:5], 2.0)


def test_resample_ignores_duplicate_vertices():
    line = np.array([[0.0, 0.0], [5.0, 0.0], [5.0, 0.0], [10.0, 0.0]])
    assert np.allclose(geo.resample(line, 1.0)[:, 0], np.arange(11))


def test_gaussian_smooth_keeps_straight_lines_and_endpoints():
    t = np.linspace(0, 100, 51)
    line = np.column_stack([t, 0.3 * t + 5])
    assert np.allclose(geo.gaussian_smooth(line, 6.0), line)


def test_gaussian_smooth_rounds_a_corner():
    corner = geo.resample(np.array([[0.0, 0.0], [50.0, 0.0], [50.0, 50.0]]), 1.0)
    smooth = geo.gaussian_smooth(corner, 5.0)
    i = 50  # the corner vertex
    assert np.hypot(*(smooth[i] - corner[i])) > 1.0
    assert np.allclose(smooth[0], corner[0]) and np.allclose(smooth[-1], corner[-1])


def test_fill_dips_fills_a_creek_but_keeps_a_valley():
    s = np.arange(400) * 2.0
    road = 200 - 10 * np.exp(-((s - 500) / 300) ** 2)  # broad valley the road follows
    creek = road.copy()
    creek[100:110] -= 4.0  # 20 m bridge gap in the bare-earth model
    filled = geo.fill_dips(creek, 30)
    assert np.abs(filled[100:110] - road[100:110]).max() < 1.0  # was 4 m deep
    assert np.allclose(filled[200:300], road[200:300], atol=0.15)


def test_runs():
    assert geo.runs(np.array([0, 1, 1, 0, 1, 0, 0, 1], dtype=bool)) == [(1, 3), (4, 5), (7, 8)]
    assert geo.runs(np.zeros(4, dtype=bool)) == []


def test_side_of():
    north = np.array([0.0, 1.0])
    assert geo.side_of(north, np.zeros(2), np.array([-5.0, 0.0])) == "left"
    assert geo.side_of(north, np.zeros(2), np.array([5.0, 1.0])) == "right"


def test_grid_sampler_is_exact_on_a_plane():
    res = 4.0
    rows, cols = 20, 30
    west, north = 1000.0, 5000.0
    # Pixel centers at (west + (c + .5) res, north - (r + .5) res); height = x/10 + y/20.
    xs = west + (np.arange(cols) + 0.5) * res
    ys = north - (np.arange(rows) + 0.5) * res
    data = xs[None, :] / 10 + ys[:, None] / 20
    sample = geo.GridSampler(data, west, north, res)
    x, y = np.array([1013.0, 1077.7]), np.array([4990.0, 4951.3])
    assert np.allclose(sample(x, y), x / 10 + y / 20)


def test_path_polyline_orients_edges():
    # Two segments stored "backwards" relative to travel still stitch into one path.
    lines = [np.array([[10.0, 0.0], [0.0, 0.0]]), np.array([[20.0, 0.0], [10.0, 0.0]])]
    g = geo.build_graph(lines)
    path = geo.path_polyline(g, geo.nearest_node(g, (0, 0)), geo.nearest_node(g, (20, 0)))
    assert np.allclose(path, [[0, 0], [10, 0], [20, 0]])


@pytest.mark.parametrize("spacing", [1.0, 2.0, 3.5])
def test_resample_spacing(spacing):
    pts = geo.resample(np.array([[0.0, 0.0], [100.0, 0.0]]), spacing)
    assert np.allclose(np.diff(pts[:, 0]), spacing)
