extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp", "char_color": Color("#49d97b")},
		{"name": "태양 여우 솔 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.webp", "char_color": Color("#ffd24a")},
		{"name": "물방울 정령 포포 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.webp", "char_color": Color("#49bfff")},
		{"name": "번개새 피카 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.webp", "char_color": Color("#ff9d3d")},
	]
	main._on_start_game_requested(configs)
	await create_timer(2.1).timeout
	# 건설 가이드의 충족/부족 상태를 한 화면에서 비교할 수 있는 예시 재료를 표시합니다.
	var game_manager: Node = root.get_node("GameManager")
	game_manager.players[0]["inventory"]["solar_panel"] = 2
	game_manager.players[0]["inventory"]["battery"] = 1
	game_manager.player_inventory_changed.emit(0, game_manager.players[0]["inventory"].duplicate(true))
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/board_preview.png")
	if error == OK:
		print("[PASS] Board preview captured")
		quit(0)
	else:
		push_error("보드 미리보기 저장 실패: %s" % error)
		quit(1)
