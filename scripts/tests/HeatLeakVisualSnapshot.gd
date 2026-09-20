extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var players: Array[Dictionary] = [
		{"name": "캡틴 에코 · 나", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(players, 600)
	await create_timer(0.35).timeout
	root.get_node("GameManager")._start_minigame(0, "heat_leak")
	await create_timer(0.75).timeout
	var image := root.get_texture().get_image()
	var initial_error := image.save_png("res://.godot/heat_leak_start.png")
	var modal := root.find_child("MiniGameModal", true, false)
	if modal and modal.heat_arcade:
		var game = modal.heat_arcade
		for window in game.windows:
			if bool(window["open"]):
				game.hero_x = float(window["x"])
				game.hero.position.x = game.hero_x
				game._try_close()
				break
	await create_timer(0.20).timeout
	image = root.get_texture().get_image()
	var closed_error := image.save_png("res://.godot/heat_leak_closed.png")
	var success := initial_error == OK and closed_error == OK
	print("[HeatLeakVisual] %s" % ("PASS" if success else "FAIL"))
	quit(0 if success else 1)
