class_name SpriteLibrary
extends RefCounted
## Resolves sprite keys from data definitions to textures.
## Drop `assets/sprites/<key>.png` into the project to replace a placeholder;
## when no image exists, get_texture() returns null and the caller draws
## a placeholder from PlaceholderArt instead.

const SPRITE_DIR := "res://assets/sprites/"

static var _cache: Dictionary = {}


static func get_texture(key: String) -> Texture2D:
	if key.is_empty():
		return null
	if not _cache.has(key):
		var path := SPRITE_DIR + key + ".png"
		_cache[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[key]
