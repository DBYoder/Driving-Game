# Highway 1

A tiny, private, chaotic arcade driving game set on real Iowa highways out of Kalona's
four-way stop: **15 miles of Iowa Highway 1 north to the first stop light in Iowa City
(Mormon Trek Blvd)**, or **7 miles of Iowa Highway 22 west to downtown Wellman**.
Made for fun with friends; not for sale. The full plan is in [PLAN.md](PLAN.md).

**Play it:** grab `HighwayOne-windows.zip` from the
[latest release](https://github.com/DBYoder/Driving-Game/releases/latest), unzip, run
`HighwayOne.exe`. (Windows will warn about an unknown publisher: *More info → Run anyway*.)
Or play it in a browser, with a shared leaderboard: see [docs/WEB.md](docs/WEB.md).

| | |
|---|---|
| ![Highway 22: the start in Kalona, facing west](docs/screenshots/highway22-kalona-start.png) | ![Highway 22: Wellman, from above](docs/screenshots/highway22-wellman-from-above.png) |
| ![Mid-Prairie High School from IA 22, a mile from Wellman](docs/screenshots/highway22-mid-prairie.png) | ![Mid-Prairie High School from above: the school, the lots, the sign by the road](docs/screenshots/highway22-mid-prairie-from-above.png) |
| ![The 1998 Ford Windstar](docs/screenshots/windstar.png) | ![The 1993 Acura Legend](docs/screenshots/legend.png) |
| ![The 1997 Toyota Tercel](docs/screenshots/tercel.png) | ![A beat-up Tercel: mirrors and bumpers gone](docs/screenshots/tercel-beat-up.png) |
| ![Behind the wheel of the Legend at harvest dusk: the dash, the gauges, the radio](docs/screenshots/in-car-legend.png) | ![The Windstar's dash at night, its gauges lit](docs/screenshots/in-car-night.png) |
| ![Stopped at the four-way stop in Kalona, a buggy waiting its turn](docs/screenshots/kalona-4-way-stop.png) | ![The finish: the stop light at Mormon Trek Blvd](docs/screenshots/mormon-trek-finish.png) |
| ![Kalona from above: streets, houses and lawns](docs/screenshots/kalona-from-above.png) | ![A gravel crossroad and the power line, mile 5.7](docs/screenshots/gravel-crossroad.png) |
| ![The title screen](docs/screenshots/title.png) | ![Settings](docs/screenshots/settings.png) |
| ![Kalona Cheese at 540th St, mile 3.9](docs/screenshots/kalona-cheese.png) | ![Boosting away from a Johnson County deputy](docs/screenshots/boost-escape.png) |
| ![Real farmsteads and tree lines at mile 2, from lidar](docs/screenshots/mile-2-farmsteads.png) | ![Night: headlights, lit windows, yard lights](docs/screenshots/night.png) |
| ![Harvest dusk: stubble, brown corn, a combine](docs/screenshots/harvest-dusk.png) | ![Thunderstorm](docs/screenshots/thunderstorm.png) |
| ![Winter near Iowa City](docs/screenshots/winter.png) | ![The garage](docs/screenshots/garage.png) |
| ![Traffic north of Kalona](docs/screenshots/mile-1-traffic.png) | ![Corn near mile 5](docs/screenshots/mile-5-corn.png) |
| ![The long view](docs/screenshots/mile-7-drone.png) | ![A beat-up Legend](docs/screenshots/legend-beat-up.png) |
| ![A Johnson County deputy on a Windstar's tail](docs/screenshots/speed-trap-chase.png) | ![Deer crossing near the creek at mile 4](docs/screenshots/deer-crossing.png) |

## Status

**v0.9: in a browser, with a shared leaderboard.** The game runs in a browser too, from a
small server on Railway that anyone with the address can open. It keeps the top ten
times and the top ten scores on each route from everyone's runs: after your first run
it asks your name, the results say where you placed, and the title screen has the
Leaderboard. (No radio in the browser.) Every merge to `main` redeploys it. How it's
set up: [docs/WEB.md](docs/WEB.md).

**v0.9.1: on phones and tablets.** Touch controls (slide a thumb on the left to steer;
gas, brake, boost, handbrake and horn on the right), tappable menus and garage, the
phone's own keyboard for the leaderboard name, sideways full screen, and lighter graphics
to start with. The web build is single-threaded now, so it runs on iPhones too.

**v0.9.4: sound on phones.** The sound stuttered a little on phones in the browser: the
game mixes it between frames there, and a phone's slower frames could let the browser's
sound run out. It now keeps twice as much ready.

**v0.9.3: a once-over.** Fixes from a pass through the whole game: the game froze for a
moment coming up on thick woods (up to a second and a half on Highway 22), and building
the world as you drive hitched; iPads got a PC's graphics settings (too much for them);
the title screen's car could set your records and post to the leaderboard; bridge
shoulders and the town gutters drove like gravel (and the grass verge did too); mailboxes
scored after the finish; a chase carried on over the finish line, or into the garage;
typing your name drove the car. And past the finish the road now ends at a ROAD CLOSED
barricade, the phone's pedals stay up so you can drive on into town, and the results tuck
away while you do.

**v0.9.2: into town.** The road no longer just stops at the finish: it carries on into
Iowa City past Mormon Trek and on through Wellman, with curbs and street lights. Wellman
is built up after its aerial photos and the lidar: downtown 8th Ave's brick storefronts
(signs, awnings, sidewalks, angle-parked cars, lamp posts), the WELLMAN water tower, and
the co-op's grain bins and elevators (on Highway 1 too). The in-car view is refitted to
the new bodies: the dash meets the hood all the way across, and the pillars, roof and
doors follow the body, so there's nowhere to see out through it.

**v0.8: a second route, Highway 22 from Kalona to Wellman.** Pick it on the garage's
new Route line. It starts in the same 4-way stop, pointed west straight out of it, and
runs 6.7 miles over Ramsey Creek, the English River and Lime Creek, past Mid-Prairie High
School, into downtown Wellman, where 8th Ave stops for you at the finish. Its 2,066 real
buildings and 72,000 trees are from the lidar like Highway 1's; it's all Washington County
(two deputies, no county line to run for), and it keeps its own records. Both routes now
have real bridges where they cross a creek or river: a concrete deck, guardrails, striped
end markers and the water underneath. Highway 1 also gains its missing Old Mans Creek sign.
And the three cars are rebuilt after photos of the real ones: rounded bodies, flush side
glass between real pillars, their own lights, grilles, trim and wheels, in the photos' colors.
And the four-way stop where both runs start is laid out like the real one: concrete, IA 1's
left-turn lanes, a free right turn round every corner with its gore striped and a YIELD
sign, IA-1 painted across the lane, light poles over the turning lanes, and the KALONA
welcome sign by the flagpole on the southwest corner.

**v0.7.2:** an in-car view with a working dash (speedometer, tachometer, fuel, temperature, odometer, warning lights, the radio's clock): press C or Y. And no more tires poking through the bodywork: every car has wheel arches now, and a test throws each one through every pose to make sure.

**v0.7.1:** the engine and tires are audible now (screeching, gravel crunch, road and wind noise), on laptop and TV speakers too.

**v0.7: graphical polish, and the real start and finish.**
- **The run** starts stopped at the stop sign at the IA-22 four-way stop in Kalona (stop signs and ALL WAY plates on every corner, stop lines, an Amish buggy waiting its turn) and ends at the first stop light in Iowa City, at Mormon Trek Blvd (signals that cycle, on mast arms). 15.4 miles.
- **Side roads and streets:** every road within 700 m of the highway, from the USGS road data: paved in town and on the highways, gravel out in the country. You can drive down them.
- **Towns** are lawns and houses, not corn; farmyards get lawns too.
- **Power lines** along the highway, crossing over now and then.
- **The sky** has clouds for each condition (and stars at night).
- **Tires** leave skid marks on the asphalt and ruts in the gravel and grass, and kick up dust, smoke, spray or snow.
- **Fixed:** the corn popping in and out in a wave as you drive.

**v0.6: polish.**
- **Menus:** a title screen (your last car cruising up the road), a pause menu on Esc, settings and a records table.
- **Settings:** Low/Medium/High graphics, resolution, scenery, full screen, three volumes and controller rumble.
- **Practice mode:** start at any mile; nothing's saved.
- **Sound:** synthesized crashes, smashes, landings, tire squeal and a horn for each car (it scares deer off the road). The controller rumbles along.
- **Results:** every run gets a title ("Minivan gymnastics: a perfect 10.").

**v0.5.1, after the v0.5 playtest:**
- **The boost.** Near misses fill a boost meter; hold Shift (or B) to burn it. It's the way to lose a cop now: deputies drive a little faster than your car can, and two full boosts leave them behind.
- **Kalona Cheese**, the old cheese factory and Kalona Creamery store at 540th St, built by hand from a photo at its real spot and size.

**v0.5: it's *our* Highway 1.** Every farmhouse, barn, machine shed, grain bin and
tree line along the road is where it really is, found in USGS lidar: 2,355 buildings
and 82,000 trees. The creeks, the county line and the Iowa City limit are signed with
their real names. Five conditions to drive it in, each with its own records: summer
afternoon, harvest dusk (combines!), night (headlights, deer ×3), a thunderstorm (wet
roads, gusts) and winter (black ice where the trees shade the road, snowplows). Drop
your own music in the `radio/` folder and the car radio plays it.

**Since v0.4:** sheriff's deputies run speed traps and chase you; get busted, lose them,
or drag the Washington County deputy over the county line. Deer bolt across near the
creeks: hold your line and they miss you.

The cars (since v0.3) are a 1998 Windstar, a Tercel and an Acura Legend. Each has its
own handling, toughness and points multiplier, plus dents and signature parts that fly
off; you pick one and a paint color in the garage. They drive the actual Highway 1:
real curves, hills, crossroads, street names and passing zones from USGS data, with a
long view (haze out to 3 km) and deep corn fields.

It's a score attack from Kalona to Iowa City: smash mailboxes, fences and hay
bales, plow corn, get air, near-miss oncoming traffic, get around Amish buggies and
tractors, and don't wreck. Low-poly, built to run on a potato. See the roadmap in
PLAN.md for what's next.

## Layout

```
game/                  Godot 4.6.3 project (GL Compatibility renderer)
  data/routes/<id>/    each route's baked road, terrain, horizon, buildings, trees and names
                       (highway1, highway22; generated, committed)
  scripts/route/       Routes (the routes and which is on), RouteData, TerrainTiles,
                       HorizonTerrain: loading and querying the baked data
  scripts/world/       road, street and terrain meshes and colliders, streaming, roadside
                       signs, the start and finish intersections, power lines, the lidar
                       buildings and trees (Scenery), hand-built landmarks, weather and
                       black ice
  scripts/car/         raycast car physics, the three cars (CarStats), models and damage,
                       the boost, drivers, engine sound, skid marks and dust
  scripts/game/        run rules, scoring and combos, records, the conditions, the radio, sound
                       effects, run titles, QA drives
  scripts/props/       mailboxes, fences, hay bales, corn clumps and the corn canopy
  scripts/traffic/     other road users and crashing into them
  scripts/cops/        speed traps, chases and their rules, the deputies' driving, the siren
  scripts/hazards/     deer
  scripts/ui/          the HUD, results, the garage (car select), the title screen and menus
  scripts/autoload/    the controls and the player's settings
  shaders/             flat-shaded terrain, road and street paint, the corn canopy, the sky
  tests/               headless GDScript tests
server/                the web server: the game in a browser and the shared leaderboard (docs/WEB.md)
tools/                 Python pipeline that bakes the road, streets, buildings, trees and names from USGS data
docs/                  route previews, screenshots, the README that ships in the zip
.github/workflows/     CI: tests, Windows/Linux/web export, screenshots, releases, the web deploy
```

## Developing

**Game:** install [Godot 4.6.3](https://godotengine.org/download/archive/4.6.3-stable/)
(standard build, not .NET), open `game/project.godot`, press F5.

```sh
godot --headless --path game --import                   # first time, or after adding files
godot --headless --path game -s res://tests/run_tests.gd  # unit tests
godot --path game -- --car=tercel --station=15000 --view=3  # skip the garage, mid-route, drone view
godot --path game -- --route=highway22 --car=legend        # Highway 22, Kalona to Wellman
godot --path game -- --autopilot --autopilot-mph=90       # watch the autopilot drive (and pass)
godot --path game -- --station=2400 --traffic-near        # start with traffic in view
godot --path game -- --car=windstar --station=6000 --chase  # a deputy already on your tail
godot --path game -- --car=windstar --station=6000 --chase --boost  # ...and a full boost burning
godot --path game -- --station=6600 --deer=25 --view=1     # deer crossing just ahead, from the driver's seat
godot --path game -- --condition=night --car=legend        # summer, harvest, night, storm, winter
godot --path game -- --scenery=0.5                         # half the trees (F2 in the game)
godot --path game -- --preset=low                          # a graphics preset, just for this run
godot --path game -- --title --menu=settings               # straight to a menu (settings, records, pause)
godot --path game -- --garage --practice                   # the garage for a practice run

# Automated test drives, headless and ~25x faster than real time:
godot --headless --fixed-fps 60 --path game -- --qa-drive            # autopilot, all 15 miles
godot --headless --fixed-fps 60 --path game -- --qa-drive --route=highway22  # ...or to Wellman
godot --headless --fixed-fps 60 --path game -- --qa-stress --seed=1  # hooligan inputs
godot --headless --fixed-fps 60 --path game -- --qa-drift            # scripted handbrake turn
godot --headless --fixed-fps 60 --path game -- --qa-cops=bust --no-traffic  # get busted (or =line)
godot --headless --fixed-fps 60 --path game -- --qa-cops=boost --no-traffic # boost away from a deputy
godot --headless --fixed-fps 60 --path game -- --qa-deer --no-traffic       # a herd, then a hit
godot --headless --fixed-fps 60 --path game -- --qa-menus                    # click through every menu
godot --path game -- --benchmark                                      # fps, draw calls, triangles
godot --path game -- --car=legend --damage=0.7 --orbit                # look at the damage
godot --path game -- --tune=handbrake_grip:0.5                        # try a CarStats tweak
```

**Road data:** only needed to re-bake (the baked files are committed). Each route is in
`tools/config.py` ROUTES; every script takes `--route=highway1` (the default) or
`--route=highway22`.

```sh
pip install -r tools/requirements.txt
python tools/bake_route.py     # downloads ~190 MB of USGS road data once, caches it in tools/.cache/
python tools/bake_places.py    # creek, county and city names for the signs, and the city limits
python tools/bake_streets.py   # the side roads and town streets
python tools/bake_lidar.py     # buildings and trees from USGS lidar (~1.5 GB once, ~20 min)
python tools/bake_lidar.py --yards  # after editing the route's landmarks.json
python tools/bake_lidar.py --extend OLD/route.json  # just the tiles near road added past the old end
python tools/preview_route.py  # writes the route-map and profile PNGs to eyeball the result
python tools/bake_route.py --route=highway22   # (and the same for the others): Kalona to Wellman
python -m pytest tools/tests
```

**Web server:** see [docs/WEB.md](docs/WEB.md) (`python -m pytest server/tests`).

Pushes to `main` build a Windows zip and publish it as a GitHub release, and push the
web build to the `web` branch, which Railway serves.

## Data credits

- Road centerlines: USGS National Transportation Dataset (NTD) for Iowa, public domain.
- Elevation: USGS 3D Elevation Program, 1/3 arc-second DEM, public domain.
- Engine: [Godot](https://godotengine.org), MIT license.
