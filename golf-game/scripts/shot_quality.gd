class_name ShotQuality
extends RefCounted
## Grades a swing as Perfect / Good / Average / Poor. Later this drives XP (Milestone 5).
##
## A shot is graded on two things, and gets the WORSE of the two grades:
##   - timing: how close the accuracy tap was to the centre of the bar
##   - power: how close the power tap was to the suggested power (yellow marker)
## Putts have no accuracy tap, so they're graded on power alone.
##
## The timing windows are measured in "sweet spots", so a club with a wider sweet spot
## (a better club level) is automatically more forgiving.

enum Tier { PERFECT, GOOD, AVERAGE, POOR }
const TIER_NAMES := ["PERFECT", "GOOD", "AVERAGE", "POOR"]

# Timing windows, as multiples of the club's sweet spot half-width.
const TIMING_PERFECT := 0.3   # A tight window in the middle of the green zone.
const TIMING_GOOD := 1.0      # Anywhere in the green zone.
const TIMING_AVERAGE := 3.0

# Power windows: how far (0..1) the power tap may be from the suggested power.
const POWER_PERFECT := 0.03
const POWER_GOOD := 0.08
const POWER_AVERAGE := 0.2


## Returns { tier, perfect_timing, perfect_power }.
## `accuracy`: -1..1 (0 = centre). `power` and `target_power`: 0..1.
## `has_timing`: false for two-tap swings (putts), which only grade power.
static func rate(power: float, accuracy: float, target_power: float, sweet_spot: float,
		has_timing := true) -> Dictionary:
	var power_tier := _grade(absf(power - target_power), POWER_PERFECT, POWER_GOOD, POWER_AVERAGE)
	var tier := power_tier
	var timing_tier := Tier.POOR
	if has_timing:
		timing_tier = _grade(absf(accuracy), sweet_spot * TIMING_PERFECT,
				sweet_spot * TIMING_GOOD, sweet_spot * TIMING_AVERAGE)
		tier = maxi(tier, timing_tier)  # Higher enum value = worse grade.
	return {
		"tier": tier,
		"perfect_timing": has_timing and timing_tier == Tier.PERFECT,
		"perfect_power": power_tier == Tier.PERFECT,
	}


static func _grade(error: float, perfect: float, good: float, average: float) -> Tier:
	if error <= perfect:
		return Tier.PERFECT
	elif error <= good:
		return Tier.GOOD
	elif error <= average:
		return Tier.AVERAGE
	return Tier.POOR
