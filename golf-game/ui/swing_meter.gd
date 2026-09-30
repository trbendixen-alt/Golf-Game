class_name SwingMeter
extends Control
## Draws the swing meter (a power bar and an accuracy bar; putts only use power). It sits at the bottom of
## the screen, where a thumb can reach. It only *displays* what ShotController tracks.

## Set by the HUD so we know what to draw.
var shot: ShotController
## Where to draw the yellow "suggested power" marker (0..1). Negative = don't draw it.
var suggested_power := -1.0

const BAR_HEIGHT := 70.0
const MARKER_COLOR := Color(1.0, 0.9, 0.2)


func _ready() -> void:
	custom_minimum_size = Vector2(0, 400)
	# IGNORE so this overlay doesn't swallow the player's taps.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()  # Ask Godot to call _draw() again this frame.


func _draw() -> void:
	if shot == null:
		return
	var font := ThemeDB.fallback_font
	var bar_width := size.x * 0.9
	var left := (size.x - bar_width) / 2.0
	var power_y := 165.0
	var accuracy_y := 325.0

	# --- Instruction text ---
	var hint := ""
	match shot.state:
		ShotController.State.IDLE:
			hint = "DRAG TO AIM  -  TAP TO SWING"
		ShotController.State.POWER:
			hint = "TAP TO HIT" if shot.two_tap else "TAP TO SET POWER"
		ShotController.State.ACCURACY:
			hint = "TAP TO SET ACCURACY"
	# Dark outline first so the hint stays readable over the white distance stripes.
	draw_string_outline(font, Vector2(0, 55), hint,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, 10, Color.BLACK)
	draw_string(font, Vector2(0, 55), hint,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color.WHITE)

	# --- Power bar: fills left to right, green (soft) to red (hard) ---
	draw_string(font, Vector2(left, power_y - 12), "POWER",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
	draw_rect(Rect2(left, power_y, bar_width, BAR_HEIGHT), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(left, power_y, bar_width * shot.power, BAR_HEIGHT),
			Color.from_hsv(0.33 * (1.0 - shot.power), 0.9, 0.95))
	# Yellow marker: stop the bar here to hit the ball as far as the cup.
	if suggested_power >= 0.0:
		var marker_x := left + bar_width * clampf(suggested_power, 0.0, 1.0)
		draw_rect(Rect2(marker_x - 5, power_y - 12, 10, BAR_HEIGHT + 24), MARKER_COLOR)

	# --- Accuracy bar: keep the marker inside the green zone in the middle ---
	if shot.two_tap:
		return  # Putts are power only.
	draw_string(font, Vector2(left, accuracy_y - 12), "ACCURACY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE)
	draw_rect(Rect2(left, accuracy_y, bar_width, BAR_HEIGHT), Color(0, 0, 0, 0.6))
	var centre_x := left + bar_width / 2.0
	var sweet_width := shot.sweet_spot * bar_width
	draw_rect(Rect2(centre_x - sweet_width / 2.0, accuracy_y, sweet_width, BAR_HEIGHT),
			Color(0.2, 0.9, 0.3, 0.8))
	# Only show the marker once the accuracy sweep has begun.
	if shot.state == ShotController.State.ACCURACY or shot.state == ShotController.State.LOCKED:
		var marker_x := centre_x + shot.accuracy * bar_width / 2.0
		draw_rect(Rect2(marker_x - 6, accuracy_y - 8, 12, BAR_HEIGHT + 16), Color.WHITE)
