class_name BallGlyph
extends Control
## A golf ball drawn as a letter: the "O" in GOLF. It's drawn with code (not an image),
## so it stays sharp at any size. It matches the title letters: a thick navy outline and
## a drop shadow.

const NAVY := Color("#0c1538")

## Thickness of the dark outline, in pixels.
@export var outline := 26.0
@export var shadow_offset := 14.0


func _draw() -> void:
	var centre := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - outline - shadow_offset / 2.0
	# Drop shadow, outline, then the ball itself.
	draw_circle(centre + Vector2(0, shadow_offset), radius + outline, Color(0, 0, 0, 0.5), true, -1.0, true)
	draw_circle(centre, radius + outline, NAVY, true, -1.0, true)
	draw_circle(centre, radius, Color(0.80, 0.84, 0.93), true, -1.0, true)            # shaded rim
	draw_circle(centre + Vector2(-radius * 0.07, -radius * 0.07), radius * 0.93, Color(0.96, 0.97, 1.0), true, -1.0, true)
	draw_circle(centre + Vector2(-radius * 0.12, -radius * 0.12), radius * 0.72, Color(1, 1, 1), true, -1.0, true)  # highlight
	# Dimples.
	var dimple := Color(0.68, 0.73, 0.85)
	for spot in [Vector2(0.05, -0.50), Vector2(-0.38, -0.22), Vector2(0.36, -0.14), Vector2(-0.06, 0.12),
			Vector2(-0.32, 0.42), Vector2(0.22, 0.44)]:
		draw_circle(centre + spot * radius, radius * 0.085, dimple, true, -1.0, true)
