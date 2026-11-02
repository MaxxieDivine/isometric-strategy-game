class_name Score
extends RefCounted
## Civ score: citizens, techs, wonders and barbarian camps destroyed, each
## times a weight from data/score.json. Works for any number of civ players.
## Once the game is over the score is frozen at its final value.

const PATH := "res://data/score.json"
const PARTS: Array[String] = ["citizens", "techs", "wonders", "camps_destroyed"]

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


static func weight(part: String) -> int:
	return int((rules().get("weights", {}) as Dictionary).get(part, 0))


## Raw counts of each scoring part for a player, right now.
static func counts(state: GameState, player_id: int) -> Dictionary:
	var citizens := 0
	for city in state.cities_of(player_id):
		citizens += city.size
	return {
		"citizens": citizens,
		"techs": Research.known(state, player_id).size(),
		"wonders": Wonders.wonders_of(state, player_id).size(),
		"camps_destroyed": int(state.players[player_id].get("camps_destroyed", 0)),
	}


## { citizens, techs, wonders, camps_destroyed: { count, points }, total },
## computed live (ignores the frozen final score).
static func live_breakdown(state: GameState, player_id: int) -> Dictionary:
	var c := counts(state, player_id)
	var result := { "total": 0 }
	for part in PARTS:
		var points := int(c[part]) * weight(part)
		result[part] = { "count": int(c[part]), "points": points }
		result["total"] = int(result["total"]) + points
	return result


## The breakdown that counts: frozen at game end, live before.
static func breakdown(state: GameState, player_id: int) -> Dictionary:
	if Victory.is_over(state):
		var final: Dictionary = state.game_over.get("final", {})
		if final.has(str(player_id)):
			return final[str(player_id)]
	return live_breakdown(state, player_id)


static func score(state: GameState, player_id: int) -> int:
	return int(breakdown(state, player_id)["total"])


## Appends this turn's score for every civ player to the history. Nothing is
## recorded after the game is over: the score is frozen then.
static func record(state: GameState) -> void:
	if Victory.is_over(state):
		return
	var scores := {}
	for player_id in state.civ_player_ids():
		scores[str(player_id)] = score(state, player_id)
	if not state.score_history.is_empty() and int(state.score_history.back()["turn"]) == state.turn:
		state.score_history.back()["scores"] = scores
	else:
		state.score_history.append({ "turn": state.turn, "scores": scores })


## A player's score over time: [[turn, score], ...].
static func history_of(state: GameState, player_id: int) -> Array:
	var result: Array = []
	for entry: Dictionary in state.score_history:
		var scores: Dictionary = entry["scores"]
		if scores.has(str(player_id)):
			result.append([int(entry["turn"]), int(scores[str(player_id)])])
	return result


## The end-of-game title for a score: { min, name, blurb }.
static func title_for(value: int) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in rules().get("titles", []):
		var title: Dictionary = entry
		if value >= int(title.get("min", 0)) and (best.is_empty() or int(title["min"]) >= int(best["min"])):
			best = title
	return best
