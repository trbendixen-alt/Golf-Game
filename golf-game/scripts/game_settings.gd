class_name GameSettings
extends RefCounted
## Player settings. They're stored in the SaveSystem's file so everything the game
## remembers lives in one place. Nothing listens to them yet (there's no audio or
## haptics until Milestone 8).

static var sound_on := true
static var haptics_on := true


## Godot runs this once, the first time any script uses GameSettings.
static func _static_init() -> void:
	load_settings()


static func load_settings() -> void:
	sound_on = bool(SaveSystem.setting("sound_on", true))
	haptics_on = bool(SaveSystem.setting("haptics_on", true))


static func save_settings() -> void:
	SaveSystem.set_setting("sound_on", sound_on)
	SaveSystem.set_setting("haptics_on", haptics_on)
	SaveSystem.save_game()
