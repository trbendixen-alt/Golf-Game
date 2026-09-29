class_name ClubSelector
extends HBoxContainer
## Club selector: "<" and ">" arrows either side of the current club's name.
## It only shows things and reports button presses; the hole scene decides what to do.

signal previous_pressed
signal next_pressed

var _previous_button: Button
var _next_button: Button
var _name_label: Label
var _stats_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 30)

	_previous_button = _make_arrow_button("<")
	_previous_button.pressed.connect(previous_pressed.emit)
	add_child(_previous_button)

	var names := VBoxContainer.new()
	names.custom_minimum_size = Vector2(420, 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(names)
	_name_label = _make_label(64)
	names.add_child(_name_label)
	_stats_label = _make_label(34)
	names.add_child(_stats_label)

	_next_button = _make_arrow_button(">")
	_next_button.pressed.connect(next_pressed.emit)
	add_child(_next_button)


func set_club(club: Dictionary) -> void:
	_name_label.text = String(club["name"]).to_upper()
	_stats_label.text = "Lv %d  -  Max %d m" % [club["level"], roundi(club["max_distance"])]


## The arrows are switched off while a swing is in progress or the ball is moving.
func set_enabled(enabled: bool) -> void:
	_previous_button.disabled = not enabled
	_next_button.disabled = not enabled


func _make_arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 150)
	button.add_theme_font_size_override("font_size", 80)
	return button


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	return label
