extends SceneTree

## 이동 중 자동 추적·확대 구도를 눈으로 점검하기 위한 수동 스냅샷 테스트입니다.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	seed(20260828)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# 로비 전환 애니메이션에 의존하지 않고, 보드가 준비된 뒤 이동 장면을 촬영합니다.
	var configs: Array[Dictionary] = [
		{"name": "캡틴 에코", "is_ai": false, "char_icon": "res://assets/characters/eco_roster/captain_eco.png", "char_color": Color("#49d97b")},
		{"name": "태양 여우 솔 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/solar_fox_sol.png", "char_color": Color("#ffd24a")},
		{"name": "물방울 정령 포포 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/water_popo.png", "char_color": Color("#49bfff")},
		{"name": "번개새 피카 (AI)", "is_ai": true, "char_icon": "res://assets/characters/eco_roster/lightning_bird_pika.png", "char_color": Color("#ff9d3d")},
	]
	main._on_start_game_requested(configs)
	# start_board_game이 첫 턴을 여는 0.4초 타이머를 완료할 때까지 기다립니다.
	await create_timer(0.55).timeout

	var game_manager = root.get_node("GameManager")
	game_manager.execute_roll_dice(0)
	# 주사위 공개 뒤 말이 이동하는 중인 프레임을 캡처합니다.
	await create_timer(1.62).timeout
	var game_board = main.get_node("GameBoard")
	assert(game_board.camera_follow_active)
	assert(game_board.camera_distance <= game_board.CAMERA_FOLLOW_DISTANCE + 0.1)

	var image := root.get_texture().get_image()
	var error := image.save_png("res://.godot/movement_preview.png")
	if error == OK:
		print("[PASS] Movement preview captured")
		quit(0)
	else:
		push_error("이동 미리보기 저장 실패: %s" % error)
		quit(1)
