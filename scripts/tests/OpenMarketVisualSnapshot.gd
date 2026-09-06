extends SceneTree

## 게임 종료 오픈마켓의 비공개 출품 화면을 16:9 기준으로 렌더링합니다.

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var configs: Array[Dictionary] = [
		{"name": "에코 히어로 1", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.webp"},
		{"name": "태양 여우 솔", "is_ai": false},
		{"name": "숲의 수호자", "is_ai": false},
		{"name": "물방울 정령", "is_ai": false}
	]
	main._on_start_game_requested(configs, 600)
	await create_timer(0.2).timeout
	var game_manager: Node = root.get_node("GameManager")
	for item_id_variant in game_manager.ITEM_DEFINITIONS.keys():
		var item_id := str(item_id_variant)
		game_manager.players[0]["inventory"][item_id] = 1 + (int(item_id.hash()) & 1)
	var quiz = main.find_child("QuizModal", true, false)
	quiz.display_quiz(1, root.get_node("QuizDatabase").get_random_quiz())
	quiz.spectator_guess_submitted = true
	game_manager._start_open_market_phase()
	if quiz.visible:
		push_error("오픈마켓 전환 시 관전 퀴즈가 닫혀야 합니다.")
		quit(1)
		return
	await create_timer(0.4).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/open_market_preview.png")
	if error == OK:
		print("[PASS] Open market preview captured")
		quit(0)
	else:
		push_error("오픈마켓 미리보기 저장 실패: %s" % error)
		quit(1)
