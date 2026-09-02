extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "에코 히어로 1", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.png"},
		{"name": "포포 (AI)", "is_ai": true},
		{"name": "퐁이 (AI)", "is_ai": true},
		{"name": "솔 (AI)", "is_ai": true}
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.5).timeout
	var game_manager: Node = root.get_node("GameManager")
	game_manager.players[0]["position"] = BoardGrid.LAST_TILE_INDEX
	game_manager._handle_lap_completion(0)
	await create_timer(0.4).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/lap_reward_preview.png")
	if error == OK:
		print("[PASS] Timed lap reward preview captured")
		quit(0)
	else:
		push_error("완주 보상 미리보기 저장 실패: %s" % error)
		quit(1)
