extends RefCounted
class_name MiniGameInput

## Keyboard and touch buttons share the same gameplay conditions.
static var touch_keys: Dictionary = {}
static var _demonstration_keys: Variant = null

static func canonical_key(key: int) -> int:
	match key:
		KEY_LEFT: return KEY_A
		KEY_RIGHT: return KEY_D
		KEY_UP: return KEY_W
		KEY_DOWN: return KEY_S
	return key

static func is_pressed(key: int) -> bool:
	if _demonstration_keys != null:
		return canonical_key(key) in _demonstration_keys
	return Input.is_key_pressed(key) or bool(touch_keys.get(canonical_key(key), false))

static func horizontal_axis() -> float:
	return 0.0 if _demonstration_keys != null else Input.get_axis("ui_left", "ui_right")

## The private demonstration supplies input only during its own simulation step.
static func simulate_demonstration(arcade: Node, tick: StringName, delta: float, keys: Array) -> void:
	_demonstration_keys = keys
	arcade.call(tick, delta)
	_demonstration_keys = null

static func set_touch(key: int, down: bool) -> void:
	touch_keys[canonical_key(key)] = down

static func release_all() -> void:
	touch_keys.clear()

## Touch labels and the visible hints use the same per-game bindings.
const ACTION_KEYS := {
	"solar_align": {KEY_A: "←", KEY_D: "→", KEY_SPACE: "점프"},
	"wind_rhythm": {KEY_A: "←", KEY_D: "→", KEY_SPACE: "제동"},
	"grid_balance": {KEY_W: "늘리기", KEY_S: "줄이기"},
	"standby_hunt": {KEY_A: "←", KEY_D: "→", KEY_W: "점프", KEY_SPACE: "뽑기"},
	"hydro_gate": {KEY_A: "←", KEY_D: "→", KEY_W: "점프", KEY_SPACE: "열기", KEY_E: "닫기"},
	"energy_sort": {KEY_A: "←", KEY_D: "→"},
	"battery_relay": {KEY_A: "←", KEY_D: "→"},
	"eco_commute": {KEY_A: "후진", KEY_D: "전진", KEY_S: "정차", KEY_SPACE: "태우기"},
	"heat_leak": {KEY_A: "←", KEY_D: "→", KEY_SPACE: "닫기"}
}
const KEY_CODES := {"A": KEY_A, "D": KEY_D, "W": KEY_W, "S": KEY_S, "E": KEY_E, "SPACE": KEY_SPACE}
static var touch_hints: Dictionary = {}
static var key_words := RegEx.create_from_string("(?<![a-zA-Z])(?:SPACE|Space|A|D|W|S|E)(?![a-zA-Z])")

static func uses_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or Input.emulate_touch_from_mouse

static func hint(game: String, message: String) -> String:
	if not uses_touch() or not ACTION_KEYS.has(game):
		return message
	if not touch_hints.has(game):
		touch_hints[game] = {}
	var cached: Dictionary = touch_hints[game]
	if cached.has(message):
		return cached[message]
	var bindings: Dictionary = ACTION_KEYS[game]
	var display := message.replace(" (← / →)", "").replace(" (W / ↑)", "")
	if game == "eco_commute":
		display = display.replace("D 전진 / A 후진", "D / A")
	for alias in [" / ←", " / →", " / ↑", " / ↓", "/←", "/→", "/↑", "/↓", " 또는 ↑/↓"]:
		display = display.replace(alias, "")
	var matches := key_words.search_all(display)
	for i in range(matches.size() - 1, -1, -1):
		var hit := matches[i]
		var code: int = KEY_CODES[hit.get_string().to_upper()]
		if bindings.has(code):
			display = display.left(hit.get_start()) + str(bindings[code]) + display.substr(hit.get_end())
	for word in bindings.values():
		display = display.replace("%s %s" % [word, word], str(word))
	cached[message] = display
	return display
