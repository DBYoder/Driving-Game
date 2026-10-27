import math

import numpy as np

import bake_aerial as ba


def test_samples_cover_the_roof_inside_its_edges():
    b = {"x": 10.0, "z": -20.0, "length": 12.0, "width": 8.0, "yaw": math.radians(30.0)}
    o = {"easting": 600000.0, "northing": 4600000.0}
    e, n = ba.samples(b, o)
    assert len(e) > 50
    # Back into the building's own frame: all inside, ba.INSET_M in from the walls.
    de, dn = e - (b["x"] + o["easting"]), n - (o["northing"] - b["z"])
    c, s = math.cos(b["yaw"]), math.sin(b["yaw"])
    u, v = de * c + dn * s, -de * s + dn * c
    assert np.abs(u).max() <= b["length"] / 2 - ba.INSET_M + 1e-6
    assert np.abs(v).max() <= b["width"] / 2 - ba.INSET_M + 1e-6
    assert abs(u.mean()) < 0.1 and abs(v.mean()) < 0.1


def test_a_roof_color_leaves_out_leaves_and_shadow():
    rng = np.random.default_rng(3)
    red = np.column_stack([rng.normal(150, 6, 60), rng.normal(50, 4, 60), rng.normal(45, 4, 60), np.full(60, 255)])
    leaves = np.column_stack([np.full(30, 60), np.full(30, 110), np.full(30, 50), np.full(30, 255)])
    shadow = np.column_stack([np.full(10, 8), np.full(10, 8), np.full(10, 10), np.full(10, 255)])
    color = ba.roof_color(np.vstack([red, leaves, shadow]))
    assert color is not None and 140 < color[0] < 165 and color[1] < 70, color


def test_no_color_for_a_roof_under_trees_or_off_the_photos():
    leaves = np.column_stack([np.full(40, 60), np.full(40, 110), np.full(40, 50), np.full(40, 255)])
    roof = np.column_stack([np.full(5, 200), np.full(5, 200), np.full(5, 200), np.full(5, 255)])
    assert ba.roof_color(np.vstack([leaves, roof])) is None
    assert ba.roof_color(np.zeros((30, 4))) is None  # alpha 0: no photo there
