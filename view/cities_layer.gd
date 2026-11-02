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
		view.set_buildings(_building_entries(city))
		view.set_wonders(_wonder_entries(state, city))
	for id: int in _views.keys():
		if not alive.has(id):
			(_views[id] as CityView).queue_free()
			_views.erase(id)


func _wonder_entries(state: GameState, city: CityState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id in Wonders.in_city(state, city):
		var def := WonderDefs.get_def(id)
		entries.append({
			"id": id,
			"sprite": String(def.get("sprite", "")),
			"color": Color.html(String(def.get("placeholder_color", "#cccccc"))),
			"letter": String(def.get("letter", "?")),
		})
	return entries


func _building_entries(city: CityState) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id in city.buildings:
		var def := BuildingDefs.get_def(id)
		entries.append({
			"id": id,
			"sprite": String(def.get("sprite", "")),
			"color": Color.html(String(def.get("placeholder_color", "#cccccc"))),
			"letter": String(def.get("letter", "?")),
		})
	return entries
