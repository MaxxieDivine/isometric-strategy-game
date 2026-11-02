class_name Victory
extends RefCounted
## How the game ends: at the turn limit (after turn `turn_limit` is played) or
## early when one civ holds every wonder (Wonder Victory). The result lives in
## GameState.game_over: {} while playing, else
##   { reason: "turn_limit" | "wonder_victory", turn, winner,
##     final: { "<player id>": Score breakdown }, continued: bool }
## `continued` is set when the player chose Keep Playing.

const PATH := "res://data/victory.json"
const TURN_LIMIT := "turn_limit"
const WONDER_VICTORY := "wonder_victory"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


static func default_turn_limit() -> int:
	return int(rules().get("turn_limit", 150))


static func countdown_turns() -> int:
	return int(rules().get("countdown_turns", 20))


static func is_over(state: GameState) -> bool:
	return not state.game_over.is_empty()


static func is_continued(state: GameState) -> bool:
	return bool(state.game_over.get("continued", false))


## Turns left including the current one (1 on the final turn).
static func turns_remaining(state: GameState) -> int:
	return state.turn_limit - state.turn + 1


## True while the top bar should count down.
static func show_countdown(state: GameState) -> bool:
	var left := turns_remaining(state)
	return not is_over(state) and left >= 1 and left <= countdown_turns()


## The player holding every wonder, or -1.
static func wonder_victor(state: GameState) -> int:
	var victor := -1
	for id in WonderDefs.ids():
		var owner := Wonders.owner_of(state, id)
		if owner < 0 or (victor >= 0 and owner != victor):
			return -1
		victor = owner
	return victor


## Called at the end of end_turn. Ends the game if a condition is met;
## otherwise reports countdown milestones (turns_remaining events).
static func check(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if is_over(state):
		return events
	var victor := wonder_victor(state) if bool(rules().get("wonder_victory", true)) else -1
	if victor >= 0:
		events.append(end_game(state, WONDER_VICTORY, victor))
	elif state.turn > state.turn_limit:
		events.append(end_game(state, TURN_LIMIT, _top_scorer(state)))
	else:
		var left := turns_remaining(state)
		for at: Variant in rules().get("countdown_news_at", []):
			if int(at) == left:
				events.append({ "type": "turns_remaining", "turns": left })
	return events


## Freezes every civ's score and returns the game_over event.
static func end_game(state: GameState, reason: String, winner: int) -> Dictionary:
	var final := {}
	for player_id in state.civ_player_ids():
		final[str(player_id)] = Score.live_breakdown(state, player_id)
	# Wonders complete on the turn that just began; the turn limit ends after
	# the limit turn was played.
	var turn := state.turn if reason == WONDER_VICTORY else mini(state.turn - 1, state.turn_limit)
	state.game_over = { "reason": reason, "turn": maxi(1, turn), "winner": winner,
		"final": final, "continued": false }
	return { "type": "game_over", "reason": reason, "winner": winner }


## Keep Playing: turns go on, the score stays frozen.
static func continue_game(state: GameState) -> void:
	if is_over(state):
		state.game_over["continued"] = true


static func _top_scorer(state: GameState) -> int:
	var best := -1
	var best_score := -1
	for player_id in state.civ_player_ids():
		var value := int(Score.live_breakdown(state, player_id)["total"])
		if value > best_score:
			best = player_id
			best_score = value
	return best
