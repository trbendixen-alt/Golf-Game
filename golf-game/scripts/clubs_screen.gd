class_name ClubsScreen
extends Control
## Spend XP on club upgrades. Each club shows its level, what the next level improves
## (max distance, sweet spot, recovery from bad lies) and what it costs.

const SCENE := "res://scenes/clubs.tscn"
const HIGHLIGHT := Color(1.0, 0.9, 0.2)
const PANEL_COLOR := Color(0, 0, 0, 0.3)

## Where BACK goes. Set by open().
static var back_scene := "res://scenes/main_menu.tscn"

var _column: VBoxContainer


## Show the clubs screen; BACK returns to `return_to`.
static func open(tree: SceneTree, return_to: String) -> void:
	back_scene = return_to
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	_column = UiHelpers.add_scroll_column(self)
	_rebuild()


## Draw everything again (after an upgrade, levels and XP have changed).
func _rebuild() -> void:
	for child in _column.get_children():
		child.queue_free()
	_column.add_child(UiHelpers.make_label("CLUBS", 90))
	var balance := UiHelpers.make_label("%d XP" % SaveSystem.xp(), 64)
	balance.add_theme_color_override("font_color", HIGHLIGHT)
	_column.add_child(balance)
	for club_name in ClubSystem.club_names():
		_column.add_child(_club_panel(club_name))
	_column.add_child(UiHelpers.make_button("BACK", _on_back_pressed))


func _club_panel(club_name: String) -> PanelContainer:
	var level := SaveSystem.club_level(club_name)
	var club := ClubSystem.get_club(club_name, level)
	var maxed := level >= ClubSystem.max_level()
	var next := club if maxed else ClubSystem.get_club(club_name, level + 1)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(24)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)

	rows.add_child(UiHelpers.make_label("%s   Lv %d / %d" % [
			club_name.to_upper(), level, ClubSystem.max_level()], 56))
	# Each stat: now -> after the upgrade.
	rows.add_child(_stat_row("Max distance", "%d m", roundf(club["max_distance"]),
			roundf(next["max_distance"]), maxed))
	rows.add_child(_stat_row("Sweet spot", "%.1f%%", club["sweet_spot"] * 100.0,
			next["sweet_spot"] * 100.0, maxed))
	rows.add_child(_stat_row("Recovery", "%d%%", roundf(club["recovery"] * 100.0),
			roundf(next["recovery"] * 100.0), maxed))

	var button: Button
	if maxed:
		button = UiHelpers.make_button("MAXED OUT", Callable())
		button.disabled = true
	else:
		var cost := ProgressionSystem.upgrade_cost(level)
		button = UiHelpers.make_button("UPGRADE  -  %d XP" % cost, _on_upgrade_pressed.bind(club_name))
		button.disabled = not ProgressionSystem.can_upgrade(club_name)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rows.add_child(button)
	return panel


## "Max distance   130 m  ->  135 m" (or just the value once maxed).
## `value_format` is e.g. "%d m" or "%.1f%%"; the arrow only shows if the shown value changes.
func _stat_row(stat: String, value_format: String, now: float, after: float, maxed: bool) -> Label:
	var now_text := value_format % now
	var after_text := value_format % after
	var text := "%s   %s" % [stat, now_text]
	if not maxed and after_text != now_text:
		text += "  ->  " + after_text
	return UiHelpers.make_label(text, 38)


func _on_upgrade_pressed(club_name: String) -> void:
	if ProgressionSystem.upgrade(club_name):
		_rebuild()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)
