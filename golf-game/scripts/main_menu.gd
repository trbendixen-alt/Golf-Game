extends Control
## The main menu: a title and a big Play button.

const MODE_SELECT_SCENE := "res://scenes/mode_select.tscn"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiHelpers.add_background(self)
	var column := UiHelpers.add_center_column(self)
	column.add_child(UiHelpers.make_label("GOLF GAME", 110))
	column.add_child(UiHelpers.make_button("PLAY", _on_play_pressed))


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(MODE_SELECT_SCENE)
