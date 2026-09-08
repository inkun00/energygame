extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true},
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.4).timeout
	root.get_node("GameManager")._start_minigame(0, "grid_balance")
	await create_timer(0.45).timeout
	var grid_viewport := root.find_child("SmartGridViewport", true, false)
	if is_instance_valid(grid_viewport):
		var grid_game = grid_viewport.get_parent()
		grid_game.demand_target = 100.0
		grid_game.current_event = "전기 버스 동시 충전  +30 MW"
	await create_timer(1.2).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/smart_grid_preview.png")
	print("[SmartGridVisual] %s" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
