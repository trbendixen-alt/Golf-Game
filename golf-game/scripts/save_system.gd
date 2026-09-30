class_name SaveSystem
extends RefCounted
## Everything the game remembers between launches, in one JSON file on the phone:
## XP, club levels, settings and the history of every finished round.
##
## The file carries a version number. When a later update changes the layout, bump
## SAVE_VERSION and add a step to _migrate() so old saves keep working.
##
## Saving writes to a temporary file first and then swaps it in, so a crash or a
## dead battery halfway through can't leave a half-written save behind.

const SAVE_VERSION := 2  # 2 = added the "rounds" history (Milestone 6).
const OLD_SETTINGS_PATH := "user://settings.json"  # Where settings lived before this file.

## Tests point this somewhere else so they never touch the player's real save.
static var save_path := "user://save.json"

static var _data: Dictionary = {}


## A brand-new player's save.
static func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"xp": 0,             # Unspent XP.
		"lifetime_xp": 0,    # Every XP ever earned (never goes down).
		"club_levels": {},   # Club name -> level. Missing = level 1.
		"settings": {"sound_on": true, "haptics_on": true},
		"rounds": [],        # One record per finished round. See Records.make_record().
	}


## The save data, loading it from disk the first time it's needed.
static func data() -> Dictionary:
	if _data.is_empty():
		load_game()
	return _data


static func load_game() -> void:
	var path := save_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		path += ".tmp"  # A save was cut off right before the swap; the new copy is complete.
	if not FileAccess.file_exists(path):
		_import_save_from_old_title_folder()
		path = save_path
	if not FileAccess.file_exists(path):
		_data = defaults()
		_import_old_settings()
		return
	var loaded = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not loaded is Dictionary:
		# Keep the broken file for debugging, and start fresh rather than crash.
		push_error("Save file is unreadable; starting a new one. Old copy kept as .bad")
		DirAccess.copy_absolute(path, save_path + ".bad")
		_data = defaults()
		return
	_data = _migrate(loaded)


static func save_game() -> void:
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data(), "\t"))
	file.close()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	DirAccess.rename_absolute(temp_path, save_path)


## Forget everything in memory and start from a new player's save (not written to
## disk until save_game()). Used by tests.
static func reset() -> void:
	_data = defaults()


## Bring an older save up to date. Anything missing gets its default value.
static func _migrate(loaded: Dictionary) -> Dictionary:
	var result := defaults()
	for key in loaded:
		result[key] = loaded[key]
	# JSON has no integers, so whole numbers come back as floats. Put them right.
	result["xp"] = int(result["xp"])
	result["lifetime_xp"] = int(result["lifetime_xp"])
	for club_name in result["club_levels"]:
		result["club_levels"][club_name] = int(result["club_levels"][club_name])
	_fix_round_numbers(result["rounds"])
	# Version 1 saves had no "rounds" list; the defaults above already gave them an
	# empty one, so nothing else is needed. Future layout changes go here, e.g.:
	#   if int(loaded.get("version", 0)) < 3: ...move things around...
	result["version"] = SAVE_VERSION
	return result


## JSON turns whole numbers into floats, so put the round history's numbers right.
static func _fix_round_numbers(rounds: Array) -> void:
	for round_record in rounds:
		for key in ["mode", "total_strokes", "total_par", "vs_par", "putts", "xp", "perfect_shots"]:
			round_record[key] = int(round_record.get(key, 0))
		round_record["longest_drive"] = float(round_record.get("longest_drive", 0.0))
		for hole in round_record.get("holes", []):
			for key in ["par", "strokes", "putts"]:
				hole[key] = int(hole.get(key, 0))


## Wipe EVERYTHING (XP, club levels, settings, round history) and save the empty
## file. This is the debug "reset saved data" option, for testing first-time behaviour.
static func reset_all() -> void:
	_data = defaults()
	save_game()
	GameSettings.load_settings()  # Put the in-memory settings back to their defaults too.


## The game used to be called "Golf Game", and Godot keeps saves in a folder named after the
## game. After the rename to "Street Golf" that folder is new and empty, so the first launch
## copies an existing save across (desktop testing only; phones never had the old folder).
## This can be deleted once nobody has a save from before the rename.
static func _import_save_from_old_title_folder() -> void:
	if save_path != "user://save.json":
		return  # Tests use their own save path.
	var old_save := OS.get_user_data_dir().get_base_dir().path_join("Golf Game").path_join("save.json")
	if FileAccess.file_exists(old_save):
		DirAccess.copy_absolute(old_save, ProjectSettings.globalize_path(save_path))


## Settings used to have their own file. Bring them across once.
static func _import_old_settings() -> void:
	if not FileAccess.file_exists(OLD_SETTINGS_PATH) or save_path != "user://save.json":
		return
	var old = JSON.parse_string(FileAccess.get_file_as_string(OLD_SETTINGS_PATH))
	if old is Dictionary:
		for key in ["sound_on", "haptics_on"]:
			if old.has(key):
				_data["settings"][key] = bool(old[key])


# ---------------------------------------------------------------------------
# Small helpers so other scripts don't poke at the dictionary directly
# ---------------------------------------------------------------------------

static func xp() -> int:
	return data()["xp"]


static func add_xp(amount: int) -> void:
	data()["xp"] += amount
	data()["lifetime_xp"] += amount


## Take XP away if there's enough. Returns false (and changes nothing) if not.
static func spend_xp(amount: int) -> bool:
	if xp() < amount:
		return false
	data()["xp"] -= amount
	return true


static func club_level(club_name: String) -> int:
	return data()["club_levels"].get(club_name, 1)


static func set_club_level(club_name: String, level: int) -> void:
	data()["club_levels"][club_name] = level


static func setting(key: String, default_value: Variant) -> Variant:
	return data()["settings"].get(key, default_value)


static func set_setting(key: String, value: Variant) -> void:
	data()["settings"][key] = value
