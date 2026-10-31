"""Highway 1 on the web: the game itself, and its shared leaderboard.

Serves the Godot web build (GAME_DIR, default ./public), cross-origin isolated (the
single-threaded build doesn't need it, but a threaded one would), using the gzip copies
made at build time when the browser takes them, and a small JSON API:

  GET  /api/leaderboard?route=highway1   the top ten times and the top ten scores on a route
       &challenge=2026-10-31              ...from that day's daily challenge only
  POST /api/runs                          a run that ended, finished or not: {route, name,
                                          points, seconds (null if it didn't finish), car,
                                          condition, version, challenge (the day, or absent)};
                                          answers with where it placed (and on the day's
                                          challenge, where it placed that day)
  GET  /api/health
  GET  /manifest.webmanifest              lets a phone keep it on the home screen, full screen
                                          and sideways

Runs are kept in Postgres when DATABASE_URL is set (Railway's Postgres), else in SQLite
(LEADERBOARD_DB, default ./leaderboard.db: fine for trying it out, but on Railway it's
wiped on every deploy unless it's on a volume).

Run it:  uvicorn app:app --port 8080
"""

from __future__ import annotations

import calendar
import contextlib
import json
import math
import mimetypes
import os
import re
import sqlite3
import threading
import time
from collections import defaultdict, deque
from pathlib import Path

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse, Response
from starlette.routing import Route

# The fastest believable time on each route (and the way back along it): 150 mph the
# whole way (Highway 1 is 15.4 miles, Highway 22 6.75). Anything quicker is someone poking
# at the API.
ROUTES = {"highway1": 15.37 / 150.0 * 3600.0, "highway22": 6.75 / 150.0 * 3600.0,
          "highway1_south": 15.37 / 150.0 * 3600.0, "highway22_east": 6.75 / 150.0 * 3600.0}
CARS = {"windstar", "tercel", "legend"}
CONDITIONS = {"summer", "harvest", "night", "storm", "winter"}
MAX_SECONDS = 3 * 3600.0
MAX_POINTS = 5_000_000
NAME = re.compile(r"^[A-Za-z0-9 .'_-]{1,16}$")
TOP = 10
# The daily challenge: the day (UTC) picks the route, car and condition, the same way the
# game does (game/scripts/game/challenge.gd: change one, change the other). Its runs count
# on the route's boards too, and on the day's own. A day's challenge takes runs from an
# hour before it starts (a clock a little fast) until two hours after it ends.
CHALLENGE_ROUTES = ["highway1", "highway22", "highway1_south", "highway22_east"]
CHALLENGE_CARS = ["windstar", "tercel", "legend"]
CHALLENGE_CONDITIONS = ["summer", "harvest", "night", "storm", "winter"]
CHALLENGE_EARLY = 3600.0
CHALLENGE_LATE = 2 * 3600.0
DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")
POSTS_PER_WINDOW = 20  # runs one address can post...
WINDOW_SECONDS = 600.0  # ...in this long
# Cross-origin isolation: what a threaded build would need (SharedArrayBuffer); harmless
# for the single-threaded one the game ships as (docs/WEB.md).
ISOLATION = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
}
# "Add to Home Screen": the game opens full screen and sideways, like an app.
MANIFEST = {
    "name": "Highway 1", "short_name": "Highway 1", "start_url": ".", "scope": ".",
    "display": "fullscreen", "orientation": "landscape",
    "background_color": "#000000", "theme_color": "#000000",
    "icons": [{"src": "index.apple-touch-icon.png", "sizes": "180x180", "type": "image/png"},
              {"src": "index.icon.png", "sizes": "128x128", "type": "image/png"}],
}
TYPES = {".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript",
         ".html": "text/html; charset=utf-8", ".png": "image/png"}


class Store:
    """The runs: Postgres if a URL is given, else a SQLite file."""

    def __init__(self, url: str | None = None, path: str | None = None):
        self.url = url
        self.path = path or "leaderboard.db"
        self._lock = threading.Lock()
        serial = "BIGSERIAL PRIMARY KEY" if url else "INTEGER PRIMARY KEY AUTOINCREMENT"
        with self._connect() as db:
            cur = db.cursor()
            cur.execute(f"""CREATE TABLE IF NOT EXISTS runs (
                id {serial}, route TEXT NOT NULL, name TEXT NOT NULL, points INTEGER NOT NULL,
                seconds DOUBLE PRECISION, car TEXT NOT NULL, condition TEXT NOT NULL,
                version TEXT NOT NULL, created DOUBLE PRECISION NOT NULL)""")
            if url:
                cur.execute("ALTER TABLE runs ADD COLUMN IF NOT EXISTS challenge TEXT")
            elif "challenge" not in [row[1] for row in cur.execute("PRAGMA table_info(runs)").fetchall()]:
                cur.execute("ALTER TABLE runs ADD COLUMN challenge TEXT")  # (a board from before the challenge)
            cur.execute("CREATE INDEX IF NOT EXISTS runs_by_time ON runs (route, seconds)")
            cur.execute("CREATE INDEX IF NOT EXISTS runs_by_points ON runs (route, points)")
            cur.execute("CREATE INDEX IF NOT EXISTS runs_by_day ON runs (challenge, seconds)")
            db.commit()

    @contextlib.contextmanager
    def _connect(self):
        if self.url:
            import psycopg  # only needed with Postgres
            db = psycopg.connect(self.url)
        else:
            db = sqlite3.connect(self.path)
        try:
            yield db
        finally:
            db.close()

    def _sql(self, q: str) -> str:
        return q.replace("?", "%s") if self.url else q

    def add(self, run: dict) -> int:
        with self._lock, self._connect() as db:
            cur = db.cursor()
            cur.execute(self._sql("""INSERT INTO runs (route, name, points, seconds, car, condition, version, created,
                challenge) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id"""),
                        (run["route"], run["name"], run["points"], run["seconds"], run["car"], run["condition"],
                         run["version"], time.time(), run.get("challenge")))
            new_id = cur.fetchone()[0]
            db.commit()
            return int(new_id)

    def top(self, route: str, challenge: str | None = None) -> dict:
        """The route's top tens, or a day's challenge's."""
        cols = "id, name, points, seconds, car, condition, created"
        where, args = ("route = ? AND challenge = ?", (route, challenge)) if challenge else ("route = ?", (route,))
        with self._connect() as db:
            cur = db.cursor()
            cur.execute(self._sql(f"SELECT {cols} FROM runs WHERE {where} AND seconds IS NOT NULL "
                                  "ORDER BY seconds ASC, created ASC LIMIT ?"), (*args, TOP))
            times = cur.fetchall()
            cur.execute(self._sql(f"SELECT {cols} FROM runs WHERE {where} ORDER BY points DESC, created ASC LIMIT ?"),
                        (*args, TOP))
            points = cur.fetchall()
        return {"times": [_entry(r) for r in times], "points": [_entry(r) for r in points]}


def _entry(row) -> dict:
    run_id, name, points, seconds, car, condition, created = row
    return {"id": run_id, "name": name, "points": points, "seconds": seconds, "car": car,
            "condition": condition, "date": time.strftime("%Y-%m-%d", time.gmtime(created))}


def _fnv(text: str) -> int:
    h = 2166136261
    for b in text.encode():
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


def _next(h: int) -> int:
    return (h * 1103515245 + 12345) & 0xFFFFFFFF


def challenge_for(day: str) -> dict:
    """A day's challenge: its route, car and condition (as the game picks them)."""
    h = _fnv(day)
    out = {}
    for key, options in (("route", CHALLENGE_ROUTES), ("car", CHALLENGE_CARS), ("condition", CHALLENGE_CONDITIONS)):
        h = _next(h)
        out[key] = options[(h >> 16) % len(options)]
    return out


def challenge_open(day: str, now: float | None = None) -> bool:
    """Whether a day's challenge still takes runs."""
    try:
        start = calendar.timegm(time.strptime(day, "%Y-%m-%d"))  # (00:00 UTC)
    except ValueError:
        return False
    now = time.time() if now is None else now
    return start - CHALLENGE_EARLY <= now <= start + 86400.0 + CHALLENGE_LATE


def check_run(body) -> tuple[dict | None, str]:
    """A posted run, cleaned up, or None and why not."""
    if not isinstance(body, dict):
        return None, "expected a JSON object"
    route, car, condition = body.get("route"), body.get("car"), body.get("condition")
    if route not in ROUTES:
        return None, "unknown route"
    if car not in CARS:
        return None, "unknown car"
    if condition not in CONDITIONS:
        return None, "unknown condition"
    name = " ".join(str(body.get("name", "")).split())
    if not NAME.match(name):
        return None, "a name is 1 to 16 letters, numbers, spaces or . ' _ -"
    points = body.get("points")
    if isinstance(points, bool) or not isinstance(points, (int, float)) or not math.isfinite(points) \
            or points < 0 or points > MAX_POINTS or points != int(points):
        return None, "points out of range"
    seconds = body.get("seconds")
    if seconds is not None:
        if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) \
                or seconds < ROUTES[route] or seconds > MAX_SECONDS:
            return None, "time out of range"
        seconds = round(float(seconds), 2)
    version = str(body.get("version", ""))[:16]
    day = body.get("challenge")
    if day is not None:
        if not isinstance(day, str) or not DAY.match(day):
            return None, "not a day"
        if not challenge_open(day):
            return None, "that day's challenge is over"
        if challenge_for(day) != {"route": route, "car": car, "condition": condition}:
            return None, "not that day's challenge"
    return {"route": route, "name": name, "points": int(points), "seconds": seconds, "car": car,
            "condition": condition, "version": version, "challenge": day}, ""


class RateLimit:
    def __init__(self, count: int, window: float):
        self.count, self.window = count, window
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, who: str) -> bool:
        now = time.monotonic()
        with self._lock:
            hits = self._hits[who]
            while hits and now - hits[0] > self.window:
                hits.popleft()
            if len(hits) >= self.count:
                return False
            hits.append(now)
            return True


def create_app(game_dir: str | Path | None = None, store: Store | None = None,
               limit: RateLimit | None = None) -> Starlette:
    game = Path(game_dir or os.environ.get("GAME_DIR", "public")).resolve()
    store = store or Store(os.environ.get("DATABASE_URL") or None, os.environ.get("LEADERBOARD_DB"))
    limit = limit or RateLimit(POSTS_PER_WINDOW, WINDOW_SECONDS)

    async def health(_: Request) -> Response:
        return JSONResponse({"ok": True})

    async def manifest(_: Request) -> Response:
        return JSONResponse(MANIFEST, media_type="application/manifest+json")

    async def leaderboard(request: Request) -> Response:
        day = request.query_params.get("challenge") or None
        if day is not None and not DAY.match(day):
            return JSONResponse({"error": "not a day"}, status_code=400)
        route = request.query_params.get("route") or (challenge_for(day)["route"] if day else "")
        if route not in ROUTES:
            return JSONResponse({"error": "unknown route"}, status_code=400)
        board = await run_in_threadpool(store.top, route, day)
        return JSONResponse({"route": route, "challenge": day, **board}, headers={"Cache-Control": "no-store"})

    async def post_run(request: Request) -> Response:
        who = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or \
            (request.client.host if request.client else "?")
        if not limit.allow(who):
            return JSONResponse({"error": "too many runs from here; try again in a few minutes"}, status_code=429)
        raw = await request.body()
        if len(raw) > 2048:
            return JSONResponse({"error": "too big"}, status_code=413)
        try:
            body = json.loads(raw)
        except ValueError:
            return JSONResponse({"error": "expected JSON"}, status_code=400)
        run, why = check_run(body)
        if run is None:
            return JSONResponse({"error": why}, status_code=400)
        new_id = await run_in_threadpool(store.add, run)
        board = await run_in_threadpool(store.top, run["route"])
        rank = lambda rows: next((i + 1 for i, r in enumerate(rows) if r["id"] == new_id), None)
        out = {"id": new_id, "time_rank": rank(board["times"]), "points_rank": rank(board["points"]),
               "route": run["route"], **board}
        if run["challenge"]:
            day = await run_in_threadpool(store.top, run["route"], run["challenge"])
            out.update({"challenge": run["challenge"], "challenge_time_rank": rank(day["times"]),
                        "challenge_points_rank": rank(day["points"])})
        return JSONResponse(out)

    async def static(request: Request) -> Response:
        rel = request.path_params.get("path", "") or "index.html"
        file = (game / rel).resolve()
        if not file.is_relative_to(game) or not file.is_file():
            return Response("Not found", status_code=404)
        kind = TYPES.get(file.suffix) or mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        packed = file.with_name(file.name + ".gz")
        gzipped = "gzip" in request.headers.get("accept-encoding", "") and packed.is_file()
        sent = packed if gzipped else file
        st = sent.stat()
        tag = f'"{st.st_mtime_ns:x}-{st.st_size:x}{"-gz" if gzipped else ""}"'
        headers = {"ETag": tag, "Cache-Control": "no-cache", "Vary": "Accept-Encoding"}
        if gzipped:
            headers["Content-Encoding"] = "gzip"
        if request.headers.get("if-none-match") == tag:
            return Response(status_code=304, headers=headers)
        return FileResponse(sent, media_type=kind, headers=headers)

    app = Starlette(routes=[
        Route("/api/health", health),
        Route("/manifest.webmanifest", manifest),
        Route("/api/leaderboard", leaderboard),
        Route("/api/runs", post_run, methods=["POST"]),
        Route("/", static),
        Route("/{path:path}", static),
    ])

    app.add_middleware(Isolate)
    return app


class Isolate:
    """Every response gets the cross-origin isolation headers (pure ASGI, so file
    responses stream as they are)."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)

        async def with_headers(message):
            if message["type"] == "http.response.start":
                message.setdefault("headers", [])
                message["headers"] = list(message["headers"]) + [(k.lower().encode(), v.encode()) for k, v in ISOLATION.items()]
            await send(message)

        await self.app(scope, receive, with_headers)


app = create_app() if os.environ.get("HIGHWAY_NO_APP") is None else None
