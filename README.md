# Highway 1

A tiny, private, chaotic arcade driving game set on 15 real miles of **Iowa Highway 1,
from the IA-22 four-way stop in Kalona to the first stop light in Iowa City (Mormon
Trek Blvd).**
Made for fun with friends; not for sale. The full plan is in [PLAN.md](PLAN.md).

**Play it:** grab `HighwayOne-windows.zip` from the
[latest release](https://github.com/DBYoder/Driving-Game/releases/latest), unzip, run
`HighwayOne.exe`. (Windows will warn about an unknown publisher: *More info → Run anyway*.)

| | |
|---|---|
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
  data/route/          baked road, terrain, horizon, buildings, trees and names (generated, committed)
  scripts/route/       RouteData, TerrainTiles, HorizonTerrain: loading and querying the baked data
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
tools/                 Python pipeline that bakes the road, streets, buildings, trees and names from USGS data
docs/                  route previews, screenshots, the README that ships in the zip
.github/workflows/     CI: tests, Windows/Linux export, screenshots, releases
```

## Developing

**Game:** install [Godot 4.6.3](https://godotengine.org/download/archive/4.6.3-stable/)
(standard build, not .NET), open `game/project.godot`, press F5.

```sh
godot --headless --path game --import                   # first time, or after adding files
godot --headless --path game -s res://tests/run_tests.gd  # unit tests
godot --path game -- --car=tercel --station=15000 --view=3  # skip the garage, mid-route, drone view
godot --path game -- --autopilot --autopilot-mph=90       # watch the autopilot drive (and pass)
godot --path game -- --station=2400 --traffic-near        # start with traffic in view
godot --path game -- --car=windstar --station=6000 --chase  # a deputy already on your tail
godot --path game -- --car=windstar --station=6000 --chase --boost  # ...and a full boost burning
godot --path game -- --station=6600 --deer=25 --view=1     # deer crossing just ahead
godot --path game -- --condition=night --car=legend        # summer, harvest, night, storm, winter
godot --path game -- --scenery=0.5                         # half the trees (F2 in the game)
godot --path game -- --preset=low                          # a graphics preset, just for this run
godot --path game -- --title --menu=settings               # straight to a menu (settings, records, pause)
godot --path game -- --garage --practice                   # the garage for a practice run

# Automated test drives, headless and ~25x faster than real time:
godot --headless --fixed-fps 60 --path game -- --qa-drive            # autopilot, all 15 miles
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

**Road data:** only needed to re-bake (the baked files are committed).

```sh
pip install -r tools/requirements.txt
python tools/bake_route.py     # downloads ~190 MB of USGS road data once, caches it in tools/.cache/
python tools/bake_places.py    # creek, county and city names for the signs, and the city limits
python tools/bake_streets.py   # the side roads and town streets
python tools/bake_lidar.py     # buildings and trees from USGS lidar (~1.5 GB once, ~20 min)
python tools/bake_lidar.py --yards  # after editing game/data/route/landmarks.json
python tools/bake_lidar.py --extend OLD/route.json  # just the tiles near road added past the old end
python tools/preview_route.py  # writes docs/route-preview/*.png to eyeball the result
python -m pytest tools/tests
```

Pushes to `main` build a Windows zip and publish it as a GitHub release.

## Data credits

- Road centerlines: USGS National Transportation Dataset (NTD) for Iowa, public domain.
- Elevation: USGS 3D Elevation Program, 1/3 arc-second DEM, public domain.
- Engine: [Godot](https://godotengine.org), MIT license.
