class_name AdvisorDefs
extends RefCounted
## Advisor definitions: data/advisors/roster.json lists who is active, and
## data/advisors/<id>.json defines each one (name, title, portrait sprite key,
## personality, selection policies, phrases, and dialogue triggers).
##
## Trigger fields: id, event (an event type, see GameActions and
## AdvisorDirector), conditions ([{ fact, op, value }], see AdvisorConditions),
## once (bool), cooldown (turns), priority (higher wins), action (optional,
## e.g. { "type": "suggest_city_site", "policy": "city_site" }), and lines
## ([{ text, tone }], text with {placeholders}).

const DIR := "res://data/advisors/"
const ROSTER_PATH := DIR + "roster.json"

static var _roster: Dictionary = {}
static var _defs: Dictionary = {}


## Replaces the loaded data (tests use this for made-up advisors); `reset`
## goes back to the files.
static func use_defs(roster_data: Dictionary, defs: Dictionary) -> void:
	_roster = roster_data
	_defs = defs


static func reset() -> void:
	_roster = {}
	_defs = {}


static func roster() -> Dictionary:
	if _roster.is_empty():
		_roster = DataLoader.load_dict(ROSTER_PATH)
	return _roster


## Ids of the active advisors, in roster order.
static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: Variant in roster().get("advisors", []):
		result.append(String(id))
	return result


static func max_messages_per_turn() -> int:
	return int(roster().get("max_messages_per_turn", 1))


static func log_limit() -> int:
	return int(roster().get("log_limit", 200))


static func get_def(id: String) -> Dictionary:
	if not _defs.has(id):
		_defs[id] = DataLoader.load_dict(DIR + id + ".json")
	return _defs[id]


static func display_name(id: String) -> String:
	return String(get_def(id).get("name", id))


static func triggers(id: String) -> Array:
	return get_def(id).get("triggers", [])


static func policy(id: String, choice: String) -> String:
	var policies: Dictionary = get_def(id).get("policies", {})
	return String(policies.get(choice, AdvisorPolicy.BEST))


static func phrase(id: String, key: String) -> String:
	var phrases: Dictionary = get_def(id).get("phrases", {})
	return String(phrases.get(key, ""))


static func initial_memory(id: String) -> Dictionary:
	var memory: Dictionary = get_def(id).get("initial_state", {})
	return memory.duplicate(true)
