# Highway 1: Kalona → Iowa City — Game Plan

A tiny, private, chaotic arcade driving game set on one real stretch of road:
**Iowa Highway 1, from the IA-22 four-way stop in Kalona to the US-218 / IA-27
interchange on the edge of Iowa City.** It's built for fun with a few friends.
It's not for sale and not meant to be polished like a product.

---

## 1. Decisions so far

| Question | Decision | What it implies |
|---|---|---|
| Platform | **Windows download** | Godot export to a single `.exe`, zipped and sent to friends |
| Core fun | **Chaotic arcade** | Fun over realism; physics tuned for feel, not accuracy |
| Who builds | **Claude writes most of it** | Code-first, text-based engine; you playtest and supply local knowledge |
| Road accuracy | **Real layout, stylized look** | Curves, hills, and crossroads come from real map and elevation data; low-poly art |
| Endpoints | **Kalona (IA-22) → US-218/IA-27 interchange** | All rural two-lane; no city to build |
| Scale | **True 1:1** | About 15 mi / ~24 km; a full run is ~10–15 min |
| Multiplayer | **Solo only** | Local high scores; no servers or netcode |
| Chaos | **All of it**: buggies & farm traffic, cops & deer, smash-for-points, weather/time-of-day | Big content list, so strict phasing (§7) |
| Cars | **1998 Ford Windstar, Toyota Tercel, Acura Legend** | Three handling archetypes (§4.2) |
| Win condition | **Score attack** | Points for chaos, plus a finish bonus for reaching Iowa City |
| Consequences | **Wreck or bust = run over** | Car health and wreck rules matter; see the 1:1 tension in §4.4 |
| Hardware | **Must run on a potato** | Godot Compatibility renderer, low-poly, fog, aggressive streaming (§5.4) |
| Timeline | **ASAP prototype** | v0.1 is "drive the real road in a box"; chaos is layered on afterward |

---

## 2. Tech stack

| Piece | Choice | Why |
|---|---|---|
| Engine | **Godot 4.6.3** (pinned in CI) | Free (MIT). Scenes and scripts are plain text, so Claude can write and diff everything. Small one-file Windows exports. Has an OpenGL 3.3 "Compatibility" renderer that runs on old integrated graphics. |
| Language | GDScript | Built in, readable, fast iteration; no C# toolchain needed |
| Physics | Godot's built-in Jolt physics + a **custom raycast car** | Godot's stock `VehicleBody3D` is finicky. A raycast car (4 spring rays + simple tire grip) is the standard arcade approach and easy to tune per car. |
| Data pipeline | Python (`numpy`, `shapely`, `pyproj`, `rasterio`) | Runs once to turn map and elevation data into baked game files that are committed to the repo |
| 3D models | Procedural meshes in Godot for props; Blender (free) Python scripts for the 3 cars and hero landmarks; CC0 packs (Kenney, Quaternius) as placeholders | You have no assets. Boxy '90s cars are ideal for scripted low-poly modeling. |
| Builds | GitHub Actions: headless Godot export → `.zip` attached to a GitHub Release | Every push to `main` produces a downloadable build, so nobody needs Godot installed |
| Tests | A small headless GDScript test runner and pytest (pipeline), plus an **autopilot QA bot** (§6) | I can't feel the game, but I can verify a lot automatically |

**Rejected:** Unity (heavier, editor-centric, worse on potatoes) and Unreal (overkill).
A web build was rejected because you chose a Windows download, though Godot can add one later almost for free.

---

## 3. Building the real road (the "real layout" part)

### 3.1 Data sources (all free)

| Data | Source | Used for |
|---|---|---|
| Road centerline and crossroads | **USGS National Transportation Dataset** for Iowa (public domain, TIGER-based) | Exact curve geometry of Hwy 1 and the 29 crossroads on it, with names (Johnson-Washington Rd, 540th St, 500th St, Hazelwood Ave, Sharon Center Rd, Naples Ave, …). *Used instead of OpenStreetMap: it's reachable from the cloud dev environment and needs no API.* |
| Buildings and trees | **USGS 3DEP lidar** point clouds (the 2019 eastern Iowa flight, via the public `usgs-lidar-public` Entwine copy on AWS) | Every farmhouse, barn, machine shed, grain bin and tree line along the road, where it really stands, at its real size (`tools/bake_lidar.py`). *Used instead of OpenStreetMap, which is blocked here.* |
| Creeks, city limits, county line | **USGS National Hydrography Dataset** and **Governmental Units** | The names on the creek, county-line and Iowa City signs (`tools/bake_places.py`) |
| Elevation | **USGS 3DEP**: 1/3″ (~10 m) tile `n42w092` (covers the whole route; confirmed downloadable), plus 1 m lidar from the `IA_EasternIA_2019` project for the road profile | Rolling hills, crests you get air off, ditches, creek valleys |
| What's growing where | **USDA Cropland Data Layer** (30 m) | Real corn fields vs. soybeans vs. pasture, placed where they actually are. *Not yet: its host is blocked here, so crops are still a made-up patchwork (§9).* |
| Landmarks and "vibe" | **You**: a list, photos, and ideally a passenger-shot phone video of the drive | The "hey, that's ___" moments the data can't provide |
| Eyeball reference only | Google Street View / Iowa aerial imagery | Checking sign placement, tree lines, and farm layouts. Never copied into the game (licensing). No dashcam video is coming, so Street View is the main reference for Phase 5. From the cloud environment it needs a Google Maps API key (§9). |

### 3.2 Pipeline (`tools/`, run once, outputs committed)

Built in Phase 0:

1. `sources.py`: downloads the Iowa road dataset once (~190 MB, cached), and reads just the route's window of the elevation tile over HTTP.
2. `bake_route.py`:
   - project everything to UTM 15N (meters), with the **origin at the route midpoint** so no point is more than ~12 km from the origin (avoids float jitter at the far end);
   - find IA 1 between the IA-22 four-way stop in Kalona and the stop light at Mormon Trek Blvd in Iowa City (the lines are the northbound stop lines), keeping 188 m of road before the start line and 300 m past the finish (Phase 7; it used to run to the US-218 crossing);
   - where IA 1 is divided (through the Kalona intersection and the last half mile before 218), run the road down the middle of the median;
   - resample the centerline every 2 m and smooth it;
   - **fill bridge dips and smooth the elevation profile.** The bare-earth elevation model has bridges removed, so creek crossings and the 218 overpass show up as pits; filling them gives a max grade of 6.2%, which is realistic;
   - find the crossroads (name, side) and the filled-in "bridges";
   - write `game/data/route/`: centerline + crossroads (`route.json`), plus 1,144 terrain tiles with the road bed and ditches carved in.
3. `preview_route.py`: writes a top-down map and an elevation-profile PNG to `docs/route-preview/`. **You check it: "does this look like the road?"**
4. `bake_places.py` (Phase 5): creek, county and city names; the city limits (Phase 7).
5. `bake_streets.py` (Phase 7): the side roads and town streets within 700 m, and their verges in `terrain_dist.bin`.
6. `bake_lidar.py` (Phase 5): buildings, trees and farmyards (lawns all through town).

Still to come: crop data (`fetch_cdl.py`, Phase 5) and passing / no-passing zones (Phase 2).

### 3.3 In-game world

- **Road**: two 12 ft lanes, shoulders, double-yellow and dashed center lines matching the real passing zones, and ditches on both sides. Ditches are a key gameplay feature (jumps and wrecks).
- **Terrain**: 256 m chunks generated from the heightmap, with the road corridor cut and filled into it.
- **Fields**: corn as instanced card rows (MultiMesh), with height and color varying by season; soybeans as low green rows; pasture with fences.
- **Farmsteads**: procedural house, barn, silo, and machine shed, placed at OSM building clusters along the road.
- **Signs**: real crossroad names and mile markers.
- **Horizon**: coarse ground (64 m grid, from the same elevation data) reaches 4.4 km past the road on every side, under the detailed corridor. Summer haze thickens from 450 m and is total at 3 km, and everything streams in where the haze already hides it.

---

## 4. Game design

### 4.1 The loop

Pick a car → pick a condition → start at the Kalona four-way stop → drive north and cause chaos for points → **reach the US-218 interchange for the finish bonus**, or wreck or get busted trying → see the results screen and your best score for that car + condition → "one more run."

### 4.2 The cars

The stats below are approximate, for flavor; tuning is for fun.

| | 1998 Ford Windstar | Toyota Tercel | Acura Legend |
|---|---|---|---|
| Real-ish specs | 3.8 L V6, ~200 hp, ~4,000 lb, FWD | 1.5 L I4, ~93 hp, ~2,000 lb, FWD | 3.2 L V6, ~200–230 hp, ~3,500 lb, FWD |
| Feel | Heavy boat. Top-heavy, so yank it and it **rolls**. Wind gusts push it around. | Slow and light. Nimble, and launches off crests. | Fastest and grippiest. Smooth. |
| Durability | High: plows through fences | Low-ish, but the engine never dies (body panels do) | Medium |
| Score multiplier | ×1.2 | **×1.5** (hardest car) | ×1.0 |
| Signature damage | Sliding door and hubcaps fly off | Bumpers and mirrors | Hood and trunk lid pop open |

### 4.3 Scoring (starting values, to be tuned)

| Event | Points |
|---|---|
| Mailbox | 50 |
| Fence section | 25 |
| Round hay bale (they roll!) | 100 |
| Plowing through corn | 5 per meter (slows you down) |
| Airtime (crest or ditch jump) | 100 per 0.5 s |
| Near-miss with oncoming traffic | 250 (and fills the boost) |
| Close pass: squeezing past something in your lane | 100 (and fills the boost) |
| Clean pass: buggy / tractor / combine | 150 / 200 / 400 |
| Escaping a cop | 1,000 |
| Crossing the county line with the Washington County deputy on you (the deputy gives up: "jurisdiction bonus") | 2,000 |
| A deer in your path that you miss | 100 |

- **Combo**: events chained within ~4 s raise a multiplier (up to ×5). Any hard hit resets it.
- **Boost**: near misses and close passes fill a meter; hold Shift (or B) to burn it for a hard shove and a higher top speed. It's how you lose a cop (§4.5).
- **Finish**: reaching the 218 interchange multiplies the whole run by ×1.5, plus a time bonus under par.

### 4.4 Wrecks, and the 1:1 problem

The run ends when:

- car health hits 0 (impact damage scales with collision force);
- the car is on its roof or side for more than 3 s;
- you're **busted** (the cop is close and you're slow for a few seconds);
- you hit a **buggy**. That's an instant run over, shown as a fade-out with no ragdolls or carnage. It keeps the game funny and tense rather than gross.

**Tension I want to flag:** with a 1:1, 12-minute road, a wreck at mile 13 would hurt if the game were "finish or nothing." My resolution: **points bank as you earn them.** A wreck ends the run, but your score stands. You only lose the unbanked combo and the ×1.5 finish multiplier, which makes "survive to Iowa City" the risk-reward call. Two more pieces:

- **Stuck in a ditch but not wrecked** → "tow truck": respawn on the road, −500 points, combo reset. This is not a run-ender.
- **Practice mode** (cheap to add): start at any mile marker; scores aren't saved. It's needed for development anyway.

### 4.5 Traffic and hazards

- **Oncoming and same-direction traffic**: cars, pickups, semis. Passing on a two-lane road with oncoming traffic is the core tension.
- **Amish buggies**: ~8–10 mph, hugging the right edge, with an orange slow-moving-vehicle triangle and lanterns at night. Densest near Kalona.
- **Farm equipment**: tractors with wagons; **combines wider than a lane** in harvest (you have to use the shoulder or the other lane); grain trucks pulling out of field entrances.
- **Cops**: the Washington County deputy at the south end and Johnson County north of the line. Speed traps sit hidden at farmsteads and crossroads. Passing one well over the 55 mph limit triggers a chase. A deputy drives a little faster than your car can, so you can't just floor it: you lose them with the boost.
- **Deer**: dusk and night, near creeks and tree lines. A collision means big damage.

### 4.6 Conditions (each has its own high-score table: 3 cars × 5 conditions)

| Condition | What changes |
|---|---|
| Summer afternoon (default) | Tall green corn, full grip |
| Harvest dusk | Brown corn and stubble fields, combines and grain trucks, more deer |
| Night | Headlights only, buggy lanterns, deer ×3 |
| Thunderstorm | Rain, wet grip, lightning, wind gusts (bad news for the Windstar) |
| Winter | Snow, black-ice patches on bridges and shaded spots, snowplows, whiteout fog |

All five run on the same road and assets. A condition is just a data file (palette, fog, grip multiplier, traffic mix, deer rate, particles), so they're cheap to add.

### 4.7 Radio

To avoid bundling copyrighted music, **drop your own `.mp3` or `.ogg` files into a `radio/` folder next to the `.exe`** and the in-game radio plays them. You can record fake local ads and DJ bits yourself. Each friend brings their own playlist.

---

## 5. Architecture

### 5.1 Repo layout
```
Driving-Game/
  PLAN.md
  tools/                  Python data pipeline (§3.2) + pytest
  game/                   Godot project
    project.godot
    data/route/           baked road, POIs, terrain/crop tiles (committed)
    data/cars/            VehicleStats resources (one per car)
    data/conditions/      Condition resources (one per weather/time variant)
    scenes/  scripts/  assets/  tests/
  .github/workflows/      build-windows.yml (export + release)
```

### 5.2 Main systems
- `RouteData`: loads the baked centerline and POIs; answers "where is mile X?" and "what's my route distance?"
- `WorldStreamer`: loads and unloads road and terrain chunks within ~1.5 km of the car.
- `RoadBuilder` / `TerrainChunk` / `PropPlacer`: procedural meshes, MultiMesh corn, fences, mailboxes.
- `Vehicle` + `VehicleStats` + `DamageModel`: raycast car, per-car tuning, health, dents, detachable parts.
- `TrafficDirector`: spawns and despawns AI ahead of and behind you along lane paths, capped at N active vehicles.
- `Cops` (traps and chases, with `Pursuit` for the rules and `CopDriver` at the wheel), `Deer`, `ScoreKeeper` (event bus), `RunManager` (start → driving → finish/wreck/bust), `HighScores` (saved to `%APPDATA%`).
- `Conditions`: applies a condition's palette, fog, grip, and traffic mix.

### 5.3 Controls
Keyboard and Xbox-style gamepad from day one, both handled natively by Godot. Steering-wheel support is a stretch goal.

### 5.4 Potato performance budget
- **Target: 60 fps at 720p on an Intel UHD 620-class laptop.**
- Compatibility (OpenGL 3.3) renderer. Flat-shaded low-poly models sharing one palette texture, so draw calls stay very low.
- No real-time shadows (blob shadows under cars). The plan was shadows on the "High" preset, but in the Compatibility renderer they wash out the lighting (Phase 6).
- MultiMesh for corn, trees, fence posts, and mailboxes. A prop only becomes a physics body when the car gets close.
- Fog hides streaming. Chunks load by route distance, not raw radius. Far-off terrain and road use lighter meshes, and signs past 1.1 km aren't drawn.
- `--benchmark` drives for 40 s and prints fps, draw calls and triangles, to check a change (or a friend's computer) against the budget.
- Low/Med/High presets plus a resolution-scale slider (Settings, v0.6; **F2** still cycles the scenery detail).
- **The v0.5 scenery's cost** (`--benchmark` on CI's software renderer, same machine, same day):

  | | v0.4 | v0.5 | v0.5, F2 half |
  |---|---|---|---|
  | Start, Kalona | 17 fps, 99k triangles | 15 fps, 144k | n/a |
  | Mid-route woods (mile 6) | 22 fps, 84k | 12 fps, 186k | 15 fps, 136k |

  A software renderer is the worst case: any real GPU draws 200k triangles without noticing. The real check is a friend's weakest PC (§9).
- **The v0.7 additions' cost** (streets, power lines, the sky, tire marks; the same software renderer, v0.6 and v0.7 side by side): Kalona 14 → 15 fps (233 → 236 draw calls), mile 6 13 → 12 fps (187 → 211 draw calls). About the same.

---

## 6. How I verify things (since I can't play it)

- **CI export on every push**: if the Windows build doesn't export, it doesn't ship.
- **Unit tests**: scoring, combo rules, wreck rules, route lookups, pipeline math.
- **Autopilot QA bot**: a headless run that drives the whole 15 miles on the centerline at speed. It fails the build if the car ever falls through the world, hits a gap between chunks, or the route breaks. It also logs worst-case frame time and active-body counts.
- **Screenshots** of key spots, rendered with software OpenGL in CI, so we can compare looks without you launching anything.
- **You** handle feel: steering, speed, how hard the Windstar rolls, whether a crest gives good air. Your playtest notes are the tuning loop.

---

## 7. Phased roadmap (ASAP prototype first)

Each phase ends with a **zip you can send to friends**. Nothing past a phase gate starts until that phase is fun.

### Phase 0: Skeleton and data ✅
- Godot project, CI Windows export, a GitHub Release with a "hello Iowa" build.
- Data pipeline fetches road and elevation data and bakes the route. **You review the preview map and elevation profile.**
- The "hello Iowa" build is a flythrough camera driving the real road at an adjustable speed, with street-name signs, mile markers, and a trip HUD.
- What the data says: the start line to the finish line is **15.14 mi**. The route climbs ~100 ft out of Kalona, rolls at 750–800 ft for 8 miles, drops into a two-mile flat creek bottom around mile 9–11, and climbs again toward Sharon Center.

### Phase 1: v0.1 "Drive the real road" ⭐ the ASAP prototype
- A real Hwy 1 road mesh on real terrain, with ditches and fog.
- One placeholder box car with the arcade raycast physics; keyboard and gamepad.
- Start at the Kalona four-way stop and finish at the 218 interchange, with a timer, speedometer, and mile markers.
- **Goal: confirm the hills and curves feel like Hwy 1 and the car is fun to throw around.**
- **Built, waiting on your playtest.**
  - What's in it: the raycast car with surface grip (asphalt, gravel shoulder, grass), front-wheel drive, a handbrake and reverse, and an automatic hold on hills. Plus chase, hood, far-chase and drone cameras, a synthesized engine sound, the clock and saved best time, and "back on the road" and restart.
  - Measured in the automated test drive: 0–60 mph in 7.7 s, a 70 mph run takes 13:10, and the 123 mph limiter is reachable.
  - The autopilot drives all 15 miles at 70, 100 and 120 mph without leaving its lane. The hooligan stress test (90–110 mph with random handbrake, full lock and panic stops) hasn't broken the physics.
  - Finding: the smoothed road profile never launches the car, even at 118 mph. Air will have to come from ditches (Phase 2) and from your "hill that gives you air" spots, which can be sharpened in the bake.

### Phase 2: v0.2 "Chaos core"
- Score and combo system, smashable mailboxes, fences, and hay bales, corn plowing, airtime.
- Health and the wreck/run-over rules, a crash cam, a results screen, local high scores.
- Basic traffic: oncoming cars, buggies, tractors, and near-misses.
- **Built:**
  - **Handbrake (from playtest feedback).** It now drifts: a quick tap slides the tail 30–45°, a longer pull about 60°, and the car straightens up 2–4 s after you do. Before, the same yank gave 6°.
  - **Scoring.** Mailboxes, pasture fences and round hay bales are placed from a seed, so they're the same every run. Fences only run along pasture and hay ground, and bales sit in hay fields. Corn (instanced, flattens where you plow) grows in the real corn fields. Airtime, near misses, and passing buggies, tractors, slow cars and semis also score. The ×5 combo and finish bonus work as in §4.3.
  - **Wrecks.** The car has health. A hit counts as damage from a 2 m/s instant speed change upward, while normal driving peaks at 0.3 and big ditch landings at 1.8. The run ends on being totaled, rolled for 3 s, hitting a buggy, or a head-on. A crash cam circles the wreck, then the results screen shows the score breakdown, best score and best time. The tow truck costs −500.
  - **Traffic.** Buggies are common near Kalona (half of the slow traffic before mile 5). Traffic brakes for you, and crashed vehicles tumble away as physics wrecks.
  - **Passing zones.** Computed from real sight distance over crests and around bends (275 m, the MUTCD figure for 55 mph). About 29% of the road is no-passing in each direction, drawn as solid or dashed lines. The autopilot only passes on a dashed line.
  - **Tests.** The autopilot now completes the whole run with traffic, passing legally (16:29 at 70 mph, because it waits behind buggies). The hooligan stress test now meets traffic and gets wrecked by it.
- **v0.2.1: sight distance and clipping (from playtest feedback).**
  - **Seeing further.** The world used to stop about 1.3 km out, with the corn ending 200 m ahead and props 800 m out, and you could watch things appear. Now:
    - Coarse horizon ground reaches 4.4 km past the road. It's baked to sit just under the detailed ground, so the two never fight.
    - Haze is total at 3 km instead of 1.15 km.
    - The road shows 2.7 km ahead. Corn lines the road 640 m either way, growing in from 560 m. Props are built 1.2 km out.
    - Traffic appears 2–2.6 km ahead and leaves 900 m behind.
    - The QA drives fail if anything pops in closer than where the haze hides it. Measured: horizon 3.6 km, road 2.7 km, detailed tiles 1.2 km, props 1.1 km, corn 625 m, traffic 1.8 km.
  - **Clipping.** A probe in the QA drives measures overlap between the car's body and wrecks, debris, standing corn and the ground. Before:
    - The car sat inside standing corn for up to 20 s per run.
    - It sat 0.8 m into debris, because smashed props weren't solid to it.
    - It sat up to 0.3 m into crashed traffic, which stayed non-solid for 0.6 s.

    Now:
    - Corn flattens wherever the body touches it.
    - Debris starts clear of the car and is solid.
    - A crashed vehicle is moved off the car before it turns into a solid wreck.
    - The collision box reaches the bottom of the bumpers.
    - Wrecks and debris no longer vanish on a timer, only once you're far away.
    - CI fails on more than 10 ticks of visible clipping. The hooligan test now also drives the mailbox and fence lines and the fields.
  - **Oncoming traffic was missing.** A sign error deleted oncoming vehicles the moment they spawned, so v0.2 only ever had the vehicles placed by `--traffic-near`. Oncoming traffic, near misses and head-ons are real now. The autopilot treats a line of slow vehicles (a car stuck behind a buggy) as one pass: it needs room for all of it and finishes past the last one. Waiting for real gaps, it now takes 19:34 at 70 mph and 18:18 at 110.
  - **Performance.** On the software renderer CI uses, it's 19 fps against v0.2's 20, with the same 1% low and fewer triangles (91k vs 97k), while seeing 2–3× further. A real GPU won't notice.

### Phase 3: v0.3 "The three cars"
- Low-poly Windstar, Tercel, and Legend models with per-car handling, durability, and multipliers.
- Visual damage: dents and flying parts. A car-select screen.
- **Built:**
  - **The cars** (`CarStats.preset()`). Springs, tire stiffness, brakes and the handbrake kick scale with each car's weight and size, so they only differ where they're meant to.

    | | Windstar | Tercel | Legend |
    |---|---|---|---|
    | Weight | 1,830 kg | 930 kg | 1,590 kg |
    | Power, top speed | 200 hp, 110 mph | 93 hp, 103 mph | 230 hp, 139 mph |
    | Feel | soft and top-heavy: leans ~6° in a swerve (others 1°), plus a cosmetic lean | light, nimble | most grip, sits low |
    | Health | 160 | 70, but can't be totaled | 110 |
    | Points | ×1.2 | ×1.5 | ×1.0 |

  - **Models.** Each car's side outline is extruded across its width, with a narrower greenhouse, glass, lights and bumpers.
  - **Damage.** Hits dent the body where they land (the outlines are split finely enough to crumple). Each car loses its signature parts, the one nearest the hit first:
    - Windstar: hubcaps, then the sliding door.
    - Tercel: mirrors, then bumpers.
    - Legend: the hood and trunk lid pop open and flap, and later the hood tears off.

    Lost parts are physics debris. Smoke at 60% damage, as before.
  - **Garage** (car-select screen). The car waits at the start line while the camera circles it. Pick the car and a paint color, with stats and best records shown. It remembers the last pick. Enter / LB goes back to it from the pause or results screen. Records are kept per car.
  - **Engine sounds** differ: the Windstar is lower, the Tercel buzzy, the Legend smooth.
  - **Defaults I picked** (tell me if they're wrong): a 1997 (5th-gen) Tercel sedan and a 1993 (2nd-gen) Legend sedan. Paint colors are from each car's real '90s palette, since I didn't know yours.
  - **Corn (playtest note: too close to the road and not deep enough).**
    - Corn starts 26 m from the centerline, behind a wider grass strip.
    - It fills whole fields. Real clumps (now with a leafy top) fill every corn field within ~100 m of the car, however deep you drive in.
    - Past them, a corn canopy covers the rest of each field to its real edges: a top of leaves and tassels plus walls of stalks. It sinks out of the way near the car.
  - **Tests.** QA drives, drift and stress runs for every car in CI. Unit tests for the car stats and the points multiplier.

### Phase 4: v0.4 "Cops & deer"
- Speed traps, chases, busted, the county-line jurisdiction bonus, deer.
- **Built:**
  - **Speed traps.** Each run hides one Washington County deputy (between Kalona and the county line at Johnson-Washington Rd, mile 1.75) and three Johnson County deputies. They park on the shoulder just past a crossroad, and the spots change every run.
  - **Radar.** Pass within 130 m of a parked cruiser above 72 mph, or hit it, and the chase is on: a banner, lights, a siren. Traffic pulls over for the siren.
  - **The cruisers** are physics cars like yours: white for Washington County, black for Johnson, with a light bar, a push bar and SHERIFF on the doors. The deputy runs you down at up to 130 mph, then sits about 10 m off your bumper. They don't ram. The HUD shows who's after you and how close.
  - **How a chase ends:**

    | What happens | Outcome | Points |
    |---|---|---|
    | You stop (under 10 mph) with the deputy within 15 m for 3 s | **Busted**: the run's over | none |
    | You get 600 m clear for 4 s, or wreck the cruiser | Lost the cop | 1,000 |
    | You cross into Johnson County with the Washington County deputy on you | Jurisdiction | 2,000 |
    | It goes on for 2½ minutes | Outlasted the cop | 1,000 |

    Calling the tow truck mid-chase counts as busted.
  - **Deer.** About 8 crossings a run (5–10), mostly at the creeks where the road bridges them and a few anywhere. They change every run.
    - Come up on one above 30 mph and a herd of one to three breaks out of the corn and bolts across. Each deer paces itself to cross ahead of you, each closer than the last.
    - Sometimes the first one stops dead in your lane and stares, then bolts at the last moment, sometimes back the way it came.
    - **It's fair:** hold your speed and line and they all miss you, if only just (QA checks it from both sides at 50, 70 and 110 mph). A deer that can't get across ahead of you in time (say you sped up after passing a buggy) stops at the roadside and crosses behind you. Speed up once they're on the road, or swerve the wrong way, and you'll hit one.
    - A hit does about 1 health per m/s of closing speed (32 at 70 mph) and costs you the combo. The deer tumbles away (no gore). Traffic and cruisers can hit them too.
    - A deer in your path that you miss scores "Deer dodged" (100).
    - Deer come out in daylight for now. Dusk and night (the conditions in §4.6) come later.
  - **Tests.** New QA scenarios run in CI:
    - get busted at a Johnson County trap;
    - outrun the Washington County deputy to the county line;
    - drive through a herd (the first one freezes in the lane), then hit a deer standing in the road.

    The full drives now run with cops and deer, and fail if the autopilot hits a deer. There are unit tests for the chase rules and where deer cross.

### Phase 5: v0.5 "It's *our* Highway 1"
- Your landmarks, real crop placement, farmsteads, real signs.
- The five conditions and the radio folder.
- **Built:**
  - **Every real building and tree along the road, from lidar.** USGS flew all of eastern Iowa with lidar in spring 2019, and the point clouds are public. `tools/bake_lidar.py` reads them for 1 km either side of the road (~1.5 GB, cached) and finds:
    - **2,355 buildings**: 1,258 houses, 151 barns, 878 sheds (machine sheds, hog buildings, shops) and 68 grain bins or silos. Each sits where it really stands, at its real footprint, height and angle.
    - **82,410 trees**: the farmstead windbreaks, fence-line rows and creek woods.

    The lidar only marks ground vs. everything else, so the bake tells them apart itself:
    - A roof sends each laser pulse back once; a bare spring tree sends it back several times (twigs, branches, ground).
    - Roofs are smooth on top, so evergreens (which also return once) don't pass as roofs.
    - Power lines and fences are too thin to count, and anything on a road (bridges, overpasses) is dropped.
    - Bins are round, or small, square and tall.
  - **In the game** (`Scenery`): low-poly houses with gable roofs and windows, red gambrel barns, steel sheds, round bins with cone roofs, leafy trees and evergreens.
    - They're drawn as GPU instances in 512 m blocks that stream with the terrain, with plainer models past 450 m. Blocks are worked out on a worker thread so there's no hitch.
    - Every farmhouse gets a yard light on a pole.
    - Near the car they're solid: crash into a barn or a tree and you'll know it.
    - The corn stops 24 m short of any building, so every farmstead has a yard walled by corn, and hay bales stay out of yards. Deer don't cross where they'd have to run through a farmyard.
    - **F2** cycles the detail (everything / half the trees / none) for slow machines; it's saved.
  - **Real signs** (`tools/bake_places.py`, USGS hydrography and boundaries):
    - **DIRTY FACE CREEK** and **OLD WOMANS CREEK** at their bridges.
    - **JOHNSON COUNTY** at the real county line (mile 1.75).
    - **IOWA CITY, POP 74,828** at the real city limit (mile 14.66).
    - 55 mph signs every four miles once out of Kalona, and IOWA 1 route markers.
  - **The five conditions** (`Condition`), picked in the garage on a new row (▲ ▼ picks car / paint / conditions, ◀ ▶ changes it). Each has its own records per car (summer keeps the old ones).

    | Condition | What changes |
    |---|---|
    | Summer afternoon | As before |
    | Harvest dusk | Low orange sun. Brown corn, and about 45% of the corn fields already cut to stubble. Fall-colored trees. Combines (wider than a lane, header over the shoulder) and grain trucks. Deer ×1.6 |
    | Night | Dark; your headlights (and every other vehicle's head and tail lights, the buggies' lanterns, the cruisers'). Lit farmhouse windows and yard lights. Deer ×3 |
    | Thunderstorm | Rain, wet roads (72% grip), lightning with thunder a moment later, and side gusts that push hardest on tall cars: bad news for the Windstar |
    | Winter | Snow on the fields, roofs and trees; the corn's all in; whiteout fog. 82% grip, and **black ice** (30%) on the bridges and wherever real trees shade the road, drawn as a dark glaze you can see coming. Snowplows |

  - **The radio** (`Radio`): any `.mp3` or `.ogg` in a `radio/` folder next to the game plays, shuffled. **N** skips, **B** turns it off/on (D-pad right/left); the song's name shows at the bottom left. The zip ships with the folder and a note in it.
  - **The autopilot** (and so the QA drives) drives the conditions the way a careful driver would. It leaves more room and slows earlier on a wet or snowy road, slows to 50 mph for ice it can see, and passes a line of slow vehicles whole if there's no room to stop between them.
  - **Tests.**
    - CI runs a full QA drive in every condition: Windstar summer, Tercel harvest, Legend night at 110, Windstar storm, Tercel winter.
    - A new clip-probe category checks the car never sits inside a building.
    - Pipeline tests cover the lidar classification (roofs vs. trees, power lines, oriented footprints, bins, yards) and the creek and city crossings. Unit tests cover the conditions, harvested fields, the traffic mix and the radio.
  - **Not done:**
    - **Real crop placement:** its host is still blocked (§9 Q6).
    - **Your landmarks:** still waiting on your list (§9 Q1). *Done since: Kalona Cheese, below.*

### v0.5.1: after the v0.5 playtest
- **Playtest notes:** "a boost mechanic for near misses, a clearer way to outrun the police", and "the one clear landmark on the run, the Kalona cheese factory" (with a photo).
- **Built:**
  - **The boost** (`Boost`). Near misses fill the meter (bottom right, over the health bar):
    - an oncoming near miss fills 40% of it;
    - a close pass (squeezing past something in your lane within 1.2 m of its mirror) fills 25% and scores 100.

    Hold **Shift** (or **B** on a controller) to burn it. A full meter lasts 4 s: a 0.7 g shove on top of the engine, and the top speed goes up by 56 mph to at most 168 mph. Flat out on a level road (boosting: two boosts back to back, measured in QA):

    | Car | Usually | Boosting |
    |---|---|---|
    | Windstar | 104 mph | 163 mph |
    | Tercel | 96 mph | 156 mph |
    | Legend | 133 mph | 166 mph |

    It shows: a flame out of the tailpipe, the view widens and drops back, and the engine roars.
  - **Losing a cop is now about the boost.**
    - A chasing deputy drives 9 mph faster than your car can go flat out (up to the cruiser's 130 mph). Flooring it won't shake them; they slowly reel you in.
    - Two full boosts get you clear, in any car.
    - Lost now takes 400 m clear for 4 s (was 600 m).
    - When a chase starts, a hint says how.
  - **Kalona Cheese** (`Landmarks`, `data/route/landmarks.json`): the Kalona Creamery since 2017, on the corner of 540th St SW, 3.9 miles up. It's built by hand from your photo, sized and placed off the lidar:
    - the red brick store a story and a half tall, KALONA CHEESE across its steep gray gable;
    - the one-story front under a gray shingled mansard, with the black KALONA CREAMERY sign over black double doors;
    - behind it, the plant: a concrete-block wing, the old plant under a tan roof, the brick smokestack, three steel silos and the big metal plant buildings.

    The windows and the sign light up at night, the roofs take the snow, and it's solid. The lidar bake had left the store out (it stands within 14 m of the road, where the bake drops what it takes for road clutter) and called the plant's tanks trees. The corn, fences and deer now keep clear of it.
  - **Tests.**
    - A new QA scenario, run for every car in CI: a deputy on your tail at your top speed, then two full boosts. Each loses the deputy 27–33 s into the chase.
    - The stress test now boosts at random.
    - Unit tests cover the meter, the boosted top speeds, the deputies' speed, close passes, and where the landmark stands (clear of the road, nothing of the lidar's left inside it).

### Phase 6: v0.6 "Polish"
- Engine and crash audio, menus, graphics presets, controller rumble, practice mode, a title screen, and anything that makes your friends laugh.
- **Built:** all of it.
  - **A title screen.** The car you drove last cruises up Highway 1 on its own, in the conditions you drove in, with the camera circling it and the radio on. The menu: Drive, Practice, Records, Settings, Quit.
  - **Menus everywhere** (`Menu`, `Menus`). Keyboard, gamepad and mouse all work: ▲ ▼ picks, ◀ ▶ changes a setting, Enter / A chooses, Esc / B goes back.
    - **Esc (or Start) opens the pause menu** instead of quitting: Resume, Restart the run, Change car, Settings, Quit to the title screen, Quit the game.
    - **The garage** goes back to the title with Esc.
  - **Settings**, saved as you change them (`Settings`, `user://settings.cfg`):

    | Setting | Choices |
    |---|---|
    | Graphics | Low (slow PCs) / Medium / High |
    | Resolution | 50–100% of the window, for the 3D |
    | Scenery | Everything / half the trees / off (still **F2** in a run) |
    | Display | Window / full screen |
    | Volume | Overall, car and effects, radio (0–100%) |
    | Controller rumble | On / off |

    The presets:
    - **Low:** 75% resolution, half the trees, plainer models past 300 m, half the rain and snow.
    - **Medium:** what every build so far has drawn.
    - **High:** 2× anti-aliasing, and detailed buildings and trees out to 800 m (not 450).

    No sun shadows after all: in the Compatibility renderer they wash the lighting out, and the cars have their blob shadows.
  - **Practice mode.** Pick a car, conditions and where to start: Kalona or any mile up the road (named for the crossroad there). The clock and scoring run as usual, but nothing's saved, and the HUD and results say PRACTICE.
  - **Records.** A table of your best score and time for every car in every condition.
  - **Sound** (`Sfx`, `CarFeel`). All synthesized, no audio files:
    - crashes (a thump, crumpling metal and bits falling, louder the harder);
    - a clang for mailboxes, a crack for fence rails, a thud for hay bales and for landing a jump;
    - a whoosh on a near miss;
    - tires squealing in a slide on the asphalt (crunching on gravel and grass);
    - a roar on the boost;
    - **a horn** (H or RB) for each car: the Windstar's low, the Legend's in between, and the Tercel's a "meep".
  - **Controller rumble:** crashes (by how hard), smashes, landings, near misses, and a buzz while boosting.
  - **For laughs:**
    - **The horn scares deer.** Lean on it and the deer up ahead spook: one frozen in the road bolts for the nearer ditch, ones on their way turn tail.
    - **Every run gets a title** on the results screen, from how it ended and what happened. "The horse saw that coming." "Minivan gymnastics: a perfect 10." "Unlicensed combine operator: 420 m of corn." "Federal mailbox offender (9 counts)." "The Dukes of Washington County." "Hauling cheese curds." "Drove it like a rental."
  - **Tests.**
    - `--qa-menus` clicks through the whole flow the way a player would, and CI runs it. The flow: title, settings, records, a practice run from mile 4 (gas, horn), the pause menu, Change car, back to the title, a real run, pause, quit to the title.
    - Unit tests cover the settings (presets, steps, saving), a menu's keys, practice runs saving nothing, the sounds, the horn spooking deer, and the run titles.

### Phase 7: v0.7 "Graphical polish"
- After the v0.6 playtest: "focus on graphical polish, and move the starting location back slightly so it starts at the 4 way stop in Kalona and extend the end of the run so it finishes at the first stop light in Iowa City", and the corn "can pop in and out in a wave motion". The start should show the 4-way stop explicitly: a stop sign, and you accelerate through the intersection.
- **Built:**
  - **The corn wave, fixed.** The corn canopy used to sink into the ground around the car, where the detailed clumps are. Its grid is 16–32 m, too coarse for that: whole triangles tilted up through the clumps as the car went by, so the corn seemed to pop in and out in a wave. Now the canopy is cut away per pixel within 84 m of the car, and the clumps stand out to 92 m and sink under the canopy by 100 m.
  - **The real start and finish.** The bake now finds both ends from the cross streets (`tools/config.py`): the run goes from the northbound stop line at the IA-22 four-way stop in Kalona (12 m short of the middle of the intersection) to the stop line at Mormon Trek Blvd, the first stop light in Iowa City, past the US-218 interchange: 15.37 miles. The origin is pinned, so the buildings, trees and landmark keep their places; `bake_lidar.py --extend` re-baked just the lidar tiles near the new end (257 more buildings, 2,600 more trees).
  - **The 4-way stop** (`Intersections`). You start stopped at the stop sign, your bumper at the line. Stop signs with ALL WAY plates and street-name blades on all four corners, stop lines across every lane, and an Amish buggy waiting its turn on E Ave. A checkered KALONA · START banner over the line.
  - **The stop light** at Mormon Trek: signal heads on mast arms over every approach, cycling green, yellow, all red, then the cross street (never green both ways). An IOWA CITY · FINISH banner over the stop line.
  - **Side roads and town streets** (`tools/bake_streets.py`, `Streets`). Every road within 700 m of the highway from the road data: paved in town and on the highways (IA 22 gets a dashed center line, Mormon Trek four lanes), gravel out in the country (two paler wheel tracks), and private lanes. They sit just above the ground, and where they cross the highway's ditch they ride a fill up to the highway's level; their ends follow the edge of its pavement. They stream in with the terrain, with colliders that grip like asphalt or gravel, so you can drive down them. The grass verges run along them and the corn keeps off them.
  - **Towns** are lawns and houses: no crops inside the Kalona and Iowa City limits (`bake_places.py` writes the city outlines). Farmyards get mown lawns around the buildings too.
  - **Power lines** (`PowerLines`): wooden poles every 46 m just inside the fence, with crossarms, insulators and three sagging wires. The line crosses the road at a crossroad every few miles and steps aside for crossroads, streets, bridges and the landmark. The poles are solid.
  - **The sky** (`sky.gdshader`): clouds for each condition (fair-weather in summer, lit orange at harvest dusk, overcast in the storm and winter), the sun or moon, and stars at night.
  - **Tire marks and dust** (`TireMarks`): black skid marks when the tires slide on the asphalt, ruts in the gravel and grass, and dust off gravel and dirt, smoke from a hard slide, spray in the rain and snow in winter. The Low preset halves the dust.
  - **Tests.** Unit tests cover the stop-line-to-stop-line route, where the car starts, the 4-way stop, the light's cycle, the streets (meeting the highway at its edge and level, never under the ground, the lookup, the surfaces), no crops in town, the power line, the tire marks and the clouds; Python tests cover the street bake. The QA drive also checks streets don't pop in (they arrive ~1.3 km out). Every QA drive and scenario passes, and the frame rate is about what v0.6's was (§5.4).

**Scope-creep parking lot** (not planned; pick from here for what's next): multiplayer, ghosts, a web build, steering wheels, a southbound run, traffic on the side roads.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Car feel is mediocre, which kills an arcade game | Custom raycast car with every knob exposed; fast playtest loop with you; a placeholder car in Phase 1 so feel gets tuned before art |
| 1:1 scale + run-ending wrecks = frustration | Banked points, the tow-truck rule, practice mode (§4.4) |
| 24 km world on potato PCs | Fog, streaming by route distance, MultiMesh, prop sleeping, autopilot frame-time logging |
| Float jitter far from origin | Origin at the route midpoint (max ~12 km away) |
| Too much chaos content | Strict phase gates; conditions are data, not new systems |
| Friends get a "Windows protected your PC" warning | Expected for an unsigned hobby `.exe`. Click **More info → Run anyway**. Instructions ship in the zip. |
| Copyright | CC0 or self-made assets; music is bring-your-own; real place names are fine for a private game |
| Map data blocked from the cloud dev environment | Resolved: the USGS sources are reachable, and the baked data is committed |

---

## 9. What I need from you (open questions)

1. **Landmarks, in order heading north from Kalona.** I want the 5–15 things you'd point at from the passenger seat: buildings, signs, the hill that gives you air, where cops actually sit, deer spots, a weird mailbox. Rough locations are fine ("just past F62 on the right"). *So far: Kalona Cheese (v0.5.1). More are welcome.*
2. **The cars.** I went with a 1997 Tercel sedan and a 1993 Legend sedan, in each car's real paint colors, all pickable in the garage. Tell me if your Tercel was a coupe or hatch, if the Legend was a coupe, or the actual colors, and I'll match them. Inside-joke details count too: the tape deck, a door that didn't close, a dent.
3. ~~A phone video of the drive.~~ Not available, so Street View stands in. It needs a **Google Maps API key** saved as a secret in this cloud environment; the free monthly allowance easily covers a few hundred reference frames. Without one, I'll rely on your landmark list and the map data. Needed before Phase 5.
4. **A gamepad?** It plays fine on keyboard, but tell me if everyone will use controllers.
5. **A name.** Working title: *Highway 1*.
6. **Network access for this cloud environment.** The buildings and trees came from USGS lidar instead of OpenStreetMap, so OSM isn't needed any more. The one thing still blocked that matters is the **crop data** (`nassgeodata.gmu.edu`): allow that host in the environment's network settings and I'll put the real corn and bean fields where they are.
7. **Set `main` as the repo's default branch** (GitHub → Settings → General → Default branch). It's currently a feature branch.

### Where access to your Windows PC would help

All the code can be written in the cloud. Running Claude Code on your own Windows machine, or connecting this session to it, would help with three things:

- **Phase 0**: running the data pipeline there sidesteps the blocked map hosts.
- **Phase 1 onward**: launching the actual `.exe` on a real GPU. That lets me take screenshots and read frame times on *your* hardware instead of software rendering in CI.
- **Potato check**: if one of your machines is the weakest in the friend group, it becomes the performance target. Running the autopilot bot on it gives real numbers.

This becomes most useful once Phase 1 has a drivable build.
