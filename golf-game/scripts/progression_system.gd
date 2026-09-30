class_name ProgressionSystem
extends RefCounted
## XP and club upgrades.
##
## After a finished round, round_xp() works out what it earned (birdies, perfect
## shots, finishing under par...). XP is then a currency: the Clubs screen spends it
## on upgrades, one level at a time, each level costing more. Upgrades are only ever
## bought with XP, never with money.
##
## The numbers live in data/progression.json so they can be balanced without code.

const RULES_FILE := "res://data/progression.json"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string(RULES_FILE))
	return _rules


## The XP a finished round earned, itemised for the summary screen.
## `results`: one { par, strokes, term } per hole. Returns { lines: [{ label, xp }], total }.
static func round_xp(results: Array, perfect_timing: int, perfect_power: int) -> Dictionary:
	var xp_rules: Dictionary = rules()["xp"]
	var lines: Array[Dictionary] = []

	var base := int(xp_rules["round_complete"].get(str(results.size()), 0))
	lines.append({"label": "%d-hole round" % results.size(), "xp": base})

	# One line per kind of hole score, best first: "2 x Birdie  +120".
	var term_counts := {}
	for result in results:
		term_counts[result["term"]] = term_counts.get(result["term"], 0) + 1
	for term in xp_rules["hole"]:
		var count: int = term_counts.get(term, 0)
		var each := int(xp_rules["hole"][term])
		if count > 0 and each > 0:
			lines.append({"label": "%d x %s" % [count, term], "xp": count * each})

	if perfect_timing > 0:
		lines.append({"label": "%d x Perfect timing" % perfect_timing,
				"xp": perfect_timing * int(xp_rules["perfect_timing"])})
	if perfect_power > 0:
		lines.append({"label": "%d x Perfect power" % perfect_power,
				"xp": perfect_power * int(xp_rules["perfect_power"])})

	var par := 0
	var strokes := 0
	for result in results:
		par += result["par"]
		strokes += result["strokes"]
	if strokes < par:
		lines.append({"label": "%d under par" % (par - strokes),
				"xp": (par - strokes) * int(xp_rules["per_stroke_under_par"])})

	var total := 0
	for line in lines:
		total += line["xp"]
	return {"lines": lines, "total": total}


## XP to raise a club from `level` to the next. -1 if it's already maxed out.
static func upgrade_cost(level: int) -> int:
	var costs: Array = rules()["upgrade_cost"]
	if level < 1 or level >= ClubSystem.max_level() or level > costs.size():
		return -1
	return int(costs[level - 1])


static func can_upgrade(club_name: String) -> bool:
	var cost := upgrade_cost(SaveSystem.club_level(club_name))
	return cost >= 0 and SaveSystem.xp() >= cost


## Spend XP to raise a club one level, and save. Returns false if it couldn't.
static func upgrade(club_name: String) -> bool:
	var level := SaveSystem.club_level(club_name)
	var cost := upgrade_cost(level)
	if cost < 0 or not SaveSystem.spend_xp(cost):
		return false
	SaveSystem.set_club_level(club_name, level + 1)
	SaveSystem.save_game()
	return true


## Can the player afford at least one upgrade right now?
static func any_upgrade_affordable() -> bool:
	for club_name in ClubSystem.club_names():
		if can_upgrade(club_name):
			return true
	return false
