class_name StatsScreen
extends Control
## The Stats screen, reached from the main menu. Everything here is read from the
## saved data (round history, club levels) through Records and ProgressionSystem.
## Nothing is stored on this screen.
##
## Shows: the four clubs (with pictures, levels and max distance), rounds played,
## best / average / fewest putts for each round length (3, 9, 18), lifetime birdies,
## eagles and aces, longest drive, and your best score on each hole.
## In a debug build (like when you press F5 in the editor) there's also a button to
## wipe all saved data, for testing first-time behaviour.

const SCENE := "res://scenes/stats.tscn"
const EMPTY := "--"  # Shown when there's nothing to show yet.

var _column: VBoxContainer
var _reset_armed := false  # The debug reset needs two taps, so it can't happen by accident.
var _reset_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	_column = UiHelpers.add_scroll_column(self)
	_rebuild()


## Draw everything again (used at the start, and after the debug reset).
func _rebuild() -> void:
	for child in _column.get_children():
		child.queue_free()
	_column.add_child(UiHelpers.make_title("STATS", 130))

	_add_card(UiHelpers.make_card("YOUR CLUBS")).add_child(_club_tiles())
	var rounds_card := UiHelpers.make_card()
	_add_card(rounds_card)
	rounds_card.add_child(_row_table([["Rounds played", str(Records.rounds_played())]], 50))

	var modes_card := UiHelpers.make_card("BY ROUND LENGTH")
	_add_card(modes_card)
	modes_card.add_child(_mode_table())
	var note := UiHelpers.make_label("Scores are compared to par. Putts = fewest in one round.", 28)
	note.modulate = Color(1, 1, 1, 0.75)
	modes_card.add_child(note)

	var lifetime_card := UiHelpers.make_card("LIFETIME")
	_add_card(lifetime_card)
	var longest := Records.longest_drive()
	lifetime_card.add_child(_row_table([
		["Aces", str(Records.term_count("Ace"))],
		["Eagles", str(Records.term_count("Eagle"))],
		["Birdies", str(Records.term_count("Birdie"))],
		["Longest drive", "%d m" % roundi(longest) if longest > 0.0 else EMPTY],
	], 44))

	var holes_card := UiHelpers.make_card("BEST SCORE PER HOLE")
	_add_card(holes_card)
	holes_card.add_child(_hole_table())

	var back := UiHelpers.make_button("BACK", _on_back_pressed, "OrangeButton")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(back)
	if OS.is_debug_build():
		_reset_button = UiHelpers.make_button("DEBUG: RESET ALL DATA", _on_reset_pressed, "OrangeButton")
		_reset_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_reset_button.add_theme_font_size_override("font_size", 50)
		_column.add_child(_reset_button)


## Puts a card (made by UiHelpers.make_card) into the column. Returns the card's inner box.
func _add_card(box: VBoxContainer) -> VBoxContainer:
	_column.add_child(box.get_parent())
	return box


## The four clubs side by side: a picture, the name, its level and how far it goes.
func _club_tiles() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for club_name in ClubSystem.club_names():
		var level := SaveSystem.club_level(club_name)
		var club := ClubSystem.get_club(club_name, level)
		var tile := VBoxContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_constant_override("separation", 4)
		var icon := ClubIcon.new()
		icon.kind = club_name
		icon.custom_minimum_size = Vector2(150, 290)
		tile.add_child(icon)
		var name_label := UiHelpers.make_label(club_name.to_upper(), 44)
		name_label.add_theme_font_override("font", UiHelpers.THEME.get_font("title", "StreetGolf"))
		tile.add_child(name_label)
		var level_label := UiHelpers.make_label("Lv %d" % level, 40)
		level_label.add_theme_color_override("font_color", UiHelpers.YELLOW)
		tile.add_child(level_label)
		var distance_label := UiHelpers.make_label("%d m" % roundi(club["max_distance"]), 34)
		distance_label.modulate = Color(1, 1, 1, 0.8)
		tile.add_child(distance_label)
		grid.add_child(tile)
	return grid


## One row per mode: rounds played, best round, average, fewest putts.
func _mode_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 34)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for heading in ["MODE", "ROUNDS", "BEST", "AVG", "PUTTS"]:
		grid.add_child(_table_heading(heading))
	for mode in Records.MODES:
		var played := Records.rounds_for_mode(mode).size()
		var best := Records.best_round(mode)
		var fewest_putts := Records.fewest_putts(mode)
		grid.add_child(UiHelpers.make_label("%d holes" % mode, 38))
		grid.add_child(UiHelpers.make_label(str(played), 38))
		grid.add_child(UiHelpers.make_label(
				EMPTY if best.is_empty() else RoundManager.format_vs_par(best["vs_par"]), 38))
		grid.add_child(UiHelpers.make_label(_format_average(Records.average_vs_par(mode)), 38))
		grid.add_child(UiHelpers.make_label(EMPTY if fewest_putts < 0 else str(fewest_putts), 38))
	return grid


## One row per hole in data/holes/: its par and your fewest strokes on it.
func _hole_table() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 50)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for heading in ["HOLE", "PAR", "BEST"]:
		grid.add_child(_table_heading(heading))
	for hole in RoundManager.all_holes():
		var best := Records.hole_best(hole["name"])
		var name_label := UiHelpers.make_label(hole["name"], 38)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(name_label)
		grid.add_child(UiHelpers.make_label(str(hole["par"]), 38))
		grid.add_child(UiHelpers.make_label(EMPTY if best < 0 else str(best), 38))
	return grid


## A two-column table: label on the left, value (in yellow) on the right.
func _row_table(rows: Array, font_size: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 80)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for row in rows:
		var name_label := UiHelpers.make_label(row[0], font_size)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		grid.add_child(name_label)
		var value_label := UiHelpers.make_label(row[1], font_size)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", UiHelpers.YELLOW)
		grid.add_child(value_label)
	return grid


func _table_heading(text: String) -> Label:
	var label := UiHelpers.make_label(text, 32)
	label.modulate = Color(1, 1, 1, 0.7)
	return label


## An average score vs par with one decimal, e.g. "+1.5" (or "--" with no rounds).
static func _format_average(average: float) -> String:
	if is_nan(average):
		return EMPTY
	if absf(average) < 0.05:
		return "E"
	return "%+.1f" % average


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(RoundManager.MENU_SCENE)


## Debug only. The first tap asks "are you sure?"; the second wipes everything.
func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "TAP AGAIN TO ERASE"
		return
	SaveSystem.reset_all()
	_reset_armed = false
	_rebuild()
