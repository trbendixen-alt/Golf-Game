class_name HoleHud
extends CanvasLayer
## Everything drawn on top of the 3D hole: stats, mini map, wind meter, pause button,
## club selector and swing meter. It builds the layout and exposes small functions
## for the hole scene to feed it information. It makes no game decisions itself.
##
## Layout (portrait):
##   top:    pause button + hole/stroke stats + wind (left), mini map (right)
##   middle: the big score message
##   bottom: club selector and swing meter, where a thumb reaches
##
## Everything sits inside the phone's "safe area" so notches and the home bar
## never cover it. Containers (MarginContainer, VBoxContainer...) do the positioning.

signal pause_pressed
signal previous_club_pressed
signal next_club_pressed

const EDGE_MARGIN := 24  # Extra space between the screen edge and the HUD.

## Set by the hole scene BEFORE this node is added, so the swing meter can read it.
var shot: ShotController

var _info_label: Label
var _stroke_label: Label
var _lie_label: Label
var _message_label: Label
var _quality_label: Label
var _quality_tween: Tween
var _wind_meter: WindMeter
var _mini_map: MiniMap
var _club_selector: ClubSelector
var _swing_meter: SwingMeter


func _ready() -> void:
	# Outer margin = phone safe area + a little breathing room.
	var insets := UiHelpers.get_safe_insets(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(insets["left"]) + EDGE_MARGIN)
	margin.add_theme_constant_override("margin_top", int(insets["top"]) + EDGE_MARGIN)
	margin.add_theme_constant_override("margin_right", int(insets["right"]) + EDGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", int(insets["bottom"]) + EDGE_MARGIN)
	add_child(margin)

	# Stack: top row / middle (message) / bottom controls.
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	# --- Top row ---
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(top_row)

	var top_left := VBoxContainer.new()
	top_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_left.add_theme_constant_override("separation", 8)
	top_row.add_child(top_left)

	var pause_button := Button.new()
	pause_button.text = "II"
	pause_button.custom_minimum_size = Vector2(110, 110)
	pause_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # Don't stretch wide.
	pause_button.add_theme_font_size_override("font_size", 48)
	pause_button.pressed.connect(pause_pressed.emit)
	top_left.add_child(pause_button)

	_info_label = _make_label(44)
	top_left.add_child(_info_label)
	_stroke_label = _make_label(44)
	top_left.add_child(_stroke_label)
	_lie_label = _make_label(40)
	top_left.add_child(_lie_label)
	_wind_meter = WindMeter.new()
	top_left.add_child(_wind_meter)

	_mini_map = MiniMap.new()
	_mini_map.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # Keep its own height.
	top_row.add_child(_mini_map)

	# --- Middle: takes all the spare space, and centres the score message in it ---
	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(middle)
	_message_label = _make_label(72)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_message_label)

	# --- Bottom: shot grade ("PERFECT!"), club selector, swing meter ---
	_quality_label = _make_label(64)
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality_label.modulate.a = 0.0  # Hidden until a shot is graded.
	page.add_child(_quality_label)

	_club_selector = ClubSelector.new()
	_club_selector.previous_pressed.connect(previous_club_pressed.emit)
	_club_selector.next_pressed.connect(next_club_pressed.emit)
	page.add_child(_club_selector)

	_swing_meter = SwingMeter.new()
	_swing_meter.shot = shot
	page.add_child(_swing_meter)


# ---------------------------------------------------------------------------
# Functions the hole scene calls to update the display
# ---------------------------------------------------------------------------

func set_info(text: String) -> void:
	_info_label.text = text


func set_strokes(text: String) -> void:
	_stroke_label.text = text


func set_message(text: String) -> void:
	_message_label.text = text


## Briefly show how good the last swing was, then fade it out.
func flash_quality(tier_name: String, seconds: float) -> void:
	_quality_label.text = tier_name + "!"
	_quality_label.modulate.a = 1.0
	if _quality_tween:
		_quality_tween.kill()
	_quality_tween = create_tween()
	_quality_tween.tween_interval(seconds * 0.6)
	_quality_tween.tween_property(_quality_label, "modulate:a", 0.0, seconds * 0.4)


## What the ball is sitting on, e.g. "Lie: Rough  -15% PWR". Red when it hurts the shot.
func set_lie(surface_label: String, power_lost_percent: int) -> void:
	_lie_label.text = "Lie: " + surface_label
	if power_lost_percent > 0:
		_lie_label.text += "  -%d%% PWR" % power_lost_percent
		_lie_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	else:
		_lie_label.remove_theme_color_override("font_color")


## Give the mini map the hole's surfaces to draw. Call once per hole.
func set_map_surfaces(surfaces: SurfaceMap) -> void:
	_mini_map.surfaces = surfaces


func set_club(club: Dictionary) -> void:
	_club_selector.set_club(club)


## Turns the club arrows on or off (off while swinging or while the ball is moving).
func set_club_buttons_enabled(enabled: bool) -> void:
	_club_selector.set_enabled(enabled)


## The yellow marker on the power bar (0..1).
func set_suggested_power(power: float) -> void:
	_swing_meter.suggested_power = power


func set_wind(speed_mph: float, arrow_angle: float) -> void:
	_wind_meter.set_wind(speed_mph, arrow_angle)


func update_map(ball_pos: Vector3, cup_pos: Vector3, aim_dir: Vector3, shot_end: Vector3,
		power: float, too_far: bool) -> void:
	_mini_map.update_map(ball_pos, cup_pos, aim_dir, shot_end, power, too_far)


## Creates a left-aligned text label with a dark outline so it's readable on any background.
func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	return label
