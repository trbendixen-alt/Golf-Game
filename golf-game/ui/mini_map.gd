class_name MiniMap
extends Control
## The mini map in the top corner: a top-down view of the ball, the cup and the aim
## line, plus the distance to the pin and the suggested power for the current club.
## The map is rotated so "up" on it is always the direction you're aiming.

const TEXT_HEIGHT := 110.0  # Space at the bottom for the two lines of text.

# Set every frame by the hole scene through update_map().
var ball_position := Vector3.ZERO
var cup_position := Vector3.ZERO
var aim_direction := Vector3(0, 0, -1)
var suggested_power := 0.0
var out_of_range := false   # True if the cup is further than the club can reach.


func _ready() -> void:
	custom_minimum_size = Vector2(300, 420)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_map(ball_pos: Vector3, cup_pos: Vector3, aim_dir: Vector3,
		power: float, too_far: bool) -> void:
	ball_position = ball_pos
	cup_position = cup_pos
	aim_direction = aim_dir
	suggested_power = power
	out_of_range = too_far
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	# Panel background.
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0, 0, 0, 0.55)
	panel.set_corner_radius_all(24)
	draw_style_box(panel, Rect2(Vector2.ZERO, size))

	# The map area (green) sits above the text area.
	var map_rect := Rect2(12, 12, size.x - 24, size.y - TEXT_HEIGHT - 24)
	draw_rect(map_rect, Color(0.25, 0.5, 0.2))

	# Turn world positions into map positions. "right" is the screen-right direction
	# when facing the aim direction; the map is centred between the ball and the cup.
	var right := aim_direction.cross(Vector3.UP)
	var middle := (ball_position + cup_position) / 2.0
	var ball_offset := _to_map_units(ball_position - middle, right)
	var cup_offset := _to_map_units(cup_position - middle, right)

	# Zoom so both the ball and the cup fit with some margin (never zoom in too far).
	var half_width := maxf(maxf(absf(ball_offset.x), absf(cup_offset.x)), 8.0)
	var half_height := maxf(maxf(absf(ball_offset.y), absf(cup_offset.y)), 12.0)
	var zoom := minf(map_rect.size.x * 0.4 / half_width, map_rect.size.y * 0.4 / half_height)
	var centre := map_rect.get_center()
	var ball_point := centre + ball_offset * zoom
	var cup_point := centre + cup_offset * zoom

	# Aim line (dashed), then the cup and the ball on top.
	draw_dashed_line(ball_point, cup_point, Color(1, 1, 1, 0.9), 3.0, 10.0)
	draw_circle(cup_point, 11.0, Color.WHITE)
	draw_circle(cup_point, 8.0, Color(0.9, 0.1, 0.1))
	draw_circle(ball_point, 9.0, Color.BLACK)
	draw_circle(ball_point, 7.0, Color.WHITE)

	# Distance and suggested power.
	var distance := Vector2(ball_position.x - cup_position.x, ball_position.z - cup_position.z).length()
	draw_string(font, Vector2(0, size.y - 62), "%d m" % roundi(distance),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color.WHITE)
	var power_text := "PWR %d%%" % roundi(suggested_power * 100.0)
	if out_of_range:
		power_text += "+"  # Even 100% won't reach.
	draw_string(font, Vector2(0, size.y - 20), power_text,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, Color(1.0, 0.9, 0.2))


## World offset (from the map centre) -> map units: x to the right, y DOWN the screen.
func _to_map_units(offset: Vector3, right: Vector3) -> Vector2:
	return Vector2(offset.dot(right), -offset.dot(aim_direction))
