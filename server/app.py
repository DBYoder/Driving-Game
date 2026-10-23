"""Highway 1 on the web: the game itself, and its shared leaderboard.

Serves the Godot web build (GAME_DIR, default ./public) with the headers its threads
need (cross-origin isolated), using the gzip copies made at build time when the browser
takes them, and a small JSON API:

  GET  /api/leaderboard?route=highway1   the top ten times and the top ten scores on a route
  POST /api/runs                          a run that ended, finished or not: {route, name,
                                          points, seconds (null if it didn't finish), car,
                                          condition, version}; answers with where it placed
  GET  /api/health

Runs are kept in Postgres when DATABASE_URL is set (Railway's Postgres), else in SQLite
(LEADERBOARD_DB, default ./leaderboard.db: fine for trying it out, but on Railway it's
wiped on every deploy unless it's on a volume).

Run it:  uvicorn app:app --port 8080
"""

from __future__ import annotations

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

# The fastest believable time on each route: 150 mph the whole way (Highway 1 is 15.4
# miles, Highway 22 6.75). Anything quicker is someone poking at the API.
ROUTES = {"highway1": 15.37 / 150.0 * 3600.0, "highway22": 6.75 / 150.0 * 3600.0}
CARS = {"windstar", "tercel", "legend"}
CONDITIONS = {"summer", "harvest", "night", "storm", "winter"}
MAX_SECONDS = 3 * 3600.0
MAX_POINTS = 5_000_000
NAME = re.compile(r"^[A-Za-z0-9 .'_-]{1,16}$")
TOP = 10
POSTS_PER_WINDOW = 20  # runs one address can post...
WINDOW_SECONDS = 600.0  # ...in this long
# What the browser needs for the game's threads (SharedArrayBuffer).
ISOLATION = {
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
    "Cross-Origin-Resource-Policy": "same-origin",
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
            cur.execute("CREATE INDEX IF NOT EXISTS runs_by_time ON runs (route, seconds)")
            cur.execute("CREATE INDEX IF NOT EXISTS runs_by_points ON runs (route, points)")
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
            cur.execute(self._sql("""INSERT INTO runs (route, name, points, seconds, car, condition, version, created)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id"""),
                        (run["route"], run["name"], run["points"], run["seconds"], run["car"], run["condition"],
                         run["version"], time.time()))
            new_id = cur.fetchone()[0]
            db.commit()
            return int(new_id)

    def top(self, route: str) -> dict:
        cols = "id, name, points, seconds, car, condition, created"
        with self._connect() as db:
            cur = db.cursor()
            cur.execute(self._sql(f"SELECT {cols} FROM runs WHERE route = ? AND seconds IS NOT NULL "
                                  "ORDER BY seconds ASC, created ASC LIMIT ?"), (route, TOP))
            times = cur.fetchall()
            cur.execute(self._sql(f"SELECT {cols} FROM runs WHERE route = ? ORDER BY points DESC, created ASC LIMIT ?"),
                        (route, TOP))
            points = cur.fetchall()
        return {"times": [_entry(r) for r in times], "points": [_entry(r) for r in points]}


def _entry(row) -> dict:
    run_id, name, points, seconds, car, condition, created = row
    return {"id": run_id, "name": name, "points": points, "seconds": seconds, "car": car,
            "condition": condition, "date": time.strftime("%Y-%m-%d", time.gmtime(created))}


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
    return {"route": route, "name": name, "points": int(points), "seconds": seconds, "car": car,
            "condition": condition, "version": version}, ""


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

    async def leaderboard(request: Request) -> Response:
        route = request.query_params.get("route", "")
        if route not in ROUTES:
            return JSONResponse({"error": "unknown route"}, status_code=400)
        board = await run_in_threadpool(store.top, route)
        return JSONResponse({"route": route, **board}, headers={"Cache-Control": "no-store"})

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
        return JSONResponse({"id": new_id, "time_rank": rank(board["times"]), "points_rank": rank(board["points"]),
                             "route": run["route"], **board})

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
