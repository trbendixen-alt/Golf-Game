# How a hole is made (data + scene)

A hole is **data plus a scene**. The data decides how it *plays*; the scene decides how it *looks*.
Main Street Opener (`golf-game/data/holes/main_street_opener.json`) is the pattern for the other 17.

## 1. The hole file (`data/holes/<id>.json`)

Everything the old placeholder holes had (name, par, tee, cup, wind, bounds, surfaces, obstacles)
plus three optional keys that make it a "real" hole:

| Key | What it does |
|---|---|
| `"look": "golden_hour"` | Lighting preset from `data/looks.json`: sun, sky, haze, bloom. |
| `"camera": {back, height, look_ahead, look_height, fov, far}` | Overrides for this hole's camera. Leave keys out to use the defaults. |
| `"scenery": {scene, sun_mask, ...}` | The pre-built scenery scene and its baked shadow mask. Also ground-shader settings (`street_half`, `street_end`, `crosswalks`) and `stakes` (draw out-of-bounds stakes or not). |

A hole **without** `scenery` still works: it is drawn with flat colours, like the placeholder holes.

**The obstacles in the file are the colliders, and they are also the art's source.** A `building`
entry has `size: [depth, width, height]`, and optional `color`, `trim`, `seed`. A `car` has `color`
and `angle`. `lamp`, `tree` and `cone` entries give positions. The scenery tool draws art on exactly
those spots, so what the player sees is what the ball hits.

## 2. The scenery scene (`scenes/holes/<id>/scenery.tscn`)

Built by a tool, not by hand (run from the `golf-game` folder, with a real window, not `--headless`):

```
godot --path . --resolution 64x64 --script res://tools/build_hole_scenery.gd -- main_street_opener
```

It writes `scenery.tscn`, `meshes/*.res`, `materials/*.tres` and `sun_mask.png`. Commit all of them.
Then run `godot --headless --path . --import --quit` so the mask texture is imported (its
`.import` file is set to VRAM-compressed with mipmaps; keep those settings).

What the tool does, and why it is cheap to draw:

- **Merging**: each 45 m slice of street has all its buildings in one mesh (one draw call).
  Building colour, size and window settings travel inside the mesh (see `building_common.gdshaderinc`).
- **Instancing**: cars, trees, lamps, cones and fence posts are MultiMeshes.
- **Level of detail**: every slice has a near and a far version, swapped by distance (Godot
  "visibility ranges"): full window shader vs a "lite" one, detailed vs simple cars/trees/lamps,
  and small clutter that disappears far away.
- **Baked lighting**: the sun's shadows and ambient occlusion on the ground are pre-computed
  into `sun_mask.png`. The sun has real-time shadows switched off for these holes.
  (Only the ground receives baked shadows; see "Known limits" below.)

The scenery tool draws art for these obstacle types: `building`, `car`, `lamp`, `tree`, `cone`.
A new obstacle type needs a model added to the tool (a test fails until it is).

The tool is currently written for the **small-town** theme. A farm or rooftop hole would get its
own theme function in the same tool (same pipeline: obstacles -> art, merge, instance, bake).

## 3. Trying a hole

Run the game (F5). On the main menu, in a debug run, press **DEBUG: MAIN STREET**. It plays that one
hole and saves no XP or records. (`RoundManager.start_preview("<hole id>")` does the same for any hole.)

Developer tools (need a window): `tools/shoot_hole.gd` saves screenshots, `tools/measure_hole.gd`
reports frame rate, draw calls and triangles at 1080x1920. Usage is in each file's first lines.

## Known limits (Milestone 7 benchmark)

- Baked shadows cover the **ground only**. Cars, trees and buildings do not shade each other,
  and the ball has a simple blob shadow.
- No lightmap GI and no reflection probe: Godot's lightmap bake can only be started from the
  editor UI, so it could not be automated here. Windows reflect the sky, not neighbouring buildings.
- Sidewalks and kerbs are flat (the ball physics treats the ground as flat).
