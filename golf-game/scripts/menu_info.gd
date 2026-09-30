class_name MenuInfo
extends RefCounted
## What the main menu's two info chips say. It lives apart from the menu so it only
## depends on the save data (progression + records), and can be tested on its own.

const YELLOW := "#ffd84a"


## e.g. "LV 3  ·  Driver Lv 2": the player's level and their highest-level club.
static func level_chip_text() -> String:
	var club := ProgressionSystem.top_club()
	return "LV [color=%s]%d[/color]  ·  %s [color=%s]Lv %d[/color]" % [
			YELLOW, ProgressionSystem.player_level(), club["name"], YELLOW, club["level"]]


## e.g. "Best 18: -4", or "Best 18: --" before an 18-hole round has been finished.
static func best_chip_text() -> String:
	var best := Records.best_round(18)
	var score := "--" if best.is_empty() else Records.format_vs_par(best["vs_par"])
	return "Best 18: [color=%s]%s[/color]" % [YELLOW, score]
