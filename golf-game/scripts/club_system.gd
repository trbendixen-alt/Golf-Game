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
# { name, level, two_tap, max_distance, launch_angle, roll_decel, sweet_spot, backspin, max_speed }
static var _clubs: Array[Dictionary] = []


static func get_clubs() -> Array[Dictionary]:
	if _clubs.is_empty():
		_load_clubs()
	return _clubs


static func _load_clubs() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(CLUBS_FILE))
	for entry in data["clubs"]:
		var stats: Dictionary = entry["level_1"]  # Only level 1 exists until progression (Milestone 5).
		var club := {
			"name": entry["name"],
			"level": 1,
			"two_tap": bool(entry.get("two_tap", false)),
			"max_distance": float(stats["max_distance"]),
			"launch_angle": float(stats["launch_angle"]),
			"roll_decel": float(stats["roll_decel"]),
			"sweet_spot": float(stats["sweet_spot"]),
			"backspin": float(stats["backspin"]),
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
	var path := simulate_path(Vector3.ZERO, Vector3(0, 0, -1), speed, club)
	var end := path[path.size() - 1]
	return Vector2(end.x, end.z).length()


## Hit a practice ball from `start` along the flat `direction` (no wind, no sidespin)
## and return every position it passes through, one per physics tick, until it stops.
## Used for the distance calculations above and for the dotted aim arc.
static func simulate_path(start: Vector3, direction: Vector3, speed: float,
		club: Dictionary) -> PackedVector3Array:
	var practice_ball := BallPhysics.new()
	practice_ball.cup_position = Vector3(1000000, 0, 1000000)  # Far away so it can't "hole out".
	practice_ball.roll_decel = club["roll_decel"]
	practice_ball.backspin = club["backspin"]
	practice_ball.place_at(start)
	practice_ball.launch(launch_velocity(club, direction, speed))
	var path := PackedVector3Array([practice_ball.position])
	var steps := 0
	while practice_ball.is_moving and steps < SIM_MAX_STEPS:
		practice_ball.step(SIM_STEP)
		path.append(practice_ball.position)
		steps += 1
	practice_ball.free()
	return path


## Turn a flat aim direction and a speed into a 3D launch velocity, tilted up by
## the club's launch angle.
static func launch_velocity(club: Dictionary, flat_direction: Vector3, speed: float) -> Vector3:
	var pitch := deg_to_rad(club["launch_angle"])
	return (flat_direction * cos(pitch) + Vector3.UP * sin(pitch)) * speed
