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
| Buildings, creeks (later) | OpenStreetMap | Farmstead and building footprints for Phase 5; the USGS road data has no driveways |
| Elevation | **USGS 3DEP**: 1/3″ (~10 m) tile `n42w092` (covers the whole route; confirmed downloadable), plus 1 m lidar from the `IA_EasternIA_2019` project for the road profile | Rolling hills, crests you get air off, ditches, creek valleys |
| What's growing where | **USDA Cropland Data Layer** (30 m) | Real corn fields vs. soybeans vs. pasture vs. woods, placed where they actually are |
| Landmarks and "vibe" | **You**: a list, photos, and ideally a passenger-shot phone video of the drive | The "hey, that's ___" moments the data can't provide |
| Eyeball reference only | Google Street View / Iowa aerial imagery | Checking sign placement, tree lines, and farm layouts. Never copied into the game (licensing). No dashcam video is coming, so Street View is the main reference for Phase 5. From the cloud environment it needs a Google Maps API key (§9). |

### 3.2 Pipeline (`tools/`, run once, outputs committed)

Built in Phase 0:

1. `sources.py`: downloads the Iowa road dataset once (~190 MB, cached), and reads just the route's window of the elevation tile over HTTP.
2. `bake_route.py`:
   - project everything to UTM 15N (meters), with the **origin at the route midpoint** so no point is more than ~12 km from the origin (avoids float jitter at the far end);
   - find IA 1 between the IA-22 crossing in Kalona and the US-218 crossing, keeping 200 m of road before the start line and 300 m past the finish;
   - where IA 1 is divided (through the Kalona intersection and the last half mile before 218), run the road down the middle of the median;
   - resample the centerline every 2 m and smooth it;
   - **fill bridge dips and smooth the elevation profile.** The bare-earth elevation model has bridges removed, so creek crossings and the 218 overpass show up as pits; filling them gives a max grade of 6.2%, which is realistic;
   - find the crossroads (name, side) and the filled-in "bridges";
   - write `game/data/route/`: centerline + crossroads (`route.json`), plus 1,144 terrain tiles with the road bed and ditches carved in.
3. `preview_route.py`: writes a top-down map and an elevation-profile PNG to `docs/route-preview/`. **You check it: "does this look like the road?"**

Still to come: crop data (`fetch_cdl.py`, Phase 5) and passing / no-passing zones (Phase 2).

### 3.3 In-game world

- **Road**: two 12 ft lanes, shoulders, double-yellow and dashed center lines matching the real passing zones, and ditches on both sides. Ditches are a key gameplay feature (jumps and wrecks).
- **Terrain**: 256 m chunks generated from the heightmap, with the road corridor cut and filled into it.
- **Fields**: corn as instanced card rows (MultiMesh), with height and color varying by season; soybeans as low green rows; pasture with fences.
- **Farmsteads**: procedural house, barn, silo, and machine shed, placed at OSM building clusters along the road.
- **Signs**: real crossroad names and mile markers.
- **Horizon**: Iowa haze fog at ~600–900 m hides streaming and suits the setting.

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
| Near-miss with oncoming traffic | 250 |
| Clean pass: buggy / tractor / combine | 150 / 200 / 400 |
| Escaping a cop | 1,000 |
| Crossing the county line with the Washington County deputy on you (he gives up: "jurisdiction bonus") | 2,000 |

- **Combo**: events chained within ~4 s raise a multiplier (up to ×5). Any hard hit resets it.
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
- **Cops**: the Washington County deputy at the south end and Johnson County north of the line. Speed traps sit hidden at farmsteads and crossroads. Passing one well over the 55 mph limit triggers a chase.
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
- `CopAI`, `DeerSpawner`, `ScoreKeeper` (event bus), `RunManager` (start → driving → finish/wreck/bust), `HighScores` (saved to `%APPDATA%`).
- `Conditions`: applies a condition's palette, fog, grip, and traffic mix.

### 5.3 Controls
Keyboard and Xbox-style gamepad from day one, both handled natively by Godot. Steering-wheel support is a stretch goal.

### 5.4 Potato performance budget
- **Target: 60 fps at 720p on an Intel UHD 620-class laptop.**
- Compatibility (OpenGL 3.3) renderer. Flat-shaded low-poly models sharing one palette texture, so draw calls stay very low.
- No real-time shadows by default (blob shadows under cars); shadows only on the "High" preset.
- MultiMesh for corn, trees, fence posts, and mailboxes. A prop only becomes a physics body when the car gets close.
- Fog hides streaming. Chunks load by route distance, not raw radius.
- Low/Med/High presets plus a resolution-scale slider.

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

### Phase 3: v0.3 "The three cars"
- Low-poly Windstar, Tercel, and Legend models with per-car handling, durability, and multipliers.
- Visual damage: dents and flying parts. A car-select screen.

### Phase 4: v0.4 "Cops & deer"
- Speed traps, chases, busted, the county-line jurisdiction bonus, deer.

### Phase 5: v0.5 "It's *our* Highway 1"
- Your landmarks, real crop placement, farmsteads, real signs.
- The five conditions and the radio folder.

### Phase 6: Polish (pick and choose)
- Engine and crash audio, menus, graphics presets, controller rumble, practice mode, a title screen, and anything that makes your friends laugh.

**Scope-creep parking lot** (not planned; revisit after Phase 5): multiplayer, ghosts, a web build, steering wheels, extending into Iowa City, a southbound run.

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

1. **Landmarks, in order heading north from Kalona.** I want the 5–15 things you'd point at from the passenger seat: buildings, signs, the hill that gives you air, where cops actually sit, deer spots, a weird mailbox. Rough locations are fine ("just past F62 on the right").
2. **The cars.** The Tercel's year and body style (sedan, coupe, or hatch) and the Legend's (sedan or coupe), plus colors for all three. Any inside-joke details count too: the tape deck, a door that didn't close, a dent.
3. ~~A phone video of the drive.~~ Not available, so Street View stands in. It needs a **Google Maps API key** saved as a secret in this cloud environment; the free monthly allowance easily covers a few hundred reference frames. Without one, I'll rely on your landmark list and the map data. Needed before Phase 5.
4. **A gamepad?** It plays fine on keyboard, but tell me if everyone will use controllers.
5. **A name.** Working title: *Highway 1*.
6. **Network access for this cloud environment.** Not needed for Phase 0, since the road now comes from USGS. OpenStreetMap (`overpass-api.de`, `download.geofabrik.de`) and the crop data (`nassgeodata.gmu.edu`) are still blocked here. They only matter in Phase 5, so allow those hosts in the environment's network settings before then.
7. **Set `main` as the repo's default branch** (GitHub → Settings → General → Default branch). It's currently a feature branch.

### Where access to your Windows PC would help

All the code can be written in the cloud. Running Claude Code on your own Windows machine, or connecting this session to it, would help with three things:

- **Phase 0**: running the data pipeline there sidesteps the blocked map hosts.
- **Phase 1 onward**: launching the actual `.exe` on a real GPU. That lets me take screenshots and read frame times on *your* hardware instead of software rendering in CI.
- **Potato check**: if one of your machines is the weakest in the friend group, it becomes the performance target. Running the autopilot bot on it gives real numbers.

This becomes most useful once Phase 1 has a drivable build.
