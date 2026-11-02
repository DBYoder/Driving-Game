# Highway 1 in a browser

The game also runs in a browser, from a small web server that keeps the shared
leaderboard: the top ten times and the top ten scores on each route (and each day's
daily challenge), from everyone's runs. It's open to anyone with the address; there's no
password.

## How it fits together

- **The web build** is Godot's Web export of the same game (`game/export_presets.cfg`,
  preset "Web"), single-threaded so it runs on iPhones and iPads too. Its page is
  `game/web/shell.html`: Godot's own, plus what phones need (below). In a browser there's
  no radio (no folder to put music in) and no Quit.
- **The server** (`server/app.py`) serves the game gzipped, with cross-origin isolation
  headers (harmless now; a threaded build would need them), the leaderboard's API and a
  web app manifest. Runs are kept in Postgres.
- **The game** posts every run that ends (finished or wrecked; not practice runs) with
  the player's name, asked once after their first run and changeable in Settings. The
  results screen says where it placed; the title screen's Leaderboard shows the top tens.
  The server checks every run (known route, car and condition; a name of 1 to 16
  letters, numbers, spaces or `. ' _ -`; no time quicker than 150 mph the whole way;
  20 runs per address per 10 minutes).
- **CI** exports the web build on every push and pull request, builds the server's
  Docker image and checks it serves the game and takes a run. On `main` it then pushes
  the server and the build to the **`web` branch** (one fresh commit each time; don't
  edit it). Railway watches that branch and redeploys when it changes, a few minutes
  after each merge.

## On phones and tablets

- **Touch controls** come up on a phone or tablet, and on any screen as soon as it's
  touched (a key or a gamepad puts them away again; Settings has Touch controls: Auto,
  On, Off). While driving: put a thumb down anywhere on the left and slide it to steer;
  GAS and BRAKE (hold it to back up) bottom right, with BOOST, HANDBRAKE and HORN above
  them; pause, camera and the tow truck top right. Menus take taps (the left or right of
  a setting steps it), the garage has Back and Drive buttons and arrows on every line,
  and the results have Run it again, Change car and Menu.
- **The name for the leaderboard** is asked in a box on the page itself, so the phone's
  own keyboard comes up.
- **Sideways only:** held upright, the page says to turn it. On Android the first tap
  goes full screen and locks it sideways. An iPhone can't do that in Safari, so while it
  loads the page suggests Share, then Add to Home Screen: from the home screen it opens
  full screen like an app (the server's manifest says so).
- **Lighter graphics:** a phone or tablet starts on Low, with the 3D drawn at about 600
  lines (their screens have two or three times a PC's pixels). Settings can change it.
- **Sound:** in the browser the game mixes its sound between frames, so it keeps about
  90 ms ready (`audio/driver/output_latency.web` = 100): enough to get over a phone's slow
  frames without a stutter. Godot's default left about 43 ms, less than a slow phone frame.
- Tested in Chrome's phone emulation (a Pixel 7 and an iPhone 14, sideways), about 240 MB
  of memory. Not yet on a real iPhone.

## Setting up Railway (once)

The `web` branch appears once this is merged into `main` and CI has finished (about
half an hour). Then, on [railway.com](https://railway.com):

1. Sign in with GitHub. A small game like this fits in the Hobby plan.
2. **New Project → Deploy from GitHub repo →** `DBYoder/Driving-Game`. (If Railway asks
   to be allowed into the repo, allow it.)
3. Open the new service, then **Settings → Source**: check the repo is
   `DBYoder/Driving-Game` (the pencil changes it), and set **Branch connected to
   production** to **`web`**. Railway finds the Dockerfile there and builds it. (Its first
   try, from `main`, fails: that's expected, `main` has no Dockerfile at the top.) If the
   repo or the `web` branch isn't offered, Railway can't see the repo yet: on GitHub,
   Settings → Applications → Railway → Configure, and add it under Repository access.
4. Back on the project, **+ Create → Database → PostgreSQL**.
5. In the game's service, **Variables → New Variable**: name `DATABASE_URL`, value
   `${{Postgres.DATABASE_URL}}` (Railway offers it as a reference). It redeploys.
6. **Settings → Networking → Generate Domain** (if it asks for a port, 8080). That's
   the address to share: anyone who opens it can play.
7. **Settings → Deploy → Healthcheck Path**: `/api/health`. A new build only takes over
   once it answers, so a broken one never replaces a working one.

To check on it: `https://<the address>/api/health` says `{"ok":true}`.

Without `DATABASE_URL` the server keeps the runs in a SQLite file inside the container,
which Railway wipes on every deploy: fine for a try, not for keeping scores.

## The Windows build and the leaderboard

The downloaded game posts to the same leaderboard once the project setting
`highway/leaderboard_url` (in `game/project.godot`) is set to the site's address. Until
then it has no Leaderboard and doesn't ask for a name.

## Running it yourself

```sh
godot --headless --path game --export-release "Web" ../build/web/index.html
pip install -r server/requirements.txt
GAME_DIR=build/web uvicorn --app-dir server app:app --port 8080
# then open http://localhost:8080
python -m pytest server/tests   # (pip install -r server/requirements-dev.txt)
```

The Web export needs Godot's export templates installed (`web_nothreads_release.zip`
and `web_nothreads_debug.zip` among them).
