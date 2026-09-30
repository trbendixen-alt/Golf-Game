class_name HoleScenery
extends Node3D
## The root of a hole's pre-built scenery scene (made by tools/build_hole_scenery.gd).
## It only carries a little information the hole needs to draw its ground correctly.

## The ground area (x, z, width, length in metres) covered by the baked sun-shadow mask.
@export var mask_rect := Rect2()
## Direction from the ground toward the sun that the shadows were baked for.
@export var to_sun := Vector3.UP
