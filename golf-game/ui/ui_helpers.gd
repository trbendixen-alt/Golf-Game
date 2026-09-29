class_name UiHelpers
extends RefCounted
## Small shared helpers for building menu screens in code, so each menu script
## stays short and readable.

const BACKGROUND_COLOR := Color(0.12, 0.30, 0.18)


## Fills the whole screen with a solid colour behind the menu.
static func add_background(parent: Control) -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)


## Adds a vertical stack of widgets centred on the screen and returns the stack.
static func add_center_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 40)
	center.add_child(column)
	return column


static func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


## A big touch-friendly button. `on_pressed` is the function to run when tapped.
static func make_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(650, 150)
	button.add_theme_font_size_override("font_size", 60)
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	return button


## Set to true to preview a phone notch / home bar on desktop while testing.
const SIMULATE_NOTCH := false


## How far in from each screen edge we must keep clear of notches, rounded corners and
## the home bar, in the game's own screen units. Returns { left, top, right, bottom }.
static func get_safe_insets(viewport: Viewport) -> Dictionary:
	if SIMULATE_NOTCH:
		return {"left": 0.0, "top": 110.0, "right": 0.0, "bottom": 60.0}
	var insets := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	# Desktop windows have no notch. (On desktop the "safe area" is just the usable screen.)
	if not OS.has_feature("mobile"):
		return insets
	var safe := DisplayServer.get_display_safe_area()      # In real screen pixels.
	var screen := DisplayServer.screen_get_size()
	var window := DisplayServer.window_get_size()
	# Convert real pixels into the game's scaled screen units.
	var to_units := viewport.get_visible_rect().size.x / float(window.x)
	insets["left"] = safe.position.x * to_units
	insets["top"] = safe.position.y * to_units
	insets["right"] = (screen.x - safe.end.x) * to_units
	insets["bottom"] = (screen.y - safe.end.y) * to_units
	return insets
