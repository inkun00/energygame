extends SceneTree
func _initialize() -> void:
	call_deferred("_capture")
func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false},
		{"name": "태양 여우 솔", "is_ai": true},
		{"name": "물방울 포포", "is_ai": true},
		{"name": "바람 토끼 보리", "is_ai": true}
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.4).timeout
	root.get_node("GameManager")._start_minigame(0, "solar_align")
	await create_timer(1.0).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/minigame_preview.png")
	print("[MiniGameVisual] %s" % ("PASS" if error == OK else "FAIL"))
	quit(0 if error == OK else 1)
