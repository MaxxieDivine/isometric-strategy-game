class_name AdvisorDirector
extends RefCounted
## Decides what the advisors say. The session hands it each batch of game
## events (see GameActions) plus two of its own:
##   game_started   { player }    (a new game, not a continued save)
##   unit_selected  { unit_id }   (the player picked a different unit)
## It matches advisor triggers against them and returns at most one message
## per call, the highest priority one, within the per-turn limit. A matched
## trigger with "carry_over": N that couldn't speak (outranked or over the
## limit) waits up to N turns and is weighed again, conditions and all.
##
## Systems produce options (e.g. CitySiteScorer ranks city sites); the
## advisor's selection policy picks which one it talks about. Never assume
## advice is optimal or honest.
##
## Only GameState.advisor is ever written. Line variety draws from the
## advisor's own RNG, so advisor activity can't change any game outcome.

const NO_CELL := Vector2i(-1, -1)
const SUGGEST_CITY_SITE := "suggest_city_site"
## Compass words for the 8 directions, starting east and turning clockwise
## (grid y grows southward).
const DIRECTIONS: Array[String] = ["east", "south-east", "south", "south-west", "west", "north-west",
	"north", "north-east"]


## The message to show for `events`, or {} for none. Message keys: advisor,
## name, title, portrait, placeholder_color, trigger, text, tone, highlight
## (a suggested cell or NO_CELL).
static func observe(state: GameState, player_id: int, events: Array[Dictionary]) -> Dictionary:
	var advisor := state.advisor
	_record_outcomes(state, player_id, events)
	if not advisor.enabled:
		return {}
	advisor.pending = advisor.pending.filter(func(entry: Dictionary) -> bool:
		return int(entry["until"]) >= state.turn)
	var matches := find_matches(state, player_id, events)
	var message := {}
	if advisor.messages_on(state.turn) < AdvisorDefs.max_messages_per_turn():
		for found in matches:
			message = compose(state, player_id, found)
			if not message.is_empty():
				_remember(state, found, message)
				break
	_carry_over(state, matches, message)
	return message


static func set_enabled(state: GameState, enabled: bool) -> void:
	state.advisor.enabled = enabled


## Triggers that are ready and whose event and conditions match, highest
## priority first (data order breaks ties). Each: { advisor, trigger, event }.
static func find_matches(state: GameState, player_id: int, events: Array[Dictionary]) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for advisor_id in AdvisorDefs.ids():
		var memory := state.advisor.memory(advisor_id)
		for trigger: Dictionary in AdvisorDefs.triggers(advisor_id):
			if not is_ready(state, advisor_id, trigger):
				continue
			for event in events:
				if String(event["type"]) != String(trigger.get("event", "")) \
						or event_player(state, event, player_id) != player_id:
					continue
				if AdvisorConditions.all_hold(trigger.get("conditions", []), state, player_id, event, memory):
					found.append({ "advisor": advisor_id, "trigger": trigger, "event": event, "order": found.size() })
					break
	# Carried-over matches from earlier turns, unless the trigger matched afresh.
	for entry: Dictionary in state.advisor.pending:
		var advisor_id := String(entry["advisor"])
		var trigger := _trigger(advisor_id, String(entry["trigger"]))
		var event: Dictionary = entry["event"]
		if trigger.is_empty() or _has_match(found, advisor_id, String(trigger["id"])) \
				or not is_ready(state, advisor_id, trigger) or event_player(state, event, player_id) != player_id:
			continue
		if AdvisorConditions.all_hold(trigger.get("conditions", []), state, player_id, event,
				state.advisor.memory(advisor_id)):
			found.append({ "advisor": advisor_id, "trigger": trigger, "event": event, "order": found.size() })
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := int(a["trigger"].get("priority", 0))
		var pb := int(b["trigger"].get("priority", 0))
		return pa > pb if pa != pb else int(a["order"]) < int(b["order"]))
	return found


## Not spent (once-only) and out of its cooldown. A trigger speaks at most
## once a turn, so cooldown 0 means "any later turn".
static func is_ready(state: GameState, advisor_id: String, trigger: Dictionary) -> bool:
	var last := state.advisor.last_fired(advisor_id, String(trigger["id"]))
	if last < 0:
		return true
	if bool(trigger.get("once", false)):
		return false
	return state.turn - last >= maxi(1, int(trigger.get("cooldown", 0)))


## Whose event this is: its player, else the owner of its city or unit.
## Turn starts belong to everyone (`viewer`). -1 when it can't be told.
static func event_player(state: GameState, event: Dictionary, viewer: int) -> int:
	if event.has("player"):
		return int(event["player"])
	if event.has("city_id"):
		var city := state.get_city(int(event["city_id"]))
		return city.owner if city != null else -1
	if event.has("unit_id"):
		var unit := state.get_unit(int(event["unit_id"]))
		return unit.owner if unit != null else -1
	if String(event["type"]) == "turn_started":
		return viewer
	return -1


## Builds the message for a match, or {} if its action has nothing to offer
## or no line can be filled.
static func compose(state: GameState, player_id: int, found: Dictionary) -> Dictionary:
	var advisor_id: String = found["advisor"]
	var trigger: Dictionary = found["trigger"]
	var values := event_values(state, player_id, found["event"])
	values["advisor_name"] = AdvisorDefs.display_name(advisor_id)
	var highlight := NO_CELL
	var action: Dictionary = trigger.get("action", {})
	if String(action.get("type", "")) == SUGGEST_CITY_SITE:
		var site := suggest_city_site(state, player_id, advisor_id, found["event"],
			String(action.get("policy", "city_site")))
		if site.is_empty():
			return {}
		values.merge(site["values"])
		highlight = site["cell"]
	var line := pick_line(state, advisor_id, trigger, values)
	if line.is_empty():
		return {}
	var def := AdvisorDefs.get_def(advisor_id)
	return {
		"advisor": advisor_id,
		"name": String(def.get("name", advisor_id)),
		"title": String(def.get("title", "")),
		"portrait": String(def.get("portrait", "")),
		"placeholder_color": String(def.get("placeholder_color", "#8899aa")),
		"trigger": String(trigger["id"]),
		"text": AdvisorText.fill(String(line["text"]), values),
		"tone": String(line.get("tone", "")),
		"line_index": int(line["index"]),
		"highlight": highlight,
	}


## Placeholder values from the event and state: player_name, turn, and when
## the event names them city_name, item, tech.
static func event_values(state: GameState, player_id: int, event: Dictionary) -> Dictionary:
	var values := { "player_name": String(state.players[player_id]["name"]), "turn": state.turn }
	var city := state.get_city(int(event.get("city_id", -1)))
	if city != null:
		values["city_name"] = city.name
	if event.has("item"):
		values["item"] = Production.news_name(String(event["item"]))
	if event.has("tech"):
		values["tech"] = TechDefs.display_name(String(event["tech"]))
	return values


## Ranks sites around the settler (the event's unit, else the player's first
## settler) and lets the advisor's policy choose one. Returns { cell, values }
## with site_where, site_direction, site_distance, site_steps ("1 step",
## "3 steps"), site_terrain; {} if none.
static func suggest_city_site(state: GameState, player_id: int, advisor_id: String, event: Dictionary,
		choice: String) -> Dictionary:
	var settler := state.get_unit(int(event.get("unit_id", -1)))
	if settler == null or settler.owner != player_id or not UnitDefs.can_found_city(settler.type):
		settler = null
		for unit in state.units_of(player_id):
			if UnitDefs.can_found_city(unit.type):
				settler = unit
				break
	if settler == null:
		return {}
	var options := CitySiteScorer.rank(state, player_id, settler.position)
	var picked := AdvisorPolicy.select(AdvisorDefs.policy(advisor_id, choice), options, state.advisor.rng)
	if picked.is_empty():
		return {}
	var cell: Vector2i = picked["cell"]
	var distance := IsoGrid.step_distance(settler.position, cell)
	var values := {
		"site_distance": distance,
		"site_steps": "1 step" if distance == 1 else "%d steps" % distance,
		"site_direction": direction_word(settler.position, cell),
		"site_terrain": String(TerrainDefs.get_def(state.map.get_terrain(cell))["name"]).to_lower(),
	}
	var where := AdvisorDefs.phrase(advisor_id, "site_here" if distance == 0 else "site_away")
	values["site_where"] = AdvisorText.fill(where, values) if where != "" else (
		"here" if distance == 0 else "%d steps to the %s" % [distance, values["site_direction"]])
	return { "cell": cell, "values": values }


## "north-east" etc. from `from` toward `to` on the ground plane.
static func direction_word(from: Vector2i, to: Vector2i) -> String:
	var delta := IsoGrid.ground_position(to) - IsoGrid.ground_position(from)
	if delta.is_zero_approx():
		return ""
	var sector := posmod(roundi(delta.angle() / (PI / 4.0)), 8)
	return DIRECTIONS[sector]


## A line whose placeholders can all be filled, chosen with the advisor's own
## RNG and avoiding the one used last time. { text, tone, index } or {}.
static func pick_line(state: GameState, advisor_id: String, trigger: Dictionary, values: Dictionary) -> Dictionary:
	var lines: Array = trigger.get("lines", [])
	var usable: Array[int] = []
	for i in lines.size():
		if AdvisorText.can_fill(String(lines[i].get("text", "")), values):
			usable.append(i)
	if usable.is_empty():
		return {}
	var last_lines: Dictionary = state.advisor.entry(advisor_id)["last_line"]
	var last := int(last_lines.get(String(trigger["id"]), -1))
	if usable.size() > 1 and usable.has(last):
		usable.erase(last)
	var index := usable[0] if usable.size() == 1 else usable[state.advisor.rng.randi_range(0, usable.size() - 1)]
	var line: Dictionary = lines[index]
	return { "text": String(line["text"]), "tone": String(line.get("tone", "")), "index": index }


static func _trigger(advisor_id: String, trigger_id: String) -> Dictionary:
	for trigger: Dictionary in AdvisorDefs.triggers(advisor_id):
		if String(trigger["id"]) == trigger_id:
			return trigger
	return {}


static func _has_match(found: Array, advisor_id: String, trigger_id: String) -> bool:
	for entry: Dictionary in found:
		if entry["advisor"] == advisor_id and String(entry["trigger"]["id"]) == trigger_id:
			return true
	return false


## Matches that didn't get to speak wait (if their trigger allows) for a
## later call; the one that spoke stops waiting.
static func _carry_over(state: GameState, matches: Array[Dictionary], spoken: Dictionary) -> void:
	var advisor := state.advisor
	var kept: Array = []
	for entry: Dictionary in advisor.pending:
		if spoken.is_empty() or entry["advisor"] != spoken["advisor"] or entry["trigger"] != spoken["trigger"]:
			kept.append(entry)
	advisor.pending = kept
	for found in matches:
		var advisor_id: String = found["advisor"]
		var trigger: Dictionary = found["trigger"]
		var turns := int(trigger.get("carry_over", 0))
		var trigger_id := String(trigger["id"])
		if turns <= 0 or (not spoken.is_empty() and spoken["advisor"] == advisor_id and spoken["trigger"] == trigger_id):
			continue
		if _has_match(_pending_as_matches(advisor.pending), advisor_id, trigger_id):
			continue
		advisor.pending.append({ "advisor": advisor_id, "trigger": trigger_id,
			"event": AdvisorState.plain_event(found["event"]), "until": state.turn + turns })


static func _pending_as_matches(pending: Array) -> Array:
	var result: Array = []
	for entry: Dictionary in pending:
		result.append({ "advisor": entry["advisor"], "trigger": { "id": entry["trigger"] } })
	return result


## Marks the trigger as spoken, counts the message, and logs the advice.
static func _remember(state: GameState, found: Dictionary, message: Dictionary) -> void:
	var advisor := state.advisor
	var advisor_id: String = found["advisor"]
	var trigger_id: String = message["trigger"]
	var entry := advisor.entry(advisor_id)
	entry["fired"][trigger_id] = state.turn
	entry["last_line"][trigger_id] = int(message["line_index"])
	if advisor.messages_turn != state.turn:
		advisor.messages_turn = state.turn
		advisor.messages_count = 0
	advisor.messages_count += 1
	var record := { "turn": state.turn, "advisor": advisor_id, "trigger": trigger_id, "text": message["text"] }
	var cell: Vector2i = message["highlight"]
	if cell != NO_CELL:
		for old: Dictionary in advisor.advice_log:
			if String(old.get("outcome", "")) == "pending":
				old["outcome"] = "superseded"
		record["suggested"] = [cell.x, cell.y]
		record["outcome"] = "pending"
	advisor.advice_log.append(record)
	var limit := AdvisorDefs.log_limit()
	if limit > 0 and advisor.advice_log.size() > limit:
		advisor.advice_log = advisor.advice_log.slice(advisor.advice_log.size() - limit)


## Quietly notes whether pending city-site advice was followed when the
## player founds a city. Runs even with the advisor off.
static func _record_outcomes(state: GameState, player_id: int, events: Array[Dictionary]) -> void:
	for event in events:
		if String(event["type"]) != "city_founded":
			continue
		var city := state.get_city(int(event["city_id"]))
		if city == null or city.owner != player_id:
			continue
		for record: Dictionary in state.advisor.advice_log:
			if String(record.get("outcome", "")) != "pending":
				continue
			var suggested := Vector2i(int(record["suggested"][0]), int(record["suggested"][1]))
			record["outcome"] = "followed" if suggested == city.position else "elsewhere"
			record["actual"] = [city.position.x, city.position.y]
			record["distance"] = IsoGrid.step_distance(suggested, city.position)


## The advice log entries, oldest first (for tests and later tuning).
static func advice_log(state: GameState) -> Array:
	return state.advisor.advice_log
