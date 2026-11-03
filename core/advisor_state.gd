class_name AdvisorState
extends RefCounted
## What the advisors remember, saved with the game (GameState.advisor).
## Nothing here affects gameplay: game rules never read it, and the advisors
## draw from their own random stream instead of GameState.rng.

## The player turned the advisor off: no triggers run and nothing is said.
var enabled: bool = true
## Advisor id -> { "memory": Dictionary (generic per-advisor state that
## trigger conditions can read; empty for now), "fired": { trigger id ->
## last turn it spoke }, "last_line": { trigger id -> line index } }.
var advisors: Dictionary = {}
## Messages shown on `messages_turn` (for the per-turn limit).
var messages_turn: int = 0
var messages_count: int = 0
## Advice given, in order (never shown to the player): { turn, advisor,
## trigger, text, [suggested: [x, y], outcome: "pending" | "followed" |
## "elsewhere" | "superseded", actual: [x, y], distance] }.
var advice_log: Array = []
## Matches that couldn't speak yet: { advisor, trigger, event (plain
## fields only), until (last turn it may still speak) }.
var pending: Array = []
## Dialogue variety only. Separate from GameState.rng so advisor activity can
## never change a game outcome.
var rng := RandomNumberGenerator.new()


## The entry for `advisor_id`, created on first use.
func entry(advisor_id: String) -> Dictionary:
	if not advisors.has(advisor_id):
		advisors[advisor_id] = { "memory": AdvisorDefs.initial_memory(advisor_id), "fired": {}, "last_line": {} }
	return advisors[advisor_id]


## The turn `trigger_id` last spoke, or -1 if never.
func last_fired(advisor_id: String, trigger_id: String) -> int:
	var fired: Dictionary = entry(advisor_id)["fired"]
	return int(fired.get(trigger_id, -1))


func memory(advisor_id: String) -> Dictionary:
	return entry(advisor_id)["memory"]


func messages_on(turn: int) -> int:
	return messages_count if messages_turn == turn else 0


func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"advisors": advisors.duplicate(true),
		"messages_turn": messages_turn,
		"messages_count": messages_count,
		"log": advice_log.duplicate(true),
		"pending": pending.duplicate(true),
		"rng": { "seed": str(rng.seed), "state": str(rng.state) },
	}


static func from_dict(data: Dictionary) -> AdvisorState:
	var result := AdvisorState.new()
	result.enabled = bool(data.get("enabled", true))
	var advisor_data: Dictionary = data.get("advisors", {})
	for id: Variant in advisor_data:
		var raw: Dictionary = advisor_data[id]
		result.advisors[String(id)] = {
			"memory": (raw.get("memory", {}) as Dictionary).duplicate(true),
			"fired": _int_values(raw.get("fired", {})),
			"last_line": _int_values(raw.get("last_line", {})),
		}
	result.messages_turn = int(data.get("messages_turn", 0))
	result.messages_count = int(data.get("messages_count", 0))
	for raw: Variant in data.get("log", []):
		result.advice_log.append(_log_entry(raw))
	for raw: Variant in data.get("pending", []):
		var entry: Dictionary = raw
		result.pending.append({ "advisor": String(entry["advisor"]), "trigger": String(entry["trigger"]),
			"event": plain_event(entry["event"]), "until": int(entry["until"]) })
	var rng_data: Dictionary = data.get("rng", {})
	if rng_data.has("seed"):
		result.rng.seed = String(rng_data["seed"]).to_int()
		result.rng.state = String(rng_data["state"]).to_int()
	return result


## The event's plain fields (ids, names, flags), for keeping in a save.
## Numbers become ints: event fields are whole numbers, and JSON gives floats.
static func plain_event(event: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in event:
		var value: Variant = event[key]
		match typeof(value):
			TYPE_INT, TYPE_FLOAT:
				result[String(key)] = int(value)
			TYPE_STRING, TYPE_STRING_NAME:
				result[String(key)] = String(value)
			TYPE_BOOL:
				result[String(key)] = value
	return result


## JSON turns ints into floats; restore them so a reload is identical.
static func _int_values(data: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in data:
		result[String(key)] = int(data[key])
	return result


static func _log_entry(raw: Dictionary) -> Dictionary:
	var entry := { "turn": int(raw["turn"]), "advisor": String(raw["advisor"]),
		"trigger": String(raw["trigger"]), "text": String(raw.get("text", "")) }
	for key: String in ["suggested", "actual"]:
		if raw.has(key):
			entry[key] = [int(raw[key][0]), int(raw[key][1])]
	if raw.has("outcome"):
		entry["outcome"] = String(raw["outcome"])
	if raw.has("distance"):
		entry["distance"] = int(raw["distance"])
	return entry
