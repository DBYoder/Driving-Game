"""The web server: the game's files with the right headers, and the leaderboard."""
import gzip
import os

os.environ["HIGHWAY_NO_APP"] = "1"  # (no default app, and no leaderboard.db, on import)

import pytest
from starlette.testclient import TestClient

import app as server


@pytest.fixture
def client(tmp_path):
    game = tmp_path / "public"
    game.mkdir()
    (game / "index.html").write_text("<html>Highway 1</html>")
    (game / "index.wasm").write_bytes(b"\0asm" + b"x" * 1000)
    (game / "index.wasm.gz").write_bytes(gzip.compress(b"\0asm" + b"x" * 1000))
    store = server.Store(path=str(tmp_path / "runs.db"))
    return TestClient(server.create_app(game, store, server.RateLimit(1000, 60.0)))


def run(**over):
    body = {"route": "highway1", "name": "Dave", "points": 12000, "seconds": 900.5, "car": "legend",
            "condition": "summer", "version": "v0.9"}
    body.update(over)
    return body


def test_serves_the_game_cross_origin_isolated(client):
    r = client.get("/")
    assert r.status_code == 200 and "Highway 1" in r.text
    assert r.headers["cross-origin-opener-policy"] == "same-origin"
    assert r.headers["cross-origin-embedder-policy"] == "require-corp"
    r = client.get("/index.wasm", headers={"Accept-Encoding": "gzip"})
    assert r.headers["content-type"] == "application/wasm"
    assert r.headers["content-encoding"] == "gzip"
    assert r.content.startswith(b"\0asm")  # (the client unpacks it)
    again = client.get("/index.wasm", headers={"Accept-Encoding": "gzip", "If-None-Match": r.headers["etag"]})
    assert again.status_code == 304
    plain = client.get("/index.wasm", headers={"Accept-Encoding": "identity", "If-None-Match": r.headers["etag"]})
    assert plain.status_code == 200 and "content-encoding" not in plain.headers, "the unzipped file is another version"


def test_nothing_outside_the_game_folder(client):
    assert client.get("/../runs.db").status_code == 404
    assert client.get("/nope.js").status_code == 404


def test_top_ten_times_and_points(client):
    for i in range(12):
        assert client.post("/api/runs", json=run(name=f"P{i}", seconds=600.0 + i, points=1000 * i)).status_code == 200
    client.post("/api/runs", json=run(name="Wreck", seconds=None, points=99999))
    board = client.get("/api/leaderboard", params={"route": "highway1"}).json()
    assert [e["name"] for e in board["times"]] == [f"P{i}" for i in range(10)]
    assert board["points"][0]["name"] == "Wreck" and len(board["points"]) == 10
    assert client.get("/api/leaderboard", params={"route": "highway22"}).json()["times"] == []


def test_a_new_run_hears_where_it_placed(client):
    client.post("/api/runs", json=run(name="Slow", seconds=1200.0, points=100))
    r = client.post("/api/runs", json=run(name="Fast", seconds=700.0, points=50)).json()
    assert r["time_rank"] == 1 and r["points_rank"] == 2


@pytest.mark.parametrize("bad", [
    {"route": "highway9"}, {"car": "corvette"}, {"condition": "fog"}, {"name": ""}, {"name": "x" * 17},
    {"name": "<script>"}, {"points": -1}, {"points": 1.5}, {"points": True}, {"seconds": 60.0},
    {"seconds": 1e9}, {"seconds": "fast"},
])
def test_bad_runs_are_turned_away(client, bad):
    assert client.post("/api/runs", json=run(**bad)).status_code == 400


def test_names_are_tidied(client):
    r = client.post("/api/runs", json=run(name="  Big   Dave ")).json()
    assert r["times"][0]["name"] == "Big Dave"


def test_too_many_runs_from_one_place(tmp_path):
    store = server.Store(path=str(tmp_path / "runs.db"))
    c = TestClient(server.create_app(tmp_path, store, server.RateLimit(2, 60.0)))
    codes = [c.post("/api/runs", json=run()).status_code for _ in range(3)]
    assert codes == [200, 200, 429]
