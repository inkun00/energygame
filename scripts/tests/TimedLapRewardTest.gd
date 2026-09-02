extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var lobby = main.get_node("LobbyUI")
	_expect(lobby.game_time_option_button.item_count == 4, "방 생성 화면에서 4가지 플레이 시간 프리셋을 선택할 수 있어야 합니다.")
	lobby.game_time_option_button.select(0)
	_expect(int(lobby.game_time_option_button.get_selected_metadata()) == 300, "첫 플레이 시간 프리셋은 5분이어야 합니다.")

	var configs: Array[Dictionary] = []
	for index in range(4):
		configs.append({"name": "완주 테스트 %d" % (index + 1), "is_ai": false})
	main._on_start_game_requested(configs, 300)
	await process_frame
	var game_manager: Node = root.get_node("GameManager")
	var hud = main.get_node("GameBoard/UILayer/HUD")
	_expect(game_manager.game_duration_seconds == 300, "선택한 5분이 실제 게임 세션에 적용되어야 합니다.")
	_expect(hud.game_time_label.text == "05:00", "HUD에 선택한 게임 시간이 표시되어야 합니다.")

	game_manager.players[0]["position"] = BoardGrid.LAST_TILE_INDEX
	game_manager._handle_lap_completion(0)
	_expect(int(game_manager.pending_lap_reward.get("rank", 0)) == 1 and int(game_manager.pending_lap_reward.get("remaining", 0)) == 3, "첫 완주자는 원하는 부품 3개를 선택할 수 있어야 합니다.")
	var reward_item_grid: Node = hud.lap_reward_panel.find_child("ItemGrid", true, false)
	_expect(hud.lap_reward_panel.visible and reward_item_grid != null and reward_item_grid.get_child_count() == game_manager.ITEM_DEFINITIONS.size(), "완주 보상 창에 모든 부품 선택지가 이미지 버튼으로 표시되어야 합니다.")
	var paused_time: float = game_manager.game_time_remaining
	game_manager._process(2.0)
	_expect(is_equal_approx(game_manager.game_time_remaining, paused_time), "완주 보상을 고르는 동안 플레이 시간이 줄어들면 안 됩니다.")
	hud._on_lap_reward_item_pressed("solar_panel")
	hud._on_lap_reward_item_pressed("solar_panel")
	hud._on_lap_reward_item_pressed("battery")
	_expect(game_manager.players[0]["inventory"]["solar_panel"] == 2 and game_manager.players[0]["inventory"]["battery"] == 1, "1등이 직접 고른 부품 3개가 개인 인벤토리에 지급되어야 합니다.")
	_expect(game_manager.players[0]["position"] == 0 and not hud.lap_reward_panel.visible, "보상 선택 후 출발 칸으로 돌아가고 보상 창이 닫혀야 합니다.")

	var expected_rewards := [2, 1, 0]
	for offset in range(3):
		var player_idx := offset + 1
		game_manager.players[player_idx]["position"] = BoardGrid.LAST_TILE_INDEX
		game_manager._handle_lap_completion(player_idx)
		var reward_count: int = expected_rewards[offset]
		if reward_count > 0:
			_expect(int(game_manager.pending_lap_reward.get("remaining", -1)) == reward_count, "%d등 완주 보상 수량이 올바르지 않습니다." % (player_idx + 1))
			for _selection in range(reward_count):
				game_manager.claim_lap_reward(player_idx, "wind_blade")
		_expect(game_manager.players[player_idx]["position"] == 0, "%d등도 보상 처리 후 출발 칸으로 돌아가야 합니다." % (player_idx + 1))
	_expect(game_manager.players[1]["inventory"]["wind_blade"] == 2, "2등은 원하는 부품 2개를 받아야 합니다.")
	_expect(game_manager.players[2]["inventory"]["wind_blade"] == 1, "3등은 원하는 부품 1개를 받아야 합니다.")
	_expect(game_manager.players[3]["lap_reward_items"] == 0, "4등은 완주 부품 보상이 없어야 합니다.")

	game_manager.game_time_remaining = 0.01
	game_manager._process(0.02)
	_expect(game_manager.village_construction_active and not game_manager.is_game_active, "설정 시간이 끝나면 보드 탐험을 멈추고 마을 건설 단계로 전환해야 합니다.")

	if failures.is_empty():
		print("[PASS] Timed multi-lap rewards and room duration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
