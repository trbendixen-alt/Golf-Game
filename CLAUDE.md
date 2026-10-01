# Street Golf: Master Prompt (v3)

> Living document. Sections marked **[NEW]** are additions/decisions I made that weren't in the original idea. Sections marked **[DECIDE]** need an answer before or during build.

---

## 1. Concept

A mobile golf game where the courses are places you'd never normally play golf: city streets, rooftops, parking lots, small-town main streets, farm fields, residential neighbourhoods, alleys, parks, docks. Golf holes are dropped into the real world. Same goal as regular golf: get the ball in the hole in the fewest strokes.

**Tone:** fun, a bit playful, easy to pick up, hard to master. Quick sessions (3-hole round should take ~5 minutes).

## 2. Game Modes

- **3-Hole Challenge** (quick play)
- **9-Hole Round**
- **18-Hole Round**
- Each mode loads randomized holes from the pool of **18 free holes** (no repeats within a single round).
- **[NEW]** For 3 and 9 hole modes, pick randomly without repeats. For 18, play all 18 in a randomized order.
- **Paid expansion:** extra map packs / additional holes sold as in-app purchases (see Monetization).

## 3. Core Gameplay

- Each hole has a tee, a hole/cup, a par, and terrain zones (fairway, rough, hazard, green, etc.).
- Player picks a club, aims, then hits with a **timing-based shot meter** (see Section 4).
- Ball flies with realistic-enough physics, lands, rolls based on the surface it lands on.
- Hole out, record strokes vs par, move to next hole.
- **[NEW]** Auto-advance rules: max stroke cap per hole (e.g. par + 5, then "pick up") so rounds don't drag.
- **[NEW]** Scoring terms shown on hole completion: Ace, Eagle, Birdie, Par, Bogey, Double Bogey+.

### Hazards
- **Water:** ball lands in water = +1 stroke penalty, drop near where it entered.
- **Potholes:** act as bunkers. Ball loses distance/roll and has a reduced-power/accuracy penalty on the next shot unless using a wedge.
- **[NEW]** Additional hazard ideas that fit the "golf in weird places" theme: storm drains (like water, penalty), parked cars/buildings (ball bounces off), hay bales/fences (bounce), traffic cones, mud patches in farm fields (slow the ball), roof edges (out of bounds).
- **[NEW]** Out of bounds: +1 stroke, replay from previous spot.

## 4. Shot Mechanic (timing-based, no swipe)

You said you don't like swipe-back-and-release, and prefer timing buttons and power. Proposed system:

**Three-tap swing meter** (classic, very readable on mobile):
1. **Tap 1: start swing.** A power bar fills up.
2. **Tap 2: set power.** Stop the bar at the desired power (0-100%). The suggested power for the target shows as a marker on the bar (from the mini map).
3. **Tap 3: set accuracy.** A marker sweeps back; tap as close to the center "sweet spot" as possible. Off-center = hook/slice (curves the ball left/right) and small distance loss.

**Shot quality tiers** (drive XP and feedback):
- Perfect (tap within tight window of the sweet spot and near target power)
- Good
- Average
- Poor / Mishit

**[NEW]** Difficulty scaling:
- Better club levels = a wider "good" window and less penalty for mistakes (this is what makes upgrades feel meaningful).
- Putter uses a simplified **two-tap** version: tap for power, aim line is fixed by the player before the swing. Short, satisfying.
- Rough and hazards shrink the sweet-spot window.
- **Wind (decided):** wind affects the **ball flight only** (not the meter). See Section 4b.

**[NEW]** Aiming: player drags/rotates an aim line (or taps to place a target reticle). Aim line shows a dotted arc preview for the currently selected club at 100% power (not affected by accuracy).

## 4b. Wind System

- Every hole has a wind **direction** and **speed in MPH** (randomized within a per-hole range).
- **Wind meter on the HUD:** arrow showing direction relative to the shot line, plus the speed in MPH as a number.
- Wind pushes the ball during flight (stronger effect on high-arc shots like wedges, less on low punch shots). Small effect on roll.
- **Visible wind in the world:** even at low speeds, show tiny wind trails/streaks drifting in the wind direction (cheap pooled particles or scrolling streak quads). At stronger speeds, the environment reacts: trees/flags/grass sway, dust and leaves blow, trails get longer and denser.
- Wind trails should be subtle enough not to clutter the screen or hurt performance (cap particle count, pool them).

## 5. Clubs & Progression

Four club categories, all **free**, all upgradeable through play:

| Club | Role |
|------|------|
| Driver | Longest distance, tee shots, least forgiving |
| Irons | Mid-distance, fairway shots |
| Wedges | Short game, high arc, best out of potholes/rough |
| Putter | On the green |

- Each club has **levels** (e.g. Level 1-10). Upgrading improves: max distance, sweet-spot window size, and recovery from rough/pothole.
- **[NEW]** Upgrades are earned with XP only (never paid) so the free game stays fair. Cosmetic club skins could be a later paid item.
- **[NEW]** Suggested internal structure: club categories contain specific clubs (Driver, 3-Iron to 9-Iron, PW/SW/LW, Putter) and upgrade levels apply per category. Keep it simple at launch: one level per category (4 total), can split later.
- **Irons (decided):** a single "Irons" club at launch, with variable power. Multiple individual irons (3-9) come in a later update, so build `ClubSystem` so adding clubs is data-only.
- So launch clubs are: **Driver, Irons, Wedge, Putter**.

## 6. XP & Rewards

After each round, XP is calculated from performance:
- Birdies, eagles, aces give big bonuses.
- Perfect timing shots (tap 3 in the sweet spot) and perfect power shots give bonus XP.
- Finishing under par gives a round bonus.
- Base XP for completing a round (bigger for 9 and 18).
- **[NEW]** Show a post-round summary screen: score vs par, total strokes, best shot, longest drive, perfect shots count, XP earned (animated count-up), level-up notifications.

## 7. Records / Stats

- Save every completed round locally (date, mode, holes played, strokes per hole, total score, XP earned).
- Detect and celebrate **new personal bests** per mode (3 / 9 / 18) on the results screen.
- Stats screen: best rounds per mode, average score, total birdies/eagles/aces, longest drive, fewest putts in a round.
- **[NEW]** Per-hole personal best, and lifetime stats.

## 8. UI / HUD (portrait)

**Orientation: portrait only, iOS and Android.** Design one-thumb-friendly: the swing meter and club arrows sit in the bottom third of the screen where the thumb reaches; the mini map and stats sit at the top. Handle notches / safe areas and a range of aspect ratios.

**Main menu (v1):** simple. Big Play button, then choose 3 / 9 / 18. Small icons for Stats and Settings.

**In-game HUD:**
- **Mini map (top corner):** overhead view of the hole showing ball, hole, hazards, and the shot line. Shows **distance to the pin** and **suggested power %** for the selected club.
- **Club selector on the playing screen (not in the pause menu):** shows the current club and its level, with **left / right arrows** to cycle through Driver, Irons, Wedge, Putter. One tap to switch, no menu diving.
- Stroke counter, hole number, par.
- **Wind meter:** direction arrow + speed in MPH (see Section 4b).
- Swing meter (bottom of screen when swinging).
- **Pause button** opens the pause menu.

**Pause menu:** Resume, Settings (sound, haptics), Quit Round. That's it.
- **No Restart Hole.** Quitting a round abandons it (no XP or record for an abandoned round, not even for holes already completed; decided).
- Keep it fast: the game should never make the player wait or dig through menus.

**Feel: arcade-like.** Snappy and responsive. Instant input response, short transitions, quick camera cuts, fast hole loading, punchy hit effects, satisfying sound/haptics on perfect shots, and short celebratory animations (skippable). Menus and result screens should be quick and never block play.

**[NEW]** Extra UX: haptic feedback on tap 3 (stronger for perfect), shot replay/camera follow on ball flight, tutorial for first round only (skippable).

## 9. Art Direction

- **Style: arcade-like but HD.** Bright, saturated, readable, with crisp clean visuals. Not a hyper-realistic sim.
- **Lean into cityscapes:** sun glinting off windows, low-angle golden-hour light, a horizon over a residential street beside a farm field. Make it look as HD as possible while keeping the app light.
- **[NEW]** Recommended approach to hit "looks HD but runs light":
  - **Stylized low-poly / clean-stylized 3D** with high-quality lighting rather than photoreal assets. Looks crisp on any screen.
  - **Baked lighting** and lightmaps for static scenery (buildings, roads); only the ball and moving objects use real-time lighting.
  - One strong **directional sun light** with long shadows, plus a sky gradient/HDRI for the horizon glow.
  - **Emissive/specular window materials** with a cheap fake sun-glint (animated specular or a shader that flashes as the camera angle changes).
  - Atmospheric effects kept cheap: distance fog / haze, a bloom pass, subtle lens flare. Avoid heavy volumetrics.
  - Texture atlases, compressed textures (ASTC), LOD on buildings/trees, instancing for repeated props (trees, cars, fences).
  - Ball trail effect and dust/particle puffs on landing (small, pooled particles).
- **[NEW]** Time-of-day variations per hole (sunrise, midday, golden hour, dusk) for variety without extra assets.
- **[NEW]** Sample hole environments (see Section 11).

## 10. Technical Spec

### Engine / Platform  **(decided: Godot 4)**
Target: **iOS and Android** phones, **portrait orientation (decided)**.

**Engine: Godot 4** (decided). Use **GDScript** (simplest, best-supported, text-based).
- Very small install size, light runtime, good 3D for stylized art, exports to iOS + Android, fully text-based project files (works well with Claude Code).
- Use the **Mobile renderer** (Vulkan/Metal) for 3D, portrait orientation, and stretch mode set up for varied phone aspect ratios and safe areas.
- Project setup: Godot 4.x stable, git repo, `.gitignore` for `.godot/`, export presets for iOS and Android configured early so we test on real devices from the first prototype.
- In-app purchases: use a maintained Godot IAP plugin (StoreKit on iOS, Google Play Billing on Android); wrap it in `IAPManager` so the plugin can be swapped if needed. Test this early, since it's the least polished part of Godot.
- Test on real phones often (not just the editor): touch timing and performance feel different on device.

### Architecture (engine-agnostic)
- **Scene/State flow:** MainMenu -> ModeSelect -> RoundLoader -> HoleScene (loop) -> RoundSummary -> MainMenu.
- **Core systems (separate modules):**
  - `RoundManager`: mode, hole order, scoring, stroke cap
  - `HoleData`: per-hole definition (see below)
  - `ShotController`: aiming, swing meter, shot quality calculation
  - `BallPhysics`: flight, bounce, roll, surface friction, wind
  - `SurfaceSystem`: tags terrain (fairway, rough, green, water, pothole, OOB, mud, etc.) with friction/bounce/penalty values
  - `ClubSystem`: stats per club per level
  - `ProgressionSystem`: XP, levels, unlocks
  - `SaveSystem`: local persistence of rounds, stats, club levels, purchases
  - `UIManager`: HUD, mini map, pause, menus
  - `AudioManager`, `HapticsManager`
  - `IAPManager`: store products, restore purchases
- **Data-driven holes:** each hole is a data file (JSON/resource) + scene: tee position, hole position, par, wind range, surface zones, hazards, time-of-day, camera hints. Adding new maps = adding data + assets, no code changes.

### Ball physics
- Simple, deterministic-feeling arc physics (not a full rigid-body sim): launch angle + speed from club/power, gravity, drag, wind force, spin-lite (hook/slice curve from accuracy tap), backspin on wedges.
- Bounce and roll depend on the surface's coefficients.
- Green: putting uses slope (subtle) and friction; keep slopes gentle at launch.
- Fixed timestep for consistent results across devices.
- **[NEW]** Collision with props (walls, cars, trees) using simple collider shapes.

### Mini map
- Top-down orthographic camera rendered to a small viewport (or a pre-rendered map image per hole + dynamic markers). Pre-rendered is cheaper.
- Shows ball, pin, aim line, hazards, and computes **distance** and **recommended power** for the selected club.

### Save data
- Local storage (JSON) v1: club levels, XP, round history, personal bests, settings, purchased packs.
- **[NEW]** Version the save format from day one so future updates don't break saves.
- **[NEW]** Later (optional): cloud save via Game Center / Google Play Games.

### Monetization
- 18 holes free, forever. Extra **map packs** (e.g. "Small Town Pack", "Downtown Pack", "Farm Country Pack") as one-time IAP.
- Use platform IAP (StoreKit / Google Play Billing) via the engine's plugin. Include **Restore Purchases**.
- **Ads: undecided, revisit later.** Focus on building the game first. Keep the architecture ad-ready (an `AdManager` stub / clean hook points between rounds, e.g. round summary screen or optional rewarded "double XP" video) so ads can be added later without refactoring. No ad SDKs in v1.

### Performance targets **[NEW]**
- 60 FPS on mid-range phones from the last ~4 years; 30 FPS fallback on older devices.
- Install size target: under ~150 MB at launch.
- Draw-call and triangle budgets per hole; LODs; texture compression; object pooling; async loading between holes (no long load screens).
- Quality settings (Low / Medium / High) with auto-detect.

### Other **[NEW]**
- Audio: ambient soundscapes per environment (traffic, birds, wind), satisfying hit/cup sounds, light music with a mute option.
- Accessibility: colorblind-safe meter, adjustable meter speed, left-handed UI layout.
- Analytics (privacy-friendly, opt-in): round completion, drop-off holes, club usage, to balance difficulty.
- Testing: unit tests for scoring, XP, and physics determinism; a debug menu to jump to any hole, spawn the ball anywhere, and change wind/club levels.
- Version control: git repo with a clear folder structure (`/scenes`, `/scripts`, `/data/holes`, `/art`, `/audio`, `/ui`).

## 11. The 18 Free Holes (starter list) **[NEW]**

Ideas to lock in (rename/swap as you like). Mix of environment, hazard type, and par:

1. Main Street Opener (small town, par 3)
2. Rooftop Chip (city rooftop, par 3, edge = OOB)
3. Corn Row Drive (farm field, par 4)
4. Cul-de-sac Classic (residential, par 4)
5. Parking Lot Par 5 (mall parking lot, cars as obstacles, par 5)
6. Harbour Dock Dogleg (waterfront, water hazard, par 4)
7. Downtown Canyon (between skyscrapers, wind tunnel, par 4)
8. Pothole Alley (back alley, potholes, par 3)
9. Barnyard Bounce (farm, hay bales, par 4)
10. Schoolyard Shortie (par 3)
11. Overpass Approach (par 4, drainage ditch hazard)
12. Train Yard Trouble (par 5)
13. Vineyard Valley (par 4)
14. Suburban Fairway (backyard to backyard, par 5)
15. Fountain Plaza (city square, fountain = water, par 3)
16. Gravel Road Grind (country road, mud, par 4)
17. Skyline Sunset (elevated park, par 5, dusk lighting)
18. The Grand Finale (mixed city/farm edge, par 5, everything at once)

## 12. Suggested Build Order (milestones) **[NEW]**

1. **Prototype:** one blank test hole, ball physics, 3-tap swing meter, putting, cup detection.
2. **Round loop:** stroke counting, par/score display, hole -> next hole, round summary.
3. **HUD:** mini map with distance/suggested power, club selector, pause menu, wind.
4. **Surfaces & hazards:** water, potholes, OOB, rough, mud.
5. **Clubs & progression:** club stats, XP, levels, save system.
6. **Records:** round history, personal best detection, stats screen.
7. **Content:** build the 18 holes with art pass and lighting.
8. **Polish:** audio, haptics, particles, tutorial, settings, performance pass.
9. **Monetization:** IAP + first paid map pack.
10. **Beta / release:** TestFlight and Google Play internal testing, bug fixing, store listing.

## 13. Open Questions **[DECIDE]**

- Ads: revisit after core game is built.
- ~~Game name?~~ **Decided: Street Golf** (tagline: "Golf where it doesn't belong").

**Decided so far:** Godot 4 (GDScript); portrait; wind affects ball only (with MPH meter + visible trails); one Irons club at launch; club select on-screen with arrows; no restart hole; arcade-like HD style; no leaderboards for now (may revisit later); XP is a currency spent on club upgrades in a Clubs screen (player picks which club, each level costs more); quitting a round earns no XP.

---
## 14. Hole content pipeline (Milestone 7 benchmark)

*Main Street Opener* is the benchmark hole that sets the visual style. A hole is data plus a scene:
see `docs/hole_format.md` for the format, the scenery build tool and the known limits, and
`CREDITS.md` for asset sources (currently: none third-party, everything procedural).

## 15. UI look (Street Golf)

The shared theme lives in `golf-game/ui/theme/street_golf.tres` (Lilita One for titles and buttons,
Fredoka for smaller text, navy outlines, glossy green and orange buttons). See `docs/ui_theme.md`.

*Add new sections below as the idea grows.*
