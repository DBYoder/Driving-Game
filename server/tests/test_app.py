"""The web server: the game's files with the right headers, and the leaderboard."""
import calendar
import gzip
import os
import sqlite3
import time

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


def test_a_phone_can_keep_it_on_the_home_screen(client):
    r = client.get("/manifest.webmanifest")
    assert r.status_code == 200 and r.headers["content-type"].startswith("application/manifest+json")
    m = r.json()
    assert m["display"] == "fullscreen" and m["orientation"] == "landscape" and m["start_url"] == "."


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


def test_the_daily_challenge_is_picked_like_the_game_picks_it():
    # (The same days and picks as game/tests/test_challenge.gd: the two must agree.)
    assert server.challenge_for("2026-10-31") == {"route": "highway22_east", "car": "legend", "condition": "harvest"}
    assert server.challenge_for("2026-11-01") == {"route": "highway1", "car": "legend", "condition": "storm"}
    assert server.challenge_for("2026-12-25") == {"route": "highway22", "car": "tercel", "condition": "harvest"}


def today_run(**over):
    day = time.strftime("%Y-%m-%d", time.gmtime())
    pick = server.challenge_for(day)
    seconds = 400.5 if pick["route"].startswith("highway22") else 900.5
    return run(**{"challenge": day, "seconds": seconds, **pick, **over})


def test_a_challenge_run_has_its_own_top_ten_and_counts_on_the_route_too(client):
    route = today_run()["route"]
    plain = client.post("/api/runs", json=run(route=route, seconds=380.0 if route.startswith("highway22") else 880.0))
    assert plain.status_code == 200
    r = client.post("/api/runs", json=today_run(name="Daily")).json()
    assert r["challenge_time_rank"] == 1 and r["challenge_points_rank"] == 1
    assert r["time_rank"] == 2, "the run that wasn't the challenge is still faster on the route's board"
    day = today_run()["challenge"]
    board = client.get("/api/leaderboard", params={"challenge": day}).json()
    assert board["route"] == route and board["challenge"] == day
    assert [e["name"] for e in board["times"]] == ["Daily"]
    route_board = client.get("/api/leaderboard", params={"route": route}).json()
    assert len(route_board["times"]) == 2


def test_only_the_days_challenge_and_only_while_its_on(client):
    pick = today_run()
    other_car = next(c for c in server.CHALLENGE_CARS if c != pick["car"])
    assert client.post("/api/runs", json=today_run(car=other_car)).json()["error"] == "not that day's challenge"
    assert client.post("/api/runs", json=run(challenge="2020-01-01", **server.challenge_for("2020-01-01"))) \
        .json()["error"] == "that day's challenge is over"
    for bad in ["today", "2026-13-01", 20261031]:
        assert client.post("/api/runs", json=today_run(challenge=bad)).status_code == 400
    assert client.get("/api/leaderboard", params={"challenge": "soon"}).status_code == 400


def test_a_challenge_takes_runs_until_two_hours_after_its_day():
    start = calendar.timegm((2026, 10, 31, 0, 0, 0))
    assert not server.challenge_open("2026-10-31", start - 3601)
    assert server.challenge_open("2026-10-31", start - 3600)  # (a clock a little fast)
    assert server.challenge_open("2026-10-31", start + 86400 + 7200)
    assert not server.challenge_open("2026-10-31", start + 86400 + 7201)
    assert not server.challenge_open("2026-02-30")


def test_a_board_from_before_the_challenge_gets_its_column(tmp_path):
    path = tmp_path / "old.db"
    db = sqlite3.connect(path)
    db.execute("""CREATE TABLE runs (id INTEGER PRIMARY KEY AUTOINCREMENT, route TEXT NOT NULL, name TEXT NOT NULL,
        points INTEGER NOT NULL, seconds DOUBLE PRECISION, car TEXT NOT NULL, condition TEXT NOT NULL,
        version TEXT NOT NULL, created DOUBLE PRECISION NOT NULL)""")
    db.execute("INSERT INTO runs (route, name, points, seconds, car, condition, version, created) "
               "VALUES ('highway1', 'Old', 5, 950.0, 'legend', 'summer', 'v0.9', 1.0)")
    db.commit()
    db.close()
    store = server.Store(path=str(path))
    assert store.top("highway1")["times"][0]["name"] == "Old"
    store.add({**run(), "challenge": "2026-10-31"})
    assert store.top("highway1", "2026-10-31")["times"][0]["name"] == "Dave"
