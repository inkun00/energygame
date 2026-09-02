extends SceneTree

## AutomatedClickTest: 실제 유저 마우스 클릭 플로우 자동 검증기

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("========================================")
	print("  STARTING AUTOMATED CLICK FLOW TEST    ")
	print("========================================")
	
	# 1. Main 씬 생성
	var main_scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main_scene)
	await process_frame
	await create_timer(0.3).timeout
	
	var lobby: Variant = main_scene.get_node("LobbyUI")
	var game_board: Variant = main_scene.get_node("GameBoard")
	
	_expect(lobby != null and lobby.visible, "로비 UI가 초기 상태에서 보여야 합니다.")
	_expect(game_board != null and not game_board.visible, "인게임 보드는 초기 상태에서 숨겨져 있어야 합니다.")
	_expect(not game_board.ui_layer.visible, "인게임 UILayer는 로비 상태에서 비활성화되어야 합니다.")
	_expect(not game_board.modals_layer.visible, "인게임 ModalsLayer는 로비 상태에서 비활성화되어야 합니다.")
	_expect(lobby.char_option_button.visible and lobby.char_option_button.item_count == 9, "로비에서 9명의 캐릭터를 드롭다운으로 선택할 수 있어야 합니다.")
	
	print("[STEP 1 PASS] 로비 초기 뷰 및 인게임 레이어 완전 격리 검증 완료")
	
	# 2. 로비에서 캐릭터 선택 버튼 클릭 시뮬레이션
	var char_buttons = lobby._character_buttons
	_expect(char_buttons.size() == 9, "스파키를 제외한 9명의 캐릭터 선택 버튼이 생성되어야 합니다.")
	
	# 2번째 캐릭터(포포) 클릭
	char_buttons[1].emit_signal("pressed")
	await process_frame
	_expect(lobby.char_option_button.selected == 1, "2번째 캐릭터(포포)가 선택되어야 합니다.")
	print("[STEP 2 PASS] 로비 캐릭터 버튼 클릭 인터랙션 검증 완료")
	
	# 3. '모험 시작' 버튼 클릭 시뮬레이션
	var start_button = lobby.local_start_button
	_expect(start_button != null and start_button.is_visible_in_tree() and not start_button.disabled, "모험 시작 버튼이 클릭 가능한 상태여야 합니다.")
	
	start_button.emit_signal("pressed")
	await process_frame
	_expect(lobby.opening_story.visible and lobby.opening_skip_button.visible, "시작 버튼을 누르면 오프닝과 즉시 시작 버튼이 표시되어야 합니다.")
	lobby._skip_opening_story()
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	
	_expect(not lobby.visible, "게임 시작 후 로비 UI가 숨겨져야 합니다.")
	_expect(game_board.visible, "게임 시작 후 게임 보드가 나타나야 합니다.")
	_expect(game_board.ui_layer.visible, "게임 시작 후 UILayer가 활성화되어야 합니다.")
	_expect(game_board.modals_layer.visible, "게임 시작 후 ModalsLayer가 활성화되어야 합니다.")
	_expect(game_board.player_pawns.size() == 4, "4명의 3D 플레이어 말이 생성되어야 합니다.")
	print("[STEP 3 PASS] 모험 시작 버튼 클릭 및 3D 게임 보드 전환 검증 완료")
	
	# 4. 인게임 1번째 플레이어(내 턴) 중앙 주사위 클릭 시뮬레이션
	var hud_ctrl: Variant = game_board.hud
	_expect(hud_ctrl != null, "HUD 컨트롤러가 유효해야 합니다.")
	
	await create_timer(0.5).timeout
	var gm = root.get_node("GameManager")
	_expect(gm.is_game_active, "게임이 활성 상태여야 합니다.")
	_expect(gm.current_turn_idx == 0, "1번째 턴은 플레이어 0(나)이어야 합니다.")
	_expect(hud_ctrl.center_dice_panel.visible and not hud_ctrl.center_dice_button.disabled, "내 턴에서는 중앙 주사위가 표시되고 클릭 가능해야 합니다.")
	
	var initial_pos = gm.players[0]["position"]
	print("[INFO] 플레이어 0 현재 위치: %d" % initial_pos)
	
	# 화면 중앙의 주사위 클릭!
	hud_ctrl.center_dice_button.emit_signal("pressed")
	await process_frame
	
	_expect(gm.current_state == gm.TurnState.ROLLING_DICE or gm.current_state == gm.TurnState.PLAYER_MOVING, "주사위 클릭 후 롤링 또는 이동 상태로 진입해야 합니다.")
	print("[STEP 4 PASS] 중앙 주사위 클릭 및 롤링 트리거 검증 완료")
	
	# 주사위 완료 및 이동 완료 대기
	await create_timer(2.0).timeout
	var moved_pos = gm.players[0]["position"]
	print("[INFO] 주사위 굴림 후 플레이어 0 위치: %d" % moved_pos)
	_expect(moved_pos > initial_pos, "플레이어가 주사위 눈금만큼 앞으로 이동해야 합니다.")
	
	# 5. 큰 건설 가이드 최하단 이동과 중복 수집현황 패널 삭제 검증
	_expect(hud_ctrl.guide_inventory_count_labels.size() == gm.ITEM_DEFINITIONS.size(), "최하단 건설 가이드에 모든 재료 개수가 표시되어야 합니다.")
	_expect(hud_ctrl.construction_guide_panel.position.y >= 574.0, "재료·시설 건설 가이드는 화면 맨 아래에 배치되어야 합니다.")
	_expect(game_board.get_node_or_null("UILayer/HUD/ActionDock") == null, "중복 건설재료 수집현황 패널은 삭제되어야 합니다.")
	print("[STEP 5 PASS] 건설 가이드 최하단 이동과 중복 패널 삭제 검증 완료")
	
	# 6. 로비 복귀 검증
	main_scene.switch_to_lobby()
	await process_frame
	await create_timer(0.3).timeout
	_expect(lobby.visible, "로비 복귀 후 로비 UI가 표시되어야 합니다.")
	_expect(not game_board.visible, "로비 복귀 후 게임 보드가 숨겨져야 합니다.")
	_expect(not game_board.ui_layer.visible, "로비 복귀 후 UILayer가 완전히 비활성화되어야 합니다.")
	print("[STEP 6 PASS] 로비 복귀 및 UI 레이어 완전 정리 검증 완료")

	print("========================================")
	if failures.is_empty():
		print("  >>> ALL CLICK TESTS PASSED (100%) <<<  ")
		print("========================================")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		print("========================================")
		quit(1)

func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("[FAIL] " + msg)
		print("[FAIL] " + msg)
