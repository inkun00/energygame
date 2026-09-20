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
	root.get_node("GameManager")._start_minigame(0, "battery_relay")
	await create_timer(0.75).timeout
	var image := root.get_texture().get_image()
	var first_error := image.save_png("res://.godot/battery_shuttle_sunny.png")
	var modal := root.find_child("MiniGameModal", true, false)
	if modal and modal.battery_arcade:
		var shuttle = modal.battery_arcade
		shuttle.elapsed = 5.5
		shuttle.battery_units = 3
		shuttle.cargo = 2
		shuttle.hero_x = 2.6
		shuttle._update_visuals()
	await create_timer(0.12).timeout
	image = root.get_texture().get_image()
	var second_error := image.save_png("res://.godot/battery_shuttle_cloudy.png")
	var success := first_error == OK and second_error == OK
	print("[BatteryVisual] %s" % ("PASS" if success else "FAIL"))
	quit(0 if success else 1)
