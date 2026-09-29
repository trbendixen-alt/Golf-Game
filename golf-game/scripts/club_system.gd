class_name ClubSystem
extends RefCounted
## Loads the clubs from data/clubs.json and answers "how hard should I hit it?".
##
## The data file gives each club a max_distance in metres (easy to tweak). We turn
## that into a launch speed by running practice shots through the real BallPhysics
## code, so what the file says is what you actually get in game.

const CLUBS_FILE := "res://data/clubs.json"
const SIM_STEP := 1.0 / 60.0
const SIM_MAX_STEPS := 60 * 30  # Give up on a practice shot after 30 seconds.

# Filled the first time it's needed, then reused. Each club is a Dictionary:
# { name, max_distance, launch_angle, roll_decel, max_speed }
static var _clubs: Array[Dictionary] = []


static func get_clubs() -> Array[Dictionary]:
	if _clubs.is_empty():
		_load_clubs()
	return _clubs


static func _load_clubs() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CLUBS_FILE))
	for entry in data["clubs"]:
		var stats: Dictionary = entry["level_1"]  # Only level 1 exists for now.
		var club := {
			"name": entry["name"],
			"max_distance": float(stats["max_distance"]),
			"launch_angle": float(stats["launch_angle"]),
			"roll_decel": float(stats["roll_decel"]),
		}
		club["max_speed"] = _find_speed_for_distance(club)
		_clubs.append(club)


## Launch speed (m/s) at which the club's practice shot travels exactly max_distance.
## Uses "bisection": guess a speed, see if it's too short or too long, narrow down.
static func _find_speed_for_distance(club: Dictionary) -> float:
	var low := 1.0
	var high := 80.0
	for i in 14:
		var middle := (low + high) / 2.0
		if simulate_distance(middle, club) < club["max_distance"]:
			low = middle
		else:
			high = middle
	return (low + high) / 2.0


## How power (0..1) should be set to hit the ball `distance` metres with this club.
## Returns 1.0 if the target is further than the club can reach.
static func suggest_power(club: Dictionary, distance: float) -> float:
	if distance >= club["max_distance"]:
		return 1.0
	var low := 0.0
	var high := 1.0
	for i in 12:
		var middle := (low + high) / 2.0
		if simulate_distance(club["max_speed"] * middle, club) < distance:
			low = middle
		else:
			high = middle
	return (low + high) / 2.0


## Hit a practice ball off-screen (no wind, dead straight) and measure how far it
## travels in total, including bounces and roll.
static func simulate_distance(speed: float, club: Dictionary) -> float:
	var practice_ball := BallPhysics.new()
	practice_ball.cup_position = Vector3(1000000, 0, 1000000)  # Far away so it can't "hole out".
	practice_ball.roll_decel = club["roll_decel"]
	practice_ball.place_at(Vector3.ZERO)
	var pitch := deg_to_rad(club["launch_angle"])
	practice_ball.launch(Vector3(0, sin(pitch), -cos(pitch)) * speed)
	var steps := 0
	while practice_ball.is_moving and steps < SIM_MAX_STEPS:
		practice_ball.step(SIM_STEP)
		steps += 1
	var distance := Vector2(practice_ball.position.x, practice_ball.position.z).length()
	practice_ball.free()
	return distance
