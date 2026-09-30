class_name ClubIcon
extends Control
## A picture of a golf club: Driver, Irons, Wedge or Putter. It is drawn with code, not
## from an image file, so it stays sharp at any size. Set `kind` to the club's name.
## Used on the Stats screen. Each club has its own head shape and colour:
##   Driver = big round orange head, Irons = steel blade, Wedge = gold angled blade,
##   Putter = flat green blade with an alignment line.

const NAVY := Color("#0c1538")
const STEEL := Color(0.80, 0.84, 0.92)
const HEAD_SCALE := 1.35

## "Driver", "Irons", "Wedge" or "Putter".
@export var kind := "Driver":
	set(value):
		kind = value
		queue_redraw()
## How much the club leans, in degrees.
@export var lean_degrees := 16.0


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(130, 260)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	# Draw in a 100 x 200 box centred on (0, 0), then scale/tilt it to fit this control.
	var fit := minf(size.x / 100.0, size.y / 200.0) * 0.92
	var club_transform := Transform2D(deg_to_rad(lean_degrees), size / 2.0).scaled_local(Vector2(fit, fit))
	# The head is drawn a little bigger than life, so each club is easy to tell apart.
	var head_pivot := Vector2(0, 60)
	var head_transform := club_transform.translated_local(head_pivot) \
			.scaled_local(Vector2(HEAD_SCALE, HEAD_SCALE)).translated_local(-head_pivot)
	draw_set_transform_matrix(head_transform)
	# Soft shadow on the ground behind the head.
	_draw_shape(_head_points(), Color(0, 0, 0, 0.0), Vector2(5, 6), Color(0, 0, 0, 0.3), 0.0)
	draw_set_transform_matrix(club_transform)

	# Shaft: navy outline, steel core, a thin highlight.
	draw_line(Vector2(0, -84), Vector2(0, 62), NAVY, 10.0, true)
	draw_line(Vector2(0, -84), Vector2(0, 62), STEEL, 5.0, true)
	draw_line(Vector2(-1.2, -80), Vector2(-1.2, 58), Color(1, 1, 1, 0.8), 1.4, true)
	# Grip: dark with two yellow bands.
	draw_rect(Rect2(-7, -100, 14, 50), NAVY)
	draw_rect(Rect2(-5, -98, 10, 46), Color(0.20, 0.23, 0.36))
	for y in [-88.0, -74.0]:
		draw_rect(Rect2(-5, y, 10, 4), Color("#ffd84a"))

	draw_set_transform_matrix(head_transform)
	_draw_head()
	draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------------------
# Heads
# ---------------------------------------------------------------------------

func _draw_head() -> void:
	match kind:
		"Driver":
			_draw_shape(_head_points(), Color("#ff9626"), Vector2.ZERO, NAVY, 5.0)
			# Crown highlight and a white swoosh.
			_draw_shape(_ellipse(Vector2(14, 64), 19, 7, 20), Color("#ffc862"), Vector2.ZERO, Color(0, 0, 0, 0), 0.0)
			draw_line(Vector2(0, 76), Vector2(30, 80), Color(1, 1, 1, 0.75), 2.4, true)
		"Irons":
			_draw_shape(_head_points(), STEEL, Vector2.ZERO, NAVY, 5.0)
			_draw_grooves(Color(0.35, 0.40, 0.55), 4, Vector2(8, 69), Vector2(40, 69), 4.5)
			draw_line(Vector2(6, 62), Vector2(38, 65), Color(1, 1, 1, 0.9), 2.0, true)
		"Wedge":
			_draw_shape(_head_points(), Color("#ffd84a"), Vector2.ZERO, NAVY, 5.0)
			_draw_grooves(Color(0.72, 0.50, 0.08), 5, Vector2(8, 68), Vector2(36, 66), 4.2)
			draw_line(Vector2(6, 61), Vector2(36, 62), Color(1, 1, 1, 0.85), 2.0, true)
		_:  # Putter
			draw_line(Vector2(0, 58), Vector2(0, 72), NAVY, 10.0, true)
			draw_line(Vector2(0, 58), Vector2(0, 72), STEEL, 5.0, true)
			_draw_shape(_head_points(), Color("#48d03e"), Vector2.ZERO, NAVY, 5.0)
			draw_line(Vector2(21, 72), Vector2(21, 85), Color(1, 1, 1, 0.95), 2.6, true)   # alignment line
			draw_line(Vector2(-2, 72.5), Vector2(44, 72.5), Color(1, 1, 1, 0.6), 2.0, true)


func _head_points() -> PackedVector2Array:
	match kind:
		"Driver":
			return _ellipse(Vector2(16, 76), 28, 17, 28)
		"Irons":
			return PackedVector2Array([Vector2(-4, 58), Vector2(5, 58), Vector2(38, 64), Vector2(46, 72),
					Vector2(44, 86), Vector2(-4, 88)])
		"Wedge":
			return PackedVector2Array([Vector2(-4, 58), Vector2(5, 58), Vector2(34, 60), Vector2(48, 70),
					Vector2(46, 83), Vector2(30, 91), Vector2(-4, 89)])
		_:
			return PackedVector2Array([Vector2(-6, 72), Vector2(44, 72), Vector2(49, 76), Vector2(49, 84),
					Vector2(44, 89), Vector2(-6, 89)])


func _ellipse(centre: Vector2, radius_x: float, radius_y: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points:
		var angle := TAU * i / points
		result.append(centre + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return result


## Fill a shape, then outline it. `offset` moves the whole shape (used for the shadow).
## With width 0 there is no outline: the shape is just filled (with `outline` if `fill`
## is fully transparent, which is how the soft shadow is drawn).
func _draw_shape(points: PackedVector2Array, fill: Color, offset: Vector2, outline: Color, width: float) -> void:
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + offset)
	if width <= 0.0:
		draw_colored_polygon(moved, fill if fill.a > 0.0 else outline)
		return
	draw_colored_polygon(moved, fill)
	var closed := moved.duplicate()
	closed.append(moved[0])
	draw_polyline(closed, outline, width, true)


## A few short parallel lines across a club face.
func _draw_grooves(color: Color, count: int, from: Vector2, to: Vector2, spacing: float) -> void:
	for i in count:
		var shift := Vector2(0, spacing * i)
		draw_line(from + shift, to + shift, color, 1.6, true)
