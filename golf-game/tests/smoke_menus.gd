extends SceneTree
## Smoke test for the menu screens. They use the RoundManager autoload, which only exists
## once the game has started, so this runs separately from run_tests.gd:
##   godot --path . --script res://tests/smoke_menus.gd
## (Needs a window. Prints PASS/FAIL lines and exits 1 on failure.)

var failures := 0

func check(condition: bool, message: String) -> void:
	print("%s  %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame  # Autoloads exist from here on.
	SaveSystem.save_path = "user://smoke_test_save.json"  # Never touch the player's real save.
	SaveSystem.reset()
	for scene_path in ["res://scenes/main_menu.tscn", "res://scenes/settings.tscn"]:
		var screen: Control = load(scene_path).instantiate()
		root.add_child(screen)
		await process_frame
		var buttons := screen.find_children("*", "StreetButton", true, false)
		var texts := buttons.map(func(b: Button) -> String: return b.text)
		if scene_path.ends_with("main_menu.tscn"):
			check(texts.has("PLAY") and texts.has("STATS") and texts.has("SETTINGS"), "main menu has PLAY, STATS, SETTINGS")
			var labels := screen.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
			check(labels.has("STREET") and labels.has("LF") and labels.has("G"), "the title is STREET / G + ball + LF")
			check(labels.has("GOLF WHERE IT DOESN'T BELONG"), "the tagline is there")
			check(screen.find_children("*", "BallGlyph", true, false).size() == 1, "the O in GOLF is a golf ball")
			var chips := screen.find_children("*", "RichTextLabel", true, false).map(func(r: RichTextLabel) -> String: return r.get_parsed_text())
			check(chips.has("LV 1  ·  Driver Lv 1") and chips.has("Best 18: --"), "a new player sees LV 1 · Driver Lv 1 and Best 18: --")
		else:
			check(texts.size() == 3, "settings has Sound, Haptics and Back")
		screen.queue_free()
		await process_frame
	await _check_settings_switches_work_repeatedly()
	await _check_every_screen_has_the_backdrop_and_theme()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://smoke_test_save.json"))
	print("smoke test: %d failed" % failures)
	quit(1 if failures > 0 else 0)


## The bug this guards against: a Settings switch worked once, then never again.
func _check_settings_switches_work_repeatedly() -> void:
	var screen: Control = load("res://scenes/settings.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var sound: Button = null
	for button in screen.find_children("*", "StreetButton", true, false):
		if button.text.begins_with("SOUND"):
			sound = button
	var start_on := GameSettings.sound_on
	var expected := start_on
	var all_flipped := true
	for press in 5:
		sound.pressed.emit()
		expected = not expected
		if GameSettings.sound_on != expected or not sound.text.ends_with("ON" if expected else "OFF"):
			all_flipped = false
	check(all_flipped, "the Sound switch flips on EVERY press (5 in a row), not just the first")
	GameSettings.sound_on = start_on
	screen.queue_free()
	await process_frame


## Every menu screen sits on the animated Main Street backdrop and uses the shared theme.
func _check_every_screen_has_the_backdrop_and_theme() -> void:
	for scene_path in ["res://scenes/main_menu.tscn", "res://scenes/mode_select.tscn", "res://scenes/stats.tscn",
			"res://scenes/clubs.tscn", "res://scenes/settings.tscn", "res://scenes/round_summary.tscn"]:
		var screen: Control = load(scene_path).instantiate()
		root.add_child(screen)
		await process_frame
		check(screen.find_children("*", "MenuBackdrop", true, false).size() == 1, "%s has the backdrop" % scene_path.get_file())
		check(screen.theme != null, "%s uses the shared theme" % scene_path.get_file())
		if scene_path.ends_with("stats.tscn"):
			var kinds := screen.find_children("*", "ClubIcon", true, false).map(func(icon: ClubIcon) -> String: return icon.kind)
			check(kinds == ["Driver", "Irons", "Wedge", "Putter"], "Stats shows a picture of each club: %s" % str(kinds))
		screen.queue_free()
		await process_frame
