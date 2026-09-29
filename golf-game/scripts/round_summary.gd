extends Control
## Shown after the last hole: a scorecard with total strokes and score vs par.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	var column := UiHelpers.add_center_column(self)
	column.add_theme_constant_override("separation", 20)
	column.add_child(UiHelpers.make_label("ROUND COMPLETE", 80))

	# Scorecard: one row per hole, four columns.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 60)
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

	# Totals.
	column.add_child(UiHelpers.make_label("Total strokes: %d" % RoundManager.total_strokes(), 56))
	column.add_child(UiHelpers.make_label("Par: %d" % RoundManager.total_par(), 56))
	column.add_child(UiHelpers.make_label(
			"Score: %s" % RoundManager.format_vs_par(RoundManager.round_vs_par()), 80))
	column.add_child(UiHelpers.make_button("MAIN MENU", _on_menu_pressed))


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(RoundManager.MENU_SCENE)
