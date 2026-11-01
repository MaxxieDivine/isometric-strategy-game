class_name CitiesLayer
extends Node2D
## Keeps one CityView per city in sync with GameState.

var _views: Dictionary = {}  # city id -> CityView


func clear_cities() -> void:
	for view: CityView in _views.values():
		view.queue_free()
	_views.clear()


func sync(state: GameState, map_view: MapView) -> void:
	var alive := {}
	var sprite_key := String(CityRules.rules().get("sprite", ""))
	for city in state.cities:
		alive[city.id] = true
		var view: CityView = _views.get(city.id)
		if view == null:
			view = CityView.new()
			view.setup(city.id, city.name, Color.html(state.players[city.owner]["color"]), sprite_key)
			view.position = map_view.grid_to_world(city.position)
			add_child(view)
			_views[city.id] = view
		view.set_city_size(city.size)
	for id: int in _views.keys():
		if not alive.has(id):
			(_views[id] as CityView).queue_free()
			_views.erase(id)
