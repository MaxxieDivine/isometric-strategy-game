class_name UnitsLayer
extends Node2D
## Keeps one UnitView per unit in sync with GameState.
## Only the top unit of each stack is drawn (the selected one, if present).

var _views: Dictionary = {}  # unit id -> UnitView


func _ready() -> void:
	y_sort_enabled = true


func clear_units() -> void:
	for view: UnitView in _views.values():
		view.queue_free()
	_views.clear()


func sync(state: GameState, selected_id: int, map_view: MapView) -> void:
	var alive := {}
	var stacks := {}  # cell -> Array of unit ids
	for unit in state.units:
		alive[unit.id] = true
		(stacks.get_or_add(unit.position, []) as Array).append(unit.id)
		var view: UnitView = _views.get(unit.id)
		if view == null:
			view = UnitView.new()
			view.setup(unit.id, UnitDefs.get_def(unit.type), Color.html(state.players[unit.owner]["color"]))
			view.position = map_view.grid_to_world(unit.position)
			add_child(view)
			_views[unit.id] = view
		view.selected = unit.id == selected_id

	for id: int in _views.keys():
		if not alive.has(id):
			(_views[id] as UnitView).queue_free()
			_views.erase(id)

	for cell: Vector2i in stacks:
		var ids: Array = stacks[cell]
		var top: int = selected_id if ids.has(selected_id) else ids.min()
		for id: int in ids:
			var view: UnitView = _views[id]
			view.visible = id == top or view.is_walking()
			view.stack_count = ids.size() if id == top else 1


func walk(unit_id: int, world_pos: Vector2) -> void:
	var view: UnitView = _views.get(unit_id)
	if view != null:
		view.walk_to(world_pos)
