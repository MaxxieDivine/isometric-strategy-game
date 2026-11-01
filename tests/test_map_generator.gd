extends SceneTree
## Headless tests for MapGenerator.
## Run: godot --headless --path . --script res://tests/test_map_generator.gd

const WIDTH := 40
const HEIGHT := 80
const SEEDS := 40

var _failures := 0


func _initialize() -> void:
	_test_same_seed_same_map()
	_test_different_seeds_differ()
	_test_border_is_ocean()
	_test_continent_count()
	_test_round_trip()
	_print_terrain_stats()
	if _failures == 0:
		print("All map generator tests passed.")
	else:
		printerr("%d check(s) failed." % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _test_same_seed_same_map() -> void:
	var a := MapGenerator.generate(WIDTH, HEIGHT, 12345)
	var b := MapGenerator.generate(WIDTH, HEIGHT, 12345)
	_check(a.terrain == b.terrain, "same seed should produce the same map")
	_check(a.generation_seed == 12345, "map should store its seed")


func _test_different_seeds_differ() -> void:
	var a := MapGenerator.generate(WIDTH, HEIGHT, 1)
	var b := MapGenerator.generate(WIDTH, HEIGHT, 2)
	_check(a.terrain != b.terrain, "different seeds should produce different maps")


func _test_border_is_ocean() -> void:
	for s in SEEDS:
		var map := MapGenerator.generate(WIDTH, HEIGHT, s)
		for y in HEIGHT:
			for x in WIDTH:
				if x == 0 or x == WIDTH - 1 or y < 2 or y >= HEIGHT - 2:
					if map.get_terrain(Vector2i(x, y)) != "ocean":
						_check(false, "seed %d: border cell (%d, %d) is land" % [s, x, y])
						return


func _test_continent_count() -> void:
	for s in SEEDS:
		var map := MapGenerator.generate(WIDTH, HEIGHT, s)
		var count := MapGenerator.count_continents(map)
		_check(count >= 2 and count <= 4, "seed %d: %d continents, expected 2-4" % [s, count])


func _test_round_trip() -> void:
	var map := MapGenerator.generate(WIDTH, HEIGHT, 777)
	var json := JSON.stringify(map.to_dict())
	var loaded := MapState.from_dict(JSON.parse_string(json))
	_check(loaded.terrain == map.terrain, "terrain should survive a JSON round trip")
	_check(loaded.generation_seed == 777, "seed should survive a JSON round trip")
	_check(loaded.width == WIDTH and loaded.height == HEIGHT, "size should survive a JSON round trip")


func _print_terrain_stats() -> void:
	var counts := {}
	var total := 0
	for s in SEEDS:
		var map := MapGenerator.generate(WIDTH, HEIGHT, s)
		for id in map.terrain:
			counts[id] = counts.get(id, 0) + 1
			total += 1
	var land: int = total - counts.get("ocean", 0)
	var parts: PackedStringArray = ["land %.0f%%" % (100.0 * land / total)]
	for id: String in counts:
		if id != "ocean":
			parts.append("%s %.0f%%" % [id, 100.0 * counts[id] / land])
	print("Terrain mix over %d seeds: %s" % [SEEDS, ", ".join(parts)])
