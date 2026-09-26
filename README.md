# Castelmare — Sicily upgrade for Place1

Replaces the cowboy map with a generated **Sicilian seaside town**, switches every character (players and NPCs) to **blocky R6**, and adds **weighty third-person movement**: a relaxed walk, Shift to run, a cinematic camera and procedural animation.

![Piazza del Duomo](docs/piazza-overview.jpg)

| | |
|---|---|
| ![Via Roma](docs/via-roma.jpg) | ![Harbour](docs/harbour.jpg) |
| ![Piazza](docs/piazza.jpg) | ![Palazzo](docs/palazzo.jpg) |
| ![Aerial](docs/aerial.jpg) | ![Bridge](docs/bridge.jpg) |

*These are offline previews of the generated geometry (three.js, simplified lighting). In Studio you'll see Roblox materials, Future lighting, terrain water and the golden-hour sky.*

## What's in it

**Movement** (`src/client/Movement.luau`, `CameraFX.luau`)
- Relaxed walk by default (10 studs/s). **Hold Shift** to run (23), with a smooth ramp in both directions. Gamepad: click **L3** to toggle. Mobile: a **RUN** button.
- Momentum: input eases in and out, so starts, stops and turns have weight.
- The body turns smoothly toward the direction of travel, in wider arcs when running. It faces the camera in shift-lock and first person.
- Hard landings slow you down briefly. A short jump cooldown stops bunny-hopping.
- Camera: the FOV widens while running, the camera trails the body slightly, head-bob is synced to the footsteps, and there is a small tilt when strafing and a springy dip on landing. All of this sits on top of Roblox's default camera, so zoom, collision and gamepad/touch controls are unchanged.
- **Shift-lock moves to Ctrl** because Shift is now Run.

**Blocky R6 characters** (`src/server/Characters.luau`, `src/shared/R6.luau`)
- Every player spawns as a classic R6 rig wearing their own 2D shirt, pants, hats, hair, face and skin colours. Bundle body meshes and 3D layered clothing are dropped because they can't fit R6.
- **Existing NPCs are converted to R6 in place** (`RigConverter.luau`). They keep their Model, Humanoid, HumanoidRootPart, scripts, clothes and accessories. To leave one alone, tag it `KeepRig`.
- On death, characters ragdoll instead of falling apart.

**Procedural animation** (`src/client/Animator.luau`)
- Animates every R6 rig from its physics: idle breathing, walk, run (forward lean and arm pump), jump, fall (with flailing on long falls), landing squash, climb, swim, sit, and holding a tool.
- Characters lean into turns and heads look around. Your head follows the camera, and NPCs glance at players who walk past.
- Stride matches speed, so feet don't skate. Footsteps are synced to the steps and vary by floor material.
- No animation assets to upload. If one of your scripts plays an Action-priority animation (a sword swing, say), the upper body is left to it and the legs keep walking.

![Poses](docs/poses-locomotion.jpg)

**The town** (`src/server/Town/`): Castelmare is generated from a fixed seed, so it's identical every time.
- **Piazza del Duomo**: a baroque cathedral with twin bell towers and majolica domes, a fountain, Garibaldi's statue, the market, the arcaded town hall (clock, flags) and a café arcade.
- **Via Roma**: string lights and shops with signs and awnings (Panificio, Trattoria, Tabacchi…), balconies, shutters, bougainvillea and parked Fiat 500s.
- **The harbour**: seawall with fishermen's boat arches, the belvedere and double staircase, quay, pier and lighthouse, colourful gozzo boats and the beach.
- **The countryside**: an old stone bridge over the river valley, a roadside shrine with candles, a masseria farmhouse, olive groves, vineyards and a lemon grove. A cypress-lined road leads up to the **Norman castle**.
- **Townsfolk**: fishermen in coppola caps, nonnas in black headscarves, a priest, vendors and tourists. They stroll the streets, work the market, sit at cafés and fish off the pier.

![Townsfolk](docs/townsfolk.jpg)

**Presentation**: golden-hour lighting (plus `BlueHour` and `Midday` presets), a letterboxed intro flyover with a title card (any key skips it), a controls hint, a run vignette and a fade-in on respawn.

## Install into Place1

**Before you start**, back up Place1: File → Save to File As…

### Option A: drag-in installer (no tools needed)
1. In Studio's Explorer, right-click **ServerStorage** → **Insert from File…** → pick [`build/SicilyUpgrade.rbxm`](build/SicilyUpgrade.rbxm).
2. Open **View → Command Bar**, paste this and press Enter:
   ```lua
   require(game.ServerStorage.SicilyUpgrade.Install)()
   ```
   This moves the scripts into place and enables them. Anything it replaces (e.g. an old `Animate` script) is backed up to `ServerStorage.SicilyUpgrade_Backup`.
3. **Lighting → Technology → Future** in Properties. Scripts can't set this, and it's what makes the town glow.
4. Move your **old cowboy map** out of Workspace (drag it into ServerStorage) or delete it.
5. Press **Play**.

### Option B: Rojo
`default.project.json` maps `src/` into your place. Run `rojo serve` and connect with the Rojo plugin. Then do steps 3–5 above.

### Try it first
Open [`build/SicilyDemo.rbxl`](build/SicilyDemo.rbxl) in Studio and press Play. It's an empty place with everything installed.

### Optional: bake the town into your place
By default the town is generated when the server starts, which takes a few seconds and holds spawning until it's done. To see and hand-edit it in Studio, bake it once from the Command Bar, then save:
```lua
require(game.ServerScriptService.SicilyServer.Town).Bake()
```
When a baked `SicilianTown` model exists, the server reuses it instead of generating a new one. Re-run `Bake()` to regenerate it.

## Controls
| | Keyboard | Gamepad | Mobile |
|---|---|---|---|
| Run | hold **Shift** | click **L3** (toggle) | **RUN** button (toggle) |
| Shift-lock | **Ctrl** | — | — |
| Skip intro | any key | any button | tap |

## Settings
Everything is in **`ReplicatedStorage.SicilyShared.Config`**. The most useful settings:

| Setting | Default | |
|---|---|---|
| `Movement.WalkSpeed` / `RunSpeed` | 10 / 23 | walk and run speed |
| `Movement.Acceleration` / `Deceleration` | 6.5 / 8.5 | lower = heavier |
| `Movement.Stamina.Enabled` | false | stamina-limited running |
| `Movement.ShiftLockKeys` | `"LeftControl,RightControl"` | `""` keeps Roblox's default |
| `Camera.RunFOV`, `WalkBob`, `RunBob` | 79, 0.03, 0.1 | camera feel |
| `Characters.KeepClothing` / `KeepAccessories` | true | what players keep from their avatar |
| `Characters.ConvertExistingNPCs` | true | R6-convert NPCs already in the place |
| `Town.Enabled` | true | turn off to keep your own map |
| `Town.HideOnBuild` | `{}` | names of old map models to move out of Workspace at runtime |
| `Town.TownsfolkCount` | 20 | strolling NPCs (plus vendors, café regulars and fishermen) |
| `Lighting.Preset` | `"GoldenHour"` | also `"BlueHour"`, `"Midday"` |
| `Lighting.DayNightCycle` | false | lamps switch on at dusk when enabled |
| `Intro.Enabled` / `Title` | true / `"CASTELMARE"` | opening flyover |

## Working with your existing game
- **Speed changes from your scripts:** set attributes on the Humanoid rather than `WalkSpeed`, because the controller sets `WalkSpeed` every frame. Use `SpeedMultiplier` (e.g. `0.5` while aiming) and `MovementLocked` (true freezes input).
- **Old sprint or movement scripts** will fight this system, so remove them.
- **R15 animations** won't play on R6 rigs; re-make any you need for R6. Action-priority tracks still override the upper body.
- **Scripts that look up R15 part names** (`UpperTorso`, `LeftHand`…) need the R6 names (`Torso`, `Left Arm`…).
- **Spawns:** players always land in the piazza. To keep your own spawn logic, set `Town.UseTownSpawns = false`.
- **Performance:** the generated town is about 20k anchored parts and ~200 lights, with terrain for the land and sea. It works with StreamingEnabled. Most small trim skips collision and shadows. To trim further, lower `Town.TownsfolkCount` or bake and then delete the areas you don't need.

## Project layout
```
src/shared/     Config, R6 rig builder, Spring
src/server/     boot script, Characters, RigConverter, Ragdoll, NPCs, LightingPreset
src/server/Town Plan (layout + terrain recipe), Landscape, Streets, Buildings, Facade,
                Landmarks, Harbour, Countryside, Props, Nav, Kit, Palette, Rng
src/client/     Movement, CameraFX, Animator, Sounds, Hud, Intro
src/overrides/  empty Animate / RbxCharacterSounds that replace Roblox's defaults
tools/          offline checks (Lune), preview renderer (three.js), installer, build script
```

## Development
`tools/build.sh` builds the installer and demo place with [Rojo](https://rojo.space) and runs the offline checks with [Lune](https://lune-org.github.io/docs):
- `tools/lune/build-town.luau` runs the real generator against the built place. Lune validates every property, enum and value type against Roblox's API, and the script prints part, light and NPC-spot counts.
- `tools/lune/test-characters.luau` checks the R6 rig and drives the real animation solver through every state, checking foot contact. It also builds every townsfolk outfit and converts a mock R15 NPC in place.
- `tools/preview/render.mjs` renders the preview shots above (`npm install` in `tools/preview`, then `node render.mjs <dir with town.json>`).

These checks run outside Roblox. The town generator and animation maths are exercised for real, but the in-engine parts (the PlayerModule hook, camera, spawning, terrain fills, NPC walking) run for the first time in your Studio. If anything errors, the Output window will say which `[Sicily]` module failed.
