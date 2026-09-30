extends Control
## Shown after the last hole: the score, a scorecard, the round's best moments, and
## the XP it earned (counting up). Tapping skips the count-up. It scrolls, because an
## 18-hole scorecard is long.

const COUNT_UP_SECONDS := 1.2
const HIGHLIGHT := Color(1.0, 0.9, 0.2)

var _xp_label: Label
var _xp_tween: Tween
var _xp_total := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	var column := UiHelpers.add_scroll_column(self)

	column.add_child(UiHelpers.make_label("ROUND COMPLETE", 80))
	column.add_child(UiHelpers.make_label(
			RoundManager.format_vs_par(RoundManager.round_vs_par()), 150))
	column.add_child(UiHelpers.make_label("%d strokes  -  par %d" % [
			RoundManager.total_strokes(), RoundManager.total_par()], 48))

	# Scorecard: one row per hole, four columns.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 60)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(grid)
	for heading in ["HOLE", "PAR", "STROKES", "SCORE"]:
		grid.add_child(UiHelpers.make_label(heading, 36))
	for i in RoundManager.results.size():
		var result: Dictionary = RoundManager.results[i]
		var difference: int = result["strokes"] - result["par"]
		grid.add_child(UiHelpers.make_label(str(i + 1), 40))
		grid.add_child(UiHelpers.make_label(str(result["par"]), 40))
		grid.add_child(UiHelpers.make_label(str(result["strokes"]), 40))
		grid.add_child(UiHelpers.make_label(RoundManager.format_vs_par(difference), 40))

	# Highlights.
	var highlights := [["Perfect shots", str(RoundManager.tier_counts[ShotQuality.Tier.PERFECT])]]
	if RoundManager.longest_drive > 0.0:
		highlights.push_front(["Longest drive", "%d m" % roundi(RoundManager.longest_drive)])
	if RoundManager.longest_hole_out > 0.0:
		highlights.append(["Longest hole-out", "%d m" % roundi(RoundManager.longest_hole_out)])
	column.add_child(_two_columns(highlights, 44))

	# XP: what each thing earned, then the total counting up.
	var round_xp := RoundManager.round_xp
	if round_xp.is_empty():  # Scene run on its own in the editor: nothing was earned.
		round_xp = {"lines": [], "total": 0}
	column.add_child(UiHelpers.make_label("XP EARNED", 56))
	var xp_lines := []
	for line in round_xp["lines"]:
		xp_lines.append([line["label"], "+%d" % line["xp"]])
	column.add_child(_two_columns(xp_lines, 38))
	_xp_total = round_xp["total"]
	_xp_label = UiHelpers.make_label("+0 XP", 96)
	_xp_label.add_theme_color_override("font_color", HIGHLIGHT)
	column.add_child(_xp_label)
	column.add_child(UiHelpers.make_label("You have %d XP" % SaveSystem.xp(), 40))
	if ProgressionSystem.any_upgrade_affordable():
		var upgrade := UiHelpers.make_label("UPGRADE AVAILABLE!", 56)
		upgrade.add_theme_color_override("font_color", HIGHLIGHT)
		column.add_child(upgrade)

	column.add_child(UiHelpers.make_button("CLUBS", _on_clubs_pressed))
	column.add_child(UiHelpers.make_button("MAIN MENU", _on_menu_pressed))

	_xp_tween = create_tween()
	_xp_tween.tween_method(_show_xp, 0, _xp_total, COUNT_UP_SECONDS) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Any tap finishes the count-up straight away (the game never makes you wait).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _xp_tween and _xp_tween.is_running():
		_xp_tween.kill()
		_show_xp(_xp_total)


func _show_xp(amount: int) -> void:
	_xp_label.text = "+%d XP" % amount


## A two-column table: label on the left, value on the right.
func _two_columns(rows: Array, font_size: int) -> GridContainer:
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
		grid.add_child(value_label)
	return grid


func _on_clubs_pressed() -> void:
	ClubsScreen.open(get_tree(), RoundManager.MENU_SCENE)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(RoundManager.MENU_SCENE)
