extends SceneTree
## Unit tests. No plugin needed; run from the golf-game folder with:
##
##   godot --headless -s res://tests/run_tests.gd
##
## Every function starting with "test_" runs. The exit code is 1 if anything failed,
## so this can run in CI later.

const RoundManagerScript := preload("res://scripts/round_manager.gd")

var _failures := 0
var _checks := 0


func _initialize() -> void:
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			var failures_before := _failures
			call(method_name)
			print("%s %s" % ["PASS" if _failures == failures_before else "FAIL", method_name])
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("    - " + message)


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

func test_score_terms() -> void:
	var rounds := RoundManagerScript.new()
	check(rounds.score_term(1, 3) == "Ace", "hole in one is an Ace")
	check(rounds.score_term(1, 4) == "Ace", "Ace beats Eagle/Albatross on a par 4")
	check(rounds.score_term(3, 5) == "Eagle", "-2 is Eagle")
	check(rounds.score_term(2, 5) == "Eagle", "-3 still shows as Eagle")
	check(rounds.score_term(3, 4) == "Birdie", "-1 is Birdie")
	check(rounds.score_term(4, 4) == "Par", "0 is Par")
	check(rounds.score_term(5, 4) == "Bogey", "+1 is Bogey")
	check(rounds.score_term(9, 4) == "Double Bogey+", "+5 is Double Bogey+")
	rounds.free()


func test_format_vs_par() -> void:
	var rounds := RoundManagerScript.new()
	check(rounds.format_vs_par(0) == "E", "even")
	check(rounds.format_vs_par(3) == "+3", "over par")
	check(rounds.format_vs_par(-2) == "-2", "under par")
	rounds.free()


func test_round_totals_and_stroke_cap() -> void:
	var rounds := RoundManagerScript.new()
	rounds.build_round(3)
	check(rounds.hole_count() == 3, "3-hole round has 3 holes")
	var par: int = rounds.current_hole()["par"]
	check(rounds.stroke_cap() == par + 5, "stroke cap is par + 5")
	for i in par + 5:
		rounds.add_stroke()
	check(rounds.is_at_stroke_cap(), "at cap after par + 5 strokes")
	rounds.record_hole()
	check(rounds.total_strokes() == par + 5, "total strokes recorded")
	check(rounds.round_vs_par() == 5, "round is +5")
	rounds.free()


func test_round_has_no_repeats_when_pool_allows() -> void:
	var rounds := RoundManagerScript.new()
	var pool_size := DirAccess.get_files_at(RoundManagerScript.HOLES_FOLDER).size()
	var count := mini(pool_size, 9)
	for attempt in 20:
		rounds.build_round(count)
		var names := {}
		for hole in rounds.hole_order:
			names[hole["name"]] = true
		check(names.size() == count, "no repeated holes in a %d-hole round" % count)
	rounds.free()


func test_shot_stats_reset_each_round() -> void:
	var rounds := RoundManagerScript.new()
	rounds.build_round(3)
	rounds.record_shot({"tier": ShotQuality.Tier.PERFECT, "perfect_timing": true, "perfect_power": true})
	check(rounds.tier_counts[ShotQuality.Tier.PERFECT] == 1, "perfect shot counted")
	rounds.build_round(3)
	check(rounds.tier_counts[ShotQuality.Tier.PERFECT] == 0, "new round starts at zero")
	check(rounds.perfect_timing_shots == 0, "perfect timing reset")
	rounds.free()


# ---------------------------------------------------------------------------
# Shot quality
# ---------------------------------------------------------------------------

func test_shot_quality_tiers() -> void:
	var sweet := 0.1
	check(ShotQuality.rate(0.5, 0.0, 0.5, sweet)["tier"] == ShotQuality.Tier.PERFECT,
			"dead centre, exact power = Perfect")
	check(ShotQuality.rate(0.5, 0.08, 0.5, sweet)["tier"] == ShotQuality.Tier.GOOD,
			"inside green zone = Good")
	check(ShotQuality.rate(0.5, 0.2, 0.5, sweet)["tier"] == ShotQuality.Tier.AVERAGE,
			"just outside green zone = Average")
	check(ShotQuality.rate(0.5, 0.9, 0.5, sweet)["tier"] == ShotQuality.Tier.POOR,
			"far edge = Poor")
	check(ShotQuality.rate(0.9, 0.0, 0.5, sweet)["tier"] == ShotQuality.Tier.POOR,
			"perfect timing can't rescue way-off power")
	var result := ShotQuality.rate(0.62, 0.01, 0.5, sweet)
	check(result["perfect_timing"] and not result["perfect_power"], "timing and power tracked separately")


func test_wider_sweet_spot_is_more_forgiving() -> void:
	var tap := 0.12
	check(ShotQuality.rate(0.5, tap, 0.5, 0.1)["tier"] == ShotQuality.Tier.AVERAGE, "narrow club: Average")
	check(ShotQuality.rate(0.5, tap, 0.5, 0.15)["tier"] == ShotQuality.Tier.GOOD, "wider club: Good")


func test_putts_grade_power_only() -> void:
	var result := ShotQuality.rate(0.5, 0.9, 0.5, 0.1, false)
	check(result["tier"] == ShotQuality.Tier.PERFECT, "accuracy ignored on a putt")
	check(not result["perfect_timing"], "putts never count as perfect timing")


func test_two_tap_swing_fires_on_second_tap() -> void:
	var shot := ShotController.new()
	shot.two_tap = true
	var fired := []
	shot.shot_fired.connect(func(power: float, accuracy: float) -> void: fired.append(accuracy))
	shot.tap()
	shot.tap()
	check(fired == [0.0], "two-tap fires dead straight on tap 2")
	check(shot.state == ShotController.State.LOCKED, "locked after firing")
	shot.free()


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------

func _hit(club: Dictionary, power: float, sidespin: float) -> Vector3:
	var ball := BallPhysics.new()
	ball.cup_position = Vector3(1000000, 0, 1000000)
	ball.roll_decel = club["roll_decel"]
	ball.backspin = club["backspin"]
	ball.sidespin = sidespin
	ball.place_at(Vector3.ZERO)
	ball.launch(ClubSystem.launch_velocity(club, Vector3(0, 0, -1), club["max_speed"] * power))
	var steps := 0
	while ball.is_moving and steps < 60 * 30:
		ball.step(1.0 / 60.0)
		steps += 1
	var end := ball.position
	ball.free()
	return end


func test_physics_is_deterministic() -> void:
	var driver: Dictionary = ClubSystem.get_clubs()[0]
	var first := _hit(driver, 0.83, 0.37)
	var second := _hit(driver, 0.83, 0.37)
	check(first == second, "same shot lands in exactly the same spot (%s vs %s)" % [first, second])


func test_clubs_reach_their_max_distance() -> void:
	for club in ClubSystem.get_clubs():
		var travelled := ClubSystem.simulate_distance(club["max_speed"], club)
		check(absf(travelled - club["max_distance"]) < 0.5,
				"%s travels %.1f m, expected %d" % [club["name"], travelled, club["max_distance"]])


func test_suggested_power_hits_the_target() -> void:
	var irons: Dictionary = ClubSystem.get_clubs()[1]
	var power := ClubSystem.suggest_power(irons, 60.0)
	var travelled := ClubSystem.simulate_distance(irons["max_speed"] * power, irons)
	check(absf(travelled - 60.0) < 0.5, "suggested power sends the ball 60 m (got %.1f)" % travelled)


func test_sidespin_curves_the_right_way() -> void:
	var driver: Dictionary = ClubSystem.get_clubs()[0]
	check(_hit(driver, 1.0, 1.0).x > 1.0, "positive sidespin slices right (+X)")
	check(_hit(driver, 1.0, -1.0).x < -1.0, "negative sidespin hooks left (-X)")
	check(absf(_hit(driver, 1.0, 0.0).x) < 0.001, "no sidespin flies straight")


func test_backspin_stops_the_ball_sooner() -> void:
	var wedge: Dictionary = ClubSystem.get_clubs()[2].duplicate()
	var with_spin := _hit(wedge, 0.8, 0.0)
	wedge["backspin"] = 0.0
	var without_spin := _hit(wedge, 0.8, 0.0)
	check(with_spin.length() < without_spin.length(), "backspin shortens the roll")


# ---------------------------------------------------------------------------
# Surfaces and hazards (Milestone 4)
# ---------------------------------------------------------------------------

## A test course: fairway strip down -Z, a green on top of it, a pond off to the
## right, and a 60 x 200 boundary.
func _test_surfaces() -> SurfaceMap:
	return SurfaceMap.new([
		{"type": "fairway", "rect": [0, -50], "size": [10, 100]},
		{"type": "green", "circle": [0, -100], "radius": 6},
		{"type": "water", "rect": [20, -50], "size": [10, 100]},
	], {"rect": [0, -50], "size": [60, 200]})


func test_surface_lookup() -> void:
	var map := _test_surfaces()
	check(map.type_at(0, -50) == "fairway", "middle of the fairway")
	check(map.type_at(0, -98) == "green", "green is drawn on top of the fairway")
	check(map.type_at(-10, -50) == "rough", "anywhere uncovered is rough")
	check(map.type_at(20, -50) == "water", "in the pond")
	check(map.type_at(40, -50) == "oob", "outside the boundary")
	var no_bounds := SurfaceMap.new([], null, "fairway")
	check(no_bounds.type_at(500, 500) == "fairway", "no bounds: the hole's own ground everywhere")


func test_rect_angle_turns_clockwise() -> void:
	# A long thin rect turned 90 degrees clockwise (seen from above, -Z up) lies along X.
	var map := SurfaceMap.new([{"type": "mud", "rect": [0, 0], "size": [2, 20], "angle": 90}])
	check(map.type_at(8, 0) == "mud", "turned rect reaches along X")
	check(map.type_at(0, -8) != "mud", "and no longer along Z")


## Hit a ball from `start` straight down -Z over `map`. Returns [end position, hazard kind, drop].
func _hit_on(map: SurfaceMap, start: Vector3, direction: Vector3, club: Dictionary,
		power: float) -> Array:
	var ball := BallPhysics.new()
	ball.cup_position = Vector3(1000000, 0, 1000000)
	ball.roll_decel = club["roll_decel"]
	ball.surfaces = map
	ball.place_at(start)
	var hazard := ["", Vector3.ZERO]
	ball.hazard.connect(func(kind: String, drop: Vector3) -> void: hazard[0] = kind; hazard[1] = drop)
	ball.launch(ClubSystem.launch_velocity(club, direction, club["max_speed"] * power))
	var steps := 0
	while ball.is_moving and steps < 60 * 30:
		ball.step(1.0 / 60.0)
		steps += 1
	var end := ball.position
	ball.free()
	return [end, hazard[0], hazard[1]]


func test_rough_stops_the_ball_sooner() -> void:
	var putter: Dictionary = ClubSystem.get_clubs()[3]
	var on_fairway: Vector3 = _hit_on(SurfaceMap.new([], null, "fairway"), Vector3.ZERO,
			Vector3(0, 0, -1), putter, 0.6)[0]
	var in_rough: Vector3 = _hit_on(SurfaceMap.new([], null, "rough"), Vector3.ZERO,
			Vector3(0, 0, -1), putter, 0.6)[0]
	check(in_rough.length() < on_fairway.length() * 0.7,
			"rough roll %.1f m vs fairway %.1f m" % [in_rough.length(), on_fairway.length()])


func test_water_drops_near_where_it_went_in() -> void:
	var map := _test_surfaces()
	var putter: Dictionary = ClubSystem.get_clubs()[3]
	# Putt from the fairway straight right into the pond (its edge is at x = 15).
	var result := _hit_on(map, Vector3(8, 0, -50), Vector3.RIGHT, putter, 1.0)
	check(result[1] == "water", "ball went in the water")
	var drop: Vector3 = result[2]
	check(map.type_at(drop.x, drop.z) != "water", "drop is on dry land")
	check(drop.x > 12.0 and drop.x < 15.0, "drop is just short of the edge (x = %.2f)" % drop.x)


func test_out_of_bounds_is_reported() -> void:
	var driver: Dictionary = ClubSystem.get_clubs()[0]
	var result := _hit_on(_test_surfaces(), Vector3(0, 0, -50), Vector3.LEFT, driver, 1.0)
	check(result[1] == "oob", "ball flew out of bounds")


func test_hazards_can_be_ignored_for_practice_shots() -> void:
	var map := _test_surfaces()
	var putter: Dictionary = ClubSystem.get_clubs()[3]
	var path := ClubSystem.simulate_path(Vector3(8, 0, -50), Vector3.RIGHT,
			putter["max_speed"], putter, map, false)
	check(path[path.size() - 1].x > 15.0, "practice ball rolls on through the pond")


func test_bad_lies_cost_power_unless_using_a_wedge() -> void:
	var clubs := ClubSystem.get_clubs()
	var pothole := SurfaceMap.get_type("pothole")
	var driver := ClubSystem.adjust_for_lie(clubs[0], pothole)
	check(driver["max_speed"] < clubs[0]["max_speed"], "driver loses power in a pothole")
	check(driver["sweet_spot"] < clubs[0]["sweet_spot"], "driver's sweet spot shrinks")
	check(driver["max_distance"] < clubs[0]["max_distance"], "driver's max distance drops")
	var wedge := ClubSystem.adjust_for_lie(clubs[2], pothole)
	check(wedge["max_speed"] == clubs[2]["max_speed"], "wedge plays out of a pothole cleanly")
	var fairway := ClubSystem.adjust_for_lie(clubs[0], SurfaceMap.get_type("fairway"))
	check(fairway == clubs[0], "fairway lie changes nothing")


func test_suggest_power_says_full_when_out_of_reach() -> void:
	var wedge: Dictionary = ClubSystem.get_clubs()[2]
	check(ClubSystem.suggest_power(wedge, 500.0) == 1.0, "500 m is out of wedge range")


func test_penalty_cant_push_score_past_the_cap() -> void:
	var rounds := RoundManagerScript.new()
	rounds.build_round(1)
	for i in rounds.stroke_cap() + 1:  # Last shot in the water: one over the cap.
		rounds.add_stroke()
	rounds.record_hole()
	check(rounds.results[0]["strokes"] == rounds.stroke_cap(), "score capped at par + 5")
	rounds.free()


func test_hole_files_are_playable() -> void:
	var rounds := RoundManagerScript.new()
	for hole in rounds._load_all_holes():
		var map := SurfaceMap.new(hole["surfaces"], hole["bounds"], hole["ground"],
				hole["obstacles"])
		var tee: Vector3 = hole["tee"]
		var cup: Vector3 = hole["cup"]
		check(map.surface_at(tee)["penalty"] == "", "%s: tee is playable" % hole["name"])
		check(map.type_at(cup.x, cup.z) == "green", "%s: cup is on the green" % hole["name"])
		check(not map.obstacles.covers(tee.x, tee.z), "%s: nothing parked on the tee" % hole["name"])
		check(not map.obstacles.covers(cup.x, cup.z), "%s: nothing parked on the cup" % hole["name"])
	rounds.free()


# ---------------------------------------------------------------------------
# Solid obstacles
# ---------------------------------------------------------------------------

## A ball moving with `velocity` from `start` over `map` until it stops (or 30 s pass).
## Returns the BallPhysics node; free it when done.
func _roll_ball(map: SurfaceMap, start: Vector3, velocity: Vector3) -> BallPhysics:
	var ball := BallPhysics.new()
	ball.cup_position = Vector3(1000000, 0, 1000000)
	ball.surfaces = map
	ball.place_at(start)
	ball.launch(velocity)
	var steps := 0
	while ball.is_moving and steps < 60 * 30:
		ball.step(1.0 / 60.0)
		steps += 1
	return ball


func test_ball_bounces_back_off_a_wall() -> void:
	var map := SurfaceMap.new([], null, "fairway",
			[{"type": "wall", "at": [0, -10], "size": [6, 0.4, 2], "angle": 0}])
	var ball := _roll_ball(map, Vector3.ZERO, Vector3(0, 0, -12))
	check(ball.position.z > -9.5, "ball stays on the near side of the wall (z = %.2f)" % ball.position.z)
	ball.free()


func test_fast_ball_cant_tunnel_through_a_thin_fence() -> void:
	var map := SurfaceMap.new([], null, "fairway",
			[{"type": "fence", "at": [0, -5], "size": [6, 0.15, 3], "angle": 0}])
	# 45 m/s moves 0.75 m per tick, far more than the fence is thick.
	var ball := _roll_ball(map, Vector3.ZERO, Vector3(0, 1, -45))
	check(ball.position.z > -5.0, "ball didn't pass through the fence (z = %.2f)" % ball.position.z)
	ball.free()


func test_angled_wall_deflects_sideways() -> void:
	# A wall turned 45 degrees across the ball's path should knock it off to the side.
	var map := SurfaceMap.new([], null, "fairway",
			[{"type": "wall", "at": [0, -8], "size": [0.4, 8, 2], "angle": 45}])
	var ball := _roll_ball(map, Vector3.ZERO, Vector3(0, 0, -10))
	check(absf(ball.position.x) > 2.0, "ball deflected sideways (x = %.2f)" % ball.position.x)
	ball.free()


func test_hay_bale_is_softer_than_a_wall() -> void:
	var wall := SurfaceMap.new([], null, "fairway", [{"type": "wall", "at": [0, -6], "size": [4, 0.4, 2]}])
	var bale := SurfaceMap.new([], null, "fairway", [{"type": "hay_bale", "at": [0, -6.6]}])
	var off_wall := _roll_ball(wall, Vector3.ZERO, Vector3(0, 0, -12))
	var off_bale := _roll_ball(bale, Vector3.ZERO, Vector3(0, 0, -12))
	check(off_bale.position.z < off_wall.position.z,
			"bale bounce (%.1f) shorter than wall bounce (%.1f)" % [off_bale.position.z, off_wall.position.z])
	off_wall.free()
	off_bale.free()


func test_ball_can_sit_on_a_roof_and_roll_off() -> void:
	var map := SurfaceMap.new([], null, "fairway",
			[{"type": "building", "at": [0, 0], "size": [10, 10, 5]}])
	var ball := BallPhysics.new()
	ball.surfaces = map
	ball.place_at(Vector3(0, 0, 0))
	check(is_equal_approx(ball.position.y, 5.0 + BallPhysics.BALL_RADIUS), "placed on the roof")
	check(map.support_at(ball.position)["surface"]["label"] == "Rooftop", "lie is the rooftop")
	ball.free()
	var rolled := _roll_ball(map, Vector3(0, 0, 0), Vector3(0, 0, -12))
	check(rolled.position.z < -5.0, "rolled off the edge (z = %.2f)" % rolled.position.z)
	check(is_equal_approx(rolled.position.y, BallPhysics.BALL_RADIUS), "and fell to the ground")
	rolled.free()


func test_ball_lands_on_a_car_roof() -> void:
	var map := SurfaceMap.new([], null, "fairway", [{"type": "car", "at": [0, 0]}])
	var ball := _roll_ball(map, Vector3(0, 0, 10), Vector3(0, 0, 0))  # Just to make one.
	ball.position = Vector3(0, 6, 0)
	ball.launch(Vector3(0, -3, 0))  # Dropped straight onto the cabin.
	var steps := 0
	while ball.is_moving and steps < 600:
		ball.step(1.0 / 60.0)
		steps += 1
	check(ball.position.y > 1.4, "ball rests on the roof (y = %.2f)" % ball.position.y)
	ball.free()


func test_obstacle_physics_is_deterministic() -> void:
	var map := SurfaceMap.new([], null, "fairway", [
		{"type": "car", "at": [1, -12], "angle": 20},
		{"type": "cone", "at": [-1, -8]},
		{"type": "hay_bale", "at": [0.5, -20]},
	])
	var first := _roll_ball(map, Vector3.ZERO, Vector3(0.7, 6, -22))
	var second := _roll_ball(map, Vector3.ZERO, Vector3(0.7, 6, -22))
	check(first.position == second.position, "same shot through obstacles ends in the same spot")
	first.free()
	second.free()


func test_practice_balls_ignore_obstacles() -> void:
	var map := SurfaceMap.new([], null, "fairway",
			[{"type": "wall", "at": [0, -5], "size": [6, 0.4, 3]}])
	var putter: Dictionary = ClubSystem.get_clubs()[3]
	var path := ClubSystem.simulate_path(Vector3.ZERO, Vector3(0, 0, -1), putter["max_speed"],
			putter, map, false)
	check(path[path.size() - 1].z < -10.0, "suggested-power maths rolls through the wall")
