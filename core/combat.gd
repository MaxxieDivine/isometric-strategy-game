class_name Combat
extends RefCounted
## Civ II style combat. Each round the attacker wins with probability
## A / (A + D) and the loser of the round takes 1 damage, until one side
## reaches 0 HP and is destroyed. Defense is multiplied by terrain
## (terrain.json), fortification (combat.json) and City Walls vs land units
## (buildings.json, or the Great Wall vs barbarians; see Effects). All
## randomness comes from GameState.rng.

const PATH := "res://data/combat.json"

static var _rules: Dictionary = {}


# --- Data ---------------------------------------------------------------------

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = DataLoader.load_dict(PATH)
	return _rules


static func max_hp() -> int:
	return int(rules().get("max_hp", 10))


static func fortified_percent() -> int:
	return int(rules().get("fortified_defense_percent", 50))


static func heal_in_field() -> int:
	return int(rules().get("heal_in_field", 1))


static func heal_in_city() -> int:
	return int(rules().get("heal_in_city", 3))


## Attacks with lower win odds than this need a confirming click.
static func confirm_below_odds() -> float:
	return float(rules().get("confirm_below_odds", 0.5))


# --- Strength -----------------------------------------------------------------

static func can_attack(unit: UnitState) -> bool:
	return attack_strength(unit) > 0.0


static func attack_strength(unit: UnitState) -> float:
	return float(UnitDefs.get_def(unit.type).get("attack", 0))


## Defense of `defender` where it stands, against a unit of `attacker_type`
## owned by `attacker_owner` (-1 = unknown; the Great Wall only counts
## against barbarians).
static func defense_strength(state: GameState, defender: UnitState, attacker_type: String, attacker_owner: int = -1) -> float:
	var strength := float(UnitDefs.get_def(defender.type).get("defense", 0))
	strength *= 1.0 + TerrainDefs.defense_percent(state.map.get_terrain(defender.position)) / 100.0
	if defender.fortified:
		strength *= 1.0 + fortified_percent() / 100.0
	var city := state.city_at(defender.position)
	if city != null and city.owner == defender.owner and UnitDefs.domain(attacker_type) == "land":
		strength *= 1.0 + Effects.defense_percent(state, city, attacker_owner) / 100.0
	return strength


## The unit on `cell` that defends against `attacker`: the best defense
## strength times HP (lowest id on a tie). Null if no enemy is there.
static func best_defender(state: GameState, cell: Vector2i, attacker: UnitState) -> UnitState:
	var best: UnitState = null
	var best_score := -1.0
	for unit in state.enemy_units_at(cell, attacker.owner):
		var score := defense_strength(state, unit, attacker.type, attacker.owner) * unit.hp
		if score > best_score:
			best = unit
			best_score = score
	return best


# --- Odds ---------------------------------------------------------------------

## Chance one round goes to the attacker.
static func round_odds(attack: float, defense: float) -> float:
	if attack <= 0.0:
		return 0.0
	if defense <= 0.0:
		return 1.0
	return attack / (attack + defense)


## Exact chance the attacker wins the whole fight, from the same round rule.
static func odds(attack: float, defense: float, attacker_hp: int, defender_hp: int) -> float:
	if attacker_hp <= 0:
		return 0.0
	if defender_hp <= 0:
		return 1.0
	var p := round_odds(attack, defense)
	# win[a][d]: chance to win with a HP left for the attacker and d for the defender.
	var win: Array[PackedFloat64Array] = []
	for a in attacker_hp + 1:
		var row := PackedFloat64Array()
		row.resize(defender_hp + 1)
		for d in defender_hp + 1:
			if a == 0:
				row[d] = 0.0
			elif d == 0:
				row[d] = 1.0
			else:
				row[d] = p * row[d - 1] + (1.0 - p) * win[a - 1][d]
		win.append(row)
	return win[attacker_hp][defender_hp]


static func win_odds(state: GameState, attacker: UnitState, defender: UnitState) -> float:
	return odds(attack_strength(attacker), defense_strength(state, defender, attacker.type, attacker.owner), attacker.hp, defender.hp)


# --- Resolution -----------------------------------------------------------------

## Fights it out, removes the loser from the state, and spends the
## attacker's moves (it stays on its tile). Returns a "combat" event:
## { attacker_id, defender_id, attacker_owner, defender_owner, attacker_type,
##   defender_type, from, to, winner ("attacker" | "defender"),
##   attacker_hp, defender_hp (after), attacker_start_hp, defender_start_hp, odds }
static func resolve(state: GameState, attacker: UnitState, defender: UnitState) -> Dictionary:
	var a := attack_strength(attacker)
	var d := defense_strength(state, defender, attacker.type, attacker.owner)
	var event := {
		"type": "combat",
		"attacker_id": attacker.id, "defender_id": defender.id,
		"attacker_owner": attacker.owner, "defender_owner": defender.owner,
		"attacker_type": attacker.type, "defender_type": defender.type,
		"from": attacker.position, "to": defender.position,
		"attacker_start_hp": attacker.hp, "defender_start_hp": defender.hp,
		"odds": odds(a, d, attacker.hp, defender.hp),
	}
	var p := round_odds(a, d)
	while attacker.hp > 0 and defender.hp > 0:
		if state.rng.randf() < p:
			defender.hp -= 1
		else:
			attacker.hp -= 1
	attacker.moves_left = 0
	attacker.moved = true
	attacker.fortified = false
	attacker.clear_orders()
	event["attacker_hp"] = attacker.hp
	event["defender_hp"] = defender.hp
	if defender.hp <= 0:
		event["winner"] = "attacker"
		state.remove_unit(defender.id)
	else:
		event["winner"] = "defender"
		state.remove_unit(attacker.id)
	return event


# --- Healing ------------------------------------------------------------------

## Start-of-turn healing: more inside an own city, a little in the field if
## the unit stayed put last turn.
static func heal(state: GameState, unit: UnitState) -> void:
	var city := state.city_at(unit.position)
	if city != null and city.owner == unit.owner:
		unit.hp = mini(max_hp(), unit.hp + heal_in_city())
	elif not unit.moved:
		unit.hp = mini(max_hp(), unit.hp + heal_in_field())
