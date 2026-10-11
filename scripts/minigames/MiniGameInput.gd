extends RefCounted
class_name MiniGameInput

## Keyboard and touch buttons share the same gameplay conditions.
static var touch_keys: Dictionary = {}

static func canonical_key(key: int) -> int:
	match key:
		KEY_LEFT: return KEY_A
		KEY_RIGHT: return KEY_D
		KEY_UP: return KEY_W
		KEY_DOWN: return KEY_S
	return key

static func is_pressed(key: int) -> bool:
	return Input.is_key_pressed(key) or bool(touch_keys.get(canonical_key(key), false))

static func set_touch(key: int, down: bool) -> void:
	touch_keys[canonical_key(key)] = down

static func release_all() -> void:
	touch_keys.clear()
