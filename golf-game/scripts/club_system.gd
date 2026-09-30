class_name ClubSystem
extends RefCounted
## Loads the clubs from data/clubs.json and answers "how hard should I hit it?".
##
## The data file gives each club a max_distance in metres (easy to tweak). We turn
## that into a launch speed by running practice shots through the real BallPhysics
## code, so what the file says is what you actually get in game.
##
## Clubs have levels (1 to max_level). The file lists level 1 and top-level stats;
## levels in between are spread evenly. The player's levels live in SaveSystem.

const CLUBS_FILE := "res://data/clubs.json"
const SIM_STEP := 1.0 / 60.0
const SIM_MAX_STEPS := 60 * 30  # Give up on a practice shot after 30 seconds.

# The raw entries from clubs.json, loaded once.
static var _entries: Array = []
static var _max_level := 10
# Clubs already worked out, by "name:level". Each club is a Dictionary:
# { name, level, max_level, two_tap, max_distance, launch_angle, roll_decel,
#   sweet_spot, backspin, recovery, max_speed }
static var _built: Dictionary = {}


## Every club, at the level the player has upgraded it to.
static func get_clubs() -> Array[Dictionary]:
	var clubs: Array[Dictionary] = []
	for entry in _club_entries():
		clubs.append(get_club(entry["name"], SaveSystem.club_level(entry["name"])))
	return clubs


static func club_names() -> Array[String]:
	var names: Array[String] = []
	for entry in _club_entries():
		names.append(entry["name"])
	return names


static func max_level() -> int:
	_club_entries()
	return _max_level


## One club's stats at a given level.
static func get_club(club_name: String, level: int) -> Dictionary:
	level = clampi(level, 1, max_level())
	var key := "%s:%d" % [club_name, level]
	if not _built.has(key):
		_built[key] = _build_club(club_name, level)
	return _built[key]


static func _club_entries() -> Array:
	if _entries.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(CLUBS_FILE))
		_max_level = int(data.get("max_level", 10))
		_entries = data["clubs"]
	return _entries


static func _build_club(club_name: String, level: int) -> Dictionary:
	var entry: Dictionary = {}
	for candidate in _club_entries():
		if candidate["name"] == club_name:
			entry = candidate
	var first: Dictionary = entry["level_1"]
	var top: Dictionary = entry.get("level_%d" % _max_level, {})
	# 0 at level 1, 1 at the top level.
	var progress := float(level - 1) / float(maxi(_max_level - 1, 1))
	var club := {
		"name": club_name,
		"level": level,
		"max_level": _max_level,
		"two_tap": bool(entry.get("two_tap", false)),
	}
	for stat in first:
		club[stat] = lerpf(float(first[stat]), float(top.get(stat, first[stat])), progress)
	club["max_speed"] = _find_speed_for_distance(club)
	return club


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


## The club as it plays from this lie (the surface the ball sits on). Rough, mud and
## potholes cut power and shrink the sweet spot; the club's "recovery" (0..1) cancels
## that much of the penalty, so a wedge (recovery 1) plays out of a pothole cleanly.
static func adjust_for_lie(club: Dictionary, lie: Dictionary) -> Dictionary:
	var keep: float = 1.0 - club["recovery"]
	var power_factor: float = 1.0 - (1.0 - lie["lie_power"]) * keep
	var sweet_factor: float = 1.0 - (1.0 - lie["lie_sweet_spot"]) * keep
	if power_factor == 1.0 and sweet_factor == 1.0:
		return club
	var adjusted := club.duplicate()
	adjusted["max_speed"] = club["max_speed"] * power_factor
	adjusted["sweet_spot"] = club["sweet_spot"] * sweet_factor
	adjusted["max_distance"] = simulate_distance(adjusted["max_speed"], adjusted)
	return adjusted


## How power (0..1) should be set to hit the ball `distance` metres with this club.
## With `surfaces`, the practice shots roll over the hole's real ground from `start`
## along `direction` (hazards count as fairway, so they don't confuse the maths).
## Returns exactly 1.0 if even full power falls short.
static func suggest_power(club: Dictionary, distance: float, start := Vector3.ZERO,
		direction := Vector3(0, 0, -1), surfaces: SurfaceMap = null) -> float:
	if simulate_distance(club["max_speed"], club, start, direction, surfaces) < distance:
		return 1.0
	# 8 rounds of halving pins the power down to within 0.4%.
	var low := 0.0
	var high := 1.0
	for i in 8:
		var middle := (low + high) / 2.0
		if simulate_distance(club["max_speed"] * middle, club, start, direction, surfaces) < distance:
			low = middle
		else:
			high = middle
	return (low + high) / 2.0


## Hit a practice ball (no wind, dead straight) and measure how far it travels in
## total, including bounces and roll. Without `surfaces` it's all fairway.
static func simulate_distance(speed: float, club: Dictionary, start := Vector3.ZERO,
		direction := Vector3(0, 0, -1), surfaces: SurfaceMap = null) -> float:
	var path := simulate_path(start, direction, speed, club, surfaces, false)
	var end := path[path.size() - 1]
	return Vector2(end.x - start.x, end.z - start.z).length()


## Hit a practice ball from `start` along the flat `direction` (no wind, no sidespin)
## and return every position it passes through, one per physics tick, until it stops.
## Used for the distance calculations above and for the dotted aim arc (which, with
## `hazards` on, stops where the ball would splash down or go out of bounds).
static func simulate_path(start: Vector3, direction: Vector3, speed: float,
		club: Dictionary, surfaces: SurfaceMap = null, hazards := true) -> PackedVector3Array:
	var practice_ball := BallPhysics.new()
	practice_ball.cup_position = Vector3(1000000, 0, 1000000)  # Far away so it can't "hole out".
	practice_ball.roll_decel = club["roll_decel"]
	practice_ball.backspin = club["backspin"]
	practice_ball.surfaces = surfaces
	practice_ball.hazards_enabled = hazards
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
