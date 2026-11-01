class_name Calendar
extends RefCounted
## Turn number → in-game year.

const START_YEAR := -4000
const YEARS_PER_TURN := 50


static func year_for_turn(turn: int) -> int:
	return START_YEAR + (turn - 1) * YEARS_PER_TURN


static func format_year(year: int) -> String:
	if year < 0:
		return "%d BC" % -year
	# There is no year 0: 1 BC is followed by AD 1.
	return "AD %d" % maxi(year, 1)
