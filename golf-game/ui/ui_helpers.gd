class_name UiHelpers
extends RefCounted
## Small shared helpers for building menu screens in code, so each menu script
## stays short and readable.

const THEME := preload("res://ui/theme/street_golf.tres")
const TITLE_SHADER := preload("res://ui/theme/title_gradient.gdshader")
## The palette's yellow, for numbers and headings.
const YELLOW := Color("#ffd84a")
const NAVY := Color("#16235a")

## How dark the background is under a content screen (Stats, Clubs...), so text stays readable.
const CONTENT_DARKNESS := 0.6


## Puts the animated Main Street background behind the screen, and gives the screen the
## shared Street Golf theme (fonts, colours, button looks). Call this first in a screen's
## _ready(). `darkness` dims the picture: 0 = as is (the main menu), higher = darker.
static func add_background(parent: Control, darkness := CONTENT_DARKNESS) -> void:
	if parent.theme == null:
		parent.theme = THEME
	var backdrop := MenuBackdrop.new()
	backdrop.darkness = darkness
	parent.add_child(backdrop)


## Adds a vertical stack of widgets centred on the screen and returns the stack.
static func add_center_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 40)
	center.add_child(column)
	return column


## Like add_center_column, but the stack scrolls when it's taller than the screen
## (e.g. an 18-hole scorecard). Kept clear of notches and the home bar.
static func add_scroll_column(parent: Control) -> VBoxContainer:
	var insets := get_safe_insets(parent.get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(insets["left"]) + 40)
	margin.add_theme_constant_override("margin_top", int(insets["top"]) + 60)
	margin.add_theme_constant_override("margin_right", int(insets["right"]) + 40)
	margin.add_theme_constant_override("margin_bottom", int(insets["bottom"]) + 60)
	parent.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 30)
	scroll.add_child(column)
	return column


static func make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	# A thin dark outline keeps the text readable over the picture.
	label.add_theme_color_override("font_outline_color", NAVY)
	label.add_theme_constant_override("outline_size", maxi(4, int(font_size * 0.09)))
	return label


## A screen heading: chunky Lilita One letters with the yellow-to-orange gradient, like the
## main menu's title.
static func make_title(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	var material := ShaderMaterial.new()
	material.shader = TITLE_SHADER
	material.set_shader_parameter("gradient_top", font_size * 0.226)
	material.set_shader_parameter("gradient_height", font_size * 0.587)
	label.material = material
	return label


## A big touch-friendly Street Golf button. `on_pressed` is the function to run when tapped.
## `variation` picks the colour: "Button" (green, the default) or "OrangeButton".
static func make_button(text: String, on_pressed: Callable, variation := "Button") -> Button:
	var button := StreetButton.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(650, 190)
	button.add_theme_font_size_override("font_size", 66)
	if on_pressed.is_valid():
		button.pressed.connect(on_pressed)
	return button


## A navy rounded panel to group a screen's content, like a card. Add widgets to the
## returned box. `title` (optional) becomes a yellow heading at the top of the card.
static func make_card(title := "") -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.set_meta("card", true)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	if title != "":
		var heading := make_label(title, 50)
		heading.add_theme_font_override("font", THEME.get_font("title", "StreetGolf"))
		heading.add_theme_color_override("font_color", YELLOW)
		box.add_child(heading)
	return box


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
