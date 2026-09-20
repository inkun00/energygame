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
	await create_timer(0.4).timeout
	root.get_node("GameManager")._start_minigame(0, "hydro_gate")
	await create_timer(0.8).timeout
	var modal := root.get_node("GameManager").get_tree().root.find_child("MiniGameModal", true, false)
	if modal and modal.hydro_arcade:
		modal.hydro_arcade.water_level = 84.0
		modal.hydro_arcade.hero_floor_index = 2
		modal.hydro_arcade.hero_x = modal.hydro_arcade.LEVER_X[2]
		modal.hydro_arcade.hero_y = modal.hydro_arcade.platform_height(2)
		modal.hydro_arcade._update_station()
		for tap in range(7):
			modal.hydro_arcade._tap_selected_gate()
	await create_timer(0.25).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/hydro_gate_preview.png")
	print("[HydroVisual] %s" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
