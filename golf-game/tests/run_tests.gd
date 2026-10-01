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


const TEST_SAVE := "user://test_save.json"


func _initialize() -> void:
	# Never touch the player's real save: use a scratch file, starting fresh.
	SaveSystem.save_path = TEST_SAVE
	SaveSystem.reset()
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			var failures_before := _failures
			call(method_name)
			print("%s %s" % ["PASS" if _failures == failures_before else "FAIL", method_name])
	for leftover in [TEST_SAVE, TEST_SAVE + ".tmp", TEST_SAVE + ".bad"]:
		DirAccess.remove_absolute(leftover)
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


# ---------------------------------------------------------------------------
# Saving, XP and club upgrades (Milestone 5)
# ---------------------------------------------------------------------------

func test_save_round_trip() -> void:
	SaveSystem.reset()
	SaveSystem.add_xp(321)
	SaveSystem.set_club_level("Irons", 4)
	SaveSystem.set_setting("sound_on", false)
	SaveSystem.save_game()
	SaveSystem._data = {}  # Forget it, so the next read comes from disk.
	check(SaveSystem.xp() == 321, "XP survives a save and load")
	check(typeof(SaveSystem.xp()) == TYPE_INT, "XP loads back as a whole number")
	check(SaveSystem.club_level("Irons") == 4, "club level survives")
	check(SaveSystem.club_level("Driver") == 1, "unsaved clubs are level 1")
	check(SaveSystem.setting("sound_on", true) == false, "settings survive")
	SaveSystem.reset()


func test_old_save_is_upgraded() -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string('{"xp": 50}')  # No version, most keys missing.
	file.close()
	SaveSystem.load_game()
	check(SaveSystem.data()["version"] == SaveSystem.SAVE_VERSION, "version filled in")
	check(SaveSystem.xp() == 50, "old values kept")
	check(SaveSystem.data()["club_levels"] is Dictionary, "missing sections get defaults")
	SaveSystem.reset()


func test_broken_save_starts_fresh() -> void:
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	SaveSystem.load_game()
	check(SaveSystem.xp() == 0, "fresh save after a broken file")
	check(FileAccess.file_exists(TEST_SAVE + ".bad"), "broken file kept for debugging")
	SaveSystem.reset()


func test_club_levels_spread_between_one_and_ten() -> void:
	var first := ClubSystem.get_club("Driver", 1)
	var top := ClubSystem.get_club("Driver", 10)
	var middle := ClubSystem.get_club("Driver", 5)
	check(first["max_distance"] == 130.0 and top["max_distance"] == 175.0, "level 1 and 10 match the file")
	check(is_equal_approx(middle["max_distance"], 150.0), "level 5 is 4/9 of the way (got %.1f)" % middle["max_distance"])
	check(top["sweet_spot"] > first["sweet_spot"], "upgrades widen the sweet spot")
	check(top["recovery"] > first["recovery"], "upgrades improve recovery")
	check(top["launch_angle"] == first["launch_angle"], "stats not in level_10 stay the same")
	var travelled := ClubSystem.simulate_distance(top["max_speed"], top)
	check(absf(travelled - 175.0) < 0.5, "level 10 driver really goes 175 m (%.1f)" % travelled)


func test_get_clubs_uses_saved_levels() -> void:
	SaveSystem.reset()
	SaveSystem.set_club_level("Wedge", 3)
	var wedge: Dictionary = ClubSystem.get_clubs()[2]
	check(wedge["level"] == 3, "wedge comes back at level 3")
	SaveSystem.reset()


func test_round_xp_adds_up() -> void:
	var results := [
		{"par": 3, "strokes": 2, "term": "Birdie"},
		{"par": 4, "strokes": 4, "term": "Par"},
		{"par": 5, "strokes": 6, "term": "Bogey"},
	]
	var xp := ProgressionSystem.round_xp(results, 2, 1)
	# 40 (3 holes) + 60 (birdie) + 20 (par) + 5 (bogey) + 30 (2 timing) + 15 (1 power)
	check(xp["total"] == 170, "3-hole round earns 170 XP (got %d)" % xp["total"])
	var line_total := 0
	for line in xp["lines"]:
		line_total += line["xp"]
	check(line_total == xp["total"], "lines add up to the total")


func test_under_par_bonus() -> void:
	var results := [{"par": 4, "strokes": 2, "term": "Eagle"}, {"par": 3, "strokes": 2, "term": "Birdie"}]
	var labels := []
	for line in ProgressionSystem.round_xp(results, 0, 0)["lines"]:
		labels.append(line["label"])
	check(labels.has("3 under par"), "under-par bonus listed (%s)" % [labels])


func test_upgrades_cost_xp() -> void:
	SaveSystem.reset()
	check(not ProgressionSystem.upgrade("Driver"), "can't upgrade with 0 XP")
	SaveSystem.add_xp(ProgressionSystem.upgrade_cost(1) + 10)
	check(ProgressionSystem.upgrade("Driver"), "upgrade once affordable")
	check(SaveSystem.club_level("Driver") == 2, "driver is level 2")
	check(SaveSystem.xp() == 10, "cost was taken off")
	check(SaveSystem.data()["lifetime_xp"] == ProgressionSystem.upgrade_cost(1) + 10,
			"spending doesn't reduce lifetime XP")
	SaveSystem.set_club_level("Driver", ClubSystem.max_level())
	SaveSystem.add_xp(100000)
	check(ProgressionSystem.upgrade_cost(ClubSystem.max_level()) == -1, "no cost past the top level")
	check(not ProgressionSystem.upgrade("Driver"), "can't upgrade a maxed club")
	SaveSystem.reset()


func test_finishing_a_round_banks_xp() -> void:
	SaveSystem.reset()
	var rounds := RoundManagerScript.new()
	rounds.build_round(3)
	for i in 3:
		rounds.strokes = rounds.current_hole()["par"]
		rounds.record_hole()
		rounds.current_index = mini(i + 1, 2)
	rounds.finish_round()
	check(rounds.round_xp["total"] > 0, "round earned XP")
	check(SaveSystem.xp() == rounds.round_xp["total"], "XP banked in the save")
	SaveSystem._data = {}
	check(SaveSystem.xp() == rounds.round_xp["total"], "and written to disk")
	rounds.free()
	SaveSystem.reset()


func test_longest_drive_only_counts_the_driver() -> void:
	var rounds := RoundManagerScript.new()
	rounds.build_round(3)
	rounds.record_shot_distance("Irons", 95.0, false)
	rounds.record_shot_distance("Driver", 120.0, false)
	rounds.record_shot_distance("Putter", 6.0, true)
	check(rounds.longest_drive == 120.0, "longest drive is the driver shot")
	check(rounds.longest_hole_out == 6.0, "hole-out recorded")
	rounds.free()


# ---------------------------------------------------------------------------
# Records and stats (Milestone 6)
# ---------------------------------------------------------------------------

## A fake finished hole, like RoundManager.results holds.
func _hole(hole_name: String, par: int, strokes: int, putts: int) -> Dictionary:
	var rounds := RoundManagerScript.new()
	var term: String = rounds.score_term(strokes, par)
	rounds.free()
	return {"name": hole_name, "par": par, "strokes": strokes, "term": term, "putts": putts}


func test_records_first_round_and_new_best() -> void:
	SaveSystem.reset()
	var first := Records.make_record([_hole("A", 3, 4, 2), _hole("B", 4, 4, 2), _hole("C", 5, 6, 3)], 100, 120.0, 2)
	check(first["mode"] == 3 and first["vs_par"] == 2 and first["putts"] == 7, "record totals")
	var result := Records.add_round(first)
	check(result["is_new_best"] and result["previous_best"].is_empty(), "first round in a mode is a best, with nothing before it")
	# A better round (-1) beats +2 and reports the old best.
	var better := Records.make_record([_hole("A", 3, 2, 1), _hole("B", 4, 4, 2), _hole("C", 5, 5, 2)], 100, 100.0, 1)
	result = Records.add_round(better)
	check(result["is_new_best"], "lower score vs par is a new best")
	check(result["previous_best"]["vs_par"] == 2, "previous best is reported")
	# The same score again is not a new best (it has to beat it).
	result = Records.add_round(Records.make_record([_hole("A", 3, 2, 1), _hole("B", 4, 4, 2), _hole("C", 5, 5, 2)], 0, 0.0, 0))
	check(not result["is_new_best"], "matching the best isn't a new best")
	# A 9-hole best is tracked separately from a 3-hole one.
	var nine: Array = []
	for i in 9:
		nine.append(_hole("H%d" % i, 4, 6, 2))
	result = Records.add_round(Records.make_record(nine, 0, 0.0, 0))
	check(result["is_new_best"], "each mode has its own best")


func test_records_stats() -> void:
	SaveSystem.reset()
	Records.add_round(Records.make_record([_hole("A", 3, 1, 0), _hole("B", 4, 3, 1), _hole("C", 5, 3, 1)], 0, 130.0, 0))  # Ace, Birdie, Eagle: -5
	Records.add_round(Records.make_record([_hole("A", 3, 5, 3), _hole("B", 4, 4, 2), _hole("C", 5, 5, 2)], 0, 90.0, 0))   # +2
	check(Records.rounds_played() == 2, "two rounds played")
	check(Records.best_round(3)["vs_par"] == -5, "best 3-hole round")
	check(Records.best_round(9).is_empty(), "no 9-hole rounds yet")
	check(is_equal_approx(Records.average_vs_par(3), -1.5), "average of -5 and +2 is -1.5")
	check(is_nan(Records.average_vs_par(18)), "no average without rounds")
	check(Records.fewest_putts(3) == 2 and Records.fewest_putts(9) == -1, "fewest putts per mode")
	check(Records.term_count("Ace") == 1 and Records.term_count("Eagle") == 1 and Records.term_count("Birdie") == 1, "ace / eagle / birdie totals")
	check(is_equal_approx(Records.longest_drive(), 130.0), "longest drive")
	check(Records.hole_best("A") == 1 and Records.hole_best("C") == 3, "fewest strokes per hole")
	check(Records.hole_best("Nowhere") == -1, "unplayed hole has no best")


func test_putts_are_counted_but_penalties_are_not() -> void:
	var rounds := RoundManagerScript.new()
	rounds.build_round(3)
	rounds.add_stroke()       # Driver
	rounds.add_stroke(true)   # Putt
	rounds.add_stroke(true)   # Putt
	rounds.add_stroke()       # A penalty stroke
	check(rounds.strokes == 4 and rounds.putts == 2, "4 strokes, 2 of them putts")
	rounds.record_hole()
	check(rounds.results[0]["putts"] == 2, "the hole remembers its putts")
	rounds.free()


func test_finishing_a_round_saves_it_and_quitting_does_not() -> void:
	SaveSystem.reset()
	var rounds := RoundManagerScript.new()
	# Quit partway through: nothing is ever saved (finish_round is never reached).
	rounds.build_round(3)
	rounds.add_stroke()
	rounds.record_hole()
	check(Records.rounds_played() == 0 and SaveSystem.xp() == 0, "an unfinished round leaves no record and no XP")
	# Finish a round properly.
	rounds.build_round(3)
	for i in 3:
		rounds.add_stroke()
		rounds.record_hole()
		rounds.strokes = 0
	rounds.finish_round()
	check(Records.rounds_played() == 1, "a finished round is recorded")
	check(rounds.personal_best["is_new_best"] and rounds.personal_best["mode"] == 3, "and counts as a personal best")
	check(Records.rounds()[0]["xp"] == rounds.round_xp["total"], "the record keeps the XP earned")
	rounds.free()


func test_round_history_survives_a_save_and_load() -> void:
	SaveSystem.reset()
	Records.add_round(Records.make_record([_hole("A", 3, 2, 1)], 40, 77.0, 1))
	SaveSystem.save_game()
	SaveSystem._data = {}  # Forget it in memory, so the next read comes from the file.
	var record: Dictionary = Records.rounds()[0]
	check(record["vs_par"] == -1 and record["holes"][0]["strokes"] == 2, "history comes back from the file")
	check(typeof(record["mode"]) == TYPE_INT and typeof(record["holes"][0]["putts"]) == TYPE_INT, "whole numbers are ints again, not floats")
	check(SaveSystem.data()["version"] == SaveSystem.SAVE_VERSION, "saved with the current version")


func test_version_1_save_gets_an_empty_history() -> void:
	SaveSystem.reset()
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string('{"version": 1, "xp": 75, "lifetime_xp": 75, "club_levels": {"Driver": 3}}')
	file.close()
	SaveSystem._data = {}
	check(SaveSystem.data()["xp"] == 75 and SaveSystem.club_level("Driver") == 3, "old XP and club levels are kept")
	check(Records.rounds_played() == 0, "an old save starts with an empty round history")
	check(SaveSystem.data()["version"] == SaveSystem.SAVE_VERSION, "and is upgraded to the new version")


func test_reset_all_wipes_everything() -> void:
	SaveSystem.reset()
	SaveSystem.add_xp(500)
	SaveSystem.set_club_level("Driver", 5)
	Records.add_round(Records.make_record([_hole("A", 3, 2, 1)], 40, 77.0, 1))
	SaveSystem.reset_all()
	check(SaveSystem.xp() == 0 and SaveSystem.club_level("Driver") == 1, "XP and club levels are back to new-player values")
	check(Records.rounds_played() == 0, "round history is gone")
	SaveSystem._data = {}
	check(SaveSystem.xp() == 0 and Records.rounds_played() == 0, "and the file on disk is wiped too")


# ---------------------------------------------------------------------------
# Main Street Opener (Milestone 7): the benchmark hole's data and scenery
# ---------------------------------------------------------------------------

func _main_street() -> Dictionary:
	var rounds := RoundManagerScript.new()
	var found := {}
	for hole in rounds.all_holes():
		if hole["id"] == "main_street_opener":
			found = hole
	rounds.free()
	return found


func test_main_street_hole_loads() -> void:
	var hole := _main_street()
	check(not hole.is_empty(), "main_street_opener.json is found among the holes")
	check(hole["name"] == "Main Street Opener" and hole["par"] == 3, "name and par")
	check(hole["look"] == "golden_hour", "uses the golden hour look")
	check(not hole["scenery"].is_empty(), "has a scenery scene")
	check(hole["camera"].has("back") and hole["camera"].has("height"), "has its own camera settings")


func test_main_street_layout_is_playable() -> void:
	var hole := _main_street()
	var map := SurfaceMap.new(hole["surfaces"], hole["bounds"], hole["ground"], hole["obstacles"])
	check(map.type_at(hole["tee"].x, hole["tee"].z) == "tee", "the tee is on the tee box")
	check(map.type_at(hole["cup"].x, hole["cup"].z) == "green", "the cup is on the green")
	check(map.type_at(0.0, -40.0) == "fairway", "the mid-fairway is fairway")
	check(map.type_at(-4.1, -40.0) == "street", "beside the fairway is street")
	check(map.type_at(-5.7, -40.0) == "rough", "the grass strip by the kerb is rough")
	check(map.type_at(-7.5, -40.0) == "sidewalk", "then the sidewalk")
	check(map.type_at(40.0, -40.0) == "oob", "outside the bounds is out of bounds")
	# Nothing solid stands on the tee, the cup or the line of the fairway's centre.
	check(not map.obstacles.covers(hole["tee"].x, hole["tee"].z), "nothing on the tee")
	check(not map.obstacles.covers(hole["cup"].x, hole["cup"].z), "nothing on the cup")
	for z in range(-2, -90, -4):
		check(not map.obstacles.covers(0.0, float(z)), "centre line clear at z=%d" % z)


func test_main_street_scenery_files_exist() -> void:
	var hole := _main_street()
	var data: Dictionary = hole["scenery"]
	check(ResourceLoader.exists(data["scene"]), "scenery scene exists (run tools/build_hole_scenery.gd if not)")
	check(ResourceLoader.exists(data["sun_mask"]), "baked sun mask exists")
	var scenery = load(data["scene"]).instantiate()
	check(scenery is HoleScenery, "the scene's root is a HoleScenery")
	check(scenery.mask_rect.size.x > 0.0, "it knows the area the sun mask covers")
	var multimeshes := 0
	var instances := 0
	for node in scenery.find_children("*", "MultiMeshInstance3D", true, false):
		multimeshes += 1
		instances += node.multimesh.instance_count
	check(multimeshes > 0 and instances > 50, "instanced props (cars, trees, lamps) are saved with their positions")
	scenery.free()


func test_every_obstacle_in_the_hole_has_art() -> void:
	# The tool draws art for these types; a new type in the data needs the tool taught about it.
	var drawn := ["building", "car", "lamp", "tree", "cone"]
	var hole := _main_street()
	for obstacle in hole["obstacles"]:
		check(drawn.has(obstacle["type"]), "no scenery art for obstacle type '%s'" % obstacle["type"])


func test_looks_are_complete() -> void:
	var looks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LookSetup.LOOKS_FILE))
	var keys := ["elev", "azim", "sun", "energy", "ambient", "exposure", "zenith", "mid", "horizon",
			"cloud", "cloud_shadow", "coverage", "fog", "fog_density", "lit", "glow_intensity",
			"glow_bloom", "saturation", "contrast"]
	for look_name in looks:
		if look_name.begins_with("_"):
			continue
		for key in keys:
			check(looks[look_name].has(key), "look '%s' is missing '%s'" % [look_name, key])


func test_preview_mode_saves_nothing() -> void:
	SaveSystem.reset()
	var rounds := RoundManagerScript.new()
	rounds.build_round(1)
	rounds.is_preview = true
	rounds.add_stroke()
	rounds.record_hole()
	check(Records.rounds_played() == 0 and SaveSystem.xp() == 0, "a preview leaves no record and no XP")
	rounds.free()


# ---------------------------------------------------------------------------
# Street Golf main menu (shared theme, chips, feedback hooks)
# ---------------------------------------------------------------------------

func test_player_level_from_lifetime_xp() -> void:
	check(ProgressionSystem.level_for(0) == 1, "a new player is level 1")
	check(ProgressionSystem.level_for(119) == 1, "119 XP is still level 1")
	check(ProgressionSystem.level_for(120) == 2, "120 XP reaches level 2")
	check(ProgressionSystem.level_for(4600) == 10, "the last listed level")
	check(ProgressionSystem.level_for(6100) == 11, "past the list, each level costs a fixed step")
	SaveSystem.reset()
	check(ProgressionSystem.player_level() == 1, "player_level() reads the save")
	SaveSystem.add_xp(300)
	SaveSystem.spend_xp(200)
	check(ProgressionSystem.player_level() == 3, "spending XP never lowers the level")


func test_top_club_is_the_highest_level() -> void:
	SaveSystem.reset()
	var top := ProgressionSystem.top_club()
	check(top["level"] == 1 and top["name"] == ClubSystem.club_names()[0], "a new player's top club is the first club at level 1")
	SaveSystem.set_club_level("Irons", 3)
	SaveSystem.set_club_level("Wedge", 3)
	top = ProgressionSystem.top_club()
	check(top["name"] == "Irons" and top["level"] == 3, "the highest level wins; the first club wins a tie")


func test_menu_chips_show_real_data_with_sensible_empty_values() -> void:
	SaveSystem.reset()
	check("Best 18: [color=#ffd84a]--[/color]" == MenuInfo.best_chip_text(), "no 18-hole round yet shows --")
	check(MenuInfo.level_chip_text().contains("LV [color=#ffd84a]1[/color]"), "a new player is LV 1")
	check(MenuInfo.level_chip_text().contains("Driver [color=#ffd84a]Lv 1[/color]"), "with a level 1 Driver")
	# A 9-hole round doesn't count as an 18-hole best.
	Records.add_round(Records.make_record([_hole("A", 3, 2, 1)], 0, 0.0, 0).merged({"mode": 9}))
	check(MenuInfo.best_chip_text().contains("--"), "only 18-hole rounds count")
	var holes: Array = []
	for i in 18:
		holes.append(_hole("H%d" % i, 4, 4 if i > 3 else 3, 2))
	Records.add_round(Records.make_record(holes, 0, 0.0, 0))
	check(MenuInfo.best_chip_text().contains("[color=#ffd84a]-4[/color]"), "a finished 18-hole round shows its score vs par")
	SaveSystem.reset()


func test_ui_theme_has_the_shared_look() -> void:
	var ui_theme: Theme = load("res://ui/theme/street_golf.tres")
	check(ui_theme != null, "the shared theme loads")
	for variation in ["BigGreenButton", "OrangeButton"]:
		check(ui_theme.get_type_variation_base(variation) == "Button", "%s is a Button variation" % variation)
		check(ui_theme.has_stylebox("pressed", variation), "%s has a pressed look" % variation)
	for name in ["navy", "gold", "yellow", "green", "orange"]:
		check(ui_theme.has_color(name, "StreetGolf"), "theme palette has %s" % name)
	check(ui_theme.has_font("title", "StreetGolf") and ui_theme.has_font("body", "StreetGolf"), "theme names its title and body fonts")
	check(ui_theme.default_font != null, "theme sets a default font")


func test_fonts_and_licences_are_in_the_project() -> void:
	for path in ["res://fonts/lilita_one/LilitaOne-Regular.ttf", "res://fonts/fredoka/Fredoka-Variable.ttf"]:
		check(ResourceLoader.exists(path), "font present: " + path)
	for path in ["res://fonts/lilita_one/OFL.txt", "res://fonts/fredoka/OFL.txt"]:
		check(FileAccess.file_exists(path), "licence file present: " + path)
	var credits := FileAccess.get_file_as_string("res://../CREDITS.md")
	check(credits.contains("Lilita One") and credits.contains("Fredoka") and credits.contains("Open Font License"), "CREDITS.md lists both fonts and their licence")


func test_project_is_called_street_golf() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "Street Golf", "project name")
	check(str(ProjectSettings.get_setting("application/config/version")) != "", "version is set")


func test_button_feedback_hooks_respect_the_settings() -> void:
	var sounds := []
	var buzzes := []
	UiFeedback.sound_hook = func(sound_name: StringName) -> void: sounds.append(sound_name)
	UiFeedback.haptic_hook = func(strength: StringName) -> void: buzzes.append(strength)
	var sound_before := GameSettings.sound_on
	var haptics_before := GameSettings.haptics_on
	GameSettings.sound_on = false
	GameSettings.haptics_on = false
	UiFeedback.press()
	check(sounds.is_empty() and buzzes.is_empty(), "nothing plays or buzzes when both are off")
	GameSettings.sound_on = true
	GameSettings.haptics_on = true
	UiFeedback.press()
	check(sounds == [&"ui_click"] and buzzes == [&"light"], "a press calls the sound and haptic hooks")
	UiFeedback.sound_hook = Callable()
	UiFeedback.haptic_hook = Callable()
	GameSettings.sound_on = sound_before
	GameSettings.haptics_on = haptics_before
