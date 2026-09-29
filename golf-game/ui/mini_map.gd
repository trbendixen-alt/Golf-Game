class_name MiniMap
extends Control
## The mini map in the top corner: a top-down view of the hole's surfaces (fairway,
## green, hazards, out of bounds), the ball, the cup and the aim line (out to where a 100% power shot would stop), plus the distance to the pin and the suggested power for the current club.
## The map is rotated so "up" on it is always the direction you're aiming.

const TEXT_HEIGHT := 110.0  # Space at the bottom for the two lines of text.

# Set every frame by the hole scene through update_map().
var ball_position := Vector3.ZERO
var cup_position := Vector3.ZERO
var aim_direction := Vector3(0, 0, -1)
var shot_end := Vector3.ZERO  # Where a 100% power shot along the aim line stops.
var suggested_power := 0.0
var out_of_range := false   # True if the cup is further than the club can reach.
## The hole's ground. Set once per hole by the HUD.
var surfaces: SurfaceMap


func _ready() -> void:
	custom_minimum_size = Vector2(300, 420)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func update_map(ball_pos: Vector3, cup_pos: Vector3, aim_dir: Vector3, end_pos: Vector3,
		power: float, too_far: bool) -> void:
	ball_position = ball_pos
	cup_position = cup_pos
	aim_direction = aim_dir
	shot_end = end_pos
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

	# The ground, drawn in the same order as the 3D hole so zones overlap the same way.
	var to_map := func(world: Vector2) -> Vector2:
		return centre + _to_map_units(Vector3(world.x, 0.0, world.y) - middle, right) * zoom
	if surfaces == null:
		draw_rect(map_rect, Color(0.25, 0.5, 0.2))
	else:
		var has_bounds := not surfaces.bounds.is_empty()
		draw_rect(map_rect, SurfaceMap.get_type("oob" if has_bounds else surfaces.ground)["color"])
		if has_bounds:
			_draw_zone(surfaces.bounds, surfaces.ground, map_rect, to_map)
		for zone in surfaces.zones:
			_draw_zone(zone["points"], zone["type"], map_rect, to_map)
		for part in surfaces.obstacles.parts:
			_draw_shape(Obstacles.footprint(part), part["color"].darkened(0.2), map_rect, to_map)

	# Aim line: straight up the map (the map is rotated to the aim), out to where a
	# full-power shot stops, cut off at the top edge of the map.
	var end_point := centre + _to_map_units(shot_end - middle, right) * zoom
	end_point.y = maxf(end_point.y, map_rect.position.y)
	if end_point.y < ball_point.y:
		draw_dashed_line(ball_point, end_point, Color(1, 1, 1, 0.9), 3.0, 10.0)
	# Then the cup and the ball on top.
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


## Fill one surface zone, cut off at the edges of the map.
func _draw_zone(points: PackedVector2Array, type_name: String, map_rect: Rect2,
		to_map: Callable) -> void:
	_draw_shape(points, SurfaceMap.get_type(type_name)["color"], map_rect, to_map)


## Fill any ground outline (world x/z points) in a colour, cut off at the map's edges.
func _draw_shape(points: PackedVector2Array, color: Color, map_rect: Rect2,
		to_map: Callable) -> void:
	var on_map := PackedVector2Array()
	for point in points:
		on_map.append(to_map.call(point))
	var frame := PackedVector2Array([map_rect.position, Vector2(map_rect.end.x, map_rect.position.y),
			map_rect.end, Vector2(map_rect.position.x, map_rect.end.y)])
	for piece in Geometry2D.intersect_polygons(on_map, frame):
		if piece.size() >= 3:
			draw_colored_polygon(piece, color)


## World offset (from the map centre) -> map units: x to the right, y DOWN the screen.
func _to_map_units(offset: Vector3, right: Vector3) -> Vector2:
	return Vector2(offset.dot(right), -offset.dot(aim_direction))
