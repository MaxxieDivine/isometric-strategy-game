class_name UnitsLayer
extends Node2D
## Keeps one UnitView per unit in sync with GameState.
## Only the top unit of each stack is drawn (the selected one, if present).
## Other players' units are drawn only on tiles the viewer can see.

var _views: Dictionary = {}  # unit id -> UnitView


func _ready() -> void:
	y_sort_enabled = true


func clear_units() -> void:
	for view: UnitView in _views.values():
		view.queue_free()
	_views.clear()


## `visible_tiles`: 1 per tile the viewer can see (Fog.compute_visible).
func sync(state: GameState, selected_id: int, map_view: MapView, viewer: int, visible_tiles: PackedByteArray) -> void:
	var alive := {}
	var stacks := {}  # cell -> Array of unit ids
	for unit in state.units:
		alive[unit.id] = true
		(stacks.get_or_add(unit.position, []) as Array).append(unit.id)
		var view: UnitView = _views.get(unit.id)
		var world := map_view.grid_to_world(unit.position)
		if view == null:
			view = UnitView.new()
			view.setup(unit.id, UnitDefs.get_def(unit.type), Color.html(state.players[unit.owner]["color"]), Combat.max_hp())
			view.position = world
			add_child(view)
			_views[unit.id] = view
		elif not view.is_busy():
			# Moves the view never animated (e.g. out of sight) snap into place.
			view.position = world
		view.selected = unit.id == selected_id
		view.set_status(unit.hp, unit.fortified)

	for id: int in _views.keys():
		if not alive.has(id):
			(_views[id] as UnitView).queue_free()
			_views.erase(id)

	for cell: Vector2i in stacks:
		var ids: Array = stacks[cell]
		var top: int = selected_id if ids.has(selected_id) else ids.min()
		var seen := visible_tiles.is_empty() or visible_tiles[IsoGrid.index_of(cell, state.map.width)] == 1
		for id: int in ids:
			var view: UnitView = _views[id]
			var own := state.get_unit(id).owner == viewer
			view.visible = (id == top or view.is_walking()) and (own or seen)
			view.stack_count = ids.size() if id == top else 1


func walk(unit_id: int, world_pos: Vector2) -> void:
	var view: UnitView = _views.get(unit_id)
	if view != null:
		view.walk_to(world_pos)


## Plays a "combat" event (see Combat.resolve). The loser's view is handed
## over to its death animation, which frees it.
func play_combat(event: Dictionary, map_view: MapView) -> void:
	var attacker: UnitView = _views.get(event["attacker_id"])
	var defender: UnitView = _views.get(event["defender_id"])
	var attacker_won: bool = event["winner"] == "attacker"
	var delay := attacker.pending_time() if attacker != null else 0.0
	if attacker != null:
		attacker.visible = true
		attacker.play_fight(true, map_view.grid_to_world(event["to"]), delay, event["attacker_hp"], not attacker_won)
		if not attacker_won:
			_views.erase(event["attacker_id"])
	if defender != null:
		defender.visible = true
		defender.play_fight(false, Vector2.ZERO, delay, event["defender_hp"], attacker_won)
		if attacker_won:
			_views.erase(event["defender_id"])
