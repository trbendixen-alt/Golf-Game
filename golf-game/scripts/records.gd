class_name Records
extends RefCounted
## Round history and the stats worked out from it.
##
## Every finished round is stored in the save file as one "round record":
##   { date, mode, holes: [{ name, par, strokes, term, putts }], total_strokes,
##     total_par, vs_par, putts, xp, longest_drive, perfect_shots }
## "mode" is 3, 9 or 18 (how many holes the round had). "vs_par" is the score
## compared to par (negative = under par).
##
## We only store the rounds. Everything else (best round, averages, birdie totals,
## per-hole bests...) is worked out from them when needed, so there's a single source
## of truth and nothing can drift out of sync.
##
## Personal bests compare SCORE VS PAR, not raw strokes, because different rounds
## use different holes (and so different pars).
## Rounds that are abandoned (Quit Round) are never added here.

const MODES := [3, 9, 18]


## Formats a score vs par: 0 -> "E" (even), 2 -> "+2", -1 -> "-1".
static func format_vs_par(difference: int) -> String:
	if difference == 0:
		return "E"
	elif difference > 0:
		return "+%d" % difference
	return "%d" % difference


static func rounds() -> Array:
	return SaveSystem.data()["rounds"]


## Turn a finished round into a record, ready for add_round().
static func make_record(results: Array, xp: int, longest_drive: float, perfect_shots: int) -> Dictionary:
	var holes: Array = []
	var strokes := 0
	var par := 0
	var putts := 0
	for result in results:
		holes.append({
			"name": result["name"], "par": result["par"], "strokes": result["strokes"],
			"term": result["term"], "putts": result.get("putts", 0),
		})
		strokes += result["strokes"]
		par += result["par"]
		putts += result.get("putts", 0)
	return {
		"date": Time.get_datetime_string_from_system(false, true),  # e.g. 2026-09-30 14:05:22
		"mode": results.size(),
		"holes": holes,
		"total_strokes": strokes,
		"total_par": par,
		"vs_par": strokes - par,
		"putts": putts,
		"xp": xp,
		"longest_drive": longest_drive,
		"perfect_shots": perfect_shots,
	}


## Store a finished round (the caller saves the file afterwards). Returns whether it
## beat the previous best for its mode: { is_new_best, previous_best }.
## previous_best is empty if this is the first round in that mode.
## Must be called BEFORE the round is stored, so "previous" really is the previous one.
static func add_round(record: Dictionary) -> Dictionary:
	var previous := best_round(record["mode"])
	# A first-ever round in a mode counts as a best, since there's nothing to beat.
	var is_new_best: bool = previous.is_empty() or record["vs_par"] < previous["vs_par"]
	rounds().append(record)
	return {"is_new_best": is_new_best, "previous_best": previous}


static func rounds_played() -> int:
	return rounds().size()


static func rounds_for_mode(mode: int) -> Array:
	return rounds().filter(func(record: Dictionary) -> bool: return record["mode"] == mode)


## The lowest-scoring round for a mode (the earliest one wins a tie). {} if none.
static func best_round(mode: int) -> Dictionary:
	var best := {}
	for record in rounds_for_mode(mode):
		if best.is_empty() or record["vs_par"] < best["vs_par"]:
			best = record
	return best


## Average score vs par over all rounds of a mode. NAN if there are none.
static func average_vs_par(mode: int) -> float:
	var played := rounds_for_mode(mode)
	if played.is_empty():
		return NAN
	var total := 0
	for record in played:
		total += record["vs_par"]
	return float(total) / played.size()


## The fewest putts in a single round of a mode. -1 if there are no rounds.
static func fewest_putts(mode: int) -> int:
	var fewest := -1
	for record in rounds_for_mode(mode):
		if fewest < 0 or record["putts"] < fewest:
			fewest = record["putts"]
	return fewest


## How many holes ever finished with this score term ("Ace", "Eagle", "Birdie"...).
static func term_count(term: String) -> int:
	var count := 0
	for record in rounds():
		for hole in record["holes"]:
			if hole["term"] == term:
				count += 1
	return count


## The longest Driver shot ever, in metres. 0 if none.
static func longest_drive() -> float:
	var longest := 0.0
	for record in rounds():
		longest = maxf(longest, record["longest_drive"])
	return longest


## The fewest strokes ever taken on a hole (by name). -1 if it's never been played.
static func hole_best(hole_name: String) -> int:
	var best := -1
	for record in rounds():
		for hole in record["holes"]:
			if hole["name"] == hole_name and (best < 0 or hole["strokes"] < best):
				best = hole["strokes"]
	return best
