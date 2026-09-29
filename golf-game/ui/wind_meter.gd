class_name WindMeter
extends Control
## Shows the wind: an arrow plus the speed in MPH. The arrow is drawn relative to your
## shot: pointing UP means the wind blows the way you're hitting (a tailwind),
## pointing right pushes the ball right, and so on.

var speed_mph := 0.0
## Arrow rotation in radians, clockwise from "up".
var arrow_angle := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(300, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_wind(mph: float, angle: float) -> void:
	speed_mph = mph
	arrow_angle = angle
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var circle_centre := Vector2(65, 65)
	draw_circle(circle_centre, 60.0, Color(0, 0, 0, 0.55))

	# The arrow: drawn pointing up, then rotated by drawing with a transform.
	draw_set_transform(circle_centre, arrow_angle)
	var arrow := PackedVector2Array([
		Vector2(0, -44), Vector2(24, -4), Vector2(9, -4),
		Vector2(9, 36), Vector2(-9, 36), Vector2(-9, -4), Vector2(-24, -4)])
	draw_colored_polygon(arrow, Color.WHITE)
	draw_set_transform(Vector2.ZERO)  # Back to normal for the text.

	draw_string(font, Vector2(140, 60), "%d" % roundi(speed_mph),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color.WHITE)
	draw_string(font, Vector2(140, 100), "MPH WIND",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
