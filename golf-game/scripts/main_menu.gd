class_name MainMenu
extends Control
## The Street Golf main menu: the Main Street picture behind a tilted title, a tagline,
## two info chips, and three big buttons in the thumb zone (PLAY, STATS, SETTINGS).
##
## Everything is real UI (labels, buttons, containers), so it stays sharp and tappable on
## any screen. Colours, fonts and button looks come from the shared theme:
## ui/theme/street_golf.tres. The layout leaves room for notches and the home bar.
##
## The top-left chip (level + best club) is also a shortcut to the Clubs screen, where
## XP is spent on upgrades, so that stays one tap from the menu.

const THEME := preload("res://ui/theme/street_golf.tres")
const TITLE_SHADER := preload("res://ui/theme/title_gradient.gdshader")
const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const TAGLINE := "GOLF WHERE IT DOESN'T BELONG"
const TITLE_TILT_DEGREES := -5.0
const STREET_SIZE := 230   # Font size of the top line.
const GOLF_SIZE := 272     # The second line is bigger, like the mockup.

var _title_block: Control
var _title_lines: Array[Control] = []
var _ball: BallGlyph
var _chips: Array[Control] = []
var _tagline: Control
var _buttons: Array[Control] = []


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBackdrop.new())

	# Keep everything clear of notches and the home bar.
	var insets := UiHelpers.get_safe_insets(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", int(insets["left"]) + 40)
	margin.add_theme_constant_override("margin_right", int(insets["right"]) + 40)
	margin.add_theme_constant_override("margin_top", int(insets["top"]) + 44)
	margin.add_theme_constant_override("margin_bottom", int(insets["bottom"]) + 70)
	add_child(margin)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)

	page.add_child(_build_top_row())
	page.add_child(_build_title_area())
	page.add_child(_build_tagline())
	# A flexible gap: on taller phones the extra height goes here, so the buttons stay
	# down where the thumb is while the title stays up in the sky.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 1.15
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(gap)
	page.add_child(_build_buttons())
	var below := Control.new()
	below.custom_minimum_size = Vector2(0, 28)
	below.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(below)
	page.add_child(_build_version())

	if OS.is_debug_build():
		_add_debug_shortcut()
	# Wait a frame so the layout exists before the intro animation measures things.
	_play_intro.call_deferred()


# ---------------------------------------------------------------------------
# Building the screen
# ---------------------------------------------------------------------------

func _build_top_row() -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := _make_chip(MenuInfo.level_chip_text())
	left.gui_input.connect(_on_level_chip_input)
	row.add_child(left)
	if ProgressionSystem.any_upgrade_affordable():
		# A small pulsing "!" tells the player they can afford an upgrade.
		var badge := Label.new()
		badge.text = "!"
		badge.add_theme_font_override("font", THEME.get_font("title", "StreetGolf"))
		badge.add_theme_font_size_override("font_size", 52)
		badge.add_theme_color_override("font_color", Color("#ffb347"))
		badge.add_theme_color_override("font_outline_color", Color("#16235a"))
		badge.add_theme_constant_override("outline_size", 10)
		row.add_child(badge)
		var pulse := create_tween().set_loops()
		pulse.tween_property(badge, "modulate:a", 0.35, 0.6)
		pulse.tween_property(badge, "modulate:a", 1.0, 0.6)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	row.add_child(_make_chip(MenuInfo.best_chip_text()))
	return row


func _make_chip(bbcode: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = "ChipPanel"
	var text := RichTextLabel.new()
	text.theme_type_variation = "ChipText"
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.text = bbcode
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(text)
	_chips.append(chip)
	return chip


func _build_title_area() -> Control:
	# The title sits in the open sky: it takes the space between the chips and the tagline.
	var area := CenterContainer.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_block = VBoxContainer.new()
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_block.add_theme_constant_override("separation", -66)
	_title_block.rotation = deg_to_rad(TITLE_TILT_DEGREES)
	_title_block.resized.connect(func() -> void: _title_block.pivot_offset = _title_block.size / 2.0)
	area.add_child(_title_block)

	var street := _title_label("STREET", STREET_SIZE)
	_title_block.add_child(street)
	_title_lines.append(street)

	var golf_row := HBoxContainer.new()
	golf_row.alignment = BoxContainer.ALIGNMENT_CENTER
	golf_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	golf_row.add_theme_constant_override("separation", -6)
	golf_row.resized.connect(func() -> void: golf_row.pivot_offset = golf_row.size / 2.0)
	_title_block.add_child(golf_row)
	_title_lines.append(golf_row)
	golf_row.add_child(_title_label("G", GOLF_SIZE))
	_ball = BallGlyph.new()
	_ball.custom_minimum_size = Vector2(GOLF_SIZE * 1.12, GOLF_SIZE * 1.12)
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball.resized.connect(func() -> void: _ball.pivot_offset = _ball.size / 2.0)
	golf_row.add_child(_ball)
	golf_row.add_child(_title_label("LF", GOLF_SIZE))
	return area


## One piece of the title: chunky letters with a yellow-to-orange fill.
func _title_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.add_theme_font_size_override("font_size", font_size)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var material := ShaderMaterial.new()
	material.shader = TITLE_SHADER
	# The gradient spans the capital letters: these fractions fit Lilita One at any size.
	material.set_shader_parameter("gradient_top", font_size * 0.226)
	material.set_shader_parameter("gradient_height", font_size * 0.587)
	label.material = material
	return label


func _build_tagline() -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var label := Label.new()
	label.theme_type_variation = "TaglineLabel"
	label.text = TAGLINE
	pill.add_child(label)
	holder.add_child(pill)
	_tagline = pill
	pill.resized.connect(func() -> void: pill.pivot_offset = pill.size / 2.0)
	return holder


func _build_buttons() -> Control:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)

	var play := _make_button("PLAY", "BigGreenButton", Vector2(860, 250), _on_play_pressed)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(play)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 34)
	row.add_child(_make_button("STATS", "OrangeButton", Vector2(413, 176), _on_stats_pressed))
	row.add_child(_make_button("SETTINGS", "OrangeButton", Vector2(413, 176), _on_settings_pressed))
	column.add_child(row)
	return column


func _make_button(text: String, variation: String, min_size: Vector2, on_pressed: Callable) -> StreetButton:
	var button := StreetButton.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = min_size
	button.pressed.connect(on_pressed)
	_buttons.append(button)
	return button


func _build_version() -> Control:
	var label := Label.new()
	label.theme_type_variation = "VersionLabel"
	label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Debug runs only: a small link to jump straight to the benchmark hole.
func _add_debug_shortcut() -> void:
	var debug := Button.new()
	debug.text = "debug: Main Street"
	debug.flat = true
	debug.add_theme_font_size_override("font_size", 30)
	debug.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	debug.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	debug.offset_left = 30
	debug.offset_top = -90
	debug.pressed.connect(RoundManager.start_preview.bind("main_street_opener"))
	add_child(debug)


# ---------------------------------------------------------------------------
# Intro animation: a quick bounce-in (about a second), never blocks input
# ---------------------------------------------------------------------------

func _play_intro() -> void:
	var tween := create_tween().set_parallel(true)
	# Title lines pop in one after the other.
	var delay := 0.05
	for line in _title_lines:
		_prepare_pop(line)
		tween.tween_property(line, "scale", Vector2.ONE, 0.5).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(line, "modulate:a", 1.0, 0.15).set_delay(delay)
		delay += 0.14
	# The golf ball spins and bounces in last.
	_ball.scale = Vector2.ZERO
	_ball.rotation = deg_to_rad(-200)
	tween.tween_property(_ball, "scale", Vector2.ONE, 0.7).set_delay(0.3) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_ball, "rotation", 0.0, 0.7).set_delay(0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Then the rest fades/pops in.
	for chip in _chips:
		chip.modulate.a = 0.0
		tween.tween_property(chip, "modulate:a", 1.0, 0.3).set_delay(0.35)
	_prepare_pop(_tagline)
	tween.tween_property(_tagline, "scale", Vector2.ONE, 0.4).set_delay(0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_tagline, "modulate:a", 1.0, 0.2).set_delay(0.55)
	delay = 0.6
	for button in _buttons:
		_prepare_pop(button)
		tween.tween_property(button, "scale", Vector2.ONE, 0.4).set_delay(delay) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "modulate:a", 1.0, 0.15).set_delay(delay)
		delay += 0.09


func _prepare_pop(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2(0.4, 0.4)
	node.modulate.a = 0.0


# ---------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)


func _on_stats_pressed() -> void:
	get_tree().change_scene_to_file(StatsScreen.SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_level_chip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		UiFeedback.press()
		ClubsScreen.open(get_tree(), RoundManager.MENU_SCENE)
