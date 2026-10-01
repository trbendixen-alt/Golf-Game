class_name SettingsScreen
extends Control
## The Settings screen, opened from the main menu: Sound and Haptics switches (saved), and BACK.
## Nothing plays sound yet (Milestone 8), but the choice is remembered and respected by
## UiFeedback, so the switches already control the click sound and buzz hooks.

const THEME := preload("res://ui/theme/street_golf.tres")
const TITLE_SHADER := preload("res://ui/theme/title_gradient.gdshader")


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self, 0.45)

	var insets := UiHelpers.get_safe_insets(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(insets["left"]) + 60)
	margin.add_theme_constant_override("margin_right", int(insets["right"]) + 60)
	margin.add_theme_constant_override("margin_top", int(insets["top"]) + 60)
	margin.add_theme_constant_override("margin_bottom", int(insets["bottom"]) + 60)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 34)
	margin.add_child(column)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 130)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var material := ShaderMaterial.new()
	material.shader = TITLE_SHADER
	material.set_shader_parameter("gradient_top", 38.0)
	material.set_shader_parameter("gradient_height", 92.0)
	title.material = material
	column.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	column.add_child(spacer)

	column.add_child(_make_switch("SOUND", GameSettings.sound_on, _on_sound_changed))
	column.add_child(_make_switch("HAPTICS", GameSettings.haptics_on, _on_haptics_changed))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 80)
	column.add_child(gap)
	var back := StreetButton.new()
	back.text = "BACK"
	back.theme_type_variation = "OrangeButton"
	back.custom_minimum_size = Vector2(700, 180)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_on_back_pressed)
	column.add_child(back)


## A big button that flips between "NAME: ON" (green) and "NAME: OFF" (orange).
func _make_switch(label: String, is_on: bool, on_changed: Callable) -> StreetButton:
	var button := StreetButton.new()
	button.custom_minimum_size = Vector2(700, 160)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The on/off state is kept ON THE BUTTON. (A variable captured by the function below
	# would be a private copy: every press would start from the original value again, and
	# the switch would only ever work once.)
	button.set_meta("is_on", is_on)
	_show_switch(button, label, is_on)
	button.pressed.connect(func() -> void:
		var now_on: bool = not button.get_meta("is_on")
		button.set_meta("is_on", now_on)
		_show_switch(button, label, now_on)
		on_changed.call(now_on))
	return button


func _show_switch(button: Button, label: String, is_on: bool) -> void:
	button.text = "%s: %s" % [label, "ON" if is_on else "OFF"]
	button.theme_type_variation = "Button" if is_on else "OrangeButton"


func _on_sound_changed(enabled: bool) -> void:
	GameSettings.sound_on = enabled
	GameSettings.save_settings()


func _on_haptics_changed(enabled: bool) -> void:
	GameSettings.haptics_on = enabled
	GameSettings.save_settings()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(RoundManager.MENU_SCENE)
