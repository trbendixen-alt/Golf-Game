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
