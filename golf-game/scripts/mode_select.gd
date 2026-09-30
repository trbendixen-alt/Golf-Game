extends Control
## Choose how many holes to play: 3, 9 or 18.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	var column := UiHelpers.add_center_column(self)
	column.add_child(UiHelpers.make_title("CHOOSE A ROUND", 110))
	# `.bind(n)` fills in the hole count for us when the button is pressed.
	column.add_child(UiHelpers.make_button("3 HOLES", RoundManager.start_round.bind(3)))
	column.add_child(UiHelpers.make_button("9 HOLES", RoundManager.start_round.bind(9)))
	column.add_child(UiHelpers.make_button("18 HOLES", RoundManager.start_round.bind(18)))
	column.add_child(UiHelpers.make_button("BACK", _on_back_pressed, "OrangeButton"))


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(RoundManager.MENU_SCENE)
