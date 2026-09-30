class_name GameSettings
extends RefCounted
## Player settings, saved to the phone so they survive restarts. Nothing listens to
## them yet (there's no audio or haptics until Milestone 8).
##
## The file has a version number from day one, so future updates can read old saves.
## When the SaveSystem arrives (Milestone 5) it can take this file over.

const SAVE_PATH := "user://settings.json"
const SAVE_VERSION := 1

static var sound_on := true
static var haptics_on := true


## Godot runs this once, the first time any script uses GameSettings.
static func _static_init() -> void:
	load_settings()


static func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return  # First launch: keep the defaults.
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		push_warning("Settings file is unreadable; using defaults.")
		return
	sound_on = bool(data.get("sound_on", sound_on))
	haptics_on = bool(data.get("haptics_on", haptics_on))


static func save_settings() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save settings: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"sound_on": sound_on,
		"haptics_on": haptics_on,
	}, "\t"))
