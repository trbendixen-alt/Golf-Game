extends Node
## RoundManager: remembers everything about the round in progress.
##
## This script is an "autoload" (see Project Settings > Globals > Autoload), which
## means Godot creates ONE copy of it when the game starts and keeps it alive while
## we switch between scenes (menu -> hole -> hole -> summary). Any script can reach
## it by its name: `RoundManager`.

const HOLES_FOLDER := "res://data/holes"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const HOLE_SCENE := "res://scenes/hole_scene.tscn"
const SUMMARY_SCENE := "res://scenes/round_summary.tscn"

## A hole is capped at par + this many strokes, then the player "picks up".
const STROKE_CAP_OVER_PAR := 5

## The holes to play this round, in order. Each entry is a Dictionary:
## { name, par, tee (Vector3), cup (Vector3), wind_min, wind_max (mph) }
var hole_order: Array[Dictionary] = []
## Which hole we're on (0 = first).
var current_index := 0
## Strokes taken so far on the current hole.
var strokes := 0
## Finished holes: an Array of { name, par, strokes }.
var results: Array[Dictionary] = []
## Shot grades this round, for the summary now and XP later (Milestone 5).
## tier_counts[ShotQuality.Tier.PERFECT] = number of Perfect shots, and so on.
var tier_counts: Array[int] = [0, 0, 0, 0]
var perfect_timing_shots := 0
var perfect_power_shots := 0


# ---------------------------------------------------------------------------
# Starting a round
# ---------------------------------------------------------------------------

## Called by the mode select screen. Sets up the round, then loads the first hole.
func start_round(hole_count: int) -> void:
	build_round(hole_count)
	get_tree().change_scene_to_file(HOLE_SCENE)


## Picks and shuffles the holes and resets the scores. (Doesn't change scene.)
func build_round(hole_count: int) -> void:
	var pool := _load_all_holes()
	hole_order.clear()
	# Random order with no repeats. With only a few placeholder holes we can run out,
	# so we shuffle the pool again to fill the round. This goes away once there are
	# 18 real holes.
	while hole_order.size() < hole_count:
		pool.shuffle()
		for hole in pool:
			if hole_order.size() < hole_count:
				hole_order.append(hole)
	current_index = 0
	strokes = 0
	results.clear()
	_reset_shot_stats()


func _reset_shot_stats() -> void:
	tier_counts = [0, 0, 0, 0]
	perfect_timing_shots = 0
	perfect_power_shots = 0


## Reads every .json file in data/holes/. Adding a hole = adding a file. No code changes.
func _load_all_holes() -> Array[Dictionary]:
	var holes: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(HOLES_FOLDER):
		if not file_name.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string(HOLES_FOLDER + "/" + file_name)
		var data = JSON.parse_string(text)
		if data == null:
			push_error("Could not read hole file: " + file_name)
			continue
		holes.append({
			"name": data["name"],
			"par": int(data["par"]),
			"tee": Vector3(data["tee"][0], data["tee"][1], data["tee"][2]),
			"cup": Vector3(data["cup"][0], data["cup"][1], data["cup"][2]),
			# Each hole picks a random wind speed between these two numbers.
			"wind_min": float(data.get("wind_mph", [0, 0])[0]),
			"wind_max": float(data.get("wind_mph", [0, 0])[1]),
		})
	return holes


# ---------------------------------------------------------------------------
# During a hole
# ---------------------------------------------------------------------------

## The hole currently being played. If a hole scene is run on its own (F6 in the
## editor) no round exists yet, so we quickly make a 3-hole one.
func current_hole() -> Dictionary:
	if hole_order.is_empty():
		build_round(3)
	return hole_order[current_index]


func hole_count() -> int:
	return hole_order.size()


## Call once per shot.
func add_stroke() -> void:
	strokes += 1


## Remember how good a shot was. `quality` comes from ShotQuality.rate().
func record_shot(quality: Dictionary) -> void:
	tier_counts[quality["tier"]] += 1
	if quality["perfect_timing"]:
		perfect_timing_shots += 1
	if quality["perfect_power"]:
		perfect_power_shots += 1


## The most strokes allowed on the current hole.
func stroke_cap() -> int:
	return current_hole()["par"] + STROKE_CAP_OVER_PAR


func is_at_stroke_cap() -> bool:
	return strokes >= stroke_cap()


## Save the finished hole's score. The player's strokes are recorded as-is; when they
## pick up, they've hit the cap so the score is par + 5.
func record_hole() -> void:
	var hole := current_hole()
	results.append({"name": hole["name"], "par": hole["par"], "strokes": strokes})


## Quit Round from the pause menu: forget the round and go back to the main menu.
## (An abandoned round earns nothing and isn't recorded.)
func abandon_round() -> void:
	hole_order.clear()
	results.clear()
	current_index = 0
	strokes = 0
	_reset_shot_stats()
	get_tree().change_scene_to_file(MENU_SCENE)


## Move on: load the next hole, or the summary screen after the last hole.
func next_hole() -> void:
	current_index += 1
	strokes = 0
	if current_index >= hole_order.size():
		get_tree().change_scene_to_file(SUMMARY_SCENE)
	else:
		get_tree().change_scene_to_file(HOLE_SCENE)


# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------

## Score of the finished holes compared to par (negative = under par).
func round_vs_par() -> int:
	return total_strokes() - total_par()


func total_strokes() -> int:
	var total := 0
	for result in results:
		total += result["strokes"]
	return total


func total_par() -> int:
	var total := 0
	for result in results:
		total += result["par"]
	return total


## The golf word for a hole score, e.g. 3 strokes on a par 4 = "Birdie".
func score_term(hole_strokes: int, par: int) -> String:
	var difference := hole_strokes - par
	if hole_strokes == 1:
		return "Ace"
	elif difference <= -2:
		return "Eagle"
	elif difference == -1:
		return "Birdie"
	elif difference == 0:
		return "Par"
	elif difference == 1:
		return "Bogey"
	else:
		return "Double Bogey+"


## Formats a score vs par: 0 -> "E" (even), 2 -> "+2", -1 -> "-1".
func format_vs_par(difference: int) -> String:
	if difference == 0:
		return "E"
	elif difference > 0:
		return "+%d" % difference
	return "%d" % difference
