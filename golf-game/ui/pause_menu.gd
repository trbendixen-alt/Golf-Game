class_name PauseMenu
extends CanvasLayer
## The pause menu: Resume, Settings and Quit Round. (There's deliberately no
## "Restart Hole".) The Settings page has sound and haptics toggles. They're saved,
## but nothing plays sound or buzzes yet (Milestone 8).

var _main_column: VBoxContainer
var _settings_column: VBoxContainer


func _ready() -> void:
	layer = 10  # Draw on top of the HUD.
	# ALWAYS = keep working while the game is paused, otherwise the buttons would freeze too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Darken the game behind the menu. It also blocks taps from reaching the game.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# Page 1: the main pause menu.
	_main_column = UiHelpers.add_center_column(root)
	_main_column.add_child(UiHelpers.make_label("PAUSED", 90))
	_main_column.add_child(UiHelpers.make_button("RESUME", close))
	_main_column.add_child(UiHelpers.make_button("SETTINGS", _show_settings))
	_main_column.add_child(UiHelpers.make_button("QUIT ROUND", _on_quit_pressed))

	# Page 2: settings.
	_settings_column = UiHelpers.add_center_column(root)
	_settings_column.add_child(UiHelpers.make_label("SETTINGS", 90))
	_settings_column.add_child(_make_toggle("SOUND", GameSettings.sound_on, _on_sound_toggled))
	_settings_column.add_child(_make_toggle("HAPTICS", GameSettings.haptics_on, _on_haptics_toggled))
	_settings_column.add_child(UiHelpers.make_button("BACK", _show_main))
	_settings_column.get_parent().visible = false  # Hide page 2 (its CenterContainer).


func open() -> void:
	_show_main()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


func _show_main() -> void:
	_settings_column.get_parent().visible = false
	_main_column.get_parent().visible = true


func _show_settings() -> void:
	_main_column.get_parent().visible = false
	_settings_column.get_parent().visible = true


func _on_quit_pressed() -> void:
	get_tree().paused = false  # Must unpause before leaving, or the menu would start frozen.
	RoundManager.abandon_round()


func _on_sound_toggled(enabled: bool) -> void:
	GameSettings.sound_on = enabled
	GameSettings.save_settings()


func _on_haptics_toggled(enabled: bool) -> void:
	GameSettings.haptics_on = enabled
	GameSettings.save_settings()


## A big button that flips between "NAME: ON" and "NAME: OFF" each time it's tapped.
func _make_toggle(label: String, is_on: bool, on_toggled: Callable) -> Button:
	var toggle := UiHelpers.make_button("", Callable())
	toggle.toggle_mode = true
	toggle.button_pressed = is_on
	toggle.text = "%s: %s" % [label, "ON" if is_on else "OFF"]
	toggle.toggled.connect(func(enabled: bool) -> void:
		toggle.text = "%s: %s" % [label, "ON" if enabled else "OFF"]
		on_toggled.call(enabled))
	return toggle
