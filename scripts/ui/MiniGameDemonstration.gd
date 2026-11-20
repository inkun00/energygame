extends HBoxContainer

const INPUT = preload("res://scripts/minigames/MiniGameInput.gd")
const UI = preload("res://scripts/ui/CommercialUI.gd")

var finished := false
var hint := ""
var _keycaps: Dictionary = {}
var _light_until: Dictionary = {}
var _idle_style := UI.padded_panel(Color("143b47"), Color("388399"), 5, 7)
var _pressed_style := UI.padded_panel(UI.GOLD, UI.GOLD_DARK, 5, 7)

func begin(game_id: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_keycaps.clear()
	_light_until.clear()
	finished = false
	hint = ""
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	var bindings: Dictionary = INPUT.ACTION_KEYS[game_id]
	for key in bindings:
		var cap := Label.new()
		var action := str(bindings[key])
		cap.text = action if INPUT.uses_touch() else "%s %s" % [OS.get_keycode_string(key), action]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 16)
		cap.add_theme_stylebox_override("normal", _idle_style)
		add_child(cap)
		_keycaps[key] = cap
	show()

func advance(arcade: Node, tick: StringName, delta: float, elapsed: float) -> void:
	var instruction: Dictionary = arcade.call("tutorial_demo_step", elapsed)
	hint = str(instruction["hint"])
	finished = bool(instruction.get("done", false))
	var keys: Array = instruction.get("keys", [])
	for key in keys:
		_light_until[key] = elapsed + 0.35
	for key in _keycaps:
		var cap: Label = _keycaps[key]
		var lit := not finished and elapsed < float(_light_until.get(key, 0))
		var style := _pressed_style if lit else _idle_style
		if cap.get_theme_stylebox("normal") != style:
			cap.add_theme_stylebox_override("normal", style)
			cap.add_theme_color_override("font_color", UI.INK if lit else UI.TEXT)
	if not finished:
		INPUT.simulate_demonstration(arcade, tick, delta, keys)
